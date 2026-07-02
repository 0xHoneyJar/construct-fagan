#!/usr/bin/env bash
# voice-health.test.sh — verifies voice-health.sh's classification + fail-loud exit
# against a MOCK cheval (no real model dispatch). Run: bash scripts/voice-health.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SUT="$HERE/voice-health.sh"
pass=0; fail=0
check() { # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fi
}

# --- a temp cheval root with a MOCK cheval.py ----------------------------------
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/.claude/adapters"
cat >"$ROOT/.claude/adapters/cheval.py" <<'PYEOF'
import sys, json
# Mock cheval: a model containing "anthropic" is DEAD (simulating the dead
# fable pin); everything else returns content (ALIVE).
model = ""
a = sys.argv[1:]
for i, x in enumerate(a):
    if x == "--model" and i + 1 < len(a):
        model = a[i + 1]
if "anthropic" in model:
    print(json.dumps({"error": True, "code": "RETRIES_EXHAUSTED",
                      "message": "PROVIDER_UNAVAILABLE: claude -p failed: Claude Fable 5 is currently unavailable"}))
    sys.exit(1)
print(json.dumps({"content": "ALIVE", "final_model_id": model.split(":")[-1]}))
PYEOF

MOCK="$ROOT/.claude/adapters/cheval.py"

# --- run: default-shape voices (claude dead, gpt+cursor alive) ------------------
out="$(bash "$SUT" --cheval "$MOCK" --json 2>/dev/null)"; rc=$?

check "fail-loud exit when a voice is dead" "1" "$rc"
check "alive count"  "2" "$(jq -r '.alive' <<<"$out")"
check "dead count"   "1" "$(jq -r '.dead'  <<<"$out")"
check "all_alive flag is false" "false" "$(jq -r '.all_alive' <<<"$out")"
check "claude classified dead" "dead" "$(jq -r '.voices[]|select(.voice|test("claude"))|.state' <<<"$out")"
check "dead reason surfaces the real cause (not a persona warning)" "true" \
  "$(jq -r '.voices[]|select(.voice|test("claude"))|.reason|test("unavailable")' <<<"$out")"
check "cursor classified alive" "alive" "$(jq -r '.voices[]|select(.voice|test("cursor"))|.state' <<<"$out")"

# --- run: all-alive set → exit 0 ----------------------------------------------
out2="$(bash "$SUT" --cheval "$MOCK" --voices "jam-reviewer-gpt,jam-reviewer-cursor" --json 2>/dev/null)"; rc2=$?
check "exit 0 when all voices alive" "0" "$rc2"
check "all_alive flag is true" "true" "$(jq -r '.all_alive' <<<"$out2")"

# --- E (council#11 self-audit): --force-headless toggles whether --model is forced, so
#     the probe mirrors the council's routing. The mock marks DEAD only when --model holds
#     "anthropic"; with --force-headless 0 no --model is passed → the claude voice reads
#     ALIVE (not force-routed to the dead pin); with 1 it is forced DEAD. ---
out3="$(bash "$SUT" --cheval "$MOCK" --voices "jam-reviewer-claude-headless" --force-headless 0 --json 2>/dev/null)"
check "E: --force-headless 0 omits --model (claude not forced to dead pin → alive)" "alive" \
  "$(jq -r '.voices[]|select(.voice|test("claude"))|.state' <<<"$out3")"
out4="$(bash "$SUT" --cheval "$MOCK" --voices "jam-reviewer-claude-headless" --force-headless 1 --json 2>/dev/null)"
check "E: --force-headless 1 forces --model (claude → dead anthropic pin)" "dead" \
  "$(jq -r '.voices[]|select(.voice|test("claude"))|.state' <<<"$out4")"

# --- F: --timeout is accepted and the probe still completes ---
out5="$(bash "$SUT" --cheval "$MOCK" --voices "jam-reviewer-gpt" --timeout 30 --json 2>/dev/null)"
check "F: --timeout accepted, probe completes (gpt alive)" "alive" \
  "$(jq -r '.voices[]|select(.voice|test("gpt"))|.state' <<<"$out5")"

echo "voice-health.test: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
