#!/usr/bin/env bash
# =============================================================================
# lib-claude-exec.sh — Claude CLI (`claude -p`) adapter for the FAGAN panel
# =============================================================================
# Version: 1.0.0 — cycle-008 FAGAN-thorough (multimodel review panel)
#
# Provides the Opus voice for the review panel. Routes through the Claude Code
# OAuth *subscription* by stripping ANTHROPIC_API_KEY before the subprocess —
# raw `claude -p` with that key set hits API/credit mode ("Credit balance is
# too low"). This mirrors cheval's claude_headless_adapter (loa#879) and the
# `.run/claude-oauth.sh` shim. NEVER pass --bare (it forces ANTHROPIC_API_KEY).
#
# Functions:
#   claude_is_available                      → 0 if claude on PATH
#   claude_exec_single <prompt> <model> <out> [ws] [timeout]
#                                            → writes raw result-envelope JSON to <out>
#   claude_envelope_ok <out_file>            → 0 if .is_error == false
#   claude_envelope_review <out_file>        → extract .result, parse to finding JSON (stdout)
#   claude_envelope_model_ran <out_file>     → model id that actually answered (stdout)
#
# Depends (source lib-codex-exec.sh first): _portable_timeout, parse_codex_output
# =============================================================================

if [[ "${_LIB_CLAUDE_EXEC_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_CLAUDE_EXEC_LOADED="true"

CLAUDE_DEFAULT_TIMEOUT="${CLAUDE_DEFAULT_TIMEOUT:-300}"

# Robust JSON extractor for panel-voice answers (shared by claude + cursor adapters).
# Handles: pure JSON, ```json fences, and prose-wrapped JSON. Uses python3
# raw_decode (anchored at the first brace) which is immune to braces-inside-strings
# (e.g. `${var}` in a diff) — the failure mode that trips brace-counting regexes.
# Args: raw_text  → prints normalized JSON to stdout, returns 0/1.
_fagan_extract_json() {
  local raw="$1"
  [[ -n "$raw" ]] || return 1
  # fast path: already valid JSON
  if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -c .
    return 0
  fi
  # robust path: decode the first complete JSON object, ignore fence/prose/trailing
  if command -v python3 >/dev/null 2>&1; then
    local out
    out="$(printf '%s' "$raw" | python3 -c 'import json,sys
raw=sys.stdin.read()
i=raw.find("{")
if i<0: sys.exit(1)
try:
    obj,_=json.JSONDecoder().raw_decode(raw,i); print(json.dumps(obj))
except Exception: sys.exit(1)' 2>/dev/null)" || return 1
    [[ -n "$out" ]] && printf '%s' "$out" | jq -c . 2>/dev/null && return 0
  fi
  return 1
}

# Resolve claude binary once.
_claude_bin() {
  command -v claude 2>/dev/null || return 1
}

claude_is_available() {
  _claude_bin >/dev/null 2>&1
}

# Execute a single `claude -p` review call on the OAuth subscription.
# Args: prompt model output_file [workspace] [timeout_secs]
# Returns: 0 on success, 1 on failure, 124 on timeout, 4 if claude not found.
claude_exec_single() {
  local prompt="$1"
  local model="$2"
  local output_file="$3"
  local workspace="${4:-}"
  local timeout_secs="${5:-$CLAUDE_DEFAULT_TIMEOUT}"

  local claude_bin
  claude_bin="$(_claude_bin)" || { echo "[claude-exec] ERROR: claude not on PATH" >&2; return 4; }

  local cleanup_ws="false"
  if [[ -z "$workspace" ]]; then
    workspace="$(mktemp -d "${TMPDIR:-/tmp}/fagan-claude-ws-$$.XXXXXX")"
    cleanup_ws="true"
  fi

  # Strip ANTHROPIC_API_KEY → OAuth subscription path (loa#879). Run from an
  # isolated workspace so a tool-call can't reach the repo. --output-format json
  # gives a result envelope; the model's text answer is in `.result`.
  #
  # --tools "" disables ALL tools. The review needs ZERO tools (the diff is in
  # the prompt), and the diff is UNTRUSTED — a prompt-injection payload inside it
  # must not be able to steer this voice into reading absolute-path secrets
  # (~/.ssh, ~/.aws), bash, or network egress. An empty cwd does NOT sandbox
  # absolute reads. Parity with the cursor adapter's lockdown.
  # (self-review iter-1, opus-skeptic CRITICAL)
  local cmd=(env -u ANTHROPIC_API_KEY "$claude_bin" -p
             --output-format json --model "$model" --tools "")

  # Prompt on STDIN (not argv) — keeps the unredacted diff out of the process
  # listing and dodges ARG_MAX on large diffs. (self-review iter-2, gpt)
  local exit_code=0
  ( cd "$workspace" && printf '%s' "$prompt" | _portable_timeout "$timeout_secs" "${cmd[@]}" ) \
    >"$output_file" 2>/dev/null || exit_code=$?

  [[ "$cleanup_ws" == "true" && -d "$workspace" ]] && rm -rf "$workspace" 2>/dev/null || true

  if [[ $exit_code -eq 124 ]]; then
    echo "[claude-exec] ERROR: claude -p timed out after ${timeout_secs}s" >&2
    return 124
  fi
  return $exit_code
}

# 0 if the envelope reports success (is_error == false), else 1.
# NB: do NOT use `.is_error // true` — jq's `//` treats the boolean `false`
# as empty and returns the alternative, inverting the check (loa-style gotcha).
claude_envelope_ok() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  [[ "$(jq -r '.is_error' "$f" 2>/dev/null)" == "false" ]]
}

# Extract the model's answer (.result) and normalize it to finding JSON.
claude_envelope_review() {
  local f="$1"
  local result
  result="$(jq -r '.result // empty' "$f" 2>/dev/null)" || return 1
  [[ -n "$result" ]] || return 1
  _fagan_extract_json "$result"
}

# The model id that actually answered (MODELINV) — key under .modelUsage.
claude_envelope_model_ran() {
  local f="$1"
  jq -r '(.modelUsage // {}) | keys[0] // "unknown"' "$f" 2>/dev/null || echo "unknown"
}
