# /fagan

> @FAGAN reviews a code diff. Strict, evidence-anchored, fix-first.

Calls the `reviewing-diffs` skill from the FAGAN construct (formerly construct-codex-review). Single GPT-5.5 pass via codex CLI · structured JSON findings · 3-iteration convergence cap.

## Usage

```
/fagan                              # current branch's diff vs main
/fagan --pr 157                     # specific PR (pulls diff via gh)
/fagan --diff /tmp/changes.diff     # arbitrary diff file
/fagan --files src/auth.ts          # specific files
```

## Persona embodiment

Equivalent to saying `@FAGAN review this`. Loads `identity/persona.yaml` + `resources/patterns.md` (the 17 patterned-finding shapes).

## When to use

See [`WHEN-TO-USE.md`](../WHEN-TO-USE.md) — short version:
- ✅ "I just wrote 50 lines, sanity-check it"
- ✅ "Did I introduce a bug in this auth code"
- ✅ Cross-model dissent gate AFTER `/bridgebuilder-review`
- ❌ Confirmed bug with repro → use `/bug` (formal triage)
- ❌ 1000-line PR review → use `/bridgebuilder-review` (multi-pass enrichment)
- ❌ Design/PRD review → use `/flatline-review`

## Output

JSON conforming to `schemas/codex-review-finding.schema.json`:
- `verdict`: APPROVED | CHANGES_REQUIRED
- `summary`: one-sentence assessment
- `findings[]`: `severity` (critical | major), `file`, `line`, `current_code`, `fixed_code`, `explanation`
- exit code: 0 = APPROVED · 1 = CHANGES_REQUIRED

## See also

- `/inspect` — alias to /fagan (verb-form)
- `/reviewing-diffs` — the underlying skill (longer name)
- `/bridgebuilder-review` — the heavier PR-level review
