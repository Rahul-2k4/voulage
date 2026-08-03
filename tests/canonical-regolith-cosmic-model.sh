#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
model_file="$repo_root/stage/unstable/ubuntu/resolute/package-model.json"
packages=(regolith-session regolith-inputd regolith-displayd)
remote_tmp_dirs=()
jq_tmp_files=()

cleanup_tmp() {
  if ((${#remote_tmp_dirs[@]} > 0)); then
    rm -rf -- "${remote_tmp_dirs[@]}"
  fi
  if ((${#jq_tmp_files[@]} > 0)); then
    rm -f -- "${jq_tmp_files[@]}"
  fi
}

trap cleanup_tmp EXIT

expected_ref_for() {
  case "$1" in
    regolith-session) printf '%s\n' '54109e2b57940afecee1b24540be41ea936587aa' ;;
    regolith-inputd) printf '%s\n' 'e612e20bba09d9d0a722c141b1df2be513c5abf6' ;;
    regolith-displayd) printf '%s\n' 'e8cc8e07e41e7b0b6dc2f1c9a7765876dfe0c46c' ;;
    *) printf 'unknown package: %s\n' "$1" >&2; return 1 ;;
  esac
}

expected_source_for() {
  case "$1" in
    regolith-session) printf '%s\n' 'https://github.com/Rahul-2k4/regolith-session.git' ;;
    regolith-inputd) printf '%s\n' 'https://github.com/Rahul-2k4/regolith-inputd.git' ;;
    regolith-displayd) printf '%s\n' 'https://github.com/Rahul-2k4/regolith-displayd.git' ;;
    *) printf 'unknown package: %s\n' "$1" >&2; return 1 ;;
  esac
}

verify_remote_ref() {
  local package_name="$1"
  local source_url="$2"
  local expected_ref="$3"
  local temp_repo
  local error_detail
  local resolved_commit
  local required_path

  if ! temp_repo="$(mktemp -d)"; then
    printf 'canonical remote check failed for %s: could not create temporary repository\n'       "$package_name" >&2
    return 1
  fi
  remote_tmp_dirs+=("$temp_repo")

  if ! git -C "$temp_repo" init -q; then
    printf 'canonical remote check failed for %s: could not initialise temporary repository %s\n'       "$package_name" "$temp_repo" >&2
    return 1
  fi

  if ! git -C "$temp_repo" fetch --no-tags --depth=1 "$source_url" "$expected_ref"     2>"$temp_repo/fetch-error.log"; then
    error_detail="$(tr "\n" " " < "$temp_repo/fetch-error.log")"
    printf 'canonical remote check failed for %s: could not fetch %s at %s: %s\n'       "$package_name" "$source_url" "$expected_ref" "$error_detail" >&2
    return 1
  fi

  if ! resolved_commit="$(git -C "$temp_repo" rev-parse --verify "$expected_ref^{commit}" 2>"$temp_repo/rev-error.log")"; then
    error_detail="$(tr "\n" " " < "$temp_repo/rev-error.log")"
    printf 'canonical remote check failed for %s: fetched ref %s is not a commit: %s\n'       "$package_name" "$expected_ref" "$error_detail" >&2
    return 1
  fi

  if [[ "$resolved_commit" != "$expected_ref" ]]; then
    printf 'canonical remote check failed for %s: fetched commit mismatch, expected %s, got %s\n'       "$package_name" "$expected_ref" "$resolved_commit" >&2
    return 1
  fi

  for required_path in debian/control debian/changelog debian/source/format; do
    if ! git -C "$temp_repo" cat-file -e "$expected_ref:$required_path"       2>"$temp_repo/path-error.log"; then
      error_detail="$(tr "\n" " " < "$temp_repo/path-error.log")"
      printf 'canonical remote check failed for %s: %s is missing at %s: %s\n'         "$package_name" "$required_path" "$expected_ref" "$error_detail" >&2
      return 1
    fi
  done

  printf 'canonical remote ref verified for %s at %s\n' "$package_name" "$expected_ref"
}

for package_name in "${packages[@]}"; do
  if [[ ! -f "$model_file" ]]; then
    printf 'canonical model check failed for %s: model file is missing: %s\n' "$package_name" "$model_file" >&2
    exit 1
  fi

  expected_ref="$(expected_ref_for "$package_name")"
  expected_source="$(expected_source_for "$package_name")"
  if ! jq_error_file="$(mktemp)"; then
    printf 'canonical model check failed for %s: could not create jq error log\n' "$package_name" >&2
    exit 1
  fi
  jq_tmp_files+=("$jq_error_file")

  if ! actual_fields="$(jq -er --arg package_name "$package_name" '
    .packages[$package_name] as $package
    | if ($package | type) != "object" then
        error("missing package object")
      elif ($package | has("ref") | not) then
        error("missing ref")
      elif ($package | has("source") | not) then
        error("missing source")
      else
        [$package.ref, $package.source] | @tsv
      end
  ' "$model_file" 2>"$jq_error_file")"; then
    jq_error="$(tr "\n" " " < "$jq_error_file")"
    printf 'canonical model check failed for %s: could not read ref/source from %s: %s\n'       "$package_name" "$model_file" "$jq_error" >&2
    exit 1
  fi
  rm -f "$jq_error_file"

  IFS=$'\t' read -r actual_ref actual_source <<< "$actual_fields"

  if [[ "$actual_ref" != "$expected_ref" ]]; then
    printf 'canonical ref mismatch for %s: expected %s, got %s\n'       "$package_name" "$expected_ref" "$actual_ref" >&2
    exit 1
  fi

  if [[ "$actual_source" != "$expected_source" ]]; then
    printf 'canonical source mismatch for %s: expected %s, got %s\n'       "$package_name" "$expected_source" "$actual_source" >&2
    exit 1
  fi

  if [[ "${VERIFY_REMOTE_REFS:-0}" == "1" ]]; then
    verify_remote_ref "$package_name" "$actual_source" "$actual_ref"
  fi
done

if [[ "${VERIFY_REMOTE_REFS:-0}" == "1" ]]; then
  printf 'canonical Voulage COSMIC refs, sources, and remote metadata passed\n'
else
  printf 'canonical Voulage COSMIC refs and sources passed (offline)\n'
fi
