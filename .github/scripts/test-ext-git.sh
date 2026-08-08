#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

git_init() {
  git -c init.defaultBranch=main init "$1" >/dev/null
  git -C "$1" config user.name "Codex Test"
  git -C "$1" config user.email "codex@example.com"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "assertion failed: $message" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

SUBMODULE_REMOTE="$TMP_ROOT/submodule-remote.git"
SUBMODULE_WORK="$TMP_ROOT/submodule-work"
git init --bare "$SUBMODULE_REMOTE" >/dev/null
git_init "$SUBMODULE_WORK"
echo "submodule content" >"$SUBMODULE_WORK/sub.txt"
git -C "$SUBMODULE_WORK" add sub.txt
git -C "$SUBMODULE_WORK" commit -m "submodule init" >/dev/null
git -C "$SUBMODULE_WORK" remote add origin "$SUBMODULE_REMOTE"
git -C "$SUBMODULE_WORK" push origin main >/dev/null
SUBMODULE_SHA=$(git -C "$SUBMODULE_WORK" rev-parse HEAD)

PACKAGE_REMOTE="$TMP_ROOT/package-remote.git"
PACKAGE_WORK="$TMP_ROOT/package-work"
git init --bare "$PACKAGE_REMOTE" >/dev/null
git_init "$PACKAGE_WORK"
echo "first" >"$PACKAGE_WORK/value.txt"
git -C "$PACKAGE_WORK" add value.txt
git -C "$PACKAGE_WORK" commit -m "first" >/dev/null
FIRST_SHA=$(git -C "$PACKAGE_WORK" rev-parse HEAD)
git -C "$PACKAGE_WORK" tag v1.0.0
git -C "$PACKAGE_WORK" -c protocol.file.allow=always submodule add "$SUBMODULE_REMOTE" deps/sub >/dev/null
git -C "$PACKAGE_WORK" commit -am "add submodule" >/dev/null
SECOND_SHA=$(git -C "$PACKAGE_WORK" rev-parse HEAD)
git -C "$PACKAGE_WORK" branch stable
git -C "$PACKAGE_WORK" remote add origin "$PACKAGE_REMOTE"
git -C "$PACKAGE_WORK" push origin main stable --tags >/dev/null

run_case() {
  local label="$1"
  local requested_ref="$2"
  local expected_head="$3"
  local expected_branch="$4"
  local expected_submodule="$5"
  local build_root="$TMP_ROOT/build-$label"

  (
    set -euo pipefail
    export GIT_ALLOW_PROTOCOL="file:git:http:https:ssh"
    source "$SCRIPT_DIR/ext-git.sh"
    PACKAGE_NAME="pkg-$label"
    PACKAGE_REF="$requested_ref"
    PACKAGE_URL="$PACKAGE_REMOTE"
    PKG_BUILD_PATH="$build_root"
    checkout
  )

  local repo_path="$build_root/pkg-$label"
  local actual_head
  actual_head=$(git -C "$repo_path" rev-parse HEAD)
  assert_eq "$expected_head" "$actual_head" "$label head"

  local actual_branch
  actual_branch=$(git -C "$repo_path" branch --show-current)
  assert_eq "$expected_branch" "$actual_branch" "$label branch state"

  if [ -n "$expected_submodule" ]; then
    local submodule_head
    submodule_head=$(git -C "$repo_path/deps/sub" rev-parse HEAD)
    assert_eq "$expected_submodule" "$submodule_head" "$label submodule head"
  fi
}

run_case "branch" "stable" "$SECOND_SHA" "stable" "$SUBMODULE_SHA"
run_case "tag" "v1.0.0" "$FIRST_SHA" "" ""
run_case "commit" "$SECOND_SHA" "$SECOND_SHA" "" "$SUBMODULE_SHA"

echo "test-ext-git.sh: PASS"
