#!/usr/bin/env bash
set -euo pipefail

model="${1:-stage/unstable/package-model.json}"
python3 - "$model" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    model = json.load(handle)

package = model.get("packages", model)["regolith-session"]
assert package["source"] == "https://github.com/Rahul-2k4/regolith-session.git"
assert package["ref"] == "3523047b7c2f7a2ca4e3d1fd800c10c342ca7a19"
PY
