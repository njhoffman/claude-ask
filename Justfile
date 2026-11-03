default:
    @just --list

# run the bats test suite
test *ARGS:
    bats {{ ARGS }} test

# shellcheck the script
lint:
    shellcheck bin/claude-ask completions/claude-ask.bash

# symlink bin/claude-ask into ~/.local/bin (or $XDG_BIN_HOME), and the shell completions where zsh (fpath) and bash-completion look; refuses to replace anything that is not a symlink
install:
    #!/usr/bin/env bash
    set -euo pipefail
    data="${XDG_DATA_HOME:-$HOME/.local/share}"
    link() {
      local src dest="$2"
      src="$(pwd -P)/$1"
      mkdir -p "${dest%/*}"
      if [[ -e "$dest" && ! -L "$dest" ]]; then
        echo "install: $dest exists and is not a symlink; remove it first" >&2
        exit 1
      fi
      ln -sfn "$src" "$dest"
      echo "$dest -> $src"
    }
    link bin/claude-ask "${XDG_BIN_HOME:-$HOME/.local/bin}/claude-ask"
    link completions/_claude-ask "$data/zsh/site-functions/_claude-ask"
    link completions/claude-ask.bash "${BASH_COMPLETION_USER_DIR:-$data/bash-completion}/completions/claude-ask"
