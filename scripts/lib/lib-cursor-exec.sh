#!/usr/bin/env bash
# =============================================================================
# lib-cursor-exec.sh — Cursor Composer adapter for the FAGAN panel
# =============================================================================
# Version: 1.0.0 — cycle-008 FAGAN-thorough
#
# Composer 2.5 (Cursor, built on Moonshot Kimi K2.5 + heavy RL) — the
# coding-specialist REVIEWER voice and a genuinely DISTINCT base corpus from
# Opus (Anthropic) and GPT (OpenAI). That corpus independence is the whole
# point: it fails differently, so it catches what the others miss.
#
# SECURITY (load-bearing — cursor-agent -p has full write+bash tool access):
#   - run in an ISOLATED EMPTY workspace (mktemp) — empty blast radius
#   - pass --trust (trust the throwaway dir, skip the interactive Trust prompt)
#   - NEVER pass -f / --yolo (force-allow-commands) — that is the injection footgun
#   - the diff lives IN the prompt, so NO repo file access is needed
#
# MODELINV caveat: cursor-agent's JSON output does NOT report the served model,
# so the panel records model_ran as "unknown" (NOT the requested model) unless the
# envelope ever exposes .model/.modelId. We pass --model explicitly and never -fast;
# a silent downgrade can't be detected from CLI output today. (build-doc "assert model ran")
#
# Depends (orchestrator sources these FIRST):
#   _fagan_extract_json  (lib-claude-exec.sh)
#   _portable_timeout    (lib-codex-exec.sh)
# =============================================================================

if [[ "${_LIB_CURSOR_EXEC_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_CURSOR_EXEC_LOADED="true"

CURSOR_DEFAULT_TIMEOUT="${CURSOR_DEFAULT_TIMEOUT:-300}"

_cursor_bin() { command -v cursor-agent 2>/dev/null || return 1; }

# Available only if the binary exists AND the account is logged in (fast check,
# bounded — avoids a 300s hang on the sign-in screen when not authed).
cursor_is_available() {
  local bin; bin="$(_cursor_bin)" || return 1
  local status
  status="$(_portable_timeout 15 "$bin" status </dev/null 2>&1 || true)"
  # "Not logged in" CONTAINS "logged in" — a bare substring match false-positives
  # on an unauthenticated install. Require "logged in" AND not "not logged in".
  # (self-review iter-1, composer MAJOR)
  printf '%s' "$status" | grep -qi "logged in" && ! printf '%s' "$status" | grep -qi "not logged in"
}

# Execute a single Composer review. Args: prompt model output_file [ws] [timeout]
# Returns 0 on success, non-zero on failure, 124 on timeout.
cursor_exec_single() {
  local prompt="$1"
  local model="$2"
  local output_file="$3"
  local workspace="${4:-}"
  local timeout_secs="${5:-$CURSOR_DEFAULT_TIMEOUT}"

  local bin; bin="$(_cursor_bin)" || { echo "[cursor-exec] ERROR: cursor-agent not on PATH" >&2; return 4; }

  local cleanup_ws="false"
  if [[ -z "$workspace" ]]; then
    workspace="$(mktemp -d "${TMPDIR:-/tmp}/fagan-cursor-ws-$$.XXXXXX")"
    cleanup_ws="true"
  fi

  # Hardened (self-review iter-2): --mode plan = read-only (analyze, no edits) +
  # --sandbox enabled = OS confinement — defense-in-depth parity with the claude
  # --tools "" lockdown, since the diff is UNTRUSTED. Verified empirically: without
  # -f, cursor denies tool execution by default ("rejected by sandbox policy").
  # --trust is BOOLEAN (skip the Workspace-Trust prompt for the empty cwd); NEVER
  # -f/--yolo. "$prompt" is the trailing POSITIONAL the agent reads as the prompt
  # (a self-review voice's "--trust ate the prompt" claim was a FALSE ALARM — the
  # live run produced a real Composer review). Empty isolated cwd = empty blast radius.
  local cmd=("$bin" -p --mode plan --sandbox enabled --output-format json --model "$model" --trust "$prompt")

  local exit_code=0
  ( cd "$workspace" && _portable_timeout "$timeout_secs" "${cmd[@]}" ) </dev/null \
    >"$output_file" 2>/dev/null || exit_code=$?

  [[ "$cleanup_ws" == "true" && -d "$workspace" ]] && rm -rf "$workspace" 2>/dev/null || true

  if [[ $exit_code -eq 124 ]]; then
    echo "[cursor-exec] ERROR: cursor-agent timed out after ${timeout_secs}s" >&2
    return 124
  fi
  return $exit_code
}

cursor_envelope_ok() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  [[ "$(jq -r '.is_error' "$f" 2>/dev/null)" == "false" ]]
}

cursor_envelope_review() {
  local f="$1"
  local result
  result="$(jq -r '.result // empty' "$f" 2>/dev/null)" || return 1
  [[ -n "$result" ]] || return 1
  _fagan_extract_json "$result"
}

# Best-effort: cursor-agent omits the served model; returns empty if absent so
# the caller can keep the requested model id.
cursor_envelope_model_ran() {
  local f="$1"
  jq -r '.model // .modelId // empty' "$f" 2>/dev/null || true
}
