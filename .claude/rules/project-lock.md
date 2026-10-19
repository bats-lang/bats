---
paths:
  - src/helpers.bats
  - src/bin/bats.bats
  - tests/project-lock/**
---

# Project lock

Each command that writes `build/`, `dist/` or `bats_modules/` (check, build, run, test, clean, lock, add, remove, tree, upload) holds the project's lock, `flock(2)` on `bats.toml` opened read-only (file's `fd_lock`), released when bats exits however it exits; a bats that waits for it says `waiting for another bats running in this project`. `bats run` releases it once the build is done, before the program runs. What bats starts inherits the open file, so a patsopt left running by a killed bats keeps the project locked until it ends. Where the file system has no locks, bats runs unlocked. The Rust bats took no lock, so two runs in one checkout wrote one `build/` at once (`tests/project-lock`).
