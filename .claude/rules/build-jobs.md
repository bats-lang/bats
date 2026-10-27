---
paths:
  - src/helpers.bats
  - src/build.bats
  - src/bin/bats.bats
  - tests/build-jobs/**
---

# Parallel compiles (build-jobs)

`bats build` and `bats test`/`run`'s build (and `check`, which accepts the option and runs no compile) take `-j N` or `--jobs N`, N a number from 1 or the word `cores`. Up to J clang processes run at once over objects that do not depend on each other, and every one has ended before anything reads an object (the link). **The invariant: what the build writes, and what it prints for each compile, does not depend on J.** A compile reads its own C and the headers, writes its own object and, after success, its own `.key`; J only changes when they run. J is not an input of any output, so it is not in the stamp (`build-freshness.md`, `stamp.md`); nothing reads a time.

## The value

* The default is `cores`: the online processors, asked of `getconf _NPROCESSORS_ONLN` once per run through `run_cmd_capture_outcome` (`capture.md`), every constructor matched. An answer that is not a number from 1 up (not run, longer than the buffer, a failed read, a word) is said once on stderr and is 1. An explicit number never asks.
* `BATS_SLOTS` (`machine-slots.md`) divides it: J = max(1, floor(requested / slots)), at most 256. bats already has a machine-wide cap that every agent here sets; the division reuses it instead of adding a load-average signal, which depends on what ran a minute ago.
* A bare `-j`, `0`, a negative, a word other than `cores` and a value that is not digits are `error: --jobs takes a number from 1 or the word cores` on stderr, status 1, nothing run (`jobs_option`; checked before the project's lock and the machine slot are taken). A value over 256 is 256. `-j N` takes its value as a separate word, as `--only` does (`count_positionals` and `first_positional` know both spellings).

*Research (bats#554).* GNU make defaults to 1 and has no limit for a bare `-j`; ninja defaults to cores + 2 and needs a number; cargo defaults to the cores and needs a number. A machine-wide cap is make's jobserver and `-l`, ninja's `-l`, cargo's jobserver client. bats takes the default of the two tools whose compile steps are independent processes like its own (every clang run writes its own object), refuses the bare `-j` (one clang per stale file, 326 in the case on the ticket, is not a default anyone wants), and caps with the slots it already has. After a failure make, ninja and cargo stop starting work; bats goes on and ends every compile, as its serial build always did, so the same messages appear in the same order for every J.

## The pool

`run_cc`, `run_cc_noted` and `run_wasm_cc` (`src/helpers.bats`) keep their freshness test, `key_drop` and preprocess (in the parent, in file order), then start the child and queue a `cc_job`: a `datavtype` that owns the child, its stderr pipe's read end and copies of the object's path, the C's path and the note. The queue is a global `ref` holding one linear `cc_pool` (`g_pool`, taken and put back with `ref_exch_elt` as `g_digests` is), a `list_vt` oldest first whose count is in the type, at most 256: `cc_make_room` returns a count below J, `cc_pool_mk` accepts only a count of at most 256, so a pool over J or over 256 does not type-check. No `$UNSAFE`, `castfn`, `praxi` or `assume`; each `fun` has a termination metric; a job's linear types make it impossible to drop or leave running (`cc_job_end` consumes the child and the descriptor, `cc_drain_list` consumes every job).

* **Room is made before the spawn** (`cc_pool_room`): the oldest jobs end until fewer than J are running, and then the child is started. Making room after the spawn runs J + 1 children.
* **Order.** Jobs end oldest first, so the compiler's text, the verbose line (`  + cc -c -o <object> <C>`, printed when the job ends) and the note come in submission order, which is the serial build's order. A younger child that ends early waits to be ended while the older ones run; the cost is an idle slot only when the oldest is the slowest. A child's stderr is read to its end before it is waited for (`capture_read`, over any buffer size: the first 65536 bytes are kept). The file package's read stops when its buffer is full, so closing the pipe then gave a compile that succeeded with more than 65536 bytes of messages a broken pipe, and it was reported as failed; read to the end it succeeds. The oldest job is always the one being read, so there is no deadlock; a younger child that fills its pipe waits until it is the oldest.
* **The kind of a job is a sum** (`cc_kind`): `CcNative(profile)` runs `native_object_record` after exit 0, `CcWasm()` runs `wasm_object_record`; the stderr handling, the order and the failure are the same for each. A patsopt job (bats#562) or an emit job (bats#563) is another constructor and one `case+` arm in `cc_job_end`; a kind left out does not compile.
* **The note** is the line a caller prints when its compile failed (`error: cc failed for dep|extra|src module <name>`). A job carries it and prints it, after the compiler's text, when it ends; `run_cc_noted` takes it. A job with no note prints the compiler's text only and does not set the build error, as `run_cc` never did; the link then fails on the missing object, as it did.
* **A wasm compile that fails sets the build error** (`CcWasm`'s arm of `cc_job_end`), where the serial build left its object out of the link list and went on. The list is built before the compile has run, so the failure has to fail the build; `wasm-ld` then runs on a missing object and its message follows.
* **The barrier** is `cc_pool_drain`: at the end of the native compile step before the link is built (`build.bats`, before Step 8) and before `wasm-ld` runs. It is a no-op on an empty pool, so `--to-c`, `check` and a build that fails before the compile step enqueue and wait for nothing. After a failed compile bats goes on submitting and the drain waits for every child, so no clang outlives the run and the project's lock is held to the end.
* **Spawn failure** drains the queue first and is then reported as before (`~1`), so its message keeps its place.

## What is tested, what is not

`tests/build-jobs` (a bats program, built and run by `check.yml` on the compiler under test; its `clang` and `getconf` are stand-ins first in `PATH`): the stand-in clang logs `S`/`E`/`F` lines, makes the compiles of the modules wait until the log has had `CC_WAIT_FOR` of them running at once (so the overlap is the one the caller starts together, not a matter of timing), holds each 0.3 s (so a pool that runs too many shows it), and fails the files `CC_FAIL_A` and `CC_FAIL_B` name; the cases are `--jobs 2`, `-j 3`, `--jobs 1`, the default and `cores` with a getconf that says 3, `BATS_SLOTS` dividing the count, a getconf that gives a word or fails (one warning), the files of `build/` (objects aside) and the output equal for `--jobs 1`, 2 and cores, the refused values, two failing compiles of which the second finishes first, a failing compile that writes 200000 bytes (the first 65536 are printed) and a successful one that does, and a `--only wasm` build of a wasm binary with two compiles at once (the stand-in holds each until both run), which fails with `wasm-ld: error: cannot open ... wasm.o` when the drain before `wasm-ld` is removed. `bats test` runs the unit tests of the division (`jobs_div`) and the value (`jobs_parse`).

Not proved: that two compiles in flight never write the same file. Each object is submitted once between two barriers, because every caller visits an object once per build and the barrier comes before the next binary's compile step; a duplicate would be two clangs on one `-o`.

## bootstrap/c

`bootstrap/c` is regenerated by `scripts/bootstrap-c.sh` from the compiler built from the sources of the change, and differs from the earlier tree only by the new source: the generator itself enqueues nothing (`--to-c` runs no compile), so the pool is empty and its drain a no-op, and the fixpoint step builds the compiler with itself and emits the same C.
