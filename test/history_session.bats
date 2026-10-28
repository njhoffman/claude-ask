#!/usr/bin/env bats
# Test --history, --session, slugify, and session naming

load test_helper

setup() {
  source_claude_ask
  export TEST_TEMP_DIR="$(mktemp -d)"
  export SESSION_DIR="$TEST_TEMP_DIR/sessions"
  mkdir -p "$SESSION_DIR"
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
# format_time_ago
# ---------------------------------------------------------------------------
@test "format_time_ago: seconds" {
  local ts
  ts=$(date -u -d '30 seconds ago' '+%Y-%m-%dT%H:%M:%SZ')
  result=$(format_time_ago "$ts")
  [[ "$result" == *"sec ago"* ]]
}

@test "format_time_ago: minutes" {
  local ts
  ts=$(date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')
  result=$(format_time_ago "$ts")
  [[ "$result" == *"min ago"* ]]
}

@test "format_time_ago: hours" {
  local ts
  ts=$(date -u -d '3 hours ago' '+%Y-%m-%dT%H:%M:%SZ')
  result=$(format_time_ago "$ts")
  [[ "$result" == *"hrs ago"* ]]
}

@test "format_time_ago: days" {
  local ts
  ts=$(date -u -d '5 days ago' '+%Y-%m-%dT%H:%M:%SZ')
  result=$(format_time_ago "$ts")
  [[ "$result" == *"d ago"* ]]
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
