# /inspect

> @FAGAN inspects code · Fagan-style formal inspection (IBM 1976) on a diff or files. Multimodel by default.

Alias for `/fagan`. Verb-form — anchored to "Fagan inspection" as the technique name. Same construct, same backend, same output:

- **Default**: 3-voice multimodel panel (opus-skeptic + gpt-reviewer + composer-reviewer) via `scripts/fagan-panel.sh`
- **`--mode fast`**: legacy single-model GPT-5.5 via `scripts/codex-review-api.sh`

## Usage

```
/inspect                            # current branch's diff vs main — multimodel
/inspect --pr 157                   # specific PR
/inspect --diff /tmp/changes.diff   # arbitrary diff
/inspect --files src/auth.ts        # specific files
/inspect --mode fast                # single-model legacy path
```

## See also

- `/fagan` — primary persona-handle alias (same skill, full docs)
- `/reviewing-diffs` — underlying skill name
- [`WHEN-TO-USE.md`](../WHEN-TO-USE.md) — when to reach for this vs other reviewers
