# bats

## Goals

bats must be:

1. **The bats compiler**: Self-hosting bats compiler written in Bats. The old Rust implementation is archived at `/home/moshez/src/bats-lang/bats-old/`.

2. **Safe**: `unsafe = false` (or no `unsafe` key) in `bats.toml`. No `$UNSAFE begin...end` blocks in bats source. No `$extfcall` — it is an unsafe construct. C code belongs in library packages (file, process, sha256, etc.) that expose safe typed APIs. If a package must be `unsafe = true`, keep the unsafety minimal — expose safe wrappers so dependents can be `unsafe = false`. Being in an unsafe package is not carte blanche to add more unsafety.

## Build & Test

```bash
dist/debug/bats check --repository /home/moshez/src/bats-lang/repository-prototype
dist/debug/bats build --repository /home/moshez/src/bats-lang/repository-prototype
```

## Bootstrap seed

`bootstrap/c/` is the checked-in C output of the compiler (`bats build --to-c`), normalized by `scripts/bootstrap-c.sh` so it is byte-identical on every machine. It is the only thing needed to get a working `bats` from scratch:

```bash
cp -R bootstrap/c /tmp/seed && make -C /tmp/seed PATSHOME=$HOME/.bats/ats2 debug/bats
```

Every change to `src/` or `bats.lock` must regenerate and commit it in the same PR:

```bash
dist/debug/bats build --repository ../repository-prototype
scripts/bootstrap-c.sh dist/debug/bats ../repository-prototype
```

CI builds the compiler from `bootstrap/c`, regenerates, and fails if the result differs. It also checks the fixpoint (the compiler built by itself emits the same C). Never edit `bootstrap/c/` by hand.

## Architecture

Entry point: `src/bin/bats.bats`
Shared modules: `src/helpers.bats`, `src/lexer.bats`, `src/emitter.bats`, `src/build.bats`, `src/docs.bats`, `src/commands.bats`, `src/lock.bats`, `src/recursion.bats`, `src/closure.bats`

Dependencies: argparse, array, arith, builder, env, file, path, process, result, sha256, str, toml

## Workflow

All changes, even one byte, in ANY repo in bats-lang, must go through branch -> PR -> green -> merge. NEVER commit directly to main. Use `gh pr merge --merge` (no squash).

When creating a new repo: push an empty initial commit to main first (`git commit --allow-empty -m "Initial commit" && git push -u origin main`), then create a feature branch for the actual content. The first branch you push becomes the default, so main must exist before any feature branches.

Never blocked by another PR — add finishing that PR to the task list instead.

Never ask permission to keep going. Keep going until the success criterion is met.

Never wait. A PR in flight (CI running, a package publishing, a review pending) is never a reason to stop or idle: pick up the next independent task from the task list (this project always has one) and come back to the PR when its event arrives. Stopping is only for a decision that is the user's to make.

## Allowed Divergences from old Rust bats

bats uses `--only <value>` (repeatable) instead of the old Rust bats' `--release` flag and `--only native|wasm`. Values: `debug`, `release`, `native`, `wasm`. Multiple `--only` flags narrow the build matrix. Default (no `--only`): build all. Example: `--only debug --only native` builds only debug native. The entry point rename (`implement main0` → `implement __BATS_main0`) applies to code only. The Rust bats renamed the first occurrence anywhere in the emitted text, including inside a string literal or a comment, which broke the build (`tests/main0-string`).

`castfn`, `praxi`, `extern` and `assume` at the start of a `#pub` declaration are rejected as unsafe constructs; the Rust bats let a `#pub` declaration through unchecked (`tests/restricted-keywords`).

The `end` that closes `$UNSAFE begin` is found in code only; the word `end` in the C of a `%{ ... %}` block (a comment, say) does not close it. The Rust bats closed the block there, which broke the build (`tests/unsafe-extcode-end`).

`$X.member` is accepted when `X` is bound by ATS's `staload X = "..."` as well as by `#use ... as X`; packages staload bridge modules this way. The Rust bats reported "unknown alias" for a staload alias (`tests/staload-alias`).

A dependency's `#pub` names are not renamed. The Rust bats renamed each dependency file's `#pub` names to `__BATS__<pkg>_<name>` on its own, so a call from one module of a dependency to another module's `#pub` function (as in bridge) no longer resolved (`tests/dep-cross-module`).

The wasm prelude defines `atspre_cloptr_free` (as ATS's `basics.cats` does, with `ATS_MFREE`). The Rust bats's wasm prelude lacked it, so a wasm binary that freed a closure imported it from a host that has none and failed to instantiate (`tests/wasm-cloptr-free`).

The wasm prelude defines `atspre_g0int_nmod_int`, `atspre_g1int_nmod_int`, `atspre_g1int_mod_int` and `atspre_neg_bool0`/`atspre_neg_bool1` (as ATS's `integer.cats` and `bool.cats` do). The Rust bats's wasm prelude lacked them, so `nmod` and `~b` in a wasm binary were imported from the host, which stubbed them to return 0 (`tests/wasm-prelude-arith`).

The wasm prelude defines `atspre_ptr_is_null`, `atspre_ptr_isnot_null` and their `ptr0`/`ptr1` forms (as ATS's pointer.cats does). The Rust bats's wasm prelude had only `atspre_ptr_isnot_null` and `atspre_ptr0_isnot_null`, so a wasm binary that made an arena (array's `arena_create` tests its region with `ptr1_isnot_null`) imported the rest from a host that has none and failed to instantiate (`tests/wasm-prelude-ptr`).

The wasm prelude defines ATS's literal pattern checks `ATSCKpat_int`, `ATSCKpat_bool`, `ATSCKpat_char` and `ATSCKpat_float` (as `pats_ccomp_instrset.h` does), which patsopt emits for a `case` on a literal. The Rust bats's wasm prelude had only `ATSCKpat_con0` and `ATSCKpat_con1`, so a wasm binary with such a `case` (css's unit table) imported `ATSCKpat_int` from a host that has none and failed to instantiate (`tests/wasm-prelude-patterns`).

The wasm prelude's `ATSCKpat_con1` checks that the value is a pointer (at least `ATS_DATACONMAX`, 1024) before it reads the constructor tag, as ATS's `pats_ccomp_instrset.h` does. The Rust bats's did not, so in a wasm binary a nullary constructor (a small integer) matched against a constructor with fields was read as an address: with its tag read as 0 it was taken for the first constructor, whose fields were then read and freed (`tests/wasm-prelude-con1`).

A wasm binary exports `bats_dynload`, the entry's dynload (named with ATS's `ATS_DYNLOADNAME`), which the host calls before `mainats_0_void`. The Rust bats's wasm had no way to run the dynloads, which a native binary's C `main` runs, so no module `val` was ever initialized: a module's `ref<int>(42)` was a null pointer, and reading it read address 0 (`tests/wasm-dynload`). The wasm prelude also defines `atspre_ptr_alloc_tsz`, with which `ref` allocates its cell, as ATS's pointer.cats does.

Every recursion needs a termination metric outside `$UNSAFE`, as a `fun` does: `fnx`, the `and` members of a `fun` or `fnx` group, and `fix` lambdas are rejected without `.< metric >.`, and `val rec` (which cannot carry one) is rejected. The Rust bats checked only the `fun` keyword, so these recursed with no termination proof (`tests/recursion-metrics`).

A `$UNITTEST` block is lexed as code, like a `#target` block (a begin span, its contents' spans, an end span), so an unsafe construct in it is rejected as anywhere else; the Rust bats copied a block's text verbatim, unchecked. A block closes at its own `end`, not at the first `end` inside it (a `let`'s), where the Rust bats closed it. A `#target` block inside a `#target` block keeps its code; it was dropped (`tests/unittest-blocks`).

`bats test` runs the tests. The Rust bats's runner called each test from a generated entry that staloads only the modules' `.sats`, where a test (defined in its block, in the `.dats`) is not declared, so it could never compile. In check and test mode each module with tests now declares `__bats_test (i: int): bool` in its `.sats` and implements it in its `.dats`, dispatching to its i-th test; `bats test` builds a runner binary in `build/_bats_test` (the package's `src/*.bats` and one binary whose `main0` calls the selected tests) and runs it, with the Rust bats's `running N native test(s)`, `  PASS <name>`/`  FAIL <name>`, `error: native test failed` and `all tests passed`. A test is `fn <name> (): bool` in a `$UNITTEST.run` block (a test `fun` would need a metric); tests in `src/bin/` are an error (the runner links `src/`'s modules, not the binaries) (`tests/test-command`). Wasm tests run the same way: a `#target wasm binary` runner in `build/_bats_test_wasm`, run in Node by a generated harness, printing the Rust bats's `running N wasm test(s)`, the PASS/FAIL lines, `P passed, F failed` and `error: wasm test failed`. For it the wasm runtime defines `print_string`, `print_newline`, `print_int` and `exit_void` over the host imports `env.bats_host_print` and `env.bats_host_exit`, which the harness provides; the Rust bats's harness called exported test functions instead, which a `.sats`-less test could not be (`tests/test-wasm`).

An `implement` on a call cycle is rejected: one that calls itself, directly or through other implements or top-level functions, in the package or in a dependency. A metric cannot be given to a function declared in a `.sats`, so ATS never checks an implement's recursion for termination; the Rust bats let it through. The calls are read from the sources (`src/recursion.bats`): a definition calls every definition its body names unqualified, an implement's name being visible in every file and another definition's only in its own, and the calls within a `fun` group, which its metric checks, are left out (`tests/implement-recursion`).

A build reuses what an earlier build produced when it is still fresh; the Rust bats rewrote every `.sats` and `.dats` on every build, so its cache (input mtime equal to the recorded one) reran patsopt on everything. A `.bats` is emitted again only when its bytes are not those its `.dats` was emitted from (their sha256, kept in `<dats>.src`; an mtime cannot tell, since a relocked dependency's files keep their archive's older mtimes, `tests/source-replaced`); its `.sats` is written only when its bytes change, and then `build/.sats_changed` is written. A module's C is fresh only when newer than both its `.dats` and `build/.sats_changed`, so a change to a `.sats` it staloads rebuilds it; a body-only change rebuilds only its own module (`tests/sats-change`).

A string literal whose last byte is an escaping backslash is an unterminated string, reported as the Rust bats reports any other ("unterminated string literal"); the Rust bats's lexer stepped past the end of the file there and panicked (`tests/unterminated`).

These are the only allowed divergences. All other flags and behaviors must match the old Rust bats exactly.

## Safety Enforcement

Unsafe constructs (`castfn`, `$extfcall`, `$extval`, `$extype`, `$extkind`, `praxi`, `extern`, `assume`, `mac#`, `ext#`, `while` (`while*` with a metric is fine), `fun`, `fnx`, a `fun` group's `and` member or `fix` without termination metric, `val rec`, `#pub prfun`/`prfn` without `primplement`) are detected by the lexer (`SConstruct`, or a rejected `SPub`) and **enforced** before patsopt runs (`validate_project` in `src/lock.bats`, Rust's `preprocess_all`), as is the rule that no `implement` is on a call cycle (`src/recursion.bats`). They, and `%{ ... %}` blocks, are rejected outside `$UNSAFE begin...end` blocks in ALL packages — both safe and unsafe. `$UNSAFE begin...end` blocks themselves are rejected in `unsafe = false` packages.

## Problem Resolution

A problem already existing is never a good reason to ignore it. Problems must be fixed. Safety problems must be prioritized.

## Safety Philosophy

Never add runtime checks (assertions, bounds checks at runtime, abort-on-overflow). The type system must prevent bad states at compile time. If you cannot prove safety statically, the API is wrong — fix the API, don't add a runtime check. Runtime checks are a sign that the type system is not being used correctly. The whole point of ATS2 and Bats is that safety is enforced by the compiler, not by runtime guards.

Segfaults must never happen. A segfault means something is fundamentally wrong — do not work around it, do not accept it, do not split files to avoid it. Find the root cause and fix it systemically. If it's caused by unbounded recursion, figure out how ATS2 is supposed to handle this (it has tail-call optimization). Use web search to understand the correct solution. Do not settle for less than correct.

Don't guess. Don't "try" things. Read the code. Carefully reason about what is happening. Understand before acting.

Do not assume Linux. Code must be portable (macOS, Linux, BSDs). Do not use `/proc/self/exe` or other Linux-specific paths.

Do not use bats-old unless it's an emergency. The self-hosting compiler is the primary build tool.

Fix problems regardless of size. Never say "too large for this session" or defer work. Do the work.

## Task Rules

A task should never be more than one thing: if it requires the word "and", for example, it should be broken up. If it refers to plurals, it should be broken up. If it has a comma, it should be broken up.
