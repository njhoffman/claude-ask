#!/usr/bin/env bats
# Test --split and --popup against the tmux stub

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0"
  export CLAUDE_STUB_TMUX_LOG="$TEST_TEMP_DIR/tmux-calls"
  export CLAUDE_STUB_TMUX_QUESTION="$TEST_TEMP_DIR/question"
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
}

# The split-window or display-popup call
launch_call() {
  grep -E '^(split-window|display-popup)' "$CLAUDE_STUB_TMUX_LOG"
}

@test "--split outside tmux is an error" {
  unset TMUX
  run "$SCRIPT_PATH" --split "question"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--split needs tmux"* ]]
}

@test "--popup with --history is an error" {
  run "$SCRIPT_PATH" --popup --history
  [ "$status" -eq 1 ]
  [[ "$output" == *"--popup runs a question or a chat"* ]]
}

@test "--split= takes h, v or auto" {
  run "$SCRIPT_PATH" --split=x "question"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--split= takes h, v or auto"* ]]
}

@test "--split with a question: a detached pane that answers, then chats" {
  run "$SCRIPT_PATH" --split -e high --theme bubbles "the question"
  [ "$status" -eq 0 ]
  launch_call | grep -q -- "^split-window -h -d -c $PWD "
  launch_call | grep -q -- " -- .*/bin/claude-ask' '--theme' 'bubbles' '--effort' 'high' '-i'$"
  [ "$(cat "$CLAUDE_STUB_TMUX_QUESTION")" = "the question" ]
  # Nothing is asked here
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "--split without a question: the chat and the focus go to the new pane" {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --split < /dev/null
  [ "$status" -eq 0 ]
  ! launch_call | grep -q -- " -d "
  ! launch_call | grep -q -- "_CLAUDE_ASK_QUESTION_TMP"
  ! launch_call | grep -q -- " '-i'$"
}

@test "--split picks the direction from the pane's size" {
  export CLAUDE_STUB_TMUX_SIZE="120 60"
  run "$SCRIPT_PATH" --split "q"
  launch_call | grep -q -- "^split-window -v -d"
  : > "$CLAUDE_STUB_TMUX_LOG"
  run "$SCRIPT_PATH" --split=h "q"
  launch_call | grep -q -- "^split-window -h -d"
  ! grep -q '^display-message' "$CLAUDE_STUB_TMUX_LOG"
}

@test "--split passes the environment tmux would not" {
  export CLAUDE_ASK_EFFORT=low
  run "$SCRIPT_PATH" --split "q"
  # In a private file, not on the command line where ps would show them
  ! launch_call | grep -q "CLAUDE_ASK_EFFORT\|SESSION_DIR\|PATH="
  local envfile
  envfile=$(launch_call | grep -o "_CLAUDE_ASK_ENV_FILE=[^' ]*" | cut -d= -f2)
  [ "$(stat -c %a "$envfile")" = 600 ]
  grep -q '^export CLAUDE_ASK_EFFORT=low$' "$envfile"
  grep -q "^export SESSION_DIR=" "$envfile"
  grep -q "^export PATH=" "$envfile"
}

@test "the environment file holds all that is exported, but the pane's own" {
  export ANTHROPIC_API_KEY=secret-key HTTPS_PROXY='http://p:1' WITH_NEWLINE=$'a\nb c'
  run "$SCRIPT_PATH" --split "q"
  local envfile
  envfile=$(launch_call | grep -o "_CLAUDE_ASK_ENV_FILE=[^' ]*" | cut -d= -f2)
  ! launch_call | grep -q secret-key
  grep -q '^export ANTHROPIC_API_KEY=secret-key$' "$envfile"
  ! grep -qE '^export (TMUX|TMUX_PANE|TERM|COLUMNS|LINES|PWD|OLDPWD|SHLVL)=' "$envfile"
  # Read back as it was, and deleted by the run that reads it
  [ "$(bash -c "source '$envfile'; printf %s \"\$WITH_NEWLINE\"")" = $'a\nb c' ]
}

@test "an environment file owned by someone else, or missing, is ignored" {
  run env _CLAUDE_ASK_ENV_FILE="$TEST_TEMP_DIR/missing" "$SCRIPT_PATH" --version
  [ "$status" -eq 0 ]
}

@test "--split: the new pane reads the question file, deletes it and answers" {
  export CLAUDE_STUB_TMUX_RUN=1 CLAUDE_ASK_FORCE_INTERACTIVE=1
  run "$SCRIPT_PATH" --split "a question with 'quotes' and \$dollars"
  [ "$status" -eq 0 ]
  grep -qF "| a question with 'quotes' and \$dollars" "$CLAUDE_STUB_LOG"
  [[ "$output" == *"Paris"* ]]
  [ -z "$(ls "$XDG_RUNTIME_DIR" | grep claude-ask-question)" ]
}

@test "--split: a long piped question goes through the file" {
  local q
  q=$(head -c 300000 /dev/zero | tr '\0' 'x')
  run "$SCRIPT_PATH" --split < <(printf '%s' "$q")
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$CLAUDE_STUB_TMUX_QUESTION")" -eq 300000 ]
}

@test "--popup with a question: answered, then paged" {
  export CLAUDE_STUB_TMUX_RUN=1 CLAUDE_ASK_POPUP_PAGER="sed 's/^/PAGED: /'"
  run "$SCRIPT_PATH" --popup "question"
  [ "$status" -eq 0 ]
  launch_call | grep -q -- "^display-popup -E -w 80% -h 80% -d $PWD "
  launch_call | grep -q -- "_CLAUDE_ASK_PAGE_AFTER=1"
  [[ "$output" == *"PAGED: The capital of France is **Paris**."* ]]
}

@test "--popup without a question: a chat, nothing paged" {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --popup < /dev/null
  [ "$status" -eq 0 ]
  ! launch_call | grep -q -- "_CLAUDE_ASK_PAGE_AFTER"
  ! launch_call | grep -q -- "_CLAUDE_ASK_QUESTION_TMP"
}

@test "--popup -i with a question: a chat after the answer, not paged" {
  run "$SCRIPT_PATH" --popup -i "question"
  launch_call | grep -q -- " '-i'$"
  ! launch_call | grep -q -- "_CLAUDE_ASK_PAGE_AFTER"
}

@test "CLAUDE_ASK_POPUP_SIZE sets the width, or width and height" {
  CLAUDE_ASK_POPUP_SIZE=60% run "$SCRIPT_PATH" --popup "q"
  launch_call | grep -q -- "-w 60% -h 60%"
  : > "$CLAUDE_STUB_TMUX_LOG"
  CLAUDE_ASK_POPUP_SIZE=100x30 run "$SCRIPT_PATH" --popup "q"
  launch_call | grep -q -- "-w 100 -h 30"
}

@test "-y and -Y are passed on to the new claude-ask" {
  run "$SCRIPT_PATH" --split --yank-code=2 "q"
  launch_call | grep -q -- " '--yank-code=2' "
  : > "$CLAUDE_STUB_TMUX_LOG"
  run "$SCRIPT_PATH" --popup -y "q"
  launch_call | grep -q -- " '--yank'"
}

@test "--popup: the run's own exit status is passed on, not called a tmux failure" {
  export CLAUDE_STUB_TMUX_RUN=1 CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/result_error.jsonl"
  export CLAUDE_ASK_POPUP_PAGER=cat
  run "$SCRIPT_PATH" --popup "q" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid API key"* ]]
  [[ "$output" != *"could not start"* ]]
  [ -z "$(ls "$XDG_RUNTIME_DIR" | grep claude-ask-env)" ]
}

@test "--popup: when tmux fails it says so and removes its files" {
  export CLAUDE_STUB_TMUX_EXIT=1
  run "$SCRIPT_PATH" --popup "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tmux could not start the popup"* ]]
  [ -z "$(ls "$XDG_RUNTIME_DIR" | grep 'claude-ask-\(question\|env\)')" ]
}

@test "when tmux fails the question file is removed and it says so" {
  export CLAUDE_STUB_TMUX_EXIT=1
  run "$SCRIPT_PATH" --split "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tmux could not start the split"* ]]
  [ -z "$(ls "$XDG_RUNTIME_DIR" | grep claude-ask-question)" ]
}

@test "shell_command: one command line that bash, zsh and fish read the same" {
  source_claude_ask
  local line want
  shell_command line printf '%s\n' plain "two words" "it's" 'a"b' '$HOME' $'new\nline' '*' '\back'
  want=$(printf '%s\n' plain "two words" "it's" 'a"b' '$HOME' $'new\nline' '*' '\back')
  [ "$(bash -c "$line")" = "$want" ]
  if command -v zsh > /dev/null; then [ "$(zsh -fc "$line")" = "$want" ]; fi
  if command -v fish > /dev/null; then [ "$(fish --no-config -c "$line")" = "$want" ]; fi
}

@test "tmux gets one word of command, with no -e" {
  export CLAUDE_ASK_EFFORT=low
  run "$SCRIPT_PATH" --popup --pager "sed 's/^/P: /'" "q"
  ! launch_call | grep -qE ' -e '
  launch_call | grep -q "^display-popup -E -w 80% -h 80% -d $PWD -- 'env' '_CLAUDE_ASK_ENV_FILE="
}

@test "a pager with quotes survives the trip" {
  export CLAUDE_STUB_TMUX_RUN=1 CLAUDE_ASK_POPUP_PAGER=cat
  run "$SCRIPT_PATH" --popup --pager "sed 's/^/P: /'" "q"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P: The capital of France"* ]]
}
