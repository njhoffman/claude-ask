#!/usr/bin/env bats
# Test what actually lands on a screen while the status bar redraws, read
# back from a real tmux pane. Skipped without tmux.

bats_require_minimum_version 1.5.0

load test_helper

# One tmux server name for the whole file: its tests run one at a time, even
# with bats --jobs (the other files still run beside them)
setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
}

setup() {
  common_setup
  command -v tmux > /dev/null || skip "tmux is not installed"
  export TMUX_TMPDIR="$TEST_TEMP_DIR" TERM=xterm-256color
  # The real width and no stand-ins: tmux gives it a terminal
  unset CLAUDE_ASK_COLUMNS CLAUDE_ASK_FORCE_TTY
}

teardown() {
  tmux -L screen-test kill-server 2> /dev/null || true
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then rm -rf "$TEST_TEMP_DIR"; fi
}

# fixture_of TEXT...: a stream with each TEXT as an event of one message
fixture_of() {
  printf '%s\n' '{"type":"system","subtype":"init","session_id":"s1","model":"claude-opus-5-5"}'
  local t
  for t in "$@"; do
    jq -cn --arg t "$t" '{type: "assistant", session_id: "s1", message: {id: "m1", content: [{type: "text", text: $t}]}}'
  done
  printf '%s\n' '{"type":"result","is_error":false,"result":"x","session_id":"s1","total_cost_usd":0.1,"duration_ms":100,"usage":{"input_tokens":1,"output_tokens":2}}'
}

# on_screen WIDTH HEIGHT: run claude-ask on $FIXTURE in a pane and leave the
# pane's text in screen_text, without the status bar's lines. A line is printed
# first, as a shell prompt would: at the very top-left, tmux's scroll-on-clear
# moves the screen into its history on \e[J.
on_screen() {
  local i
  tmux -L screen-test -f /dev/null new-session -d -x "$1" -y "$2" \
    "echo top; CLAUDE_STUB_FIXTURE='$FIXTURE' CLAUDE_STUB_DELAY=0.05 '$SCRIPT_PATH' --no-pager q; touch '$TEST_TEMP_DIR/done'; sleep 30"
  for ((i = 0; i < 100; i++)); do
    [[ -e "$TEST_TEMP_DIR/done" ]] && break
    sleep 0.1
  done
  [[ -e "$TEST_TEMP_DIR/done" ]]
  sleep 0.2
  # -J keeps trailing spaces, in tmux 3.2 at least
  screen_text=$(tmux -L screen-test capture-pane -p -J | sed 's/ *$//' | grep -v -e '^$' -e '^top$' -e 'chunks' -e 'opus 5.5')
  printf 'screen:\n%s\n' "$screen_text"
}

@test "screen: text after a wrapped line goes straight on" {
  local long
  long=$(printf 'x%.0s' {1..130})
  FIXTURE="$TEST_TEMP_DIR/f"
  fixture_of "$long" "TAIL" "MORE" > "$FIXTURE"
  on_screen 60 20
  [ "$screen_text" = "${long}TAILMORE" ]
}

@test "screen: a chunk ending exactly at the width keeps its last character" {
  local full
  full=$(printf 'x%.0s' {1..59})Z
  FIXTURE="$TEST_TEMP_DIR/f"
  fixture_of "$full" "TAIL" > "$FIXTURE"
  on_screen 60 20
  [ "$screen_text" = "${full}TAIL" ]
}

@test "screen: words arriving as deltas are placed like any text" {
  FIXTURE="$TEST_TEMP_DIR/f"
  {
    printf '%s\n' '{"type":"system","subtype":"init","session_id":"s1","model":"claude-opus-5-5"}'
    for t in "one " "two" $'\n\nthree ' "four five " "six"; do
      jq -cn --arg t "$t" '{type: "stream_event", event: {type: "content_block_delta", delta: {type: "text_delta", text: $t}}}'
    done
    printf '%s\n' '{"type":"result","is_error":false,"result":"x","session_id":"s1","total_cost_usd":0.1,"duration_ms":100,"usage":{"input_tokens":1,"output_tokens":2}}'
  } > "$FIXTURE"
  on_screen 60 20
  [ "$screen_text" = $'one two\nthree four five six' ]
}

@test "screen: wide characters are not overwritten" {
  FIXTURE="$TEST_TEMP_DIR/f"
  fixture_of "日本語日本語" "TAIL" > "$FIXTURE"
  on_screen 60 20
  [ "$screen_text" = "日本語日本語TAIL" ]
}

@test "screen: a partial line keeps its place when the bar scrolls the pane" {
  # Several lines, then the bottom of a short pane, so each redraw scrolls
  FIXTURE="$TEST_TEMP_DIR/f"
  fixture_of $'one\ntwo\nthree\nfour\nfive\nsix\nseven\nstart ' "middle " "end" > "$FIXTURE"
  on_screen 60 10
  [[ "$screen_text" == *$'seven\nstart middle end'* ]]
  # No copies of the bar left in the text
  [ "$(tmux -L screen-test capture-pane -p -S - | grep -c 'chunks')" -eq 1 ]
}

@test "screen: color codes in a chunk do not move the text" {
  FIXTURE="$TEST_TEMP_DIR/f"
  fixture_of "before " "after" > "$FIXTURE"
  local pager="sed -u 's/^/\x1b[31m/'"
  tmux -L screen-test -f /dev/null new-session -d -x 60 -y 20 \
    "CLAUDE_STUB_FIXTURE='$FIXTURE' CLAUDE_STUB_DELAY=0.05 '$SCRIPT_PATH' --pager \"$pager\" q; touch '$TEST_TEMP_DIR/done'; sleep 30"
  local i
  for ((i = 0; i < 100; i++)); do [[ -e "$TEST_TEMP_DIR/done" ]] && break; sleep 0.1; done
  sleep 0.2
  tmux -L screen-test capture-pane -p | grep -q '^before after'
}
