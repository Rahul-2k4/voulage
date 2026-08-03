#!/usr/bin/env bash
set -euo pipefail

if (($# > 1)); then
  printf 'usage: %s [package-model.json]\n' "$0" >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
model_file="${1:-$repo_root/stage/unstable/ubuntu/resolute/package-model.json}"
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

read_model_field() {
  local package_name="$1"
  local output_var="$2"
  local error_file
  local fields
  local error_detail

  if ! error_file="$(mktemp)"; then
    printf 'model integrity check failed for %s: could not create jq error log\n' "$package_name" >&2
    return 1
  fi
  jq_tmp_files+=("$error_file")

  if ! fields="$(jq -er --arg package_name "$package_name" '
    .packages[$package_name] as $package
    | if ($package | type) != "object" then
        error("package entry must be an object")
      elif (($package.source | type) != "string") then
        error("source must be a string")
      elif (($package.source | length) == 0) then
        error("source must be non-empty")
      elif (($package.source | test("^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$")) | not) then
        error("source must be a non-empty URL")
      elif (($package.ref | type) != "string") then
        error("ref must be a string")
      elif (($package.ref | length) == 0) then
        error("ref must be non-empty")
      else
        [$package.source, $package.ref] | @tsv
      end
  ' "$model_file" 2>"$error_file")"; then
    error_detail="$(tr "\n" " " < "$error_file")"
    printf 'model integrity check failed for %s in %s: %s\n' "$package_name" "$model_file" "$error_detail" >&2
    return 1
  fi

  printf -v "$output_var" '%s' "$fields"
}

verify_remote_ref() {
  local package_name="$1"
  local source_url="$2"
  local requested_ref="$3"
  local temp_repo
  local error_detail
  local resolved_commit

  if ! temp_repo="$(mktemp -d)"; then
    printf 'model remote check failed for %s: could not create temporary repository\n' "$package_name" >&2
    return 1
  fi
  remote_tmp_dirs+=("$temp_repo")

  if ! git -C "$temp_repo" init -q; then
    printf 'model remote check failed for %s: could not initialise temporary repository\n' "$package_name" >&2
    return 1
  fi

  if ! git -C "$temp_repo" fetch --no-tags --depth=1 "$source_url" "$requested_ref" 2>"$temp_repo/fetch-error.log"; then
    error_detail="$(tr "\n" " " < "$temp_repo/fetch-error.log")"
    printf 'model remote check failed for %s: could not fetch %s at %s: %s\n' "$package_name" "$source_url" "$requested_ref" "$error_detail" >&2
    return 1
  fi

  if ! resolved_commit="$(git -C "$temp_repo" rev-parse --verify 'FETCH_HEAD^{commit}' 2>"$temp_repo/rev-error.log")"; then
    error_detail="$(tr "\n" " " < "$temp_repo/rev-error.log")"
    printf 'model remote check failed for %s: %s at %s did not resolve to a commit: %s\n' "$package_name" "$source_url" "$requested_ref" "$error_detail" >&2
    return 1
  fi

  if [[ "$requested_ref" =~ ^[0-9a-fA-F]{40}$ ]] && [[ "$resolved_commit" != "$requested_ref" ]]; then
    printf 'model remote check failed for %s: expected SHA %s, fetched %s\n' "$package_name" "$requested_ref" "$resolved_commit" >&2
    return 1
  fi

  printf 'model remote ref verified for %s: %s at %s\n' "$package_name" "$requested_ref" "$resolved_commit"
}

if [[ ! -f "$model_file" ]]; then
  printf 'model integrity check failed: model file is missing: %s\n' "$model_file" >&2
  exit 1
fi

if ! model_error_file="$(mktemp)"; then
  printf 'model integrity check failed for %s: could not create jq error log\n' "$model_file" >&2
  exit 1
fi
jq_tmp_files+=("$model_error_file")

if ! model_packages="$(jq -er '
  .packages
  | if type != "object" then error("packages must be an object") else keys[] end
' "$model_file" 2>"$model_error_file")"; then
  model_error="$(tr "\n" " " < "$model_error_file")"
  printf 'model integrity check failed for %s: %s\n' "$model_file" "$model_error" >&2
  exit 1
fi

while IFS= read -r package_name; do
  [[ -n "$package_name" ]] || continue
  package_fields=""
  read_model_field "$package_name" package_fields
  IFS=$'\t' read -r source_url requested_ref <<< "$package_fields"

  if [[ "${VERIFY_REMOTE_REFS:-0}" == "1" ]]; then
    verify_remote_ref "$package_name" "$source_url" "$requested_ref"
  fi
done <<< "$model_packages"

if [[ "${VERIFY_REMOTE_REFS:-0}" == "1" ]]; then
  printf 'model integrity and remote resolution passed: %s\n' "$model_file"
else
  printf 'model integrity passed (offline): %s\n' "$model_file"
fi
