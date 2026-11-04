#!/usr/bin/env bats
# Test option forms, tool activity, the editor, session files that are not
# valid, where sessions live, and how --history and --session show them

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  PTY="$BATS_TEST_DIRNAME/helpers/pty_run.py"
  unset XDG_DATA_HOME
  # less stops to warn when there is no TERM (CI has none)
  export TERM=xterm-256color
}

@test "options take =VALUE" {
  run "$SCRIPT_PATH" --no-pager --effort=high --model=opus --theme=powerline "q"
  [ "$status" -eq 0 ]
  grep -q -- '--effort high --model opus' "$CLAUDE_STUB_LOG"
  [[ "$output" == *$'\ue0b0'* ]]
  run "$SCRIPT_PATH" --pager="sed s/^/PAGED:/" "q"
  [[ "$output" == *"PAGED:"* ]]
  run "$SCRIPT_PATH" --no-pager --session=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paris"* ]]
}

@test "=VALUE is checked like a separate value" {
  run "$SCRIPT_PATH" --effort=turbo "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"effort must be one of"* ]]
  run "$SCRIPT_PATH" --theme=nope "q"
  [ "$status" -eq 1 ]
  for bad in --effort= --model= --pager=; do
    run "$SCRIPT_PATH" "$bad" "q"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
  done
}

@test "short flags can be bundled" {
  run "$SCRIPT_PATH" --no-pager "first"
  : > "$CLAUDE_STUB_LOG"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager -ir < <(printf 'again\n')
  [ "$status" -eq 0 ]
  grep -q -- '--resume' "$CLAUDE_STUB_LOG"
  : > "$CLAUDE_STUB_LOG"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager -ie high "q" < /dev/null
  [ "$status" -eq 0 ]
  grep -q -- '--effort high' "$CLAUDE_STUB_LOG"
}

@test "an unknown flag in a bundle, and -- ends the options" {
  run "$SCRIPT_PATH" -iz "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: -z"* ]]
  run "$SCRIPT_PATH" --no-pager -- -ir is a question
  [ "$status" -eq 0 ]
  grep -qF '| -ir is a question' "$CLAUDE_STUB_LOG"
}

@test "the info line shows the running tool and its detail" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/tool_denied.jsonl"
  run "$SCRIPT_PATH" --no-pager "q"
  local clean
  clean=$(printf '%s' "$output" | strip_ansi)
  [[ "$clean" == *"Bash: git status |"* ]]
  [[ "$clean" == *"Write: /tmp/x |"* ]]
  # No detail to show: just the name
  [[ "$clean" == *"TodoWrite |"* ]]
  # Only the first line of a command
  [[ "$clean" != *"second line"* ]]
  # Gone from the final line
  [[ "$(tail -2 <<< "$clean")" != *"TodoWrite"* ]]
}

@test "the tool is cleared by its result, by text and by the end" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"assistant","message":{"id":"m","content":[{"type":"thinking","thinking":"x"}]}}'
  [ "$is_thinking" -eq 1 ]
  process_stream_line '{"type":"assistant","message":{"id":"m","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b"}}]}}'
  [ "$current_tool" = "Read: /a/b" ]
  [ "$is_thinking" -eq 0 ]
  process_stream_line '{"type":"user","message":{"content":[{"type":"tool_result"}]}}'
  [ -z "$current_tool" ]
  process_stream_line '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"Read","input":{}}]}}'
  [ "$current_tool" = "Read" ]
  process_stream_line '{"type":"assistant","message":{"id":"m3","content":[{"type":"text","text":"done"}]}}'
  [ -z "$current_tool" ]
  process_stream_line '{"type":"assistant","message":{"id":"m4","content":[{"type":"text","text":"and"},{"type":"tool_use","name":"Grep","input":{"pattern":"p"}}]}}'
  [ "$current_tool" = "Grep: p" ]
  process_stream_line '{"type":"result","is_error":false,"result":"x"}'
  [ -z "$current_tool" ]
}

@test "a long tool detail is cut to the width" {
  source_claude_ask
  local long
  long=$(printf 'x%.0s' {1..300})
  TERM_COLS=80
  render_stream_info info 1 2 3 4 running 0 "" "Bash: $long"
  [[ "$info" == *"…"* ]]
  [[ "$(printf '%s' "$info" | strip_ansi)" != *"$long"* ]]
  visible_width w "$info"
  [ "$w" -le 80 ]
  # Also in a very narrow terminal it is short
  TERM_COLS=20
  render_stream_info info 1 2 3 4 running 0 "" "Bash: $long"
  [[ "$(printf '%s' "$info" | strip_ansi)" == *"Bash: xxxxx…"* ]]
  # And not shown when done
  render_stream_info info 1 2 3 "" done 0 "" "Bash: ls"
  [[ "$info" != *"Bash"* ]]
}

@test "denied tools are named after the answer, each once" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/tool_denied.jsonl"
  run --separate-stderr "$SCRIPT_PATH" --no-pager "q"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"not permitted: Bash, Write"* ]]
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/full_session.jsonl"
  run --separate-stderr "$SCRIPT_PATH" --no-pager "other"
  [[ "$stderr" != *"not permitted"* ]]
}

@test "EDITOR can hold arguments, and VISUAL comes first" {
  cat > "$TEST_TEMP_DIR/ed" <<STUB
#!/bin/bash
printf '%s' "\$*" > "$TEST_TEMP_DIR/ed-args"
echo "from \$1" > "\${@: -1}"
STUB
  chmod +x "$TEST_TEMP_DIR/ed"
  export EDITOR="$TEST_TEMP_DIR/ed --wait"
  unset VISUAL
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf '\\e\nexit\n')
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_TEMP_DIR/ed-args")" == "--wait "*question.md ]]
  grep -qF '| from --wait' "$CLAUDE_STUB_LOG"
  export VISUAL="$TEST_TEMP_DIR/ed --visual"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf '\\e\nexit\n')
  grep -qF '| from --visual' "$CLAUDE_STUB_LOG"
}

@test "a file that is not a session is reported, with status 1" {
  printf '{broken' > "$SESSION_DIR/bad.json"
  run "$SCRIPT_PATH" --session bad
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad is not a valid session file"* ]]
  [[ "$output" != *"parse error"* ]]
  run "$SCRIPT_PATH" --resume=bad "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad is not a valid session file"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
  run "$SCRIPT_PATH" -y --session bad
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad is not a valid session file"* ]]
  # Empty, an array and several objects (an old raw stream) are not either
  : > "$SESSION_DIR/empty.json"
  printf '[1]' > "$SESSION_DIR/list.json"
  printf '{"a":1}\n{"b":2}\n' > "$SESSION_DIR/lines.json"
  for name in empty list lines; do
    run "$SCRIPT_PATH" --session "$name"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$name is not a valid session file"* ]]
  done
}

# Three turns in one session
three_turns() {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 "$SCRIPT_PATH" --no-pager > /dev/null 2>&1 < <(printf 'one\ntwo\nthree\n')
}

@test "--session with several turns: one pager over them all" {
  three_turns
  # A small screen, so less waits: one q ends it all
  PTY_SIZE=60x5 run python3 "$PTY" 'expect::' 'send:G' 'expect:(END)' 'send:q' 'sleep:0.5' -- \
    bash -c "'$SCRIPT_PATH' --pager 'tee -a $TEST_TEMP_DIR/rendered' --session one; touch '$TEST_TEMP_DIR/done'"
  [ -e "$TEST_TEMP_DIR/done" ]
  # Each turn was rendered, and the pager was less, not the renderer
  [ "$(grep -o 'Paris' "$TEST_TEMP_DIR/rendered" | wc -l)" -eq 3 ]
}

@test "--session that fits the screen is just printed" {
  three_turns
  PTY_SIZE=120x50 run python3 "$PTY" 'sleep:1' -- \
    bash -c "'$SCRIPT_PATH' --pager cat --session one; touch '$TEST_TEMP_DIR/done'"
  [ -e "$TEST_TEMP_DIR/done" ]
  [[ "$output" == *"> three"* ]]
}

@test "--session to a pipe or with --no-pager does not page" {
  three_turns
  run "$SCRIPT_PATH" --pager "sed s/^/ANSWER:/" --session one
  [ "$status" -eq 0 ]
  [ "$(grep -c 'ANSWER:' <<< "$output")" -eq 3 ]
  PTY_SIZE=60x5 run python3 "$PTY" 'sleep:1' -- \
    bash -c "'$SCRIPT_PATH' --no-pager --session one; touch '$TEST_TEMP_DIR/done'"
  [ -e "$TEST_TEMP_DIR/done" ]
}

# pty_chat STEP...: the chat in a pseudo-terminal, with no readline settings
pty_chat() {
  INPUTRC=/dev/null run python3 "$PTY" "$@" -- "$SCRIPT_PATH" --no-pager
}

@test "a multi-line question comes back whole from the history file" {
  pty_chat 'expect:> ' 'send:aaa\rbbb\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$status" -eq 0 ]
  # One entry, on one line
  [ "$(cat "$XDG_STATE_HOME/claude-ask/history")" = "aaa⏎bbb" ]
  : > "$CLAUDE_STUB_LOG"
  pty_chat 'expect:> ' 'send:\x1b[A' 'expect:aaa⏎bbb' 'send:\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -qF '| aaa\nbbb' "$CLAUDE_STUB_LOG"
  # Asked again: the same one entry again
  [ "$(grep -c 'aaa⏎bbb' "$XDG_STATE_HOME/claude-ask/history")" -eq 2 ]
}

@test "a recalled multi-line question that starts with /word is still a question" {
  pty_chat 'expect:> ' 'send:/etc/hosts\rexit\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  : > "$CLAUDE_STUB_LOG"
  pty_chat 'expect:> ' 'send:\x1b[A' 'expect:/etc/hosts⏎exit' 'send:\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$status" -eq 0 ]
  grep -qF '| /etc/hosts\nexit' "$CLAUDE_STUB_LOG"
}

@test "a history file from before the mark still works" {
  local hist="$XDG_STATE_HOME/claude-ask/history"
  mkdir -p "${hist%/*}"
  printf 'old one\nold two\n' > "$hist"
  pty_chat 'expect:> ' 'send:\x1b[A' 'sleep:0.3' 'send:\x1b[A' 'sleep:0.3' 'send:\r' 'expect:chunks' 'expect:> ' 'send:exit\r'
  [ "$status" -eq 0 ]
  grep -qF '| old one' "$CLAUDE_STUB_LOG"
}

@test "sessions live under XDG_DATA_HOME by default" {
  export HOME="$TEST_TEMP_DIR/home" XDG_DATA_HOME="$TEST_TEMP_DIR/data"
  unset SESSION_DIR
  run "$SCRIPT_PATH" --no-pager "q"
  [ -f "$XDG_DATA_HOME/claude-ask/sessions/q.json" ]
  [ "$(stat -c %a "$XDG_DATA_HOME/claude-ask/sessions")" = 700 ]
  unset XDG_DATA_HOME
  run "$SCRIPT_PATH" --no-pager "r"
  [ -f "$HOME/.local/share/claude-ask/sessions/r.json" ]
}

@test "sessions in the old place move once, and say so" {
  export HOME="$TEST_TEMP_DIR/home"
  unset SESSION_DIR
  local old="$HOME/.local/share/claude/cli-sessions" new="$HOME/.local/share/claude-ask/sessions"
  mkdir -p "$old"
  printf '{"question":"q","answer":"kept","session_id":"s"}' > "$old/kept.json"
  run --separate-stderr "$SCRIPT_PATH" --no-pager --session kept
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept"* ]]
  [[ "$stderr" == *"moved saved sessions to $new"* ]]
  [ -f "$new/kept.json" ]
  [ ! -e "$old" ]
  run --separate-stderr "$SCRIPT_PATH" --history
  [[ "$stderr" != *"moved"* ]]
}

@test "the old place is left alone when the new one exists or SESSION_DIR is set" {
  export HOME="$TEST_TEMP_DIR/home"
  local old="$HOME/.local/share/claude/cli-sessions" new="$HOME/.local/share/claude-ask/sessions"
  mkdir -p "$old"
  printf '{}' > "$old/kept.json"
  # SESSION_DIR from common_setup is set
  run "$SCRIPT_PATH" --no-pager "q"
  [ -f "$old/kept.json" ]
  [ ! -e "$new" ]
  unset SESSION_DIR
  mkdir -p "$new"
  run "$SCRIPT_PATH" --no-pager "q"
  [ -f "$old/kept.json" ]
  [ -f "$new/q.json" ]
}

@test "when the move fails the old place is used" {
  export HOME="$TEST_TEMP_DIR/home" XDG_DATA_HOME="$TEST_TEMP_DIR/readonly"
  unset SESSION_DIR
  local old="$HOME/.local/share/claude/cli-sessions"
  mkdir -p "$old" "$XDG_DATA_HOME"
  printf '{"question":"q","answer":"a"}' > "$old/kept.json"
  chmod 555 "$XDG_DATA_HOME"
  run "$SCRIPT_PATH" --history
  chmod 755 "$XDG_DATA_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept"* ]]
  [ -f "$old/kept.json" ]
}

@test "--history fits the width, and drops the name when very narrow" {
  run "$SCRIPT_PATH" --no-pager "a question long enough that it has to be cut somewhere in the table"
  CLAUDE_ASK_COLUMNS=90 run "$SCRIPT_PATH" --history
  [ "$status" -eq 0 ]
  [ "${#output}" -le 90 ]
  [[ "$output" == *"…"* ]]
  [[ "$output" == *"a-question-long"* ]]
  CLAUDE_ASK_COLUMNS=40 run "$SCRIPT_PATH" --history
  [ "${#output}" -le 40 ]
  [[ "$output" != *"a-question-long"* ]]
  [[ "$output" == *"a quest"* ]]
}

@test "--history keeps its columns in line with double-width characters" {
  export LANG=C.UTF-8
  run "$SCRIPT_PATH" --no-pager "short"
  run "$SCRIPT_PATH" --no-pager "日本語の質問です、これは四十文字を超えるとても長い質問の例です、さらに続けます、もっともっと"
  CLAUDE_ASK_COLUMNS=100 run "$SCRIPT_PATH" --history
  local line prefix bars=()
  while IFS= read -r line; do
    # Where the last separator is, in columns
    prefix="${line% | *}"
    bars+=("$(printf '%s' "$prefix" | wc -L)")
  done <<< "$output"
  [ "${#bars[@]}" -eq 2 ]
  [ "${bars[0]}" -eq "${bars[1]}" ]
  [[ "$output" == *"…"* ]]
}

@test "--history to a pipe keeps its full width" {
  run "$SCRIPT_PATH" --no-pager "a question long enough that it has to be cut somewhere in the table"
  run env -u CLAUDE_ASK_COLUMNS -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" --history
  [[ "$output" == *"a question long enough that it has to b…"* ]]
}
