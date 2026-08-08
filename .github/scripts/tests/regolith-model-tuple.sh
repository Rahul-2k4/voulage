#!/bin/sh
set -eu

model=${1:?model path required}
session_ref=${2:?session ref required}
inputd_ref=${3:?inputd ref required}
displayd_ref=${4:?displayd ref required}

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' 'jq is required' >&2
  exit 2
}

actual=$(jq -r '[.packages["regolith-session"].ref, .packages["regolith-inputd"].ref, .packages["regolith-displayd"].ref] | @tsv' "$model")
expected=$(printf '%s\t%s\t%s\n' "$session_ref" "$inputd_ref" "$displayd_ref")

if [ "$actual" != "$expected" ]; then
  printf 'regolith model tuple mismatch\nexpected: %s\nactual:   %s\n' "$expected" "$actual" >&2
  exit 1
fi

printf 'regolith model tuple: %s\n' "$actual"
