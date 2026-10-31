# claude-ask

Ask Claude a question from the terminal. `claude-ask` runs
`claude -p --output-format stream-json`, streams the answer through a pager
and pins a status bar (model, tokens, cost, time) to the top row.

```sh
claude-ask "Explain git rebase"          # ask
claude-ask                               # compose the question in $EDITOR
claude-ask --theme powerline "..."       # minimal | bubbles | powerline
claude-ask --history                     # saved sessions
claude-ask --session 1                   # replay the newest one
claude-ask --version                     # print the version
claude-ask --help                        # every option
```

Needs `claude` (Claude Code), `jq`, `bc`, and a pager (`nvimpager` by
default; `--pager CMD`, run with `bash -c`, or `--no-pager` otherwise).
Sessions are saved to `~/.local/share/claude/cli-sessions/` (`SESSION_DIR`
overrides); `CLAUDE_ASK_BIN` names a different `claude` command. When
`claude` fails, its error is printed and `claude-ask` exits non-zero.
`--debug-log` writes to `~/.local/state/claude-ask/debug.log`
(`--debug-log=FILE` for another file).

## Install

```sh
just install    # symlinks bin/claude-ask into ~/.local/bin
```

## Development

`just test` runs the bats suite in `test/`; `just lint` runs shellcheck.
The tests never call the real `claude`: `test/stubs/claude` replays a
fixture from `test/fixtures/`.
`docs/claude-ask.example.json` is a recorded stream-json session for reference.
