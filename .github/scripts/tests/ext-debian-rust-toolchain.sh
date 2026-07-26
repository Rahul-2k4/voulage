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
unset DEBUILD_PREPEND_PATH RUSTUP_TOOLCHAIN CARGO RUSTC VOULAGE_DEFAULT_RUST_TOOLCHAIN
printf '[package]
edition = "2024"
' > Cargo.toml
prepare_rust_toolchain
prepare_debuild_path_args debuild_path_args
rust_bin=$(dirname "$(rustup which --toolchain "$RUSTUP_TOOLCHAIN" rustc)")
test "${debuild_path_args[0]}" = "--prepend-path=$rust_bin:$HOME/.cargo/bin"
export DEBUILD_PREPEND_PATH=/custom/prepend
prepare_debuild_path_args debuild_path_args
test "${debuild_path_args[0]}" = "--prepend-path=/custom/prepend:$rust_bin:$HOME/.cargo/bin"
printf '[package]
rust-version = "1.92"
edition = "2021"
' > Cargo.toml
printf '1.92
' > rust-toolchain
unset RUSTUP_TOOLCHAIN DEBUILD_PREPEND_PATH
prepare_debuild_path_args debuild_path_args
rust_bin=$(dirname "$(rustup which rustc)")
test "${debuild_path_args[0]}" = "--prepend-path=$rust_bin:$HOME/.cargo/bin"
rm rust-toolchain
printf 'ext-debian Rust toolchain tests passed\n'
