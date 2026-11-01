#!/usr/bin/env bats
# Test theme rendering functions

load test_helper

setup() {
  common_setup
  source_claude_ask
}

# ---------------------------------------------------------------------------
# Minimal theme
# ---------------------------------------------------------------------------
@test "minimal: renders model name" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "" "" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"opus"* ]]
}

@test "minimal: renders spinner" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "" "" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"⠋"* ]]
}

@test "minimal: renders tokens when present" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "19.9k" "275" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"in:19.9k"* ]]
  [[ "$result" == *"out:275"* ]]
}

@test "minimal: omits tokens when empty" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "" "" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" != *"in:"* ]]
  [[ "$result" != *"out:"* ]]
}

@test "minimal: renders cost when present" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "" "" '$0.0950' "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *'$0.0950'* ]]
}

@test "minimal: renders duration when present" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "" "" "" "7.4s" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"7.4s"* ]]
}

@test "minimal: renders done indicator" {
  THEME="minimal"
  render_status_bar result "✓" "opus" "19.9k" "275" '$0.0950' "7.4s" "done"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"done"* ]]
  [[ "$result" == *"✓"* ]]
}

@test "minimal: uses pipe separators" {
  THEME="minimal"
  render_status_bar result "⠋" "opus" "1k" "50" '$0.01' "1s" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"|"* ]]
}

# ---------------------------------------------------------------------------
# Bubbles theme
# ---------------------------------------------------------------------------
@test "bubbles: renders model name" {
  THEME="bubbles"
  render_status_bar result "⠋" "sonnet" "" "" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"sonnet"* ]]
}

@test "bubbles: renders tokens bubble" {
  THEME="bubbles"
  render_status_bar result "⠋" "sonnet" "6.3k" "150" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"in:6.3k"* ]]
  [[ "$result" == *"out:150"* ]]
}

@test "bubbles: renders cost bubble" {
  THEME="bubbles"
  render_status_bar result "⠋" "sonnet" "" "" '$0.012' "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *'$0.012'* ]]
}

@test "bubbles: renders done bubble" {
  THEME="bubbles"
  render_status_bar result "✓" "sonnet" "6.3k" "150" '$0.012' "3.2s" "done"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"done"* ]]
}

@test "bubbles: contains nerd font separator characters" {
  THEME="bubbles"
  render_status_bar result "⠋" "sonnet" "1k" "" "" "" "running"
  # Check for the raw separator bytes (U+E0B6 and U+E0B4)
  [[ "$result" == *$'\ue0b6'* ]]
  [[ "$result" == *$'\ue0b4'* ]]
}

# ---------------------------------------------------------------------------
# Powerline theme
# ---------------------------------------------------------------------------
@test "powerline: renders model name" {
  THEME="powerline"
  render_status_bar result "⠋" "haiku" "" "" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"haiku"* ]]
}

@test "powerline: starts with decorative gradient" {
  THEME="powerline"
  render_status_bar result "⠋" "haiku" "" "" "" "" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == "░▒▓"* ]]
}

@test "powerline: renders all segments" {
  THEME="powerline"
  render_status_bar result "⠋" "haiku" "2.1k" "80" '$0.003' "1.5s" "running"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"haiku"* ]]
  [[ "$result" == *"in:2.1k"* ]]
  [[ "$result" == *"out:80"* ]]
  [[ "$result" == *'$0.003'* ]]
  [[ "$result" == *"1.5s"* ]]
}

@test "powerline: contains powerline separator character" {
  THEME="powerline"
  render_status_bar result "⠋" "haiku" "1k" "" "" "" "running"
  [[ "$result" == *$'\ue0b0'* ]]
}

@test "powerline: renders done state" {
  THEME="powerline"
  render_status_bar result "✓" "haiku" "2.1k" "80" '$0.003' "1.5s" "done"
  result=$(printf '%s' "$result" | strip_ansi)
  [[ "$result" == *"done"* ]]
}

# ---------------------------------------------------------------------------
# render_status_bar dispatch
# ---------------------------------------------------------------------------
@test "powerline: separator after a missing tokens segment uses the claude color" {
  THEME="powerline"
  render_status_bar bar "x" "opus" "" "" '$0.01' "" "running"
  [[ "$bar" == *"${BG_COST}${FG_CLAUDE}${SEP_POWERLINE}"* ]]
}

@test "powerline: separator after a missing cost segment uses the tokens color" {
  THEME="powerline"
  render_status_bar bar "x" "opus" "1k" "50" "" "2.0s" "running"
  [[ "$bar" == *"${BG_DURATION}${FG_TOKENS}${SEP_POWERLINE}"* ]]
}

@test "powerline: done cap follows the last present segment" {
  THEME="powerline"
  render_status_bar bar "x" "opus" "1k" "50" '$0.01' "" "done"
  [[ "$bar" == *"${BG_COST}${FG_COST}${SEP_POWERLINE}${RST}${BG_COST} ${FG_COST}done"* ]]
}

@test "render_status_bar dispatches to correct theme" {
  # Each theme produces different output for the same input
  THEME="minimal"
  render_status_bar minimal_out "⠋" "opus" "1k" "50" "" "" "running"
  minimal_out=$(printf '%s' "$minimal_out" | strip_ansi)

  THEME="powerline"
  render_status_bar powerline_out "⠋" "opus" "1k" "50" "" "" "running"
  powerline_out=$(printf '%s' "$powerline_out" | strip_ansi)

  # Powerline has the ░▒▓ prefix, minimal doesn't
  [[ "$powerline_out" == "░▒▓"* ]]
  [[ "$minimal_out" != "░▒▓"* ]]
}

# ---------------------------------------------------------------------------
# Output variables
# ---------------------------------------------------------------------------
@test "renderers and formatters write into any caller variable name" {
  # These names are used inside the functions themselves (without the "_"
  # prefix the locals now carry); the results must still reach the caller
  local line out n info status
  render_status_bar line "x" "opus" "1k" "" "" "" "running"
  [[ "$(printf '%s' "$line" | strip_ansi)" == *"opus"* ]]
  format_tokens out 19900
  [ "$out" = "19.9k" ]
  format_duration n 7429
  [ "$n" = "7.4s" ]
  render_stream_info info 3 1500 7 "" done 0
  [[ "$info" == *"1.5k chars"* ]]
  format_cost status 0.5
  [ "$status" = '$0.5000' ]
}
