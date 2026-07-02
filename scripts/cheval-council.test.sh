#!/usr/bin/env bash
# cheval-council.test.sh — verifies the COUNCIL's own aggregation logic against a MOCK
# cheval (no real model dispatch): the APPROVED/CHANGES_REQUIRED roll-up, the synth-on-
# empty-block honesty fix (a block must carry a reason; tagged synthesized:true, #11/H),
# and the degraded-panel 2-family floor (multi_perspective_met).
#
# The verification instrument, verified — the operator's "the instruments check the agent"
# applied to the council itself. The mock returns {content:"<review-json>"}; the council
# extracts the first JSON object as the voice's {verdict,findings}.
# Run: bash scripts/cheval-council.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SUT="$HERE/cheval-council.sh"
pass=0; fail=0
check() { # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fi
}

# --- a temp cheval root with a MOCK cheval.py keyed off --agent (the voice name) -------
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/.claude/adapters"
cat >"$ROOT/.claude/adapters/cheval.py" <<'PYEOF'
import sys, json
a = sys.argv[1:]; agent = ""
for i, x in enumerate(a):
    if x == "--agent" and i + 1 < len(a):
        agent = a[i + 1]
# A voice whose name contains "dead" simulates a dropped voice (provider-unavailable).
if "dead" in agent:
    print(json.dumps({"error": True, "code": "PROVIDER_UNAVAILABLE", "message": "mock dead voice"}))
    sys.exit(1)
# "emptyblock" → CHANGES_REQUIRED with NO structured findings (tests the synth/H path).
if "emptyblock" in agent:
    review = {"verdict": "CHANGES_REQUIRED", "findings": []}
elif "block" in agent:
    review = {"verdict": "CHANGES_REQUIRED", "findings": [{"severity": "major", "title": "a real finding"}]}
else:
    review = {"verdict": "APPROVED", "findings": []}
# cheval wraps the model's review text in {content: ...}; the council extracts the JSON.
print(json.dumps({"content": json.dumps(review)}))
PYEOF
MOCK="$ROOT/.claude/adapters/cheval.py"
DIFF="$ROOT/diff.txt"; printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n' >"$DIFF"

# 1. all-approve → APPROVED, full panel, floor met -----------------------------------
o1="$(bash "$SUT" "$DIFF" --cheval "$MOCK" --voices "approve-1,approve-2,approve-3" 2>/dev/null)"
check "all-approve → verdict APPROVED"           "APPROVED" "$(jq -r '.verdict' <<<"$o1")"
check "all-approve → 3 voices survived"          "3"        "$(jq -r '.panel.voices_survived' <<<"$o1")"
check "all-approve → multi_perspective_met true" "true"     "$(jq -r '.panel.multi_perspective_met' <<<"$o1")"

# 2. one REAL block → CHANGES_REQUIRED -------------------------------------------------
o2="$(bash "$SUT" "$DIFF" --cheval "$MOCK" --voices "approve-1,block-1,approve-2" 2>/dev/null)"
check "one real block → verdict CHANGES_REQUIRED" "CHANGES_REQUIRED" "$(jq -r '.verdict' <<<"$o2")"

# 3. EMPTY block → a block must carry a reason: synth finding tagged synthesized:true (H)
o3="$(bash "$SUT" "$DIFF" --cheval "$MOCK" --voices "approve-1,emptyblock-1" 2>/dev/null)"
check "empty-block → still CHANGES_REQUIRED"      "CHANGES_REQUIRED" "$(jq -r '.verdict' <<<"$o3")"
check "empty-block → synthesized finding present" "true" \
  "$(jq -r '[.panel.voices[].findings[]? | select(.synthesized == true)] | length > 0' <<<"$o3")"

# 4. DEGRADED panel: only 1 alive → floor NOT met (the cross-model guarantee surfaces) -
o4="$(bash "$SUT" "$DIFF" --cheval "$MOCK" --voices "approve-1,dead-1,dead-2" 2>/dev/null)"
check "degraded (1 alive) → 1 survived"               "1"     "$(jq -r '.panel.voices_survived' <<<"$o4")"
check "degraded (1 alive) → multi_perspective_met FALSE" "false" "$(jq -r '.panel.multi_perspective_met' <<<"$o4")"

# 5. PREFLIGHT all-dead → refuse EARLY (before dispatch) with the actionable error (#8/D).
#    The real voice-health probes the mock; both voices read dead → no voice reachable.
o5="$(bash "$SUT" "$DIFF" --cheval "$MOCK" --preflight --voices "dead-1,dead-2" 2>/dev/null)"
check "preflight all-dead → refuses preflight_all_voices_dead" "preflight_all_voices_dead" \
  "$(jq -r '.error // ""' <<<"$o5")"
# and with a live voice present, the preflight does NOT refuse (it proceeds to a verdict):
o6="$(bash "$SUT" "$DIFF" --cheval "$MOCK" --preflight --voices "approve-1,approve-2" 2>/dev/null)"
check "preflight with live voices → no probe-refusal (real verdict)" "APPROVED" \
  "$(jq -r '.verdict' <<<"$o6")"

echo "cheval-council.test: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
