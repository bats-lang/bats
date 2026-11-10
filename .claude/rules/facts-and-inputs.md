---
paths:
  - src/facts.bats
  - src/inputs.bats
  - tests/build-facts/**
  - tests/build-inputs/**
---

# Facts and inputs modules

A module that staloads `"_bats_facts.sats"` gets `build/src/_bats_facts` (`src/facts.bats`): The Rust bats had none.

Keyword commit-count (bats#574, for quire's Android versionCode, quire#979): `bats_commit_count (): commit_count` is a linear datavtype, `CommitCounted of int n` with `n >= 1` (`git rev-list --count` of the commit) or `CommitHistoryShallow`, matched with `case+`. A shallow clone (`git rev-parse --is-shallow-repository` says `true`) gives the second, never a wrong number; a git that cannot count is an error that says so. The same commit gives the same count in any full clone. Additive: the four other facts are unchanged (`tests/build-facts` calls them). `tests/build-facts` plays N commits (1, 2, 3), a full clone of it (3) and a `--depth 1` clone (refused).

A module that staloads `"_bats_inputs.sats"` gets `build/src/_bats_inputs` (`src/inputs.bats`, bats-lang/bats#267): It reads no git and no clock, so the same bytes give the same digest in any directory, with any mtimes and at any commit, and a dirty tree has an honest one; the dependencies' archives are named in `bats.lock` by their sha256, so the lock stands for them. The Rust bats had none (`tests/build-inputs`).

Order of the three `.sats` writers (bats#400): a bats killed between the two leaves the stamp ahead (every C is made again), never a C kept fresh from an older `.sats`.
