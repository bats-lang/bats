---
paths:
  - tests/keep-on-fail.sh
  - tests/keep-on-fail/**
  - scripts/bootstrap-c.sh
  - .github/workflows/check.yml
---

# A failing test script keeps its temp directory (keep-on-fail)

A failure that leaves nothing to read cannot be root-caused (#478: a fixtures case failed
once and its directory, logs and memo were gone). Every script under `tests/` and
`scripts/bootstrap-c.sh` sources `tests/keep-on-fail.sh` in place of its own `mktemp` and
trap.

* It sets `TMP` to a new absolute directory `bats-<script's directory>.XXXXXX` under
  `${BATS_KEPT_DIR:-${TMPDIR:-/tmp}}`, creating that base if it is missing.
* Exit 0 removes `TMP`. Any other exit keeps it and ends stderr with `kept: <TMP>`.
* A script that must tear something down on every exit (an unmount) names a function in
  `KEEP_ON_FAIL_TEARDOWN` before sourcing; it runs first, and `TMP` is kept or removed after.
* The path to source is `"$(dirname "$0")/../keep-on-fail.sh"` (a script is run by its path).
* A script killed by a signal runs no exit trap, so its directory stays as well.

`tests/keep-on-fail/check.sh` runs a failing script (also one that dies of `set -e`), a
passing one and one with a teardown. In CI `check.yml` sets `BATS_KEPT_DIR` to a directory
of the runner and, when a step fails, uploads it as the artifact `kept-check`; a green run
uploads nothing.

Shell: the scripts are existing shell tests (the test driver in bats is quire#646's
ticket); the helper stays in them.
