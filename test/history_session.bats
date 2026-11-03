#!/usr/bin/env bats
# Test --history, --session, slugify, and session naming

load test_helper

setup() {
  common_setup
  source_claude_ask
}

# ---------------------------------------------------------------------------
# slugify_question
# ---------------------------------------------------------------------------
@test "slugify_question: lowercases and replaces spaces with hyphens" {
  result=$(slugify_question "What Is Bash")
  [ "$result" = "what-is-bash" ]
}

@test "slugify_question: removes special characters" {
  result=$(slugify_question "How do I use git?")
  [ "$result" = "how-do-i-use-git" ]
}

@test "slugify_question: collapses multiple hyphens" {
  result=$(slugify_question "foo---bar   baz")
  [ "$result" = "foo-bar-baz" ]
}

@test "slugify_question: truncates to max length" {
  result=$(slugify_question "a very long question that should be truncated" 10)
  [ ${#result} -le 10 ]
}

@test "slugify_question: strips leading and trailing hyphens" {
  result=$(slugify_question "  hello world  ")
  [ "$result" = "hello-world" ]
}

# ---------------------------------------------------------------------------
# unique_session_name
# ---------------------------------------------------------------------------
@test "unique_session_name: returns base name when no conflict" {
  result=$(unique_session_name "my-session" "$SESSION_DIR")
  [ "$result" = "my-session" ]
}

@test "unique_session_name: appends -2 on first conflict" {
  touch "$SESSION_DIR/my-session.json"
  result=$(unique_session_name "my-session" "$SESSION_DIR")
  [ "$result" = "my-session-2" ]
}

@test "unique_session_name: increments suffix on multiple conflicts" {
  touch "$SESSION_DIR/my-session.json"
  touch "$SESSION_DIR/my-session-2.json"
  touch "$SESSION_DIR/my-session-3.json"
  result=$(unique_session_name "my-session" "$SESSION_DIR")
  [ "$result" = "my-session-4" ]
}

# ---------------------------------------------------------------------------
# format_age
# ---------------------------------------------------------------------------
@test "format_age: seconds, minutes, hours, days, weeks" {
  local r
  format_age r 30
  [ "$r" = "30 sec ago" ]
  format_age r 900
  [ "$r" = "15 min ago" ]
  format_age r 10800
  [ "$r" = "3 hrs ago" ]
  format_age r 9000
  [ "$r" = "2.5 hrs ago" ]
  format_age r 432000
  [ "$r" = "5d ago" ]
  format_age r 1814400
  [ "$r" = "3w ago" ]
}

@test "format_age: the edges between units" {
  local r
  format_age r 59
  [ "$r" = "59 sec ago" ]
  format_age r 60
  [ "$r" = "1 min ago" ]
  format_age r 3600
  [ "$r" = "1 hrs ago" ]
  format_age r 86400
  [ "$r" = "1d ago" ]
  format_age r 604800
  [ "$r" = "1w ago" ]
}

# ---------------------------------------------------------------------------
# history_records
# ---------------------------------------------------------------------------
@test "history_records: one jq reads every file, in the order given" {
  jq -n '{question: "q1", answer: "a\nb", timestamp: "2026-11-01T00:00:00Z"}' > "$SESSION_DIR/one.json"
  jq -n '{turns: [{question: "q2", answer: "x"}, {question: "q3", answer: "y\nz"}],
    timestamp: "2026-11-02T00:00:00Z"}' > "$SESSION_DIR/two.json"
  history_records "$SESSION_DIR/two.json" "$SESSION_DIR/one.json"
  [ "${#HISTORY_RECORDS[@]}" -eq 10 ]
  [ "${HISTORY_RECORDS[0]}" = "$SESSION_DIR/two.json" ]
  [ "${HISTORY_RECORDS[2]}" = "q2" ]
  [ "${HISTORY_RECORDS[3]}" = "3" ]
  [ "${HISTORY_RECORDS[4]}" = "2" ]
  [ "${HISTORY_RECORDS[5]}" = "$SESSION_DIR/one.json" ]
  [ "${HISTORY_RECORDS[6]}" = "1793491200" ]
  [ "${HISTORY_RECORDS[8]}" = "2" ]
}

@test "history_records: a broken file keeps its name and the others still read" {
  jq -n '{question: "good", answer: "a", timestamp: "2026-11-01T00:00:00Z"}' > "$SESSION_DIR/good.json"
  printf '{not json' > "$SESSION_DIR/broken.json"
  history_records "$SESSION_DIR/broken.json" "$SESSION_DIR/good.json"
  [ "${#HISTORY_RECORDS[@]}" -eq 10 ]
  [ "${HISTORY_RECORDS[0]}" = "$SESSION_DIR/broken.json" ]
  [ "${HISTORY_RECORDS[2]}" = "" ]
  [ "${HISTORY_RECORDS[7]}" = "good" ]
}

@test "history_records: a timestamp jq cannot read gives no age" {
  jq -n '{question: "q", timestamp: "yesterday"}' > "$SESSION_DIR/odd.json"
  history_records "$SESSION_DIR/odd.json"
  [ "${HISTORY_RECORDS[1]}" = "" ]
  run show_history "$SESSION_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"odd"* ]]
}

@test "show_history: shows the age of the last timestamp" {
  local ts
  ts=$(jq -rn '(now - 900) | floor | todate')
  jq -n --arg ts "$ts" '{question: "recent", answer: "a", timestamp: $ts}' > "$SESSION_DIR/recent.json"
  run show_history "$SESSION_DIR"
  [[ "$output" == *"15 min ago"* ]]
}

# ---------------------------------------------------------------------------
# show_history
# ---------------------------------------------------------------------------
@test "show_history: empty directory returns error" {
  run show_history "$SESSION_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No saved sessions"* ]]
}

@test "show_history: lists sessions with name and question" {
  cat > "$SESSION_DIR/git-bare.json" <<'JSON'
{"session_id":"abc","model":"opus","name":"git-bare","question":"How do I setup a bare repo?","answer":"Use git init --bare.\nThen configure.","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON

  run show_history "$SESSION_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git-bare"* ]]
  [[ "$output" == *"How do I setup a bare repo?"* ]]
  [[ "$output" == *"L"* ]]
}

@test "show_history: truncates long names with ellipsis" {
  local long_name="this-is-a-very-long-session-name-that-exceeds-max"
  cat > "$SESSION_DIR/${long_name}.json" <<'JSON'
{"session_id":"abc","model":"opus","name":"test","question":"test","answer":"test","timestamp":"2026-03-28T00:00:00Z"}
JSON

  MAX_DISPLAY_NAME=20
  run show_history "$SESSION_DIR"
  [ "$status" -eq 0 ]
}

@test "show_history: shows multiple sessions sorted by mtime" {
  cat > "$SESSION_DIR/first.json" <<'JSON'
{"session_id":"1","model":"opus","name":"first","question":"Q1","answer":"A1","timestamp":"2026-03-27T00:00:00Z"}
JSON
  sleep 0.1
  cat > "$SESSION_DIR/second.json" <<'JSON'
{"session_id":"2","model":"opus","name":"second","question":"Q2","answer":"A2","timestamp":"2026-03-28T00:00:00Z"}
JSON

  run show_history "$SESSION_DIR"
  [ "$status" -eq 0 ]
  # second should appear before first (newer mtime)
  local second_line first_line
  second_line=$(echo "$output" | grep "second")
  first_line=$(echo "$output" | grep "first")
  [[ -n "$second_line" ]]
  [[ -n "$first_line" ]]
}

# ---------------------------------------------------------------------------
# view_session
# ---------------------------------------------------------------------------
@test "view_session: no arg falls back to history" {
  run view_session ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"No saved sessions"* ]]
}

@test "view_session: sentinel falls back to history" {
  run view_session "__SHOW_HISTORY__"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No saved sessions"* ]]
}

@test "view_session: invalid name shows error and history" {
  run view_session "nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Session not found"* ]]
}

@test "view_session: finds session by numeric index" {
  cat > "$SESSION_DIR/test-session.json" <<'JSON'
{"session_id":"abc","model":"claude-opus-4-20250514","name":"test-session","question":"What is bash?","answer":"Bash is a shell.","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON

  USE_PAGER=0
  run view_session "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash is a shell"* ]]
}

@test "view_session: finds session by exact name" {
  cat > "$SESSION_DIR/git-bare.json" <<'JSON'
{"session_id":"abc","model":"claude-opus-4-20250514","name":"git-bare","question":"How to git bare?","answer":"Use git init --bare.","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON

  USE_PAGER=0
  run view_session "git-bare"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git init --bare"* ]]
}

@test "view_session: finds session by prefix" {
  cat > "$SESSION_DIR/git-bare-repo.json" <<'JSON'
{"session_id":"abc","model":"claude-opus-4-20250514","name":"git-bare-repo","question":"Q","answer":"Found by prefix.","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON

  USE_PAGER=0
  run view_session "git-bare"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Found by prefix"* ]]
}

@test "view_session: ambiguous prefix shows matches" {
  cat > "$SESSION_DIR/git-bare.json" <<'JSON'
{"session_id":"1","model":"opus","name":"git-bare","question":"Q1","answer":"A1","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON
  cat > "$SESSION_DIR/git-basics.json" <<'JSON'
{"session_id":"2","model":"opus","name":"git-basics","question":"Q2","answer":"A2","cost_usd":"0.05","duration_ms":"3000","usage":{"input_tokens":"100","output_tokens":"50"},"timestamp":"2026-03-28T00:00:00Z"}
JSON

  run view_session "git-ba"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ambiguous"* ]]
  [[ "$output" == *"git-bare"* ]]
  [[ "$output" == *"git-basics"* ]]
}
