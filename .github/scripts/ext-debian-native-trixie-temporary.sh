#!/bin/bash

# Temporary native Trixie evidence build. Keep Debian packaging behavior,
# source validation, and local unsigned build flags in ext-debian.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ext-debian.sh"

# Debian's Trixie CI image has an older system Rust than some COSMIC sources.
# Keep the source checkout authoritative: select the channel declared by the
# package, install it reproducibly through rustup, and pass the real toolchain
# bin directory through debuild's environment boundary.
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
    echo "rustup is required to build the declared Rust toolchain ($toolchain)" >&2
    return 1
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
