#!/usr/bin/env bats
# Test JSON stream parsing

load test_helper

# ---------------------------------------------------------------------------
# Model extraction
# ---------------------------------------------------------------------------
@test "parses opus model from init message" {
  parsed=$(parse_fixture "init.jsonl")
  model=$(get_parsed "model" "$parsed")
  [ "$model" = "opus 4.6" ]
}

@test "parses sonnet model from full session" {
  parsed=$(parse_fixture "full_session.jsonl")
  model=$(get_parsed "model" "$parsed")
  [ "$model" = "sonnet 4.5" ]
}

@test "parses haiku model" {
  parsed=$(parse_fixture "haiku_session.jsonl")
  model=$(get_parsed "model" "$parsed")
  [ "$model" = "haiku 4.5" ]
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
@test "short_model_name gives the family and version" {
  source_claude_ask
  [ "$(short_model_name "claude-opus-5-5")" = "opus 5.5" ]
  [ "$(short_model_name "claude-fable-5-1[1m]")" = "fable 5.1" ]
  [ "$(short_model_name "claude-opus-4-6")" = "opus 4.6" ]
  [ "$(short_model_name "claude-opus-4-20250514")" = "opus 4" ]
  [ "$(short_model_name "claude-sonnet-4-5-20250929")" = "sonnet 4.5" ]
  [ "$(short_model_name "claude-3-5-sonnet-20241022")" = "sonnet 3.5" ]
  [ "$(short_model_name "claude-3-opus-20240229")" = "opus 3" ]
  [ "$(short_model_name "us.anthropic.claude-haiku-5-5")" = "haiku 5.5" ]
}

@test "short_model_name falls back to the family, or the id without its suffix" {
  source_claude_ask
  [ "$(short_model_name "opus")" = "opus" ]
  [ "$(short_model_name "anthropic.claude-sonnet-4-5-v1:0")" = "sonnet" ]
  [ "$(short_model_name "some-other-model[1m]")" = "some-other-model" ]
}

# ---------------------------------------------------------------------------
# The parser coprocess
# ---------------------------------------------------------------------------
@test "parser: bad lines give no event and the next good line still parses" {
  source_claude_ask
  reset_stream_state
  ! process_stream_line 'not json'
  ! process_stream_line '[1, 2]'
  ! process_stream_line '"a string"'
  ! process_stream_line '{"type": "assistant", "message": "not an object"}'
  ! process_stream_line '{"no": "type"}'
  process_stream_line '{"type":"system","subtype":"init","model":"claude-opus-5-5","session_id":"s"}'
  [ "$model" = "opus 5.5" ]
  [ "$session_id" = "s" ]
}

@test "parser: a NUL in the text does not put it out of step" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"assistant","message":{"content":[{"type":"text","text":"a\u0000b"}]}}'
  [ "$CHUNK" = "ab" ]
  process_stream_line '{"type":"result","is_error":false,"result":"done","total_cost_usd":0.5,"duration_ms":10}'
  [ "$cost" = "0.5" ]
  [ "$status" = "done" ]
}

@test "parser: newlines between JSON tokens are read as one line" {
  source_claude_ask
  reset_stream_state
  process_stream_line $'{"type":"assistant",\n"message":{"content":[{"type":"text","text":"x\\ny"}]}}'
  [ "$CHUNK" = $'x\ny' ]
  process_stream_line '{"type":"system","subtype":"init","model":"claude-haiku-5-5"}'
  [ "$model" = "haiku 5.5" ]
}

@test "parser: one jq serves every event, and a dead one is started again" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"system","subtype":"init","model":"claude-opus-5-5"}'
  local pid="$STREAM_JQ_PID"
  process_stream_line '{"type":"system","subtype":"init","model":"claude-sonnet-5-5"}'
  [ "$STREAM_JQ_PID" = "$pid" ]
  kill "$pid"
  wait "$pid" 2> /dev/null || true
  process_stream_line '{"type":"system","subtype":"init","model":"claude-haiku-5-5"}'
  [ "$model" = "haiku 5.5" ]
  [ "$STREAM_JQ_PID" != "$pid" ]
  stop_stream_jq
}

@test "parser: jq ignores SIGINT" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"system","subtype":"init","model":"claude-opus-5-5"}'
  local pid="$STREAM_JQ_PID"
  kill -INT "$pid"
  sleep 0.2
  kill -0 "$pid"
  stop_stream_jq
}

@test "parser: no jq is left behind when the script exits" {
  local log="$TEST_TEMP_DIR/debug.log" pid
  run "$SCRIPT_PATH" --no-pager --debug-log="$log" "question"
  [ "$status" -eq 0 ]
  pid=$(sed -n 's/.*stream parser started: pid=\([0-9]*\).*/\1/p' "$log" | head -1)
  [ -n "$pid" ]
  sleep 0.2
  ! kill -0 "$pid" 2> /dev/null
}

# ---------------------------------------------------------------------------
# Partial messages: recorded from claude 2.1.317 (--include-partial-messages)
# ---------------------------------------------------------------------------
@test "partial messages: text comes once, from the deltas" {
  source_claude_ask
  reset_stream_state
  local chunks=0 line
  while IFS= read -r line; do
    process_stream_line "$line" || continue
    if [[ -n "$CHUNK" ]]; then chunks=$((chunks + 1)); fi
  done < "$FIXTURES_DIR/partial_messages.jsonl"
  local result
  result=$(jq -r 'select(.type == "result") | .result' "$FIXTURES_DIR/partial_messages.jsonl")
  # Both messages, once each, a blank line between them
  [[ "$answer_text" == *$'\n\n'"$result" ]]
  [ "$(grep -o 'contains' <<< "$answer_text" | wc -l)" -eq 1 ]
  [ "$chunks" -gt 5 ]
  [ "$status" = "done" ]
}

@test "partial messages: what each event sets" {
  source_claude_ask
  reset_stream_state
  se() { process_stream_line "{\"type\":\"stream_event\",\"event\":$1}"; }
  se '{"type":"message_start","message":{"id":"m1"}}'
  [ "$REDRAW_MAY_WAIT" -eq 1 ]
  se '{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}'
  [ "$is_thinking" -eq 1 ]
  # Thinking and tool input are not the answer
  se '{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}'
  [ -z "$CHUNK" ] && [ -z "$answer_text" ]
  se '{"type":"content_block_delta","delta":{"type":"text_delta","text":"He"}}'
  [ "$CHUNK" = "He" ] && [ "$is_thinking" -eq 0 ]
  se '{"type":"content_block_delta","delta":{"type":"text_delta","text":"llo "}}'
  [ "$answer_text" = "Hello " ]
  [ "$BLOCK_ENDED" -eq 0 ]
  # Its assistant event repeats the block
  process_stream_line '{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"Hello "}]}}'
  [ -z "$CHUNK" ] && [ "$answer_text" = "Hello " ]
  se '{"type":"content_block_stop","index":0}'
  [ "$BLOCK_ENDED" -eq 1 ]
  se '{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"Read"}}'
  [ "$current_tool" = "Read" ]
  se '{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"a\""}}'
  [ -z "$CHUNK" ] && [ "$current_tool" = "Read" ]
  process_stream_line '{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","name":"Read","input":{"file_path":"a.txt"}}]}}'
  [ "$current_tool" = "Read: a.txt" ]
  # A new message
  se '{"type":"message_start","message":{"id":"m2"}}'
  se '{"type":"content_block_delta","delta":{"type":"text_delta","text":"Done"}}'
  [ "$CHUNK" = $'\n\nDone' ]
  [ -z "$current_tool" ]
  [ "$answer_text" = $'Hello \n\nDone' ]
}

@test "partial messages: control characters are removed from deltas" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"a\u001b]52;c;x\u0007b\n"}}}'
  [ "$CHUNK" = $'a]52;c;xb\n' ]
}

# ---------------------------------------------------------------------------
# A background subagent: recorded from claude 2.1.317. Several results in a
# run, and one line of a subagent's text added (that run's had none)
# ---------------------------------------------------------------------------
@test "subagent: its own text is not the answer, in any form" {
  source_claude_ask
  reset_stream_state
  process_stream_line '{"type":"assistant","parent_tool_use_id":"t1","message":{"id":"s1","content":[{"type":"text","text":"inner"}]}}'
  [ -z "$CHUNK" ] && [ -z "$answer_text" ]
  process_stream_line '{"type":"stream_event","parent_tool_use_id":"t1","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"inner"}}}'
  [ -z "$CHUNK" ] && [ -z "$answer_text" ]
  [ "$stream_text_unconfirmed" -eq 0 ]
  # Its tools still show what is going on
  process_stream_line '{"type":"assistant","parent_tool_use_id":"t1","message":{"id":"s1","content":[{"type":"tool_use","name":"Read","input":{"file_path":"a"}}]}}'
  [ "$current_tool" = "Read: a" ]
  # And its thinking does not disturb the main answer's
  process_stream_line '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"mine"}}}'
  process_stream_line '{"type":"assistant","parent_tool_use_id":"t1","message":{"id":"s1","content":[{"type":"text","text":"inner"}]}}'
  [ "$stream_text_unconfirmed" -eq 1 ]
  process_stream_line '{"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"mine"}]}}'
  [ "$answer_text" = "mine" ]
}

@test "subagent: after a result a new init means it is running again" {
  source_claude_ask
  reset_stream_state
  local line
  process_stream_line '{"type":"system","subtype":"init","model":"claude-opus-5-5","session_id":"s"}'
  process_stream_line '{"type":"result","is_error":false,"result":"first"}'
  [ "$status" = "done" ]
  process_stream_line '{"type":"system","subtype":"status"}' || true
  [ "$status" = "done" ]
  process_stream_line '{"type":"system","subtype":"init","model":"claude-opus-5-5","session_id":"s"}'
  [ "$status" = "running" ]
  process_stream_line '{"type":"result","is_error":false,"result":""}'
  [ "$status" = "done" ]
}
