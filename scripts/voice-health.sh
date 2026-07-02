#!/usr/bin/env bash
# voice-health.sh — PROACTIVE liveness probe for the council's cross-model voices.
#
# The reactive half of the immune system (cheval-council.sh's degraded-panel
# warning + voice-utilization.mjs) catches a dead voice AFTER a review drops it.
# This catches it BEFORE: a trivial probe through cheval per voice, so a dead
# model pin (e.g. claude-headless `cli_model: fable` → "Claude Fable 5 is
# currently unavailable", or gemini-headless → IneligibleTier) fails LOUD at a
# health check instead of silently halving every council / BB / flatline review.
#
# Routes through cheval (NOT the raw CLIs) on purpose — so it exercises the
# CONFIGURED pin and catches config-level death (a dead cli_model), not just a
# missing binary. Proof-of-life is verify-by-dispatch: a voice is alive only if
# a real provider returned content.
#
# Usage: voice-health.sh [--voices a,b,c] [--cheval <path/to/cheval.py>] [--json]
#   --voices   comma list (default: the council's claude+gpt+cursor, or
#              $FAGAN_PANEL_VOICES_CHEVAL)
#   --cheval   path to cheval.py (default: walk up from $PWD to find
#              .claude/adapters/cheval.py, like cheval-council.sh)
#   --json     emit a machine envelope instead of the human table
# Exit: 0 all probed voices alive · 1 one or more DEAD (fail-loud) · 2 input error
set -uo pipefail

err() { printf '[voice-health] %s\n' "$*" >&2; }

VOICES="${FAGAN_PANEL_VOICES_CHEVAL:-jam-reviewer-claude-headless,jam-reviewer-gpt,jam-reviewer-cursor}"
CHEVAL=""
JSON=0
# Probe with the SAME routing + timeout the council will use (council#11 self-review,
# E/F): force the headless terminal only when the council would (FORCE_HEADLESS=1), and
# use the council's timeout — else a slow-but-healthy voice (>90s) or a different route
# gets mis-flagged pre-flight versus the real dispatch.
TIMEOUT_S="${VOICE_HEALTH_TIMEOUT:-90}"
FORCE_HEADLESS="${CHEVAL_COUNCIL_FORCE_HEADLESS:-1}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --voices)         VOICES="${2:-}"; shift 2 ;;
    --cheval)         CHEVAL="${2:-}"; shift 2 ;;
    --timeout)        TIMEOUT_S="${2:-90}"; shift 2 ;;
    --force-headless) FORCE_HEADLESS="${2:-1}"; shift 2 ;;
    --json)           JSON=1; shift ;;
    -h|--help) err "usage: voice-health.sh [--voices a,b,c] [--cheval <path>] [--timeout <s>] [--force-headless 0|1] [--json]"; exit 2 ;;
    *) err "unknown arg: $1"; exit 2 ;;
  esac
done

# Resolve cheval.py — explicit --cheval, else walk up from $PWD (council pattern).
if [[ -z "$CHEVAL" ]]; then
  d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.claude/adapters/cheval.py" ]]; then CHEVAL="$d/.claude/adapters/cheval.py"; break; fi
    d="$(dirname "$d")"
  done
fi
[[ -n "$CHEVAL" && -f "$CHEVAL" ]] || { err "cheval.py not found — pass --cheval <path/to/.claude/adapters/cheval.py>"; exit 2; }
# Canonicalize (symlink-resolved absolute) so the cd-into-root dispatch is stable
# — same discipline as cheval-council.sh (the cwd-tension fix, #11).
CHEVAL="$(cd "$(dirname "$CHEVAL")" && pwd -P)/$(basename "$CHEVAL")"
CHEVAL_ROOT="$(cd "$(dirname "$CHEVAL")/../.." 2>/dev/null && pwd -P)"
[[ -n "$CHEVAL_ROOT" && -f "$CHEVAL_ROOT/.claude/adapters/cheval.py" ]] || { err "could not resolve cheval root from $CHEVAL"; exit 2; }

# voice → within-company headless terminal. Mirrors cheval-council.sh's
# headless_model_for_voice() so the probe tests EXACTLY what the council dispatches.
headless_model_for_voice() {
  case "$1" in
    *fable*)                               echo "anthropic:claude-fable-headless" ;;
    *cursor*)                              echo "cursor:cursor-headless" ;;
    *gemini*|*deep-thinker*|*gem-*)        echo "google:gemini-headless" ;;
    *claude*|*anthropic*|*opus*|*sonnet*)  echo "anthropic:claude-headless" ;;
    *gpt*|*codex*|*openai*|*reviewer*)     echo "openai:codex-headless" ;;
    *)                                     echo "openai:codex-headless" ;;
  esac
}

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/probe.txt"; printf 'Reply with exactly the word ALIVE.' >"$PROBE"
SYS="$WORK/sys.txt";     printf 'You are a liveness probe. Reply with exactly the word ALIVE and nothing else.' >"$SYS"

results="[]"; alive=0; dead=0
IFS=',' read -ra VLIST <<<"$VOICES"
for raw in ${VLIST[@]+"${VLIST[@]}"}; do
  voice="$(printf '%s' "$raw" | xargs)"   # trim whitespace
  [[ -z "$voice" ]] && continue
  model="$(headless_model_for_voice "$voice")"
  # E: force the headless terminal ONLY when the council would (FORCE_HEADLESS=1);
  # otherwise probe the voice's default chain — the exact path the real dispatch takes.
  model_flag=()
  if [[ "$FORCE_HEADLESS" -eq 1 ]]; then model_flag=(--model "$model"); route="$model"; else route="$voice default-chain"; fi
  err "probing $voice → $route (timeout ${TIMEOUT_S}s) …"
  out="$( ( cd "$CHEVAL_ROOT" && timeout "$TIMEOUT_S" python3 "$CHEVAL" --agent "$voice" ${model_flag[@]+"${model_flag[@]}"} --input "$PROBE" --system "$SYS" --output-format json ) 2>"$WORK/err" )" || true
  content="$(jq -r 'if (.error // false) then "" else (.content // "") end' <<<"$out" 2>/dev/null || echo "")"
  if [[ -n "$content" && "$content" != "null" ]]; then
    state="alive"; alive=$((alive + 1)); reason=""
    model_ran="$(jq -r '.final_model_id // .model_invoked // .model // "?"' <<<"$out" 2>/dev/null || echo "?")"
  else
    state="dead"; dead=$((dead + 1)); model_ran=""
    reason="$(jq -r '(.message // .code // empty)' <<<"$out" 2>/dev/null | tr '\n' ' ' | head -c 220)"
    if [[ -z "$reason" ]]; then
      # Pull the MEANINGFUL failure from stderr — skip the (non-fatal) persona /
      # no-system-prompt warnings that every jam-reviewer agent emits, and surface
      # the real death cause (provider-unavailable, dead model pin, ineligible tier).
      reason="$(grep -aoiE 'PROVIDER_UNAVAILABLE[^"]*|currently unavailable[^"]*|IneligibleTier[^"]*|RETRIES_EXHAUSTED[^"]*|not (set|configured|authenticated)[^"]*' "$WORK/err" 2>/dev/null | tail -1 | tr '\n' ' ' | head -c 220)"
      [[ -z "$reason" ]] && reason="$(grep -aviE 'persona|no system prompt' "$WORK/err" 2>/dev/null | grep -aE '.' | tail -1 | tr '\n' ' ' | head -c 220)"
      [[ -z "$reason" ]] && reason="no content returned"
    fi
  fi
  results="$(jq -c --arg v "$voice" --arg m "$model" --arg s "$state" --arg mr "$model_ran" --arg r "$reason" \
    '. + [{voice:$v, model:$m, state:$s, model_ran:$mr, reason:$r}]' <<<"$results")"
  err "  → $state${model_ran:+ ($model_ran)}${reason:+ — $reason}"
done

ntotal=$((alive + dead))
summary="voice-health · $alive/$ntotal alive, $dead DEAD"
if [[ "$JSON" -eq 1 ]]; then
  jq -nc --arg s "$summary" --argjson a "$alive" --argjson d "$dead" --argjson v "$results" \
    '{summary:$s, alive:$a, dead:$d, all_alive:($d==0), voices:$v}'
else
  err "$summary"
  jq -r '.[] | "  [\(.state|ascii_upcase)] \(.voice) → \(.model)" + (if .model_ran!="" then " (\(.model_ran))" else "" end) + (if .reason!="" then "  — \(.reason)" else "" end)' <<<"$results"
fi
[[ "$dead" -eq 0 ]] && exit 0 || exit 1
