#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/package"
source "$SCRIPT_ROOT/ext-debian.sh"
cd "$TMP_DIR/package"
printf '[package]\nrust-version = "1.93"\n' > Cargo.toml
unset RUSTUP_TOOLCHAIN CARGO RUSTC
prepare_rust_toolchain
test "${RUSTUP_TOOLCHAIN:-}" = '1.93-x86_64-unknown-linux-gnu' || test "${RUSTUP_TOOLCHAIN:-}" = '1.93.0-x86_64-unknown-linux-gnu'
printf '%s\n' '1.93' > rust-toolchain
unset RUSTUP_TOOLCHAIN
prepare_rust_toolchain
test -z "${RUSTUP_TOOLCHAIN:-}"
rm rust-toolchain
export RUSTUP_TOOLCHAIN=1.92 CARGO=/custom/cargo RUSTC=/custom/rustc
prepare_rust_toolchain
test "$RUSTUP_TOOLCHAIN" = 1.92
test "$CARGO" = /custom/cargo
test "$RUSTC" = /custom/rustc
printf 'ext-debian Rust toolchain tests passed\n'
