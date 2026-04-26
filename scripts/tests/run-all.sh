#!/usr/bin/env bash
# Run all bats tests in this directory.
set -euo pipefail

if ! command -v bats >/dev/null; then
  echo "bats not installed. Install with: brew install bats-core" >&2
  exit 127
fi

cd "$(dirname "${BASH_SOURCE[0]}")"
bats *.bats
