# claude-ask task list

Open work on claude-ask. Every item carries a priority, `(p1)` high, `(p2)`
normal or `(p3)` low, and a category: `[bug]`, `[feature]`, `[refactor]`,
`[docs]`, `[test]`, `[chore]` or `[perf]`.

Reviewed: 2026-10-28

## 1. claude-ask

- [ ] **Make `just lint` pass.** (p2) [chore] shellcheck reports 10 warnings
  (9 SC2034 unused variables such as `BG_CONTEXT` and `cache_read_tokens`, one
  SC2120 on `show_history`) and 10 infos in `bin/claude-ask`. Remove the dead
  variables or mark the deliberate ones, then add lint to CI or a pre-commit.
- [ ] **Temp files in a private directory.** (p3) [bug] The debug log defaults
  to `/tmp/claude-ask.log` and the FIFOs and raw stream use fixed `/tmp`
  prefixes (`bin/claude-ask` around lines 127, 682, 1078, 1141), readable by
  other users and ignoring `$TMPDIR`. Use `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}`
  and `mktemp -d` once per run.
- [ ] **Default pager depends on a personal colorscheme.** (p3) [bug]
  `PAGER_CMD` runs `nvimpager` with `colorscheme nord-nick`; on a host without
  nvimpager or that colorscheme the answer does not render. Fall back to the
  commented-out `bat` command when `nvimpager` is missing, or make it a config
  value.
- [ ] **A `--version` flag.** (p3) [feature] Print the `VERSION` file's value.
