#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PACKAGE_ROOT="$TMP_DIR/package"
MOCK_BIN="$TMP_DIR/bin"
CAPTURE="$TMP_DIR/dch-capture"
VERSION_FILE="$TMP_DIR/version"
VERSION_CAPTURE="$TMP_DIR/version-capture"
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
cat "$VERSION_FILE"
EOF
cat > "$MOCK_BIN/dch" <<'EOF'
#!/bin/bash
for ((i = 1; i <= $#; i++)); do
  if [ "${!i}" = "--newversion" ]; then
    j=$((i + 1))
    printf '%s\n' "${!j}" >> "$VERSION_CAPTURE"
    printf '%s\n%s\n%s\n' "${DEBFULLNAME-}" "${DEBEMAIL-}" "${EMAIL-}" > "$DCH_CAPTURE"
    exit 0
  fi
done
exit 1
EOF
chmod +x "$MOCK_BIN/dpkg-parsechangelog" "$MOCK_BIN/dch"

source "$REPO_ROOT/.github/scripts/ext-debian.sh"
export PATH="$MOCK_BIN:$PATH"
export PKG_BUILD_PATH="$TMP_DIR"
export PACKAGE_NAME=package
export CODENAME=resolute
export DCH_CAPTURE="$CAPTURE"
export VERSION_FILE
export VERSION_CAPTURE

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
printf '%s\n' '1.2.3-1' > "$VERSION_FILE"
update_changelog
assert_identity 'Regolith Linux' 'regolith.linux@gmail.com'

run_version_case() {
  local input=$1
  local codename=$2
  local expected=$3
  local expected_calls=$4
  printf '%s\n' "$input" > "$VERSION_FILE"
  : > "$VERSION_CAPTURE"
  : > "$CAPTURE"
  CODENAME="$codename" update_changelog
  if [ "$(wc -l < "$VERSION_CAPTURE")" -ne "$expected_calls" ]; then
    printf 'unexpected dch call count for %s\n' "$input" >&2
    return 1
  fi
  if [ "$expected_calls" -eq 1 ]; then
    test "$(cat "$VERSION_CAPTURE")" = "$expected"
  fi
}

run_version_case '0.1.0-1' resolute '0.1.0-1-1regolith-resolute' 1
run_version_case '0.1.0-1-1regolith-resolute' resolute '' 0
run_version_case '0.1.0-1-1regolith-trixie' resolute '0.1.0-1-1regolith-resolute' 1

printf '%s\n' \
  'Source: fixture-package' \
  'Section: misc' \
  'Priority: optional' \
  'Standards-Version: 4.6.0' > "$PACKAGE_ROOT/debian/control"
unset DEBEMAIL DEBFULLNAME EMAIL
update_changelog
assert_identity 'Regolith Linux' 'regolith.linux@gmail.com'

printf 'test-ext-debian: changelog identity fallback passed\n'
