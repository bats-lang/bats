---
paths:
  - tests/run-fixtures.sh
  - tests/run-fixtures/**
  - .github/workflows/check.yml
---

# Fixture times (bats-lang/bats#595, keyword: fixture-times)

The `Fixture tests` step of `check.yml` runs `tests/run-fixtures.sh dist/debug/bats ~/repository`, which runs each `tests/*/check.sh` in turn (extra arguments name the scripts instead, as the test does). The step was 56 to 106 minutes with no time for any fixture in its log, and a job still running cannot be downloaded, so where the time went could not be read.

* The clock is `date +%s%N` of the runner (a duration, never a file's time); the avenue for shell is that bats has no clock.
* Non-bats code of ours (quire#646): `tests/run-fixtures.sh` is shell, the existing `tests/*/check.sh` harness form, and the avenue exhausted is that bats has no clock; it is a stopgap until the driver of bats#284 exists in bats, which then moves the runner.
