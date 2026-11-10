---
paths:
  - src/helpers.bats
  - src/bin/bats.bats
  - tests/machine-slots/**
---

# Machine slots

the files and convention of gen-pwa test's `PWA_TEST_SLOTS` and `PWA_TEST_LOCK_DIR` (bats-lang/pwa#82), so one directory given to both is one pool. The Rust bats had no machine-wide limit (`tests/machine-slots`).

**Refused (bats-lang/bats#464).** Running on without the slot would drop the machine's cap, which is what `BATS_SLOTS` is for, so the run stops instead.

*Research (pwa#155, comment 6330340164, checked on util-linux 2.39.3 as root).* `flock(1)` never runs its command when it cannot open the lock file (exit 66) or when the lock is busy under `-n` (exit 1), so a run without its lock is the failure, not the default. Cargo ignores lock errors only where a file system cannot lock, and that protects a build cache per target directory, not a machine-wide cap. GNU make, when its jobserver cannot be used, runs `-j1` with a warning: a serial run is safe, a run without the lock is not. Bazel waits on its output-base lock, or fails at once under `--noblock_for_lock`. So: refuse, do not fall back.

*Proved, tested, not reproduced.* no file system this machine has refuses `flock(2)` (tmpfs, ext4, sysfs, procfs, /dev/shm and a FIFO all take it), and a lock that waits is not refused by the kernel for being busy.
