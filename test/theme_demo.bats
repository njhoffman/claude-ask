#!/usr/bin/env bats
# Test --demo-themes option

load test_helper

@test "--demo-themes exits 0" {
  run "$SCRIPT_PATH" --demo-themes
  [ "$status" -eq 0 ]
}

@test "--demo-themes shows all three theme names" {
  run "$SCRIPT_PATH" --demo-themes
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"minimal"* ]]
  [[ "$output_clean" == *"bubbles"* ]]
  [[ "$output_clean" == *"powerline"* ]]
}

@test "--demo-themes shows streaming and finished labels" {
  run "$SCRIPT_PATH" --demo-themes
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"streaming:"* ]]
  [[ "$output_clean" == *"finished:"* ]]
}

@test "--demo-themes shows sample model name" {
  run "$SCRIPT_PATH" --demo-themes
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"opus"* ]]
}

@test "--demo-themes shows checkmark for finished state" {
  run "$SCRIPT_PATH" --demo-themes
  [[ "$output" == *"✓"* ]]
}

@test "--demo-themes shows sample cost" {
  run "$SCRIPT_PATH" --demo-themes
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *'$0.0950'* ]]
}

@test "--demo-themes shows sample duration" {
  run "$SCRIPT_PATH" --demo-themes
  output_clean=$(echo "$output" | strip_ansi)
  [[ "$output_clean" == *"7.4s"* ]]
}

@test "--demo-themes does not require a question argument" {
  run "$SCRIPT_PATH" --demo-themes
  [ "$status" -eq 0 ]
  [[ "$output" != *"Usage:"* ]]
}
