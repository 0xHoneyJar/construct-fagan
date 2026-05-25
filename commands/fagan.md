# /fagan

> @FAGAN reviews a code diff. Strict, evidence-anchored, fix-first. **Multimodel by default** — 3 voices from distinct base corpora reach consensus or surface dissent.

Calls the `reviewing-diffs` skill from the FAGAN construct in **thorough mode** by default: routes through `scripts/fagan-panel.sh`, fanning the diff out to:

- `opus-skeptic` — Claude Opus in the **skeptic** seat (Anthropic, via `claude` CLI)
- `gpt-reviewer` — GPT-5.5 in the **reviewer** seat (OpenAI, via `codex` CLI)
- `composer-reviewer` — Composer 2.5 in the **reviewer** seat (Cursor, via `cursor-agent`)

Distinct corpora fail differently. A lone critical from any voice HOLDS the gate (never out-voted). Consensus findings (≥2 voices) earn `tier: consensus`; lone findings surface as `panel.lone_blocking_flags`. Unavailable adapters DROP (honest headcount), never substitute — `panel.dropped[]` records which voices fell out.

## Usage

```
/fagan                              # current branch's diff vs main — multimodel
/fagan --pr 157                     # specific PR (pulls diff via gh)
/fagan --diff /tmp/changes.diff     # arbitrary diff file
/fagan --files src/auth.ts          # specific files
/fagan --mode fast                  # single-model (GPT-5.5 via codex) — legacy fast path
```

## Persona embodiment

Equivalent to saying `@FAGAN review this`. Loads `identity/persona.yaml` + `resources/patterns.md` (the 17 patterned-finding shapes). Each voice in the panel receives the persona seat-fit prompt (`prompts/code-review.md` for reviewers · `prompts/skeptic-review.md` for skeptics).

## When to use

See [`WHEN-TO-USE.md`](../WHEN-TO-USE.md) — short version:

- ✅ "I just wrote 50 lines, sanity-check it"
- ✅ "Did I introduce a bug in this auth code"
- ✅ Cross-model dissent gate AFTER `/bridgebuilder-review`
- ❌ Confirmed bug with repro → use `/bug` (formal triage)
- ❌ 1000-line PR review → use `/bridgebuilder-review` (multi-pass enrichment)
- ❌ Design/PRD review → use `/flatline-review`

## Output

JSON conforming to `schemas/codex-review-finding.schema.json`, with panel extensions:

- `verdict`: `APPROVED` | `CHANGES_REQUIRED`
- `summary`: e.g. `"3 voices · 5 findings (2 consensus, 3 lone) · 2 blocking"`
- `findings[]` — each finding includes:
  - `severity` (`critical` | `major` | `cleanup`), `file`, `line`
  - `current_code`, `fixed_code`, `explanation`
  - `voices[]`, `roles[]`, `consensus_count`, `tier` (`consensus` | `lone`)
- `panel` (panel mode only):
  - `voices[]`: per-voice `verdict`, `model_requested`, `model_ran`, `finding_count`
  - `dropped[]`: voice ids whose adapter/auth was unavailable
  - `models_ran[]`: confirmed served-model identities (for MODELINV audit)
  - `lone_blocking_flags[]`: lone-voice criticals/majors holding the gate

**Exit codes**: `0` = APPROVED · `1` = CHANGES_REQUIRED · `2` = input error · `3` = all voices dropped · `5` = format error.

## Requirements (multimodel default)

- `claude` CLI — OAuth subscription (opus-skeptic voice)
- `codex` CLI — `~/.codex/auth.json` (gpt-reviewer voice)
- `cursor-agent` — Cursor **Pro** subscription (composer-reviewer voice; free tier returns `resource_exhausted` and the voice DROPS)
- `jq`

Any voice whose CLI/auth is unavailable is dropped from the headcount — the panel runs at whatever width is currently live (2-voice if Cursor missing, 1-voice if only one available). When **all** voices drop, the panel fails CLOSED (`verdict: CHANGES_REQUIRED`, exit 3, `error: all_voices_dropped`). Use `--mode fast` for the legacy single-GPT path when you specifically want a cheap one-pass review.

## Configuration

Voice roster is operator-tunable via the `fagan_protocol.voices` block in `.loa.config.yaml` (exported as `FAGAN_PANEL_VOICES="id:role:adapter:model,…"`). Built-in default roster:

```
opus-skeptic:skeptic:claude:opus,gpt-reviewer:reviewer:codex:gpt-5.5,composer-reviewer:reviewer:cursor:composer-2.5
```

| Env var | Default | Effect |
|---|---|---|
| `FAGAN_PANEL_TIMEOUT` | `300` | Per-voice timeout (seconds) |
| `FAGAN_PANEL_MAX_TOKENS` | `30000` | Diff truncation threshold |
| `FAGAN_PANEL_VOICES` | (default roster above) | `id:role:adapter:model[,…]` |

## See also

- `/inspect` — alias to /fagan (verb-form)
- `/reviewing-diffs` — the underlying skill (longer name; honors `mode: fast|thorough`)
- `/bridgebuilder-review` — the heavier PR-level review
- `scripts/fagan-panel.sh` — the multimodel panel runner
- `scripts/codex-review-api.sh` — the single-model fast path
