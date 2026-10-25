---
paths:
  - src/facts.bats
  - src/inputs.bats
  - tests/build-facts/**
  - tests/build-inputs/**
---

# Facts and inputs modules

A module that staloads `"_bats_facts.sats"` gets `build/src/_bats_facts` (`src/facts.bats`): `bats_commit_time`, `bats_commit_version` (`YEAR.MONTH.DAY.SECONDS` in UTC), `bats_commit_short` and `bats_commit_sha` of the commit `BATS_COMMIT` names, else `HEAD`; outside a git repository, or for a revision git does not know, it is an error that says so. Its `.sats` never changes and its `.dats` is written only when its bytes change, so a new commit compiles that one module again. A project that does not staload it (the name in a comment or a string is not a staload; bats's own sources write it) gets none. `_bats_*` files in `build/src` are bats's own and are not pruned as orphans (`tests/build-facts`). The Rust bats had none.

A module that staloads `"_bats_inputs.sats"` gets `build/src/_bats_inputs` (`src/inputs.bats`, bats-lang/bats#267): `bats_inputs_sha256 (): string 64`, the sha256, as 64 lowercase hex digits, of a listing of the project's own inputs: the line `bats-inputs 1`, then `<path> <sha256 of the file>` for `bats.toml`, for `bats.lock` when there is one and for every `src/**/*.bats`, in byte order of path (`LC_ALL=C sort`). It reads no git and no clock, so the same bytes give the same digest in any directory, with any mtimes and at any commit, and a dirty tree has an honest one; the dependencies' archives are named in `bats.lock` by their sha256, so the lock stands for them. Its `.sats` never changes and its `.dats` is written only when its bytes change, so a changed input compiles that one module again. A file that cannot be read is an error that says so. A project that does not staload it (the name in a comment or a string is not a staload) gets none and runs nothing; `_bats_*` files are not pruned as orphans. bats's own sources staload it and do not use it yet (the identity of this bats, for the stamp of a `build/` to come). The Rust bats had none (`tests/build-inputs`).

Order of the three `.sats` writers (bats#400): `build.bats`, `facts.bats` and `inputs.bats` all touch `build/.sats_changed` before the `.sats` is written, and write the `.dats` only when both are in place (`write_sats_changed` and `dats_when` in `src/helpers.bats`, beside `write_changed`; the two modules held a copy of each). A stamp that cannot be written is said (`write_settle`), and then neither the `.sats` nor the `.dats` is written, so a bats killed between the two leaves the stamp ahead (every C is made again), never a C kept fresh from an older `.sats`. `tests/full-disk/check.sh` plays it with `build/.sats_changed` as a directory for each of the three writers and asks that no `.sats` and no `.dats` exist after the failed check.
