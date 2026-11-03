# claude-ask

Ask Claude a question from the terminal. `claude-ask` runs
`claude -p --output-format stream-json` and streams the answer through a
pager, with a status bar (model and version, effort, tokens, cost, time)
drawn just below the
text as it arrives; the final bar stays under the answer.

```sh
claude-ask "Explain git rebase"          # ask once
claude-ask                               # chat: a "> " prompt after each answer
claude-ask -i "Explain git rebase"       # ask, then keep chatting
claude-ask -r "And with --onto?"         # follow up in the most recent session
claude-ask -r                            # continue the most recent session as a chat
git diff | claude-ask                    # piped input is the question
claude-ask --theme powerline "..."       # minimal | bubbles | powerline
claude-ask -e high -m sonnet "..."       # effort level and model
claude-ask --history                     # saved sessions
claude-ask --session 1                   # replay the newest one
claude-ask --version                     # print the version
claude-ask --help                        # every option
```

Needs bash 5, `claude` (Claude Code) and `jq`. Answers are rendered with
`nvcat --pager less` (Neovim Markdown rendering, paged with `less` when
printed straight to the terminal); without `nvcat` they print as plain text.
`--pager CMD` (run with `bash -c`) or `CLAUDE_ASK_PAGER` picks another
renderer, `--no-pager` none. In a shell from `~/.shell`, `ask` is an alias
for `claude-ask`.
Sessions are saved to `~/.local/share/claude/cli-sessions/` (`SESSION_DIR`
overrides); `CLAUDE_ASK_BIN` names a different `claude` command. When
`claude` fails, its error is printed and `claude-ask` exits non-zero.
`--debug-log` writes to `~/.local/state/claude-ask/debug.log`
(`--debug-log=FILE` for another file).

`-e` / `--effort` sets the effort (thinking) level, one of `low`, `medium`,
`high`, `xhigh`, `max`, and `-m` / `--model` the model (an alias such as
`opus` or a full name); `CLAUDE_ASK_EFFORT` and `CLAUDE_ASK_MODEL` set the
defaults. Both are passed to `claude` on every turn. The status bar shows the
model with its version (`opus 5.5`) and, after it, the effort level; with no
effort given, `claude` uses its own setting, which the stream does not
report, so none is shown. `-r` keeps the effort and model the session was
last asked with, unless `-e` or `-m` is given.

In a chat, these commands work at the prompt:

| Command           | Does                                                     |
| ----------------- | -------------------------------------------------------- |
| `/help`           | list the commands                                        |
| `/effort [LEVEL]` | show or set the effort for the next questions; `default` clears it |
| `/model [NAME]`   | show or set the model; `default` clears it               |
| `/theme [NAME]`   | show or set the status bar theme                         |
| `/status`         | the conversation, model, effort and theme                |
| `/new`            | start a new conversation (a new session file)            |
| `/editor`, `\e`   | compose the question in `$EDITOR`                        |
| `/exit`, `/quit`  | end the chat (so do `exit`, `quit` and Ctrl-D)           |

A line whose first word is some other `/word` is refused as an unknown
command; one like `/etc/hosts: what is this?` is asked as a question.
Ctrl-C stops the answer being streamed without leaving the chat. Questions are kept in `~/.local/state/claude-ask/history`
for the up arrow. Each conversation is one session file with a `turns` list;
`--history` shows the turn count and `--session` replays every turn.

## Install

```sh
just install    # symlinks bin/claude-ask into ~/.local/bin
```

## Development

`just test` runs the bats suite in `test/`; `just lint` runs shellcheck.
The tests never call the real `claude`: `test/stubs/claude` replays a
fixture from `test/fixtures/`.
`docs/claude-ask.example.json` is a recorded stream-json session for reference.
