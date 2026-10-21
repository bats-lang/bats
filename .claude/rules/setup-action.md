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
ATS2 is installed (`bats check-pins`, repository-prototype#353 piece 2, bats#391:
the workflows, actions, `package.json` files and `src/ats2.bats` that are
tracked or untracked and not ignored, by `git ls-files --cached --others
--exclude-standard`, so `bats_modules/` and `build/` are not read; no input
turns it off, an exception is the caller's `# unpinned:` line, listed in the
log). A compiler that predates the checker prints its usage and exits 0 for
an unknown command, so the step first probes for the checker's own usage with
status 2 and refuses a compiler that has none, so a repository whose
`bats-version` predates bats#390 is refused until it repins its compiler; sets
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
a workflow with a floating input planted untracked in the checkout, which must
fail the action (the step's outcome), removed, then the action on
`tests/setup-action/project` with the compiler built from the commit under
test (which must pass: the repository's own files are clean), and `tests/setup-action/verify.sh` (GMP patsopt linked to
libgmp, lld, the caps, the repository at its pin, `BATS_COMMIT` the head and
not the merge, and a build of the project whose facts name that commit).
`bats check-pins` (`.claude/rules/check-pins.md`, tested by `tests/check-pins`, a step of the `check` job on the seed compiler) fails any `uses:` of a workflow or action that is not a local path or a repository at a full commit SHA followed by a comment naming the version, and the other inputs of CI that move. A change to the action is called by its new
commit only after this repository's CI has passed on it.
