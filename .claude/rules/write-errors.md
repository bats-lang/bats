---
paths:
  - src/helpers.bats
  - src/build.bats
  - src/stamp.bats
  - tests/full-disk/**
---

# Write errors

A write that fails is an error, never a file taken for whole (bats#359, #360, #361, #314; the shared host's disk filled in the middle of a run and bats built from a C cut short at the byte where the write failed). The first failed byte stops the write (the file package's `buf_write_byte` empties its buffer on an error, so going on would write the bytes after a gap). `relative_c` no longer falls back to patsopt's C as it is when the rewritten one cannot be written (that put a C with the checkout's path in it in place, and said nothing). The shared cache's copy (`BATS_CACHE_DIR`) is a `cp` and `mv` of the shell: its status is said as a warning, and the build goes on (the cache is not what is built, and the copy is moved whole or not at all). `tests/full-disk/check.sh` plays it: It fails on main's compiler: a C cut at the limit is accepted and `check passed` is said (the cases of the .dats, the .sats and 0 failed silently, with no error line, or with the stamp's message, not the write's).
