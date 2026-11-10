---
paths:
  - .github/actions/setup/action.yml
  - tests/setup-action/**
---

# The setup step other bats repositories call (#274)

`.github/actions/setup/action.yml` is the one step a bats repository's job
runs first, called by commit: `bats-lang/bats/.github/actions/setup@<40 hex
digits> # <what it is>` after a checkout (two commits deep, `fetch-depth: 2`,
when the version is a pull request's head).
keys no cache: a `build/` is kept or dropped by bats itself (#267).

A change to the action is called by its new
commit only after this repository's CI has passed on it.

## Shell that remains, and the avenue exhausted for each (quire#646)

The enumeration of the files is bats's (`bats check-pins --discover`, with fixtures
in `tests/check-pins`): a shell pipeline of `git ls-files` and `mapfile` was the
first version, and it is gone. The 4095-byte limit is why it had to move: the
command line `bats check-pins` reads is 4096 bytes (`.claude/rules/check-pins.md`),
so a shell that expands a long list of files into arguments can exceed it, while
bats reads the list from git into the same buffer and refuses a list that fills
it (status 2), never cuts it. What is shell, and why bats cannot be:

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
* **`tests/setup-action/verify.sh`** (bats#514, modified by #283): the step of the `setup-action` job that runs after the action and checks what it left behind: the GMP build of ATS2 in `~/.bats/ats2` (its marker, and `patsopt` linked to libgmp by `ldd`), `libgmp-dev` (`dpkg -s`) and lld (`wasm-ld`), the caps in the environment (`BATS_PATSOPT_TIMEOUT_S` 600, `BATS_PATSOPT_MEM_MB` 4096), the repository clone at its pin (`git rev-parse`) and `BATS_REPOSITORY`, `BATS_COMMIT` the pull request's head and not the merge (`HEAD^2`), and a build of `tests/setup-action/project` whose facts name that commit. Avenues exhausted: `bats test` runs a project's own tests inside a build, in the environment the test driver gives, and the thing checked is the environment the action wrote into the job (`GITHUB_ENV`, the apt packages, the checkout's git history), which exists only in the steps after the action; `bats fixtures` and `tests/*/check.sh` run in the `check` job, which does not use the action (it builds its seed by hand), so they never see what the action left; a check inside `bats` itself (a self-check command) would be product code that reads one CI runner's `dpkg` and `ldd`, and the policy here is a portable bats. No avenue was found that moves it, and #510 does not move it; it stays one POSIX shell script that the job runs as its last step, with the project path and the three expected values as arguments.
* **`tests/setup-action/check.sh`** (bats#511, keyword: env-line) is not part of the `setup-action` job: `tests/run-fixtures.sh` runs it with the other groups in the `check` job (every change that is not only markdown). It runs the action's two awk env-line programs, the one that accepts `bats clone-repository`'s `BATS_REPOSITORY=<dir>` and the one that accepts `bats record-commit`'s `BATS_COMMIT=` and 40 lowercase hex digits (length 52), on good and bad lines (the good line with and without its final newline, no line, a blank line, two lines in each order, an empty value, a second `=`, a CR, a commit of 39, 41 and 40 non-hex characters, an upper-case digit, a trailing space, text before the name). The programs are read as text from `.github/actions/setup/action.yml` between the comment lines `# env-line-repository begin|end` and `# env-line-commit begin|end` (no YAML parser; one of each marker, no single quote inside), so the test runs the very text the action runs, as `relock-pins.yml` does with `pin-rewrite`. Mutants of each program (a dropped `NR == 1`, a changed length, a dropped anchor, a widened character class, an empty value allowed) are text edits of the extracted program; each must fail a case and the test names the case. Dropping `NR == 1` from the pattern alone is not a mutant: the END block's `NR == 1` refuses the same lines. The test found that the repository program accepted a CR in the value (`[^=]+`), so the class is `[^=\r]+` now. The avenue for the shell is in the script (the ticket prescribes a check.sh; the awk is the action's).
* The rest of the action (the pins read, the apt install, the bootstrap build,
  the clone and record steps) is as before this change (#274, #283).
