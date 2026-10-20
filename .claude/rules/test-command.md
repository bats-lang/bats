---
paths:
  - src/commands.bats
  - tests/test-command/**
  - tests/test-wasm/**
---

# bats test

`bats test` runs the tests. The Rust bats's runner called each test from a generated entry that staloads only the modules' `.sats`, where a test (defined in its block, in the `.dats`) is not declared, so it could never compile. In check and test mode each module with tests now declares `__bats_test (i: int): bool` in its `.sats` and implements it in its `.dats`, dispatching to its i-th test; `bats test` builds a runner binary in `build/_bats_test` (the package's `src/*.bats` and one binary whose `main0` calls the selected tests) and runs it, with the Rust bats's `running N native test(s)`, `  PASS <name>`/`  FAIL <name>`, `error: native test failed` and `all tests passed`. A test is `fn <name> (): bool` in a `$UNITTEST.run` block (a test `fun` would need a metric); tests in `src/bin/` are an error (the runner links `src/`'s modules, not the binaries) (`tests/test-command`). Wasm tests run the same way: a `#target wasm binary` runner in `build/_bats_test_wasm`, run in Node by a generated harness, printing the Rust bats's `running N wasm test(s)`, the PASS/FAIL lines, `P passed, F failed` and `error: wasm test failed`. For it the wasm runtime defines `print_string`, `print_newline`, `print_int` and `exit_void` over the host imports `env.bats_host_print` and `env.bats_host_exit`, which the harness provides; the Rust bats's harness called exported test functions instead, which a `.sats`-less test could not be (`tests/test-wasm`).
