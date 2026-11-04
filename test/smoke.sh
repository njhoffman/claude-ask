#!/usr/bin/env bash
# A smoke test against the real claude, which the tests replay fixtures in place
# of: `just smoke`. It makes three haiku requests, about a cent, and leaves
# throwaway sessions under ~/.claude/projects. Sessions go to a temp directory.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="${CLAUDE_ASK_SMOKE_SCRIPT:-$root/bin/claude-ask}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export SESSION_DIR="$work/sessions" XDG_STATE_HOME="$work/state"
unset CLAUDE_ASK_ARGS CLAUDE_ASK_MODEL CLAUDE_ASK_EFFORT
failed=0

check() {
  local what="$1"
  shift
  if "$@"; then
    printf 'ok    %s\n' "$what"
  else
    printf 'FAIL  %s\n' "$what"
    failed=1
  fi
}

ask() {
  # stdin closed, or a piped-input read could wait on an inherited one
  "$script" -m haiku --no-pager "$@" < /dev/null
}

has() { [[ "$1" == *"$2"* ]]; }
no_escapes() { [[ "$1" != *$'\e'* ]]; }
saved_is() { jq -e --argjson result "$result" "$1" "$file" > /dev/null; }

printf 'asking (1 of 3)...\n'
first=$(ask --save-raw "Reply with exactly this word and nothing else: pineapple" 2> "$work/err1") || {
  cat "$work/err1" >&2
  check "a first answer" false
}
check "the answer is on stdout" has "${first,,}" pineapple
check "stdout has no escape codes" no_escapes "$first"

# shellcheck disable=SC2012 # session names are slugs
file=$(ls -t "$SESSION_DIR"/*.json 2> /dev/null | head -1 || true)
check "a session file was saved" test -n "$file"
if [[ -n "$file" ]]; then
  check "it holds the answer" has "$(jq -r '.answer // "" | ascii_downcase' "$file")" pineapple
  check "it has a session id" test -n "$(jq -r '.session_id // ""' "$file")"
  check "it has the model" has "$(jq -r '.model // ""' "$file")" haiku
  check "it has the cost" test -n "$(jq -r '.cost_usd // ""' "$file")"
  check "it is private" test "$(stat -c %a "$file")" = 600
  raw="${file%.json}.jsonl"
  check "text came as partial messages" grep -q '"text_delta"' "$raw"
fi

printf 'resuming (2 of 3)...\n'
second=$(ask --save-raw -r "Which word did I ask you to reply with? Reply with only that word." 2> "$work/err2") || {
  cat "$work/err2" >&2
  check "a resumed answer" false
}
check "resuming carries the conversation" has "${second,,}" pineapple
if [[ -n "$file" ]]; then
  check "the turn joined the same file" test "$(jq -r '.turn_count // 0' "$file")" = 2
fi

printf 'through a file, from another directory (3 of 3)...\n'
(cd "$work" && ask --save-raw -r "Reply with exactly: done" > "$work/out" 2> "$work/err3") || cat "$work/err3" >&2
check "the answer went to the file" has "$(tr '[:upper:]' '[:lower:]' < "$work/out")" "done"
check "the file has no escape codes" no_escapes "$(cat "$work/out")"

# claude reports running totals: what was saved must add up to the last of them
if [[ -n "$file" ]]; then
  result=$(jq -c 'select(.type == "result")' "${file%.json}.jsonl" | tail -1)
  # shellcheck disable=SC2016 # jq programs
  check "the saved cost is claude's last total" saved_is \
    '(.cost_usd - $result.total_cost_usd) | fabs < 0.000001'
  # shellcheck disable=SC2016 # jq programs
  check "the saved tokens are claude's last total" saved_is \
    '.usage.output_tokens == ($result.modelUsage | map_values(.outputTokens) | add)'
  printf 'cost: $%s\n' "$(jq -r '.cost_usd // "?"' "$file")"
fi
if ((failed)); then
  printf 'smoke test FAILED\n' >&2
  exit 1
fi
printf 'smoke test passed\n'
