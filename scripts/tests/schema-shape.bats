#!/usr/bin/env bats
# Verify the schema is valid JSON Schema draft-07 and matches the documented shape.

load test_helper

@test "schema is valid JSON" {
  jq empty "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json"
}

@test "schema declares draft-07" {
  local declared
  declared=$(jq -r '."$schema"' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json")
  [ "$declared" = "http://json-schema.org/draft-07/schema#" ]
}

@test "schema requires verdict" {
  jq -e '.required | index("verdict")' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json"
}

@test "verdict enum is binary (APPROVED, CHANGES_REQUIRED)" {
  local verdicts
  verdicts=$(jq -r '.properties.verdict.enum | sort | join(",")' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json")
  [ "$verdicts" = "APPROVED,CHANGES_REQUIRED" ]
}

@test "schema is permissive (no additionalProperties: false at root)" {
  local addl
  addl=$(jq '.additionalProperties // null' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json")
  [ "$addl" = "null" ]
}

@test "findings items require severity, file, description, fixed_code" {
  local req
  req=$(jq -r '.properties.findings.items.required | sort | join(",")' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json")
  [ "$req" = "description,file,fixed_code,severity" ]
}

@test "severity enum is critical | major" {
  local sev
  sev=$(jq -r '.properties.findings.items.properties.severity.enum | sort | join(",")' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json")
  [ "$sev" = "critical,major" ]
}

@test "previous_issues_status status enum has the 3 expected values" {
  local s
  s=$(jq -r '.properties.previous_issues_status.items.properties.status.enum | sort | join(",")' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json")
  [ "$s" = "fixed,not_fixed,rejected_with_valid_reason" ]
}

@test "schema has fabrication_check + iteration + auto_approved meta" {
  jq -e '.properties.fabrication_check' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json"
  jq -e '.properties.iteration' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json"
  jq -e '.properties.auto_approved' "$CONSTRUCT_ROOT/schemas/codex-review-finding.schema.json"
}
