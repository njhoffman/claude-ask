# BATS test helper for claude-ask tests

SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/bin/claude-ask"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

STUB_DIR="${BATS_TEST_DIRNAME}/stubs"

# Isolate every test: no real claude, sessions, logs or runtime files outside
# TEST_TEMP_DIR. Test files that define their own setup() call this first.
common_setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export SESSION_DIR="$TEST_TEMP_DIR/sessions"
  export XDG_RUNTIME_DIR="$TEST_TEMP_DIR/run"
  export XDG_STATE_HOME="$TEST_TEMP_DIR/state"
  mkdir -p "$SESSION_DIR" "$XDG_RUNTIME_DIR"
  export CLAUDE_ASK_BIN="$STUB_DIR/claude"
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/full_session.jsonl"
  unset CLAUDE_STUB_STDERR CLAUDE_STUB_EXIT CLAUDE_STUB_ARGS CLAUDE_STUB_STDIN CLAUDE_STUB_DELAY
  unset CLAUDE_STUB_LOG CLAUDE_STUB_FAIL_CALL CLAUDE_ASK_FORCE_INTERACTIVE
  export CLAUDE_ASK_DEMO_DELAY=0
}

setup() {
  common_setup
}

teardown() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Source claude-ask functions without executing the main logic.
# Sets _CLAUDE_ASK_SOURCED=1 so the script returns after defining functions.
# Requires a dummy positional arg or THEME_DEMO=1 to pass arg validation.
source_claude_ask() {
  export _CLAUDE_ASK_SOURCED=1
  # Provide a dummy question to pass the positional check
  source "$SCRIPT_PATH" "dummy" 2>/dev/null
  unset _CLAUDE_ASK_SOURCED
}

# Strip ANSI escape sequences from text for assertion matching.
strip_ansi() {
  sed 's/\x1b\[[0-9;]*[mK]//g; s/\x1b\[[0-9]*;[0-9]*[Hr]//g; s/\x1b\[\?25[hl]//g; s/\x1b\[[su]//g'
}

# Feed a stream-json file through the script's own process_stream_line, in
# the current shell, so the state variables can be checked directly.
# Takes a fixture name (in test/fixtures) or a path.
feed_stream() {
  local path="$1" line
  [[ "$path" == */* ]] || path="${FIXTURES_DIR}/${path}"
  reset_stream_state
  while IFS= read -r line; do
    process_stream_line "$line" || true
  done < "$path"
}

# Run a fixture through feed_stream and print the state as key=value lines.
# Usage: parsed=$(parse_fixture "full_session.jsonl")
# Then:  get_parsed model "$parsed"
parse_fixture() {
  source_claude_ask
  feed_stream "$1"
  echo "model=$model"
  echo "session_id=$session_id"
  echo "input_tokens=$input_tokens"
  echo "output_tokens=$output_tokens"
  echo "cost=$cost"
  echo "duration_ms=$duration_ms"
  echo "status=$status"
  echo "stream_error=$stream_error"
  echo "is_thinking=$is_thinking"
  echo "text_chunks=$text_chunks"
  echo "answer_text=$answer_text"
}

# Extract a variable from parse_fixture output
get_parsed() {
  local var="$1"
  local output="$2"
  echo "$output" | grep "^${var}=" | head -1 | cut -d= -f2-
}
