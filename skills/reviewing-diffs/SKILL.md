---
name: reviewing-diffs
description: Adversarial code review of a unified diff via codex CLI. Returns structured JSON findings with line-anchored fixes. Convergence loop with 3-iteration cap.
allowed-tools: [Bash, Read]
user-invocable: true
---

# /reviewing-diffs — Diff Code Review

Single-pass GPT code review of a unified diff. Returns structured JSON conforming to `schemas/codex-review-finding.schema.json`.

## Inputs

| Input | Required | Description |
|---|---|---|
| `diff_path` | yes | Path to a unified diff file (or `-` for stdin) |
| `mode` | no (default `fast`) | `fast` = single-model (gpt-5.5 via codex). `thorough` = multimodel PANEL (Opus + GPT + Composer). |
| `iteration` | no (default 1) | Convergence loop iteration; ≥2 triggers re-review prompt (fast mode) |
| `previous_findings` | when iteration ≥ 2 | Path to prior verdict JSON (the previous review's response) |

## Invocation

```bash
# FAST (default) — single-model, per-diff, cheap
bash scripts/codex-review-api.sh review-diff path/to/changes.diff

# Re-review (iteration 2+) — must supply previous findings
bash scripts/codex-review-api.sh review-diff path/to/changes.diff \
  --iteration 2 \
  --previous .run/codex-review/iter-1.json

# THOROUGH — multimodel PANEL (3 voices, distinct corpora). For TEND passes /
# pre-merge gates. Emits the same finding schema + a `panel` block (per-voice
# verdicts, who-caught-what, models_ran, dropped voices, lone_blocking_flags).
bash scripts/fagan-panel.sh review-diff path/to/changes.diff
```

## Modes

`mode: thorough` routes to `fagan-panel.sh` instead of the single-model path. The
panel fans the diff out to voices from DISTINCT base corpora so reviews fail
differently — a lone critical from any voice HOLDS the gate (never out-voted), and
disagreement is surfaced (`panel.lone_blocking_flags`), not averaged away.

- **Voice roster** is operator-tunable via the `fagan_protocol.voices` block in
  `.loa.config.yaml` (exported as `FAGAN_PANEL_VOICES="id:role:adapter:model,…"`),
  or the built-in default `opus(skeptic)/claude + gpt-5.5(reviewer)/codex +
  composer-2.5(reviewer)/cursor`.
- **Requirements:** claude CLI (OAuth subscription), codex CLI (`~/.codex/auth.json`),
  cursor-agent (Cursor **Pro** — free tier returns `resource_exhausted`). Any voice
  whose CLI/auth is unavailable is DROPPED (honest headcount), never substituted.
- **Default stays `fast`** — thorough is opt-in (slower; one metered Composer call).

## Output

JSON conforming to `schemas/codex-review-finding.schema.json`:

- `verdict`: `APPROVED` | `CHANGES_REQUIRED`
- `summary`: one-sentence assessment
- `findings[]`: each with `severity`, `file`, `line`, `description`, `current_code`, `fixed_code`, `explanation`
- `fabrication_check`: `passed` + `concerns[]`
- `previous_issues_status[]`: per-issue status on re-review
- `iteration`, `auto_approved`, `note`: meta

Exit codes map to verdict: `0=APPROVED`, `1=CHANGES_REQUIRED`, `2=input_err`, `3=api_failure`, `4=auth`, `5=format_err`.

## When to use

- After an implementer (codex-rescue, codex CLI implementer, etc.) ships a diff
- Inside the `code-implement-and-review` composition (stage 2)
- Standalone: operator wants a single review pass on a PR diff before merge

## When NOT to use

- For PRD/SDD/Sprint planning review — use **Flatline Protocol**
- For style / lint feedback — use the project's linter
- For UI/UX feel — use **artisan**
- For architecture audits — use **audit-* compositions**

## Persona

This skill embodies **FAGAN** — strict code reviewer in the Fagan tradition (formal code inspection, IBM 1976). Line-anchored, evidence-based, fix-first. Severity is binary: `critical` or `major`. Style and "could be cleaner" suggestions are explicitly forbidden.

## Convergence

- Iteration cap: `CODEX_REVIEW_MAX_ITERATIONS` (default 3).
- Past the cap, the API auto-approves at the wrapper level (no model invocation), returning `auto_approved: true` with `note: "iteration-cap-reached"`.
- The re-review prompt enforces: "VERIFY. DON'T REINVENT. CONVERGE."
