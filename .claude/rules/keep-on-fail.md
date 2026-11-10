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

* The directory's name is neutral and carries no word of the test's name: a test that
  matches words in bats's output (`grep -qi slot`) would meet its own name in a path bats
  prints. The test's name is in the `kept:` line instead.
* A script killed by a signal runs no exit trap, so its directory stays as well.

Shell: the scripts are existing shell tests (the test driver in bats is quire#646's
ticket); the helper stays in them.

The manifest test (`tests/toml-fields`) is written in bats (build-freshness.md); on a failure it keeps `tests/toml-fields/work` and says so with the same `kept:` line, and `check.yml` uploads that directory too. So does the digest test (`tests/proved-sha256`, stamp.md): it keeps `tests/proved-sha256/work`.
