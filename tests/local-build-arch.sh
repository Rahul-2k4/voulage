#!/usr/bin/env bash
set -euo pipefail

script=$(dirname "$0")/../.github/scripts/local-build.sh

"$script" --help >/dev/null
"$script" --arch arm64 --help >/dev/null
