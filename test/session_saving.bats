#!/usr/bin/env bats
# Test session saving logic

load test_helper

setup() {
  source_claude_ask
  export TEST_TEMP_DIR="$(mktemp -d)"
  export SESSION_DIR="$TEST_TEMP_DIR/sessions"
  mkdir -p "$SESSION_DIR"
}

@test "saves parsed session to correct file" {
  local raw_tmp="$TEST_TEMP_DIR/raw.jsonl"
  cp "${FIXTURES_DIR}/full_session.jsonl" "$raw_tmp"

  local session_file="${SESSION_DIR}/full-session-001.json"

  jq -s '
    {
      session_id: (map(select(.type == "system")) | first | .session_id // null),
      model: (map(select(.type == "system")) | first | .model // null),
      question: null,
      answer: (map(select(.type == "result")) | last | .result // null),
      thinking: (map(select(.type == "assistant" and .message.content[0].type == "thinking")) | map(.message.content[0].thinking) | if length > 0 then join("\n") else null end),
      cost_usd: (map(select(.type == "result")) | last | .total_cost_usd // null),
      duration_ms: (map(select(.type == "result")) | last | .duration_ms // null),
      duration_api_ms: (map(select(.type == "result")) | last | .duration_api_ms // null),
      usage: {
        input_tokens: (map(select(.type == "result")) | last | .usage.input_tokens // null),
        output_tokens: (map(select(.type == "result")) | last | .usage.output_tokens // null),
        cache_creation_input_tokens: (map(select(.type == "result")) | last | (.usage.cache_creation_input_tokens // null)),
        cache_read_input_tokens: (map(select(.type == "result")) | last | .usage.cache_read_input_tokens // null)
      },
      timestamp: now | todate
    }
  ' "$raw_tmp" | jq --arg q "What is the capital of France?" '.question = $q' > "$session_file"

  [ -f "$session_file" ]

  # Validate structure
  session_id=$(jq -r '.session_id' "$session_file")
  [ "$session_id" = "full-session-001" ]

  model=$(jq -r '.model' "$session_file")
  [[ "$model" == *"sonnet"* ]]

  question=$(jq -r '.question' "$session_file")
  [ "$question" = "What is the capital of France?" ]

  answer=$(jq -r '.answer' "$session_file")
  [[ "$answer" == *"Paris"* ]]

  cost=$(jq -r '.cost_usd' "$session_file")
  [ "$cost" = "0.012345" ]

  dur=$(jq -r '.duration_ms' "$session_file")
  [ "$dur" = "3200" ]
}

@test "saved session includes thinking text" {
  local raw_tmp="$TEST_TEMP_DIR/raw.jsonl"
  cp "${FIXTURES_DIR}/full_session.jsonl" "$raw_tmp"
  local session_file="${SESSION_DIR}/test.json"

  jq -s '
    {
      thinking: (map(select(.type == "assistant" and .message.content[0].type == "thinking")) | map(.message.content[0].thinking) | if length > 0 then join("\n") else null end)
    }
  ' "$raw_tmp" > "$session_file"

  thinking=$(jq -r '.thinking' "$session_file")
  [[ "$thinking" == *"think about"* ]]
}

@test "saved session includes usage tokens" {
  local raw_tmp="$TEST_TEMP_DIR/raw.jsonl"
  cp "${FIXTURES_DIR}/full_session.jsonl" "$raw_tmp"
  local session_file="${SESSION_DIR}/test.json"

  jq -s '
    {
      usage: {
        input_tokens: (map(select(.type == "result")) | last | .usage.input_tokens // null),
        output_tokens: (map(select(.type == "result")) | last | .usage.output_tokens // null),
        cache_creation_input_tokens: (map(select(.type == "result")) | last | (.usage.cache_creation_input_tokens // null)),
        cache_read_input_tokens: (map(select(.type == "result")) | last | .usage.cache_read_input_tokens // null)
      }
    }
  ' "$raw_tmp" > "$session_file"

  in_tokens=$(jq -r '.usage.input_tokens' "$session_file")
  [ "$in_tokens" = "500" ]

  out_tokens=$(jq -r '.usage.output_tokens' "$session_file")
  [ "$out_tokens" = "15" ]

  cache_create=$(jq -r '.usage.cache_creation_input_tokens' "$session_file")
  [ "$cache_create" = "8000" ]

  cache_read=$(jq -r '.usage.cache_read_input_tokens' "$session_file")
  [ "$cache_read" = "4000" ]
}

@test "raw save mode copies file directly" {
  local raw_tmp="$TEST_TEMP_DIR/raw.jsonl"
  cp "${FIXTURES_DIR}/full_session.jsonl" "$raw_tmp"
  local session_file="${SESSION_DIR}/raw-test.jsonl"

  cp "$raw_tmp" "$session_file"

  [ -f "$session_file" ]
  # Should have multiple lines (one per JSON object)
  local line_count
  line_count=$(wc -l < "$session_file")
  [ "$line_count" -ge 3 ]
}
