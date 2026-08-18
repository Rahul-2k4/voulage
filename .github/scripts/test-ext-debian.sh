#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PACKAGE_ROOT="$TMP_DIR/package"
MOCK_BIN="$TMP_DIR/bin"
CAPTURE="$TMP_DIR/dch-capture"
CARGO_CAPTURE="$TMP_DIR/cargo-capture"
mkdir -p "$PACKAGE_ROOT/debian" "$MOCK_BIN"

printf '%s\n' \
  'Source: fixture-package' \
  'Section: misc' \
  'Priority: optional' \
  'Maintainer: Regolith Linux <regolith.linux@gmail.com>' \
  'Standards-Version: 4.6.0' > "$PACKAGE_ROOT/debian/control"
printf '%s\n' \
  'fixture-package (1.2.3-1) unstable; urgency=medium' \
  '  * Initial release.' \
  ' -- Existing Maintainer <builder@hostname>  Mon, 10 Aug 2026 00:00:00 +0000' > "$PACKAGE_ROOT/debian/changelog"

cat > "$MOCK_BIN/dpkg-parsechangelog" <<'EOF'
#!/bin/bash
printf '%s\n' 1.2.3
EOF
cat > "$MOCK_BIN/dch" <<'EOF'
#!/bin/bash
printf '%s\n' "${DEBFULLNAME-}" "${DEBEMAIL-}" "${EMAIL-}" > "$DCH_CAPTURE"
EOF
chmod +x "$MOCK_BIN/dpkg-parsechangelog" "$MOCK_BIN/dch"

cat > "$MOCK_BIN/cargo" <<'EOF'
#!/bin/bash
printf '%s|%s\n' "${CARGO_NET_OFFLINE-}" "$*" >> "$CARGO_CAPTURE"
if [ "$1" = "vendor" ]; then
  mkdir -p vendor/mock-crate
  printf 'fixture\n' > vendor/mock-crate/lib.rs
  printf '[source.vendored-sources]\n'
fi
EOF
chmod +x "$MOCK_BIN/cargo"
export CARGO_CAPTURE
source "$REPO_ROOT/.github/scripts/ext-debian.sh"
export PATH="$MOCK_BIN:$PATH"
export PKG_BUILD_PATH="$TMP_DIR"
export PACKAGE_NAME=package
export CODENAME=resolute
export DCH_CAPTURE="$CAPTURE"
export CARGO_CAPTURE

assert_identity() {
  local expected_name=$1
  local expected_email=$2
  local actual_name actual_email
  actual_name=$(sed -n '1p' "$CAPTURE")
  actual_email=$(sed -n '2p' "$CAPTURE")
  [[ "$actual_name" == "$expected_name" ]]
  [[ "$actual_email" == "$expected_email" ]]
  [[ "$actual_name" != *hostname* ]]
  [[ "$actual_email" != *hostname* ]]
}

unset DEBEMAIL DEBFULLNAME EMAIL
update_changelog
assert_identity 'Regolith Linux' 'regolith.linux@gmail.com'

printf '%s\n' \
  'Source: fixture-package' \
  'Section: misc' \
  'Priority: optional' \
  'Standards-Version: 4.6.0' > "$PACKAGE_ROOT/debian/control"
unset DEBEMAIL DEBFULLNAME EMAIL
update_changelog
assert_identity 'Regolith Linux' 'regolith.linux@gmail.com'

assert_hook_before_stage() {
  local binary_line
  local caller hook_line stage_line
  for caller in local-build.sh main.sh ci-build.sh; do
    hook_line=$(grep -n "^[[:space:]]*prepare_source_package$" "$REPO_ROOT/.github/scripts/$caller" | cut -d: -f1)
    stage_line=$(grep -n "^[[:space:]]*stage_source$" "$REPO_ROOT/.github/scripts/$caller" | cut -d: -f1)
    [[ -n "$hook_line" && -n "$stage_line" && "$hook_line" -lt "$stage_line" ]]
  done
  binary_line=$(grep -n '^prepare_binary_package()' "$REPO_ROOT/.github/scripts/ext-debian.sh" | cut -d: -f1)
  [[ -n "$binary_line" ]]
  grep -n '^  prepare_binary_package$' "$REPO_ROOT/.github/scripts/ext-debian.sh" | awk -F: -v line="$binary_line" '$1 > line { found = 1 } END { exit !found }'
}

assert_hook_before_stage

rm -f "$CARGO_CAPTURE"
rm -f "$PACKAGE_ROOT/Cargo.toml"
printf 'vendor.tar\n' > "$PACKAGE_ROOT/debian/rules"
unset CARGO
prepare_source_package
[[ ! -s "$CARGO_CAPTURE" ]]
[[ ! -e "$PACKAGE_ROOT/vendor.tar" ]]

printf '[package]\nname = "fixture"\nversion = "0.1.0"\n' > "$PACKAGE_ROOT/Cargo.toml"
rm -f "$PACKAGE_ROOT/debian/rules" "$PACKAGE_ROOT/debian/Makefile" "$PACKAGE_ROOT/Makefile" "$PACKAGE_ROOT/justfile"
: > "$CARGO_CAPTURE"
prepare_source_package
[[ ! -s "$CARGO_CAPTURE" ]]
[[ ! -e "$PACKAGE_ROOT/vendor.tar" ]]

printf 'vendor.tar\n' > "$PACKAGE_ROOT/Makefile"

export CARGO="$MOCK_BIN/cargo"
export CARGO_FEATURES=cosmic
prepare_source_package
test -f "$PACKAGE_ROOT/vendor.tar"
tar tf "$PACKAGE_ROOT/vendor.tar" | grep -Fx "vendor/mock-crate/lib.rs"
tar tf "$PACKAGE_ROOT/vendor.tar" | grep -Fx ".cargo/config"
grep -Fx "vendor.tar" "$PACKAGE_ROOT/debian/source/include-binaries"
grep -Fx -- "--extend-diff-ignore=^\\.cargo/config.toml$" "$PACKAGE_ROOT/debian/source/options"
grep -Fx -- "--extend-diff-ignore=^\\.cargo/config$" "$PACKAGE_ROOT/debian/source/options"
grep -F "true|metadata --locked --offline --format-version 1 --no-deps --features cosmic" "$CARGO_CAPTURE"
grep -F "true|vendor --locked --offline vendor" "$CARGO_CAPTURE"

rm -rf "$PACKAGE_ROOT/vendor" "$PACKAGE_ROOT/.cargo"
prepare_binary_package
test -f "$PACKAGE_ROOT/vendor/mock-crate/lib.rs"
test -f "$PACKAGE_ROOT/.cargo/config"
test "$(cat "$PACKAGE_ROOT/.cargo/config")" = '[source.vendored-sources]'
[[ "$VOULAGE_DEBUILD_NO_PRE_CLEAN" == true ]]

rm -rf "$PACKAGE_ROOT/vendor" "$PACKAGE_ROOT/.cargo"
rm -f "$PACKAGE_ROOT/vendor.tar"
if prepare_binary_package; then
  echo 'prepare_binary_package unexpectedly succeeded without vendor.tar' >&2
  exit 1
fi
test ! -e "$PACKAGE_ROOT/vendor"
[[ "$VOULAGE_DEBUILD_NO_PRE_CLEAN" == false ]]

printf 'not a tar archive\n' > "$PACKAGE_ROOT/vendor.tar"
if prepare_binary_package; then
  echo 'prepare_binary_package unexpectedly succeeded with a corrupt archive' >&2
  exit 1
fi
test ! -e "$PACKAGE_ROOT/vendor"
[[ "$VOULAGE_DEBUILD_NO_PRE_CLEAN" == false ]]

printf 'test-ext-debian: changelog identity, pre-source vendoring, and binary restore passed\n'
