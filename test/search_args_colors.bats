#!/usr/bin/env bats
# Test --search, --history=N, --delete, --prune, what is passed on to claude,
# OSC 52 and the color depth

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  PTY="$BATS_TEST_DIRNAME/helpers/pty_run.py"
  # OSC 52 is not sent to a dumb terminal, which CI's TERM may be
  export TERM=xterm-256color
}

# session NAME QUESTION ANSWER AGE_DAYS: a saved session that old
session() {
  local stamp
  stamp=$(jq -rn --argjson d "$4" '(now - $d * 86400) | floor | todate')
  jq -n --arg q "$2" --arg a "$3" --arg t "$stamp" --arg n "$1" \
    '{name: $n, session_id: $n, question: $q, answer: $a, timestamp: $t, turn_count: 1,
      turns: [{question: $q, answer: $a, timestamp: $t}]}' > "$SESSION_DIR/$1.json"
  touch -d "-$4 days" "$SESSION_DIR/$1.json"
}

three_sessions() {
  session newest "About git rebase" "Use --onto." 1
  session middle "About docker" "Volumes persist. GIT is not involved." 10
  session oldest "About cats" "They sleep." 100
}

@test "--history=N shows the newest N" {
  three_sessions
  run "$SCRIPT_PATH" --history=2
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"newest"* && "$output" == *"middle"* && "$output" != *"oldest"* ]]
  run "$SCRIPT_PATH" --history=0
  [ "$status" -eq 1 ]
  run "$SCRIPT_PATH" --history=x
  [ "$status" -eq 1 ]
}

@test "--search looks in questions and answers, in any case, keeping the numbers" {
  three_sessions
  run "$SCRIPT_PATH" --search git
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "1 "*newest* ]]
  # In an answer only, and numbered as in --history
  [[ "${lines[1]}" == "2 "*middle* ]]
  run "$SCRIPT_PATH" --search=SLEEP
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "3 "*oldest* ]]
  run "$SCRIPT_PATH" --no-pager --session 3
  [[ "$output" == *"They sleep"* ]]
}

@test "--search finds text in any turn, and --history=N limits what it finds" {
  three_sessions
  jq '.turns += [{question: "later", answer: "a zebra", timestamp: .timestamp}]' "$SESSION_DIR/oldest.json" > "$TEST_TEMP_DIR/t"
  cat "$TEST_TEMP_DIR/t" > "$SESSION_DIR/oldest.json"
  touch -d "-100 days" "$SESSION_DIR/oldest.json"
  run "$SCRIPT_PATH" --search zebra
  [[ "$output" == *"oldest"* ]]
  run "$SCRIPT_PATH" --search about --history=1
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *newest* ]]
}

@test "--search: nothing found, a regex is plain text, a bad file does not stop it" {
  three_sessions
  run "$SCRIPT_PATH" --search "no such text"
  [ "$status" -eq 1 ]
  [[ "$output" == *'No saved session has "no such text"'* ]]
  run "$SCRIPT_PATH" --search "g.t"
  [ "$status" -eq 1 ]
  printf '{broken' > "$SESSION_DIR/bad.json"
  run "$SCRIPT_PATH" --search cats
  [ "$status" -eq 0 ]
  [[ "$output" == *"oldest"* ]]
  [[ "$output" != *"bad"* ]]
}

@test "--delete without a terminal refuses, and --force deletes it and its .jsonl" {
  three_sessions
  printf '{}\n' > "$SESSION_DIR/middle.jsonl"
  run "$SCRIPT_PATH" --delete middle < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"--force"* ]]
  [ -f "$SESSION_DIR/middle.json" ]
  run "$SCRIPT_PATH" --delete middle --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted 1 saved session."* ]]
  [ ! -e "$SESSION_DIR/middle.json" ]
  [ ! -e "$SESSION_DIR/middle.jsonl" ]
  [ -f "$SESSION_DIR/newest.json" ]
}

@test "--delete takes a number or a unique prefix, and refuses others" {
  three_sessions
  run "$SCRIPT_PATH" --delete=1 --force
  [ ! -e "$SESSION_DIR/newest.json" ]
  run "$SCRIPT_PATH" --delete old --force
  [ ! -e "$SESSION_DIR/oldest.json" ]
  run "$SCRIPT_PATH" --delete nosuch --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session nosuch"* ]]
  session mid2 q a 1
  run "$SCRIPT_PATH" --delete mi --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ambiguous"* ]]
  [ -f "$SESSION_DIR/middle.json" ] && [ -f "$SESSION_DIR/mid2.json" ]
}

@test "--delete at a terminal asks: only yes deletes" {
  three_sessions
  run python3 "$PTY" 'expect:[y/N]' 'send:n\r' 'sleep:0.3' -- "$SCRIPT_PATH" --delete middle
  [ "$status" -eq 1 ]
  [[ "$output" == *"middle"* && "$output" == *"Nothing deleted"* ]]
  [ -f "$SESSION_DIR/middle.json" ]
  run python3 "$PTY" 'expect:[y/N]' 'send:\r' 'sleep:0.3' -- "$SCRIPT_PATH" --delete middle
  [ -f "$SESSION_DIR/middle.json" ]
  run python3 "$PTY" 'expect:[y/N]' 'send:y\r' 'sleep:0.3' -- "$SCRIPT_PATH" --delete middle
  [ "$status" -eq 0 ]
  [ ! -e "$SESSION_DIR/middle.json" ]
}

@test "--prune deletes only what is older, by the saved time" {
  three_sessions
  # A recent time saved, an old file time: it stays
  touch -d "-400 days" "$SESSION_DIR/newest.json"
  run "$SCRIPT_PATH" --prune 30d --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"oldest"* && "$output" != *"middle"* ]]
  [[ "$output" == *"Deleted 1 saved session."* ]]
  [ ! -e "$SESSION_DIR/oldest.json" ]
  [ -f "$SESSION_DIR/newest.json" ] && [ -f "$SESSION_DIR/middle.json" ]
}

@test "--prune: units, the question, and a file with no time stays" {
  three_sessions
  printf '{broken' > "$SESSION_DIR/bad.json"
  printf '{"question":"no time"}' > "$SESSION_DIR/notime.json"
  run "$SCRIPT_PATH" --prune=2w < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"oldest"* && "$output" == *"--force"* ]]
  [ -f "$SESSION_DIR/oldest.json" ]
  run "$SCRIPT_PATH" --prune=48h --force
  [[ "$output" == *"Deleted 2 saved sessions."* ]]
  [ -f "$SESSION_DIR/newest.json" ] && [ -f "$SESSION_DIR/bad.json" ] && [ -f "$SESSION_DIR/notime.json" ]
  run "$SCRIPT_PATH" --prune=1000 --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"No saved session is older than 1000"* ]]
  run "$SCRIPT_PATH" --prune=soon
  [ "$status" -eq 1 ]
  [ -f "$SESSION_DIR/newest.json" ]
}

@test "--claude-arg and CLAUDE_ASK_ARGS reach claude, quoted, last" {
  export CLAUDE_ASK_ARGS="--append-system-prompt 'be brief, please' --verbose-not"
  run "$SCRIPT_PATH" --no-pager -m opus --claude-arg --add-dir --claude-arg=../my\ src "q"
  [ "$status" -eq 0 ]
  grep -qF -- "--model opus --append-system-prompt be brief, please --verbose-not --add-dir ../my src |" "$CLAUDE_STUB_LOG"
}

@test "what claude-ask sets itself cannot be passed on" {
  for bad in -p --print --resume=x -r --output-format --verbose --include-partial-messages; do
    run "$SCRIPT_PATH" --claude-arg="$bad" "q"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be passed on"* ]]
  done
  run "$SCRIPT_PATH" --claude-arg=--model=x "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"use claude-ask's own --model"* ]]
  CLAUDE_ASK_ARGS="'unmatched" run "$SCRIPT_PATH" "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unmatched quotes"* ]]
  CLAUDE_ASK_ARGS='$(touch '"$TEST_TEMP_DIR"'/ran)' run "$SCRIPT_PATH" --no-pager "q"
  [ ! -e "$TEST_TEMP_DIR/ran" ]
}

@test "-r keeps what was passed on, and says so; new ones win" {
  run "$SCRIPT_PATH" --no-pager --claude-arg --add-dir --claude-arg "../my src" "first"
  [ "$(jq -c '.turns[0].claude_args' "$SESSION_DIR/first.json")" = '["--add-dir","../my src"]' ]
  : > "$CLAUDE_STUB_LOG"
  run --separate-stderr "$SCRIPT_PATH" --no-pager -r "second"
  [[ "$stderr" == *'from the session, passing on to claude: --add-dir ../my\ src'* ]]
  grep -qF -- "--add-dir ../my src |" "$CLAUDE_STUB_LOG"
  [ "$(jq -c '.turns[1].claude_args' "$SESSION_DIR/first.json")" = '["--add-dir","../my src"]' ]
  : > "$CLAUDE_STUB_LOG"
  run --separate-stderr "$SCRIPT_PATH" --no-pager -r --claude-arg --tools --claude-arg Read "third"
  [[ "$stderr" != *"from the session"* ]]
  grep -qF -- "--tools Read |" "$CLAUDE_STUB_LOG"
  ! grep -qF -- "--add-dir" "$CLAUDE_STUB_LOG"
}

@test "a session with nothing passed on stays quiet, and old files work" {
  run "$SCRIPT_PATH" --no-pager "first"
  [ "$(jq -c '.turns[0].claude_args' "$SESSION_DIR/first.json")" = "null" ]
  run --separate-stderr "$SCRIPT_PATH" --no-pager -r "second"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"passing on"* ]]
}

@test "/status shows what is passed on" {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager --claude-arg --tools --claude-arg Read < <(printf '/status\n')
  [[ "$output" == *"passed to claude: --tools Read"* ]]
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf '/status\n')
  [[ "$output" != *"passed to claude"* ]]
}

@test "--split passes on --claude-arg, not what is in the environment" {
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0" CLAUDE_STUB_TMUX_LOG="$TEST_TEMP_DIR/tmux-calls"
  export CLAUDE_ASK_ARGS="--from-env x"
  run "$SCRIPT_PATH" --split --claude-arg --tools --claude-arg Read "q"
  grep -q -- "--claude-arg --tools --claude-arg Read" "$CLAUDE_STUB_TMUX_LOG"
  ! grep -q -- "--from-env" "$CLAUDE_STUB_TMUX_LOG"
}

@test "with no clipboard command the terminal is asked (OSC 52)" {
  export CLAUDE_ASK_CLIPBOARD=""
  unset DISPLAY WAYLAND_DISPLAY
  session known "q" "copy me" 1
  run python3 "$PTY" 'expect:yanked' 'sleep:0.2' -- "$SCRIPT_PATH" -y --session known
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e]52;c;'"$(printf 'copy me' | base64)"$'\a'* ]]
  [[ "$output" == *"the terminal's clipboard"* ]]
}

@test "OSC 52 is not sent to a dumb terminal, or when too long, or with no terminal" {
  export CLAUDE_ASK_CLIPBOARD=""
  unset DISPLAY WAYLAND_DISPLAY
  session known "q" "copy me" 1
  session big "q" "$(head -c 90000 /dev/zero | tr '\0' 'x')" 1
  TERM=dumb run python3 "$PTY" 'sleep:0.5' -- "$SCRIPT_PATH" -y --session known
  [[ "$output" != *$'\e]52'* ]]
  [[ "$output" == *"nowhere to yank"* ]]
  run python3 "$PTY" 'sleep:0.5' -- "$SCRIPT_PATH" -y --session big
  [[ "$output" != *$'\e]52'* ]]
  [[ "$output" == *"too long"* ]]
  run setsid "$SCRIPT_PATH" -y --session known
  [ "$status" -eq 1 ]
  [[ "$output" == *"nowhere to yank"* ]]
}

@test "OSC 52 is only the fallback" {
  session known "q" "copy me" 1
  run python3 "$PTY" 'expect:yanked' 'sleep:0.2' -- "$SCRIPT_PATH" -y --session known
  [[ "$output" != *$'\e]52'* ]]
  [ "$(cat "$TEST_TEMP_DIR/clipboard")" = "copy me" ]
}

@test "clipboard_cmd falls back to clip.exe on WSL" {
  mkdir -p "$TEST_TEMP_DIR/wsl"
  printf '#!/bin/sh\n' > "$TEST_TEMP_DIR/wsl/clip.exe"
  chmod +x "$TEST_TEMP_DIR/wsl/clip.exe"
  source_claude_ask
  unset CLAUDE_ASK_CLIPBOARD DISPLAY WAYLAND_DISPLAY
  local saved="$PATH"
  PATH="$TEST_TEMP_DIR/wsl"
  clipboard_cmd
  PATH="$saved"
  [ "$CLIP_CMD" = "clip.exe" ]
}

@test "inside tmux the buffer also goes to the outer terminal" {
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0" CLAUDE_STUB_TMUX_LOG="$TEST_TEMP_DIR/tmux-calls"
  session known "q" "copy me" 1
  run "$SCRIPT_PATH" -y --session known
  grep -q '^load-buffer -w -' "$CLAUDE_STUB_TMUX_LOG"
}

# The bar in the given environment
bar_with() {
  run env "$@" "$SCRIPT_PATH" --no-pager "q$RANDOM"
}

@test "colors: truecolor from COLORTERM, 256 and 16 from TERM, none on dumb" {
  bar_with COLORTERM=truecolor TERM=xterm-256color
  [[ "$output" == *$'\e[38;2;'* ]]
  bar_with COLORTERM=24bit TERM=xterm
  [[ "$output" == *$'\e[38;2;'* ]]
  bar_with COLORTERM= TERM=tmux-256color
  [[ "$output" == *$'\e[38;5;'* ]]
  [[ "$output" != *$'\e[38;2;'* ]]
  bar_with COLORTERM= TERM=xterm
  [[ "$output" != *$'\e[38;'* ]]
  [[ "$output" =~ $'\e['(3|9)[0-7]m ]]
  bar_with COLORTERM= TERM=dumb
  [[ "$output" != *$'\e[38'* ]]
  [[ ! "$output" =~ $'\e['(3|9)[0-7]m ]]
}

@test "colors: CLAUDE_ASK_COLORS and NO_COLOR win, and a bad value is an error" {
  bar_with COLORTERM=truecolor CLAUDE_ASK_COLORS=256
  [[ "$output" == *$'\e[38;5;'* ]]
  bar_with COLORTERM= TERM=dumb CLAUDE_ASK_COLORS=truecolor
  [[ "$output" == *$'\e[38;2;'* ]]
  bar_with CLAUDE_ASK_COLORS=none
  [[ "$output" != *$'\e[38;'* ]]
  bar_with CLAUDE_ASK_COLORS=truecolor NO_COLOR=1
  [[ "$output" != *$'\e[38;'* ]]
  bar_with CLAUDE_ASK_COLORS=many
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE_ASK_COLORS must be one of"* ]]
}

@test "recolor maps palette colors to the nearest 256 and 16 colors" {
  source_claude_ask
  COLOR_DEPTH=256
  recolor $'\e[38;2;255;0;0m'
  [ "$OUT_COLOR" = $'\e[38;5;196m' ]
  recolor $'\e[48;2;0;0;255m'
  [ "$OUT_COLOR" = $'\e[48;5;21m' ]
  # Greys use the ramp
  recolor $'\e[48;2;49;50;48m'
  [ "$OUT_COLOR" = $'\e[48;5;236m' ]
  COLOR_DEPTH=16
  recolor $'\e[38;2;255;0;0m'
  [ "$OUT_COLOR" = $'\e[91m' ]
  recolor $'\e[48;2;0;128;0m'
  [ "$OUT_COLOR" = $'\e[42m' ]
  # A dark foreground stays visible
  recolor $'\e[38;2;40;40;40m'
  [ "$OUT_COLOR" = $'\e[90m' ]
}

@test "themes keep their layout at every depth" {
  for depth in truecolor 256 16 none; do
    run env CLAUDE_ASK_COLORS="$depth" "$SCRIPT_PATH" --no-pager --theme powerline "q$depth"
    [ "$status" -eq 0 ]
    local clean
    clean=$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$clean" == *"sonnet 4.5"* ]]
  done
}
