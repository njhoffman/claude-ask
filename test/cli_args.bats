#!/usr/bin/env bats
# Test CLI argument parsing

bats_require_minimum_version 1.5.0

load test_helper

@test "no question and empty piped input is an error" {
  run "$SCRIPT_PATH" --no-pager < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"No question provided"* ]]
}

@test "piped input with no question is asked once, not as a chat" {
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  run "$SCRIPT_PATH" --no-pager < <(printf 'line one\nline two\n')
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF '| line one\nline two' "$CLAUDE_STUB_LOG"
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

@test "accepts --theme minimal and renders the answer" {
  run "$SCRIPT_PATH" --no-pager --theme minimal "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paris"* ]]
  [[ "$output" == *"sonnet"* ]]
}

@test "accepts --theme bubbles" {
  run "$SCRIPT_PATH" --no-pager --theme bubbles "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\ue0b6'* ]]
}

@test "accepts --theme powerline" {
  run "$SCRIPT_PATH" --no-pager --theme powerline "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"░▒▓"* ]]
}

# ---------------------------------------------------------------------------
# A full run against the stub claude
# ---------------------------------------------------------------------------
@test "passes the question to claude on stdin and saves the session" {
  export CLAUDE_STUB_ARGS="$TEST_TEMP_DIR/claude-args"
  export CLAUDE_STUB_STDIN="$TEST_TEMP_DIR/claude-stdin"
  run "$SCRIPT_PATH" --no-pager "What is the capital of France?"
  [ "$status" -eq 0 ]
  grep -qx "What is the capital of France?" "$CLAUDE_STUB_STDIN"
  grep -qx "stream-json" "$CLAUDE_STUB_ARGS"
  ! grep -q "capital" "$CLAUDE_STUB_ARGS"
  local file="$SESSION_DIR/what-is-the-capital-of-france.json"
  [ -f "$file" ]
  [ "$(jq -r '.question' "$file")" = "What is the capital of France?" ]
}

@test "--no-stream renders the whole answer at the end" {
  run "$SCRIPT_PATH" --no-pager --no-stream "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paris"* ]]
}

@test "streams through a pager command" {
  run "$SCRIPT_PATH" --pager "sed 's/^/> /'" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"> The capital of France is **Paris**."* ]]
}

@test "--pager keeps quoted arguments intact" {
  run "$SCRIPT_PATH" --no-stream --pager "sed 's/Paris/the city of light/'" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the city of light"* ]]
}

@test "a question starting with - is not read as an option" {
  export CLAUDE_STUB_ARGS="$TEST_TEMP_DIR/claude-args"
  export CLAUDE_STUB_STDIN="$TEST_TEMP_DIR/claude-stdin"
  run "$SCRIPT_PATH" --no-pager -- "-v explain this"
  [ "$status" -eq 0 ]
  grep -qx -- "-v explain this" "$CLAUDE_STUB_STDIN"
  ! grep -qx -- "-v" "$CLAUDE_STUB_ARGS"
}

@test "--save-raw saves the raw stream beside the parsed session" {
  run "$SCRIPT_PATH" --no-pager --save-raw "raw question"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.question' "$SESSION_DIR/raw-question.json")" = "raw question" ]
  cmp "$SESSION_DIR/raw-question.jsonl" "$FIXTURES_DIR/full_session.jsonl"
  run "$SCRIPT_PATH" --history
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c "raw-question")" -eq 1 ]
  run "$SCRIPT_PATH" --no-pager --session raw-question
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paris"* ]]
}

@test "a pager line written in parts does not stall the stream" {
  # The pager prints a partial line, then holds it open until its input ends;
  # a blocking read of that line would never return
  export CLAUDE_STUB_DELAY=0.2
  run timeout 10 "$SCRIPT_PATH" --pager "printf 'partial line'; cat > /dev/null" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"partial line"* ]]
}

@test "--version prints the VERSION file" {
  run "$SCRIPT_PATH" --version
  [ "$status" -eq 0 ]
  [ "$output" = "claude-ask $(cat "$SCRIPT_DIR/VERSION")" ]
}

@test "--version works through a symlink" {
  ln -s "$SCRIPT_PATH" "$TEST_TEMP_DIR/claude-ask"
  run "$TEST_TEMP_DIR/claude-ask" --version
  [ "$output" = "claude-ask $(cat "$SCRIPT_DIR/VERSION")" ]
}

@test "leaves no runtime files behind" {
  run "$SCRIPT_PATH" "test" --no-pager
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$XDG_RUNTIME_DIR")" ]
}

# ---------------------------------------------------------------------------
# Errors from claude
# ---------------------------------------------------------------------------
@test "reports a missing claude command" {
  export CLAUDE_ASK_BIN="claude-ask-no-such-command"
  run -127 "$SCRIPT_PATH" --no-pager "test"
  [[ "$output" == *"required command not found: claude-ask-no-such-command"* ]]
}

@test "reports claude's exit status and stderr" {
  export CLAUDE_STUB_FIXTURE=""
  export CLAUDE_STUB_EXIT=2
  export CLAUDE_STUB_STDERR="Not logged in"
  run "$SCRIPT_PATH" --no-pager "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exited with status 2"* ]]
  [[ "$output" == *"Not logged in"* ]]
  [ -z "$(ls -A "$SESSION_DIR")" ]
}

@test "reports an error result and saves it in the session" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/result_error.jsonl"
  run "$SCRIPT_PATH" --no-pager "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude-ask: Invalid API key"* ]]
  [ "$(jq -r '.is_error' "$SESSION_DIR/test.json")" = "true" ]
}

@test "reports a stream that ends without a result" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/text_chunk.jsonl"
  run "$SCRIPT_PATH" --no-pager "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ended without a result"* ]]
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

@test "--debug-log=FILE writes to FILE" {
  local logfile="$TEST_TEMP_DIR/logs/debug.log"
  run "$SCRIPT_PATH" --no-pager --debug-log="$logfile" "test"
  [ "$status" -eq 0 ]
  grep -q "args parsed" "$logfile"
}

@test "--debug-log uses the default file and keeps the question" {
  run "$SCRIPT_PATH" --no-pager --debug-log "What is 2+2?"
  [ "$status" -eq 0 ]
  grep -q "args parsed" "$XDG_STATE_HOME/claude-ask/debug.log"
  [ -f "$SESSION_DIR/what-is-2-2.json" ]
}

@test "--debug-log= without a file name is an error" {
  run "$SCRIPT_PATH" --debug-log= "test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a file name"* ]]
}
