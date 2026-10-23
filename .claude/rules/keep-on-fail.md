---
paths:
  - tests/keep-on-fail.sh
  - tests/keep-on-fail/**
  - scripts/bootstrap-c.sh
  - .github/workflows/check.yml
---

# A failing test script keeps its temp directory (keep-on-fail)

A failure that leaves nothing to read cannot be root-caused, so a failing test keeps its
directory, logs and memo. Every script under `tests/` and
`scripts/bootstrap-c.sh` sources `tests/keep-on-fail.sh` in place of its own `mktemp` and
trap.

* It sets `TMP` to a new absolute directory `bats-tmp.XXXXXX` under
  `${BATS_KEPT_DIR:-${TMPDIR:-/tmp}}`, creating that base if it is missing.
* The directory's name is neutral and carries no word of the test's name: a test that
  matches words in bats's output (`grep -qi slot`) would meet its own name in a path bats
  prints. The test's name is in the `kept:` line instead.
* Exit 0 removes `TMP`. Any other exit keeps it and ends stderr with
  `kept: <TMP> (<script's directory name>)`.
* A script that must tear something down on every exit (an unmount) names a function in
  `KEEP_ON_FAIL_TEARDOWN` before sourcing; it runs first, and `TMP` is kept or removed after.
* The path to source is `"$(dirname "$0")/../keep-on-fail.sh"` (a script is run by its path).
* A script killed by a signal runs no exit trap, so its directory stays as well.

`tests/keep-on-fail/check.sh` runs a failing script (also one that dies of `set -e`), a
passing one and one with a teardown (its hook must see the directory still there on a pass
and on a failure, and a failure's directory must remain), and checks the neutral name and the
test's name in the `kept:` line. In CI `check.yml` sets `BATS_KEPT_DIR` to a directory
of the runner and, when a step fails, uploads it as the artifact `kept-check`; a green run
uploads nothing.

Shell: the scripts are existing shell tests (the test driver in bats is quire#646's
ticket); the helper stays in them.
