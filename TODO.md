# claude-ask task list

Open work on claude-ask. Every item carries a priority, `(p1)` high, `(p2)`
normal or `(p3)` low, and a category: `[bug]`, `[feature]`, `[refactor]`,
`[docs]`, `[test]`, `[chore]` or `[perf]`.

Reviewed: 2026-11-03

## 8. Runs with several results

- [ ] **Denied tools are lost when a later result has none.** (p2) [bug] A run with a
  background agent has several `result` events, and `denied_tools` takes the last:
  denied in the first and none in the second prints no `not permitted` line (checked).
  Collect them over the whole answer.
- [ ] **Saved tokens are zero after a background agent.** (p2) [bug] The recorded run's
  results have 233, 143 and then 0 output tokens, and `SESSION_JQ` uses only the last,
  so `usage` saves as 0 (checked with a fixture of that shape). `process_stream_line`
  also takes a `0` as a value, so the final bar should show 0 too. Add them up over a
  turn's results, or ignore a result with no tokens. The cost is cumulative already,
  so it stays as it is: check that before adding anything else up.

## 9. Environments

- [x] **`--split` and `--popup` fail with an exported `SHELLOPTS` or `BASHOPTS`.** (p2)
  [bug] Both are readonly, so sourcing the environment file stops the new run with
  `SHELLOPTS: readonly variable` under `set -e` (checked). Leave them out of the file,
  with `UID`, `EUID` and `PPID`, and do not let a variable it cannot set end the run.
- [ ] **A dumb terminal gets cursor moves.** (p3) [bug] `TERM=dumb` turns colors off
  since 0.12.0, but the bar still redraws with `\eD`, `\e7` and `\e[J` (14 lines of them
  in a short run), which show as garbage in such a terminal. Treat it like stdout not
  being a terminal, with just the final bar.
- [ ] **`claude` and its tools get a changed locale.** (p3) [bug] The script exports
  `LC_NUMERIC=C` and moves `LC_ALL` to `LANG` for its own number formatting, and
  `claude` inherits that (checked: `LC_ALL` empty, `LC_NUMERIC=C`), so a command a tool
  runs formats numbers differently than in the user's shell. Restore the original
  values for the `claude` process only.
- [ ] **macOS is half supported and never run.** (p3) [test] The script has `pbcopy`, a
  `stat -f` fallback in `just smoke` and the bash check for it, but nothing runs there,
  and the tests use `setsid`, `touch -d` and `stat -c`. Add a macOS CI job with a
  newer bash, or state that it is Linux only and remove the pretence. Not tried: what
  fails there is unknown.

## 10. Small bugs and suggestions

- [ ] **A question of only digits makes a session its number hides.** (p3) [bug] Asking
  `5` saves `5.json`, and `--session 5`, `--resume=5` and `--delete 5` mean the fifth
  newest whenever there are five, so that session can only be reached by its number.
  `--delete --force` could remove the wrong one. Give such a slug a prefix (`q-5`).
- [ ] **`--version` says `unknown` for a copy of the script.** (p3) [bug] It reads
  `VERSION` beside `bin/`, though `--completions` was built to work from a copy alone
  (checked). Keep the version in the script as well, with a test that they match, or
  have `just lint` check it.
- [ ] **Binary piped input.** (p3) [bug] `head -c 200 /dev/urandom | claude-ask "q"` prints
  bash's `command substitution: ignored null byte` with a line number, and sends the
  rest as the question. Refuse input with NUL bytes, saying so, since a file was probably
  piped by mistake.
- [ ] **An interrupted answer cannot be yanked.** (p3) [feature] After Ctrl-C the text is
  on screen, but `/yank` says there is no answer, or copies the one before it without
  saying so. Keep the partial text for `/yank`, and say it is partial.
- [ ] **`/retry` in a chat.** (p3) [feature] After a failed or interrupted turn the
  question has to be fetched with the up arrow and sent again. `/retry` could ask the
  last question again, optionally with `/effort` or `/model` changed first.
- [ ] **`just uninstall`.** (p3) [chore] `just install` now writes up to three files beside
  the symlink, and nothing removes them. Remove what it would write, and the old
  session location is left alone.
- [ ] **GitHub releases from the tags.** (p3) [chore] There are 20-odd tags and no releases,
  so the changelog is only readable in the repository. A workflow on `v*` tags could
  publish that version's `CHANGELOG.md` section.
- [ ] **Keep CI's versions moving.** (p3) [chore] `actions/checkout@v7` and bats `v1.11.0` are
  fixed by hand. Dependabot for actions would notice new ones; pinning to a commit is
  stricter, if that is wanted for a small project.
- [ ] **Run the tests in parallel.** (p3) [test] The suite takes 1:30-3:30 one at a time. It
  isolates each test in a temp directory, and `bats --jobs` is available where GNU
  `parallel` is (it is here; CI would install it). Not tried: the pty and tmux tests have
  timing in them, so they may need to stay serial.

## Completed

### 7. Block rendering (completed 2026-11-03)

- [x] **Blocks render differently from the whole answer.** (p2) [bug] Compared with
  real `nvcat`, on one answer: a table that starts a block loses its top border (a
  blank row where `╭───┬───╮` should be) and gains two blank rows after it; a code
  block inside a list item loses its indent; and a nested bullet after a blank line
  gets the top-level marker (`◆`, not `◇`). `--no-stream` and `--session` render it
  whole and are right. For the border, try rendering with a line above the block and
  dropping it; for lists, do not end a block at a blank line when the next line is
  indented or a list item, which needs holding the blank until the next line comes.
- [x] **Many short blocks lag behind the answer.** (p2) [perf] Each block starts the
  renderer: 40 one-line paragraphs took 9.2s against 0.28s rendered whole (load
  average 7), while the event reader waits. Faster models can get ahead of that. When
  a render took long, put every block already complete into the next run, or set a
  minimum time between runs.

### 6. Repository (completed 2026-11-03)

- [x] **Show background agents on the info line.** (p3) [feature] A subagent can
  run in the background: its tool call gets a result at once, so the info line
  goes quiet while `system` events (`task_started`, `task_progress`,
  `task_notification`) report on it. Show its description until it finishes, as
  with a running tool. `test/fixtures/subagent.jsonl` has the flow, without those
  events, so record their fields again.
- [x] **Text from subagents is shown as the answer.** (p3) [bug] Events from a
  subagent (a `Task` tool call) carry `parent_tool_use_id`, which nothing checks,
  so if their text is in the stream it would be shown and saved as part of the
  answer. Not checked against a real subagent run: record one, and skip events
  with that field if so. They could go on the info line instead.
- [x] **A chunk ending exactly at the terminal width loses its last character
  on screen.** (p3) [bug] The cursor there is "pending wrap", which moving it
  clears, so the next text overwrites the last cell: 59 `x` and `Z` in 60 columns
  followed by `TAIL` shows `x...xTAIL`. Only the screen is affected, not the saved
  answer, and the column-counting code before 0.9.0 did it too. It matters more
  once partial messages make chunks end mid-line. Telling needs the column: count
  display width only to detect this case, and move to the next row first.
- [x] **Lines typed ahead during an answer merge into one question.** (p3) [bug]
  Two lines typed while an answer streams are waiting at the next prompt, so
  they look like a paste. Flushing typed-ahead input before the prompt would
  fix it, at the cost of losing a line typed ahead on purpose.
- [x] **No colors but truecolor.** (p3) [feature] Since 0.9.0 `NO_COLOR` is
  honored, but the palette is 24-bit only, which a 256-color terminal shows
  wrongly. Fall back on `COLORTERM`.
- [x] **Test older tool versions in CI.** (p3) [chore] jq 1.7 already broke
  saving (0.6.2). Add `ubuntu-22.04` (jq
  1.6, bash 5.1, an older tmux) to the matrix, or state the minimum versions in
  the README. `launch_in_tmux` assumes `display-popup -e` and does not check.
- [x] **A smoke test against the real `claude`.** (p3) [test] Every test replays
  fixtures, so a change in the stream format would go unnoticed, and the `-r` and
  partial-message items above need the real thing. Add `just smoke`, not in CI,
  that asks one cheap question with haiku and checks parsing, saving and resume.
- [x] **`just lint` skips the stubs and helpers.** (p3) [chore] It checks only
  the script and the bash completion; `shellcheck` reports 12 findings in
  `test/stubs/*` and `test/test_helper.bash`. Fix them and add those files.
- [x] **`bc` is only used by one test.** (p3) [chore] The script stopped needing
  it, but `test/mock_stream.bats:81` still calls it, so CI installs it. Compare
  with `awk` or `jq` and drop it from `ci.yml`.
- [x] **One helper for the session file list.** (p3) [refactor] `ls -t
  "$dir"/*.json` is written out in `newest_session_file`, `show_history` and
  `find_session`; the themes are listed in two regexes, `CHAT_THEMES`,
  `run_theme_demo` and the completions; the model aliases in `chat_help`,
  `CHAT_MODEL_ALIASES` and the completions. Keep one of each. The drift test
  checks only option names, so extend it to the values.
- [x] **Small doc fixes.** (p3) [docs] CLAUDE.md's list of slash commands lacks
  `/yank` and `/quit`, and has no word on `/editor`. In `bin/claude-ask`, the
  comment about the question file (line 369) now sits above the
  `_CLAUDE_ASK_STARTED` block instead of the code it describes.

### 5. Options and tmux (completed 2026-11-03)

- [x] **`--split` and `--popup` lose the shell's environment.** (p3) [bug]
  tmux runs them with the server's environment, and `launch_in_tmux` passes on
  only `PATH`, `SESSION_DIR`, `XDG_STATE_HOME`, `XDG_RUNTIME_DIR`, `EDITOR` and
  `CLAUDE_ASK_*`. So `ANTHROPIC_API_KEY`, `CLAUDE_CONFIG_DIR`, `HTTPS_PROXY`,
  `LESS` and the like set in this shell are not seen, and could mean another
  account. Do not just add them with `-e`, which puts a key in the process list:
  write them to a private file the new run reads and deletes, like the question.
- [x] **`EDITOR` with arguments fails.** (p3) [bug] `compose_in_editor` runs
  `"${EDITOR:-vi}" "$f"`, so `EDITOR="code --wait"` gives "No such file or
  directory" and `\e` just returns to the prompt. Run it with `bash -c` as git
  does, and try `VISUAL` first.
- [x] **No `--theme=X`, `--effort=X`, `--model=X`, or `-ir`.** (p3) [bug] All are
  "Unknown option", though `--split=`, `--resume=` and `--debug-log=` take that
  form. Accept `=` for every option with a value and split bundled short flags,
  and add them to both completion files.
- [x] **Pass options through to `claude`.** (p3) [feature] Nothing reaches
  `claude` except `--effort`, `--model` and `--resume`, so a chat cannot use
  `--allowedTools`, `--permission-mode`, `--add-dir` or
  `--append-system-prompt`. Add `CLAUDE_ASK_ARGS` or a repeatable
  `--claude-arg`, saved with the session so `-r` keeps it.
- [x] **Yank over ssh with OSC 52.** (p3) [feature] Over ssh with no `DISPLAY`
  there is no clipboard command, so outside tmux `-y` fails. Fall back to the
  OSC 52 escape, which most terminals and tmux pass to the local clipboard, and
  add `clip.exe` for WSL.
- [x] **Check the bash version.** (p3) [bug] The shebang is `#!/bin/bash`, which
  is 3.2 on macOS even with a newer bash installed, and nothing checks
  `BASH_VERSINFO`, so it fails with confusing errors (`mapfile`, `coproc`,
  `EPOCHREALTIME`), although `pbcopy` suggests macOS is meant to work. Use
  `#!/usr/bin/env bash` and exit with a clear message below 5.

### 4. Sessions and chat history (completed 2026-11-03)

- [x] **Script source lines end up in the chat history.** (p2) [bug]
  `chat_loop` runs `set -o history` and never turns it off, so bash records
  the rest of the script as it reads it: after a chat the history file ends
  with `if [[ "$LAST_TURN_STATUS" -ne 0 ]]; then exit 1; fi` and `exit 0`, and
  the up arrow offers them. Run `set +o history` when the chat ends, add a test,
  and remove the lines already in `~/.local/state/claude-ask/history`.
- [x] **Session files are readable by other users.** (p2) [bug] Sessions hold
  questions, piped diffs and answers, but are created with the umask (`0664`
  here, in a `0775` directory), unlike the chat history (`0600`). Create the
  directory `0700` and the files `0600` (`umask 077` around `save_session`,
  including `--save-raw`), and tighten existing ones when they are next written.
- [x] **A corrupt session file gives a poor error.** (p3) [bug]
  `--session bad` prints jq's parse error and exits 0; `--resume=bad` says "has
  no session id and cannot be resumed". Check that the file parses and report
  "NAME is not a valid session file", exit 1.
- [x] **`--session` opens the pager once per turn.** (p3) [bug] `show_turn` runs
  the pager for each turn, so a 3-turn session runs it 3 times (counted) and
  with the default `nvcat --pager less` needs `q` once per turn. Render all
  turns as one document for one pager.
- [x] **Multi-line questions come back split from the history file.** (p3) [bug]
  A pasted question is one entry during the chat, but the file holds its lines
  separately, so next time each is its own up-arrow entry. Bash has no format
  for this without timestamps: `HISTTIMEFORMAT` with `lithist`, or store them
  joined.
- [x] **The session directory ignores `XDG_DATA_HOME`.** (p3) [bug] `STATE_DIR`
  honors `XDG_STATE_HOME`, but `SESSION_DIR` is always under
  `~/.local/share/claude/`, inside a directory named after another tool. Use
  `${XDG_DATA_HOME:-~/.local/share}/claude-ask/sessions`, falling back to the old
  place when it holds sessions; the completion files glob it too.
- [x] **Search and prune sessions.** (p3) [feature] Sessions pile up with no way
  to find or remove them: `--history` lists all of them. Add a limit
  (`--history=N`), a search over questions and answers, and `--delete ID|N` or
  an age-based prune.
- [x] **`--history` does not fit the terminal.** (p3) [bug] The table has fixed
  widths of about 90 columns, wrapping in a narrow pane, and counts characters,
  so 39 double-width characters take 78 columns and push the row out of line.
  Use `TERM_COLS` and display width; `disp_name` also hides what makes long names
  differ.

### 3. Input and output (completed 2026-11-03)

- [x] **Piped input with `-i` asks one paid question per line.** (p2) [bug]
  `printf 'a\nb\nc\n' | claude-ask -i` makes 3 `claude` calls, and
  `git diff | claude-ask -i "review"` asks `review` and then every line of the
  diff as its own question. `chat_loop` reads the pipe as typed input (meant
  for `CLAUDE_ASK_FORCE_INTERACTIVE`, the tests). Read the pipe as the question
  or its context, then chat on `/dev/tty`; with no terminal, refuse `-i`.
- [x] **Piped input is dropped when a question is given.** (p2) [bug]
  `echo DATA | claude-ask "summarize"` sends only `summarize`, with no warning;
  `git diff | claude-ask "review this"` is the obvious way to use it. Send the
  question followed by the piped text, keeping `--split` and `--popup` working
  (the question file already handles the size).
- [x] **Output to a file or pipe is full of escape codes.** (p2) [bug]
  `claude-ask q > out` writes cursor moves, colors and every status bar redraw
  to the file (14 of its lines in a one-line answer, 2249 bytes), since nothing
  checks `-t 1`. So `claude-ask q | grep x` and `$(claude-ask q)` are unusable.
  When stdout is not a terminal print only the answer, with the status bar on
  stderr if that is a terminal. Honor `NO_COLOR` at the same time (no support
  today), and consider 256-color fallbacks: the palette is truecolor only.
- [x] **Text after a wrapped line or wide characters lands in the wrong
  place.** (p2) [bug] `emit_text` counts characters into `CURSOR_COL`, and
  `update_status_bar` restores that column with `\e[%dG`. On a real screen
  (`tmux capture-pane`, 60 columns) a 130-character chunk followed by `TAIL`
  shows `T` at column 60 and `AIL` on the next row, and `日本語日本語` followed
  by `TAIL` shows `日本語TAIL`: the text is overwritten. Pager output with
  color codes is counted the same way. Save and restore the cursor (`\e7`,
  `\e8`, or `\e[s`, `\e[u`) instead of computing a column, watching for
  scrolling, or count display width modulo `TERM_COLS`.
- [x] **Messages of one answer run together.** (p2) [bug] With a tool call
  between two assistant messages, the answer shows
  `Let me check that.The answer is 42.`: `process_stream_line` appends each
  message's text with nothing between them, which also breaks Markdown. Add a
  blank line between messages. The saved `answer`, `/yank` and `--session`
  keep only the `result` text (the last message), unlike what was shown; decide
  whether that is what they should hold.
- [x] **Answers can send escape sequences to the terminal.** (p2) [bug] A text
  block holding `\u001b]52;c;...` reaches stdout as it is with `--no-pager` or
  no `nvcat` (checked), so a page a tool fetched could set the clipboard or the
  window title; `less -R` and session replay need checking too. Strip control
  characters except newline and tab from the answer, and from questions shown
  by `--history` and `--session`.
- [x] **A paste that arrives in pieces becomes several questions.** (p2) [bug]
  `chat_loop` gathers only lines already waiting (`read -t 0`), so two lines 50ms
  apart make 2 `claude` calls, which is likely over ssh or a slow tmux
  `paste-buffer` (one 300-line write is fine). Wait a short time, say 30ms, before
  deciding nothing more is coming. The reverse also happens: two lines typed
  ahead while an answer streams are merged into one question.
- [x] **Real streaming with `--include-partial-messages`.** (p2) [feature]
  `claude` emits whole messages unless given that option, which the script does
  not pass, so a long answer appears all at once when its message is done and
  the status bar sits still until then. Pass it and parse the `stream_event`
  text deltas, without printing the final `assistant` message again. Far more
  chunks would end mid-line, so see the exact-width item below.
- [x] **Show what `claude` is doing during tool calls.** (p3) [feature]
  `tool_use` blocks are ignored (`Bash` never appears in the output), so a long
  tool run looks like a hung spinner. Put the tool's name in the info line, as
  `thinking...` is now, and show denied tools: in `-p` mode these fail quietly.

### 2. CI (completed 2026-11-03)

- [x] **The real-tmux popup tests fail on CI.** (p1) [test] All four tests in
  `test/tmux_popup.bats` fail on the 0.8.2 run (41735238717, tmux 3.4), each
  about 11s, so an `expect` step timing out; the rest of the suite passes. They
  pass here on tmux next-3.9 and on Ubuntu's 3.5a, also with a minimal
  environment and no terminal on stdin, so it is either tmux 3.4 or the runner.
  Which step fails is unknown because a failing test prints nothing: first make
  `in_tmux` print the screen on failure. Until then it is not known whether
  `--popup` itself works on tmux 3.4.

### 1. claude-ask (completed 2026-11-03)

- [x] **Make `just lint` pass.** (p2) [chore] shellcheck reports 10 warnings
  (9 SC2034 unused variables such as `BG_CONTEXT` and `cache_read_tokens`, one
  SC2120 on `show_history`) and 10 infos in `bin/claude-ask`. Remove the dead
  variables or mark the deliberate ones, then add lint to CI or a pre-commit.
- [x] **Temp files in a private directory.** (p3) [bug] The debug log defaults
  to `/tmp/claude-ask.log` and the FIFOs and raw stream use fixed `/tmp`
  prefixes (`bin/claude-ask` around lines 127, 682, 1078, 1141), readable by
  other users and ignoring `$TMPDIR`. Use `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}`
  and `mktemp -d` once per run.
- [x] **Default pager depends on a personal colorscheme.** (p3) [bug]
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
- [x] **Run lint and tests in CI.** (p3) [chore] `just lint` and `just test`
  pass now but nothing runs them. Add a GitHub Actions workflow (shellcheck,
  bats and jq are all in the Ubuntu image or apt; `bc` is no longer needed)
  or a pre-commit hook. The suite needs bash 5 and takes about 35s.
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
- [x] **One `jq` process per stream event.** (p3) [perf] Since the status bar
  redraw stopped forking, the per-event `jq` call in `process_stream_line` is
  nearly all of the remaining time (about 16ms an event; 4.8s of 5.2s for 300
  events). Run one long-lived `jq --unbuffered` over the whole stream (a
  coprocess fed each line, or reading claude's output directly and emitting the
  NUL-separated fields) and read its records instead of starting `jq` per line.
- [x] **Resume or chat in a chosen session, not only the newest.** (p3)
  [feature] `-r` always takes the newest session file. Let `--session ID|N`
  combine with `-r` or `-i` (or give `-r` an optional `ID|N`) to continue an
  older conversation, reusing `view_session`'s lookup by index, name and prefix.
- [x] **The chat prompt cannot take a multi-line paste.** (p3) [feature]
  Pasting several lines at the `> ` prompt sends each line as its own question.
  Bracketed paste does not help: it is already on by default (readline 8.1+),
  and a test under a pseudo-terminal shows `read -e` still returns at the
  first pasted newline (`line one`, with `line two` left for the next read).
  After `read` returns, gather any input already waiting (`read -t 0`, then
  short-timeout reads) into the same question, since typed lines never arrive
  that fast; or document `\e` / `/editor` for multi-line questions.
- [x] **A status bar wider than the terminal breaks the redraw.** (p2) [bug]
  `update_status_bar` moves back up with `\e[3A`, which assumes the bar and
  the info line each take one row. In a narrow pane (a tmux split under about
  75 columns), the powerline bar with tokens, cost, duration and now an
  effort level wraps, so each redraw lands one row lower and leaves copies of
  the bar behind. Cut the bar and info line to the terminal width (count
  visible characters without the escapes), or drop segments from the right,
  and test it at a small `COLUMNS`.
- [x] **An unknown `/model` fails every turn after it.** (p3) [bug] `claude`
  answers `--model nosuchmodel` with an error result ("There's an issue with
  the selected model ... Run --model to pick a different model") and exit 1;
  `claude-ask` prints that, but `MODEL` stays set, so every later question
  fails the same way until `/model default`. On an `assistant` event with
  `error: "model_not_found"`, restore the previous model and say so, or at
  least hint at `/model` in the chat.
- [x] **The chat prompt does not show the model or effort.** (p3) [feature]
  The status bar appears only while an answer streams, so after `/effort` or
  `/model` nothing on screen shows the current setting until the next answer.
  Put a short form in the prompt (`opus 5.5 · high > `), dim, or print it
  after each change (already done) and at chat start next to the `/help`
  hint.
- [x] **Tab completion for chat commands.** (p3) [feature] Since 0.7.0 Tab
  at the chat prompt inserts a tab (`chat_inputrc`), so a Tab in pasted code
  is kept now that bracketed paste is off; completion needs another key.
  Bind one (say `M-/` or a second Tab press) to complete the `/word`
  commands and their arguments (effort levels, themes, model aliases), if a
  non-interactive `read -e` can run it (`bind -x` does not take effect in a
  script; a readline macro in the INPUTRC file might), or note that it
  cannot.
- [x] **Shell completion for the options.** (p3) [feature] No bash or zsh
  completion for `--theme`, `-e`, `-m`, `--session` (session names) and the
  rest. Add `completions/_claude-ask` (zsh) and a bash one, installed by
  `just install`.
- [x] **`--history` starts two `jq` processes per session file.** (p3) [perf]
  `show_history` runs one `jq` for the fields and `format_time_ago` another
  (in a command substitution) for the timestamp, so a few hundred sessions
  take seconds. Compute the age in the first `jq` (`now - (.timestamp |
  fromdateiso8601)`), or read every file in one `jq` call.
- [x] **The pager plumbing is still named after `bat`.** (p3) [refactor]
  `BAT_PID`, `BAT_FIFO`, `BAT_OUT_FD` and `drain_bat` (`bin/claude-ask`
  around lines 1385 and 1432-1474) date from when the pager was `bat`; it is
  now any `PAGER_CMD`. Rename them `PAGER_*` and `drain_pager`.
- [x] **`--popup` is only tested against the tmux stub.** (p3) [test]
  `display-popup` needs an attached client, so the smoke test on a private
  tmux server (`tmux -L`) covered `--split` but not the popup: the paging
  after the answer, `-+F` with a `LESS` that has `-F`, and the popup closing
  on quit or `/quit`. Check it by hand, or drive an attached client in a
  test (a `script`-run `tmux attach` on the private server).
- [x] **Ctrl-C at the chat prompt drops the line only at Enter.** (p3)
  [bug] The SIGINT trap sets `TURN_INTERRUPTED`, but a trapped signal does
  not interrupt `read -e`, so `abc` Ctrl-C shows `^C` and keeps reading:
  what is typed next is added to `abc`, and the whole line is dropped only
  when Enter is pressed (0.7.0 does the same). Make Ctrl-C end the read at
  once (no trap while reading, so readline's own SIGINT handling clears the
  line, or `bind -x` on `\C-c` emptying `READLINE_LINE`), and add a pty test.
