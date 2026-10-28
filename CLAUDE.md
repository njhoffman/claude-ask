# CLAUDE.md

claude-ask: one bash script, `bin/claude-ask`, an interactive wrapper around
`claude --output-format stream-json --verbose -p` that streams the answer
through a pager with a themed status bar pinned to the terminal's top row.

## Commands

- `just test` (or `bats test/`) runs the suite; `bats test/<file>.bats` one file.
- `just lint` runs shellcheck on the script.
- `just install` symlinks `bin/claude-ask` into `~/.local/bin`.

## Architecture

- **Status bar themes**: `--theme minimal|bubbles|powerline` (catppuccin mocha
  palette, nerd font separators for bubbles/powerline).
- **Pager**: `--pager CMD` or `--no-pager`.
- **Sessions**: parsed JSON saved to
  `~/.local/share/claude/cli-sessions/{session_id}.json` (raw with
  `--save-raw`); `--history` lists them, `--session ID|N` replays one.
- **Demos**: `--demo-themes` and `--demo-output` render without calling Claude.
- **Testability**: the functions are sourceable with `_CLAUDE_ASK_SOURCED=1`;
  format helpers and renderers are defined before that guard.
  `test/test_helper.bash` sources the script and feeds fixtures from
  `test/fixtures/` through the parse loop.
- `docs/claude-ask.example.json` is a recorded stream-json session.

## Versioning

`VERSION` holds the version; each release gets an annotated tag `vX.Y.Z` and
a `CHANGELOG.md` entry.
