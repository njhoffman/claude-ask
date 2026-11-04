#!/usr/bin/env bats
# Test the shell completion files in completions/: the bash one by calling
# its function, the zsh one for syntax and with _arguments stubbed, and
# both against the options --help lists

bats_require_minimum_version 1.5.0

load test_helper

BASH_COMP="${SCRIPT_DIR}/completions/claude-ask.bash"
ZSH_COMP="${SCRIPT_DIR}/completions/_claude-ask"

setup() {
  common_setup
  # shellcheck source=../completions/claude-ask.bash
  source "$BASH_COMP"
}

# comp WORD...: complete the last WORD of "claude-ask WORD...", as bash
# splits it (an = is a word of its own)
comp() {
  COMP_WORDS=(claude-ask "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  _claude_ask
}

# session NAME AGE: a saved session file AGE minutes old
session() {
  printf '{}\n' > "$SESSION_DIR/$1.json"
  touch -d "-$2 minutes" "$SESSION_DIR/$1.json"
}

# The options --help lists in its Options section: the start of each line
# that begins with one ("-e, --effort LEVEL Effort ..." gives -e, --effort)
help_options() {
  "$SCRIPT_PATH" --help | sed -n '/^Options/,/^Examples:/p' | grep -E '^  -' |
    grep -oE '^  -[^ ]*(, --?[^ ]*)?' | grep -oE -- '--?[a-zA-Z][a-zA-Z-]*' | sort -u
}

@test "bash: options complete from -" {
  comp --th
  [ "${COMPREPLY[*]}" = "--theme --theme=" ]
  comp --no-
  [ "${COMPREPLY[*]}" = "--no-pager --no-stream" ]
}

@test "bash: effort levels, models and themes" {
  comp -e h
  [ "${COMPREPLY[*]}" = "high" ]
  comp --effort ""
  [ "${COMPREPLY[*]}" = "low medium high xhigh max" ]
  comp -m s
  [ "${COMPREPLY[*]}" = "sonnet" ]
  comp --theme ""
  [ "${COMPREPLY[*]}" = "minimal bubbles powerline" ]
}

@test "bash: --session completes saved session names" {
  session git-rebase 5
  session git-bisect 1
  session docker-volumes 3
  comp --session git
  [ "${#COMPREPLY[@]}" -eq 2 ]
  [[ " ${COMPREPLY[*]} " == *" git-rebase "* ]]
  [[ " ${COMPREPLY[*]} " == *" git-bisect "* ]]
  # An option after --session (it takes an optional argument)
  comp --session --hi
  [ "${COMPREPLY[*]}" = "--history --history=" ]
}

@test "bash: --resume= completes session names after the =" {
  session git-rebase 5
  session docker-volumes 3
  comp --resume = d
  [ "${COMPREPLY[*]}" = "docker-volumes" ]
  comp --resume =
  [ "${#COMPREPLY[@]}" -eq 2 ]
  # Without = in COMP_WORDBREAKS the word is not split
  comp --resume=gi
  [ "${COMPREPLY[*]}" = "git-rebase" ]
}

@test "bash: no sessions, no names" {
  comp --session ""
  [ "${#COMPREPLY[@]}" -eq 0 ]
  export SESSION_DIR="$TEST_TEMP_DIR/missing"
  comp --resume = ""
  [ "${#COMPREPLY[@]}" -eq 0 ]
}

@test "bash: --split= directions and --debug-log= files" {
  comp --split = ""
  [ "${COMPREPLY[*]}" = "h v auto" ]
  touch "$TEST_TEMP_DIR/ask.log"
  comp --debug-log = "$TEST_TEMP_DIR/ask"
  [ "${COMPREPLY[*]}" = "$TEST_TEMP_DIR/ask.log" ]
}

@test "bash: values after = for every option that takes them" {
  comp --effort = h
  [ "${COMPREPLY[*]}" = "high" ]
  comp --model = s
  [ "${COMPREPLY[*]}" = "sonnet" ]
  comp --theme = p
  [ "${COMPREPLY[*]}" = "powerline" ]
  session git-rebase 5
  comp --session = g
  [ "${COMPREPLY[*]}" = "git-rebase" ]
}

@test "bash: options ending in = are offered" {
  comp --resume
  [[ " ${COMPREPLY[*]} " == *" --resume= "* ]]
  comp --yank
  [ "${COMPREPLY[*]}" = "--yank --yank-code --yank-code=" ]
  # As one word, --yank-code= is at its value, a number: nothing to offer
  comp --yank-code=
  [ "${#COMPREPLY[@]}" -eq 0 ]
}

@test "bash: the question gets nothing" {
  comp "what is"
  [ "${#COMPREPLY[@]}" -eq 0 ]
  comp -e high ""
  [ "${#COMPREPLY[@]}" -eq 0 ]
}

@test "bash: it is registered for claude-ask" {
  run complete -p claude-ask
  [ "$status" -eq 0 ]
  [[ "$output" == *"-F _claude_ask claude-ask"* ]]
}

@test "both files cover every option --help lists" {
  local opt missing=()
  while IFS= read -r opt; do
    [[ " $(echo $_claude_ask_options) " == *" $opt "* ]] || missing+=("bash:$opt")
    grep -qF -e "$opt[" -e "$opt=[" -e "$opt=-[" -e "{$opt," -e ",$opt}" -e ")$opt[" "$ZSH_COMP" || missing+=("zsh:$opt")
  done < <(help_options)
  [ "$(help_options | wc -l)" -gt 20 ]
  if ((${#missing[@]})); then
    printf 'missing: %s\n' "${missing[@]}"
    false
  fi
}

@test "bash: shellcheck is clean" {
  command -v shellcheck > /dev/null || skip "shellcheck is not installed"
  run shellcheck -s bash "$BASH_COMP"
  [ "$status" -eq 0 ]
}

@test "zsh: the file parses" {
  command -v zsh > /dev/null || skip "zsh is not installed"
  run zsh -n "$ZSH_COMP"
  [ "$status" -eq 0 ]
}

@test "zsh: sessions are offered newest first" {
  command -v zsh > /dev/null || skip "zsh is not installed"
  session old-one 30
  session newest 1
  session middle 10
  # _arguments and _describe stubbed: print what they are given
  run zsh -fc '
    _arguments() { print -rl -- "$@" }
    _describe() { print -rl -- "${(@P)${@[-1]}}" }
    source "$1" > /dev/null
    _claude-ask_sessions' zsh "$ZSH_COMP"
  [ "$status" -eq 0 ]
  [ "$output" = $'newest\nmiddle\nold-one' ]
}

@test "zsh: _arguments gets every spec, with the value lists filled in" {
  command -v zsh > /dev/null || skip "zsh is not installed"
  run zsh -fc '
    _arguments() { print -rl -- "$@" }
    source "$1"' zsh "$ZSH_COMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[effort (thinking) level]:level:(low medium high xhigh max)"* ]]
  [[ "$output" == *"--theme=[status bar theme]:theme:(minimal bubbles powerline)"* ]]
  [[ "$output" == *"--resume=-["*"::session:_claude-ask_sessions"* ]]
}
