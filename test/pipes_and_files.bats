#!/usr/bin/env bats
# Test piped input, output to a file or pipe, what is kept of an answer and
# who can read it

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  PTY="$BATS_TEST_DIRNAME/helpers/pty_run.py"
}

# What claude was asked, one call per line (as the stub logs it)
asked() {
  sed 's/^[^|]*| //' "$CLAUDE_STUB_LOG"
}

@test "piped input follows the question" {
  run "$SCRIPT_PATH" --no-pager "summarize" < <(printf 'DATA\nMORE\n')
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  [ "$(asked)" = 'summarize\n\nDATA\nMORE' ]
}

@test "a file on stdin follows the question too" {
  printf 'FROM FILE\n' > "$TEST_TEMP_DIR/in"
  run "$SCRIPT_PATH" --no-pager "summarize" < "$TEST_TEMP_DIR/in"
  [ "$(asked)" = 'summarize\n\nFROM FILE' ]
}

@test "/dev/null and an empty pipe add nothing to the question" {
  run "$SCRIPT_PATH" --no-pager "alone" < /dev/null
  [ "$(asked)" = 'alone' ]
  : > "$CLAUDE_STUB_LOG"
  run "$SCRIPT_PATH" --no-pager "alone" < <(printf ' \n')
  [ "$(asked)" = 'alone' ]
}

@test "a stdin that stays open is waited for, and says so" {
  run timeout 3 "$SCRIPT_PATH" --no-pager "q" < <(sleep 5)
  [ "$status" -eq 124 ]
  [[ "$output" == *"waiting for piped input"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "a slow pipe gets through" {
  run "$SCRIPT_PATH" --no-pager "q" < <(sleep 2.5; printf 'late\n')
  [ "$status" -eq 0 ]
  [ "$(asked)" = 'q\n\nlate' ]
}

@test "--split and --popup carry piped input in the question file" {
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0" CLAUDE_STUB_TMUX_QUESTION="$TEST_TEMP_DIR/question"
  run "$SCRIPT_PATH" --split "review" < <(printf 'DIFF')
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_STUB_TMUX_QUESTION")" = $'review\n\nDIFF' ]
}

@test "-i with a pipe and no terminal is refused, nothing asked" {
  run setsid "$SCRIPT_PATH" --no-pager -i < <(printf 'a\nb\nc\n')
  [ "$status" -eq 1 ]
  [[ "$output" == *"-i needs a terminal"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
  run setsid "$SCRIPT_PATH" --no-pager -i "review" < <(printf 'a\nb\n')
  [ "$status" -eq 1 ]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "-i with a pipe: one question from the pipe, then a chat on the terminal" {
  run python3 "$PTY" 'expect:> ' 'send:typed\r' 'expect:turn 2' 'expect:> ' 'send:exit\r' -- \
    bash -c "printf 'a\nb\nc\n' | '$SCRIPT_PATH' --no-pager -i 'review'"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  [ "$(asked | head -1)" = 'review\n\na\nb\nc' ]
  [ "$(asked | tail -1)" = 'typed' ]
}

# No stand-in for a terminal, and none on stdout or stderr
plain() {
  env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" "$@"
}

@test "stdout not a terminal: only the answer, with its newline" {
  plain "q" > "$TEST_TEMP_DIR/out" 2> "$TEST_TEMP_DIR/err"
  [ "$(cat "$TEST_TEMP_DIR/out")" = "The capital of France is **Paris**." ]
  [ "$(tail -c 1 "$TEST_TEMP_DIR/out" | od -An -c | tr -d ' ')" = '\n' ]
  [ ! -s "$TEST_TEMP_DIR/err" ]
  ! grep -q $'\e' "$TEST_TEMP_DIR/out"
}

@test "stdout not a terminal: the default pager is not used, a --pager is" {
  export CLAUDE_ASK_PAGER="sed s/^/DEFAULT:/"
  [ "$(plain "q" 2> /dev/null)" = "The capital of France is **Paris**." ]
  run env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" --pager "sed s/^/CHOSEN:/" "q"
  [[ "$output" == "CHOSEN:The capital"* ]]
}

@test "stdout not a terminal: --no-stream, a failure and -r stay clean" {
  [ "$(plain --no-stream "q" 2> /dev/null)" = "The capital of France is **Paris**." ]
  plain "first" > /dev/null 2>&1
  # The new answer only, not the last one replayed
  [ "$(plain -r "second" 2> /dev/null | grep -c capital)" -eq 1 ]
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/result_error.jsonl"
  run --separate-stderr env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" "q"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Invalid API key"* ]]
  [[ "$stderr" != *$'\e'* ]]
}

@test "--session to a file: the question and answer, no escapes" {
  plain "q" > /dev/null 2>&1
  plain --session 1 > "$TEST_TEMP_DIR/out" 2> /dev/null
  grep -q '^> q$' "$TEST_TEMP_DIR/out"
  grep -q 'Paris' "$TEST_TEMP_DIR/out"
  ! grep -q $'\e' "$TEST_TEMP_DIR/out"
}

@test "stdout a file, stderr a terminal: the bar is on the terminal" {
  run python3 "$PTY" -- bash -c "CLAUDE_ASK_FORCE_TTY= '$SCRIPT_PATH' q > '$TEST_TEMP_DIR/out'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sonnet 4.5"* ]]
  [ "$(cat "$TEST_TEMP_DIR/out")" = "The capital of France is **Paris**." ]
}

@test "a reader that goes away ends the run, and it cleans up" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/full_session.jsonl"
  run bash -c "env -u CLAUDE_ASK_FORCE_TTY '$SCRIPT_PATH' q 2> /dev/null | true"
  [ "$status" -eq 0 ]
  sleep 0.2
  [ -z "$(ls -A "$XDG_RUNTIME_DIR")" ]
}

@test "NO_COLOR: no colors in the bar or the notes" {
  export NO_COLOR=1
  run "$SCRIPT_PATH" --no-pager --theme powerline "q"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e[38;2'* ]]
  [[ "$output" != *$'\e[48;2'* ]]
  [[ "$output" == *"sonnet 4.5"* ]]
  export NO_COLOR=""
  run "$SCRIPT_PATH" --no-pager "q"
  [[ "$output" == *$'\e[38;2'* ]]
}

@test "messages join with a blank line, events of one message do not" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/two_messages.jsonl"
  local want=$'Let me check that.\n\nThe answer is 42.'
  [ "$(env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" "q" 2> /dev/null)" = "$want" ]
  [ "$(jq -r .answer "$SESSION_DIR/q.json")" = "$want" ]
  [ "$(jq -r '.turns[0].answer' "$SESSION_DIR/q.json")" = "$want" ]
}

@test "-y copies every message of the answer" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/two_messages.jsonl"
  run "$SCRIPT_PATH" --no-pager -y "q"
  [ "$(cat "$TEST_TEMP_DIR/clipboard")" = $'Let me check that.\n\nThe answer is 42.' ]
}

@test "an error result with no text is still the saved answer" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/result_error.jsonl"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$(jq -r .answer "$SESSION_DIR/q.json")" = "Invalid API key" ]
}

@test "control characters never reach the terminal; tab and newline do" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/escape_answer.jsonl"
  plain "q" > "$TEST_TEMP_DIR/out" 2> /dev/null
  ! grep -q $'\e' "$TEST_TEMP_DIR/out"
  ! grep -q $'\a' "$TEST_TEMP_DIR/out"
  ! LC_ALL=C grep -q $'\xc2\x9b' "$TEST_TEMP_DIR/out"
  ! grep -q $'\r' "$TEST_TEMP_DIR/out"
  grep -q "hello ]52;c;ZXZpbA== world" "$TEST_TEMP_DIR/out"
  grep -q $'^\ttabbed' "$TEST_TEMP_DIR/out"
}

@test "control characters in a saved session are not replayed either" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/escape_answer.jsonl"
  run "$SCRIPT_PATH" --no-pager $'evil \e]0;title\a question'
  local name
  name=$(basename "$(ls "$SESSION_DIR"/*.json)" .json)
  plain --session "$name" > "$TEST_TEMP_DIR/out" 2> /dev/null
  ! grep -q $'\e' "$TEST_TEMP_DIR/out"
  grep -q 'evil ]0;title question' "$TEST_TEMP_DIR/out"
  plain --history > "$TEST_TEMP_DIR/out" 2> /dev/null
  ! grep -q $'\e' "$TEST_TEMP_DIR/out"
  CLAUDE_ASK_CLIPBOARD="cat > '$TEST_TEMP_DIR/clip2'" plain -y --session "$name" > /dev/null 2>&1
  ! grep -q $'\e' "$TEST_TEMP_DIR/clip2"
}

@test "session files are private, whatever the umask" {
  umask 022
  run "$SCRIPT_PATH" --no-pager --save-raw "q"
  [ "$(stat -c %a "$SESSION_DIR/q.json")" = 600 ]
  [ "$(stat -c %a "$SESSION_DIR/q.jsonl")" = 600 ]
  # A later turn tightens a file that was not
  chmod 644 "$SESSION_DIR/q.json"
  run "$SCRIPT_PATH" --no-pager --resume=q "more"
  [ "$(stat -c %a "$SESSION_DIR/q.json")" = 600 ]
}

@test "a new session directory is private, a chosen one is left alone" {
  export SESSION_DIR="$TEST_TEMP_DIR/new/sessions"
  umask 022
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$(stat -c %a "$SESSION_DIR")" = 700 ]
  export SESSION_DIR="$TEST_TEMP_DIR/mine"
  mkdir -m 755 "$SESSION_DIR"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$(stat -c %a "$SESSION_DIR")" = 755 ]
}

@test "the default session directory is tightened" {
  export HOME="$TEST_TEMP_DIR/home"
  unset SESSION_DIR
  unset XDG_DATA_HOME
  mkdir -p -m 755 "$HOME/.local/share/claude-ask/sessions"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$(stat -c %a "$HOME/.local/share/claude-ask/sessions")" = 700 ]
}

@test "claude's tools keep the user's umask" {
  cat > "$TEST_TEMP_DIR/umask-claude" <<STUB
#!/bin/bash
umask > "$TEST_TEMP_DIR/seen-umask"
cat "$FIXTURES_DIR/full_session.jsonl"
STUB
  chmod +x "$TEST_TEMP_DIR/umask-claude"
  umask 022
  CLAUDE_ASK_BIN="$TEST_TEMP_DIR/umask-claude" run "$SCRIPT_PATH" --no-pager "q"
  [ "$(cat "$TEST_TEMP_DIR/seen-umask")" = "0022" ]
}
