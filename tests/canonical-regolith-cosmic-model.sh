#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
model_file="$repo_root/stage/unstable/ubuntu/resolute/package-model.json"
packages=(regolith-session regolith-inputd regolith-displayd)

expected_ref_for() {
  case "$1" in
    regolith-session) printf '%s\n' '6b5777d9f6ee2e292248ed501f4f4195522fb3ac' ;;
    regolith-inputd) printf '%s\n' 'e612e20bba09d9d0a722c141b1df2be513c5abf6' ;;
    regolith-displayd) printf '%s\n' 'c4d4edba2f6ff8c1db8f006329fa6bfef01de63b' ;;
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

for package_name in "${packages[@]}"; do
  if [[ ! -f "$model_file" ]]; then
    printf 'canonical model check failed for %s: model file is missing: %s\n' "$package_name" "$model_file" >&2
    exit 1
  fi

  expected_ref="$(expected_ref_for "$package_name")"
  expected_source="$(expected_source_for "$package_name")"
  jq_error_file="$(mktemp)"
  trap 'rm -f "$jq_error_file"' EXIT

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
    printf 'canonical model check failed for %s: could not read ref/source from %s: %s\n' "$package_name" "$model_file" "$jq_error" >&2
    exit 1
  fi
  rm -f "$jq_error_file"
  trap - EXIT

  IFS=$'\t' read -r actual_ref actual_source <<< "$actual_fields"

  if [[ "$actual_ref" != "$expected_ref" ]]; then
    printf 'canonical ref mismatch for %s: expected %s, got %s\n' "$package_name" "$expected_ref" "$actual_ref" >&2
    exit 1
  fi

  if [[ "$actual_source" != "$expected_source" ]]; then
    printf 'canonical source mismatch for %s: expected %s, got %s\n' "$package_name" "$expected_source" "$actual_source" >&2
    exit 1
  fi
done

printf 'canonical Voulage COSMIC refs and sources passed\n'
