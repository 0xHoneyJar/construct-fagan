#!/usr/bin/env bash
# run-tests.sh — the deterministic-checks gate for construct-fagan's instruments.
#
# Runs EVERY scripts/*.test.sh suite (the council aggregation/synth/floor/preflight, the
# voice-health probe) and exits non-zero if any fails. The review instrument verifies the
# agent; this verifies the instrument. A test that never runs is a numb gate — wire this
# into CI or a pre-merge hook so a regression in the cross-model review is CAUGHT, not
# silently shipped.
#
# Usage: bash scripts/run-tests.sh   (exit 0 = all green; non-zero = a suite failed)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
shopt -s nullglob
suites=("$HERE"/*.test.sh)
shopt -u nullglob

if [[ "${#suites[@]}" -eq 0 ]]; then
  echo "run-tests: no *.test.sh suites found in $HERE" >&2
  exit 2
fi

failed=()
for suite in "${suites[@]}"; do
  name="$(basename "$suite")"
  printf '\n──────── %s ────────\n' "$name"
  if bash "$suite"; then :; else failed+=("$name"); fi
done

printf '\n════════════════════════════════════════\n'
if [[ "${#failed[@]}" -eq 0 ]]; then
  echo "✓ run-tests: all ${#suites[@]} suite(s) passed"
  exit 0
else
  echo "✗ run-tests: ${#failed[@]}/${#suites[@]} suite(s) FAILED — ${failed[*]}"
  exit 1
fi
