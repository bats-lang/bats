---
paths:
  - src/commands.bats
  - tests/test-command/**
  - tests/test-wasm/**
---

# bats test

`bats test` runs the tests. The Rust bats's runner called each test from a generated entry that staloads only the modules' `.sats`, where a test (defined in its block, in the `.dats`) is not declared, so it could never compile. A test is `fn <name> (): bool` in a `$UNITTEST.run` block (a test `fun` would need a metric); the Rust bats's harness called exported test functions instead, which a `.sats`-less test could not be (`tests/test-wasm`).
