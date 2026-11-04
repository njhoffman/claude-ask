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

@test "model and cwd come from the init event when hook events come first" {
  local file
  file=$(save_session "$FIXTURES_DIR/hooks_first.jsonl" "hooks")
  [ "$(jq -r '.model' "$file")" = "claude-opus-5-5" ]
  [ "$(jq -r '.cwd' "$file")" = "/work/project" ]
  [ "$(jq -r '.session_id' "$file")" = "hooks-session-001" ]
}

@test "a second turn is added to an existing session file" {
  local file
  file=$(save_session "$FIXTURES_DIR/full_session.jsonl" "first")
  save_session "$FIXTURES_DIR/haiku_session.jsonl" "second" "$file" > /dev/null
  [ "$(jq -r '.turn_count' "$file")" = "2" ]
  [ "$(jq -r '.answer' "$file")" = "Quick answer." ]
  [ "$(jq -r '.usage.input_tokens' "$file")" = "550" ]
  [ "$(jq -r '.turns[0].answer' "$file")" = "The capital of France is **Paris**." ]
}

@test "an old single-turn file becomes the first turn" {
  jq -n '{session_id: "s1", model: "opus", name: "legacy", question: "old q",
    answer: "old a", cost_usd: 0.5, timestamp: "2026-01-01T00:00:00Z"}' > "$SESSION_DIR/legacy.json"
  save_session "$FIXTURES_DIR/full_session.jsonl" "new q" "$SESSION_DIR/legacy.json" > /dev/null
  [ "$(jq -r '[.turns[].question] | join(",")' "$SESSION_DIR/legacy.json")" = "old q,new q" ]
  [ "$(jq -r '.cost_usd' "$SESSION_DIR/legacy.json")" = "0.512345" ]
}

# turn_fixture DIR N IN OUT COST API USAGE_IN USAGE_OUT: a fixture for one call,
# from what claude reports: running totals in modelUsage, cost and API time
turn_fixture() {
  jq -c -n --arg n "$2" --argjson in "$3" --argjson out "$4" --argjson cost "$5" --argjson api "$6" \
    --argjson uin "$7" --argjson uout "$8" '
    {type: "system", subtype: "init", session_id: "s", model: "claude-haiku-5-5"},
    {type: "assistant", session_id: "s", message: {id: ("m" + $n), content: [{type: "text", text: ("answer " + $n)}]}},
    {type: "result", is_error: false, session_id: "s", result: ("answer " + $n), total_cost_usd: $cost,
     duration_ms: 1000, duration_api_ms: $api, usage: {input_tokens: $uin, output_tokens: $uout},
     modelUsage: {"claude-haiku-5-5": {inputTokens: $in, outputTokens: $out, cacheReadInputTokens: ($in * 1000), cacheCreationInputTokens: 0}}}' \
    > "$1/turn$2.jsonl"
}

# The numbers of a real run: three turns of one conversation
real_turns() {
  turn_fixture "$TEST_TEMP_DIR" 1 2 221 0.00633442 2193 2 221
  turn_fixture "$TEST_TEMP_DIR" 2 4 227 0.00678822 3558 2 6
  turn_fixture "$TEST_TEMP_DIR" 3 6 230 0.00722921 4858 2 3
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  export CLAUDE_STUB_FIXTURES="$TEST_TEMP_DIR/turn1.jsonl $TEST_TEMP_DIR/turn2.jsonl $TEST_TEMP_DIR/turn3.jsonl"
}

@test "a resumed conversation: each turn has what it added, the total is claude's last" {
  real_turns
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf 'first\nsecond\nthird\n')
  [ "$status" -eq 0 ]
  local f="$SESSION_DIR/first.json"
  [ "$(jq -c '[.turns[].usage.output_tokens]' "$f")" = "[221,6,3]" ]
  [ "$(jq -c '[.turns[].usage.input_tokens]' "$f")" = "[2,2,2]" ]
  [ "$(jq -c '[.turns[].duration_api_ms]' "$f")" = "[2193,1365,1300]" ]
  [ "$(jq -c '[.turns[].cost_usd]' "$f")" = "[0.00633442,0.0004538,0.00044099]" ]
  # The totals agree with what claude last reported
  [ "$(jq -c '.cost_usd' "$f")" = "0.00722921" ]
  [ "$(jq -c '[.usage.input_tokens, .usage.output_tokens, .duration_api_ms]' "$f")" = "[6,230,4858]" ]
  [ "$(jq -c '.usage.cache_read_input_tokens' "$f")" = "6000" ]
  # Wall-clock time really is per run
  [ "$(jq -c '.duration_ms' "$f")" = "3000" ]
}

@test "the bar shows each turn's own numbers and the real total" {
  real_turns
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf 'first\nsecond\n')
  local clean
  clean=$(printf '%s' "$output" | strip_ansi)
  local finals
  finals=$(grep -a 'done' <<< "$clean")
  [[ "$(head -1 <<< "$finals")" == *"in:2 out:221"* ]]
  [[ "$(head -1 <<< "$finals")" == *'$0.0063'* ]]
  [[ "$(tail -1 <<< "$finals")" == *"in:2 out:6"* ]]
  [[ "$(tail -1 <<< "$finals")" == *'$0.0005'* ]]
  [[ "$clean" == *'turn 2 | $0.0068 total'* ]]
}

@test "resuming in a new run carries on from the saved totals" {
  real_turns
  run "$SCRIPT_PATH" --no-pager "first"
  run "$SCRIPT_PATH" --no-pager -r "second"
  run "$SCRIPT_PATH" --no-pager --resume=first "third"
  local f="$SESSION_DIR/first.json"
  [ "$(jq -c '[.turns[].usage.output_tokens]' "$f")" = "[221,6,3]" ]
  [ "$(jq -c '.cost_usd' "$f")" = "0.00722921" ]
  [ "$(jq -c '.usage.output_tokens' "$f")" = "230" ]
  # --session replays each turn's own
  run "$SCRIPT_PATH" --no-pager --session first
  [[ "$(printf '%s' "$output" | strip_ansi)" == *"in:2 out:6"* ]]
}

@test "a total that goes down starts again: no negative numbers" {
  turn_fixture "$TEST_TEMP_DIR" 1 10 500 0.5 1000 10 500
  turn_fixture "$TEST_TEMP_DIR" 2 3 20 0.1 200 3 20
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  export CLAUDE_STUB_FIXTURES="$TEST_TEMP_DIR/turn1.jsonl $TEST_TEMP_DIR/turn2.jsonl"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf 'first\nsecond\n')
  local f="$SESSION_DIR/first.json"
  [ "$(jq -c '[.turns[].usage.output_tokens]' "$f")" = "[500,20]" ]
  [ "$(jq -c '[.turns[].cost_usd]' "$f")" = "[0.5,0.1]" ]
  [ "$(jq -c '.cost_usd' "$f")" = "0.6" ]
}

@test "with no modelUsage the tokens are per result, the cost still a running total" {
  jq -c -n '{type: "system", subtype: "init", session_id: "s", model: "m"},
    {type: "result", is_error: false, session_id: "s", result: "a", total_cost_usd: 0.3, duration_ms: 1, usage: {input_tokens: 1, output_tokens: 50}}' > "$TEST_TEMP_DIR/turn1.jsonl"
  jq -c -n '{type: "system", subtype: "init", session_id: "s", model: "m"},
    {type: "result", is_error: false, session_id: "s", result: "b", total_cost_usd: 0.4, duration_ms: 1, usage: {input_tokens: 2, output_tokens: 7}}' > "$TEST_TEMP_DIR/turn2.jsonl"
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  export CLAUDE_STUB_FIXTURES="$TEST_TEMP_DIR/turn1.jsonl $TEST_TEMP_DIR/turn2.jsonl"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf 'first\nsecond\n')
  local f="$SESSION_DIR/first.json"
  [ "$(jq -c '[.turns[].usage.output_tokens]' "$f")" = "[50,7]" ]
  [ "$(jq -c '.usage.output_tokens' "$f")" = "57" ]
  [ "$(jq -c '.cost_usd' "$f")" = "0.4" ]
}

@test "a file saved before totals gets its turns put right with a new one" {
  jq -n '{session_id: "s", question: "q1", turn_count: 2, cost_usd: 0.7, duration_api_ms: 700, usage: {},
    turns: [{question: "q1", answer: "a1", cost_usd: 0.3, duration_api_ms: 300, usage: {input_tokens: 1, output_tokens: 40}},
            {question: "q2", answer: "a2", cost_usd: 0.4, duration_api_ms: 400, usage: {input_tokens: 1, output_tokens: 5}}]}' > "$SESSION_DIR/old.json"
  jq -c -n '{type: "system", subtype: "init", session_id: "s", model: "m"},
    {type: "result", is_error: false, session_id: "s", result: "a3", total_cost_usd: 0.5, duration_ms: 1, duration_api_ms: 500,
     usage: {input_tokens: 1, output_tokens: 3}, modelUsage: {m: {inputTokens: 3, outputTokens: 48}}}' > "$TEST_TEMP_DIR/turn.jsonl"
  CLAUDE_STUB_FIXTURE="$TEST_TEMP_DIR/turn.jsonl" run "$SCRIPT_PATH" --no-pager --resume=old "q3"
  [ "$status" -eq 0 ]
  local f="$SESSION_DIR/old.json"
  [ "$(jq -c '[.turns[].cost_usd]' "$f")" = "[0.3,0.1,0.1]" ]
  [ "$(jq -c '.cost_usd' "$f")" = "0.5" ]
  [ "$(jq -c '.duration_api_ms' "$f")" = "500" ]
  # Its tokens were each turn's own, and no running total to compare with
  [ "$(jq -c '[.turns[].usage.output_tokens]' "$f")" = "[40,5,3]" ]
}

@test "a turn with no cost keeps the others' total" {
  turn_fixture "$TEST_TEMP_DIR" 1 2 221 0.25 2193 2 221
  jq -c -n '{type: "system", subtype: "init", session_id: "s", model: "m"},
    {type: "result", is_error: true, session_id: "s", result: "broke", duration_ms: 1}' > "$TEST_TEMP_DIR/turn2.jsonl"
  export CLAUDE_STUB_LOG="$TEST_TEMP_DIR/calls"
  export CLAUDE_STUB_FIXTURES="$TEST_TEMP_DIR/turn1.jsonl $TEST_TEMP_DIR/turn2.jsonl"
  CLAUDE_ASK_FORCE_INTERACTIVE=1 run "$SCRIPT_PATH" --no-pager < <(printf 'first\nsecond\n')
  [ "$(jq -c '.cost_usd' "$SESSION_DIR/first.json")" = "0.25" ]
  [ "$(jq -c '.usage.output_tokens' "$SESSION_DIR/first.json")" = "221" ]
}
