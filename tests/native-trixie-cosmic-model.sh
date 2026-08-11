#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  printf 'usage: %s [package-model.json]\n' "$0" >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
model_file="$repo_root/stage/unstable/debian/trixie/package-model.json"
if [ "$#" -eq 1 ]; then
  model_file="$1"
fi
verify_remote_refs="${VERIFY_REMOTE_REFS-0}"
case "$verify_remote_refs" in
  0|1) ;;
  *)
    printf 'VERIFY_REMOTE_REFS must be 0 or 1, got: %s\n' "$verify_remote_refs" >&2
    exit 2
    ;;
esac
tmp_root="$(mktemp -d)"
trap 'rm -rf -- "$tmp_root"' EXIT

expected_ref_for() {
  case "$1" in
    cosmic-session) printf '%s\n' '83a8b7c0021f19e714dd09eea3aba2e48a492e6a' ;;
    cosmic-settings-daemon) printf '%s\n' '04bdcce710e48aa1b8480780a981f0bf0302f901' ;;
    *) printf 'unknown package: %s\n' "$1" >&2; return 1 ;;
  esac
}

expected_source_for() {
  case "$1" in
    cosmic-session) printf '%s\n' 'https://github.com/Rahul-2k4/cosmic-session.git' ;;
    cosmic-settings-daemon) printf '%s\n' 'https://github.com/Rahul-2k4/cosmic-settings-daemon.git' ;;
    *) printf 'unknown package: %s\n' "$1" >&2; return 1 ;;
  esac
}

verify_remote_ref() {
  local package_name="$1"
  local source_url="$2"
  local expected_ref="$3"
  local temp_repo="$tmp_root/$package_name"
  local resolved_commit

  mkdir -p "$temp_repo"
  git -C "$temp_repo" init -q
  if ! git -C "$temp_repo" fetch --no-tags --depth=1 "$source_url" "$expected_ref" \
      2>"$temp_repo/fetch-error.log"; then
    printf 'native Trixie remote check failed for %s: could not fetch %s at %s: %s\n' \
      "$package_name" "$source_url" "$expected_ref" "$(tr '\n' ' ' < "$temp_repo/fetch-error.log")" >&2
    return 1
  fi

  if ! resolved_commit="$(git -C "$temp_repo" rev-parse --verify 'FETCH_HEAD^{commit}')"; then
    printf 'native Trixie remote check failed for %s: fetched ref %s is not a commit\n' \
      "$package_name" "$expected_ref" >&2
    return 1
  fi
  if [ "$resolved_commit" != "$expected_ref" ]; then
    printf 'native Trixie remote check failed for %s: expected %s, got %s\n' \
      "$package_name" "$expected_ref" "$resolved_commit" >&2
    return 1
  fi
  printf 'native Trixie remote ref verified for %s at %s\n' "$package_name" "$expected_ref"
}

if [ ! -f "$model_file" ]; then
  printf 'native Trixie model check failed: model file is missing: %s\n' "$model_file" >&2
  exit 1
fi

jq -e '.packages | type == "object"' "$model_file" >/dev/null

for package_name in cosmic-session cosmic-settings-daemon; do
  expected_ref="$(expected_ref_for "$package_name")"
  expected_source="$(expected_source_for "$package_name")"
  if ! actual_fields="$(jq -er --arg package_name "$package_name" '
    .packages[$package_name] as $package
    | if ($package | type) != "object" then
        error("missing package object")
      elif ($package | has("ref") | not) then
        error("missing ref")
      elif ($package | has("source") | not) then
        error("missing source")
      elif (($package.ref | type) != "string") then
        error("ref must be a string")
      elif (($package.ref | test("^[0-9a-f]{40}$")) | not) then
        error("ref must be an immutable 40-hex commit SHA")
      elif (($package.source | type) != "string") then
        error("source must be a string")
      elif (($package.source | test("^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$")) | not) then
        error("source must be a non-empty URL")
      else
        [$package.ref, $package.source] | @tsv
      end
  ' "$model_file")"; then
    printf 'native Trixie model check failed for %s in %s\n' "$package_name" "$model_file" >&2
    exit 1
  fi

  IFS=$'\t' read -r actual_ref actual_source <<< "$actual_fields"
  [ "$actual_ref" = "$expected_ref" ] || {
    printf 'native Trixie ref mismatch for %s: expected %s, got %s\n' \
      "$package_name" "$expected_ref" "$actual_ref" >&2
    exit 1
  }
  [ "$actual_source" = "$expected_source" ] || {
    printf 'native Trixie source mismatch for %s: expected %s, got %s\n' \
      "$package_name" "$expected_source" "$actual_source" >&2
    exit 1
  }

  if [ "$verify_remote_refs" = "1" ]; then
    verify_remote_ref "$package_name" "$actual_source" "$actual_ref"
  fi
done

if [ "$verify_remote_refs" = "1" ]; then
  printf 'native Trixie COSMIC refs, sources, metadata, and remote resolution passed\n'
else
  printf 'native Trixie COSMIC refs, sources, and metadata passed (offline)\n'
fi
