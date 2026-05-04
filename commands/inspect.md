# /inspect

> @FAGAN inspects code · Fagan-style formal inspection (IBM 1976) on a diff or files.

Alias for `/fagan`. Verb-form — anchored to "Fagan inspection" as the technique name. Same construct, same backend, same output.

## Usage

```
/inspect                            # current branch's diff vs main
/inspect --pr 157                   # specific PR
/inspect --diff /tmp/changes.diff   # arbitrary diff
/inspect --files src/auth.ts        # specific files
```

## See also

- `/fagan` — primary persona-handle alias (same skill)
- `/reviewing-diffs` — underlying skill name
- [`WHEN-TO-USE.md`](../WHEN-TO-USE.md) — when to reach for this vs other reviewers
