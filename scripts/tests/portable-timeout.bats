#!/usr/bin/env bats
# Tests for the portable timeout shim in lib-codex-exec.sh.
# Verifies cross-platform behavior: GNU timeout · gtimeout (coreutils) · perl-shim.
# All three must produce exit code 124 on timeout (GNU semantics).

load test_helper

setup() {
  source "$CONSTRUCT_ROOT/scripts/lib/lib-security.sh"
  source "$CONSTRUCT_ROOT/scripts/lib/lib-codex-exec.sh"
  unset _PORTABLE_TIMEOUT_BIN
}

@test "_resolve_portable_timeout finds at least one mechanism on this host" {
  # Direct call (not `run`) so variable assignment persists in current shell
  _resolve_portable_timeout
  [ "$?" -eq 0 ]
  [[ "$_PORTABLE_TIMEOUT_BIN" == "timeout" || "$_PORTABLE_TIMEOUT_BIN" == "gtimeout" || "$_PORTABLE_TIMEOUT_BIN" == "perl-shim" ]]
}

@test "_portable_timeout returns 0 when command completes within budget" {
  run _portable_timeout 5 true
  [ "$status" -eq 0 ]
}

@test "_portable_timeout returns command's own exit code (non-timeout failure)" {
  run _portable_timeout 5 false
  [ "$status" -eq 1 ]
}

@test "_portable_timeout returns 124 when command exceeds budget (GNU semantics)" {
  run _portable_timeout 1 sleep 5
  [ "$status" -eq 124 ]
}

@test "_portable_timeout via perl-shim produces 124 not 142 (SIGALRM normalization)" {
  if ! command -v perl >/dev/null 2>&1; then
    skip "perl not available on this host"
  fi
  # Force perl-shim path
  _PORTABLE_TIMEOUT_BIN="perl-shim"
  run _portable_timeout 1 sleep 5
  [ "$status" -eq 124 ]
  [ "$status" -ne 142 ]
}

@test "_portable_timeout via perl-shim respects exact-budget commands" {
  if ! command -v perl >/dev/null 2>&1; then
    skip "perl not available on this host"
  fi
  _PORTABLE_TIMEOUT_BIN="perl-shim"
  run _portable_timeout 3 sleep 1
  [ "$status" -eq 0 ]
}

@test "_resolve_portable_timeout caches detection across calls" {
  _resolve_portable_timeout
  local first="$_PORTABLE_TIMEOUT_BIN"
  _resolve_portable_timeout
  [ "$_PORTABLE_TIMEOUT_BIN" = "$first" ]
}

@test "_portable_timeout passes through command args correctly" {
  run _portable_timeout 5 sh -c "echo hello; exit 7"
  [ "$status" -eq 7 ]
  [[ "$output" == "hello" ]]
}
