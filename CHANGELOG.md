# Changelog

All notable changes to claude-ask are recorded here, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, with
[semantic versioning](https://semver.org/).

## [Unreleased]

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
