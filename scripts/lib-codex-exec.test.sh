#!/usr/bin/env bash
# lib-codex-exec.test.sh — verifies _version_gte(), the version comparison that gates codex
# CAPABILITY detection (which codex flags fagan-review.sh may use). This is the classic
# bug-prone spot: a naive string compare reads "0.130" < "0.9" (lexical "1" < "9"), but the
# real ordering is 0.130 > 0.9. A regression here silently mis-detects codex capabilities.
# Run: bash scripts/lib-codex-exec.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$HERE/lib/lib-codex-exec.sh"
pass=0; fail=0

gte() { # <name> <v1> <v2> <expected: yes|no>  (asserts _version_gte v1 v2)
  local name="$1" v1="$2" v2="$3" exp="$4" got
  if _version_gte "$v1" "$v2"; then got=yes; else got=no; fi
  if [[ "$got" == "$exp" ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL %s (_version_gte %s %s → %s, expected %s)\n' "$name" "$v1" "$v2" "$got" "$exp"; fi
}

gte "equal versions are >="                     "1.2.3"   "1.2.3"   yes
gte "higher patch is >="                        "1.2.4"   "1.2.3"   yes
gte "lower patch is NOT >="                      "1.2.2"   "1.2.3"   no
gte "NUMERIC not lexical: 0.130.0 >= 0.9.0"      "0.130.0" "0.9.0"   yes
gte "NUMERIC not lexical: 0.9.0 < 0.130.0"       "0.9.0"   "0.130.0" no
gte "major bump >="                              "2.0.0"   "1.9.9"   yes
gte "older major NOT >="                          "1.9.9"   "2.0.0"   no
gte "real codex min-version gate (0.130 ≥ 0.20)" "0.130.0" "0.20.0"  yes

echo "lib-codex-exec.test: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
