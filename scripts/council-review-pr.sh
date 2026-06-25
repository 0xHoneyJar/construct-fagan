#!/usr/bin/env bash
# council-review-pr.sh — ONE command to run the governed cross-model council (codex+cursor
# via cheval) on a PR's diff. The convergence loop is the subscription-usage path; it gets
# under-used when invoking it is multi-step (gh pr diff → find cheval.py → cheval-council.sh).
# This collapses that to: council-review-pr.sh <pr> [--repo owner/name] [--preflight].
#
# Consumption gradient: the verified path must be the path of LEAST resistance, or it loses
# to the lazy one. Lower the friction → the subscriptions actually get used.
#
# Resolves cheval.py from $CHEVAL_PY, else walks up from $PWD for .claude/adapters/cheval.py.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PR=""; REPO=""; EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       REPO="$2"; shift 2 ;;
    --preflight)  EXTRA+=(--preflight); shift ;;
    --out)        EXTRA+=(--out "$2"); shift 2 ;;
    --voices)     EXTRA+=(--voices "$2"); shift 2 ;;
    -h|--help)    echo "usage: council-review-pr.sh <pr-number> [--repo owner/name] [--preflight] [--voices a,b,c] [--out file]"; exit 0 ;;
    -*)           echo "council-review-pr: unknown flag $1" >&2; exit 2 ;;
    *)            PR="$1"; shift ;;
  esac
done
[[ -n "$PR" ]] || { echo "usage: council-review-pr.sh <pr-number> [--repo owner/name] [--preflight]" >&2; exit 2; }

# Resolve cheval.py — explicit $CHEVAL_PY, else walk up (the council/voice-health pattern).
CHEVAL="${CHEVAL_PY:-}"
if [[ -z "$CHEVAL" ]]; then
  d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.claude/adapters/cheval.py" ]]; then CHEVAL="$d/.claude/adapters/cheval.py"; break; fi
    d="$(dirname "$d")"
  done
fi
[[ -n "$CHEVAL" && -f "$CHEVAL" ]] || { echo "council-review-pr: cheval.py not found — set CHEVAL_PY=<path/to/.claude/adapters/cheval.py>" >&2; exit 2; }

repo_flag=(); [[ -n "$REPO" ]] && repo_flag=(--repo "$REPO")
diff="$(mktemp)"; trap 'rm -f "$diff"' EXIT
if ! gh pr diff "$PR" "${repo_flag[@]}" >"$diff" 2>/dev/null; then
  echo "council-review-pr: \`gh pr diff $PR ${REPO:+--repo $REPO}\` failed (auth? wrong repo? PR number?)" >&2; exit 2
fi
[[ -s "$diff" ]] || { echo "council-review-pr: PR #$PR has an empty diff" >&2; exit 2; }

echo "[council-review-pr] PR #${PR}${REPO:+ ($REPO)} · $(wc -l <"$diff" | tr -d ' ') diff lines · routing through cheval (codex+cursor; claude drops on the fable issue until model-config flips)…" >&2
exec bash "$HERE/cheval-council.sh" "$diff" --cheval "$CHEVAL" "${EXTRA[@]}"
