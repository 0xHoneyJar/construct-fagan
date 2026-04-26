#!/usr/bin/env bats
# Verify the awk-based prompt template substitution round-trips safely
# even with shell metacharacters in PREVIOUS_FINDINGS.

load test_helper

@test "re-review.md template has the expected substitution markers" {
  grep -q '{{ITERATION}}' "$CONSTRUCT_ROOT/prompts/re-review.md"
  grep -q '{{PREVIOUS_FINDINGS}}' "$CONSTRUCT_ROOT/prompts/re-review.md"
}

@test "awk substitution replaces both markers" {
  local out
  out=$(awk -v iter=2 -v findings='{"x":1}' '
    { gsub(/\{\{ITERATION\}\}/, iter); gsub(/\{\{PREVIOUS_FINDINGS\}\}/, findings); print }
  ' "$CONSTRUCT_ROOT/prompts/re-review.md")

  ! echo "$out" | grep -q '{{ITERATION}}'
  ! echo "$out" | grep -q '{{PREVIOUS_FINDINGS}}'
  echo "$out" | grep -q 'iteration `2`'
  echo "$out" | grep -q '{"x":1}'
}

@test "awk substitution survives shell metacharacters in findings" {
  local meta='findings with $variables `backticks` and "quotes" and ;semicolons;'
  local out
  out=$(awk -v iter=3 -v findings="$meta" '
    { gsub(/\{\{ITERATION\}\}/, iter); gsub(/\{\{PREVIOUS_FINDINGS\}\}/, findings); print }
  ' "$CONSTRUCT_ROOT/prompts/re-review.md")

  echo "$out" | grep -qF "$meta"
}

@test "convergence invariant phrase is present (load-bearing)" {
  grep -q 'VERIFY. DON.T REINVENT. CONVERGE.' "$CONSTRUCT_ROOT/prompts/re-review.md"
}

@test "code-review.md exists and ends with strict-on-security imperative" {
  [[ -f "$CONSTRUCT_ROOT/prompts/code-review.md" ]]
  tail -3 "$CONSTRUCT_ROOT/prompts/code-review.md" | grep -q 'BE STRICT ON SECURITY'
}
