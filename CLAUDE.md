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
- **Pager**: `--pager CMD` (run with `bash -c`) or `--no-pager`.
- **Sessions**: parsed JSON saved to
  `~/.local/share/claude/cli-sessions/{question-slug}.json`, plus the raw
  stream as `{question-slug}.jsonl` with `--save-raw`; `--history` lists
  them, `--session ID|N` replays one.
- **Demos**: `--demo-themes` and `--demo-output` render without calling Claude
  (`CLAUDE_ASK_DEMO_DELAY=0` removes the frame delay; the tests set it).
- **Question**: passed to `claude -p` on stdin, never as an argument.
- **Stream parsing**: `process_stream_line` (one `jq` call per event) updates
  the state variables and is the only parser: the main loop, `--demo-output`
  and the tests all call it. `save_session` writes session files.
- **Runtime files**: one private `mktemp -d` per run (under
  `$XDG_RUNTIME_DIR`) holds the pager FIFO, the raw stream and `claude`'s
  stderr; `cleanup` removes it.
- **Testability**: the functions are sourceable with `_CLAUDE_ASK_SOURCED=1`;
  everything the tests call is defined before that guard.
  `common_setup` in `test/test_helper.bash` isolates each test (temp
  `SESSION_DIR`, `XDG_*` dirs) and points `CLAUDE_ASK_BIN` at
  `test/stubs/claude`, which replays `CLAUDE_STUB_FIXTURE`; test files with
  their own `setup()` must call `common_setup` first.
- `docs/claude-ask.example.json` is a recorded stream-json session.

## Versioning

`VERSION` holds the version; each release gets an annotated tag `vX.Y.Z` and
a `CHANGELOG.md` entry.
