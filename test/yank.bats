#!/usr/bin/env bats
# Test yanking answers and code blocks: -y, -Y, --yank-code=N, /yank and
# the clipboard and tmux buffer they copy to

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/code_answer.jsonl"
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  CLIP="$TEST_TEMP_DIR/clipboard"
}

chat() {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager "${CHAT_ARGS[@]}" < <(printf '%s\n' "$@")
}

# The fixture's two code blocks, as yanked
BLOCK1='while IFS= read -r line; do
  echo "$line"
done < file'
BLOCK2='{ print }'

# ---------------------------------------------------------------------------
# Code block extraction
# ---------------------------------------------------------------------------
@test "extract_code_blocks finds backtick and tilde blocks without their fences" {
  source_claude_ask
  extract_code_blocks $'text\n```sh\necho a\n```\nmore\n~~~\nb\n~~~'
  [ "${#CODE_BLOCKS[@]}" -eq 2 ]
  [ "${CODE_BLOCKS[0]}" = $'echo a\n' ]
  [ "${CODE_BLOCKS[1]}" = $'b\n' ]
}

@test "extract_code_blocks: a shorter or other fence does not close a block" {
  source_claude_ask
  extract_code_blocks $'````md\n```\ninner\n~~~\n````'
  [ "${#CODE_BLOCKS[@]}" -eq 1 ]
  [ "${CODE_BLOCKS[0]}" = $'```\ninner\n~~~\n' ]
}

@test "extract_code_blocks: an unclosed block runs to the end; none gives none" {
  source_claude_ask
  extract_code_blocks $'```\nopen'
  [ "${CODE_BLOCKS[0]}" = $'open\n' ]
  extract_code_blocks "no code here"
  [ "${#CODE_BLOCKS[@]}" -eq 0 ]
}

@test "extract_code_blocks keeps indented fences and blank lines inside" {
  source_claude_ask
  extract_code_blocks $'   ```\na\n\nb\n   ```'
  [ "${CODE_BLOCKS[0]}" = $'a\n\nb\n' ]
}

@test "split_direction: side by side only when wide and roomy" {
  source_claude_ask
  [ "$(split_direction 240 60)" = h ]
  [ "$(split_direction 120 60)" = v ]
  [ "$(split_direction 150 30)" = v ]
  [ "$(split_direction 160 30)" = h ]
}

# ---------------------------------------------------------------------------
# -y and -Y with a question: the new answer
# ---------------------------------------------------------------------------
@test "-y copies the new answer, without the last newline" {
  run "$SCRIPT_PATH" --no-pager -y "question"
  [ "$status" -eq 0 ]
  [ "$(cat "$CLIP")" = "$(jq -r 'select(.type == "result") | .result' "$CLAUDE_STUB_FIXTURE")" ]
  [ "$(tail -c 1 "$CLIP")" != "" ]
  [[ "$output" == *"yanked the answer (13 lines) to the clipboard"* ]]
}

@test "-Y copies every code block, a blank line between them" {
  run "$SCRIPT_PATH" --no-pager -Y "question"
  [ "$status" -eq 0 ]
  [ "$(cat "$CLIP")" = "$BLOCK1"$'\n\n'"$BLOCK2" ]
  [[ "$output" == *"yanked 2 code blocks (5 lines)"* ]]
}

@test "--yank-code=2 copies only the second block" {
  run "$SCRIPT_PATH" --no-pager --yank-code=2 "question"
  [ "$(cat "$CLIP")" = "$BLOCK2" ]
  [[ "$output" == *"yanked code block 2 of 2"* ]]
}

@test "--yank-code=N needs a block number" {
  run "$SCRIPT_PATH" --yank-code=0 "question"
  [ "$status" -eq 1 ]
  [[ "$output" == *"takes a block number"* ]]
  run "$SCRIPT_PATH" --yank-code=x "question"
  [ "$status" -eq 1 ]
}

@test "-Y on an answer without code says so and the run still succeeds" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/full_session.jsonl"
  run "$SCRIPT_PATH" --no-pager -Y "question"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the answer has no code blocks"* ]]
  [ ! -e "$CLIP" ]
}

@test "--yank-code=3 past the last block says how many there are" {
  run "$SCRIPT_PATH" --no-pager --yank-code=3 "question"
  [[ "$output" == *"there is no code block 3 (the answer has 2)"* ]]
}

@test "the yank note goes to stderr, the answer to stdout" {
  run --separate-stderr "$SCRIPT_PATH" --no-pager -y "question"
  [[ "$stderr" == *"yanked the answer"* ]]
  [[ "$output" != *"yanked"* ]]
}

# ---------------------------------------------------------------------------
# -y and -Y without a question: a saved answer
# ---------------------------------------------------------------------------
@test "-y with no question copies the newest session's last answer and asks nothing" {
  run "$SCRIPT_PATH" --no-pager "first question"
  : > "$CLAUDE_STUB_LOG"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" -y < /dev/null
  [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_STUB_LOG" ]
  [[ "$(cat "$CLIP")" == "Two ways:"* ]]
}

@test "-Y with no question copies the code of the saved answer" {
  run "$SCRIPT_PATH" --no-pager "first question"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" -Y < /dev/null
  [ "$(cat "$CLIP")" = "$BLOCK1"$'\n\n'"$BLOCK2" ]
}

@test "--session N -y copies that session's answer instead of replaying it" {
  jq -n '{session_id: "s1", name: "older", question: "q", answer: "older answer",
    timestamp: "2026-11-01T00:00:00Z"}' > "$SESSION_DIR/older.json"
  touch -d "-1 hour" "$SESSION_DIR/older.json"
  run "$SCRIPT_PATH" --no-pager "newer question"
  run "$SCRIPT_PATH" --no-pager --session 2 -y
  [ "$status" -eq 0 ]
  [ "$(cat "$CLIP")" = "older answer" ]
  [[ "$output" != *"> q"* ]]
}

@test "-y with no saved session is an error" {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" -y < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no saved session to yank from"* ]]
}

@test "-y with piped input asks it and copies the new answer" {
  run "$SCRIPT_PATH" --no-pager -y < <(printf 'piped question')
  [ "$status" -eq 0 ]
  grep -q '| piped question$' "$CLAUDE_STUB_LOG"
  [[ "$(cat "$CLIP")" == "Two ways:"* ]]
}

# ---------------------------------------------------------------------------
# Where it goes
# ---------------------------------------------------------------------------
@test "inside tmux the text also goes to a tmux buffer" {
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0"
  export CLAUDE_STUB_TMUX_BUFFER="$TEST_TEMP_DIR/buffer"
  run "$SCRIPT_PATH" --no-pager -Y "question"
  [ "$(cat "$TEST_TEMP_DIR/buffer")" = "$(cat "$CLIP")" ]
  [[ "$output" == *"to the clipboard and a tmux buffer"* ]]
}

@test "with no clipboard command and no tmux it says there is nowhere to yank" {
  export CLAUDE_ASK_CLIPBOARD="exit 1"
  run "$SCRIPT_PATH" --no-pager -y "question"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nowhere to yank to"* ]]
}

@test "clipboard_cmd picks wl-copy on Wayland, xclip on X11" {
  source_claude_ask
  unset CLAUDE_ASK_CLIPBOARD
  local bin="$TEST_TEMP_DIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\n' > "$bin/wl-copy"
  printf '#!/bin/sh\n' > "$bin/xclip"
  chmod +x "$bin"/*
  PATH="$bin" WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 clipboard_cmd
  [ "$CLIP_CMD" = "wl-copy" ]
  PATH="$bin" WAYLAND_DISPLAY="" DISPLAY=:0 clipboard_cmd
  [ "$CLIP_CMD" = "xclip -selection clipboard" ]
  ! PATH="$bin" WAYLAND_DISPLAY="" DISPLAY="" clipboard_cmd
}

# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
@test "chat: /yank, /yank code and /yank code N copy from the last answer" {
  CHAT_ARGS=()
  chat "question" "/yank code 1"
  [ "$(cat "$CLIP")" = "$BLOCK1" ]
  chat "question" "/yank code"
  [ "$(cat "$CLIP")" = "$BLOCK1"$'\n\n'"$BLOCK2" ]
  chat "question" "/yank"
  [[ "$(cat "$CLIP")" == "Two ways:"* ]]
}

@test "chat: /yank before any answer, and a bad argument, are refused" {
  CHAT_ARGS=()
  chat "/yank" "/yank lines"
  [[ "$output" == *"there is no answer to yank"* ]]
  [[ "$output" == *"/yank takes nothing, code, or code N"* ]]
  [ ! -e "$CLIP" ]
}

@test "chat: -r makes the session's last answer the one /yank copies" {
  jq -n '{session_id: "old", name: "saved", question: "q", answer: "saved answer",
    timestamp: "2026-11-01T00:00:00Z"}' > "$SESSION_DIR/saved.json"
  CHAT_ARGS=(-r)
  chat "/yank"
  [ "$(cat "$CLIP")" = "saved answer" ]
}

@test "chat: -i -Y copies every answer" {
  CHAT_ARGS=(-i -Y)
  chat "one" "two"
  [ "$(grep -c 'yanked 2 code blocks' <<< "$output")" -eq 2 ]
}

@test "chat: /help lists /yank" {
  CHAT_ARGS=()
  chat "/help"
  [[ "$output" == *"/yank [code [N]]"* ]]
}
