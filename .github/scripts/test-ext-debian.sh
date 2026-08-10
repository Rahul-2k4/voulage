#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PACKAGE_ROOT="$TMP_DIR/package"
MOCK_BIN="$TMP_DIR/bin"
CAPTURE="$TMP_DIR/dch-capture"
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

source "$REPO_ROOT/.github/scripts/ext-debian.sh"
export PATH="$MOCK_BIN:$PATH"
export PKG_BUILD_PATH="$TMP_DIR"
export PACKAGE_NAME=package
export CODENAME=resolute
export DCH_CAPTURE="$CAPTURE"

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

printf 'test-ext-debian: changelog identity fallback passed\n'
