#!/usr/bin/env bats
# Test Tab completion at the chat prompt: chat_complete's line, cursor and
# list (the pseudo-terminal tests in chat_terminal.bats cover the binding)

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  source_claude_ask
}

# complete LINE [POINT]: chat_complete with the cursor at POINT (the end)
complete() {
  local point="${2:-${#1}}"
  chat_complete "$1" "$point"
}

@test "complete: a unique command prefix completes, with a space" {
  complete "/eff"
  [ "$COMPLETE_LINE" = "/effort " ]
  [ "$COMPLETE_POINT" -eq 8 ]
  [ "${#COMPLETE_LIST[@]}" -eq 0 ]
}

@test "complete: an ambiguous prefix lists its matches" {
  complete "/e"
  [ "$COMPLETE_LINE" = "/e" ]
  [ "$COMPLETE_POINT" -eq 2 ]
  [ "${COMPLETE_LIST[*]}" = "/effort /editor /exit" ]
}

@test "complete: matches are extended as far as they agree" {
  complete "/ex"
  [ "$COMPLETE_LINE" = "/exit " ]
  complete "/ed"
  [ "$COMPLETE_LINE" = "/editor " ]
}

@test "complete: / alone lists every command" {
  complete "/"
  [ "${#COMPLETE_LIST[@]}" -eq "${#CHAT_COMMANDS[@]}" ]
  [[ " ${COMPLETE_LIST[*]} " == *" /help "* ]]
  [[ " ${COMPLETE_LIST[*]} " == *" /quit "* ]]
}

@test "complete: effort levels and default" {
  complete "/effort hi"
  [ "$COMPLETE_LINE" = "/effort high " ]
  complete "/effort x"
  [ "$COMPLETE_LINE" = "/effort xhigh " ]
  complete "/effort m"
  [ "${COMPLETE_LIST[*]}" = "medium max" ]
  complete "/effort d"
  [ "$COMPLETE_LINE" = "/effort default " ]
}

@test "complete: an empty argument lists all of them" {
  complete "/effort "
  [ "${COMPLETE_LIST[*]}" = "low medium high xhigh max default" ]
  complete "/theme "
  [ "${COMPLETE_LIST[*]}" = "minimal bubbles powerline" ]
}

@test "complete: model aliases, themes and /yank code" {
  complete "/model so"
  [ "$COMPLETE_LINE" = "/model sonnet " ]
  complete "/model f"
  [ "$COMPLETE_LINE" = "/model fable " ]
  complete "/theme p"
  [ "$COMPLETE_LINE" = "/theme powerline " ]
  complete "/yank c"
  [ "$COMPLETE_LINE" = "/yank code " ]
}

@test "complete: a question gets a literal tab" {
  complete "what is"
  [ "$COMPLETE_LINE" = $'what is\t' ]
  [ "$COMPLETE_POINT" -eq 8 ]
  [ "${#COMPLETE_LIST[@]}" -eq 0 ]
  complete ""
  [ "$COMPLETE_LINE" = $'\t' ]
}

@test "complete: no match gets a literal tab" {
  complete "/zz"
  [ "$COMPLETE_LINE" = $'/zz\t' ]
  complete "/effort turbo"
  [ "$COMPLETE_LINE" = $'/effort turbo\t' ]
  # A path is not a command
  complete "/etc/hosts"
  [ "$COMPLETE_LINE" = $'/etc/hosts\t' ]
}

@test "complete: commands without arguments to complete get a tab" {
  complete "/help "
  [ "$COMPLETE_LINE" = $'/help \t' ]
  complete "/yank code "
  [ "$COMPLETE_LINE" = $'/yank code \t' ]
}

@test "complete: the text after the cursor is kept" {
  complete "/eff high" 4
  # A space already follows, so none is added
  [ "$COMPLETE_LINE" = "/effort high" ]
  [ "$COMPLETE_POINT" -eq 7 ]
  complete "/effx" 4
  [ "$COMPLETE_LINE" = "/effort x" ]
  [ "$COMPLETE_POINT" -eq 8 ]
}

@test "complete: a tab goes in at the cursor" {
  complete "ab" 1
  [ "$COMPLETE_LINE" = $'a\tb' ]
  [ "$COMPLETE_POINT" -eq 2 ]
}

@test "complete: works with an empty IFS, as inside read" {
  IFS= chat_complete "/effort hi" 10
  [ "$COMPLETE_LINE" = "/effort high " ]
}

@test "complete: every chat command is one chat_command knows" {
  local c
  for c in "${CHAT_COMMANDS[@]}"; do
    [[ "$c" == /editor ]] && continue
    run grep -qE "^    ($c|[^)]*\\| $c)[ )]" "$SCRIPT_PATH"
    [ "$status" -eq 0 ] || { echo "not in chat_command: $c"; false; }
  done
}
