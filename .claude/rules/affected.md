---
paths:
  - src/affected.bats
  - tests/affected/**
  - .github/workflows/check.yml
---

# bats affected: the affected rule of check.yml (bats#481)

`bats affected <base> <head>` prints `inert=true` or `inert=false` on stdout and its reason on stderr (exit 0), so a CI step appends its stdout to `$GITHUB_OUTPUT`. Inert means nothing the compiler, its tests, `bootstrap/c` or the workflow reads (`grep` of `src/`, `scripts/`, `tests/` and `.github/` for `.md` finds only `tests/docs/expected/index.md`, under `tests/`, and the rules named in comments).

The rule is a subcommand written in bats (`src/affected.bats`, run before bats's own arguments are read, as `check-pins` is; quire#646), because the cheap job has only the seed compiler (built from `bootstrap/c` in seconds, no ATS2) and a separate bats program could not be compiled there. The pathspec limits the diff before git pairs a rename, so a source file moved to a `.md` name is listed at its old path (removing `--no-renames` from the call changed no fixture, so the flag is not there). No file time is read.

`check.yml`: A skipped job counts as passed for the branch rule that requires `check`. The cached binary is only a locator by content: it is the function of `bootstrap/c` alone and is used for `check-pins` and `affected` only; the compiler that CI judges is the one `check` builds, whose C the "bootstrap/c matches" and fixpoint steps compare. A pull request is judged by `HEAD^1` to `HEAD` of its merge checkout, a push by `github.event.before` to `HEAD`, a dispatch by an empty change (everything runs).

Comparable: GitHub's `paths-ignore` leaves a required check pending when the whole workflow is skipped, which is why the filter is a job whose dependents are skipped; `dorny/paths-filter` does the same with a JS action; quire's `scripts/affected.py` (quire#619) is the model, a rule table with a test table. Tested: `tests/affected/check.sh` (a fixture for each kind of change, renames, an unknown revision, no repository, the arguments).
