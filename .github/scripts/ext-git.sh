#!/bin/bash

resolve_checkout_mode() {
  if git ls-remote --exit-code --heads origin "$PACKAGE_REF" >/dev/null 2>&1; then
    CHECKOUT_MODE="branch"
    CHECKOUT_REF="refs/heads/$PACKAGE_REF"
    return 0
  fi

  if git ls-remote --exit-code --tags origin "$PACKAGE_REF" >/dev/null 2>&1; then
    CHECKOUT_MODE="tag"
    CHECKOUT_REF="refs/tags/$PACKAGE_REF"
    return 0
  fi

  if printf '%s' "$PACKAGE_REF" | grep -Eq '^[0-9a-fA-F]{40}$'; then
    CHECKOUT_MODE="commit"
    CHECKOUT_REF="$PACKAGE_REF"
    return 0
  fi

  CHECKOUT_MODE="ref"
  CHECKOUT_REF="$PACKAGE_REF"
}

checkout_requested_ref() {
  git fetch --depth 1 origin "$CHECKOUT_REF"

  case "$CHECKOUT_MODE" in
    branch)
      git checkout -B "$PACKAGE_REF" --track "origin/$PACKAGE_REF"
      ;;
    tag|commit|ref)
      git checkout --detach FETCH_HEAD
      ;;
  esac
}

checkout() {
  set -e

  echo "::group::Cloning $PACKAGE_NAME on ref: $PACKAGE_REF"

  if [ -z "$PACKAGE_URL" ]; then
    echo "Error: package model is invalid. Model field 'source' undefined, aborting."
    exit 1
  fi

  if [ -d "$PKG_BUILD_PATH/$PACKAGE_NAME" ]; then
    echo "Deleting existing repo, $PACKAGE_NAME"
    rm -Rfv "${PKG_BUILD_PATH:?}/$PACKAGE_NAME"
  fi

  if [ ! -d "$PKG_BUILD_PATH" ]; then
    echo "Creating build directory $PKG_BUILD_PATH"

    mkdir -p "$PKG_BUILD_PATH" || {
      echo "Error: failed to create build dir $PKG_BUILD_PATH, aborting."
      exit 1
    }
  fi

  cd "$PKG_BUILD_PATH" || exit
  git clone --no-checkout "$PACKAGE_URL" "$PACKAGE_NAME"
  cd "$PACKAGE_NAME" || exit
  resolve_checkout_mode
  checkout_requested_ref
  git submodule sync --recursive
  git submodule update --init --recursive --checkout

  cd .. || exit

  cd - >/dev/null 2>&1 || exit
  echo "::endgroup::"
}

sanitize_git() {
  if [ -d ".github" ]; then
    rm -Rf .github
    echo "Removed $(pwd).github directory before building to appease debuild."
  fi
  if [ -d ".git" ]; then
    rm -Rf .git
    echo "Removed $(pwd).git directory before building to appease debuild."
  fi
}
