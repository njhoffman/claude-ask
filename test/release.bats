#!/usr/bin/env bats
# scripts/release-notes, which the release workflow publishes from

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  NOTES="$BATS_TEST_DIRNAME/../scripts/release-notes"
  CL="$TEST_TEMP_DIR/CHANGELOG.md"
  cat > "$CL" << 'MD'
# Changelog

## [Unreleased]

### Added

- not yet

## [1.2.0] - 2026-01-02

### Added

- one

### Fixed

- two

## [1.1.10] - 2026-01-01

- older

## [1.1.1] - 2025-12-31

- oldest
MD
}

@test "release-notes: a version's section, without its heading or blank ends" {
  run "$NOTES" 1.2.0 "$CL"
  [ "$status" -eq 0 ]
  [ "$output" = $'### Added\n\n- one\n\n### Fixed\n\n- two' ]
  # A tag name works too
  run "$NOTES" v1.2.0 "$CL"
  [ "$output" = $'### Added\n\n- one\n\n### Fixed\n\n- two' ]
}

@test "release-notes: 1.1.1 is not 1.1.10, and the last section ends at the file's end" {
  run "$NOTES" 1.1.1 "$CL"
  [ "$output" = "- oldest" ]
  run "$NOTES" 1.1.10 "$CL"
  [ "$output" = "- older" ]
}

@test "release-notes: no section is status 1, saying so" {
  run --separate-stderr "$NOTES" 9.9.9 "$CL"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"no section for 9.9.9"* ]]
}

@test "release-notes: every tag of this repository has a section" {
  command -v git > /dev/null || skip "no git"
  local root tag
  root="$BATS_TEST_DIRNAME/.."
  git -C "$root" rev-parse --git-dir > /dev/null 2>&1 || skip "not a git checkout"
  # A shallow checkout (CI) has no tags; the version in VERSION is checked anyway
  for tag in $(git -C "$root" tag -l 'v*') "$(cat "$root/VERSION")"; do
    "$NOTES" "$tag" > /dev/null
  done
}
