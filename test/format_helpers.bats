#!/usr/bin/env bats
# Test format helper functions

load test_helper

setup() {
  common_setup
  source_claude_ask
}

# ---------------------------------------------------------------------------
# format_tokens
# ---------------------------------------------------------------------------
@test "format_tokens: empty input returns empty" {
  format_tokens result ""
  [ -z "$result" ]
}

@test "format_tokens: zero returns empty" {
  format_tokens result "0"
  [ -z "$result" ]
}

@test "format_tokens: small number returns as-is" {
  format_tokens result "500"
  [ "$result" = "500" ]
}

@test "format_tokens: 999 returns as-is" {
  format_tokens result "999"
  [ "$result" = "999" ]
}

@test "format_tokens: 1000 formats as 1.0k" {
  format_tokens result "1000"
  [ "$result" = "1.0k" ]
}

@test "format_tokens: 19900 formats as 19.9k" {
  format_tokens result "19900"
  [ "$result" = "19.9k" ]
}

@test "format_tokens: 1000000 formats as 1.0M" {
  format_tokens result "1000000"
  [ "$result" = "1.0M" ]
}

@test "format_tokens: 2500000 formats as 2.5M" {
  format_tokens result "2500000"
  [ "$result" = "2.5M" ]
}

# ---------------------------------------------------------------------------
# format_duration
# ---------------------------------------------------------------------------
@test "format_duration: empty input returns empty" {
  format_duration result ""
  [ -z "$result" ]
}

@test "format_duration: sub-second shows ms" {
  format_duration result "500"
  [ "$result" = "500ms" ]
}

@test "format_duration: 1000ms formats as 1.0s" {
  format_duration result "1000"
  [ "$result" = "1.0s" ]
}

@test "format_duration: 7429ms formats as 7.4s" {
  format_duration result "7429"
  [ "$result" = "7.4s" ]
}

@test "format_duration: 60000ms formats as 1m0s" {
  format_duration result "60000"
  [ "$result" = "1m0s" ]
}

@test "format_duration: 90000ms formats as 1m30s" {
  format_duration result "90000"
  [ "$result" = "1m30s" ]
}

# ---------------------------------------------------------------------------
# format_cost
# ---------------------------------------------------------------------------
@test "format_cost: empty input returns empty" {
  format_cost result ""
  [ -z "$result" ]
}

@test "format_cost: formats with 4 decimal places" {
  format_cost result "0.094995"
  [ "$result" = '$0.0950' ]
}

@test "format_cost: formats zero" {
  format_cost result "0"
  [ "$result" = '$0.0000' ]
}

@test "format_cost: formats small cost" {
  format_cost result "0.001"
  [ "$result" = '$0.0010' ]
}

# ---------------------------------------------------------------------------
# format_count
# ---------------------------------------------------------------------------
@test "format_count: empty input returns 0" {
  format_count result ""
  [ "$result" = "0" ]
}

@test "format_count: zero returns 0" {
  format_count result "0"
  [ "$result" = "0" ]
}

@test "format_count: small number returns as-is" {
  format_count result "42"
  [ "$result" = "42" ]
}

@test "format_count: 1500 formats as 1.5k" {
  format_count result "1500"
  [ "$result" = "1.5k" ]
}

@test "format_count: 2500000 formats as 2.5M" {
  format_count result "2500000"
  [ "$result" = "2.5M" ]
}

# ---------------------------------------------------------------------------
# format_elapsed
# ---------------------------------------------------------------------------
@test "format_elapsed: empty input returns 0s" {
  format_elapsed result ""
  [ "$result" = "0s" ]
}

@test "format_elapsed: zero returns 0s" {
  format_elapsed result "0"
  [ "$result" = "0s" ]
}

@test "format_elapsed: seconds" {
  format_elapsed result "45"
  [ "$result" = "45s" ]
}

@test "format_elapsed: minutes and seconds" {
  format_elapsed result "90"
  [ "$result" = "1m30s" ]
}

@test "format_elapsed: hours and minutes" {
  format_elapsed result "3720"
  [ "$result" = "1h2m" ]
}

# ---------------------------------------------------------------------------
# render_stream_info
# ---------------------------------------------------------------------------
@test "render_stream_info: shows lines and chars" {
  render_stream_info result "42" "1500" "12" "5" "running" "0"
  [[ "$result" == *"42 lines"* ]]
  [[ "$result" == *"1.5k chars"* ]]
  [[ "$result" == *"12 chunks"* ]]
}

@test "render_stream_info: shows elapsed when running" {
  render_stream_info result "10" "500" "5" "30" "running" "0"
  [[ "$result" == *"30s"* ]]
}

@test "render_stream_info: omits elapsed when done" {
  render_stream_info result "10" "500" "5" "30" "done" "0"
  [[ "$result" != *"30s"* ]]
}

@test "render_stream_info: shows thinking indicator" {
  render_stream_info result "0" "0" "0" "3" "running" "1"
  [[ "$result" == *"thinking"* ]]
}

@test "render_stream_info: hides thinking when done" {
  render_stream_info result "10" "500" "5" "30" "done" "1"
  [[ "$result" != *"thinking"* ]]
}

# ---------------------------------------------------------------------------
# Locale independence
# ---------------------------------------------------------------------------
@test "formats numbers with a dot under a comma-decimal locale" {
  locale -a 2> /dev/null | grep -qi '^de_DE\.utf-\?8$' || skip "de_DE.UTF-8 locale not installed"
  export LC_ALL=de_DE.UTF-8
  run "$SCRIPT_PATH" --no-pager "test"
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *'$0.0123'* ]]
  [[ "$output_clean" == *"3.2s"* ]]
}

@test "debug log timestamps have milliseconds" {
  run "$SCRIPT_PATH" --no-pager --debug-log="$TEST_TEMP_DIR/debug.log" "test"
  [ "$status" -eq 0 ]
  grep -Eq '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}\] args parsed' "$TEST_TEMP_DIR/debug.log"
}
