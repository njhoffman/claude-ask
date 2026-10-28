default:
    @just --list

# run the bats test suite
test *ARGS:
    bats {{ ARGS }} test

# shellcheck the script
lint:
    shellcheck bin/claude-ask

# symlink bin/claude-ask into ~/.local/bin (or $XDG_BIN_HOME); refuses to replace anything that is not a symlink
install:
    #!/usr/bin/env bash
    set -euo pipefail
    src="$(pwd -P)/bin/claude-ask"
    dest="${XDG_BIN_HOME:-$HOME/.local/bin}/claude-ask"
    mkdir -p "${dest%/*}"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      echo "install: $dest exists and is not a symlink; remove it first" >&2
      exit 1
    fi
    ln -sfn "$src" "$dest"
    echo "$dest -> $src"
