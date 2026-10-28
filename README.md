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
claude-ask --help                        # every option
```

Needs `claude` (Claude Code), `jq`, and a pager (`nvimpager` by default,
`--pager CMD` or `--no-pager` otherwise). Sessions are saved to
`~/.local/share/claude/cli-sessions/` (`SESSION_DIR` overrides).

## Install

```sh
just install    # symlinks bin/claude-ask into ~/.local/bin
```

## Development

`just test` runs the bats suite in `test/`; `just lint` runs shellcheck.
`docs/claude-ask.example.json` is a recorded stream-json session for reference.
