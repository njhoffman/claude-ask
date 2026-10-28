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

@test "extracts cache creation tokens" {
  parsed=$(parse_fixture "text_chunk.jsonl")
  tokens=$(get_parsed "cache_creation_tokens" "$parsed")
  [ "$tokens" = "5000" ]
}

@test "extracts cache read tokens" {
  parsed=$(parse_fixture "text_chunk.jsonl")
  tokens=$(get_parsed "cache_read_tokens" "$parsed")
  [ "$tokens" = "3000" ]
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
# Missing fields
# ---------------------------------------------------------------------------
@test "handles session with no cache tokens" {
  parsed=$(parse_fixture "haiku_session.jsonl")
  cache=$(get_parsed "cache_creation_tokens" "$parsed")
  [ -z "$cache" ]
}
