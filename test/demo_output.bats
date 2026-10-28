#!/usr/bin/env bats
# Test --demo-output option

load test_helper

@test "--demo-output exits 0" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  [ "$status" -eq 0 ]
}

@test "--demo-output does not require a question argument" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  [ "$status" -eq 0 ]
  [[ "$output" != *"No question provided"* ]]
}

@test "--demo-output shows small response label" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"small response"* ]]
}

@test "--demo-output shows medium response label" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"medium response"* ]]
}

@test "--demo-output shows large response label" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"large response"* ]]
}

@test "--demo-output shows both stream and batch modes" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"stream mode"* ]]
  [[ "$output_clean" == *"batch mode"* ]]
}

@test "--demo-output --no-stream shows only batch mode" {
  run "$SCRIPT_PATH" --demo-output --no-stream --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" != *"stream mode"* ]]
  [[ "$output_clean" == *"batch mode"* ]]
}

@test "--demo-output includes Paris in answer content" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"Paris"* ]]
}

@test "--demo-output shows final status bars with checkmark" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  # Count checkmarks - should have one per size*mode combination
  local checkmark_count
  checkmark_count=$(echo "$output" | grep -c "✓" || true)
  [[ "$checkmark_count" -ge 3 ]]
}

@test "--demo-output shows stream info lines" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"lines"* ]]
  [[ "$output_clean" == *"chars"* ]]
  [[ "$output_clean" == *"chunks"* ]]
}

@test "--demo-output shows done status" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"done"* ]]
}

@test "--demo-output shows cost in final status" {
  run "$SCRIPT_PATH" --demo-output --no-pager
  output_clean=$(echo "$output" | strip_ansi)
  # Should have at least one cost formatted as $X.XXXX
  [[ "$output_clean" == *'$0.'* ]]
}
