---
paths:
  - src/merge_proof.bats
  - tests/merge-proof/**
---

# bats merge-proof: the main-merge ruling as a command (bats#530, from bats#426)

The owner's ruling of 2026-10-20: an approving review stays authoritative when the only change since is a merge of main. `bats merge-proof <reviewed-sha> <head> [--repository <dir>]` checks that, in a checkout of the head, run at its root (the repository is `--repository`, else `BATS_REPOSITORY`; the regeneration needs it). It is a subcommand written in bats (`src/merge_proof.bats`, run before bats's own arguments are read, as `affected` is; quire#646). Its answer is the head-naming review of a gated repository's brief: the reviewer pastes the output.

2. a conflict resolved by hand is the one thing the ruling leaves to a person.
4. the test is git's answer, not the repository's name.

The order puts the cheap proofs first and the regeneration, which builds the compiler's C, last.

## Research

The rule is the owner's ruling. Comparable: GitHub's branch protection option to dismiss stale approvals when new commits are pushed dismisses an approval on any new commit, with no exception for a merge of the base branch, and is a setting rather than a proof; Gerrit's label copy conditions (`changekind:TRIVIAL_REBASE`, `changekind:NO_CODE_CHANGE`) keep a vote when the new patch set changes no code, which is this check's idea (the change is the same). `git patch-id` ignores line numbers and whitespace, which would pass a changed indentation, so the comparison here keeps the bytes. `git diff --cc` is git's own "hunks of a merge that differ from all parents", which is what a reviewer of a merge reads (`git show` of a merge prints it).

## Tested and limited

Tested (`tests/merge-proof/check.sh`, with a stand-in `scripts/bootstrap-c.sh` that derives bootstrap/c from src): a clean main merge (OK), a changed hunk (main already had the pull request's change), a hand-resolved conflict (the hunks alone, no verdict, nothing on stderr), a clean main merge in a repository with no `scripts/` and no `bootstrap/c`, run with no repository (OK, `no-bootstrap-script`; bats#592), the same repository with main's change already in the pull request's hunk (`no-bootstrap-script-changed-hunk`: proof 3 still decides), a stale bootstrap/c, the same stale head run from a subdirectory of the repository (`stale-bootstrap-from-subdirectory`: exit 2, no `OK:`, stderr says `scripts/bootstrap-c.sh did not run to its end`; the mutant without `--full-tree` prints `OK:` and fails it), a third parent, a head with one parent, a second parent that is a side branch, a reviewed head that is not a parent, a checkout that is not the head, an unknown revision, the repository from the environment, and the arguments. Each proof was shown to matter by injection, one mutant of `src/merge_proof.bats` for each, the project rebuilt and the fixtures run: the third parent allowed (`third-parent` fails), the combined hunks not printed (`hand-resolved-conflict`), the diffs not compared (`changed-hunk`), a stale bootstrap/c not reported (`stale-bootstrap`), the other parent not required to be main's (`parent-not-main`), the reviewed head not required to be a parent (`reviewed-not-a-parent`) and the checkout not required to be the head (`checkout-not-head`); in each the fixture of that proof fails and the ones before it pass (the output is in the pull request of bats#530).

Limits: the existence test of proof 4 is by the whole tree (`--full-tree`). The script is spawned by a path relative to the working directory (`scripts/bootstrap-c.sh`), so a run outside the root of a scripted repository exits 2, failing closed. git's output of a call is read through the capture of `src/helpers.bats` (`.claude/rules/capture.md`): the start of it is kept, which is all the command reads from a call except the hunks, which git prints straight to stdout. A revision starting with `-` is a usage error. `origin/main` is the main the proofs use. The comparison of the two diffs prints the diff of the two files, whose header names the files in the git directory.
