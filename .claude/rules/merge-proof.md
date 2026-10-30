---
paths:
  - src/merge_proof.bats
  - tests/merge-proof/**
---

# bats merge-proof: the main-merge ruling as a command (bats#530, from bats#426)

The owner's ruling of 2026-10-20: an approving review stays authoritative when the only change since is a merge of main. `bats merge-proof <reviewed-sha> <head> [--repository <dir>]` checks that, in a checkout of the head, run at its root (the repository is `--repository`, else `BATS_REPOSITORY`; the regeneration needs it). It is a subcommand written in bats (`src/merge_proof.bats`, run before bats's own arguments are read, as `affected` is; quire#646). Its answer is the head-naming review of a gated repository's brief: the reviewer pastes the output.

Exit 0 and one line `OK: <head> is the reviewed <reviewed> and a merge of main <main parent>`. Exit 1 and a line `NOT OK: <reason>` (a reason from the proofs below, with the differing hunks after it for the diff). Exit 1 and the resolved hunks alone, nothing else on either stream, for a merge whose conflicts were resolved by hand. Exit 2 and a line on stderr for a usage error and for a git that did not answer.

## The proofs, in order

1. The head has two parents (a head with one is not a merge, a head with three is not one the ruling covers), one of them the reviewed head, and the other a commit of main (`git merge-base --is-ancestor <parent> origin/main`).
2. The merge made no change of its own. `git diff-tree --cc` over the whole tree, bootstrap/c included, prints the hunks that differ from both parents: any such hunk is printed alone for the reviewer, because a conflict resolved by hand is the one thing the ruling leaves to a person. A conflict that took one side whole shows no hunk, since it equals a parent.
3. The pull request's own diff is unchanged. `git diff origin/main...<head>` and `git diff origin/main...<reviewed>`, both over the whole tree but bootstrap/c, are written by git into files in the git directory (`--output`, named by the head) and compared by `git diff --no-index --exit-code -I'^index '`: byte for byte but for the index lines. The hunk headers are part of the bytes, so a main change above the pull request's hunk in the same file, or git's function heading taken from a line main added, is not the same diff and is not OK; the reviewer reads the differing hunks the command prints. The files are removed after the comparison.
4. bootstrap/c is not stale. This proof applies only to a repository whose head has `scripts/bootstrap-c.sh` (bats#592): the test is git's answer, `git ls-tree --name-only <head> -- scripts/bootstrap-c.sh` printing the path, not the repository's name. In a repository without the script (pwa, bridge, capacitor-plugins have no `bootstrap/c`) proofs 1 to 3 decide, no `--repository` is needed and the same `OK:` line is printed. In a repository with it: the checkout must be the head with no tracked file changed; `scripts/bootstrap-c.sh <this binary> <repository>` runs (the binary is argv[0], the compiler whose C the head is judged by) and `git status --porcelain -- bootstrap/c` must be empty. A regenerated tree is left in place for the author to commit.

The order puts the cheap proofs first and the regeneration, which builds the compiler's C, last.

## Research

The rule is the owner's ruling. Comparable: GitHub's branch protection option to dismiss stale approvals when new commits are pushed dismisses an approval on any new commit, with no exception for a merge of the base branch, and is a setting rather than a proof; Gerrit's label copy conditions (`changekind:TRIVIAL_REBASE`, `changekind:NO_CODE_CHANGE`) keep a vote when the new patch set changes no code, which is this check's idea (the change is the same). `git patch-id` ignores line numbers and whitespace, which would pass a changed indentation, so the comparison here keeps the bytes. `git diff --cc` is git's own "hunks of a merge that differ from all parents", which is what a reviewer of a merge reads (`git show` of a merge prints it).

## Tested and limited

Tested (`tests/merge-proof/check.sh`, with a stand-in `scripts/bootstrap-c.sh` that derives bootstrap/c from src): a clean main merge (OK), a changed hunk (main already had the pull request's change), a hand-resolved conflict (the hunks alone, no verdict, nothing on stderr), a clean main merge in a repository with no `scripts/` and no `bootstrap/c`, run with no repository (OK, `no-bootstrap-script`; bats#592), a stale bootstrap/c, a third parent, a head with one parent, a second parent that is a side branch, a reviewed head that is not a parent, a checkout that is not the head, an unknown revision, the repository from the environment, and the arguments. Each proof was shown to matter by injection, one mutant of `src/merge_proof.bats` for each, the project rebuilt and the fixtures run: the third parent allowed (`third-parent` fails), the combined hunks not printed (`hand-resolved-conflict`), the diffs not compared (`changed-hunk`), a stale bootstrap/c not reported (`stale-bootstrap`), the other parent not required to be main's (`parent-not-main`), the reviewed head not required to be a parent (`reviewed-not-a-parent`) and the checkout not required to be the head (`checkout-not-head`); in each the fixture of that proof fails and the ones before it pass (the output is in the pull request of bats#530).

Limits: git's output of a call is read through the capture of `src/helpers.bats` (`.claude/rules/capture.md`): the start of it is kept, which is all the command reads from a call except the hunks, which git prints straight to stdout. A revision starting with `-` is a usage error. `origin/main` is the main the proofs use. The comparison of the two diffs prints the diff of the two files, whose header names the files in the git directory.
