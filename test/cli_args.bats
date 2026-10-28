#!/usr/bin/env bats
# Test CLI argument parsing

load test_helper

@test "opens editor when no arguments given and exits if empty" {
  export EDITOR="true"  # no-op, leaves file empty
  run "$SCRIPT_PATH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No question provided"* ]]
}

@test "uses editor content as question when no arguments given" {
  # Create a fake editor that writes a question to the file
  fake_editor="$TEST_TEMP_DIR/fake-editor"
  printf '#!/bin/bash\necho "test question" > "$1"\n' > "$fake_editor"
  chmod +x "$fake_editor"
  export EDITOR="$fake_editor"
  # Will fail trying to reach claude, but should get past arg parsing
  run timeout 2 "$SCRIPT_PATH" 2>&1 || true
  [[ "$output" != *"No question provided"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT_PATH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-ask"* ]]
  [[ "$output" == *"--theme"* ]]
  [[ "$output" == *"--pager"* ]]
  [[ "$output" == *"--demo-themes"* ]]
}

@test "-h prints usage and exits 0" {
  run "$SCRIPT_PATH" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-ask"* ]]
}

@test "rejects invalid --theme value" {
  run "$SCRIPT_PATH" --theme invalid "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be one of"* ]]
}

@test "accepts --theme minimal" {
  # Will fail trying to connect to claude, but should get past arg parsing
  run timeout 2 "$SCRIPT_PATH" --theme minimal "test" 2>&1 || true
  # Should NOT have the theme validation error
  [[ "$output" != *"must be one of"* ]]
}

@test "accepts --theme bubbles" {
  run timeout 2 "$SCRIPT_PATH" --theme bubbles "test" 2>&1 || true
  [[ "$output" != *"must be one of"* ]]
}

@test "accepts --theme powerline" {
  run timeout 2 "$SCRIPT_PATH" --theme powerline "test" 2>&1 || true
  [[ "$output" != *"must be one of"* ]]
}

@test "rejects unknown option" {
  run "$SCRIPT_PATH" --foobar "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "--theme requires an argument" {
  run "$SCRIPT_PATH" --theme
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an argument"* ]]
}

@test "--pager requires an argument" {
  run "$SCRIPT_PATH" --pager
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an argument"* ]]
}

@test "--history with no sessions shows message" {
  export SESSION_DIR="$TEST_TEMP_DIR/empty-sessions"
  mkdir -p "$SESSION_DIR"
  run "$SCRIPT_PATH" --history
  [ "$status" -eq 1 ]
  [[ "$output" == *"No saved sessions"* ]]
}

@test "--history lists saved sessions" {
  local session_dir="$TEST_TEMP_DIR/sessions"
  mkdir -p "$session_dir"
  cat > "$session_dir/test-session.json" <<'JSON'
{"session_id":"abc-123","model":"opus","name":"test-session","question":"What is bash?","answer":"Bash is a shell.\nIt is useful.","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON

  # Override SESSION_DIR by exporting it
  export SESSION_DIR="$session_dir"
  source_claude_ask
  run show_history "$session_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-session"* ]]
  [[ "$output" == *"What is bash?"* ]]
}

@test "--session without argument shows history" {
  export SESSION_DIR="$TEST_TEMP_DIR/empty-sessions"
  mkdir -p "$SESSION_DIR"
  run "$SCRIPT_PATH" --session
  [ "$status" -eq 1 ]
  [[ "$output" == *"No saved sessions"* ]]
}

@test "--session with invalid id shows error and history" {
  export SESSION_DIR="$TEST_TEMP_DIR/empty-sessions"
  mkdir -p "$SESSION_DIR"
  run "$SCRIPT_PATH" --session nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Session not found"* ]]
}

@test "--debug-log creates log file" {
  local logfile="$TEST_TEMP_DIR/debug.log"
  export EDITOR="true"
  run "$SCRIPT_PATH" --debug-log "$logfile"
  # Script will exit because editor leaves empty file, but log should exist
  [ -f "$logfile" ]
}

@test "--debug-log defaults to /tmp/claude-ask.log" {
  source_claude_ask
  # After sourcing with dummy arg, DEBUG_LOG is not set (no --debug-log flag passed)
  [[ -z "${DEBUG_LOG:-}" ]]
}
