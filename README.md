# claude-ask

Ask Claude a question from the terminal. `claude-ask` runs
`claude -p --output-format stream-json` and streams the answer through a
pager, with a status bar (model, tokens, cost, time) drawn just below the
text as it arrives; the final bar stays under the answer.

```sh
claude-ask "Explain git rebase"          # ask
claude-ask                               # compose the question in $EDITOR
claude-ask --theme powerline "..."       # minimal | bubbles | powerline
claude-ask --history                     # saved sessions
claude-ask --session 1                   # replay the newest one
claude-ask --version                     # print the version
claude-ask --help                        # every option
```

Needs bash 5, `claude` (Claude Code), `jq`, and a pager (`nvimpager` by
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
