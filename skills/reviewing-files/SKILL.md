---
name: reviewing-files
description: Adversarial code review of specific files (no diff context) via codex CLI. Use for module-scoped audits without a PR. Returns same JSON shape as reviewing-diffs.
allowed-tools: [Bash, Read]
user-invocable: true
---

# /reviewing-files — File Code Review

Same persona and output shape as `/reviewing-diffs`, but takes one or more file paths instead of a unified diff. Use when there is no diff context to review (e.g., "audit `src/auth.ts` before we ship").

## Inputs

| Input | Required | Description |
|---|---|---|
| `files` | yes (≥ 1) | One or more file paths to review |
| `iteration` | no (default 1) | Convergence loop iteration |
| `previous_findings` | when iteration ≥ 2 | Path to prior verdict JSON |

## Invocation

```bash
bash scripts/codex-review-api.sh review-files src/auth.ts src/session.ts
```

## Output

Same JSON shape as `/reviewing-diffs` — see `schemas/codex-review-finding.schema.json`.

Note: without a diff context, the reviewer evaluates the file as-is. There is no "what changed" anchor, so findings tend to focus on bugs and security issues rather than evolution-of-code concerns.

## When to use

- Pre-merge audit of a specific module
- "Audit this file before we ship" requests
- Verifying a refactor that wasn't captured as a single diff
- Standalone module review when no PR / diff exists

## When NOT to use

- When you have a diff — use `/reviewing-diffs` for tighter signal
- For whole-repo audits — too broad; scope down or use a multi-pass composition
- For everything in the `/reviewing-diffs` "When NOT to use" list (Flatline / artisan / audit-* are still the right tools for their territories)

## Persona

Same as `/reviewing-diffs` — **FAGAN**, strict code reviewer.
