#!/bin/bash

# Temporary native Trixie evidence build. Keep Debian packaging behavior,
# source validation, and local unsigned build flags in ext-debian.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ext-debian.sh"

# Native CI must use only Debian's configured repositories. This deliberately
# leaves the Debian extension's build, validation, and cleanup functions intact.
archive_setup_scripts() {
  echo "::group::Skipping Regolith apt archive setup"
  echo "Temporary local build: no Regolith apt source, key, or publication is configured."
  echo "::endgroup::"
}
