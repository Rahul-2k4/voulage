#!/usr/bin/env bash
set -euo pipefail

model="${1:-stage/unstable/package-model.json}"
python3 - "$model" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    model = json.load(handle)

packages = model.get("packages", model)
expected = {
    "regolith-session": (
        "https://github.com/Rahul-2k4/regolith-session.git",
        "831596f8f054a6904b0846b6a899912c6c13d465",
    ),
    "regolith-inputd": (
        "https://github.com/Rahul-2k4/regolith-inputd.git",
        "c658754ec10ac75422cba8e1c3517bba6075795f",
    ),
    "regolith-displayd": (
        "https://github.com/Rahul-2k4/regolith-displayd.git",
        "5a7c86ea791b9befbd8b44489f8a405cfbad926e",
    ),
}

for name, (source, ref) in expected.items():
    package = packages[name]
    assert package["source"] == source, (name, package["source"])
    assert package["ref"] == ref, (name, package["ref"])
    assert len(ref) == 40 and all(char in "0123456789abcdef" for char in ref), name
PY
