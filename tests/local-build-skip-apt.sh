#!/usr/bin/env bash
set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

package_dir="$test_root/package"
log_file="$test_root/commands.log"
mkdir -p "$package_dir"

cat > "$test_root/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${VOULAGE_TEST_LOG:?}"
EOF

cat > "$test_root/debuild" <<'EOF'
#!/usr/bin/env bash
printf 'debuild %s\n' "$*" >> "${VOULAGE_TEST_LOG:?}"
EOF

chmod +x "$test_root/sudo" "$test_root/debuild"

run_build_src_package() {
  : > "$log_file"
  export VOULAGE_TEST_LOG="$log_file"
  export PKG_BUILD_PATH="$test_root"
  export PACKAGE_NAME=package
  export LOCAL_BUILD=true
  export PATH="$test_root:$PATH"

  # The extension supplies this helper in the real Voulage build.
  sanitize_git() { :; }
  source .github/scripts/ext-debian.sh
  build_src_package
}

run_build_src_package
grep -Fqx 'sudo apt update' "$log_file"
grep -Fqx 'sudo apt build-dep -y .' "$log_file"
grep -Fqx 'debuild -S -sa -us -uc' "$log_file"

VOULAGE_SKIP_APT_BUILD_DEP=true run_build_src_package
if grep -q '^sudo ' "$log_file"; then
  echo 'apt commands were not skipped' >&2
  exit 1
fi
grep -Fqx 'debuild -S -sa -us -uc' "$log_file"

echo 'local-build apt gate tests passed'
