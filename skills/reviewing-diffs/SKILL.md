---
name: reviewing-diffs
description: Adversarial code review of a unified diff via a CROSS-MODEL council (4 distinct model families) by default, single-pass codex CLI as fallback. Returns structured JSON findings with line-anchored fixes.
allowed-tools: [Bash, Read]
user-invocable: true
---

# /reviewing-diffs — Diff Code Review

Adversarial code review of a unified diff. **Default: cross-model council** — four
DISTINCT model families (claude / gpt-codex / cursor-composer / gemini) review the
same diff so no single corpus's blind spot decides the verdict. **Fallback:**
single-pass GPT review via the codex CLI.

The dispatcher is `scripts/fagan-review.sh`; mode is selected by `FAGAN_REVIEW_MODE`
(`council` default, `single` fallback). Council output carries a per-voice MODELINV
audit (`.run/model-invoke.jsonl`) + a `panel:{voices,dropped,models_ran}` block;
single-pass output conforms to `schemas/codex-review-finding.schema.json`.

## Inputs

| Input | Required | Description |
|---|---|---|
| `diff_path` | yes | Path to a unified diff file (or `-` for stdin) |
| `iteration` | no (default 1) | Convergence loop iteration; ≥2 triggers re-review prompt |
| `previous_findings` | when iteration ≥ 2 | Path to prior verdict JSON (the previous review's response) |

## Invocation

```bash
# DEFAULT — cross-model 4-voice council (claude + gpt-codex + cursor + gemini)
bash scripts/fagan-review.sh path/to/changes.diff

# Council with an explicit cheval + voice set (e.g. for testing / pinned routing)
bash scripts/fagan-review.sh path/to/changes.diff \
  --voices jam-reviewer-claude,jam-reviewer-gpt,jam-reviewer-cursor,deep-thinker \
  --cheval /abs/path/to/.claude/adapters/cheval.py

# FALLBACK — single-pass GPT review (one model, no audit envelope)
FAGAN_REVIEW_MODE=single bash scripts/fagan-review.sh path/to/changes.diff

# Re-review (iteration 2+, single-pass only) — must supply previous findings
FAGAN_REVIEW_MODE=single bash scripts/fagan-review.sh path/to/changes.diff \
  --iteration 2 \
  --previous .run/codex-review/iter-1.json

# The single-pass backend is also callable directly (the dispatcher just wraps it):
#   bash scripts/codex-review-api.sh review-diff path/to/changes.diff
```

### Review modes

| `FAGAN_REVIEW_MODE` | Backend | Models | Audit envelope | When |
|---|---|---|---|---|
| `council` (default) | `scripts/cheval-council.sh` | 4 distinct families | per-voice MODELINV | genuine cross-model SWE review |
| `single` | `scripts/codex-review-api.sh` | one GPT pass | none | fast single-opinion check; council unavailable |

**Default voices** (`FAGAN_PANEL_VOICES_CHEVAL` to override) bind to subscription
HEADLESS terminals — no API quota dependency:

| Voice | Headless terminal (model family) |
|---|---|
| `jam-reviewer-claude` | `anthropic:claude-headless` |
| `jam-reviewer-gpt` | `openai:codex-headless` |
| `jam-reviewer-cursor` | `cursor:cursor-headless` (Composer 2.5) |
| `deep-thinker` | `google:gemini-headless` |

**Fallback behavior:** in `council` mode, if the council cannot RUN (cheval.py
absent / bad input → exit 2) the dispatcher falls back to single-pass. It does
NOT fall back on a council exit 3 (**all-voices-dropped — the load-bearing
fail-closed verdict**), which propagates so a degraded council can never be
silently downgraded to a single-model APPROVED. Set
`FAGAN_REVIEW_COUNCIL_FALLBACK=0` to make a council infra-failure hard-fail.

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
