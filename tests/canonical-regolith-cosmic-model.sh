#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
model_file="$repo_root/stage/unstable/ubuntu/resolute/package-model.json"

declare -A expected_refs=(
  [regolith-session]="6b5777d9f6ee2e292248ed501f4f4195522fb3ac"
  [regolith-inputd]="e612e20bba09d9d0a722c141b1df2be513c5abf6"
  [regolith-displayd]="c4d4edba2f6ff8c1db8f006329fa6bfef01de63b"
)

for package_name in "${!expected_refs[@]}"; do
  expected_ref="${expected_refs[$package_name]}"
  actual_ref="$(jq -er --arg package_name "$package_name" '.packages[$package_name].ref' "$model_file")"

  if [[ "$actual_ref" != "$expected_ref" ]]; then
    printf 'canonical ref mismatch: %s: expected %s, got %s\n' \
      "$package_name" "$expected_ref" "$actual_ref" >&2
    exit 1
  fi
done

printf 'canonical Voulage COSMIC refs passed\n'
