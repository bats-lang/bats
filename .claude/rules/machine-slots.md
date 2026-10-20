---
paths:
  - src/helpers.bats
  - src/bin/bats.bats
  - tests/machine-slots/**
---

# Machine slots

With `BATS_SLOTS` set (1 to 64; a larger number is 64, anything else is said and ignored), `check`, `build`, `test` and `run`'s build also hold one of that many machine slots, after the project's lock: `flock(2)` on `<BATS_LOCK_DIR>/slot-<i>.lock` (`BATS_LOCK_DIR` defaults to `~/.cache/bats`, made when missing), the files and convention of gen-pwa test's `PWA_TEST_SLOTS` and `PWA_TEST_LOCK_DIR` (bats-lang/pwa#82), so one directory given to both is one pool. Each free slot is tried in turn; when none is, bats says `waiting for another bats on this machine (N at once, BATS_SLOTS; <dir>/slot-0.lock was last taken by bats build in <directory>)` (the holder writes that note as the slot's file's first line and clears it as it releases the slot) and waits for slot 0. The kernel releases a slot however bats ends; what bats starts inherits it, as it inherits the project's lock. While it holds a slot, what bats starts gets `BATS_SLOT_HELD`, the slot's file, and a bats that finds that file locked by another open runs in its parent's slot instead of waiting for one (a command make starts runs in its implicit job slot); a `BATS_SLOT_HELD` whose slot no one holds is ignored. Unset or empty, nothing is read, made or said. A directory, file or lock that fails is said, and bats runs without a slot. The Rust bats had no machine-wide limit (`tests/machine-slots`).
