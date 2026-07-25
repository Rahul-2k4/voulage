#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/package"
source "$SCRIPT_ROOT/ext-debian.sh"
cd "$TMP_DIR/package"

printf '[package]\nedition = "2024"\n' > Cargo.toml
unset RUSTUP_TOOLCHAIN CARGO RUSTC VOULAGE_DEFAULT_RUST_TOOLCHAIN
prepare_rust_toolchain
test -n "${RUSTUP_TOOLCHAIN:-}"
case "$RUSTUP_TOOLCHAIN" in 1.93* ) ;; *) exit 1 ;; esac

printf '[package]\nrust-version = "1.93"\nedition = "2021"\n' > Cargo.toml
printf '%s\n' '1.92' > rust-toolchain
unset RUSTUP_TOOLCHAIN
prepare_rust_toolchain
test -z "${RUSTUP_TOOLCHAIN:-}"
rm rust-toolchain

export RUSTUP_TOOLCHAIN=1.92 CARGO=/custom/cargo RUSTC=/custom/rustc
prepare_rust_toolchain
test "$RUSTUP_TOOLCHAIN" = 1.92
test "$CARGO" = /custom/cargo
test "$RUSTC" = /custom/rustc

unset RUSTUP_TOOLCHAIN CARGO RUSTC
printf '[package]\nedition = "2024"\n' > Cargo.toml
export VOULAGE_DEFAULT_RUST_TOOLCHAIN=9.99
prepare_rust_toolchain
test -z "${RUSTUP_TOOLCHAIN:-}"
printf 'ext-debian Rust toolchain tests passed\n'
