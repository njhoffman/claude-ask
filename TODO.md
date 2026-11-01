# claude-ask task list

Open work on claude-ask. Every item carries a priority, `(p1)` high, `(p2)`
normal or `(p3)` low, and a category: `[bug]`, `[feature]`, `[refactor]`,
`[docs]`, `[test]`, `[chore]` or `[perf]`.

Reviewed: 2026-10-31

## 1. claude-ask

- [x] **Make `just lint` pass.** (p2) [chore] shellcheck reports 10 warnings
  (9 SC2034 unused variables such as `BG_CONTEXT` and `cache_read_tokens`, one
  SC2120 on `show_history`) and 10 infos in `bin/claude-ask`. Remove the dead
  variables or mark the deliberate ones, then add lint to CI or a pre-commit.
- [x] **Temp files in a private directory.** (p3) [bug] The debug log defaults
  to `/tmp/claude-ask.log` and the FIFOs and raw stream use fixed `/tmp`
  prefixes (`bin/claude-ask` around lines 127, 682, 1078, 1141), readable by
  other users and ignoring `$TMPDIR`. Use `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}`
  and `mktemp -d` once per run.
- [ ] **Default pager depends on a personal colorscheme.** (p3) [bug]
  `PAGER_CMD` runs `nvimpager` with `colorscheme nord-nick`; on a host without
  nvimpager or that colorscheme the answer does not render. Fall back to the
  commented-out `bat` command when `nvimpager` is missing, or make it a config
  value.
- [x] **A `--version` flag.** (p3) [feature] Print the `VERSION` file's value.
- [x] **`PAGER_CMD` is word-split, so quoted arguments break.** (p2) [bug]
  `$PAGER_CMD` is expanded unquoted (`bin/claude-ask` lines 684, 774, 973,
  1082, 1270); bash does not re-parse quotes, so the default
  `-c "colorscheme nord-nick | ..."` reaches nvimpager as the separate words
  `"colorscheme`, `nord-nick`, `|`, ... and any `--pager` value with quotes
  breaks the same way. Run it with `bash -c "$PAGER_CMD"` (or `eval`), and add
  a test that a quoted `--pager` argument arrives intact.
- [x] **Tests call the real `claude` binary.** (p2) [test] Four tests in
  `test/cli_args.bats` (editor-question and the three `--theme` cases) run the
  full script with `timeout 2`, which starts `claude -p "test"` (a real API
  request) and the real pager, against the real `SESSION_DIR`; this also makes
  the suite slow (over two minutes). Put a stub `claude` first on `PATH` and
  set `SESSION_DIR` to `$TEST_TEMP_DIR` in `setup`. Also, "--debug-log defaults
  to /tmp/claude-ask.log" only checks that `DEBUG_LOG` is empty and never
  tests the default.
- [x] **The stream parse loop exists three times.** (p2) [refactor] The main
  loop (`bin/claude-ask` ~1155-1252), `run_demo_output` (~695-757) and
  `parse_fixture` in `test/test_helper.bash` each carry their own copy, and they
  have already drifted (the test copy has no thinking or metrics handling), so
  the json_parsing tests exercise the helper, not the script. Extract one
  `process_stream_line` function above the sourcing guard and call it from all
  three.
- [x] **Errors from `claude` are swallowed.** (p2) [bug] `claude` runs with
  `2> /dev/null` and its exit status is ignored (line 1252); a missing binary,
  expired auth or a `result` event with `is_error: true` ends with an empty
  answer under a "done" status bar and no message. Check for `claude`, `jq` and
  `bc` up front, capture stderr to the temp dir and print it on failure, and
  exit non-zero.
- [x] **Docs say the status bar is pinned to the top row.** (p3) [docs]
  README, CLAUDE.md and the 0.1.0 CHANGELOG entry say so, but
  `update_status_bar` draws it below the streamed content.
- [x] **Powerline separators assume every segment is present.** (p3) [bug]
  `render_powerline` computes `prev_bg` and never uses it: the cost separator
  is always drawn in the tokens color and the duration separator in the cost
  color, so a bar without tokens or cost shows mismatched arrows. Track the
  previous segment's color and use it for each separator; add theme tests for
  the partial cases.
- [x] **`--save-raw` sessions break `--history` and `--session`.** (p3) [bug]
  Raw sessions are JSONL saved as `.json`; `show_history` and `view_session`
  run single-object jq queries on them, giving one result per line (garbled
  line counts, an empty answer). Save raw as `.jsonl` alongside the parsed
  `.json`, or teach the readers to detect JSONL.
- [x] **A question with no ASCII letters saves an invisible session.** (p3)
  [bug] `slugify_question` returns an empty slug for e.g. a CJK-only question,
  so the file is `SESSION_DIR/.json`, which `ls *.json` in `--history` skips.
  Fall back to the session id or a timestamp when the slug is empty.
- [x] **Questions starting with `-` reach `claude` as options.** (p3) [bug]
  `claude ... -p "$question"` passes a question like `-v explain this` as a
  flag. Use `-p -- "$question"` (and check `claude` accepts `--` there).
- [x] **Only `content[0]` of each assistant event is read.** (p3) [bug] A
  message carrying more than one block (thinking plus text, or a tool use
  before the text) loses the later blocks. Iterate `.message.content[]`.
- [x] **Up to eight `jq` processes per stream line.** (p3) [perf] Each event
  forks `jq` once per field. One `jq -r` call per line emitting all fields
  (`@tsv` or NUL-separated) would cut this; it fits naturally into the shared
  parse function above.
- [x] **Number formatting depends on locale and GNU date.** (p3) [bug]
  `printf '%.4f'` on `bc` output fails under a comma-decimal `LC_NUMERIC`
  (e.g. `de_DE.UTF-8`); `format_time_ago` and `debug_log` use GNU-only `date -d`
  and `%3N`. Set `LC_NUMERIC=C` at the top; note GNU date as a requirement or
  add a fallback.
- [x] **`--debug-log` swallows the question.** (p2) [bug] The flag takes an
  optional file argument, so `claude-ask --debug-log "What is 2+2?"` (the
  header's own example, line 29) logs to a file named `What is 2+2?` and opens
  the editor. Take the file only as `--debug-log=FILE` (bare `--debug-log`
  uses the default), and fix the example.
- [ ] **Run lint and tests in CI.** (p3) [chore] `just lint` and `just test`
  pass now but nothing runs them. Add a GitHub Actions workflow (shellcheck,
  bats, jq and bc are all in the Ubuntu image or apt) or a pre-commit hook.
- [x] **`--demo-output` tests are slow.** (p3) [test] `generate_mock_stream`
  sleeps 0.03s per chunk and `test/demo_output.bats` runs the full demo
  (six streams) in each of its tests. Make the demo delay an environment
  value the tests set to 0.
- [x] **Status bar updates can stall on a partial pager line.** (p3)
  [bug] `drain_bat` checks `read -t 0` and then does a blocking `read -r`, so
  when the pager has printed part of a line without its newline the status
  bar update waits for the rest. Read with a short timeout instead.
- [x] **Each status bar redraw forks a dozen processes.** (p3) [perf]
  `refresh_status_bar` runs `format_tokens`, `format_cost` and
  `format_duration` in command substitutions (several calling `bc`), and
  `update_status_bar` renders the bar and the info line in two more; a
  `--demo-output` run with no delay still takes about 4s. Do the formatting
  with bash integer arithmetic and `printf -v` instead of `bc` and subshells.
- [ ] **One `jq` process per stream event.** (p3) [perf] Since the status bar
  redraw stopped forking, the per-event `jq` call in `process_stream_line` is
  nearly all of the remaining time (about 16ms an event; 4.8s of 5.2s for 300
  events). Run one long-lived `jq --unbuffered` over the whole stream (a
  coprocess fed each line, or reading claude's output directly and emitting the
  NUL-separated fields) and read its records instead of starting `jq` per line.
