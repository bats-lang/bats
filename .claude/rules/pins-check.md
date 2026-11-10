---
paths:
  - src/pins_check.bats
  - tests/pins-check/**
---

# bats pins-check: what the review of a pure pin or relock pull request verifies, as a command (bats#427)

`bats pins-check <base> <head> [--compiler <dir>] [--repository <dir>] [--require-contains <sha>]` checks, in a git checkout of the pull request (any working tree: it reads git objects only), that the diff `base...head` (from the merge base, the pull request's own diff) is a pure move of pins. It is a subcommand written in bats (`src/pins_check.bats`, run before bats's own arguments are read, as `affected` and `merge-proof` are; quire#646). The review of such a pull request is its output: the reviewer pastes it and confirms the diff is pins only (the review stays, the gate needs a comment; only its size shrinks). `--compiler` is a checkout of bats-lang/bats (where the commit of `.github/bats-version` is looked up), `--repository` the package repository's checkout (else `BATS_REPOSITORY`: the commits of `.github/repository-version` and of the `repository-prototype` workflow pins, and the sidecars). A checkout is needed only for a pin that moved.

## The checks

2. If neither is an ancestor of the other, the two have **diverged**: a `note:` line, not a finding. Why: the old pin of many of the pull requests measured below (every pin move from the bats pin of 2026-10-16) was a commit that is on no branch of bats's main (it was dropped when main was rewritten), so no pin after it can descend from it; GitHub's compare API has the same three outcomes (`ahead`, `behind`, `diverged`, with `identical`), and only `behind` is a regression.
4. the sha256 equals the sidecar of the package repository **at the commit of the head's `.github/repository-version`** (read with `git show`, never from the files the clone has checked out: the same check as `bats check-push` check 1, whose `check_entry` it calls).
5. Without the option nothing is asked of the fix: the relock picked a pin that was the newest when it ran, and only the fix the reviewer names is the question.

## Decisions

* The name is the issue's (`pins-check`); `check-pins` (bats#390) is the CI inputs that move, and the two verbs do not mix.
* The diff is read as `git diff -U0` of each file, in 65536 bytes of git's stdout (`tool_output_wide` in `src/helpers.bats`, the capture of `.claude/rules/capture.md` with a bigger buffer and a flag for "there was more"); a diff longer than that is a finding, never a cut one. Lines, not YAML (quire#646: no YAML parser in this compiler).
* `check_entry`, `git_status` and `locks_result` of `src/check_push.bats`, and `word` of `src/merge_proof.bats`, are public for it, so the sidecar rule is written once.
* No mtimes, no network, no clock: the answer is a function of the git objects and the files named.

## Tested and limited

Non-bats code of ours (quire#646): `tests/pins-check/check.sh` is the existing `tests/*/check.sh` harness form, and the avenue exhausted is a bats test, which cannot run the built binary in scratch git repositories (a compiler checkout, a package repository and an app with pull request branches) until the driver of bats#284 exists.

