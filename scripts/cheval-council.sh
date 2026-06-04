#!/usr/bin/env bash
# =============================================================================
# cheval-council.sh — cheval-ROUTED multimodal review (coherent sibling of fagan-panel.sh)
# =============================================================================
# WHY THIS EXISTS
#   fagan-panel.sh dispatches each voice to a RAW CLI (claude -p / codex exec /
#   cursor-agent -p). That works, but it BYPASSES cheval (the intelligence
#   router), so the council loses: MODELINV audit (which model ACTUALLY answered
#   — codex/cursor report "unknown"), chain-walk fallback, verdict-quality
#   envelopes, and budget/metering. For medium-high-stakes work (financial risk,
#   data validity) the audit chain is load-bearing.
#
#   This script routes each voice THROUGH cheval instead:
#       python .claude/adapters/cheval.py --agent <voice> --input <diff> --system <persona>
#   so every voice emits a MODELINV envelope (.run/model-invoke.jsonl) and a
#   verdict-quality sidecar — the SAME contract flatline-orchestrator.sh uses.
#
# THE LESSON (grounded 2026-06-03): cheval HTTP providers (openai/anthropic API)
#   need API keys + live quota. cheval HEADLESS adapters (codex-headless /
#   claude-headless / gemini-headless) wrap the SAME subscription-auth CLIs FAGAN
#   already uses — but ADD the audit envelope. So bind council voices to HEADLESS
#   agents to get cheval's guardrails WITHOUT an API-quota dependency.
#
# HONEST HEADCOUNT: a voice whose chain exhausts / auth-misses / errors is
#   DROPPED (recorded in panel.dropped[]), never substituted — same discipline as
#   fagan-panel.sh. A lone CHANGES_REQUIRED holds the gate.
#
# Usage:
#   cheval-council.sh <diff_path|-> [--voices a,b,c] [--cheval <path>] [--out <json>]
#                     [--timeout N] [--max-tokens N]
#   --voices : comma-separated cheval AGENT names (default: the headless reviewer set)
#
# Exit: 0 APPROVED · 1 CHANGES_REQUIRED · 2 input error · 3 all voices dropped
# =============================================================================
set -euo pipefail

err() { printf '[cheval-council] %s\n' "$*" >&2; }

DIFF_PATH=""; OUT=""; TIMEOUT="${CHEVAL_COUNCIL_TIMEOUT:-280}"; MAX_TOKENS="${CHEVAL_COUNCIL_MAX_TOKENS:-16000}"
# Default voices bind to cheval agents that resolve to HEADLESS (subscription) adapters.
# gpt-reviewer (codex/openai) + a claude reviewer + a gemini voice = distinct corpora.
VOICES="${FAGAN_PANEL_VOICES_CHEVAL:-gpt-reviewer,reviewing-code,deep-thinker}"
CHEVAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --voices)     VOICES="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --cheval)     CHEVAL="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    -*)           err "unknown flag $1"; exit 2 ;;
    *)            DIFF_PATH="$1"; shift ;;
  esac
done
[[ -n "$DIFF_PATH" ]] || { err "usage: cheval-council.sh <diff|-> [--voices a,b,c]"; exit 2; }

# Resolve cheval.py (walk up for .claude/adapters/cheval.py, else env override).
if [[ -z "$CHEVAL" ]]; then
  d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/.claude/adapters/cheval.py" ]] && { CHEVAL="$d/.claude/adapters/cheval.py"; break; }
    d="$(dirname "$d")"
  done
fi
[[ -n "$CHEVAL" && -f "$CHEVAL" ]] || { err "cheval.py not found (pass --cheval <path>)"; exit 2; }

if [[ "$DIFF_PATH" == "-" ]]; then DIFF="$(cat)"; elif [[ -f "$DIFF_PATH" ]]; then DIFF="$(cat "$DIFF_PATH")"; else err "diff not found: $DIFF_PATH"; exit 2; fi
[[ -n "$DIFF" ]] || { err "empty diff"; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DIFF_FILE="$WORK/diff.txt"; printf '%s\n' "$DIFF" >"$DIFF_FILE"

# The review persona — strict, evidence-anchored, fix-first. Each voice returns a
# single JSON object so we can aggregate verdicts deterministically.
PERSONA="$WORK/persona.txt"
cat >"$PERSONA" <<'EOF'
You are a strict, evidence-anchored code reviewer (FAGAN seat). Review the unified
diff. Find correctness bugs, security holes, and contract violations — line-anchored,
fix-first. Be adversarial but precise. Do NOT invent scope beyond the diff.
Respond with ONLY a single JSON object, no prose around it:
{"verdict":"APPROVED"|"CHANGES_REQUIRED","findings":[{"severity":"critical"|"major"|"cleanup","line":<int|null>,"title":"...","fix":"..."}]}
Return CHANGES_REQUIRED if any critical/major finding exists.
EOF

panel_voices_json="[]"; dropped_json="[]"; models_ran_json="[]"
any_changes=0; survived=0

IFS=',' read -ra VARR <<<"$VOICES"
for voice in "${VARR[@]}"; do
  voice="$(echo "$voice" | xargs)"; [[ -n "$voice" ]] || continue
  err "dispatching voice '$voice' through cheval…"
  raw="$WORK/$voice.json"; vqs="$WORK/$voice.vq.json"; ec=0
  # Snapshot the audit-log length so we attribute ONLY this voice's MODELINV entries
  # (fix: avoids the cross-voice race of a bare `tail -1` on the shared log).
  before=0; [[ -f .run/model-invoke.jsonl ]] && before=$(wc -l < .run/model-invoke.jsonl 2>/dev/null || echo 0)
  LOA_VERDICT_QUALITY_SIDECAR="$vqs" \
    python3 "$CHEVAL" --agent "$voice" --input "$DIFF_FILE" --system "$PERSONA" \
      --output-format json --json-errors --max-tokens "$MAX_TOKENS" --timeout "$TIMEOUT" \
      >"$raw" 2>"$WORK/$voice.stderr" || ec=$?

  content="$(jq -r '.content // empty' "$raw" 2>/dev/null || true)"
  # Read ONLY the entries THIS voice appended (per-voice attribution, no race).
  model_ran="$(tail -n +"$((before+1))" .run/model-invoke.jsonl 2>/dev/null | jq -r '.payload.final_model_id // empty' 2>/dev/null | tail -1 || true)"
  [[ -n "$model_ran" ]] || model_ran="unknown"

  if [[ "$ec" -ne 0 || -z "$content" ]]; then
    reason="$(jq -r '.code // .message // empty' "$raw" 2>/dev/null | head -c 80)"
    [[ -n "$reason" ]] || reason="exit:$ec/empty"
    err "  voice '$voice' DROPPED ($reason)"
    dropped_json="$(jq -c --arg v "$voice" --arg r "$reason" '. + [{voice:$v, reason:$r}]' <<<"$dropped_json")"
    continue
  fi

  # Extract the voice's JSON verdict. BALANCED-BRACE scan (fix: a greedy /\{.*\}/
  # over-captures across multiple objects / trailing prose and corrupts the JSON).
  # Returns the FIRST substring that actually parses as JSON.
  vjson="$(printf '%s' "$content" | python3 -c '
import sys, json
t = sys.stdin.read().strip()
def first_json(s):
    try:
        json.loads(s); return s
    except Exception:
        pass
    depth = 0; start = -1
    for i, c in enumerate(s):
        if c == "{":
            if depth == 0: start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                cand = s[start:i+1]
                try:
                    json.loads(cand); return cand
                except Exception:
                    pass
    return "{}"
sys.stdout.write(first_json(t))
' 2>/dev/null || echo '{}')"
  echo "$vjson" | jq empty >/dev/null 2>&1 || vjson='{}'
  # FAIL-CLOSED: an unparseable / verdict-less voice response HOLDS the gate
  # (CHANGES_REQUIRED) — it must NEVER silently default to APPROVED. A broken
  # voice that passed garbage cannot be allowed to approve a review.
  verdict="$(jq -r '.verdict // "CHANGES_REQUIRED"' <<<"$vjson" 2>/dev/null || echo CHANGES_REQUIRED)"
  case "$verdict" in APPROVED|CHANGES_REQUIRED) ;; *) verdict="CHANGES_REQUIRED" ;; esac
  fcount="$(jq -r '[.findings[]?] | length' <<<"$vjson" 2>/dev/null || echo 0)"
  [[ "$verdict" == "CHANGES_REQUIRED" ]] && any_changes=1
  survived=$((survived+1))
  err "  voice '$voice' → $verdict ($fcount findings) · model_ran=$model_ran"
  panel_voices_json="$(jq -c --arg v "$voice" --arg m "$model_ran" --arg vd "$verdict" --argjson fc "$fcount" --argjson fj "$vjson" \
    '. + [{voice:$v, model_ran:$m, verdict:$vd, finding_count:$fc, findings:($fj.findings // [])}]' <<<"$panel_voices_json")"
  models_ran_json="$(jq -c --arg m "$model_ran" '. + [$m]' <<<"$models_ran_json")"
done

if [[ "$survived" -eq 0 ]]; then
  err "ALL VOICES DROPPED — failing CLOSED"
  result="$(jq -nc --argjson d "$dropped_json" '{verdict:"CHANGES_REQUIRED", error:"all_voices_dropped", panel:{voices:[], dropped:$d}}')"
  [[ -n "$OUT" ]] && echo "$result" >"$OUT" || echo "$result"; exit 3
fi

verdict="APPROVED"; [[ "$any_changes" -eq 1 ]] && verdict="CHANGES_REQUIRED"
ndrop="$(jq 'length' <<<"$dropped_json")"
summary="cheval-routed · $survived voice(s) survived, $ndrop dropped · verdict $verdict"
result="$(jq -nc --arg verdict "$verdict" --arg summary "$summary" --argjson v "$panel_voices_json" --argjson d "$dropped_json" --argjson m "$models_ran_json" \
  '{verdict:$verdict, summary:$summary, panel:{routed_via:"cheval", voices:$v, dropped:$d, models_ran:$m}}')"
[[ -n "$OUT" ]] && echo "$result" >"$OUT" || echo "$result"
err "$summary"
[[ "$verdict" == "APPROVED" ]] && exit 0 || exit 1
