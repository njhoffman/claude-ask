# Changelog

All notable changes to claude-ask are recorded here, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, with
[semantic versioning](https://semver.org/).

## [Unreleased]

## [0.15.4] - 2026-11-03

### Fixed

- A resumed conversation's cost, tokens and API time are no longer overstated. `claude`
  reports running totals, which were saved as each turn's own and added up (three
  turns costing $0.0072 showed $0.0204; wrong for cost since 0.4.0, and for tokens
  since 0.15.3). Each turn now saves what it added, and the bar shows that.

## [0.15.3] - 2026-11-03

### Changed

- `--help` fits the terminal: long descriptions wrap under their own column, not
  under the options. To a pipe its lines stay whole, unless `CLAUDE_ASK_COLUMNS` is set.
- `TERM=dumb` gets no status bar redraws or other cursor moves, just the final bar.

### Fixed

- A run with a background agent, which has several results, is saved and shown
  properly: tokens are the whole run's, with the subagent's, not the last result's
  (often 0); the duration is the whole run's, not the last result's (a few
  milliseconds); and denied tools from any result are named.
- `claude`, its tools and `--split` and `--popup` get the user's own locale, not the
  `LC_NUMERIC=C` this script uses for its own numbers.
- `--version` works for a copy of the script.
- With no controlling terminal, as under cron, no `/dev/tty` error is printed.

## [0.15.2] - 2026-11-03

### Fixed

- Text rendered while streaming matches the whole answer rendered at once: a table
  keeps its top border and no longer gets blank rows after it, and a list stays
  together through its blank lines, keeping the indent of code in it and its nesting.
- Many short paragraphs no longer lag behind the answer: after a pager run, blocks
  that finish meanwhile wait up to twice its time and go through together (40
  paragraphs arriving at once: 9.2s before, 0.5s now, with `nvcat`).
- `--split` and `--popup` work with `SHELLOPTS` or `BASHOPTS` exported.
- `--help` lines up its columns, gives each option one line, and no longer colors the
  first letter of a description.

## [0.15.1] - 2026-11-03

### Fixed

- `--popup` works on tmux 3.2, whose `display-popup` has no `-e` and takes one
  command: tmux now gets one command for both `--popup` and `--split`.
- `--claude-arg` and `CLAUDE_ASK_ARGS` are saved properly with jq 1.6.

### Changed

- CI also runs the tests on Ubuntu 22.04 (jq 1.6, bash 5.1, tmux 3.2, fish 3.3).

## [0.15.0] - 2026-11-03

### Added

- `--help` is in color at a terminal. `NO_COLOR` and a pipe give it plain.
- Agents running in the background show on the info line (`agent: Look at logs`)
  until they finish, and the status stays running while they do.
- `just smoke` tries the real `claude` with three haiku requests, a few cents.

### Changed

- `just lint` also checks the test stubs and helpers, and CI no longer installs `bc`.

## [0.14.0] - 2026-11-03

### Added

- `--completions bash|zsh|fish` prints a completion script, with fish new. It works
  from the script alone, needing neither the repository nor `jq`.

### Changed

- The completion scripts are inside `bin/claude-ask`, and `completions/` is gone.
  `just install` writes them from the script instead of linking them. Symlinks an
  earlier install left point at nothing now: run `just install` again.
- zsh's script can also be sourced (`source <(claude-ask --completions zsh)`).

## [0.13.0] - 2026-11-03

### Changed

- Lines typed while an answer streams wait at the next prompt, editable and
  joined with `⏎`, until Enter. Before, several of them were asked at once as one
  question.

### Fixed

- Below bash 5 the script stops with a clear message, and it now finds bash on
  `PATH` (`#!/usr/bin/env bash`), where `/bin/bash` is 3.2 on macOS.
- A subagent's own text is not taken for the answer.
- A run with a background agent has several results: the bar goes back to running
  when more follows, instead of showing done while text still arrives.
- The OSC 52 tests set `TERM` (`TERM=dumb` failed CI for 0.12.0).

## [0.12.0] - 2026-11-03

### Added

- `--search TEXT` lists sessions with TEXT in a question or an answer, keeping
  their `--history` numbers, and `--history=N` lists the newest N.
- `--delete ID|N` and `--prune AGE` delete sessions. Both list what they would
  remove and ask first; with no terminal they need `--force`.
- `--claude-arg WORD` and `CLAUDE_ASK_ARGS` pass options on to `claude`. They are
  saved with the session, and `-r` uses them again and says which.
- Yanking with no clipboard command and no tmux asks the terminal (OSC 52), which
  reaches the local clipboard over ssh; `clip.exe` is used on WSL.
- `CLAUDE_ASK_COLORS` chooses `truecolor`, `256`, `16` or `none`.

### Changed

- Colors follow `COLORTERM` and `TERM`: a terminal not known to take 24-bit color
  gets 256 or 16 colors. Over ssh, where `COLORTERM` is often not passed on, that
  can mean 256; set `CLAUDE_ASK_COLORS=truecolor` to keep 24-bit.
- Inside tmux a yank uses `load-buffer -w`, so tmux also sends it to the outer
  terminal's clipboard.

## [0.11.0] - 2026-11-03

### Changed

- Answers really stream. `claude` is asked for partial messages, so with
  `--no-pager`, or stdout going to a file or pipe, text appears word by word.
- With a pager, each finished block (a paragraph, a list, a whole code block) is
  rendered as it completes. Before, the default `nvcat` showed nothing until the
  whole answer had arrived. Text before a tool call shows before the tool runs.
- The status bar redraws about ten times a second while words arrive, and is only
  cleared when text reaches it, so it does not flicker.

### Fixed

- A chunk ending exactly at the terminal width no longer loses its last character
  on screen.
- The `--session` test that fits the screen sets `TERM`: `less` stops to warn
  without one, which failed CI for 0.10.0 (the popup tests all pass on tmux 3.4).

## [0.10.0] - 2026-11-03

### Changed

- Sessions moved to `${XDG_DATA_HOME:-~/.local/share}/claude-ask/sessions`. Those
  in `~/.local/share/claude/cli-sessions` move there once, on the first run,
  unless `SESSION_DIR` is set. A chat open during the move cannot save its next
  turn, so end open chats first.
- `--split` and `--popup` pass on everything exported in the shell (except what
  belongs to the new pane, such as `TMUX` and `TERM`), in a private file, not
  only `CLAUDE_ASK_*` and a few others on tmux's command line where `ps` showed
  them. So `ANTHROPIC_API_KEY`, `CLAUDE_CONFIG_DIR` and proxy settings now apply.
- `--session` with several turns uses one pager over them all, not one per turn.
- `--history` fits the terminal, dropping the name column when very narrow, and
  keeps its columns in line with double-width characters.

### Added

- While a tool runs, the info line shows it (`Bash: git status`), and tools
  `claude` was not permitted to use are named after the answer.
- Options with a value take `--option=VALUE` (`--theme`, `--effort`, `--model`,
  `--pager`, `--session`), short flags can be bundled (`-ir`, `-ie high`), and both
  completion files know the `=` forms.

### Fixed

- `EDITOR` can hold arguments (`code --wait`), and `VISUAL` comes first.
- A session file that is not valid is reported as such, with status 1, by
  `--session`, `--resume=` and `-y`, instead of a jq error and status 0.
- A multi-line question recalled from the history is asked whole. It is stored
  on one line, with `⏎` for each line break, and shown that way at the prompt.
- `--effort=` and `--pager=` with no value are errors.
- The `--popup` test with `LESS=-F` no longer types keys at `less`, which failed
  CI for 0.9.0 (on tmux 3.4 the other popup tests passed: `--popup` works there).

## [0.9.0] - 2026-11-03

### Changed

- When stdout is not a terminal it gets only the answer, ending in a newline:
  no status bar, cursor moves or colors, and no default pager (a `--pager` you
  give still runs). The status bar goes to stderr if that is a terminal. `-r`
  does not replay the last answer into a file.
- Piped input is added after a question given on the command line, instead of
  being ignored. A stdin that does not end is waited for, with a note after 2s
  (`< /dev/null` skips it).
- `-i` with piped input asks one question and chats on the terminal, and is
  refused when there is none. It used to ask one question per line of the pipe.
- A saved answer, `--session` and `/yank` hold every message of the answer, as
  shown, not only the last one.
- `CLAUDE_ASK_FORCE_INTERACTIVE` is for the tests' chats; `CLAUDE_ASK_FORCE_TTY`
  is new, for tests that look at the bar.

### Added

- `NO_COLOR` is honored.

### Fixed

- Text after a wrapped line or wide characters no longer lands in the wrong
  place or overwrites what is there, and the end of a long status bar line is no
  longer left beside the text written over it.
- Messages of one answer are separated by a blank line instead of running
  together (`Let me check that.The answer is 42.`).
- Control characters in answers and questions, except tab and newline, are
  removed before they reach the terminal or the clipboard, so an escape sequence
  in an answer cannot set the clipboard or the title.
- A paste that arrives in pieces (ssh, tmux) is one question: the chat waits
  0.1s for more after each line.
- Lines of the script no longer end up in the chat history. Remove any already
  there from `~/.local/state/claude-ask/history`: they read
  `if [[ "$LAST_TURN_STATUS" -ne 0 ]]; then   exit 1; fi` and `exit 0`.
- Session files are private (`0600`, also `--save-raw`, and existing ones when
  next written), and so are a new session directory and the default one (`0700`).

## [0.8.2] - 2026-11-03

### Fixed

- `--popup` with a question whose answer fails no longer reports "tmux
  could not start the popup": the popup did start. The run's own exit
  status is passed on instead.

### Changed

- The pager pipeline's variables and functions are named after the pager
  (`PAGER_PID`, `PAGER_FIFO`, `PAGER_OUT_FD`, `drain_pager`), not `bat`.
- `--popup` is tested against a real tmux (a private server with a client
  attached in a pseudo-terminal): the paging, `LESS=-F`, closing on quit
  and on `/quit`, and a failed answer. CI installs tmux for it.

## [0.8.1] - 2026-11-03

### Fixed

- Ctrl-C at the chat prompt clears the line at once and starts a new
  prompt. Before, it showed `^C` and kept reading: what was typed next was
  added to the line, and all of it was dropped only at Enter.
- A run ended by a signal (SIGTERM, or Ctrl-C outside a chat) cleans up
  again: the cleanup stopped at its first line, leaving the runtime
  directory behind and `claude` and the pager running.
- Ctrl-\ (SIGQUIT) ends the run through the same cleanup.

## [0.8.0] - 2026-11-03

### Added

- Tab at the chat prompt completes the `/command` names and the arguments
  of `/effort`, `/model`, `/theme` and `/yank`, and lists the matches when
  there are several. Elsewhere, and on every line of a paste after the
  first, it still inserts a tab. It works in emacs and vi mode.
- Shell completion for zsh (`completions/_claude-ask`) and bash
  (`completions/claude-ask.bash`): the options, effort levels, models,
  themes, `--split=` directions, and saved session names for `--session`
  and `--resume=`. `just install` links them into
  `~/.local/share/zsh/site-functions` and
  `~/.local/share/bash-completion/completions`.

## [0.7.0] - 2026-11-03

### Added

- `--resume=ID|N` continues a chosen session, found the same way as
  `--session` (a `--history` number, a name or a unique prefix); `-r` alone
  still takes the newest.
- The chat prompt shows the model and effort, e.g. `opus 5.5 · high > `:
  the model that answered last (or the one `-m` / `/model` asks for until
  it answers) and the effort when one is set.
- A multi-line paste at the chat prompt is one question; its lines show at
  a `. ` prompt. Before, only the first line was asked and the rest was
  lost.

### Changed

- At the chat prompt Tab inserts a tab instead of completing a file name,
  so pasted code keeps its tabs, and bracketed paste is off (the chat uses
  its own readline settings after your `~/.inputrc`).

## [0.6.2] - 2026-11-03

### Fixed

- Saving a session failed with jq 1.7 (Ubuntu 24.04, Debian 13) with
  "array and object cannot be added": jq 1.7 reads `X + Y as $v` with `as`
  binding first. Found by the first CI run.

## [0.6.1] - 2026-11-03

### Changed

- Streaming is lighter: one `jq` process parses the whole stream instead
  of one per event (300 events: 10.5s of parsing down to 0.4s).
- `--history` reads every session file with one `jq` call instead of
  three processes per file (300 sessions: 4.9s down to 0.2s). A file that
  is not valid JSON is still listed, by name.

### Added

- CI: GitHub Actions runs shellcheck and the bats suite on every push to
  main and every pull request.

## [0.6.0] - 2026-11-03

### Added

- Yanking: `-y` / `--yank` copies the answer and `-Y` / `--yank-code`
  its fenced code blocks (`--yank-code=N` only the Nth) to the clipboard
  (wl-copy, xclip, xsel or pbcopy; `CLAUDE_ASK_CLIPBOARD` overrides) and,
  inside tmux, a tmux buffer. With a question they copy the new answer
  (every answer in a chat with `-i`); without one, the last answer of the
  newest session, or of `--session ID|N`, and exit. The last newline is left
  off, so a pasted command does not run at once.
- Chat command `/yank [code [N]]` copies the last answer, its code blocks or
  block N; after `-r` that is the session's last answer.
- `--split[=h|v]` runs claude-ask in a new tmux pane, side by side when the
  pane is more than twice as wide as tall with 80 columns per half, else one
  above the other. With a question the answer goes to the new pane (which
  then stays as a chat) and the focus stays where it was; without one you
  chat in the new pane.
- `--popup` runs claude-ask in a tmux popup (`CLAUDE_ASK_POPUP_SIZE`,
  default 80%): a question's answer streams and then opens from the top in a
  pager (`CLAUDE_ASK_POPUP_PAGER`, default `less -R -+F`); quitting it
  closes the popup. Without a question it is a chat until `/quit`.
- The options, `CLAUDE_ASK_*` variables, `SESSION_DIR` and `PATH` reach the
  new pane or popup; the question goes through a private temp file, so long
  piped questions work.

### Fixed

- In a terminal too narrow for the whole status bar, segments are left out
  from the right (done, then duration, cost and tokens) instead of the bar
  wrapping, and the redraw counts wrapped rows, so it no longer leaves
  copies of the bar behind. The width is re-read when the terminal is
  resized; `CLAUDE_ASK_COLUMNS` overrides it.
- A model claude does not know no longer breaks the conversation. Its error
  is reported (not shown as the answer), the turn is not saved, and the chat
  goes back to the last model that answered (or the default). A model that
  `-r` restored from the session and that no longer exists is retried with
  the default model straight away.
- An API error's message (from an `assistant` event with an `error`) is
  reported as the error instead of being streamed as the answer.

## [0.5.0] - 2026-11-03

### Added

- `-e` / `--effort LEVEL` sets the effort (thinking) level (`low`,
  `medium`, `high`, `xhigh`, `max`) and `-m` / `--model MODEL` the model;
  `CLAUDE_ASK_EFFORT` and `CLAUDE_ASK_MODEL` set their defaults. The status
  bar shows the effort after the model, e.g. `opus 5.5 · high`.
- Chat commands: `/help`, `/effort [LEVEL]`, `/model [NAME]`, `/theme
  [NAME]`, `/status`, `/new` (start a new conversation), `/editor` (same as
  `\e`), and `/exit` / `/quit`. An unknown `/word` is refused instead of
  being sent to Claude. The chat opens with a `/help for commands` hint.
- Session files record each turn's model, effort and `-m` option;
  `--session` shows them per turn, and `-r` keeps the session's effort and
  model unless `-e` or `-m` is given.

### Changed

- The status bar shows the model's version: `opus 5.5`, `sonnet 4.5`,
  `sonnet 3.5`, instead of just `opus` or `sonnet`. Other families, such as
  `fable 5.1`, are shortened the same way.

## [0.4.1] - 2026-10-31

### Changed

- The default pager is `nvcat --pager less` instead of nvimpager with a
  personal colorscheme. When the default pager is not installed, answers
  print as plain text instead of disappearing.

### Added

- `CLAUDE_ASK_PAGER` sets the default pager command.

### Fixed

- The pager gets the terminal width (`COLUMNS`) while streaming; it writes
  to a pipe there and fell back to 80 columns.

## [0.4.0] - 2026-10-31

### Added

- Chat mode: `-i` / `--interactive` keeps a `> ` prompt open after each
  answer, and every question continues the same Claude conversation. It is
  the default when no question is given and stdin is a terminal. `\e` at the
  prompt opens `$EDITOR` for a longer question, `exit` / `quit` / Ctrl-D end
  the chat, Ctrl-C stops the current answer without leaving, and the up arrow
  recalls questions (kept in `~/.local/state/claude-ask/history`).
- `-r` / `--resume` continues the most recent saved session: with a
  question, asks it there; without, opens the chat there. It first shows a
  header (turns, total cost, directory) and the last question and answer.
- Piped input with no question is read as the question (`git diff |
  claude-ask`).
- Sessions record the directory they were started in (`cwd`).

### Changed

- With no question, `claude-ask` opens a chat instead of `$EDITOR`.
- A session file now holds a whole conversation: a `turns` list, with the
  first question, last answer and total cost, tokens and time at the top
  level. `--history` shows the number of turns (`3T`) and `--session`
  replays every turn. Files saved by earlier versions are read as one turn.
- The status bar's info line shows the turn number and the conversation's
  total cost from the second turn on.

### Fixed

- Sessions saved since Claude Code started emitting hook events before its
  `init` event had `model: null`; the model is now taken from `init`.

## [0.3.1] - 2026-10-31

### Changed

- Redrawing the status bar no longer starts any processes: the format helpers
  use bash arithmetic instead of `bc` (same output), and nothing runs in a
  subshell. A 300-event answer renders in about a third of the time; most of
  what remains is the one `jq` call per event.
- `bc` is no longer needed.

### Fixed

- A question with no ASCII letters or digits (e.g. Japanese only) is saved as
  `session-<id>.json` instead of a hidden `.json` that `--history` never listed.
- The README, CLAUDE.md and the 0.1.0 entry below said the status bar was
  pinned to the top row; it is drawn below the streamed text.

## [0.3.0] - 2026-10-31

### Added

- `--version` prints the version (from the repo's `VERSION`, also when
  installed as a symlink).
- `CLAUDE_ASK_DEMO_DELAY` sets the delay between demo frames.

### Changed

- `--save-raw` now saves the raw stream as `NAME.jsonl` in addition to the
  normal `NAME.json`, instead of in its place, so raw-saved sessions show up in
  `--history` and replay with `--session`.
- The question is passed to `claude` on stdin instead of as an argument.

### Fixed

- A question starting with `-` is no longer read by `claude` as an option.
- Costs, token counts and durations are formatted correctly under a
  comma-decimal locale (e.g. `de_DE.UTF-8`); previously they failed.
- `--history` and `--debug-log` no longer need GNU `date`.
- A pager that writes part of a line and waits no longer hangs the stream.

## [0.2.0] - 2026-10-31

### Changed

- When `claude` fails (missing command, non-zero exit, an error result, or a
  response that ends without a result), `claude-ask` prints the error and
  `claude`'s stderr and exits non-zero; the status bar shows a cross. An
  error result is still saved as a session, with `is_error: true`.
- `--debug-log` now always writes to
  `~/.local/state/claude-ask/debug.log`; use `--debug-log=FILE` for another
  file. `--debug-log FILE` is no longer accepted.
- Runtime files (pager FIFO, raw stream, `claude`'s stderr) live in one
  private directory per run under `$XDG_RUNTIME_DIR`, removed on exit.
- Missing `jq` or `bc` is reported up front.
- Each stream event is parsed with a single `jq` call.

### Added

- `CLAUDE_ASK_BIN` names the `claude` command to run.

### Fixed

- `--pager` commands with quoted arguments work; the default nvimpager
  command now receives its colorscheme arguments intact.
- `--debug-log "question"` no longer takes the question as the log file name.
- Answer text in every content block of a message is shown, not only the
  first block.
- The last line of the pager's output is no longer dropped when it has no
  trailing newline (one-line answers could vanish).
- Powerline separators take the color of the segment before them when the
  tokens or cost segment is missing.
- A stream line that is not JSON no longer prevents saving the session.

## [0.1.0] - 2026-10-28

### Added

- `claude-ask`, moved here from `~/.config/claude/scripts/`: asks Claude a
  question from the terminal (`claude -p` with stream-json), streams the answer
  through a pager above a status bar drawn below the text (themes `minimal`,
  `bubbles`, `powerline`), saves sessions to
  `~/.local/share/claude/cli-sessions/` and replays them with `--history` /
  `--session`.
- The bats suite (`just test`) and its stream-json fixtures; `just install`
  links the script into `~/.local/bin`.
