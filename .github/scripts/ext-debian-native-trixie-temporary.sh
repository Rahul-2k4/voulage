#!/bin/bash

# Temporary native Trixie evidence build. Keep Debian packaging behavior,
# source validation, and local unsigned build flags in ext-debian.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ext-debian.sh"

# Debian's Trixie CI image has an older system Rust than some COSMIC sources.
# Keep the source checkout authoritative: select the channel declared by the
# package, install it reproducibly through rustup, and pass the real toolchain
# bin directory through debuild's environment boundary.
bootstrap_rustup() {
  local rustup_target=""
  local installer_url=""
  local checksum_url=""
  local installer_dir=""
  local installer_path=""
  local checksum_path=""
  local expected_checksum=""
  local actual_checksum=""
  local cargo_home="${CARGO_HOME:-$HOME/.cargo}"

  case "$(uname -m)" in
    x86_64) rustup_target="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) rustup_target="aarch64-unknown-linux-gnu" ;;
    *)
      echo "Unsupported architecture for rustup bootstrap: $(uname -m)" >&2
      return 1
      ;;
  esac

  installer_url="https://static.rust-lang.org/rustup/dist/$rustup_target/rustup-init"
  checksum_url="https://static.rust-lang.org/rustup/dist/$rustup_target/rustup-init.sha256"
  installer_dir=$(mktemp -d)
  installer_path="$installer_dir/rustup-init"
  checksum_path="$installer_dir/rustup-init.sha256"

  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$installer_path" "$installer_url"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$checksum_path" "$checksum_url"

  expected_checksum=$(awk 'NF { print $1; exit }' "$checksum_path")
  actual_checksum=$(sha256sum "$installer_path" | awk '{ print $1 }')
  if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]] || [ "$expected_checksum" != "$actual_checksum" ]; then
    echo "rustup-init checksum verification failed" >&2
    rm -rf "$installer_dir"
    return 1
  fi

  chmod 0755 "$installer_path"
  "$installer_path" --profile minimal --default-toolchain none --no-modify-path -y
  rm -rf "$installer_dir"

  export PATH="$cargo_home/bin:$PATH"
  if ! command -v rustup >/dev/null 2>&1; then
    echo "rustup bootstrap completed without installing rustup" >&2
    return 1
  fi
}

prepare_declared_rust_toolchain() {
  local project_root="$1"
  local toolchain_file=""
  local toolchain=""
  local cargo_path=""

  if [ -f "$project_root/rust-toolchain.toml" ]; then
    toolchain_file="$project_root/rust-toolchain.toml"
    toolchain=$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$toolchain_file" | head -n 1)
  elif [ -f "$project_root/rust-toolchain" ]; then
    toolchain_file="$project_root/rust-toolchain"
    toolchain=$(sed -n '1p' "$toolchain_file")
  fi

  if [ -z "$toolchain_file" ]; then
    echo "No source-declared Rust toolchain found in $project_root" >&2
    return 1
  fi
  if [ -z "$toolchain" ] || [[ "$toolchain" =~ [^A-Za-z0-9._+-] ]]; then
    echo "Invalid Rust toolchain declaration in $toolchain_file" >&2
    return 1
  fi
  if ! command -v rustup >/dev/null 2>&1; then
    bootstrap_rustup
  fi

  rustup toolchain install "$toolchain" --profile minimal --no-self-update
  cargo_path=$(rustup which --toolchain "$toolchain" cargo)
  RUSTUP_TOOLCHAIN="$toolchain"
  export RUSTUP_TOOLCHAIN
  DEBUILD_PREPEND_PATH="$(dirname "$cargo_path")"
  export DEBUILD_PREPEND_PATH
}

# ext-debian.sh calls debuild for both source and binary packages. The wrapper
# preserves the selected toolchain across debuild's sanitized environment.
debuild() {
  prepare_declared_rust_toolchain "$(pwd)"
  command debuild --prepend-path="$DEBUILD_PREPEND_PATH" "$@"
}

# Native CI must use only Debian's configured repositories. This deliberately
# leaves the Debian extension's build, validation, and cleanup functions intact.
archive_setup_scripts() {
  echo "::group::Skipping Regolith apt archive setup"
  echo "Temporary local build: no Regolith apt source, key, or publication is configured."
  echo "::endgroup::"
}
