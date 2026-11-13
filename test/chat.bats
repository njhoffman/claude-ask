#!/usr/bin/env bats
# Test the chat (-i, the no-question default) and --resume

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  # bats has no terminal on stdin; this lets the chat read piped questions
  export CLAUDE_ASK_FORCE_INTERACTIVE=1
}

# chat LINES...: run the script as a chat fed these lines on stdin
chat() {
  run "$SCRIPT_PATH" --no-pager "${CHAT_ARGS[@]}" < <(printf '%s\n' "$@")
}

# The session id the stub's full_session.jsonl reports
SID="full-session-001"

# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
@test "chat: each question is a turn in one conversation and one file" {
  CHAT_ARGS=()
  chat "first question" "second question"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  # The first call starts a conversation; the second continues it
  ! sed -n 1p "$CLAUDE_STUB_LOG" | grep -q -- "--resume"
  sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--resume $SID | second question"

  local file="$SESSION_DIR/first-question.json"
  [ "$(ls "$SESSION_DIR" | wc -l)" -eq 1 ]
  [ "$(jq -r '.turn_count' "$file")" = "2" ]
  [ "$(jq -r '[.turns[].question] | join(",")' "$file")" = "first question,second question" ]
  [ "$(jq -r '.question' "$file")" = "first question" ]
  # The stub reports the same running total each time, so nothing was added
  [ "$(jq -r '.cost_usd' "$file")" = "0.012345" ]
}

@test "chat: the info line shows the turn and the conversation total" {
  CHAT_ARGS=()
  chat "one" "two"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *'turn 2 | $0.0123 total'* ]]
}

@test "chat: exit and quit end it; blank lines are skipped" {
  CHAT_ARGS=()
  chat "" "   " "only question" "quit" "never asked"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
  CHAT_ARGS=()
  chat "exit" "never asked"
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

@test "chat: a last line without a newline is still asked" {
  run "$SCRIPT_PATH" --no-pager < <(printf 'no newline')
  [ "$status" -eq 0 ]
  grep -q '| no newline$' "$CLAUDE_STUB_LOG"
}

@test "chat: \\e composes the question in \$EDITOR" {
  local editor="$TEST_TEMP_DIR/editor"
  printf '#!/bin/bash\nprintf "line one\\nline two" > "$1"\n' > "$editor"
  chmod +x "$editor"
  export EDITOR="$editor"
  CHAT_ARGS=()
  chat '\e'
  [ "$status" -eq 0 ]
  grep -qF '| line one\nline two' "$CLAUDE_STUB_LOG"
}

@test "chat: an empty editor buffer asks nothing" {
  export EDITOR=true
  CHAT_ARGS=()
  chat '\e'
  [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "chat: a failed turn reports the error and the chat goes on" {
  export CLAUDE_STUB_FAIL_CALL=1
  CHAT_ARGS=()
  chat "fails" "works"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub failure"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  [ -f "$SESSION_DIR/works.json" ]
}

@test "chat: exits 1 when the last turn failed" {
  export CLAUDE_STUB_FAIL_CALL=2
  CHAT_ARGS=()
  chat "works" "fails"
  [ "$status" -eq 1 ]
}

@test "chat: questions are kept in the history file" {
  CHAT_ARGS=()
  chat "remember me"
  grep -qx "remember me" "$XDG_STATE_HOME/claude-ask/history"
}

@test "-i: answers the question, then keeps chatting" {
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager -i "first" < <(printf 'second\n')
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  [ "$(jq -r '.turn_count' "$SESSION_DIR/first.json")" = "2" ]
}

@test "without -i a question is answered once" {
  run "$SCRIPT_PATH" --no-pager "only" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

@test "chat: Ctrl-C stops the answer, saves nothing, and the chat goes on" {
  # Job control gives the background run its own process group, so it does
  # not start with SIGINT ignored the way plain background jobs do
  set -m
  export CLAUDE_STUB_DELAY=0.5
  "$SCRIPT_PATH" --no-pager > "$TEST_TEMP_DIR/out" 2>&1 \
    < <(printf 'slow one\n'; sleep 3; printf 'after\n') &
  local pid=$!
  sleep 1.2
  kill -INT "$pid"
  local rc=0
  wait "$pid" || rc=$?
  set +m
  [ "$rc" -eq 0 ]
  grep -q "(interrupted)" "$TEST_TEMP_DIR/out"
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  [ ! -e "$SESSION_DIR/slow-one.json" ]
  [ -f "$SESSION_DIR/after.json" ]
}

@test "chat: /retry with nothing to retry, or after an answer, says why and asks nothing" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/retry_answer.jsonl"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run --separate-stderr "$SCRIPT_PATH" --no-pager \
    < <(printf '/retry\nfirst\n/retry\n/retry now\n')
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no question has been asked in this chat to retry"* ]]
  [[ "$stderr" == *"the last question was answered"* ]]
  [[ "$stderr" == *"/retry takes nothing"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

@test "chat: /retry after a failed later turn resumes at the last answer" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/retry_answer.jsonl"
  export CLAUDE_STUB_FAIL_CALL=2
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run --separate-stderr "$SCRIPT_PATH" --no-pager \
    < <(printf 'first\nsecond\n/retry\n')
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 3 ]
  local third
  third=$(sed -n 3p "$CLAUDE_STUB_LOG")
  [[ "$third" == *"--resume retry-001 --resume-session-at uuid-answer-1 "* ]]
  [[ "$third" == *"| second" ]]
}

@test "chat: /retry after a failed first question starts a new session" {
  export CLAUDE_STUB_FIXTURE="$FIXTURES_DIR/retry_answer.jsonl"
  export CLAUDE_STUB_FAIL_CALL=1
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run --separate-stderr "$SCRIPT_PATH" --no-pager \
    < <(printf 'first\n/retry\n')
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 2 ]
  [[ "$(sed -n 2p "$CLAUDE_STUB_LOG")" != *"--resume"* ]]
  [[ "$(sed -n 2p "$CLAUDE_STUB_LOG")" == *"| first" ]]
  [ "$(jq -r '.turns[0].assistant_uuid' "$SESSION_DIR/first.json")" = "uuid-answer-1" ]
}

@test "chat: /retry in a session saved without message ids refuses" {
  old_session legacy 5
  export CLAUDE_STUB_FAIL_CALL=1
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run --separate-stderr "$SCRIPT_PATH" --no-pager -r \
    < <(printf 'again\n/retry\n')
  [[ "$stderr" == *"saved before /retry could leave a turn out"* ]]
  [ "$(wc -l < "$CLAUDE_STUB_LOG")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --resume
# ---------------------------------------------------------------------------
# old_session NAME AGE_MINUTES [SESSION_ID]: a single-turn file as saved before
# conversations had turns
old_session() {
  local sid="${3-old-$1}"
  jq -n --arg n "$1" --arg sid "$sid" '{session_id: (if $sid == "" then null else $sid end),
    model: "claude-opus-4-6", name: $n, question: ("question " + $n),
    answer: ("answer " + $n), cost_usd: 0.01, duration_ms: 1000,
    usage: {input_tokens: 10, output_tokens: 5}, timestamp: "2026-10-01T00:00:00Z"}' \
    > "$SESSION_DIR/$1.json"
  touch -d "-$2 minutes" "$SESSION_DIR/$1.json"
}

@test "-r QUESTION: asks in the newest session and adds the turn to it" {
  unset CLAUDE_ASK_FORCE_INTERACTIVE
  old_session older 60
  old_session newest 5
  run "$SCRIPT_PATH" --no-pager -r "follow up" < /dev/null
  [ "$status" -eq 0 ]
  grep -q -- "--resume old-newest | follow up" "$CLAUDE_STUB_LOG"
  local file="$SESSION_DIR/newest.json"
  [ "$(jq -r '.turn_count' "$file")" = "2" ]
  [ "$(jq -r '[.turns[].question] | join(",")' "$file")" = "question newest,follow up" ]
  # The running total claude reported, not added to the one before
  [ "$(jq -r '.cost_usd' "$file")" = "0.012345" ]
  [ "$(ls "$SESSION_DIR" | wc -l)" -eq 2 ]
}

@test "-r: shows a header and the last turn before asking" {
  old_session newest 5
  CHAT_ARGS=(-r)
  chat "next"
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *'resuming newest (1 turn, $0.0100)'* ]]
  [[ "$output_clean" == *"> question newest"* ]]
  [[ "$output_clean" == *"answer newest"* ]]
}

@test "-r without a question opens the chat in that session" {
  old_session newest 5
  CHAT_ARGS=(-r)
  chat "one" "two"
  [ "$status" -eq 0 ]
  # The first call resumes the saved id; later ones follow the id claude
  # reports (the stub's fixture always reports $SID)
  sed -n 1p "$CLAUDE_STUB_LOG" | grep -q -- "--resume old-newest | one"
  sed -n 2p "$CLAUDE_STUB_LOG" | grep -q -- "--resume $SID | two"
  [ "$(jq -r '.turn_count' "$SESSION_DIR/newest.json")" = "3" ]
}

@test "-r with no saved sessions is an error" {
  run "$SCRIPT_PATH" --no-pager -r "anything" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no saved session to resume"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "-r on a session without an id is an error" {
  old_session noid 5 ""
  run "$SCRIPT_PATH" --no-pager -r "anything" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"noid has no session id"* ]]
}

# ---------------------------------------------------------------------------
# Reading conversations
# ---------------------------------------------------------------------------
@test "--history shows the first question and the number of turns" {
  CHAT_ARGS=()
  chat "first question" "second question"
  run "$SCRIPT_PATH" --history
  [ "$status" -eq 0 ]
  [[ "$output" == *"first question"* ]]
  [[ "$output" == *" 2T"* ]]
}

@test "--session replays every turn" {
  CHAT_ARGS=()
  chat "first question" "second question"
  run "$SCRIPT_PATH" --no-pager --session 1
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"> first question"* ]]
  [[ "$output_clean" == *"> second question"* ]]
  [ "$(grep -c "Paris" <<< "$output_clean")" -eq 2 ]
}

@test "--session still replays a session saved before turns existed" {
  old_session legacy 5
  run "$SCRIPT_PATH" --no-pager --session legacy
  [ "$status" -eq 0 ]
  [[ "$output" == *"answer legacy"* ]]
}

@test "--save-raw appends every turn to the .jsonl" {
  CHAT_ARGS=(--save-raw)
  chat "one" "two"
  [ "$(grep -c '"type":"result"' "$SESSION_DIR/one.jsonl")" -eq 2 ]
}

# ---------------------------------------------------------------------------
# --resume=ID|N
# ---------------------------------------------------------------------------
@test "--resume=N continues the Nth newest session, not the newest" {
  unset CLAUDE_ASK_FORCE_INTERACTIVE
  old_session older 60
  old_session newest 5
  run "$SCRIPT_PATH" --no-pager --resume=2 "follow up" < /dev/null
  [ "$status" -eq 0 ]
  grep -q -- "--resume old-older | follow up" "$CLAUDE_STUB_LOG"
  [ "$(jq -r '.turn_count' "$SESSION_DIR/older.json")" = "2" ]
  [ "$(jq -r '.turn_count // 1' "$SESSION_DIR/newest.json")" = "1" ]
}

@test "--resume=NAME and --resume=PREFIX find the session" {
  unset CLAUDE_ASK_FORCE_INTERACTIVE
  old_session git-bare-repo 60
  old_session newest 5
  run "$SCRIPT_PATH" --no-pager --resume=git-bare-repo "q1" < /dev/null
  [ "$status" -eq 0 ]
  run "$SCRIPT_PATH" --no-pager --resume=git-ba "q2" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.turns[].question] | join(",")' "$SESSION_DIR/git-bare-repo.json")" = "question git-bare-repo,q1,q2" ]
}

@test "--resume= chats in the chosen session without a question" {
  old_session older 60
  old_session newest 5
  CHAT_ARGS=(--resume=older)
  chat "one"
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"resuming older (1 turn"* ]]
  sed -n 1p "$CLAUDE_STUB_LOG" | grep -q -- "--resume old-older | one"
}

@test "--resume= with an unknown or ambiguous session is an error" {
  unset CLAUDE_ASK_FORCE_INTERACTIVE
  old_session git-one 60
  old_session git-two 5
  run "$SCRIPT_PATH" --no-pager --resume=nothing "q" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session nothing (--history lists them)"* ]]
  run "$SCRIPT_PATH" --no-pager --resume=git "q" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ambiguous session name 'git'"* ]]
  [ ! -s "$CLAUDE_STUB_LOG" ]
}

@test "--resume= needs a session" {
  run "$SCRIPT_PATH" --resume= "q"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--resume= takes a session name or number"* ]]
}

@test "--resume= is passed on by --split" {
  export PATH="$STUB_DIR:$PATH" TMUX="/tmp/fake,1,0" CLAUDE_STUB_TMUX_LOG="$TEST_TEMP_DIR/tmux"
  unset CLAUDE_ASK_FORCE_INTERACTIVE
  run "$SCRIPT_PATH" --split --resume=3 "q"
  grep -q -- " '--resume=3' '-i'$" "$CLAUDE_STUB_TMUX_LOG"
  run "$SCRIPT_PATH" --split -r "q"
  grep -q -- " '-r' '-i'$" "$CLAUDE_STUB_TMUX_LOG"
}
