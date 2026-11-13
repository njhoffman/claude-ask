#!/usr/bin/env bats
# scripts/install, which `just install` and `just uninstall` run

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  INSTALL="$BATS_TEST_DIRNAME/../scripts/install"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"
  unset XDG_BIN_HOME BASH_COMPLETION_USER_DIR
  export XDG_DATA_HOME="$HOME/.local/share" XDG_CONFIG_HOME="$HOME/.config"
  BIN="$HOME/.local/bin/claude-ask"
  ZSH_C="$XDG_DATA_HOME/zsh/site-functions/_claude-ask"
  BASH_C="$XDG_DATA_HOME/bash-completion/completions/claude-ask"
  FISH_C="$XDG_CONFIG_HOME/fish/completions/claude-ask.fish"
}

@test "install links the script and writes the completions; uninstall removes them" {
  run "$INSTALL" install
  [ "$status" -eq 0 ]
  [ -L "$BIN" ]
  [ "$(readlink -f "$BIN")" = "$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/bin/claude-ask" ]
  grep -q 'claude-ask' "$ZSH_C"
  grep -q 'claude-ask' "$BASH_C"
  mkdir -p "$SESSION_DIR"
  echo '{}' > "$SESSION_DIR/keep.json"
  run "$INSTALL" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$BIN" ] && [ ! -L "$BIN" ]
  [ ! -e "$ZSH_C" ] && [ ! -e "$BASH_C" ]
  # Sessions stay
  [ -f "$SESSION_DIR/keep.json" ]
  # Twice is fine, and says nothing
  run "$INSTALL" uninstall
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uninstall removes a fish completion even when fish is gone" {
  mkdir -p "${FISH_C%/*}"
  echo '# old' > "$FISH_C"
  PATH="$BATS_TEST_DIRNAME/stubs:/usr/bin:/bin" run "$INSTALL" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$FISH_C" ]
}

@test "uninstall leaves a claude-ask that is not this checkout's" {
  mkdir -p "${BIN%/*}"
  ln -s /usr/bin/true "$BIN"
  run --separate-stderr "$INSTALL" uninstall
  [ "$status" -eq 0 ]
  [ -L "$BIN" ]
  [[ "$stderr" == *"left alone"* ]]
  rm "$BIN"
  echo '#!/bin/sh' > "$BIN"
  run --separate-stderr "$INSTALL" uninstall
  [ -f "$BIN" ]
  [[ "$stderr" == *"is not a symlink; left alone"* ]]
}

@test "install refuses to replace a file that is not a symlink" {
  mkdir -p "${BIN%/*}"
  echo '#!/bin/sh' > "$BIN"
  run --separate-stderr "$INSTALL" install
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"exists and is not a symlink"* ]]
}

@test "install with no or a wrong word says how to use it" {
  run "$INSTALL"
  [ "$status" -eq 2 ]
  run "$INSTALL" remove
  [ "$status" -eq 2 ]
}
