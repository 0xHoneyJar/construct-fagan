#!/usr/bin/env bash
# =============================================================================
# codex-review-api.sh — Lean diff/file code review via codex CLI
# =============================================================================
#
# Commands:
#   review-diff <diff_path>   Review a unified diff
#   review-files <f1> [f2…]   Review specific files (no diff context)
#
# Options:
#   --iteration N             Iteration number (default 1; ≥2 triggers re-review prompt)
#   --previous <findings.json> Required when iteration ≥ 2 (the prior verdict JSON)
#   --output <file>           Write JSON response to file in addition to stdout
#   --model <id>              Override CODEX_REVIEW_MODEL
#
# Exit codes:
#   0 = APPROVED
#   1 = CHANGES_REQUIRED
#   2 = input error (bad args, missing files)
#   3 = API failure (codex invocation failed)
#   4 = auth (OPENAI_API_KEY not set)
#   5 = format error (response could not be parsed as JSON)
#
# Env:
#   OPENAI_API_KEY              required
#   CODEX_REVIEW_MODEL          default: gpt-5.3-codex
#   CODEX_REVIEW_TIMEOUT        default: 300
#   CODEX_REVIEW_MAX_ITERATIONS default: 3
#   CODEX_REVIEW_MAX_TOKENS     default: 30000
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSTRUCT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$CONSTRUCT_ROOT/prompts"
SCHEMA_PATH="$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json"

# shellcheck source=lib/lib-security.sh
source "$SCRIPT_DIR/lib/lib-security.sh"
# shellcheck source=lib/lib-content.sh
source "$SCRIPT_DIR/lib/lib-content.sh"
# shellcheck source=lib/lib-codex-exec.sh
source "$SCRIPT_DIR/lib/lib-codex-exec.sh"

CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.3-codex}"
CODEX_REVIEW_TIMEOUT="${CODEX_REVIEW_TIMEOUT:-300}"
CODEX_REVIEW_MAX_ITERATIONS="${CODEX_REVIEW_MAX_ITERATIONS:-3}"
CODEX_REVIEW_MAX_TOKENS="${CODEX_REVIEW_MAX_TOKENS:-30000}"

err() { echo "[codex-review] ERROR: $*" >&2; }

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

# -----------------------------------------------------------------------------
# Arg parsing
# -----------------------------------------------------------------------------
COMMAND="${1:-}"
[[ -z "$COMMAND" ]] && { usage; exit 2; }
shift

iter=1
previous_findings_file=""
output_file=""
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iteration) iter="$2"; shift 2 ;;
    --previous)  previous_findings_file="$2"; shift 2 ;;
    --output)    output_file="$2"; shift 2 ;;
    --model)     CODEX_REVIEW_MODEL="$2"; shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do inputs+=("$1"); shift; done ;;
    -*) err "Unknown option: $1"; exit 2 ;;
    *) inputs+=("$1"); shift ;;
  esac
done

if ! [[ "$iter" =~ ^[0-9]+$ ]] || [[ "$iter" -lt 1 ]]; then
  err "--iteration must be a positive integer"
  exit 2
fi

# -----------------------------------------------------------------------------
# Auto-approval (inherits gpt-review-api.sh:264-269 pattern)
# -----------------------------------------------------------------------------
if [[ "$iter" -gt "$CODEX_REVIEW_MAX_ITERATIONS" ]]; then
  resp=$(jq -n \
    --argjson cap "$CODEX_REVIEW_MAX_ITERATIONS" \
    --argjson it  "$iter" \
    '{verdict:"APPROVED", summary:("Auto-approved after " + ($cap|tostring) + " iterations"), auto_approved:true, iteration:$it, note:"iteration-cap-reached"}')
  echo "$resp"
  [[ -n "$output_file" ]] && echo "$resp" > "$output_file"
  exit 0
fi

ensure_codex_auth || { err "OPENAI_API_KEY not set"; exit 4; }

# -----------------------------------------------------------------------------
# Build content payload
# -----------------------------------------------------------------------------
collect_inputs() {
  local cmd="$1"; shift
  case "$cmd" in
    review-diff)
      [[ ${#inputs[@]} -eq 1 ]] || { err "review-diff requires exactly one diff path"; exit 2; }
      local p="${inputs[0]}"
      if [[ "$p" == "-" ]]; then
        cat
      elif [[ -f "$p" ]]; then
        cat "$p"
      else
        err "diff not found: $p"; exit 2
      fi
      ;;
    review-files)
      [[ ${#inputs[@]} -ge 1 ]] || { err "review-files requires at least one file path"; exit 2; }
      for f in "${inputs[@]}"; do
        [[ -f "$f" ]] || { err "file not found: $f"; exit 2; }
        printf '\n=== FILE: %s ===\n' "$f"
        cat "$f"
      done
      ;;
    *) err "Unknown command: $cmd"; usage; exit 2 ;;
  esac
}

raw=$(collect_inputs "$COMMAND")
[[ -n "$raw" ]] || { err "empty input"; exit 2; }
prepared=$(prepare_content "$raw" "$CODEX_REVIEW_MAX_TOKENS")

# -----------------------------------------------------------------------------
# Build prompt
# -----------------------------------------------------------------------------
if [[ "$iter" -eq 1 ]]; then
  [[ -f "$PROMPTS_DIR/code-review.md" ]] || { err "missing prompt: $PROMPTS_DIR/code-review.md"; exit 3; }
  sp=$(cat "$PROMPTS_DIR/code-review.md")
else
  [[ -n "$previous_findings_file" ]] || { err "Re-review (iter ≥ 2) requires --previous <findings.json>"; exit 2; }
  [[ -f "$previous_findings_file" ]] || { err "previous findings not found: $previous_findings_file"; exit 2; }
  [[ -f "$PROMPTS_DIR/re-review.md" ]] || { err "missing prompt: $PROMPTS_DIR/re-review.md"; exit 3; }
  prev=$(cat "$previous_findings_file")
  # Awk-based safe template substitution (vision-002 pattern from gpt-review-api.sh:90)
  sp=$(awk -v iter="$iter" -v findings="$prev" '
    { gsub(/\{\{ITERATION\}\}/, iter); gsub(/\{\{PREVIOUS_FINDINGS\}\}/, findings); print }
  ' "$PROMPTS_DIR/re-review.md")
fi

full_prompt=$(printf '%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON only, conforming to the schema in the system prompt.' "$sp" "$prepared")

# -----------------------------------------------------------------------------
# Execute codex CLI
# -----------------------------------------------------------------------------
workspace=$(setup_review_workspace "")
out="${workspace}/codex-review-out-$$.txt"

if ! codex_exec_single "$full_prompt" "$CODEX_REVIEW_MODEL" "$out" "$workspace" "$CODEX_REVIEW_TIMEOUT"; then
  cleanup_workspace "$workspace"
  err "codex invocation failed"
  exit 3
fi

raw_response=$(cat "$out")
cleanup_workspace "$workspace"

# -----------------------------------------------------------------------------
# Parse + enrich + redact
# -----------------------------------------------------------------------------
if ! resp=$(parse_codex_output "$raw_response"); then
  err "could not parse codex output as JSON"
  exit 5
fi

# Enrich with iteration metadata (after model returns, before redaction)
resp=$(echo "$resp" | jq --argjson it "$iter" '. + {iteration: $it}')

# Redact secrets in the response (jq key-preserving)
resp=$(redact_secrets "$resp" "json")

echo "$resp"
[[ -n "$output_file" ]] && echo "$resp" > "$output_file"

# -----------------------------------------------------------------------------
# Exit code maps verdict
# -----------------------------------------------------------------------------
verdict=$(echo "$resp" | jq -r '.verdict // "UNKNOWN"')
case "$verdict" in
  APPROVED)         exit 0 ;;
  CHANGES_REQUIRED) exit 1 ;;
  *) err "unrecognized verdict: $verdict"; exit 5 ;;
esac
