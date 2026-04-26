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
| `iteration` | no (default 1) | Convergence loop iteration; ≥2 triggers re-review prompt |
| `previous_findings` | when iteration ≥ 2 | Path to prior verdict JSON (the previous review's response) |

## Invocation

```bash
# First review
bash scripts/codex-review-api.sh review-diff path/to/changes.diff

# Re-review (iteration 2+) — must supply previous findings
bash scripts/codex-review-api.sh review-diff path/to/changes.diff \
  --iteration 2 \
  --previous .run/codex-review/iter-1.json
```

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
