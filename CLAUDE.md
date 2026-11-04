# CLAUDE.md

claude-ask: one bash script, `bin/claude-ask`, an interactive wrapper around
`claude --output-format stream-json --verbose -p` that streams the answer
through a pager with a themed status bar redrawn just below the streamed text
(and left under the answer when it finishes).

## Commands

- `just test` (or `bats test/`) runs the suite; `bats test/<file>.bats` one file.
- `just lint` runs shellcheck on the script.
- `just install` symlinks `bin/claude-ask` into `~/.local/bin` and the
  completions (`completions/_claude-ask` for zsh, `completions/claude-ask.bash`
  for bash) where zsh and bash-completion look.

## Architecture

- **Status bar themes**: `--theme minimal|bubbles|powerline` (catppuccin mocha
  palette, nerd font separators for bubbles/powerline).
- **Pager**: default `nvcat --pager less` (`CLAUDE_ASK_PAGER` overrides; a
  default that is not installed means plain text); `--pager CMD` (run with
  `bash -c`) or `--no-pager`. `run_pager` passes `COLUMNS`, since a pager
  writing to a pipe cannot ask the terminal for its width. A renderer may print
  nothing until its input ends (nvcat does, and takes 200-300ms a run), so
  while streaming `write_chunk` splits the text into blocks (a blank line, or
  a whole code block) and `render_block` runs the pager on each;
  `render_flush` at `content_block_stop` and at the end shows the rest.
  Tests set `CLAUDE_ASK_PAGER=cat`.
- **Terminal or not**: `OUT_TTY` is whether stdout is a terminal
  (`CLAUDE_ASK_FORCE_TTY` for tests; `common_setup` sets it and `exec < /dev/null`).
  Bars, notes and cursor moves go to `BAR_FD`: stdout, else stderr if a terminal,
  else `/dev/null`. Without `OUT_TTY`, stdout gets only the answer.
- **Piped input**: `read_piped_input`; with a question only a pipe or file is
  read. `-i` then does `exec < /dev/tty`. `CLAUDE_ASK_FORCE_INTERACTIVE` keeps
  stdin as typed chat input.
- **Control characters**: `CONTROL_CHARS_RE` (a jq regex), in the stream fields
  and `clean` in `SESSION_TURNS_JQ`. Anything shown from a session file uses it.
- **Sessions**: parsed JSON saved to
  `${XDG_DATA_HOME:-~/.local/share}/claude-ask/sessions/{question-slug}.json`
  (moved once from `OLD_SESSION_DIR`, unless `SESSION_DIR` is set), plus the raw
  stream as `{question-slug}.jsonl` with `--save-raw`; `--history` lists
  them, `--session ID|N` replays one.
- **Demos**: `--demo-themes` and `--demo-output` render without calling Claude
  (`CLAUDE_ASK_DEMO_DELAY=0` removes the frame delay; the tests set it).
- **Question**: passed to `claude -p` on stdin, never as an argument.
- **Chat and resume**: `ask_once` runs one turn (stream, save, report);
  `chat_loop` reads `> ` prompts and calls it; `CONV_*` holds the
  conversation (session file, claude session id for `--resume`, which works
  from any directory, turns, total cost). `-r` loads the newest session file, `--resume=ID|N` the one
  `find_session` finds (shared with `--session`). No question + a terminal on
  stdin means chat; `CLAUDE_ASK_FORCE_INTERACTIVE` lets tests chat over a pipe.
  `chat_prompt` puts `LAST_MODEL` (or `MODEL`) and `EFFORT` in the prompt;
  `chat_inputrc` gives readline bracketed paste off and Tab as tab-insert,
  and `chat_loop` gathers pasted lines already waiting into one question
  (at a terminal only). At a terminal `chat_bind_keys` binds Tab to
  `chat_tab` and Ctrl-C to `chat_ctrl_c` with `bind -x` (which needs
  `set -o emacs` in a script; the inputrc's editing-mode still wins).
  `chat_read` reads each prompt line with the tty's intr key undefined
  (a trapped SIGINT does not end `read -e`) and restores `CHAT_STTY`
  after; `cleanup` restores it too, and QUIT and TERM are trapped so it
  runs. `chat_complete LINE POINT` (before
  the guard, unit-tested) completes `/commands` and their arguments or
  inserts a tab, and `CHAT_TAB_LITERAL` makes it a plain tab at a paste's
  continuation lines. `bind -x` runs inside `IFS= read`, so IFS is empty
  there. `test/chat_terminal.bats` drives a pseudo-terminal
  with `test/helpers/pty_run.py`.
  `chat_command` runs the `/word` commands (`/help`, `/effort`, `/model`,
  `/theme`, `/yank`, `/status`, `/new`, `/exit`, `/quit`); a first word that is not `/[a-z]+`
  is a question.
- **Effort and model**: `EFFORT` and `MODEL` (`-e`, `-m`, `CLAUDE_ASK_EFFORT`,
  `CLAUDE_ASK_MODEL`, `/effort`, `/model`; empty means claude's default) are
  passed as `--effort` and `--model` on every turn. The stream never reports
  the effort, so the status bar (`model_label`) shows only one set here.
  Each turn saves `model` (from `init`), `effort` and `model_option`; `-r`
  restores the last two when not given. An `assistant` event's `error`
  becomes `api_error`; on `model_not_found` `ask_once` saves nothing and
  falls back to `MODEL_GOOD` (retrying once when `MODEL_RESTORED`).
- **Yank**: `extract_code_blocks` (fills `CODE_BLOCKS`), `yank_answer`,
  `yank_text` (clipboard via `clipboard_cmd`, plus `tmux load-buffer`).
  `LAST_ANSWER` is the result text of the last turn (or the session's last
  answer after `-r`). `YANK_PREVIOUS`: `-y`/`-Y` with no question.
- **tmux**: `launch_in_tmux` re-runs the script with `split-window` or
  `display-popup`, passing options. tmux uses the server's environment, so all
  that is exported goes in a private file, `_CLAUDE_ASK_ENV_FILE`, which the very
  top of the script sources and deletes; nothing secret goes on tmux's command
  line. The question goes in `_CLAUDE_ASK_QUESTION_TMP` (read and deleted), a
  popup's paging in `_CLAUDE_ASK_PAGE_AFTER`. `display-popup -E` returns the popup
  run's status, so a nonzero status with the environment file gone is passed on,
  not reported as tmux failing.
  `test/stubs/tmux` logs calls and can run the command
  (`CLAUDE_STUB_TMUX_RUN`; display-popup then returns its status);
  `test/tmux_popup.bats` drives a real tmux (private server, client in a
  pty with `PTY_SIZE`; skipped without tmux); `common_setup` unsets `TMUX` and points
  `CLAUDE_ASK_CLIPBOARD` at a temp file.
- **Width**: `render_status_bar_fitted` drops segments to fit `TERM_COLS`
  (`read_term_cols`: `CLAUDE_ASK_COLUMNS`, the tty, `COLUMNS`; re-read on
  WINCH). Tests set `CLAUDE_ASK_COLUMNS=200`.
- **Redraw**: `update_status_bar` never computes a column: it makes rows with
  `\eD` (keeps the column, unlike `\n`), moves back up by `text_rows`, and draws
  between `\e7` and `\e8`. `emit_text` clears the old bar before text goes over
  it when text reaches them. `test/screen.bats` reads real screens from a tmux pane; it starts below
  the top-left, where tmux's `scroll-on-clear` turns `\e[J` into history.
- **Session files**: one per conversation; `turns` plus top-level first
  question, last answer and totals (`SESSION_JQ`). Files from before turns are
  read as one turn (`SESSION_TURNS_JQ`'s `turns_of`). Model and cwd come from
  the `init` system event; hook events come before it.
- **Tools**: stream fields 13 and 14 are the tool an event starts and the result's
  denied tools; `current_tool` is on the info line until a `user` event, text or
  the result.
- **Answers**: events of one message share `.message.id`; a blank line goes
  where it changes, in `process_stream_line` and `SESSION_JQ` alike.
- **Partial messages**: `claude` gets `--include-partial-messages`, so text comes
  as `stream_event` deltas and each finished block comes again, whole, in an
  `assistant` event, which `stream_text_unconfirmed` skips (a stream with no
  deltas still works). `test/fixtures/partial_messages.jsonl` is a real recording,
  scrubbed: its `partial_json` deltas split a path across events, so check
  fixtures on their joined strings. `show_stream_event` redraws about ten times a
  second for deltas, and never with the cursor just past the last column
  (`LINE_COLS`), since moving it from there loses the next character's place.
- **Stream parsing**: `process_stream_line` updates the state variables and
  is the only parser: the main loop, `--demo-output` and the tests all call
  it. It gets an event's fields from one long-lived `jq` coprocess
  (`stream_fields`, `STREAM_COPROC_JQ`): one NUL-separated record of
  `STREAM_FIELD_COUNT` fields per input line, an empty one for bad input.
  The coprocess closes inherited fds and ignores
  SIGINT; it is restarted if it dies. `save_session` writes session files.
- **Chat history**: read `-e` stops at a newline, so a multi-line question is held
  on one line with `CHAT_NEWLINE_MARK` (`⏎`), turned back on submit.
- **History**: `fit_column` and `display_width` do the columns;
  `history_records` reads all session files with one `jq`
  (`HISTORY_JQ`), falling back to one per file when one is not JSON;
  `format_age` formats the age.
- **Runtime files**: one private `mktemp -d` per run (under
  `$XDG_RUNTIME_DIR`) holds the raw stream and `claude`'s stderr; `cleanup` removes it.
- **Traps**: write `return 0`, never a bare `return`, in anything
  `cleanup` or the traps call: in a trap a bare `return` gives the status
  from before the trap, and under `set -e` that aborts the handler.
- **Renderers and format helpers** write into the variable named by their
  first argument (like `printf -v`), so a redraw forks nothing; their locals
  all start with `_`, so output variable names must not.
- **Testability**: the functions are sourceable with `_CLAUDE_ASK_SOURCED=1`;
  everything the tests call is defined before that guard.
  `common_setup` in `test/test_helper.bash` isolates each test (temp
  `SESSION_DIR`, `XDG_*` dirs) and points `CLAUDE_ASK_BIN` at
  `test/stubs/claude`, which replays `CLAUDE_STUB_FIXTURE`; test files with
  their own `setup()` must call `common_setup` first.
- `docs/claude-ask.example.json` is a recorded stream-json session.
- **Shell completion**: `completions/`; they glob `SESSION_DIR` for session
  names themselves. `test/completion.bats` calls the bash function, runs
  the zsh file with `_arguments` stubbed, and checks both cover every
  option in `--help`, so a new option needs adding to both.
- CI: `.github/workflows/ci.yml` runs `just lint` and `just test` on
  Ubuntu 24.04 (bats, just, bc and zsh from apt).

## Versioning

`VERSION` holds the version; each release gets an annotated tag `vX.Y.Z` and
a `CHANGELOG.md` entry.
