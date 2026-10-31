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
  result=$(render_status_bar "⠋" "opus" "" "" "" "" "running" | strip_ansi)
  [[ "$result" == *"opus"* ]]
}

@test "minimal: renders spinner" {
  THEME="minimal"
  result=$(render_status_bar "⠋" "opus" "" "" "" "" "running" | strip_ansi)
  [[ "$result" == *"⠋"* ]]
}

@test "minimal: renders tokens when present" {
  THEME="minimal"
  result=$(render_status_bar "⠋" "opus" "19.9k" "275" "" "" "running" | strip_ansi)
  [[ "$result" == *"in:19.9k"* ]]
  [[ "$result" == *"out:275"* ]]
}

@test "minimal: omits tokens when empty" {
  THEME="minimal"
  result=$(render_status_bar "⠋" "opus" "" "" "" "" "running" | strip_ansi)
  [[ "$result" != *"in:"* ]]
  [[ "$result" != *"out:"* ]]
}

@test "minimal: renders cost when present" {
  THEME="minimal"
  result=$(render_status_bar "⠋" "opus" "" "" '$0.0950' "" "running" | strip_ansi)
  [[ "$result" == *'$0.0950'* ]]
}

@test "minimal: renders duration when present" {
  THEME="minimal"
  result=$(render_status_bar "⠋" "opus" "" "" "" "7.4s" "running" | strip_ansi)
  [[ "$result" == *"7.4s"* ]]
}

@test "minimal: renders done indicator" {
  THEME="minimal"
  result=$(render_status_bar "✓" "opus" "19.9k" "275" '$0.0950' "7.4s" "done" | strip_ansi)
  [[ "$result" == *"done"* ]]
  [[ "$result" == *"✓"* ]]
}

@test "minimal: uses pipe separators" {
  THEME="minimal"
  result=$(render_status_bar "⠋" "opus" "1k" "50" '$0.01' "1s" "running" | strip_ansi)
  [[ "$result" == *"|"* ]]
}

# ---------------------------------------------------------------------------
# Bubbles theme
# ---------------------------------------------------------------------------
@test "bubbles: renders model name" {
  THEME="bubbles"
  result=$(render_status_bar "⠋" "sonnet" "" "" "" "" "running" | strip_ansi)
  [[ "$result" == *"sonnet"* ]]
}

@test "bubbles: renders tokens bubble" {
  THEME="bubbles"
  result=$(render_status_bar "⠋" "sonnet" "6.3k" "150" "" "" "running" | strip_ansi)
  [[ "$result" == *"in:6.3k"* ]]
  [[ "$result" == *"out:150"* ]]
}

@test "bubbles: renders cost bubble" {
  THEME="bubbles"
  result=$(render_status_bar "⠋" "sonnet" "" "" '$0.012' "" "running" | strip_ansi)
  [[ "$result" == *'$0.012'* ]]
}

@test "bubbles: renders done bubble" {
  THEME="bubbles"
  result=$(render_status_bar "✓" "sonnet" "6.3k" "150" '$0.012' "3.2s" "done" | strip_ansi)
  [[ "$result" == *"done"* ]]
}

@test "bubbles: contains nerd font separator characters" {
  THEME="bubbles"
  result=$(render_status_bar "⠋" "sonnet" "1k" "" "" "" "running")
  # Check for the raw separator bytes (U+E0B6 and U+E0B4)
  [[ "$result" == *$'\ue0b6'* ]]
  [[ "$result" == *$'\ue0b4'* ]]
}

# ---------------------------------------------------------------------------
# Powerline theme
# ---------------------------------------------------------------------------
@test "powerline: renders model name" {
  THEME="powerline"
  result=$(render_status_bar "⠋" "haiku" "" "" "" "" "running" | strip_ansi)
  [[ "$result" == *"haiku"* ]]
}

@test "powerline: starts with decorative gradient" {
  THEME="powerline"
  result=$(render_status_bar "⠋" "haiku" "" "" "" "" "running" | strip_ansi)
  [[ "$result" == "░▒▓"* ]]
}

@test "powerline: renders all segments" {
  THEME="powerline"
  result=$(render_status_bar "⠋" "haiku" "2.1k" "80" '$0.003' "1.5s" "running" | strip_ansi)
  [[ "$result" == *"haiku"* ]]
  [[ "$result" == *"in:2.1k"* ]]
  [[ "$result" == *"out:80"* ]]
  [[ "$result" == *'$0.003'* ]]
  [[ "$result" == *"1.5s"* ]]
}

@test "powerline: contains powerline separator character" {
  THEME="powerline"
  result=$(render_status_bar "⠋" "haiku" "1k" "" "" "" "running")
  [[ "$result" == *$'\ue0b0'* ]]
}

@test "powerline: renders done state" {
  THEME="powerline"
  result=$(render_status_bar "✓" "haiku" "2.1k" "80" '$0.003' "1.5s" "done" | strip_ansi)
  [[ "$result" == *"done"* ]]
}

# ---------------------------------------------------------------------------
# render_status_bar dispatch
# ---------------------------------------------------------------------------
@test "powerline: separator after a missing tokens segment uses the claude color" {
  THEME="powerline"
  out=$(render_status_bar "x" "opus" "" "" '$0.01' "" "running")
  [[ "$out" == *"${BG_COST}${FG_CLAUDE}${SEP_POWERLINE}"* ]]
}

@test "powerline: separator after a missing cost segment uses the tokens color" {
  THEME="powerline"
  out=$(render_status_bar "x" "opus" "1k" "50" "" "2.0s" "running")
  [[ "$out" == *"${BG_DURATION}${FG_TOKENS}${SEP_POWERLINE}"* ]]
}

@test "powerline: done cap follows the last present segment" {
  THEME="powerline"
  out=$(render_status_bar "x" "opus" "1k" "50" '$0.01' "" "done")
  [[ "$out" == *"${BG_COST}${FG_COST}${SEP_POWERLINE}${RST}${BG_COST} ${FG_COST}done"* ]]
}

@test "render_status_bar dispatches to correct theme" {
  # Each theme produces different output for the same input
  THEME="minimal"
  minimal_out=$(render_status_bar "⠋" "opus" "1k" "50" "" "" "running" | strip_ansi)

  THEME="powerline"
  powerline_out=$(render_status_bar "⠋" "opus" "1k" "50" "" "" "running" | strip_ansi)

  # Powerline has the ░▒▓ prefix, minimal doesn't
  [[ "$powerline_out" == "░▒▓"* ]]
  [[ "$minimal_out" != "░▒▓"* ]]
}
