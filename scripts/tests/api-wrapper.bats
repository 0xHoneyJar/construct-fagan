#!/usr/bin/env bats
# Happy-path tests for codex-review-api.sh. No aspirational asserts —
# every assertion reflects current implementation behavior.

load test_helper

@test "wrapper exists and is executable" {
  [[ -x "$API" ]]
}

@test "bash syntax is valid" {
  run bash -n "$API"
  [ "$status" -eq 0 ]
}

@test "no command exits 2 (input error)" {
  run "$API"
  [ "$status" -eq 2 ]
}

@test "unknown command exits 2" {
  OPENAI_API_KEY=stub run "$API" review-bogus
  [ "$status" -eq 2 ]
}

@test "review-diff with missing file exits 2" {
  OPENAI_API_KEY=stub run "$API" review-diff /nonexistent.diff
  [ "$status" -eq 2 ]
}

@test "review-diff with no args exits 2" {
  OPENAI_API_KEY=stub run "$API" review-diff
  [ "$status" -eq 2 ]
}

@test "review-files with no args exits 2" {
  OPENAI_API_KEY=stub run "$API" review-files
  [ "$status" -eq 2 ]
}

@test "missing OPENAI_API_KEY exits 4 (auth)" {
  cat > "$BATS_TMPDIR/sample.diff" <<'EOF'
diff --git a/foo.ts b/foo.ts
+const x = 1;
EOF
  unset OPENAI_API_KEY
  run "$API" review-diff "$BATS_TMPDIR/sample.diff"
  [ "$status" -eq 4 ]
}

@test "iteration > MAX_ITERATIONS auto-approves without invoking model" {
  cat > "$BATS_TMPDIR/sample.diff" <<'EOF'
diff --git a/foo.ts b/foo.ts
+const x = 1;
EOF
  echo '{"verdict":"CHANGES_REQUIRED","findings":[]}' > "$BATS_TMPDIR/prev.json"

  CODEX_REVIEW_MAX_ITERATIONS=3 OPENAI_API_KEY=stub run "$API" \
    review-diff "$BATS_TMPDIR/sample.diff" \
    --iteration 4 \
    --previous "$BATS_TMPDIR/prev.json"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "APPROVED"' > /dev/null
  echo "$output" | jq -e '.auto_approved == true' > /dev/null
  echo "$output" | jq -e '.note == "iteration-cap-reached"' > /dev/null
  echo "$output" | jq -e '.iteration == 4' > /dev/null
}

@test "iteration must be positive integer" {
  cat > "$BATS_TMPDIR/sample.diff" <<'EOF'
diff --git a/foo.ts b/foo.ts
+x
EOF
  OPENAI_API_KEY=stub run "$API" review-diff "$BATS_TMPDIR/sample.diff" --iteration 0
  [ "$status" -eq 2 ]
}

@test "re-review without --previous exits 2" {
  cat > "$BATS_TMPDIR/sample.diff" <<'EOF'
diff --git a/foo.ts b/foo.ts
+x
EOF
  OPENAI_API_KEY=stub run "$API" review-diff "$BATS_TMPDIR/sample.diff" --iteration 2
  [ "$status" -eq 2 ]
}

@test "--previous with missing file exits 2" {
  cat > "$BATS_TMPDIR/sample.diff" <<'EOF'
diff --git a/foo.ts b/foo.ts
+x
EOF
  OPENAI_API_KEY=stub run "$API" review-diff "$BATS_TMPDIR/sample.diff" \
    --iteration 2 --previous /nonexistent/prev.json
  [ "$status" -eq 2 ]
}
