---
paths:
  - src/validated.bats
  - src/lock.bats
  - tests/check-validated/**
  - tests/uses-memo/**
---

# Validated records and the #use memo

An unchanged `bats check` on a project of quire's size (18 dependencies, 158 `.bats` files, 4.7 MB) took 26.5 s of CPU and no longer does (bats#296; callgrind of the 189 G instructions, and gdb samples of the process for time). Where it went: opening a file or a directory with the file package copied the whole 524288 bytes of the path's array into a fresh C string (20,000 opens, 37% of the instructions in `write_borrow` and 19% more zeroing the copies), so every path is opened at its own length now (`file_open_m`, `file_exists_m`, `dir_open_m` and `file_open_n` in `src/helpers.bats`, which copy the bytes up to the first NUL into an array of that size (bats#368 removed the fixed-size wrappers that passed the builder's 524288 bytes to them); the digests of the shared `.sats` and dependency files, which were a file each at the time, are one table in the memory of the process since bats#311, described in check-memo.md); and `validate_project` lexed every source of the project and its dependencies twice, once for the safety rules and once for the call cycles (23%). No time is read. `.bats_valid` belongs to no mark: `cache_swap` and the stamp's drop leave it alone, as its keys name bats and everything else they depend on.

The `#use` packages are kept by content the same way (bats#310): every check used to lex each `.bats` file of the project for `#use` lines, 8% of a check in which nothing had changed. A record is written only into a `build/.bats_valid/` that is already there (a record never makes `build/`: a validation that fails leaves none).

The target of each source is kept in memory for the run, by the sha256 of its bytes and not by its path (`bats test` rewrites the same path with other contents; a build does not change a source).
