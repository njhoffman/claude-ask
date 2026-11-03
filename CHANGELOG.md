# Changelog

All notable changes to claude-ask are recorded here, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, with
[semantic versioning](https://semver.org/).

## [Unreleased]

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
