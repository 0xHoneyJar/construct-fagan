# Common test helper sourced by every .bats file.
#   load test_helper

CONSTRUCT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/../.." && pwd)"
API="$CONSTRUCT_ROOT/scripts/codex-review-api.sh"

export CONSTRUCT_ROOT API
