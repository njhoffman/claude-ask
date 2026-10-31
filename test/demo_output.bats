#!/usr/bin/env bats
# Test --demo-output option

load test_helper

# The demo is run once for the whole file; each test checks its output
setup_file() {
  export CLAUDE_ASK_DEMO_DELAY=0
  export XDG_RUNTIME_DIR="$BATS_FILE_TMPDIR"
  local status=0
  "$BATS_TEST_DIRNAME/../bin/claude-ask" --demo-output --no-pager \
    > "$BATS_FILE_TMPDIR/demo.out" 2>&1 || status=$?
  echo "$status" > "$BATS_FILE_TMPDIR/demo.status"
}

# Load the shared demo run into $status and $output, like `run` would
load_demo() {
  status=$(< "$BATS_FILE_TMPDIR/demo.status")
  output=$(< "$BATS_FILE_TMPDIR/demo.out")
}

@test "--demo-output exits 0" {
  load_demo
  [ "$status" -eq 0 ]
}

@test "--demo-output does not require a question argument" {
  load_demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"No question provided"* ]]
}

@test "--demo-output shows small response label" {
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"small response"* ]]
}

@test "--demo-output shows medium response label" {
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"medium response"* ]]
}

@test "--demo-output shows large response label" {
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"large response"* ]]
}

@test "--demo-output shows both stream and batch modes" {
  load_demo
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
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"Paris"* ]]
}

@test "--demo-output shows final status bars with checkmark" {
  load_demo
  # Count checkmarks - should have one per size*mode combination
  local checkmark_count
  checkmark_count=$(echo "$output" | grep -c "✓" || true)
  [[ "$checkmark_count" -ge 3 ]]
}

@test "--demo-output shows stream info lines" {
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"lines"* ]]
  [[ "$output_clean" == *"chars"* ]]
  [[ "$output_clean" == *"chunks"* ]]
}

@test "--demo-output shows done status" {
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"done"* ]]
}

@test "--demo-output shows cost in final status" {
  load_demo
  output_clean=$(echo "$output" | strip_ansi)
  # Should have at least one cost formatted as $X.XXXX
  [[ "$output_clean" == *'$0.'* ]]
}

@test "--demo-output with a pager streams through it" {
  run "$SCRIPT_PATH" --demo-output --pager "sed 's/^/> /'"
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"> The capital of France is **Paris**."* ]]
}
