#!/usr/bin/env bash
# =============================================================================
# fagan-review.sh — /fagan review dispatcher (council DEFAULT, single FALLBACK)
# =============================================================================
# WHY THIS EXISTS
#   /fagan used to call codex-review-api.sh directly — a SINGLE GPT-5.5 pass.
#   A single model has a single blind spot: the model that wrote (or is biased
#   like) the code is the one judging it. This dispatcher makes the cross-model
#   COUNCIL (cheval-council.sh) the default — four DISTINCT model families
#   (claude / gpt-codex / cursor-composer / gemini) review the same diff, so no
#   one corpus's blind spot decides the verdict — and keeps the single-pass path
#   as an explicit, documented FALLBACK.
#
# MODES (env FAGAN_REVIEW_MODE, default `council`):
#   council  → scripts/cheval-council.sh  (4-voice cross-model, MODELINV audit,
#              drop-discipline, fail-closed). THE DEFAULT.
#   single   → scripts/codex-review-api.sh review-diff  (lean single GPT pass).
#
#   In `council` mode, if the council CANNOT RUN (exit 2: cheval.py not found /
#   bad input — an INFRASTRUCTURE failure, NOT a verdict), this dispatcher falls
#   back to single-pass so a missing cheval doesn't block all review. It does
#   NOT fall back on exit 3 (all-voices-dropped) — that is the council's
#   load-bearing FAIL-CLOSED verdict and MUST propagate. A degraded council that
#   could reach zero models must never be silently downgraded to a single-model
#   APPROVED. Set FAGAN_REVIEW_COUNCIL_FALLBACK=0 to make a council infra-failure
#   hard-fail (no single-pass fallback).
#
# Usage:
#   fagan-review.sh <diff_path|-> [--mode council|single] [council/codex flags…]
#   Unrecognized flags are forwarded to the active backend, so e.g.
#     fagan-review.sh changes.diff --voices a,b,c --cheval /path/cheval.py
#   reaches the council, and
#     FAGAN_REVIEW_MODE=single fagan-review.sh changes.diff --model gpt-5.5
#   reaches codex-review-api.sh.
#
# Exit: 0 APPROVED · 1 CHANGES_REQUIRED · 2 input/infra error · 3 all voices
#       dropped (council fail-closed) · 4 auth (single) · 5 format (single)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNCIL="$SCRIPT_DIR/cheval-council.sh"
CODEX="$SCRIPT_DIR/codex-review-api.sh"

err() { printf '[fagan-review] %s\n' "$*" >&2; }

MODE="${FAGAN_REVIEW_MODE:-council}"
COUNCIL_FALLBACK="${FAGAN_REVIEW_COUNCIL_FALLBACK:-1}"

# Flags are partitioned by backend so a council→single fallback never forwards a
# council-only flag (e.g. --cheval) to codex-review-api.sh (which would error).
#   council-only : --cheval --voices --out --timeout --max-tokens
#   codex-only   : --previous --output --iteration
#   shared       : --model (forwarded to whichever backend runs)
DIFF_PATH=""
COUNCIL_ARGS=(); CODEX_ARGS=()
# (no bash-4 nameref — match the council's macOS/bash-3.2 portability discipline)
while [[ $# -gt 0 ]]; do
  flag="$1"; val=""; has_val=0
  if [[ "$flag" == --* && $# -ge 2 && "$2" != -* && "$2" != "-" ]]; then val="$2"; has_val=1; fi
  # NOTE: arms end with `; :` so a short-circuited `&&` can't leave the case with
  # a non-zero status that `set -e` would trip on.
  case "$flag" in
    --mode)      MODE="$2"; shift 2; continue ;;
    -)           DIFF_PATH="$flag"; shift; continue ;;
    --cheval|--voices|--out|--timeout|--max-tokens)
                 COUNCIL_ARGS+=("$flag"); [[ $has_val -eq 1 ]] && COUNCIL_ARGS+=("$val"); : ;;
    --previous|--output|--iteration)
                 CODEX_ARGS+=("$flag"); [[ $has_val -eq 1 ]] && CODEX_ARGS+=("$val"); : ;;
    --model)     # shared — goes to both partitions; only the active backend runs
                 COUNCIL_ARGS+=("$flag"); CODEX_ARGS+=("$flag")
                 [[ $has_val -eq 1 ]] && { COUNCIL_ARGS+=("$val"); CODEX_ARGS+=("$val"); }; : ;;
    --*)         # unknown flag → forward to council only (the default backend)
                 COUNCIL_ARGS+=("$flag"); [[ $has_val -eq 1 ]] && COUNCIL_ARGS+=("$val"); : ;;
    *)           [[ -z "$DIFF_PATH" ]] && DIFF_PATH="$flag"; : ;;
  esac
  if [[ "$flag" == --* && $has_val -eq 1 ]]; then shift 2; else shift; fi
done

[[ -n "$DIFF_PATH" ]] || { err "usage: fagan-review.sh <diff|-> [--mode council|single] [flags…]"; exit 2; }

case "$MODE" in
  council)
    [[ -x "$COUNCIL" || -f "$COUNCIL" ]] || { err "council script missing: $COUNCIL"; exit 2; }
    err "review mode: COUNCIL (cross-model 4-voice) → $COUNCIL"
    ec=0
    bash "$COUNCIL" "$DIFF_PATH" "${COUNCIL_ARGS[@]}" || ec=$?
    if [[ "$ec" -eq 2 && "$COUNCIL_FALLBACK" == "1" ]]; then
      # Council could not RUN (infra: cheval.py absent / bad input). Fall back to
      # single-pass. NOTE: exit 3 (all-dropped fail-closed) is deliberately NOT
      # caught here — it propagates as the council's verdict.
      err "council infra-failure (exit 2) — falling back to SINGLE-pass (set FAGAN_REVIEW_COUNCIL_FALLBACK=0 to disable)"
      MODE="single"
    else
      exit "$ec"
    fi
    ;;
esac

if [[ "$MODE" == "single" ]]; then
  [[ -x "$CODEX" || -f "$CODEX" ]] || { err "single-pass script missing: $CODEX"; exit 2; }
  err "review mode: SINGLE (one GPT pass) → $CODEX review-diff"
  exec bash "$CODEX" review-diff "$DIFF_PATH" "${CODEX_ARGS[@]}"
fi

err "unknown FAGAN_REVIEW_MODE '$MODE' (expected council|single)"
exit 2
