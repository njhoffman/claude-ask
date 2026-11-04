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

@test "default pager that is not installed falls back to plain text" {
  export CLAUDE_ASK_PAGER="claude-ask-no-such-pager --pager less"
  run "$SCRIPT_PATH" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"The capital of France is **Paris**."* ]]
}

@test "CLAUDE_ASK_PAGER sets the default pager" {
  export CLAUDE_ASK_PAGER="sed 's/^/>> /'"
  run "$SCRIPT_PATH" "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *">> The capital of France"* ]]
}

@test "the pager gets the terminal width in COLUMNS while streaming" {
  unset COLUMNS
  run script -qec "stty cols 123 rows 40; '$SCRIPT_PATH' --pager 'echo cols=\$COLUMNS; cat > /dev/null' test < /dev/null" /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"cols=123"* ]]
}

@test "an exported COLUMNS is passed to the pager unchanged" {
  export COLUMNS=77
  run "$SCRIPT_PATH" --pager 'echo cols=$COLUMNS; cat > /dev/null' "test"
  [[ "$output" == *"cols=77"* ]]
}

@test "the default nvcat pager renders the answer" {
  command -v nvcat > /dev/null || skip "nvcat not installed"
  unset CLAUDE_ASK_PAGER
  export COLUMNS=80
  run "$SCRIPT_PATH" "test"
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  # Rendered: the ** markers are gone, the text is there
  [[ "$output_clean" == *"Paris"* ]]
  [[ "$output_clean" != *"**Paris**"* ]]
}

@test "leaves no runtime files behind" {
  run "$SCRIPT_PATH" "test" --no-pager
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$XDG_RUNTIME_DIR")" ]
}

@test "a SIGTERM mid-answer still removes the runtime files" {
  export CLAUDE_STUB_DELAY=1
  "$SCRIPT_PATH" "test" --no-pager > /dev/null 2>&1 &
  local pid=$!
  # The runtime dir exists once the run has started
  for _ in $(seq 50); do [ -n "$(ls -A "$XDG_RUNTIME_DIR")" ] && break; sleep 0.1; done
  [ -n "$(ls -A "$XDG_RUNTIME_DIR")" ]
  sleep 0.3
  kill -TERM "$pid"
  local rc=0
  wait "$pid" || rc=$?
  [ "$rc" -eq 143 ]
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

@test "the script finds bash on PATH and stops below bash 5" {
  [ "$(head -1 "$SCRIPT_PATH")" = "#!/usr/bin/env bash" ]
  source_claude_ask
  run require_bash 5
  [ "$status" -eq 0 ]
  run require_bash 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs bash 5 or newer, and this is bash 3"* ]]
}

@test "the bash check comes before anything newer than 3.2" {
  # Only the shebang, comments, set and blank lines may come before it
  local first
  first=$(grep -n -m1 -vE '^(#.*|set -euo pipefail|)$' "$SCRIPT_PATH" | cut -d: -f2)
  [ "$first" = "require_bash() {" ]
}

# --help at a terminal
help_in_pty() {
  run python3 "$BATS_TEST_DIRNAME/helpers/pty_run.py" -- "$SCRIPT_PATH" --help
}

@test "--help at a terminal has color, and the same text" {
  export TERM=xterm-256color
  unset NO_COLOR CLAUDE_ASK_COLORS
  local plain
  plain=$("$SCRIPT_PATH" --help)
  [[ "$plain" != *$'\e'* ]]
  help_in_pty
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[1;33mOptions'* ]]
  [[ "$output" == *$'\e[1;33mExamples:'* ]]
  [[ "$output" == *$'\e[36m--theme THEME\e[0m '* ]]
  [[ "$output" == *$'\e[36m-e, --effort LEVEL\e[0m '* ]]
  # Only the option: not the first capital of what describes it
  [[ "$output" == *$'\e[36m--debug-log[=FILE]\e[0m'*' Write debug'* ]]
  [[ "$output" == *$'\e[36m--split[=h|v]\e[0m'* ]]
  [[ "$output" == *$'\e[36m--resume=ID|N\e[0m'* ]]
  [[ "$output" == *$'\e[36m--session [ID|N]\e[0m'* ]]
  [[ "$output" == *$'\e[32mSESSION_DIR\e[0m'* ]]
  [[ "$output" == *$'\e[32mVISUAL, EDITOR\e[0m'* ]]
  [[ "$output" == *$'\e[2m'*"# start a chat"$'\e[0m'* ]]
  # Take the colors away and it is the plain text, to the character
  local stripped
  stripped=$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r')
  [ "$stripped" = "$plain" ]
}

@test "--help has no color with NO_COLOR, CLAUDE_ASK_COLORS=none or a dumb terminal" {
  export TERM=xterm-256color
  NO_COLOR=1 help_in_pty
  [[ "$output" != *$'\e['* ]]
  CLAUDE_ASK_COLORS=none help_in_pty
  [[ "$output" != *$'\e['* ]]
  TERM=dumb help_in_pty
  [[ "$output" != *$'\e['* ]]
}

@test "--help lines up its columns, one line for each thing" {
  local help
  help=$(env -u CLAUDE_ASK_COLUMNS "$SCRIPT_PATH" --help)
  # Options: where the description starts is the same on every line
  [ "$(sed -n '/^Options/,/^Examples:/p' <<< "$help" | grep -cE '^ +-')" -gt 20 ]
  sed -n '/^Options/,/^Examples:/p' <<< "$help" | grep -E '^ +-' | python3 -c '
import re, sys
starts = {re.search(r"\S  +(\S)", l).start(1) for l in sys.stdin}
assert len(starts) == 1, starts'
  sed -n '/^Environment:/,$p' <<< "$help" | tail -n +2 | python3 -c '
import re, sys
starts = {re.search(r"\S  +(\S)", l).start(1) for l in sys.stdin}
assert len(starts) == 1, starts'
  sed -n '/^Examples:/,/^Environment:/p' <<< "$help" | grep '  # ' | python3 -c '
import sys
starts = {l.index("  # ") for l in sys.stdin}
assert len(starts) == 1, starts'
  # Long options under the long ones, and no continuation lines anywhere
  [[ "$help" == *$'\n      --popup '* ]]
  [[ "$help" == *$'\n  -i, --interactive '* ]]
  ! sed -n '/^Options/,/^Examples:/p' <<< "$help" | grep -E '^ +[^ -]'
  ! sed -n '/^Environment:/,$p' <<< "$help" | grep -E '^   '
}

# help_at WIDTH: --help as a terminal of that width shows it, without color codes,
# and with no carriage returns
help_at() {
  PTY_SIZE="${1}x60" TERM=xterm-256color run python3 "$BATS_TEST_DIRNAME/helpers/pty_run.py" -- env -u CLAUDE_ASK_COLUMNS "$SCRIPT_PATH" --help
  [ "$status" -eq 0 ]
  help_text=$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r')
}

@test "--help wraps long descriptions under their own column" {
  help_at 80
  # Nothing but examples goes past the width
  sed '/^Examples:/,/^Environment:/d' <<< "$help_text" | awk 'length($0) > 80 { bad = 1 } END { exit bad }'
  # Where the options' descriptions start, and every wrapped line starts there too
  local options col
  options=$(sed -n '/^Options/,/^Examples:/p' <<< "$help_text" | sed '1d;$d' | grep -v '^$')
  col=$(python3 -c '
import re, sys
lines = sys.stdin.read().splitlines()
col = re.search(r"\S  +(\S)", lines[0]).start(1)
for l in lines:
    if re.match(r" +-", l) and re.search(r"\S  +(\S)", l):
        assert re.search(r"\S  +(\S)", l).start(1) == col, l
    else:
        assert len(l) - len(l.lstrip()) == col, l
print(col)' <<< "$options")
  [ "$col" -gt 20 ]
  # Some did wrap, and the variables likewise
  [ "$(grep -cE "^ {$col}[^ ]" <<< "$options")" -gt 3 ]
  sed -n '/^Environment:/,$p' <<< "$help_text" | sed '1d' | python3 -c '
import re, sys
lines = [l for l in sys.stdin.read().split("\n") if l]
col = re.search(r"\S  +(\S)", lines[0]).start(1)
for l in lines:
    if not l.startswith(" " * col):
        assert re.search(r"\S  +(\S)", l).start(1) == col, l'
}

@test "--help keeps every word when it wraps, and the examples whole" {
  local whole
  whole=$(env -u CLAUDE_ASK_COLUMNS "$SCRIPT_PATH" --help)
  help_at 60
  [ "$(tr -s ' \n' ' ' <<< "$help_text")" = "$(tr -s ' \n' ' ' <<< "$whole")" ]
  grep -qx '  claude-ask -Y "A bash loop over lines of a file"  # copy the code' <<< "$help_text"
}

@test "--help keeps a wide terminal on one line each" {
  local whole
  whole=$(env -u CLAUDE_ASK_COLUMNS "$SCRIPT_PATH" --help)
  help_at 1000
  [ "$help_text" = "$whole" ]
}

@test "--help in a very narrow terminal falls back to a small indent" {
  help_at 40
  sed -n '/^Options/,/^Examples:/p' <<< "$help_text" | grep -q '^        Keep the chat open'
  sed -n '/^Options/,/^Examples:/p' <<< "$help_text" | grep -q '^  -i, --interactive *$'
  # Only the heading, which stays one line, and two paths with no place to break
  sed '/^Examples:/,/^Environment:/d' <<< "$help_text" | awk 'length($0) > 40 { n++ } END { exit n > 3 }'
}

@test "--help to a pipe stays whole unless a width is given; color does not count" {
  run env -u CLAUDE_ASK_COLUMNS "$SCRIPT_PATH" --help
  [[ "$output" == *"Continue the most recent saved session (with a question: ask it there; without: chat there)"* ]]
  run env CLAUDE_ASK_COLUMNS=70 "$SCRIPT_PATH" --help
  [[ "$output" != *"Continue the most recent saved session (with a question: ask it there; without: chat there)"* ]]
  sed '/^Examples:/,/^Environment:/d' <<< "$output" | awk 'length($0) > 70 { bad = 1 } END { exit bad }'
  # With color at the same width: the same line breaks
  local plain="$output"
  CLAUDE_ASK_COLUMNS=70 TERM=xterm-256color run python3 "$BATS_TEST_DIRNAME/helpers/pty_run.py" -- "$SCRIPT_PATH" --help
  [[ "$output" == *$'\e[36m'* ]]
  [ "$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r')" = "$plain" ]
}

@test "--help with NO_COLOR at a terminal still fits the width" {
  NO_COLOR=1 CLAUDE_ASK_COLUMNS=70 TERM=xterm-256color run python3 "$BATS_TEST_DIRNAME/helpers/pty_run.py" -- "$SCRIPT_PATH" --help
  [[ "$output" != *$'\e['* ]]
  sed '/^Examples:/,/^Environment:/d' <<< "$(tr -d '\r' <<< "$output")" | awk 'length($0) > 70 { bad = 1 } END { exit bad }'
}

@test "--help: a word too long for the column moves the entry to the small indent" {
  CLAUDE_ASK_COLUMNS=60 run "$SCRIPT_PATH" --help
  [[ "$output" == *$'\n  SESSION_DIR\n        Where sessions are saved'* ]]
  # Nothing past the width, or under the names' column
  sed '/^Examples:/,/^Environment:/d' <<< "$output" | grep -v '^Options' | awk 'length($0) > 60 { bad = 1 } END { exit bad }'
}

@test "--version: the script and VERSION agree, and a copy of the script knows" {
  run "$SCRIPT_PATH" --version
  [ "$output" = "claude-ask $(cat "$SCRIPT_DIR/VERSION")" ]
  mkdir "$TEST_TEMP_DIR/alone"
  cp "$SCRIPT_PATH" "$TEST_TEMP_DIR/alone/claude-ask"
  run "$TEST_TEMP_DIR/alone/claude-ask" --version
  [ "$output" = "claude-ask $(cat "$SCRIPT_DIR/VERSION")" ]
}

@test "no controlling terminal: nothing about /dev/tty on stderr" {
  # stdout and stderr to files, in a new session with no terminal
  unset CLAUDE_ASK_COLUMNS COLUMNS
  setsid -w env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" --pager cat "q" > "$TEST_TEMP_DIR/out" 2> "$TEST_TEMP_DIR/err"
  [ ! -s "$TEST_TEMP_DIR/err" ]
  grep -q 'capital of France' "$TEST_TEMP_DIR/out"
}
