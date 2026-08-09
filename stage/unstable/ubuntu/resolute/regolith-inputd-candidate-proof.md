# regolith-inputd Voulage lintian-clean candidate proof

- Candidate branch: codex/voulage-inputd-lintian-clean-20260810
- Candidate base: 5d8a9046d6eef7b4fdfcf5b5e1a14cdbac312f98
- Package: regolith-inputd
- Source: https://github.com/Rahul-2k4/regolith-inputd.git
- Exact source ref: b380c9aa8f75b8d2da657b58b459a861c3a5d56b
- Target: Ubuntu Resolute amd64, stage unstable
- Model: stage/unstable/package-model.json

## Validation

- jq empty stage/unstable/package-model.json: passed.
- Merged model (stage root + unstable + unstable/ubuntu/resolute): passed; regolith-inputd resolves to the exact source URL and ref above.
- bash -n local-build.sh ext-debian.sh ext-git.sh main.sh: passed.
- git diff --check: passed.

## Package generation

Not run in this candidate update; package generation and lintian output are to be verified separately.
