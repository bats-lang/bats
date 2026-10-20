---
paths:
  - src/bin/bats.bats
  - src/commands.bats
---

# Command line and repository

bats uses `--only <value>` (repeatable) instead of the old Rust bats' `--release` flag and `--only native|wasm`. Values: `debug`, `release`, `native`, `wasm`. Multiple `--only` flags narrow the build matrix. Default (no `--only`): build all. Example: `--only debug --only native` builds only debug native. The entry point rename (`implement main0` → `implement __BATS_main0`) applies to code only. The Rust bats renamed the first occurrence anywhere in the emitted text, including inside a string literal or a comment, which broke the build (`tests/main0-string`).

`BATS_REPOSITORY` names the package repository when `--repository` is not given; the flag wins (`tests/repository-env`). The Rust bats had only the flag.
