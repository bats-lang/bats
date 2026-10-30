---
paths:
  - tests/run-fixtures.sh
  - tests/run-fixtures/**
  - .github/workflows/check.yml
---

# Fixture times (bats-lang/bats#595, keyword: fixture-times)

The `Fixture tests` step of `check.yml` runs `tests/run-fixtures.sh dist/debug/bats ~/repository`, which runs each `tests/*/check.sh` in turn (extra arguments name the scripts instead, as the test does). The step was 56 to 106 minutes with no time for any fixture in its log, and a job still running cannot be downloaded, so where the time went could not be read.

* Each `ok` line of a group is printed with ` in N s` appended, N the whole seconds since the group's previous `ok` line or its start, as the line passes (a line is printed when the group prints it, so a running job shows it).
* When a group ends, the runner prints `group <name>: ok in N s` (`group <name>: FAILED with status S in N s` for a failure, which stops the run with S as before). `<name>` is the group's directory.
* After the last group, or the failed one, `slowest groups:` lists the ten slowest, `     N s  <name>` each, slowest first, then `total: N s`.
* The clock is `date +%s%N` of the runner (a duration, never a file's time), cut to milliseconds, so a whole second is a floor and a group that sleeps 3 s reports 3. GNU date, as on the runner; the avenue for shell is that bats has no clock.
* `tests/run-fixtures/check.sh` plays stand-in groups: one sleeping 1 s then 2 s is 3 s, its cases 1 s and 2 s, and is first in the summary; a later group reads the runner's output and fails unless that group's result line is already there (live); twelve groups give ten rows; a failed group is timed, summarised and stops the run; the arguments reach the group.
* Non-bats code of ours (quire#646): `tests/run-fixtures.sh` is shell, the existing `tests/*/check.sh` harness form, and the avenue exhausted is that bats has no clock; it is a stopgap until the driver of bats#284 exists in bats, which then moves the runner.
* Limits: a case's time runs from the group's previous `ok` line (or its start), so a group that prints all its `ok` lines at its end shows 0 s on them; the group line carries the total.
* Nothing under `src/` is involved.
