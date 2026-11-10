---
paths:
  - .github/actions/setup/action.yml
  - tests/setup-action/**
---

# The setup step other bats repositories call (#274)

A change to the action is called by its new
commit only after this repository's CI has passed on it.

## Shell that remains, and the avenue exhausted for each (quire#646)

* **The probe** (`bats check-pins` with no argument, status 2, usage ends in
  `--discover`): it runs a compiler that may predate the mode, which cannot be
  asked in bats by that compiler. It is the one command whose job is to run
  before the new code can.
* **The step's `cd "$WORKSPACE"`**: the step runs `bats`, which reads the
  current directory; the action's `working-directory` input is another directory
  (the project's), and a composite step sets only one, so the cd chooses the
  repository's root. An input that named the directory would let a caller point
  the check elsewhere.
* **The planted file in `check.yml`** (`cp` and `rm -f` of a fixture): the
  action is tested by the job that uses it, and the test needs a floating
  workflow that is in the checkout for the failing call and not in it for the
  clean one. Avenues exhausted: a tracked fixture in `.github/workflows` fails the
  repository's own pin check (the step "Every CI input is pinned" and the clean
  call); a bats fixture job (`bats fixtures`) runs after the action has run, so
  it cannot plant what the action reads first; bats has no command that copies a
  file. The fixture is kept as a tracked file outside `.github` so that the shell
  is two commands, with no floating input written by `echo`.
* **`tests/setup-action/verify.sh`** (bats#514, modified by #283): the step of the `setup-action` job that runs after the action and checks what it left behind. Avenues exhausted: `bats test` runs a project's own tests inside a build, in the environment the test driver gives, and the thing checked is the environment the action wrote into the job (`GITHUB_ENV`, the apt packages, the checkout's git history), which exists only in the steps after the action; `bats fixtures` and `tests/*/check.sh` run in the `check` job, which does not use the action (it builds its seed by hand), so they never see what the action left; a check inside `bats` itself (a self-check command) would be product code that reads one CI runner's `dpkg` and `ldd`, and the policy here is a portable bats. No avenue was found that moves it, and #510 does not move it; it stays one POSIX shell script that the job runs as its last step, with the project path and the three expected values as arguments.
* **`tests/setup-action/check.sh`** (bats#511, keyword: env-line) is not part of the `setup-action` job: `tests/run-fixtures.sh` runs it with the other groups in the `check` job (every change that is not only markdown). The avenue for the shell is in the script (the ticket prescribes a check.sh; the awk is the action's).