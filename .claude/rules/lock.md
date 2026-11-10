---
paths:
  - src/lock.bats
  - bats.lock
  - tests/lock-*/**
  - tests/locked-deps/**
---

# The lock and locked packages

With a `bats.lock`, `check`, `build`, `run` and `test` use exactly the versions it locks, transitive ones too (`locked_deps` in `src/lock.bats`). The Rust bats's `resolve_deps`, and this one until now, never read the lock: they fetched the newest version of each package `src/` uses directly, so a committed lock pinned nothing and a missing locked version went unnoticed. **A held copy is the locked archive, not only the locked version** (#321): What is recorded is the archive's sha256, not the unpacked files': a copy edited in place after the fetch is not noticed (Cargo checks a crate's checksum against Cargo.lock when it downloads it and Go's go.sum at the download, not each unpacked file at each build; npm's integrity is checked at install), because hashing every installed file at every run is not cheap; a changed archive or lock is.