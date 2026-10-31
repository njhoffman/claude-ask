#!/usr/bin/env bats
# Test JSON stream parsing

load test_helper

# ---------------------------------------------------------------------------
# Model extraction
# ---------------------------------------------------------------------------
@test "parses opus model from init message" {
  parsed=$(parse_fixture "init.jsonl")
  model=$(get_parsed "model" "$parsed")
  [ "$model" = "opus" ]
}

@test "parses sonnet model from full session" {
  parsed=$(parse_fixture "full_session.jsonl")
  model=$(get_parsed "model" "$parsed")
  [ "$model" = "sonnet" ]
}

@test "parses haiku model" {
  parsed=$(parse_fixture "haiku_session.jsonl")
  model=$(get_parsed "model" "$parsed")
  [ "$model" = "haiku" ]
}

@test "strips context window suffix from model name" {
  parsed=$(parse_fixture "init.jsonl")
  model=$(get_parsed "model" "$parsed")
  # Should not contain [1m] or any bracket suffix
  [[ "$model" != *"["* ]]
}

# ---------------------------------------------------------------------------
# Session ID
# ---------------------------------------------------------------------------
@test "extracts session_id from init message" {
  parsed=$(parse_fixture "init.jsonl")
  sid=$(get_parsed "session_id" "$parsed")
  [ "$sid" = "test-session-001" ]
}

@test "extracts session_id from full session" {
  parsed=$(parse_fixture "full_session.jsonl")
  sid=$(get_parsed "session_id" "$parsed")
  [ "$sid" = "full-session-001" ]
}

# ---------------------------------------------------------------------------
# Answer text extraction
# ---------------------------------------------------------------------------
@test "extracts answer text from text chunk" {
  parsed=$(parse_fixture "text_chunk.jsonl")
  text=$(get_parsed "answer_text" "$parsed")
  [ "$text" = "Hello, world!" ]
}

@test "extracts answer text from full session" {
  parsed=$(parse_fixture "full_session.jsonl")
  text=$(get_parsed "answer_text" "$parsed")
  [[ "$text" == *"Paris"* ]]
}

@test "ignores thinking content in answer text" {
  parsed=$(parse_fixture "full_session.jsonl")
  text=$(get_parsed "answer_text" "$parsed")
  [[ "$text" != *"think about"* ]]
}

# ---------------------------------------------------------------------------
# Token counts
# ---------------------------------------------------------------------------
@test "extracts input tokens" {
  parsed=$(parse_fixture "text_chunk.jsonl")
  tokens=$(get_parsed "input_tokens" "$parsed")
  [ "$tokens" = "100" ]
}

@test "extracts output tokens" {
  parsed=$(parse_fixture "text_chunk.jsonl")
  tokens=$(get_parsed "output_tokens" "$parsed")
  [ "$tokens" = "25" ]
}

@test "result message updates final token counts" {
  parsed=$(parse_fixture "full_session.jsonl")
  tokens=$(get_parsed "input_tokens" "$parsed")
  [ "$tokens" = "500" ]
  out_tokens=$(get_parsed "output_tokens" "$parsed")
  [ "$out_tokens" = "15" ]
}

# ---------------------------------------------------------------------------
# Cost and duration
# ---------------------------------------------------------------------------
@test "extracts cost from result" {
  parsed=$(parse_fixture "full_session.jsonl")
  cost=$(get_parsed "cost" "$parsed")
  [ "$cost" = "0.012345" ]
}

@test "extracts duration from result" {
  parsed=$(parse_fixture "full_session.jsonl")
  dur=$(get_parsed "duration_ms" "$parsed")
  [ "$dur" = "3200" ]
}

# ---------------------------------------------------------------------------
# Status transitions
# ---------------------------------------------------------------------------
@test "status is done after result message" {
  parsed=$(parse_fixture "full_session.jsonl")
  s=$(get_parsed "status" "$parsed")
  [ "$s" = "done" ]
}

@test "status is running when no result message" {
  parsed=$(parse_fixture "text_chunk.jsonl")
  s=$(get_parsed "status" "$parsed")
  [ "$s" = "running" ]
}

# ---------------------------------------------------------------------------
# Thinking, multiple content blocks, skipped lines
# ---------------------------------------------------------------------------
@test "thinking event sets is_thinking without adding answer text" {
  parsed=$(parse_fixture "thinking.jsonl")
  [ "$(get_parsed is_thinking "$parsed")" = "1" ]
  [ -z "$(get_parsed answer_text "$parsed")" ]
}

@test "text after thinking clears is_thinking" {
  parsed=$(parse_fixture "full_session.jsonl")
  [ "$(get_parsed is_thinking "$parsed")" = "0" ]
}

@test "joins every text block of a message, not only the first" {
  source_claude_ask
  feed_stream "multi_block.jsonl"
  [ "$answer_text" = $'First part. Second\tpart\nwith a newline.' ]
  [ "$text_chunks" -eq 1 ]
  [ "$answer_lines" -eq 1 ]
  [ "$answer_chars" -eq "${#answer_text}" ]
}

@test "skips rate_limit_event and non-JSON lines" {
  source_claude_ask
  reset_stream_state
  run process_stream_line '{"type":"rate_limit_event"}'
  [ "$status" -eq 1 ]
  run process_stream_line 'not json at all'
  [ "$status" -eq 1 ]
  run process_stream_line ''
  [ "$status" -eq 1 ]
  run process_stream_line '{"no_type":true}'
  [ "$status" -eq 1 ]
}

@test "accepts events of unknown type without changing state" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"user","message":{"content":[{"type":"tool_result"}]}}'
  [ -z "$answer_text" ]
  [ "$status" = "running" ]
}

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------
@test "error result sets status error and stream_error" {
  parsed=$(parse_fixture "result_error.jsonl")
  [ "$(get_parsed status "$parsed")" = "error" ]
  [ "$(get_parsed stream_error "$parsed")" = "Invalid API key" ]
}

@test "successful result leaves stream_error empty" {
  parsed=$(parse_fixture "full_session.jsonl")
  [ -z "$(get_parsed stream_error "$parsed")" ]
}

# ---------------------------------------------------------------------------
# Model names
# ---------------------------------------------------------------------------
@test "short_model_name keeps unknown model ids without the bracket suffix" {
  source_claude_ask
  [ "$(short_model_name "claude-fable-5-1[1m]")" = "claude-fable-5-1" ]
  [ "$(short_model_name "claude-opus-4-6")" = "opus" ]
}
