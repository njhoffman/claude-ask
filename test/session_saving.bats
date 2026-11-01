#!/usr/bin/env bats
# Test session saving logic

load test_helper

setup() {
  common_setup
  source_claude_ask
}

@test "saves parsed session named after the question" {
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "What is the capital of France?")

  [ "$file" = "$SESSION_DIR/what-is-the-capital-of-france.json" ]
  [ -f "$file" ]
  [ "$(jq -r '.session_id' "$file")" = "full-session-001" ]
  [[ "$(jq -r '.model' "$file")" == *"sonnet"* ]]
  [ "$(jq -r '.name' "$file")" = "what-is-the-capital-of-france" ]
  [ "$(jq -r '.question' "$file")" = "What is the capital of France?" ]
  [[ "$(jq -r '.answer' "$file")" == *"Paris"* ]]
  [ "$(jq -r '.cost_usd' "$file")" = "0.012345" ]
  [ "$(jq -r '.duration_ms' "$file")" = "3200" ]
  [ "$(jq -r '.is_error' "$file")" = "false" ]
  [ "$(jq -r '.timestamp' "$file")" != "null" ]
}

@test "a second session with the same question gets a numbered name" {
  save_session "$FIXTURES_DIR/full_session.jsonl" "same question" > /dev/null
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "same question")
  [ "$file" = "$SESSION_DIR/same-question-2.json" ]
}

@test "saved session includes thinking text" {
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "q")
  [[ "$(jq -r '.thinking' "$file")" == *"think about"* ]]
}

@test "saved session finds thinking in any content block" {
  local file
  file=$(save_session "$FIXTURES_DIR/multi_block.jsonl" "q")
  [ "$(jq -r '.thinking' "$file")" = "Weighing the options." ]
}

@test "saved session includes usage tokens" {
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "q")
  [ "$(jq -r '.usage.input_tokens' "$file")" = "500" ]
  [ "$(jq -r '.usage.output_tokens' "$file")" = "15" ]
  [ "$(jq -r '.usage.cache_creation_input_tokens' "$file")" = "8000" ]
  [ "$(jq -r '.usage.cache_read_input_tokens' "$file")" = "4000" ]
}

@test "saved session records an error result" {
  local file
  file=$(save_session "$FIXTURES_DIR/result_error.jsonl" "q")
  [ "$(jq -r '.is_error' "$file")" = "true" ]
  [ "$(jq -r '.answer' "$file")" = "Invalid API key" ]
}

@test "raw save mode also writes the stream unchanged as .jsonl" {
  SAVE_RAW=1
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "raw test")
  [ "$file" = "$SESSION_DIR/raw-test.json" ]
  [ "$(jq -r '.session_id' "$file")" = "full-session-001" ]
  cmp "$SESSION_DIR/raw-test.jsonl" "$FIXTURES_DIR/full_session.jsonl"
}

@test "without --save-raw no .jsonl is written" {
  save_session "$FIXTURES_DIR/full_session.jsonl" "plain" > /dev/null
  [ ! -e "$SESSION_DIR/plain.jsonl" ]
}

@test "a question with no ASCII letters is named after the session id" {
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "日本の首都は？")
  [ "$file" = "$SESSION_DIR/session-full-ses.json" ]
  [ "$(jq -r '.question' "$file")" = "日本の首都は？" ]
}

@test "a punctuation-only question is named after the session id" {
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "???")
  [ "$file" = "$SESSION_DIR/session-full-ses.json" ]
}

@test "without a session id the fallback name uses the time" {
  local file
  file=$(save_session "$FIXTURES_DIR/text_chunk.jsonl" "???")
  [[ "$file" =~ /session-[0-9]{8}-[0-9]{6}\.json$ ]]
}

@test "a session saved under a fallback name shows in the history" {
  save_session "$FIXTURES_DIR/full_session.jsonl" "日本の首都は？" > /dev/null
  run show_history "$SESSION_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session-full-ses"* ]]
  [ -z "$(ls -A "$SESSION_DIR" | grep '^\.')" ]
}
