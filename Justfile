default:
    @just --list

# run the bats test suite
test *ARGS:
    bats {{ ARGS }} test

# shellcheck the script and the bash completion it prints
lint:
    shellcheck bin/claude-ask
    bin/claude-ask --completions bash | shellcheck -s bash -

# symlink bin/claude-ask into ~/.local/bin (or $XDG_BIN_HOME), refusing to replace anything but a symlink, and write the shell completions where zsh (fpath), bash-completion and fish look; run it again after an update for new options
install:
    #!/usr/bin/env bash
    set -euo pipefail
    data="${XDG_DATA_HOME:-$HOME/.local/share}"
    src="$(pwd -P)/bin/claude-ask"
    dest="${XDG_BIN_HOME:-$HOME/.local/bin}/claude-ask"
    mkdir -p "${dest%/*}"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      echo "install: $dest exists and is not a symlink; remove it first" >&2
      exit 1
    fi
    ln -sfn "$src" "$dest"
    echo "$dest -> $src"
    write() {
      mkdir -p "${2%/*}"
      # Not through a symlink an older install left there
      rm -f "$2"
      "$src" --completions "$1" > "$2"
      echo "$2"
    }
    write zsh "$data/zsh/site-functions/_claude-ask"
    write bash "${BASH_COMPLETION_USER_DIR:-$data/bash-completion}/completions/claude-ask"
    if command -v fish > /dev/null 2>&1; then
      write fish "${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions/claude-ask.fish"
    fi
