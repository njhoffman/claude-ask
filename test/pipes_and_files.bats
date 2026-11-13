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

@test "piped input with NUL bytes is refused, and nothing is asked" {
  run --separate-stderr "$SCRIPT_PATH" --no-pager "q" < <(printf 'text\0more')
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the piped input is not text: it has NUL bytes"* ]]
  [[ "$stderr" != *"ignored null byte"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
  # UTF-16 too, and with no question
  iconv -f UTF-8 -t UTF-16LE <<< "hello" > "$TEST_TEMP_DIR/u16"
  run --separate-stderr "$SCRIPT_PATH" --no-pager < "$TEST_TEMP_DIR/u16"
  [ "$status" -eq 1 ]
  [ ! -s "$CLAUDE_STUB_LOG" ]
  # The temp file it read into is gone
  [ -z "$(ls "$XDG_RUNTIME_DIR" | grep claude-ask-input)" ]
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

@test "claude is asked for partial messages" {
  run "$SCRIPT_PATH" --no-pager "q"
  grep -q -- '--include-partial-messages' "$CLAUDE_STUB_LOG"
}

@test "partial messages: the answer shows once, and is saved once" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/partial_messages.jsonl"
  local result want="I'll read \`a.txt\` from the working directory and show its contents."
  result=$(jq -r 'select(.type == "result") | .result' "$CLAUDE_STUB_FIXTURE")
  [ "$(plain "q" 2> /dev/null)" = "$want"$'\n\n'"$result" ]
  [ "$(jq -r .answer "$SESSION_DIR/q.json")" = "$want"$'\n\n'"$result" ]
  [ "$(jq -r .session_id "$SESSION_DIR/q.json")" = "partial-001" ]
}

# A pager that logs each run: its input between markers
counting_pager() {
  cat > "$TEST_TEMP_DIR/pager" <<STUB
#!/bin/bash
input=\$(cat)
printf '[%s]\n' "\$input" >> "$TEST_TEMP_DIR/pager-runs"
printf 'R:%s\n' "\$input"
STUB
  chmod +x "$TEST_TEMP_DIR/pager"
}

@test "with a pager each block is rendered on its own, a code block whole" {
  counting_pager
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  jq -cn '{type: "system", subtype: "init", session_id: "s", model: "claude-opus-5-5"},
    ({type: "stream_event", event: {type: "message_start", message: {id: "m1"}}}),
    ("First para", "graph.\n", "\nSecond one.\n\n```sh\necho a\n", "\necho b\n```", "\n\nLast bit") as $t
      | {type: "stream_event", event: {type: "content_block_delta", delta: {type: "text_delta", text: $t}}}' > "$CLAUDE_STUB_FIXTURE"
  printf '%s\n' '{"type":"result","is_error":false,"result":"x","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}' >> "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/pager-runs")" = $'[First paragraph.]\n[Second one.]\n[```sh\necho a\n\necho b\n```]\n[Last bit]' ]
  # Blocks with a blank line between them, and nothing else on stdout
  : > "$TEST_TEMP_DIR/pager-runs"
  [ "$(plain --pager "$TEST_TEMP_DIR/pager" "again" 2> /dev/null)" = $'R:First paragraph.\n\nR:Second one.\n\nR:```sh\necho a\n\necho b\n```\n\nR:Last bit' ]
}

@test "with a pager text shows before a tool runs, with no blank line after it" {
  counting_pager
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/partial_messages.jsonl"
  run "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$TEST_TEMP_DIR/pager-runs")" = "[I'll read \`a.txt\` from the working directory and show its contents.]" ]
  # The text after the tool is whole blocks, none repeated
  [ "$(grep -c "I'll read" "$TEST_TEMP_DIR/pager-runs")" -eq 1 ]
  [ "$(grep -c '^\[The file' "$TEST_TEMP_DIR/pager-runs")" -eq 1 ]
}

@test "a pager that gives nothing back: the text itself is shown" {
  run "$SCRIPT_PATH" --pager "cat > /dev/null" "q"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paris"* ]]
  run "$SCRIPT_PATH" --pager "exit 3" "other q"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paris"* ]]
}

@test "many deltas do not redraw the bar for each one" {
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  {
    printf '%s\n' '{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5-5"}'
    jq -cn 'range(400) | {type: "stream_event", event: {type: "content_block_delta", delta: {type: "text_delta", text: "w "}}}'
    printf '%s\n' '{"type":"result","is_error":false,"result":"x","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}'
  } > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$status" -eq 0 ]
  # Every word arrives; well under one bar each
  [ "$(printf '%s' "$output" | strip_ansi | grep -o 'w ' | wc -l)" -ge 400 ]
  [ "$(grep -c 'chunks' <<< "$output")" -lt 200 ]
}

@test "a run with a background subagent: all the answer, once, and success" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/subagent.jsonl"
  run --separate-stderr env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" "q"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SUBAGENT TEXT"* ]]
  [ "$(grep -c 'still running' <<< "$output")" -eq 1 ]
  [ "$(grep -c '^The subagent says hi' <<< "$output")" -eq 1 ]
  [[ "$output" == *$'notification arrives.\n\nThe subagent says hi'* ]]
  # The last result is empty; what was shown is what is saved
  [ "$(jq -r .answer "$SESSION_DIR/q.json")" = "$output" ]
  [ "$(jq -r .session_id "$SESSION_DIR/q.json")" = "subagent-001" ]
  [ "$(jq -r .is_error "$SESSION_DIR/q.json")" = "false" ]
}

@test "a background agent shows on the activity row until it finishes" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/subagent.jsonl"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$status" -eq 0 ]
  local clean
  clean=$(printf '%s' "$output" | strip_ansi)
  # On its own row, under the counts
  [[ "$clean" == *$'\n  agent: Subagent greeting reply'* ]]
  [[ "$clean" != *"agent: Subagent greeting reply |"* ]]
  [[ "$(tail -2 <<< "$clean")" != *"agent:"* ]]
  # Done at the end, as the last result said
  [[ "$clean" == *"done"* ]]
}

@test "a stream that ends after a result, with an agent never reported done, succeeds" {
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  cat > "$CLAUDE_STUB_FIXTURE" <<'JSONL'
{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5-5"}
{"type":"system","subtype":"background_tasks_changed","tasks":[{"description":"forever"}]}
{"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"the answer"}]},"session_id":"s"}
{"type":"result","is_error":false,"result":"the answer","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}
JSONL
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ended without a result"* ]]
}

# delta_fixture TEXT...: a stream with each TEXT as a delta of one message
delta_fixture() {
  printf '%s\n' '{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5-5"}'
  printf '%s\n' '{"type":"stream_event","event":{"type":"message_start","message":{"id":"m1"}}}'
  local t
  for t in "$@"; do
    jq -cn --arg t "$t" '{type: "stream_event", event: {type: "content_block_delta", delta: {type: "text_delta", text: $t}}}'
  done
  printf '%s\n' '{"type":"result","is_error":false,"result":"x","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}'
}

@test "a list stays one block through its blank lines, code in it too" {
  counting_pager
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  delta_fixture $'Intro.\n\n1. first\n\n   more of first\n\n2. second\n\n   ```sh\n   echo a\n\n   echo b\n   ```\n\n- bullet\n\n  - nested\n\nAfter the list.\n\nAnother.\n' > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/pager-runs")" = $'[Intro.]\n[1. first\n\n   more of first\n\n2. second\n\n   ```sh\n   echo a\n\n   echo b\n   ```\n\n- bullet\n\n  - nested]\n[After the list.]\n[Another.]' ]
}

@test "a paragraph right after a list ends it, and a list at the end flushes" {
  counting_pager
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  delta_fixture $'- a\n- b\n\nNot indented.\n\n- c\n\n  under c' > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$(cat "$TEST_TEMP_DIR/pager-runs")" = $'[- a\n- b]\n[Not indented.]\n[- c\n\n  under c]' ]
}

@test "a table gets a line above it, others do not, and blank ends are trimmed" {
  cat > "$TEST_TEMP_DIR/pager" <<STUB
#!/bin/bash
input=\$(cat; echo x)
printf '%s' "\${input%x}" >> "$TEST_TEMP_DIR/pager-input"
printf '%s===\n' '' >> "$TEST_TEMP_DIR/pager-input"
# As a renderer does: rows with only escape codes around the text
printf '\e[0m\n\e[39m%s\e[0m\n\e[0m\e[K\n\e[0m\n' "\$(printf '%s' "\$input" | tr -d 'x\n')"
STUB
  chmod +x "$TEST_TEMP_DIR/pager"
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  delta_fixture $'| a |\n|---|\n\nPlain.\n\n| b |\n|---|\n' > "$CLAUDE_STUB_FIXTURE"
  run env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/pager-input")" = $'\n| a |\n|---|\n===\nPlain.\n===\n\n| b |\n|---|\n===' ]
  # One blank line between blocks and none at either end
  [ "$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')" = $'| a ||---|\n\nPlain.\n\n| b ||---|' ]
}

@test "a slow pager runs less often than there are blocks; nothing is lost" {
  cat > "$TEST_TEMP_DIR/pager" <<STUB
#!/bin/bash
sleep 0.2
input=\$(cat)
echo run >> "$TEST_TEMP_DIR/pager-runs"
printf '%s\n' "\$input"
STUB
  chmod +x "$TEST_TEMP_DIR/pager"
  unset CLAUDE_ASK_RENDER_EVERY
  local texts=() i
  for i in {1..40}; do texts+=($'Paragraph '"$i"$'.\n\n'); done
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  delta_fixture "${texts[@]}" > "$CLAUDE_STUB_FIXTURE"
  run env -u CLAUDE_ASK_FORCE_TTY "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_TEMP_DIR/pager-runs")" -lt 12 ]
  for i in {1..40}; do [[ "$output" == *"Paragraph $i."* ]]; done
  [ "$(grep -c '^$' <<< "$output")" -eq 39 ]
}

@test "with time between them, blocks still show one at a time" {
  counting_pager
  export CLAUDE_ASK_RENDER_EVERY=100 CLAUDE_STUB_DELAY=0.3
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  delta_fixture $'One.\n\n' $'Two.\n\n' $'Three.\n\n' > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$(cat "$TEST_TEMP_DIR/pager-runs")" = $'[One.]\n[Two.]\n[Three.]' ]
}

@test "a tool call shows what is waiting, however soon" {
  counting_pager
  export CLAUDE_ASK_RENDER_EVERY=100000 CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  {
    printf '%s\n' '{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5-5"}'
    printf '%s\n' '{"type":"stream_event","event":{"type":"message_start","message":{"id":"m1"}}}'
    printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"One.\n\nTwo.\n\nThree"}}}'
    printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_stop","index":0}}'
    printf '%s\n' '{"type":"stream_event","event":{"type":"message_start","message":{"id":"m2"}}}'
    printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Four"}}}'
    printf '%s\n' '{"type":"result","is_error":false,"result":"x","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}'
  } > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --pager "$TEST_TEMP_DIR/pager" "q"
  [ "$status" -eq 0 ]
  # The first run as soon as the first block is done; the rest at the block's end
  [ "$(cat "$TEST_TEMP_DIR/pager-runs")" = $'[One.]\n[Two.\n\nThree]\n[Four]' ]
}

# results_fixture RESULT_JSON...: an answer's text, then those results, each after
# an init, as a run with a background agent has
results_fixture() {
  local result i=0
  for result in "$@"; do
    i=$((i + 1))
    printf '%s\n' '{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5-5"}'
    printf '{"type":"assistant","session_id":"s","message":{"id":"m%d","content":[{"type":"text","text":"part %d"}],"usage":{"input_tokens":1,"output_tokens":1}}}\n' "$i" "$i"
    jq -c '{type: "result", is_error: false, session_id: "s", result: "x", total_cost_usd: 0.5} + .' <<< "$result"
  done
}

@test "several results: modelUsage has the tokens, durations add, the API time does not" {
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  results_fixture \
    '{"usage":{"input_tokens":4,"output_tokens":233},"duration_ms":11878,"duration_api_ms":11681,"modelUsage":{"h":{"inputTokens":5,"outputTokens":300}}}' \
    '{"usage":{"input_tokens":4,"output_tokens":143},"duration_ms":1816,"duration_api_ms":11681,"modelUsage":{"h":{"inputTokens":10,"outputTokens":500,"cacheReadInputTokens":64113,"cacheCreationInputTokens":40270},"o":{"outputTokens":43}}}' \
    '{"usage":{"input_tokens":0,"output_tokens":0},"duration_ms":7,"duration_api_ms":0,"result":"","modelUsage":{"h":{"inputTokens":10,"outputTokens":500,"cacheReadInputTokens":64113,"cacheCreationInputTokens":40270},"o":{"outputTokens":43}}}' \
    > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.usage.input_tokens, .usage.output_tokens, .usage.cache_read_input_tokens, .usage.cache_creation_input_tokens]' "$SESSION_DIR/q.json")" = "[10,543,64113,40270]" ]
  [ "$(jq -c '[.duration_ms, .duration_api_ms, .cost_usd]' "$SESSION_DIR/q.json")" = "[13701,11681,0.5]" ]
  local final
  final=$(printf '%s' "$output" | strip_ansi | grep -a 'done' | tail -1)
  [[ "$final" == *"in:10 out:543"* ]]
  [[ "$final" == *"13.7s"* ]]
}

@test "several results with no modelUsage: the tokens add up, and it ignores an empty one" {
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  results_fixture \
    '{"usage":{"input_tokens":100,"output_tokens":50},"duration_ms":100}' \
    '{"usage":{"input_tokens":200,"output_tokens":70},"duration_ms":200}' \
    '{"usage":{"input_tokens":0,"output_tokens":0},"duration_ms":7,"result":""}' \
    > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$(jq -c '[.usage.input_tokens, .usage.output_tokens, .duration_ms]' "$SESSION_DIR/q.json")" = "[300,120,307]" ]
  [[ "$(printf '%s' "$output" | strip_ansi | grep -a 'done' | tail -1)" == *"in:300 out:120"* ]]
}

@test "one result is unchanged, and an answer only in an earlier result is kept" {
  run "$SCRIPT_PATH" --no-pager "q"
  [ "$(jq -c '[.usage.input_tokens, .usage.output_tokens, .duration_ms]' "$SESSION_DIR/q.json")" = "[500,15,3200]" ]
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  {
    printf '%s\n' '{"type":"system","subtype":"init","session_id":"s","model":"claude-opus-5-5"}'
    printf '%s\n' '{"type":"result","is_error":false,"result":"the text","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}'
    printf '%s\n' '{"type":"result","is_error":false,"result":"","session_id":"s","total_cost_usd":0.1,"duration_ms":1,"usage":{"input_tokens":0,"output_tokens":0}}'
  } > "$CLAUDE_STUB_FIXTURE"
  run "$SCRIPT_PATH" --no-pager "r"
  [ "$(jq -r .answer "$SESSION_DIR/r.json")" = "the text" ]
}

@test "denied tools from every result are named, each once" {
  export CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/f"
  results_fixture \
    '{"permission_denials":[{"tool_name":"Bash"},{"tool_name":"Write"}],"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}' \
    '{"permission_denials":[{"tool_name":"Bash"},{"tool_name":"Read"}],"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}' \
    '{"permission_denials":[],"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1}}' \
    > "$CLAUDE_STUB_FIXTURE"
  run --separate-stderr "$SCRIPT_PATH" --no-pager "q"
  [[ "$stderr" == *"not permitted: Bash, Write, Read"* ]]
}

@test "a dumb terminal: no cursor moves, the answer and the final bar" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/full_session.jsonl"
  TERM=dumb CLAUDE_ASK_FORCE_TTY= run python3 "$PTY" 'sleep:1.2' -- "$SCRIPT_PATH" --no-pager q
  [[ "$output" != *$'\e'* ]]
  [[ "$output" == *"The capital of France"* ]]
  [[ "$output" == *"sonnet 4.5"* ]]
  [ "$(grep -c 'sonnet 4.5' <<< "$output")" -eq 1 ]
  # Nor from a terminal with no TERM at all
  CLAUDE_ASK_FORCE_TTY= run env -u TERM python3 "$PTY" 'sleep:1.2' -- "$SCRIPT_PATH" --no-pager r
  [[ "$output" != *$'\e[J'* ]]
}

@test "a dumb terminal: Ctrl-C stops an answer cleanly" {
  export CLAUDE_STUB_DELAY=0.4
  TERM=dumb CLAUDE_ASK_FORCE_TTY= run python3 "$PTY" 'expect:> ' 'send:q\r' 'sleep:0.7' 'send:\x03' 'expect:(interrupted)' 'expect:> ' 'send:exit\r' -- "$SCRIPT_PATH" --no-pager
  [[ "$output" != *$'\e[J'* ]]
  [[ "$output" != *$'\eD'* ]]
}

@test "claude gets the user's locale; the script keeps its own number format" {
  cat > "$TEST_TEMP_DIR/lc" <<STUB
#!/bin/bash
printf 'LC_ALL=[%s] LANG=[%s] LC_NUMERIC=[%s] set=[%s]\n' "\${LC_ALL-}" "\${LANG-}" "\${LC_NUMERIC-}" "\${LC_NUMERIC+y}" > "$TEST_TEMP_DIR/seen"
cat "$FIXTURES_DIR/full_session.jsonl"
STUB
  chmod +x "$TEST_TEMP_DIR/lc"
  export CLAUDE_ASK_BIN="$TEST_TEMP_DIR/lc"
  run env LC_ALL=de_DE.UTF-8 LANG=en_US.UTF-8 LC_NUMERIC=de_DE.UTF-8 "$SCRIPT_PATH" --no-pager "q1"
  [ "$(cat "$TEST_TEMP_DIR/seen")" = "LC_ALL=[de_DE.UTF-8] LANG=[en_US.UTF-8] LC_NUMERIC=[de_DE.UTF-8] set=[y]" ]
  # What was not set stays not set
  run env -u LC_ALL -u LC_NUMERIC LANG=C.UTF-8 "$SCRIPT_PATH" --no-pager "q2"
  [ "$(cat "$TEST_TEMP_DIR/seen")" = "LC_ALL=[] LANG=[C.UTF-8] LC_NUMERIC=[] set=[]" ]
  # And the cost still shows with a dot
  [[ "$output" == *'$0.0123'* ]]
}

@test "the tmux environment file has the user's locale" {
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0" CLAUDE_STUB_TMUX_LOG="$TEST_TEMP_DIR/tmux-calls"
  run env -u LC_NUMERIC LC_ALL=de_DE.UTF-8 "$SCRIPT_PATH" --split "q"
  local envfile
  envfile=$(grep -o "_CLAUDE_ASK_ENV_FILE=[^' ]*" "$CLAUDE_STUB_TMUX_LOG" | cut -d= -f2)
  grep -q '^export LC_ALL=de_DE.UTF-8$' "$envfile"
  ! grep -q '^export LC_NUMERIC=' "$envfile"
}
