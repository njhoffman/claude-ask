default:
    @just --list

# run the bats test suite, one job per core when GNU parallel is installed
# (TEST_JOBS=1 runs it one test at a time)
test *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    jobs="${TEST_JOBS:-}"
    if [[ -z "$jobs" ]] && command -v parallel > /dev/null 2>&1; then jobs=$(nproc); fi
    if [[ -n "$jobs" && "$jobs" != 1 ]]; then set -- --jobs "$jobs"; fi
    bats "$@" {{ ARGS }} test

# shellcheck the script, the bash completion it prints, and the test helpers
lint:
    shellcheck bin/claude-ask
    bin/claude-ask --completions bash | shellcheck -s bash -
    shellcheck -s bash -x test/stubs/* test/test_helper.bash test/smoke.sh scripts/*

# try the real claude: three haiku requests, about a cent; not part of test or CI
smoke:
    test/smoke.sh

# symlink bin/claude-ask into ~/.local/bin (or $XDG_BIN_HOME), refusing to
# replace anything but a symlink, and write the shell completions where zsh
# (fpath), bash-completion and fish look; run it again after an update for new
# options
install:
    scripts/install install

# remove what install made: the symlink (only one into this checkout) and the
# completion files; saved sessions stay
uninstall:
    scripts/install uninstall
