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
claude-ask --resume=3                    # continue the third newest (or --resume=NAME)
git diff | claude-ask                    # piped input is the question
git diff | claude-ask "Review this"      # or follows the question
claude-ask "List 3 colors" > colors.txt  # just the answer in the file
claude-ask --theme powerline "..."       # minimal | bubbles | powerline
claude-ask -e high -m sonnet "..."       # effort level and model
claude-ask -Y "..."                      # copy the answer's code blocks
claude-ask -y                            # copy the last saved answer
claude-ask --split "..."                 # answer in a new tmux pane
claude-ask --popup                       # chat in a tmux popup
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
Sessions are saved to `${XDG_DATA_HOME:-~/.local/share}/claude-ask/sessions/`
(`SESSION_DIR` overrides; those in the old `~/.local/share/claude/cli-sessions`
move there on the first run); `CLAUDE_ASK_BIN` names a different `claude` command. When
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
last asked with, unless `-e` or `-m` is given. When `claude` does not know
the model, the turn is not saved and `claude-ask` goes back to the last model
that answered (or the default); a model `-r` restored is then retried with
the default.

Options with a value also take `--option=VALUE`, and short flags can be bundled
(`-ir`, `-ie high`). While a tool runs, the line under the status bar names it
(`Bash: git status`); tools `claude` was not permitted to use are listed after
the answer. `\e` opens `$VISUAL` or `$EDITOR`, which can hold arguments
(`code --wait`).

In a terminal too narrow for the whole status bar, segments are left out
from the right (done, duration, cost, tokens); `CLAUDE_ASK_COLUMNS` sets the
width it is fitted to.

## Pipes and files

Piped input (or a file on stdin) goes after the question, with a blank line
between; with no question it is the question. It is read to its end, and after
2 seconds of waiting a note says so: `< /dev/null` skips it. With `-i` the chat
then continues on the terminal, and with no terminal `-i` is refused rather than
taking each line for a question.

When stdout is not a terminal it gets only the answer: no status bar, cursor
moves, colors or default pager (a `--pager` you give still runs). The status bar
goes to stderr if that is a terminal. `NO_COLOR` turns off colors everywhere.

Control characters in answers and questions, other than tab and newline, are
removed before they are shown or copied, so an escape sequence in something a
tool fetched cannot reach the terminal. An answer holds all the messages it was
shown with (a tool call can come between them), a blank line between each.
Session files are `0600`; a new or the default session directory is `0700`.

## Chat commands

The prompt shows the model and the effort level, e.g. `opus 5.5 · high > `:
the model that answered last, or the one `-m` or `/model` asks for until it
answers. A multi-line paste is asked as one question (its lines show at a
`. ` prompt); for that the chat turns bracketed paste off, on top of your
own readline settings (emacs or vi mode).

Tab completes the command names and the arguments of `/effort`, `/model`,
`/theme` and `/yank`, and lists the choices when there are several (`/`
then Tab lists every command). Anywhere else it inserts a tab, as it does
at every line of a paste after the first, so tabs in pasted code are kept.

In a chat, these commands work at the prompt:

| Command           | Does                                                     |
| ----------------- | -------------------------------------------------------- |
| `/help`           | list the commands                                        |
| `/effort [LEVEL]` | show or set the effort for the next questions; `default` clears it |
| `/model [NAME]`   | show or set the model; `default` clears it               |
| `/theme [NAME]`   | show or set the status bar theme                         |
| `/yank [code [N]]` | copy the last answer, its code blocks, or block N       |
| `/status`         | the conversation, model, effort and theme                |
| `/new`            | start a new conversation (a new session file)            |
| `/editor`, `\e`   | compose the question in `$EDITOR`                        |
| `/exit`, `/quit`  | end the chat (so do `exit`, `quit` and Ctrl-D)           |

A line whose first word is some other `/word` is refused as an unknown
command; one like `/etc/hosts: what is this?` is asked as a question.
Ctrl-C stops the answer being streamed without leaving the chat; at the
prompt it clears the line, as a shell does. Questions are kept in
`~/.local/state/claude-ask/history` for the up arrow; a multi-line one comes back
on one line, with `⏎` for each line break. Each conversation is one session file with a `turns` list;
`--history` shows the turn count, fitted to the terminal, and `--session` replays
every turn, in one pager when there are several.

## Yanking

`-y` copies the answer, `-Y` its fenced code blocks (a blank line between
them) and `--yank-code=N` only block N. They go to the clipboard (wl-copy on
Wayland, xclip or xsel on X11, pbcopy on macOS; `CLAUDE_ASK_CLIPBOARD` is a
command run with `bash -c` that reads the text on stdin) and, inside tmux, to
a tmux buffer (`prefix ]` pastes it). With a question they copy the new
answer; with no question they copy the newest session's last answer (or the
one `--session ID|N` names) and exit. `-i -y` copies every answer in a chat.

## tmux

`--split` starts claude-ask in a new pane: side by side when the current
pane is more than twice as wide as it is tall and each half keeps 80
columns, otherwise one above the other (`--split=h` or `--split=v` to
choose). With a question, the answer streams in the new pane, which stays
open as a chat, and you stay where you were; without one, the chat opens
there and so does the focus. `--popup` uses a tmux popup instead
(`CLAUDE_ASK_POPUP_SIZE`, e.g. `90%` or `120x40`): a question's answer
streams, then opens in a pager (`CLAUDE_ASK_POPUP_PAGER`, default
`less -R -+F`), and quitting the pager closes the popup; without a question
it is a chat until `/quit`. Both pass on the other options and everything
exported in your shell, which tmux would otherwise not see, in a private file
the new run reads and deletes, so API keys stay out of the process list.

## Install

```sh
just install    # symlinks bin/claude-ask into ~/.local/bin, and the completions
```

The shell completions (options, effort levels, models, themes, and saved
session names for `--session` and `--resume=`) are `completions/_claude-ask`
for zsh, linked into `~/.local/share/zsh/site-functions` (which must be in
`fpath`; run `rm ~/.zcompdump*; compinit` once if zsh had cached its list),
and `completions/claude-ask.bash` for bash, linked into
`~/.local/share/bash-completion/completions` (`BASH_COMPLETION_USER_DIR`),
where bash-completion loads it; without bash-completion, source it.

## Development

`just test` runs the bats suite in `test/`; `just lint` runs shellcheck.
The tests never call the real `claude`: `test/stubs/claude` replays a
fixture from `test/fixtures/`.
`docs/claude-ask.example.json` is a recorded stream-json session for reference.
