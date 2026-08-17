#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../ext-debian.sh"

unset CARGO_FEATURES
prepare_debuild_feature_args feature_args
test "${#feature_args[@]}" -eq 0

export CARGO_FEATURES=cosmic
prepare_debuild_feature_args feature_args
test "${feature_args[0]}" = "-eCARGO_FEATURES=cosmic"

export CARGO_FEATURES=gnome
prepare_debuild_feature_args feature_args
test "${feature_args[0]}" = "-eCARGO_FEATURES=gnome"

printf '%s\n' 'debuild Cargo feature forwarding passed'
