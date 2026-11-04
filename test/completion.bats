#!/usr/bin/env bats
# Test what --completions prints: the bash script by calling its function, the
# zsh one for syntax, with _arguments stubbed, the fish one with fish itself, and
# all three against the options --help lists

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  BASH_COMP="$TEST_TEMP_DIR/claude-ask.bash"
  ZSH_COMP="$TEST_TEMP_DIR/_claude-ask"
  FISH_COMP="$TEST_TEMP_DIR/claude-ask.fish"
  "$SCRIPT_PATH" --completions bash > "$BASH_COMP"
  "$SCRIPT_PATH" --completions zsh > "$ZSH_COMP"
  "$SCRIPT_PATH" --completions=fish > "$FISH_COMP"
  # shellcheck disable=SC1090 # generated above
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
# ("-e, --effort LEVEL  Effort ..." gives -e, --effort)
help_options() {
  "$SCRIPT_PATH" --help | sed -n '/^Options/,/^Examples:/p' | grep -E '^ +-' |
    grep -oE '^ +-[^ ]*(, --?[^ ]*)?' | grep -oE -- '--?[a-zA-Z][a-zA-Z-]*' | sort -u
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

@test "all three cover every option --help lists" {
  local opt missing=()
  while IFS= read -r opt; do
    [[ " $(echo $_claude_ask_options) " == *" $opt "* ]] || missing+=("bash:$opt")
    grep -qF -e "$opt[" -e "$opt=[" -e "$opt=-[" -e "{$opt," -e ",$opt}" -e ")$opt[" "$ZSH_COMP" || missing+=("zsh:$opt")
    case "$opt" in
      --*) grep -qE -- "-l ${opt#--}( |\$)" "$FISH_COMP" || missing+=("fish:$opt") ;;
      *) grep -qE -- "-s ${opt#-}( |\$)" "$FISH_COMP" || missing+=("fish:$opt") ;;
    esac
  done < <(help_options)
  [ "$(help_options | wc -l)" -gt 20 ]
  if ((${#missing[@]})); then
    printf 'missing: %s\n' "${missing[@]}"
    false
  fi
}

@test "all three offer the same themes, models and effort levels as the script" {
  source_claude_ask
  local efforts="${EFFORT_LEVELS//,/}" comp_script="" list
  for list in "${THEMES[*]}" "${MODEL_ALIASES[*]}" "$efforts"; do
    grep -qF -- "_claude_ask_reply \"\$cur\" $list" "$BASH_COMP"
    grep -qF -- "=($list)" "$ZSH_COMP"
    grep -qF -- "-a '$list'" "$FISH_COMP"
  done
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
    compdef() { }
    source "$1"
    _claude-ask_sessions' zsh "$ZSH_COMP"
  [ "$status" -eq 0 ]
  [ "$output" = $'newest\nmiddle\nold-one' ]
}

@test "zsh: _arguments gets every spec, with the value lists filled in" {
  command -v zsh > /dev/null || skip "zsh is not installed"
  run zsh -fc '
    _arguments() { print -rl -- "$@" }
    compdef() { }
    source "$1"
    _claude-ask' zsh "$ZSH_COMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[effort (thinking) level]:level:(low medium high xhigh max)"* ]]
  [[ "$output" == *"--theme=[status bar theme]:theme:(minimal bubbles powerline)"* ]]
  [[ "$output" == *"--resume=-["*"::session:_claude-ask_sessions"* ]]
}

@test "zsh: sourced it registers itself, autoloaded it completes" {
  command -v zsh > /dev/null || skip "zsh is not installed"
  run zsh -fc 'compdef() { print -r -- "compdef $*" }; source "$1"' zsh "$ZSH_COMP"
  [ "$output" = "compdef _claude-ask claude-ask" ]
  head -1 "$ZSH_COMP" | grep -qx '#compdef claude-ask'
}

@test "--completions: each shell, and anything else is refused" {
  for shell in bash zsh fish; do
    run "$SCRIPT_PATH" --completions "$shell"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-ask"* ]]
  done
  run "$SCRIPT_PATH" --completions powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"takes bash, zsh or fish"* ]]
  run "$SCRIPT_PATH" --completions
  [ "$status" -eq 1 ]
}

@test "--completions needs nothing else: a copy of the script alone, no jq" {
  mkdir "$TEST_TEMP_DIR/alone"
  cp "$SCRIPT_PATH" "$TEST_TEMP_DIR/alone/claude-ask"
  run env PATH="/usr/bin:/bin" "$TEST_TEMP_DIR/alone/claude-ask" --completions fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -c claude-ask"* ]]
  mkdir "$TEST_TEMP_DIR/nojq"
  ln -s "$(command -v bash)" "$TEST_TEMP_DIR/nojq/bash"
  ln -s "$(command -v cat)" "$TEST_TEMP_DIR/nojq/cat"
  ln -s "$(command -v env)" "$TEST_TEMP_DIR/nojq/env"
  run env PATH="$TEST_TEMP_DIR/nojq" "$TEST_TEMP_DIR/alone/claude-ask" --completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F _claude_ask claude-ask"* ]]
}

@test "bash: eval of what it prints works, and completes the shell names" {
  run bash -c 'eval "$("$1" --completions bash)"; complete -p claude-ask' bash "$SCRIPT_PATH"
  [[ "$output" == *"-F _claude_ask claude-ask"* ]]
  comp --completions ""
  [ "${COMPREPLY[*]}" = "bash zsh fish" ]
  comp --completions = z
  [ "${COMPREPLY[*]}" = "zsh" ]
}

# fish_complete LINE: what real fish offers for LINE, one candidate a line
fish_complete() {
  run fish --no-config -c 'source $argv[1]; complete -C"$argv[2]"' "$FISH_COMP" "$1"
}

@test "fish: the script parses" {
  command -v fish > /dev/null || skip "fish is not installed"
  run fish --no-config --no-execute "$FISH_COMP"
  [ "$status" -eq 0 ]
}

@test "fish: options and their values complete" {
  command -v fish > /dev/null || skip "fish is not installed"
  fish_complete "claude-ask --the"
  [[ "$output" == --theme* ]]
  fish_complete "claude-ask --theme "
  [[ "$output" == *minimal* && "$output" == *powerline* ]]
  fish_complete "claude-ask --theme=b"
  [[ "$output" == *"--theme=bubbles"* ]]
  fish_complete "claude-ask -e "
  [[ "$output" == *xhigh* ]]
  fish_complete "claude-ask --completions "
  [[ "$output" == *bash* && "$output" == *fish* ]]
}

@test "fish: session names newest first, and the question gets no file names" {
  command -v fish > /dev/null || skip "fish is not installed"
  session old-one 30
  session newest 1
  fish_complete "claude-ask --session "
  [ "${lines[0]%%$'\t'*}" = "newest" ]
  [ "${lines[1]%%$'\t'*}" = "old-one" ]
  fish_complete "claude-ask --delete new"
  [[ "$output" == newest* ]]
  : > "$TEST_TEMP_DIR/some-file"
  cd "$TEST_TEMP_DIR"
  fish_complete "claude-ask some"
  [ -z "$output" ]
  # --debug-log does take files
  fish_complete "claude-ask --debug-log=some"
  [[ "$output" == *"some-file"* ]]
}

@test "fish: no session directory gives no names and no errors" {
  command -v fish > /dev/null || skip "fish is not installed"
  export SESSION_DIR="$TEST_TEMP_DIR/missing"
  fish_complete "claude-ask --session "
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
