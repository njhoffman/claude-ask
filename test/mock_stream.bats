#!/usr/bin/env bats
# Test mock stream-json generator and stream parsing

load test_helper

setup() {
  common_setup
  source_claude_ask
}


# ---------------------------------------------------------------------------
# generate_mock_stream: structure
# ---------------------------------------------------------------------------
@test "mock stream: small has system, thinking, text, and result events" {
  local types
  types=$(generate_mock_stream small 0 | jq -r '.type')
  [[ "$types" == *"system"* ]]
  [[ "$types" == *"assistant"* ]]
  [[ "$types" == *"result"* ]]
}

@test "mock stream: system event has model and session_id" {
  local tmpfile="$TEST_TEMP_DIR/stream.jsonl"
  generate_mock_stream small 0 > "$tmpfile"
  local system_line
  system_line=$(head -1 "$tmpfile")
  local model session_id
  model=$(printf '%s' "$system_line" | jq -r '.model')
  session_id=$(printf '%s' "$system_line" | jq -r '.session_id')
  [[ "$model" == *"opus"* ]]
  [[ "$session_id" == "demo-small" ]]
}

@test "mock stream: has thinking event" {
  local thinking_count
  thinking_count=$(generate_mock_stream small 0 | jq -r 'select(.message.content[0].type == "thinking")' | grep -c "thinking" || true)
  [[ "$thinking_count" -ge 1 ]]
}

@test "mock stream: text chunks contain actual content" {
  local text
  text=$(generate_mock_stream small 0 | jq -r 'select(.message.content[0].type == "text") | .message.content[0].text // empty' | tr -d '\n')
  [[ -n "$text" ]]
  [[ "$text" == *"Paris"* ]]
}

@test "mock stream: result has cost and duration" {
  local result_line
  result_line=$(generate_mock_stream small 0 | jq -r 'select(.type == "result")')
  local cost duration
  cost=$(printf '%s' "$result_line" | jq -r '.total_cost_usd')
  duration=$(printf '%s' "$result_line" | jq -r '.duration_ms')
  [[ "$cost" != "null" && -n "$cost" ]]
  [[ "$duration" != "null" && -n "$duration" ]]
}

# ---------------------------------------------------------------------------
# generate_mock_stream: sizes
# ---------------------------------------------------------------------------
@test "mock stream: small produces fewer chunks than medium" {
  local small_chunks medium_chunks
  small_chunks=$(generate_mock_stream small 0 | jq -r 'select(.message.content[0].type == "text")' | grep -c "text" || echo 0)
  medium_chunks=$(generate_mock_stream medium 0 | jq -r 'select(.message.content[0].type == "text")' | grep -c "text" || echo 0)
  [[ "$small_chunks" -lt "$medium_chunks" ]]
}

@test "mock stream: medium produces fewer chunks than large" {
  local medium_chunks large_chunks
  medium_chunks=$(generate_mock_stream medium 0 | jq -r 'select(.message.content[0].type == "text")' | grep -c "text" || echo 0)
  large_chunks=$(generate_mock_stream large 0 | jq -r 'select(.message.content[0].type == "text")' | grep -c "text" || echo 0)
  [[ "$medium_chunks" -lt "$large_chunks" ]]
}

@test "mock stream: small result has lower cost than large" {
  local small_cost large_cost
  small_cost=$(generate_mock_stream small 0 | jq -r 'select(.type == "result") | .total_cost_usd')
  large_cost=$(generate_mock_stream large 0 | jq -r 'select(.type == "result") | .total_cost_usd')
  # Compare as strings since bc handles decimals
  local cmp
  cmp=$(echo "$small_cost < $large_cost" | bc)
  [[ "$cmp" -eq 1 ]]
}

@test "mock stream: invalid size returns error" {
  run generate_mock_stream invalid 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be small, medium, or large"* ]]
}

# ---------------------------------------------------------------------------
# Parsing mock streams through process_stream_line
# ---------------------------------------------------------------------------
@test "mock stream: small parses to correct model" {
  local fixture="$TEST_TEMP_DIR/mock_small.jsonl"
  generate_mock_stream small 0 > "$fixture"
  feed_stream "$fixture"

  [ "$model" = "opus" ]
  [ "$session_id" = "demo-small" ]
  [ "$status" = "done" ]
  [[ "$answer_text" == *"Paris"* ]]
  [[ -n "$cost" ]]
  [[ -n "$duration_ms" ]]
}

@test "mock stream: medium answer contains markdown headings" {
  local fixture="$TEST_TEMP_DIR/mock_medium.jsonl"
  generate_mock_stream medium 0 > "$fixture"
  feed_stream "$fixture"

  [[ "$answer_text" == *"## "* ]]
  [[ "$answer_text" == *"### "* ]]
  [[ "$answer_text" == *'```'* ]]
}

@test "mock stream: large answer reassembles to the original text" {
  local fixture="$TEST_TEMP_DIR/mock_large.jsonl"
  generate_mock_stream large 0 > "$fixture"
  feed_stream "$fixture"

  [ "$answer_text" = "$MOCK_LARGE_TEXT" ]
}

# ---------------------------------------------------------------------------
# Stream metrics tracking
# ---------------------------------------------------------------------------
@test "mock stream: metrics track lines correctly for medium" {
  local fixture="$TEST_TEMP_DIR/mock_medium.jsonl"
  generate_mock_stream medium 0 > "$fixture"
  feed_stream "$fixture"

  local newlines="${MOCK_MEDIUM_TEXT//[!$'\n']/}"
  [ "$answer_lines" -eq "${#newlines}" ]
  [ "$answer_chars" -eq "${#answer_text}" ]
  [[ "$text_chunks" -gt 1 ]]
}

@test "mock stream: all events are valid JSON" {
  generate_mock_stream large 0 | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '%s' "$line" | jq -e . > /dev/null 2>&1
  done
}
