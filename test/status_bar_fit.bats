#!/usr/bin/env bats
# Test fitting the status bar to the terminal width and the redraw's row
# count when lines wrap

load test_helper

setup() {
  common_setup
  source_claude_ask
}

# A full bar: every segment present
full_bar() {
  render_status_bar_fitted "$1" "✓" "opus 5.5" "19.9k" "275" '$0.0950' "7.4s" "done"
}

@test "visible_width ignores color codes" {
  local w
  visible_width w $'\e[38;2;1;2;3mab\e[0mc'
  [ "$w" -eq 3 ]
  visible_width w ""
  [ "$w" -eq 0 ]
}

@test "text_rows counts wrapped rows" {
  local r
  TERM_COLS=10
  text_rows r "1234567890"
  [ "$r" -eq 1 ]
  text_rows r "12345678901"
  [ "$r" -eq 2 ]
  text_rows r $'\e[1m'"$(printf '%25s' x)"$'\e[0m'
  [ "$r" -eq 3 ]
  TERM_COLS=0
  text_rows r "$(printf '%300s' x)"
  [ "$r" -eq 1 ]
}

@test "a wide terminal gets every segment" {
  local bar
  TERM_COLS=200
  for THEME in minimal bubbles powerline; do
    full_bar bar
    bar=$(printf '%s' "$bar" | strip_ansi)
    [[ "$bar" == *"in:19.9k"* && "$bar" == *'$0.0950'* && "$bar" == *"7.4s"* && "$bar" == *"done"* ]]
  done
}

@test "segments go from the right until the bar fits" {
  local bar w full
  for THEME in minimal bubbles powerline; do
    TERM_COLS=0
    full_bar full
    visible_width w "$full"
    # One column short: "done" goes first
    TERM_COLS=$((w - 1))
    full_bar bar
    bar=$(printf '%s' "$bar" | strip_ansi)
    [[ "$bar" != *"done"* && "$bar" == *"7.4s"* ]]
    # Narrower: duration and cost go, the tokens stay
    TERM_COLS=40
    full_bar bar
    visible_width w "$bar"
    [ "$w" -le 40 ]
    bar=$(printf '%s' "$bar" | strip_ansi)
    [[ "$bar" == *"opus 5.5"* && "$bar" == *"in:19.9k"* && "$bar" != *"7.4s"* ]]
  done
}

@test "the model segment stays even when nothing fits" {
  local bar
  TERM_COLS=5
  for THEME in minimal bubbles powerline; do
    full_bar bar
    bar=$(printf '%s' "$bar" | strip_ansi)
    [[ "$bar" == *"opus 5.5"* && "$bar" != *"in:"* ]]
  done
}

@test "read_term_cols takes CLAUDE_ASK_COLUMNS and ignores junk" {
  CLAUDE_ASK_COLUMNS=42 read_term_cols
  [ "$TERM_COLS" -eq 42 ]
  CLAUDE_ASK_COLUMNS=wide read_term_cols
  [ "$TERM_COLS" -eq 0 ]
}

@test "the redraw moves up past every wrapped row" {
  # update_status_bar is defined after the sourcing guard: run the script
  run env CLAUDE_ASK_COLUMNS=20 "$SCRIPT_PATH" --no-pager --theme powerline -e high "question"
  [ "$status" -eq 0 ]
  # The info line ("  0 lines | 0 chars | 0 chunks | 0s") wraps at 20
  # columns: a move of more than 3 rows shows up
  [[ "$output" =~ $'\e['([4-9]|[1-9][0-9])A ]]
}

@test "a run in a narrow terminal leaves out segments" {
  run env CLAUDE_ASK_COLUMNS=40 "$SCRIPT_PATH" --no-pager --theme powerline "question"
  [ "$status" -eq 0 ]
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"sonnet 4.5"* ]]
  [[ "$output_clean" != *"3.2s"* ]]
}
