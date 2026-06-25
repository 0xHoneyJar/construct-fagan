#!/usr/bin/env bash
# lib-security.test.sh — verifies redact_secrets() actually strips the secret classes it
# claims to. redact_secrets is live (codex-review-api.sh runs it over review output before
# it leaves the process); an UNVERIFIED redaction is a leak waiting to happen. Uses
# realistic full-length tokens (the patterns require minimum lengths — a short probe would
# false-negative, as a too-short ghp_ did on first pass).
# Run: bash scripts/lib-security.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$HERE/lib/lib-security.sh"
pass=0; fail=0

# redacts <name> <secret> — the secret must NOT survive, and [REDACTED] must appear.
redacts() {
  local name="$1" secret="$2"
  local out; out="$(redact_secrets "prefix $secret suffix" text /nonexistent-config 2>/dev/null)"
  if [[ "$out" != *"$secret"* && "$out" == *"[REDACTED]"* ]]; then
    pass=$((pass+1)); printf '  ok   redacts %s\n' "$name"
  else
    fail=$((fail+1)); printf '  FAIL redacts %s\n       leaked: %s\n' "$name" "$out"
  fi
}
# keeps <name> <text> — an ordinary string must pass through untouched (no false-positive).
keeps() {
  local name="$1" text="$2"
  local out; out="$(redact_secrets "$text" text /nonexistent-config 2>/dev/null)"
  if [[ "$out" == "$text" ]]; then pass=$((pass+1)); printf '  ok   keeps %s (no false-positive)\n' "$name"
  else fail=$((fail+1)); printf '  FAIL keeps %s\n       mangled: %s\n' "$name" "$out"; fi
}

redacts "Anthropic API key"      "sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
redacts "OpenAI project key"     "sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz012345"
redacts "OpenAI general key"     "sk-AbCdEfGhIjKlMnOpQrStUvWxYz012345"
redacts "GitHub PAT (ghp_, 36c)" "ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
redacts "GitHub OAuth (gho_)"    "gho_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
redacts "AWS access key id"      "AKIAIOSFODNN7EXAMPLE"
redacts "JWT"                    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJ"

keeps "ordinary review prose"    "the function returns 401 on invalid creds and logs nothing"
keeps "a short sk- false-friend" "the ask-201 ticket tracks this"

echo "lib-security.test: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
