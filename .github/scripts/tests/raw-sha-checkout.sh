#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
SOURCE_REPO="$TMP_DIR/source"
BUILD_DIR="$TMP_DIR/build"
mkdir -p "$SOURCE_REPO" "$BUILD_DIR"
git -C "$SOURCE_REPO" init -q -b main
git -C "$SOURCE_REPO" config user.email test@example.invalid
git -C "$SOURCE_REPO" config user.name test
printf 'source\n' > "$SOURCE_REPO/file"
git -C "$SOURCE_REPO" add file
git -C "$SOURCE_REPO" commit -q -m initial
SHA=$(git -C "$SOURCE_REPO" rev-parse HEAD)
git -C "$SOURCE_REPO" tag v1
source "$SCRIPT_ROOT/ext-git.sh"
PACKAGE_NAME=sha-package
PACKAGE_URL="$SOURCE_REPO"
PACKAGE_REF="$SHA"
PKG_BUILD_PATH="$BUILD_DIR"
checkout
test "$(git -C "$BUILD_DIR/$PACKAGE_NAME" rev-parse HEAD)" = "$SHA"
test "$(git -C "$BUILD_DIR/$PACKAGE_NAME" symbolic-ref --short -q HEAD || true)" = ""
PACKAGE_NAME=branch-package
PACKAGE_REF=main
checkout
test "$(git -C "$BUILD_DIR/$PACKAGE_NAME" symbolic-ref --short HEAD)" = main
MODEL_REPO="$TMP_DIR/model"
MANIFEST_DIR="$TMP_DIR/manifests"
mkdir -p "$MODEL_REPO/stage" "$MODEL_REPO/.github/scripts" "$MANIFEST_DIR"
cp "$SCRIPT_ROOT/main.sh" "$MODEL_REPO/main.sh"
cp "$SCRIPT_ROOT/ext-git.sh" "$MODEL_REPO/.github/scripts/ext-git.sh"
printf '#!/bin/bash\n' > "$MODEL_REPO/extension.sh"
cat > "$MODEL_REPO/stage/package-model.json" <<EOF
{"packages":{"sha-package":{"source":"$SOURCE_REPO","ref":"$SHA"}}}
EOF
bash "$MODEL_REPO/main.sh" check --extension "$MODEL_REPO/extension.sh" --git-repo-path "$MODEL_REPO" --manifest-path "$MANIFEST_DIR" --pkg-build-path "$TMP_DIR/main-build" --pkg-publish-path "$TMP_DIR/main-publish" --distro ubuntu --codename resolute --stage unstable --suite unstable --component main --arch amd64 >/dev/null
grep -Fq "sha-package $SOURCE_REPO $SHA $SHA" "$MANIFEST_DIR/next-manifest.txt"
printf 'raw SHA checkout and manifest tests passed\n'

INVALID_SHA=0000000000000000000000000000000000000000
cat > "$MODEL_REPO/stage/package-model.json" <<EOF2
{"packages":{"invalid-sha-package":{"source":"$SOURCE_REPO","ref":"$INVALID_SHA"}}}
EOF2
if bash "$MODEL_REPO/main.sh" check --extension "$MODEL_REPO/extension.sh" --git-repo-path "$MODEL_REPO" --manifest-path "$MANIFEST_DIR/invalid" --pkg-build-path "$TMP_DIR/main-build-invalid" --pkg-publish-path "$TMP_DIR/main-publish-invalid" --distro ubuntu --codename resolute --stage unstable --suite unstable --component main --arch amd64 >"$TMP_DIR/invalid-sha.log" 2>&1; then
  echo "invalid SHA was accepted" >&2
  exit 1
fi
grep -Fq "SHA $INVALID_SHA was not found at source URL $SOURCE_REPO" "$TMP_DIR/invalid-sha.log"
