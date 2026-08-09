# regolith-inputd Voulage candidate proof

- Candidate branch: codex/voulage-inputd-candidate-20260810
- Candidate base: db0ff7bca46e10fb69a57cbd795bea23a73c1a82
- Package: regolith-inputd
- Source: https://github.com/Rahul-2k4/regolith-inputd.git
- Exact source ref: cd1c2cd1056bfb51a920f2a8794ccbf89e953489
- Target: Ubuntu Resolute amd64, stage unstable
- Model: stage/unstable/package-model.json

## Validation

- jq empty stage/unstable/package-model.json: passed.
- Merged model (stage root + unstable + unstable/ubuntu/resolute): passed; regolith-inputd resolves to the exact source URL and ref above.
- bash -n local-build.sh ext-debian.sh ext-git.sh main.sh: passed.
- git diff --check: passed.

## Bounded package attempt

timeout 180s bash .github/scripts/local-build.sh --extension .github/scripts/ext-debian.sh --git-repo-path <candidate-worktree> --package-name regolith-inputd --package-url https://github.com/Rahul-2k4/regolith-inputd.git --package-ref cd1c2cd1056bfb51a920f2a8794ccbf89e953489 --distro ubuntu --codename resolute --stage unstable

Result: no .deb artifact. The builder cloned and detached at cd1c2cd (fix: guard empty sway keyboard layouts), updated the changelog to 0.4.1-1-1regolith-resolute, and then stopped during source-package preparation at sudo apt update / sudo apt build-dep -y . Exact blocker: sudo: a terminal is required to read the password; either use the -S option or configure an askpass helper, followed by sudo: a password is required.

The archive setup also reported HTTP 404 for http://archive.regolith-desktop.com/ubuntu//dists/resolute/Release; this was non-fatal and the exact source ref was still cloned. No QEMU or runtime proof is claimed.
