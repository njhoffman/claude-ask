# Changelog

All notable changes to claude-ask are recorded here, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, with
[semantic versioning](https://semver.org/).

## [Unreleased]

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
  through a pager under a status bar pinned to the top row (themes `minimal`,
  `bubbles`, `powerline`), saves sessions to
  `~/.local/share/claude/cli-sessions/` and replays them with `--history` /
  `--session`.
- The bats suite (`just test`) and its stream-json fixtures; `just install`
  links the script into `~/.local/bin`.
