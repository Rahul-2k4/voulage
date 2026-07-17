#!/bin/bash

set -e
set -o errexit
# Extension for Debian repo and package support

#### Debian specific functions

# Update the changelog to specify the target distribution codename
update_changelog() {
  # set -x
  echo "::group::Updating debian/changelog file"
  cd "${PKG_BUILD_PATH:?}/$PACKAGE_NAME"
  version=$(dpkg-parsechangelog --show-field Version)
  source_format="debian/source/format"
  if [ -f "$source_format" ] && grep -Fqx "3.0 (native)" "$source_format"; then
    printf "%s\n" "3.0 (quilt)" > "$source_format"
  fi
  case "$version" in
    *-1regolith-*)
      if [[ "$version" =~ ^(.+)-([0-9]+)-1regolith-.+$ ]]; then
        base_version="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
      else
        base_version="${version%-1regolith-*}-1"
      fi
      ;;
    *)
      if [[ "$version" =~ ^.+-[0-9]+$ ]]; then
        base_version="$version"
      else
        base_version="${version}-1"
      fi
      ;;
  esac
  new_version="${base_version}-1regolith-$CODENAME"
  echo -e "\033[0;34mUpdating changlog to ${new_version} for $CODENAME...\033[0m"
  if [ "$new_version" != "$version" ]; then
    dch --force-distribution --distribution "$CODENAME" --newversion "$new_version" "Automated Voulage release"
  else
    echo -e "\033[0;34mVersion already targets $CODENAME; skipping dch.\033[0m"
  fi

  cd - >/dev/null 2>&1 || exit
  echo "::endgroup::"
}

# Determine if the changelog has the correct distribution codename
dist_valid() {
  cd "${PKG_BUILD_PATH:?}/$PACKAGE_NAME"

  TOP_CHANGELOG_LINE=$(head -n 1 debian/changelog)
  CHANGELOG_DIST=$(echo "$TOP_CHANGELOG_LINE" | cut -d' ' -f3)

  cd - >/dev/null 2>&1

  # echo "Checking $CODENAME and $CHANGELOG_DIST"
  if [[ "$CHANGELOG_DIST" == *"$CODENAME"* ]]; then
    return 0
  else
    return 1
  fi
}

stage_source() {
  echo "::group::Preparing source for $PACKAGE_NAME"
  pushd .

  cd "$PKG_BUILD_PATH/$PACKAGE_NAME" || exit
  debian_package_name=$(dpkg-parsechangelog --show-field Source)
  full_version=$(dpkg-parsechangelog --show-field Version)
  debian_version="${full_version%-*}"
  cd "$PKG_BUILD_PATH" || exit

  echo -e "\033[0;34mGenerating source tarball from git repo\033[0m"
  tar --force-local -c -z -v -f  "${debian_package_name}_${debian_version}.orig.tar.gz" --exclude .git\* --exclude debian "$PACKAGE_NAME"

  if [ "$LOCAL_BUILD" == "false" ]; then
    debian_package_name_indicator="${debian_package_name:0:1}"
    if [ "${debian_package_name:0:3}" == "lib" ]; then
      debian_package_name_indicator="${debian_package_name:0:4}"
    fi

    echo -e "\033[0;34mDownloading existing .orig.tar.gz from archive\033[0m"

    # try to download the .orig.tar.gz from existing archive, and check if they are identical or not
    wget -O "${debian_package_name}_${debian_version}-existing.orig.tar.gz" "http://archive.regolith-desktop.com/$DISTRO/$SUITE/pool/main/${debian_package_name_indicator}/${debian_package_name}/${debian_package_name}_${debian_version}.orig.tar.gz" || true

    if [ -s "${debian_package_name}_${debian_version}-existing.orig.tar.gz" ]; then
      echo -e "\033[0;34mChecking if existing is the same as the one just built...\033[0m"

      tmp=$(mktemp -d)
      mkdir -p "${tmp}/current"
      mkdir -p "${tmp}/existing"

      tar -xzf "${debian_package_name}_${debian_version}.orig.tar.gz" -C "${tmp}/current"
      tar -xzf "${debian_package_name}_${debian_version}-existing.orig.tar.gz" -C "${tmp}/existing"

      if ! diff ${tmp}/current/*/ ${tmp}/existing/*/; then
        # existing .orig.tar.gz file is different that the one we just built
        # keep the one we just built and override push it to the repository.
        rm -f "${debian_package_name}_${debian_version}-existing.orig.tar.gz" || true

        echo "  They are different! Need to rebuild the source."
        echo "SRCLOG:$DISTRO=$CODENAME=$SUITE=${debian_package_name_indicator}=${debian_package_name}=${debian_package_name}_${debian_version}=${debian_package_name}_${debian_version}.orig.tar.gz"
        if [ "$SUITE" == "stable" ]; then
          echo "SRCLOG:$DISTRO=$CODENAME=$COMPONENT=${debian_package_name_indicator}=${debian_package_name}=${debian_package_name}_${debian_version}=${debian_package_name}_${debian_version}.orig.tar.gz"
        fi
      else
        # both .orig.tar.gz files are identical!
        # remove the one we just built and reuse the existing one.
        echo "  They are the same."
        rm -f "${debian_package_name}_${debian_version}.orig.tar.gz" || true
        mv "${debian_package_name}_${debian_version}-existing.orig.tar.gz" "${debian_package_name}_${debian_version}.orig.tar.gz"
      fi
      if [ -n "$tmp" ]; then
        rm -rf "$tmp" || true
      fi
    else
      # there's no existing .orig.tar.gz file! Clean up the empty downloaded file.
      echo "Existing .orig.tar.gz file not found in the archives. Using the one just built."
      rm -f "${debian_package_name}_${debian_version}-existing.orig.tar.gz" || true
      echo "SRCLOG:$DISTRO=$CODENAME=$SUITE=${debian_package_name_indicator}=${debian_package_name}=${debian_package_name}_${debian_version}=${debian_package_name}_${debian_version}.orig.tar.gz"
      if [ "$SUITE" == "stable" ]; then
        echo "SRCLOG:$DISTRO=$CODENAME=$COMPONENT=${debian_package_name_indicator}=${debian_package_name}=${debian_package_name}_${debian_version}=${debian_package_name}_${debian_version}.orig.tar.gz"
      fi
    fi
  fi

  popd
  echo "::endgroup::"
}

build_src_package() {
  set -e

  echo "::group::Building source package $PACKAGE_NAME"
  pushd .
  cd "$PKG_BUILD_PATH/$PACKAGE_NAME" || exit

  echo -e "\033[0;34mSanitizing package folder.\033[0m"
  sanitize_git

  echo -e "\033[0;34mBuilding source package.\033[0m"
  sudo apt update
  sudo apt build-dep -y .

  local deb_build_sign=""
  if [ "$LOCAL_BUILD" == "true" ]; then
    deb_build_sign="-us -uc"
  fi

  local debuild_path_args=()
  if [ -n "$DEBUILD_PREPEND_PATH" ]; then
    debuild_path_args=(--prepend-path="$DEBUILD_PREPEND_PATH")
  fi

  local vendor_tar_marker=false
  local metadata_file
  for metadata_file in debian/rules debian/Makefile Makefile justfile; do
    if [ -f "$metadata_file" ] && grep -Fq "vendor.tar" "$metadata_file"; then
      vendor_tar_marker=true
      break
    fi
  done

  if [ "$vendor_tar_marker" == "true" ]; then
    mkdir -p debian/source
    local include_binaries_tmp
    include_binaries_tmp=$(mktemp debian/source/include-binaries.XXXXXX)
    if [ -f debian/source/include-binaries ]; then
      grep -Fvx "vendor.tar" debian/source/include-binaries > "$include_binaries_tmp" || true
    fi
    printf "%s\n" "vendor.tar" >> "$include_binaries_tmp"
    mv "$include_binaries_tmp" debian/source/include-binaries

    local source_options_tmp
    source_options_tmp=$(mktemp debian/source/options.XXXXXX)
    if [ -f debian/source/options ]; then
      grep -Fvx -e "--extend-diff-ignore=^\\.cargo/config.toml$" -e "--extend-diff-ignore=^\\.cargo/config$" debian/source/options > "$source_options_tmp" || true
    fi
    printf "%s\n" "--extend-diff-ignore=^\\.cargo/config.toml$" >> "$source_options_tmp"
    printf "%s\n" "--extend-diff-ignore=^\\.cargo/config$" >> "$source_options_tmp"
    mv "$source_options_tmp" debian/source/options
  fi

  debuild "${debuild_path_args[@]}" -S -sa $deb_build_sign

  popd
  echo "::endgroup::"
}

build_bin_package() {
  set -e

  echo "::group::Building binary package $PACKAGE_NAME"
  pushd .
  cd "$PKG_BUILD_PATH/$PACKAGE_NAME" || exit

  echo -e "\033[0;34mBuilding binary package.\033[0m"

  local deb_build_sign=""
  if [ "$LOCAL_BUILD" == "true" ]; then
    deb_build_sign="-us -uc"
  fi

  local debuild_path_args=()
  if [ -n "$DEBUILD_PREPEND_PATH" ]; then
    debuild_path_args=(--prepend-path="$DEBUILD_PREPEND_PATH")
  fi

  debuild "${debuild_path_args[@]}" -b -sa $deb_build_sign

  popd
  echo "::endgroup::"
}

publish() {
  echo "::group::Publishing binary and source packages"
  cd "${PKG_BUILD_PATH:?}/$PACKAGE_NAME"
  version=$(dpkg-parsechangelog --show-field Version)
  debian_package_name=$(dpkg-parsechangelog --show-field Source)
  cd "$PKG_BUILD_PATH"

  DEB_SRC_PKG_PATH="$(pwd)/${debian_package_name}_${version}_source.changes"

  if [ ! -f "$DEB_SRC_PKG_PATH" ]; then
    echo -e "\033[0;31m${debian_package_name}_${version}_source.changes not found!\033[0m"
  else
    echo -e "\033[0;34mPublishing source package $debian_package_name into $PKG_PUBLISH_PATH.\033[0m"

    short_version="${version%-*}"

    mkdir -p $PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE

    echo "  Copying ${debian_package_name}_${version}.dsc"
    cp "$(pwd)/${debian_package_name}_${version}.dsc" "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"

    echo "  Copying ${debian_package_name}_${short_version}.orig.tar.gz"
    cp "$(pwd)/${debian_package_name}_${short_version}.orig.tar.gz" "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"

    if [ -f "$(pwd)/${debian_package_name}_${version}.debian.tar.xz" ]; then
      echo "  Copying ${debian_package_name}_${version}.debian.tar.xz"
      cp "$(pwd)/${debian_package_name}_${version}.debian.tar.xz" "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"
    fi
    if [ -f "$(pwd)/${debian_package_name}_${version}.tar.xz" ]; then
      echo "  Copying ${debian_package_name}_${version}.tar.xz"
      cp "$(pwd)/${debian_package_name}_${version}.tar.xz" "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"
    fi
    if [ -f "$(pwd)/${debian_package_name}_${version}.diff.gz" ]; then
      echo "  Copying ${debian_package_name}_${version}.diff.gz"
      cp "$(pwd)/${debian_package_name}_${version}.diff.gz" "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"
    fi

    if [ "$LOCAL_BUILD" == "false" ] && [ "$SUITE" == "stable" ]; then
      mkdir -p "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$COMPONENT"
      cd "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$COMPONENT" >/dev/null 2>&1

      ln "../$SUITE/${debian_package_name}_${version}.dsc" .
      ln "../$SUITE/${debian_package_name}_${short_version}.orig.tar.gz" .

      if [ -f "../$SUITE/${debian_package_name}_${version}.debian.tar.xz" ]; then
        ln "../$SUITE/${debian_package_name}_${version}.debian.tar.xz" .
      fi
      if [ -f "../$SUITE/${debian_package_name}_${version}.tar.xz" ]; then
        ln "../$SUITE/${debian_package_name}_${version}.tar.xz" .
      fi
      if [ -f "../$SUITE/${debian_package_name}_${version}.diff.gz" ]; then
        ln "../$SUITE/${debian_package_name}_${version}.diff.gz" .
      fi

      cd - >/dev/null 2>&1
    fi
  fi

  DEB_CONTROL_FILE="$PKG_BUILD_PATH/$PACKAGE_NAME/debian/control"
  echo -e "\033[0;34mPublishing binary package $debian_package_name into $PKG_PUBLISH_PATH.\033[0m"

  awk '/^Package:/ { package = $2 } /^Architecture:/ { print package, $2 }' "$DEB_CONTROL_FILE" |
    while read -r bin_pkg bin_arch; do
      if [ "$bin_arch" == "all" ]; then
        target_arches=all
      else
        target_arches=$ARCH
      fi

      for target_arch in $target_arches; do
        DEB_BIN_PKG_PATH="$(pwd)/${bin_pkg}_${version}_${target_arch}.deb"

        if [ -f "$DEB_BIN_PKG_PATH" ]; then
          mkdir -p $PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE
          echo "  Copying ${bin_pkg}_${version}_${target_arch}.deb"
          cp "$DEB_BIN_PKG_PATH" "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$SUITE"

          if [ "$LOCAL_BUILD" == "false" ] && [ "$SUITE" == "stable" ]; then
            mkdir -p "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$COMPONENT"
            cd "$PKG_PUBLISH_PATH/$DISTRO/$CODENAME/$COMPONENT" >/dev/null 2>&1
            ln "../$SUITE/${bin_pkg}_${version}_${target_arch}.deb" .
            cd - >/dev/null 2>&1
          fi

          echo "CHLOG:Published ${bin_pkg}_${version}_${target_arch}.deb in $DISTRO/$CODENAME/$STAGE from $PKG_LINE"
        else
          echo -e "\033[0;31m  Package $bin_pkg does not exist for $target_arch.\033[0m"
        fi
      done
    done

  echo "::endgroup::"
}

archive_setup_scripts() {
  # Following allows for internal dependencies

  echo "::group::Setting up archive apt list"
  if [ "$LOCAL_BUILD" == "true" ]; then
    echo -e "\033[0;34mSkipping archive apt setup for local build.\033[0m"
    echo "::endgroup::"
    return 0
  fi

  rm /tmp/Release || true
  wget --timeout=10 --tries=1 -P /tmp "http://archive.regolith-desktop.com/$DISTRO/$SUITE/dists/$CODENAME/Release" || true

  if [ -s /tmp/Release ]; then
    rm /tmp/Release

    local repo_line=""
    if [ "$LOCAL_BUILD" == "false" ] && [ "$SUITE" == "stable" ]; then
      # fixed version component
      repo_line="http://archive.regolith-desktop.com/$DISTRO/$SUITE $CODENAME v$COMPONENT"
    else
      # main component
      repo_line="http://archive.regolith-desktop.com/$DISTRO/$SUITE $CODENAME $COMPONENT"
    fi

    echo -e "\033[0;34mAdding repo to apt: $repo_line\033[0m"
    sudo mkdir -p /etc/apt/keyrings/
    wget -qO - http://archive.regolith-desktop.com/regolith.key | gpg --dearmor | sudo tee /etc/apt/keyrings/regolith.gpg >/dev/null
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/regolith.gpg] $repo_line" | sudo tee /etc/apt/sources.list.d/regolith.list

    sudo apt update
  fi

  if [ -f "/etc/apt/sources.list.d/regolith-local.list" ]; then
    sudo rm /etc/apt/sources.list.d/regolith-local.list
    echo "Cleaned up temp apt repo"
  fi
  echo "::endgroup::"
}

archive_cleanup_scripts() {
  # Remove regolith repo from build system apt config
  echo "::group::Cleaning up archive apt list"
  if [ -f "/etc/apt/sources.list.d/regolith.list" ]; then
    echo "Deleting /etc/apt/sources.list.d/regolith.list file"
    sudo rm -f /etc/apt/sources.list.d/regolith.list || true
  fi
  echo "::endgroup::"
}

# Setup debian repo
setup() {
  source_setup_scripts
  archive_setup_scripts
}
