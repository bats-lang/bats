---
paths:
  - .github/actions/setup/action.yml
  - tests/setup-action/**
---

# The setup step other bats repositories call (#274)

`.github/actions/setup/action.yml` is the one step a bats repository's job
runs first, called by commit: `bats-lang/bats/.github/actions/setup@<40 hex
digits> # <what it is>` after a checkout (two commits deep, `fetch-depth: 2`,
when the version is a pull request's head). It installs, on an apt runner,
the GMP build of ATS2 (`ATS2-Postiats-gmp-0.4.2`, its tarball checked
against a SHA-256 written in the action: the `-int` build accepts false
statements, quire#594), `libgmp-dev` and `lld`; builds the compiler from the
checked-in `bootstrap/c` of the commit `.github/bats-version` names
(`bats-version` overrides, `profile` is `release` or `debug`) and puts it on
the PATH; clones repository-prototype at the commit
`.github/repository-version` names (`BATS_REPOSITORY`); checks the pins of
the calling repository with that compiler, right after the build and before
ATS2 is installed (`bats check-pins --discover`, repository-prototype#353 piece 2,
bats#391: bats itself lists the workflows, actions, `package.json` files and
`src/ats2.bats` of the repository of the current directory, tracked or untracked
and not ignored (`git ls-files --cached --others --exclude-standard`, run by
bats through the process package), so `bats_modules/` and `build/` are not
read; no input turns it off, an exception is the caller's `# unpinned:` line,
listed in the log). A compiler that predates the mode cannot say so (an older
one prints its usage and exits 0 for an unknown command), so the step first
probes: `bats check-pins` with no argument must exit 2 with a usage that ends in
`--discover`, and a compiler that does not is refused, so a repository whose
`bats-version` predates bats#391 is refused until it repins its compiler; sets
`BATS_PATSOPT_TIMEOUT_S` and `BATS_PATSOPT_MEM_MB` (600 and 4096, inputs);
and sets `BATS_COMMIT` to `commit`, which defaults to
`github.event.pull_request.head.sha || github.sha`, so the version names a
pull request's head, not the merge GitHub tests, and a merge group's own
commit. It refuses before installing anything: a pin that is not a full
lowercase SHA (never a branch or a tag; a missing pin file is an error, not
the newest), a `commit` not in the checkout, a project with no `bats.lock`
(`require-lock: 'false'` for a package with no dependencies). It installs and
keys no cache: a `build/` is kept or dropped by bats itself (#267).

Its test is the `setup-action` job of `check.yml`: the three refusals, then
the workflow with a floating input of `tests/setup-action/planted/floating.yml`
copied untracked into `.github/workflows`, which must fail the action (the
step's outcome), removed, then the action on
`tests/setup-action/project` with the compiler built from the commit under
test (which must pass: the repository's own files are clean), and `tests/setup-action/verify.sh` (GMP patsopt linked to
libgmp, lld, the caps, the repository at its pin, `BATS_COMMIT` the head and
not the merge, and a build of the project whose facts name that commit).
`bats check-pins` (`.claude/rules/check-pins.md`, tested by `tests/check-pins`, `--discover` included, a step of the `check` job on the seed compiler) fails any `uses:` of a workflow or action that is not a local path or a repository at a full commit SHA followed by a comment naming the version, and the other inputs of CI that move. A change to the action is called by its new
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
* The rest of the action (the pins read, the apt install, the bootstrap build,
  the clone and record steps) is as before this change (#274, #283).
