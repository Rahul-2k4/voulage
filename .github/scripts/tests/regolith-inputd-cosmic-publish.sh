#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
SETUP="$REPO_ROOT/stage/unstable/ubuntu/resolute/setup.sh"
MODEL="$REPO_ROOT/stage/unstable/ubuntu/resolute/package-model.json"

test -f "$SETUP"
test -f "$MODEL"

unset CARGO_FEATURES
# The target setup is sourced by Voulage before package builds.
source "$SETUP"
test "${CARGO_FEATURES:-}" = cosmic

grep -Fq '"ref": "3b3309a46c88289783dc7271557743f2e2586b57"' "$MODEL"
grep -Fq '"source": "https://github.com/Rahul-2k4/regolith-inputd.git"' "$MODEL"

printf '%s\n' 'regolith-inputd COSMIC packaging gate passed'
