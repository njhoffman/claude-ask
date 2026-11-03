#!/usr/bin/env bats
# Test the effort level and model: -e/--effort, -m/--model, their
# environment defaults, the status bar, session files, -r and the chat's
# slash commands

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  export CLAUDE_STUB_ARGS="$TEST_TEMP_DIR/claude-args"
}

# chat LINES...: run the script as a chat fed these lines on stdin
chat() {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager "${CHAT_ARGS[@]}" < <(printf '%s\n' "$@")
}

# args_after FLAG: the argument claude got after FLAG (one per line in
# CLAUDE_STUB_ARGS), empty when FLAG was not passed
args_after() {
  grep -x -A1 -- "$1" "$CLAUDE_STUB_ARGS" | sed -n 2p
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
@test "-e and -m are passed to claude" {
  run "$SCRIPT_PATH" --no-pager -e high -m sonnet "question"
  [ "$status" -eq 0 ]
  [ "$(args_after --effort)" = "high" ]
  [ "$(args_after --model)" = "sonnet" ]
}

@test "--effort and --model are the long forms" {
  run "$SCRIPT_PATH" --no-pager --effort xhigh --model claude-opus-5-5 "question"
  [ "$status" -eq 0 ]
  [ "$(args_after --effort)" = "xhigh" ]
  [ "$(args_after --model)" = "claude-opus-5-5" ]
}

@test "without -e or -m claude gets neither flag" {
  run "$SCRIPT_PATH" --no-pager "question"
  [ "$status" -eq 0 ]
  ! grep -qx -- "--effort" "$CLAUDE_STUB_ARGS"
  ! grep -qx -- "--model" "$CLAUDE_STUB_ARGS"
}

@test "an unknown effort level is an error and claude is not run" {
  run "$SCRIPT_PATH" --no-pager -e extreme "question"
  [ "$status" -eq 1 ]
  [[ "$output" == *"effort must be one of: low, medium, high, xhigh, max"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "-e and -m need an argument" {
  run "$SCRIPT_PATH" -e
  [ "$status" -eq 1 ]
  [[ "$output" == *"-e requires an argument"* ]]
  run "$SCRIPT_PATH" --model
  [ "$status" -eq 1 ]
  [[ "$output" == *"--model requires an argument"* ]]
}

@test "CLAUDE_ASK_EFFORT and CLAUDE_ASK_MODEL are the defaults; -e and -m win" {
  CLAUDE_ASK_EFFORT=low CLAUDE_ASK_MODEL=haiku run "$SCRIPT_PATH" --no-pager "question"
  [ "$(args_after --effort)" = "low" ]
  [ "$(args_after --model)" = "haiku" ]
  CLAUDE_ASK_EFFORT=low CLAUDE_ASK_MODEL=haiku run "$SCRIPT_PATH" --no-pager -e max -m opus "question"
  [ "$(args_after --effort)" = "max" ]
  [ "$(args_after --model)" = "opus" ]
}

@test "a bad CLAUDE_ASK_EFFORT is an error" {
  CLAUDE_ASK_EFFORT=huge run "$SCRIPT_PATH" --no-pager "question"
  [ "$status" -eq 1 ]
  [[ "$output" == *"effort must be one of"* ]]
}

# ---------------------------------------------------------------------------
# Status bar
# ---------------------------------------------------------------------------
@test "model_label adds the effort after the model" {
  source_claude_ask
  local label
  model_label label "opus 5.5" "high"
  [ "$(printf '%s' "$label" | strip_ansi)" = "opus 5.5 · high" ]
  model_label label "opus 5.5" ""
  [ "$label" = "opus 5.5" ]
}

@test "the status bar shows the model version and the effort in every theme" {
  local theme
  for theme in minimal bubbles powerline; do
    run "$SCRIPT_PATH" --no-pager --theme "$theme" -e high "question"
    [ "$status" -eq 0 ]
    output_clean=$(echo "$output" | strip_ansi)
    [[ "$output_clean" == *"sonnet 4.5 · high"* ]]
  done
}

@test "the status bar shows no effort when none was given" {
  run "$SCRIPT_PATH" --no-pager "question"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"sonnet 4.5"* ]]
  [[ "$output_clean" != *"·"* ]]
}

@test "--demo-themes shows a model version and effort" {
  run "$SCRIPT_PATH" --demo-themes
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"opus 5.5 · high"* ]]
}

# ---------------------------------------------------------------------------
# Session files, replay and -r
# ---------------------------------------------------------------------------
@test "each turn records its model, effort and -m option" {
  run "$SCRIPT_PATH" --no-pager -e medium -m sonnet "first question"
  [ "$status" -eq 0 ]
  local file="$SESSION_DIR/first-question.json"
  [ "$(jq -r '.turns[0].effort' "$file")" = "medium" ]
  [ "$(jq -r '.turns[0].model_option' "$file")" = "sonnet" ]
  [ "$(jq -r '.turns[0].model' "$file")" = "claude-sonnet-4-5[200k]" ]
  [ "$(jq -r '.effort' "$file")" = "medium" ]
}

@test "without -e or -m the turn's effort and model_option are null" {
  run "$SCRIPT_PATH" --no-pager "first question"
  local file="$SESSION_DIR/first-question.json"
  [ "$(jq -r '.turns[0].effort' "$file")" = "null" ]
  [ "$(jq -r '.turns[0].model_option' "$file")" = "null" ]
}

@test "--session shows each turn's model and effort" {
  jq -n '{session_id: "s1", model: "claude-opus-5-5", name: "mixed",
    question: "q1", answer: "a2", timestamp: "2026-11-01T00:00:00Z",
    turns: [
      {question: "q1", answer: "a1", model: "claude-sonnet-4-5", effort: "low"},
      {question: "q2", answer: "a2", effort: null}]}' > "$SESSION_DIR/mixed.json"
  run "$SCRIPT_PATH" --no-pager --session mixed
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"sonnet 4.5 · low"* ]]
  # The second turn has no model of its own: the session's is used
  [[ "$output_clean" == *"opus 5.5 "* ]]
  [[ "$output_clean" != *"opus 5.5 ·"* ]]
}

# saved_session NAME EFFORT MODEL_OPTION: a one-turn session file
saved_session() {
  jq -n --arg e "$2" --arg m "$3" '{session_id: "old-id", model: "claude-opus-5-5",
    name: "saved", question: "q", answer: "a", timestamp: "2026-11-01T00:00:00Z",
    turns: [{question: "q", answer: "a", model: "claude-opus-5-5",
             effort: $e, model_option: $m}]}' > "$SESSION_DIR/$1.json"
}

@test "-r keeps the session's effort and model" {
  saved_session saved high opus
  run "$SCRIPT_PATH" --no-pager -r "follow up" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(args_after --effort)" = "high" ]
  [ "$(args_after --model)" = "opus" ]
}

@test "-r with -e and -m uses those instead" {
  saved_session saved high opus
  run "$SCRIPT_PATH" --no-pager -r -e low -m haiku "follow up" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(args_after --effort)" = "low" ]
  [ "$(args_after --model)" = "haiku" ]
}

# ---------------------------------------------------------------------------
# Chat slash commands
# ---------------------------------------------------------------------------
@test "chat: /effort and /model change the flags for the next question" {
  CHAT_ARGS=()
  chat "one" "/effort max" "/model haiku" "two" "/effort default" "/model default" "three"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 3 ]
  ! sed -n 1p "$CLAUDE_STUB_LOG" | grep -q -- "--effort"
  sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--effort max --model haiku | two"
  ! sed -n 3p "$CLAUDE_STUB_LOG" | grep -q -- "--effort\|--model"
}

@test "chat: /effort and /model with no argument show the current value" {
  CHAT_ARGS=(-e medium)
  chat "/effort" "/model"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"effort: medium"* ]]
  [[ "$output_clean" == *"model: default"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "chat: a bad /effort level or /model name is refused and changes nothing" {
  CHAT_ARGS=(-e low)
  chat "/effort huge" "/model two words" "q"
  [[ "$output" == *"effort must be one of"* ]]
  [[ "$output" == *"a model name has no spaces"* ]]
  grep -q -- "--effort low | q" "$CLAUDE_STUB_LOG"
  ! grep -q -- "--model" "$CLAUDE_STUB_LOG"
}

@test "chat: the status bar follows /effort" {
  CHAT_ARGS=()
  chat "/effort xhigh" "q"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"sonnet 4.5 · xhigh"* ]]
}

@test "chat: opens with a hint about /help" {
  CHAT_ARGS=()
  chat "exit"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == "/help for commands"* ]]
}

@test "chat: /help lists the commands" {
  CHAT_ARGS=()
  chat "/help"
  [ "$status" -eq 0 ]
  local cmd
  for cmd in /help /effort /model /theme /status /new /editor /exit; do
    [[ "$output" == *"$cmd"* ]]
  done
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "chat: /status shows the conversation, model, effort and theme" {
  CHAT_ARGS=(-e high --theme bubbles)
  chat "/status" "first question" "/status"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"session: new conversation"* ]]
  [[ "$output_clean" == *"session: first-question (1 turn, \$0.0123)"* ]]
  [[ "$output_clean" == *"model:   default (last answer: sonnet 4.5)"* ]]
  [[ "$output_clean" == *"effort:  high"* ]]
  [[ "$output_clean" == *"theme:   bubbles"* ]]
}

@test "chat: /new starts a new conversation in a new file" {
  CHAT_ARGS=()
  chat "first question" "/new" "second question"
  [ "$status" -eq 0 ]
  ! sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--resume"
  [ -f "$SESSION_DIR/first-question.json" ]
  [ -f "$SESSION_DIR/second-question.json" ]
}

@test "chat: /theme changes the theme and refuses unknown ones" {
  CHAT_ARGS=()
  chat "/theme powerline" "/theme" "/theme neon"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"theme: powerline"* ]]
  [[ "$output" == *"theme must be one of"* ]]
}

@test "chat: /exit and /quit end it" {
  CHAT_ARGS=()
  chat "/exit" "never asked"
  [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_STUB_LOG" ]
  chat "/quit" "never asked"
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "chat: /editor composes the question in \$EDITOR" {
  local editor="$TEST_TEMP_DIR/editor"
  printf '#!/bin/bash\nprintf "from the editor" > "$1"\n' > "$editor"
  chmod +x "$editor"
  export EDITOR="$editor"
  CHAT_ARGS=()
  chat "/editor"
  grep -q '| from the editor$' "$CLAUDE_STUB_LOG"
}

@test "chat: an unknown /word is refused; a path is asked as a question" {
  CHAT_ARGS=()
  chat "/modle opus" "/etc/hosts: what is this?"
  [[ "$output" == *"unknown command /modle (/help lists them)"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  grep -q '| /etc/hosts: what is this?$' "$CLAUDE_STUB_LOG"
}

@test "chat: commands go to the history file" {
  CHAT_ARGS=()
  chat "/effort high" "q"
  grep -qx "/effort high" "$XDG_STATE_HOME/claude-ask/history"
}

# ---------------------------------------------------------------------------
# A model claude does not know
# ---------------------------------------------------------------------------
@test "-m with an unknown model: claude's message, exit 1, nothing saved" {
  export CLAUDE_STUB_UNKNOWN_MODEL=nosuchmodel
  run "$SCRIPT_PATH" --no-pager -m nosuchmodel "question"
  [ "$status" -eq 1 ]
  [[ "$output" == *"issue with the selected model (nosuchmodel)"* ]]
  [[ "$output" == *"model nosuchmodel not found; back to the default model"* ]]
  [ -z "$(ls -A "$SESSION_DIR")" ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

@test "an unknown model's message is not shown as the answer" {
  export CLAUDE_STUB_UNKNOWN_MODEL=nosuchmodel
  run --separate-stderr "$SCRIPT_PATH" --no-pager -m nosuchmodel "question"
  [[ "$output" != *"issue with the selected model"* ]]
  [[ "$stderr" == *"issue with the selected model"* ]]
}

@test "chat: an unknown /model goes back to the last model that answered" {
  export CLAUDE_STUB_UNKNOWN_MODEL=nosuchmodel
  CHAT_ARGS=(-m sonnet)
  chat "one" "/model nosuchmodel" "two" "three"
  [[ "$output" == *"model nosuchmodel not found; back to sonnet"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 3 ]
  sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--model nosuchmodel | two"
  # Not retried: the next question is asked with sonnet, in the same
  # conversation, and the failed turn is not in the file
  sed -n 3p "$CLAUDE_STUB_LOG" | grep -q -- "--resume full-session-001 --model sonnet | three"
  [ "$(jq -r '[.turns[].question] | join(",")' "$SESSION_DIR/one.json")" = "one,three" ]
}

@test "chat: with no model that answered yet it goes back to the default" {
  export CLAUDE_STUB_UNKNOWN_MODEL=nosuchmodel
  CHAT_ARGS=(-m nosuchmodel)
  chat "one" "two"
  [[ "$output" == *"back to the default model"* ]]
  ! sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--model"
  ! sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--resume"
}

@test "-r: a saved model that is gone is retried with the default" {
  export CLAUDE_STUB_UNKNOWN_MODEL=retired-model
  saved_session saved high retired-model
  run "$SCRIPT_PATH" --no-pager -r "follow up" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"model retired-model not found; back to the default model"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  sed -n 1p "$CLAUDE_STUB_LOG" | grep -q -- "--resume old-id --effort high --model retired-model | follow up"
  sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--resume old-id --effort high | follow up"
  [ "$(jq -r '.turns | length' "$SESSION_DIR/saved.json")" = "2" ]
  [ "$(jq -r '.turns[1].model_option' "$SESSION_DIR/saved.json")" = "null" ]
}
