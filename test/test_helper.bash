# BATS test helper for claude-ask tests

SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/bin/claude-ask"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Source claude-ask functions without executing the main logic.
# Sets _CLAUDE_ASK_SOURCED=1 so the script returns after defining functions.
# Requires a dummy positional arg or THEME_DEMO=1 to pass arg validation.
source_claude_ask() {
  export _CLAUDE_ASK_SOURCED=1
  # Provide a dummy question to pass the positional check
  source "$SCRIPT_PATH" "dummy" 2>/dev/null
  unset _CLAUDE_ASK_SOURCED
}

# Strip ANSI escape sequences from text for assertion matching.
strip_ansi() {
  sed 's/\x1b\[[0-9;]*[mK]//g; s/\x1b\[[0-9]*;[0-9]*[Hr]//g; s/\x1b\[\?25[hl]//g; s/\x1b\[[su]//g'
}

# Run a fixture file through the JSON parsing logic.
# Feeds fixture lines through the parse loop and captures variable state.
# Usage: parsed=$(parse_fixture "full_session.jsonl")
# Then:  echo "$parsed" | grep "^model=" | cut -d= -f2-
parse_fixture() {
  local fixture_name="$1"
  local fixture_path="${FIXTURES_DIR}/${fixture_name}"

  source_claude_ask

  # Reset state variables
  model=""
  session_id=""
  spinner_idx=0
  input_tokens=""
  output_tokens=""
  cache_creation_tokens=""
  cache_read_tokens=""
  cost=""
  duration_ms=""
  answer_text=""
  status="running"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    [[ -z "$line_type" ]] && continue

    case "$line_type" in
      system)
        model=$(printf '%s' "$line" | jq -r '.model // empty' 2>/dev/null) || true
        session_id=$(printf '%s' "$line" | jq -r '.session_id // empty' 2>/dev/null) || true
        model="${model%%\[*}"
        case "${model,,}" in
          *haiku*)  model="haiku" ;;
          *sonnet*) model="sonnet" ;;
          *opus*)   model="opus" ;;
        esac
        ;;
      assistant)
        content_type=$(printf '%s' "$line" | jq -r '.message.content[0].type // empty' 2>/dev/null) || true
        if [[ "$content_type" == "text" ]]; then
          text_chunk=$(printf '%s' "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null) || true
          [[ -n "$text_chunk" ]] && answer_text+="$text_chunk"
        fi
        new_input=$(printf '%s' "$line" | jq -r '.message.usage.input_tokens // empty' 2>/dev/null) || true
        new_output=$(printf '%s' "$line" | jq -r '.message.usage.output_tokens // empty' 2>/dev/null) || true
        new_cache_creation=$(printf '%s' "$line" | jq -r '.message.usage.cache_creation_input_tokens // empty' 2>/dev/null) || true
        new_cache_read=$(printf '%s' "$line" | jq -r '.message.usage.cache_read_input_tokens // empty' 2>/dev/null) || true
        [[ -n "$new_input" ]] && input_tokens="$new_input"
        [[ -n "$new_output" ]] && output_tokens="$new_output"
        [[ -n "$new_cache_creation" ]] && cache_creation_tokens="$new_cache_creation"
        [[ -n "$new_cache_read" ]] && cache_read_tokens="$new_cache_read"
        ;;
      result)
        status="done"
        cost=$(printf '%s' "$line" | jq -r '.total_cost_usd // empty' 2>/dev/null) || true
        duration_ms=$(printf '%s' "$line" | jq -r '.duration_ms // empty' 2>/dev/null) || true
        new_input=$(printf '%s' "$line" | jq -r '.usage.input_tokens // empty' 2>/dev/null) || true
        new_output=$(printf '%s' "$line" | jq -r '.usage.output_tokens // empty' 2>/dev/null) || true
        [[ -n "$new_input" ]] && input_tokens="$new_input"
        [[ -n "$new_output" ]] && output_tokens="$new_output"
        ;;
    esac
  done < "$fixture_path"

  # Output all state as key=value for easy assertion
  echo "model=$model"
  echo "session_id=$session_id"
  echo "input_tokens=$input_tokens"
  echo "output_tokens=$output_tokens"
  echo "cache_creation_tokens=$cache_creation_tokens"
  echo "cache_read_tokens=$cache_read_tokens"
  echo "cost=$cost"
  echo "duration_ms=$duration_ms"
  echo "answer_text=$answer_text"
  echo "status=$status"
}

# Extract a variable from parse_fixture output
get_parsed() {
  local var="$1"
  local output="$2"
  echo "$output" | grep "^${var}=" | head -1 | cut -d= -f2-
}
