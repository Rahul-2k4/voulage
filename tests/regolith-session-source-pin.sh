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
        "3523047b7c2f7a2ca4e3d1fd800c10c342ca7a19",
    ),
    "regolith-inputd": (
        "https://github.com/Rahul-2k4/regolith-inputd.git",
        "e32d0497f67fea94fb98f803c406c704191b741c",
    ),
    "regolith-displayd": (
        "https://github.com/Rahul-2k4/regolith-displayd.git",
        "817becd9dc7e6a12f13f3f30f663555212ae78fa",
    ),
    "cosmolith": (
        "https://github.com/Rahul-2k4/cosmolith.git",
        "296d576b8fabaf23535980975cf825337010e4e5",
    ),
}

for name, (source, ref) in expected.items():
    package = packages[name]
    assert package["source"] == source, (name, package["source"])
    assert package["ref"] == ref, (name, package["ref"])
    assert len(ref) == 40 and all(char in "0123456789abcdef" for char in ref), name
PY
