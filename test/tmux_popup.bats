#!/usr/bin/env bats
# Test --popup against a real tmux: a private server (its socket in the
# test's temp dir, no config) with a client attached in a pseudo-terminal,
# since display-popup needs one. Skipped without tmux.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  command -v tmux > /dev/null || skip "tmux is not installed"
  export TMUX_TMPDIR="$TEST_TEMP_DIR"
  # tmux needs a terminal type it knows (CI may have none, or dumb)
  export PTY_SIZE=100x30 TERM=xterm-256color
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  unset LESS
  PTY="$BATS_TEST_DIRNAME/helpers/pty_run.py"
}

teardown() {
  tmux -L popup-test kill-server 2> /dev/null || true
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then rm -rf "$TEST_TEMP_DIR"; fi
}

# in_tmux STEP...: run the steps at a shell in a tmux pane with the client
# attached to the pseudo-terminal. CA is the claude-ask command line there.
# "echo AF""TER" (and the like) prints a word the typed line does not hold.
# PS1 is set in the pane's command: tmux runs it with $SHELL -c, and when
# that is bash a non-interactive bash drops an inherited PS1.
in_tmux() {
  run python3 "$PTY" 'expect:READY$ ' "$@" 'send:exit\r' -- \
    tmux -L popup-test -f /dev/null new-session "PS1='READY\$ ' bash --norc --noprofile"
  screen_text=$(printf '%s' "$output" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\x1b[()][A-Z0-9]//g' | tr -d '\001\002\r')
  # bats shows what a test prints only when it fails: what the client was
  # sent, and the pane now if the server is still up (the helper's status is
  # 124 when an expect step timed out)
  printf 'pty status: %s\n--- client output (end):\n' "$status"
  printf '%s\n' "$screen_text" | tr -s ' ' | tail -c 2500
  printf '\n--- pane:\n'
  tmux -L popup-test capture-pane -p 2>&1 | grep -v '^$' || true
}

CA="$BATS_TEST_DIRNAME/../bin/claude-ask"

@test "popup: a question's answer is paged, and quitting the pager closes it" {
  in_tmux "send:$CA --popup q; echo RC=\$?\\r" 'expect:(END)' 'sleep:0.3' 'send:q' \
    'expect:RC=0' 'send:echo AF""TER\r' 'expect:AFTER'
  [ "$status" -eq 0 ]
  [[ "$screen_text" == *"The capital of France is"* ]]
  # The popup was open (paging) until q: the status came after
  local paged="${screen_text%%(END)*}"
  [[ "$paged" != *"RC=0"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

@test "popup: the pager waits even when LESS has -F" {
  export LESS=-F
  in_tmux "send:$CA --popup q; echo RC=\$?\\r" 'expect:(END)' 'sleep:1' \
    'send:echo EA""RLY\r' 'sleep:0.5' 'send:q' 'expect:RC=0' 'send:echo AF""TER\r' 'expect:AFTER'
  [ "$status" -eq 0 ]
  # The keys typed while it paged went to less, not to the shell
  [[ "$screen_text" != *"EARLY"* ]]
}

@test "popup: with no question it is a chat until /quit" {
  in_tmux "send:$CA --popup; echo RC=\$?\\r" 'expect:/help for commands' 'send:q\r' \
    'expect:Paris' 'expect:> ' 'send:/quit\r' 'expect:RC=0' 'send:echo AF""TER\r' 'expect:AFTER'
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

@test "popup: a failed answer waits for a key, closes, and passes on its status" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/result_error.jsonl"
  in_tmux "send:$CA --popup q; echo RC=\$?\\r" 'expect:press a key to close' 'sleep:0.3' 'send:x' \
    'expect:RC=1' 'send:echo AF""TER\r' 'expect:AFTER'
  [ "$status" -eq 0 ]
  [[ "$screen_text" == *"Invalid API key"* ]]
  # The popup started, so it is not reported as tmux failing
  [[ "$screen_text" != *"could not start"* ]]
}
