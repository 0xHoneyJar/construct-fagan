# Vendored libraries

These files are vendored from
[loa-constructs](https://github.com/0xHoneyJar/loa-constructs) at commit
`df1c0304` (tag `v2.35.0`). Do not edit in place — propose upstream changes
via PR to loa-constructs first, then re-vendor.

| File | Source | Pin | Adaptations |
|---|---|---|---|
| `scripts/lib/lib-codex-exec.sh` | `loa-constructs/.claude/scripts/lib-codex-exec.sh` | `df1c0304` | None — already portable |
| `scripts/lib/lib-security.sh` | `loa-constructs/.claude/scripts/lib-security.sh` | `df1c0304` | Config key renamed `flatline_protocol.secret_scanning.patterns` → `codex_review.secret_patterns`. Log prefix rebranded `[gpt-review-security]` → `[codex-review-security]`. |
| `scripts/lib/lib-content.sh` | `loa-constructs/.claude/scripts/lib-content.sh` | `df1c0304` | None — already portable |

## Why vendor instead of source?

- **Portability**: this construct must work standalone, not require loa-constructs to be cloned alongside it.
- **Stability**: pin to a known-good commit, lift on a deliberate cadence rather than absorbing every upstream change.
- **Auditability**: the construct's provenance is visible in this file.

## Re-vendor procedure

```bash
PIN=<new-loa-constructs-commit-sha>
cd ~/Documents/GitHub/loa-constructs && git fetch origin && git checkout "$PIN"
cd ~/Documents/GitHub/construct-codex-review

cp ~/Documents/GitHub/loa-constructs/.claude/scripts/lib-codex-exec.sh scripts/lib/lib-codex-exec.sh
cp ~/Documents/GitHub/loa-constructs/.claude/scripts/lib-content.sh   scripts/lib/lib-content.sh
cp ~/Documents/GitHub/loa-constructs/.claude/scripts/lib-security.sh  scripts/lib/lib-security.sh

# Re-apply lib-security.sh adaptations
sed -i '' 's|flatline_protocol\.secret_scanning\.patterns|codex_review.secret_patterns|g' scripts/lib/lib-security.sh
sed -i '' 's|\[gpt-review-security\]|[codex-review-security]|g' scripts/lib/lib-security.sh

# Update the pin in this file + commit
```

## Upstream change policy

If you need behavior the vendored libs don't provide:

1. **First**: open a PR against `0xHoneyJar/loa-constructs` with the change.
2. **After it merges**: re-vendor at the new pin.
3. **Never**: edit the vendored copy directly except for the documented adaptations above.

The exception is the documented adaptations table — those are decoupling
adaptations that don't make sense to push upstream (e.g. config key rename
from a bonfire-coupled name).
