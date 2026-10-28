#!/usr/bin/env bats
# Test mock stream-json generator and stream parsing

load test_helper

setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
  source_claude_ask
}

teardown() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
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
# Parsing mock stream through the fixture parser
# ---------------------------------------------------------------------------
@test "mock stream: small parses to correct model" {
  # Write mock stream to a temp fixture
  local fixture="$TEST_TEMP_DIR/mock_small.jsonl"
  generate_mock_stream small 0 > "$fixture"

  source_claude_ask
  model=""
  session_id=""
  input_tokens=""
  output_tokens=""
  cost=""
  duration_ms=""
  answer_text=""
  status="running"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    [[ -z "$line_type" ]] && continue
    case "$line_type" in
      system)
        model=$(printf '%s' "$line" | jq -r '.model // empty' 2>/dev/null) || true
        model="${model%%\[*}"
        case "${model,,}" in
          *opus*) model="opus" ;;
        esac
        ;;
      assistant)
        content_type=$(printf '%s' "$line" | jq -r '.message.content[0].type // empty' 2>/dev/null) || true
        if [[ "$content_type" == "text" ]]; then
          text_chunk=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null) || true
          [[ -n "$text_chunk" ]] && answer_text+="$text_chunk"
        fi
        new_in=$(printf '%s' "$line" | jq -r '.message.usage.input_tokens // empty' 2>/dev/null) || true
        new_out=$(printf '%s' "$line" | jq -r '.message.usage.output_tokens // empty' 2>/dev/null) || true
        [[ -n "$new_in" ]] && input_tokens="$new_in"
        [[ -n "$new_out" ]] && output_tokens="$new_out"
        ;;
      result)
        status="done"
        cost=$(printf '%s' "$line" | jq -r '.total_cost_usd // empty' 2>/dev/null) || true
        duration_ms=$(printf '%s' "$line" | jq -r '.duration_ms // empty' 2>/dev/null) || true
        ;;
    esac
  done < "$fixture"

  [ "$model" = "opus" ]
  [ "$status" = "done" ]
  [[ "$answer_text" == *"Paris"* ]]
  [[ -n "$cost" ]]
  [[ -n "$duration_ms" ]]
}

@test "mock stream: medium answer contains markdown headings" {
  local fixture="$TEST_TEMP_DIR/mock_medium.jsonl"
  generate_mock_stream medium 0 > "$fixture"

  source_claude_ask
  answer_text=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    case "$line_type" in
      assistant)
        content_type=$(printf '%s' "$line" | jq -r '.message.content[0].type // empty' 2>/dev/null) || true
        if [[ "$content_type" == "text" ]]; then
          text_chunk=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null) || true
          [[ -n "$text_chunk" ]] && answer_text+="$text_chunk"
        fi
        ;;
    esac
  done < "$fixture"

  [[ "$answer_text" == *"## "* ]]
  [[ "$answer_text" == *"### "* ]]
  [[ "$answer_text" == *'```'* ]]
}

@test "mock stream: large answer contains table and code blocks" {
  local fixture="$TEST_TEMP_DIR/mock_large.jsonl"
  generate_mock_stream large 0 > "$fixture"

  source_claude_ask
  answer_text=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    case "$line_type" in
      assistant)
        content_type=$(printf '%s' "$line" | jq -r '.message.content[0].type // empty' 2>/dev/null) || true
        if [[ "$content_type" == "text" ]]; then
          text_chunk=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null) || true
          [[ -n "$text_chunk" ]] && answer_text+="$text_chunk"
        fi
        ;;
    esac
  done < "$fixture"

  [[ "$answer_text" == *"| Season"* ]]
  [[ "$answer_text" == *'```bash'* ]]
  [[ "$answer_text" == *"metro_lines"* ]]
}

# ---------------------------------------------------------------------------
# Stream metrics tracking
# ---------------------------------------------------------------------------
@test "mock stream: metrics track lines correctly for medium" {
  local fixture="$TEST_TEMP_DIR/mock_medium.jsonl"
  generate_mock_stream medium 0 > "$fixture"

  source_claude_ask
  answer_text=""
  answer_lines=0
  answer_chars=0
  text_chunks=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    case "$line_type" in
      assistant)
        content_type=$(printf '%s' "$line" | jq -r '.message.content[0].type // empty' 2>/dev/null) || true
        if [[ "$content_type" == "text" ]]; then
          text_chunk=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null) || true
          if [[ -n "$text_chunk" ]]; then
            answer_text+="$text_chunk"
            text_chunks=$(( text_chunks + 1 ))
            answer_chars=$(( answer_chars + ${#text_chunk} ))
            local nl_stripped="${text_chunk//[!$'\n']/}"
            answer_lines=$(( answer_lines + ${#nl_stripped} ))
          fi
        fi
        ;;
    esac
  done < "$fixture"

  # Medium text has multiple lines
  [[ "$answer_lines" -gt 5 ]]
  # Chars should match accumulated text length
  [[ "$answer_chars" -eq "${#answer_text}" ]]
  # Should have multiple chunks
  [[ "$text_chunks" -gt 1 ]]
}

@test "mock stream: all events are valid JSON" {
  generate_mock_stream large 0 | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '%s' "$line" | jq -e . > /dev/null 2>&1
  done
}
