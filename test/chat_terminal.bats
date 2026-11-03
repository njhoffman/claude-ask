#!/usr/bin/env bats
# Test the chat at a real terminal (a pseudo-terminal): the prompt with the
# model and effort, and multi-line pastes

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  # The runner's own readline settings stay out of it
  export INPUTRC="$TEST_TEMP_DIR/inputrc"
  : > "$INPUTRC"
  PTY="$BATS_TEST_DIRNAME/helpers/pty_run.py"
}

# pty_chat STEP... [-- ARG...]: run the chat in a pseudo-terminal
pty_chat() {
  local steps=() args=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    steps+=("$1")
    shift
  done
  if [[ "${1:-}" == "--" ]]; then shift; args=("$@"); fi
  run python3 "$PTY" "${steps[@]}" -- "$SCRIPT_PATH" --no-pager "${args[@]}"
  output_clean=$(printf '%s' "$output" | strip_ansi | tr -d '\001\002\r')
}

@test "pty: a three-line paste is one question" {
  pty_chat 'expect:> ' 'send:line one\rline two\rline three\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF '| line one\nline two\nline three' "$CLAUDE_STUB_LOG"
  # The pasted lines show at the continuation prompt
  [[ "$output_clean" == *". line two"* ]]
}

@test "pty: a tab in a paste is kept, not taken for completion" {
  pty_chat 'expect:> ' 'send:def f():\r\treturn 1\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF "$(printf '| def f():\\n\treturn 1')" "$CLAUDE_STUB_LOG"
}

@test "pty: a paste that starts with /word or exit is still a question" {
  pty_chat 'expect:> ' 'send:/etc/hosts\rexit\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF '| /etc/hosts\nexit' "$CLAUDE_STUB_LOG"
}

@test "pty: lines typed one at a time are separate questions" {
  pty_chat 'expect:> ' 'send:first\r' 'expect:chunks' 'expect:> ' 'send:second\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
}

@test "pty: the prompt is plain before an answer, then shows its model" {
  pty_chat 'expect:> ' 'send:q\r' 'expect:chunks' 'expect:sonnet 4.5 > ' 'send:exit\r'
  [ "$status" -eq 0 ]
  [[ "$output_clean" == *"/help for commands"$'\n'"> q"* ]]
  [[ "$output_clean" == *"sonnet 4.5 > "* ]]
}

@test "pty: -e and -m show in the prompt from the start" {
  pty_chat 'expect:> ' 'send:exit\r' -- -e high -m opus
  [[ "$output_clean" == *"opus · high > "* ]]
}

@test "pty: after an answer to -m opus the prompt shows the model that answered" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/code_answer.jsonl"
  pty_chat 'expect:> ' 'send:q\r' 'expect:chunks' 'expect:opus 5.5 · low > ' 'send:exit\r' -- -m opus -e low
  [[ "$output_clean" == *"opus 5.5 · low > "* ]]
}

@test "pty: /effort and /model change the prompt" {
  pty_chat 'expect:> ' 'send:q\r' 'expect:sonnet 4.5 > ' 'send:/effort max\r' 'expect:sonnet 4.5 · max > ' \
    'send:/model haiku\r' 'expect:haiku · max > ' 'send:/model default\r' 'expect:model: default' 'sleep:0.3' 'send:exit\r'
  [[ "$output_clean" == *"haiku · max > "* ]]
  # The default model answered last, so it shows again after /model default
  [[ "$output_clean" == *$'model: default\nsonnet 4.5 · max > '* ]]
}

@test "pty: after /model default the model is unknown until the next answer" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/haiku_session.jsonl"
  pty_chat 'expect:> ' 'send:q\r' 'expect:haiku 4.5 > ' 'send:/model default\r' 'expect:model: default' 'sleep:0.3' 'send:exit\r' -- -m haiku
  [[ "$output_clean" == *$'model: default\n> '* ]]
}

@test "pty: --resume= shows the session's model in the prompt" {
  jq -n '{session_id: "old", name: "saved", question: "q", answer: "a", model: "claude-opus-5-5",
    timestamp: "2026-11-01T00:00:00Z",
    turns: [{question: "q", answer: "a", model: "claude-opus-5-5", effort: "high"}]}' > "$SESSION_DIR/saved.json"
  pty_chat 'expect:opus 5.5 · high > ' 'send:exit\r' -- --resume=saved
  [[ "$output_clean" == *"opus 5.5 · high > "* ]]
}

@test "pty: Tab completes a command and its argument" {
  pty_chat 'expect:> ' 'send:/eff\t' 'expect:/effort ' 'send:hi\t\r' 'expect:effort: high' 'send:exit\r'
  [ "$status" -eq 0 ]
  [[ "$output_clean" == *"effort: high"* ]]
  [[ "$output_clean" == *"high > "* ]]
}

@test "pty: Tab on an ambiguous prefix lists the matches" {
  pty_chat 'expect:> ' 'send:/e\t' 'expect:/effort /editor /exit' 'send:x\t\r'
  [ "$status" -eq 0 ]
  [[ "$output_clean" == *"/effort /editor /exit"* ]]
  # /ex completed to /exit, which ended the chat
  [ ! -s "${CLAUDE_STUB_LOG}" ]
}

@test "pty: Tab completes in vi mode too" {
  printf 'set editing-mode vi\n' > "$INPUTRC"
  pty_chat 'expect:> ' 'send:/the\t' 'expect:/theme ' 'send:pow\t\r' 'expect:theme: powerline' 'send:exit\r'
  [ "$status" -eq 0 ]
  [[ "$output_clean" == *"theme: powerline"* ]]
}

@test "pty: a tab in a pasted line after the first is never completed" {
  pty_chat 'expect:> ' 'send:look:\r/e\tx\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF "$(printf '| look:\\n/e\tx')" "$CLAUDE_STUB_LOG"
}

@test "pty: Ctrl-C at the prompt drops the line at once" {
  pty_chat 'expect:> ' 'send:abc' 'expect:> abc' 'send:\x03' 'expect:abc^C' 'send:xyz\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$status" -eq 0 ]
  # Only what was typed after Ctrl-C was asked
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF '| xyz' "$CLAUDE_STUB_LOG"
  ! grep -qF 'abc' "$CLAUDE_STUB_LOG"
}

@test "pty: Ctrl-C at the prompt works in vi mode" {
  printf 'set editing-mode vi\n' > "$INPUTRC"
  pty_chat 'expect:> ' 'send:abc' 'expect:> abc' 'send:\x03' 'expect:abc^C' 'send:xyz\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF '| xyz' "$CLAUDE_STUB_LOG"
}

@test "pty: Ctrl-C still stops an answer, and the chat goes on" {
  export CLAUDE_STUB_DELAY=0.4
  pty_chat 'expect:> ' 'send:q\r' 'expect:connecting' 'sleep:0.5' 'send:\x03' 'expect:(interrupted)' 'expect:> ' 'send:exit\r'
  [ "$status" -eq 0 ]
  [[ "$output_clean" == *"(interrupted)"* ]]
}

@test "pty: Ctrl-\\ at the prompt ends the chat and puts the intr key back" {
  run python3 "$PTY" 'expect:> ' 'send:\x1c' 'sleep:1.5' -- bash -c \
    "'$SCRIPT_PATH' --no-pager; echo status=\$?; stty -a | grep -o 'intr = [^;]*'"
  output_clean=$(printf '%s' "$output" | strip_ansi | tr -d '\001\002\r')
  [[ "$output_clean" == *"status=131"* ]]
  [[ "$output_clean" == *"intr = ^C"* ]]
}

@test "pty: the intr key is put back when the chat is killed at the prompt" {
  run python3 "$PTY" 'expect:> ' 'sleep:2.5' -- bash -c \
    "timeout --foreground -s TERM 1 '$SCRIPT_PATH' --no-pager; stty -a | grep -o 'intr = [^;]*'"
  output_clean=$(printf '%s' "$output" | strip_ansi | tr -d '\001\002\r')
  [[ "$output_clean" == *"intr = ^C"* ]]
}
