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
Shared modules: `src/helpers.bats`, `src/lexer.bats`, `src/emitter.bats`, `src/build.bats`, `src/docs.bats`, `src/commands.bats`, `src/lock.bats`, `src/recursion.bats`, `src/closure.bats`, `src/cache.bats`, `src/facts.bats`, `src/inputs.bats`

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

The wasm prelude defines the `uint` operations (`atspre_g0int2uint_int_uint`, `atspre_g0uint2int_uint_int`, `atspre_g0uint_add_uint` and the other arithmetic, comparison and bit operations, their `g1uint` forms) and the char comparisons (`atspre_eq_char0_char0`, `atspre_neq_char1_char1`, ...), as ATS's `integer.cats` and `char.cats` do. The Rust bats's wasm prelude lacked them, so a wasm binary that hashed with sha256 or compared chars imported them from a host that has none and failed to instantiate (`tests/wasm-prelude-uint`).

A wasm binary exports `bats_dynload`, the entry's dynload (named with ATS's `ATS_DYNLOADNAME`), which the host calls before `mainats_0_void`. The Rust bats's wasm had no way to run the dynloads, which a native binary's C `main` runs, so no module `val` was ever initialized: a module's `ref<int>(42)` was a null pointer, and reading it read address 0 (`tests/wasm-dynload`). The wasm prelude also defines `atspre_ptr_alloc_tsz`, with which `ref` allocates its cell, as ATS's pointer.cats does.

Every recursion needs a termination metric outside `$UNSAFE`, as a `fun` does: `fnx`, the `and` members of a `fun` or `fnx` group, and `fix` lambdas are rejected without `.< metric >.`, and `val rec` (which cannot carry one) is rejected. The Rust bats checked only the `fun` keyword, so these recursed with no termination proof (`tests/recursion-metrics`).

A `$UNITTEST` block is lexed as code, like a `#target` block (a begin span, its contents' spans, an end span), so an unsafe construct in it is rejected as anywhere else; the Rust bats copied a block's text verbatim, unchecked. A block closes at its own `end`, not at the first `end` inside it (a `let`'s), where the Rust bats closed it. A `#target` block inside a `#target` block keeps its code; it was dropped (`tests/unittest-blocks`).

`bats test` runs the tests. The Rust bats's runner called each test from a generated entry that staloads only the modules' `.sats`, where a test (defined in its block, in the `.dats`) is not declared, so it could never compile. In check and test mode each module with tests now declares `__bats_test (i: int): bool` in its `.sats` and implements it in its `.dats`, dispatching to its i-th test; `bats test` builds a runner binary in `build/_bats_test` (the package's `src/*.bats` and one binary whose `main0` calls the selected tests) and runs it, with the Rust bats's `running N native test(s)`, `  PASS <name>`/`  FAIL <name>`, `error: native test failed` and `all tests passed`. A test is `fn <name> (): bool` in a `$UNITTEST.run` block (a test `fun` would need a metric); tests in `src/bin/` are an error (the runner links `src/`'s modules, not the binaries) (`tests/test-command`). Wasm tests run the same way: a `#target wasm binary` runner in `build/_bats_test_wasm`, run in Node by a generated harness, printing the Rust bats's `running N wasm test(s)`, the PASS/FAIL lines, `P passed, F failed` and `error: wasm test failed`. For it the wasm runtime defines `print_string`, `print_newline`, `print_int` and `exit_void` over the host imports `env.bats_host_print` and `env.bats_host_exit`, which the harness provides; the Rust bats's harness called exported test functions instead, which a `.sats`-less test could not be (`tests/test-wasm`).

An `implement` on a call cycle is rejected: one that calls itself, directly or through other implements or top-level functions, in the package or in a dependency. A metric cannot be given to a function declared in a `.sats`, so ATS never checks an implement's recursion for termination; the Rust bats let it through. The calls are read from the sources (`src/recursion.bats`): a definition calls every definition its body names unqualified, an implement's name being visible in every file and another definition's only in its own, and the calls within a `fun` group, which its metric checks, are left out (`tests/implement-recursion`).

With a `bats.lock`, `check`, `build`, `run` and `test` use exactly the versions it locks, transitive ones too (`locked_deps` in `src/lock.bats`). The Rust bats's `resolve_deps`, and this one until now, never read the lock: they fetched the newest version of each package `src/` uses directly, so a committed lock pinned nothing and a missing locked version went unnoticed. Now each locked package that `bats_modules` does not hold at its locked version (the `.bats-version` stamp `fetch` writes, or the package's `bats.toml` version) is fetched from the repository after its archive's sha256 is checked against the lock, replacing what was there; a locked version the repository lacks, an archive of another sha256, or no `--repository` to fetch from is an error. A lock that does not match the project is an error too, with a hint to relock: a package used but not locked, one locked but not used, or a locked version `bats.toml`'s constraints rule out. Newer versions in the repository are not an error; `bats lock --dry-run` still reports them as a stale lock. `bats lock` replaces what `bats_modules` holds of another version, so a relock reads each package's own `#use`s from the version it locks (`tests/locked-deps`). Without a lock, the newest version of each package `src/` uses is fetched, as before.

A build reuses what an earlier build produced when it is still fresh; the Rust bats rewrote every `.sats` and `.dats` on every build, so its cache (input mtime equal to the recorded one) reran patsopt on everything. A `.bats` is emitted again only when its bytes are not those its `.dats` was emitted from (their sha256, kept in `<dats>.src`; an mtime cannot tell, since a relocked dependency's files keep their archive's older mtimes, `tests/source-replaced`); its `.sats` is written only when its bytes change, and then `build/.sats_changed` is written. A module's C is fresh only when newer than both its `.dats` and `build/.sats_changed`, so a change to a `.sats` it staloads rebuilds it; a body-only change rebuilds only its own module (`tests/sats-change`).

A string literal whose last byte is an escaping backslash is an unterminated string, reported as the Rust bats reports any other ("unterminated string literal"); the Rust bats's lexer stepped past the end of the file there and panicked (`tests/unterminated`).

What allocates must be linear outside `$UNSAFE`, since wasm has no garbage collector and a non-linear boxed value is never freed. Each of these is rejected, with a message that names the linear form to use: a `datatype` with a constructor that carries data (use `datavtype`; `of ()` is nullary); a boxed tuple, record or list (`'(`, `'{`, `'[`, `$tup`, `$rec`, `$list` and their `_t` forms; use `@( )`, `@{ }`, `$tup_vt`, `$rec_vt`, `$list_vt`); a non-linear closure (`cloref`, `cloref0`, `cloref1`, `cloptr`, `cloptr0`, `cloptr1`; use `lincloptr1`, made with `llam`); a `lam` whose arrow leaves its kind to its context (given to a cloref parameter, the prelude's included, it is a `cloref1` closure; use `llam`, or the arrow `=<fun1>` for a plain function; `lam@` is a flat closure and stays); and a `ref` made inside a function (`ref<...>(` or `ref_make_elt` on an indented line; a top-level one is made once and stays). So are the prelude's own non-linear builders, which the source names without writing a `datatype`: the constructors of `list`, `option` and `stream_con` (`list_cons`, `list_nil`, `Some`, `None`, `stream_cons`, `stream_nil`) and the macros `nil`, `cons` and `::` (unless the file declares its own `nil` or `cons`, as the list package does over `list_vt`); every prelude function whose result is a non-linear list, option or stream built from something that is not one (enumerated from the prelude's SATS files: `list_append`, `list_vt2t`, `option_of_option_vt`, `stream_make_nil`, ...); `$delay`; and libats/ML, ATS's garbage-collected library (its `list0`, `Some0`, ..., and any staload or include of it). A qualified name (`$R.some`) is another package's and stays; the messages name `list_vt`, `option_vt` or result's `option`, and `stream_vt` (`tests/prelude-builders`). The Rust bats let them all through (`tests/linear-heap`).

A template instance patsopt finds no implementation for (`PMVtmpltcstmat` in the C it emits) fails `bats check` and `bats build` right after patsopt, with an error that names the template, shows the instance, and points to the `.bats` line that uses it. The Rust bats's check passed it, since check runs no cc, and only cc rejected it at build, with an error in the generated C (`tests/template-instances`). So does a lambda whose kind is a plain function but which captures a variable (`ATSERRORnotenvless` in the C), pointing to its `.bats` line (`tests/capturing-function`).

patsopt's C names the project's files relative to the project (`build/src/m.dats`): after patsopt succeeds, `src/cache.bats` takes the project's directory out of the paths it wrote, plain in comments and mangled into symbol names, where it is followed by `build/` (`build_057_`), as GCC's `-ffile-prefix-map` or Rust's `--remap-path-prefix` do. The same sources give the same C at any path, so a `build/` and the shared cache below are valid wherever the checkout is; ATS's `$mylocation` names its file relative to the project. The Rust bats's C held the absolute path, so a `build/` was valid only where it was made. patsopt writes `<C>.raw`, which is rewritten beside the C and renamed into place, so a bats stopped at any point never leaves a C that is half written or still holds the path (`tests/project-lock`, `tests/shared-cache`).

With `BATS_CACHE_DIR` set, patsopt's C is kept there, under a key of what patsopt reads: the toolchain (a listing of `$PATSHOME/bin/patsopt` and the files of `prelude/`, `libats/`, `share/`, `ccomp/` by `cksum`, made once per process), patsopt's arguments, and the module's `.dats` with every file its staloads and includes reach (`patsopt --depgen`, followed to the end), each by path and sha256. A module bats would run patsopt on is looked up first; a hit is copied into place and checked as patsopt's output is (template instances, capturing lambdas), and only a run that passed those checks is kept, so a hit never passes what a cold build fails. Entries are written beside their place and renamed into it, so checkouts share the cache with no lock; one unused for 7 days is removed (at most once a day, after a store). The Rust bats had no cache shared between checkouts (`tests/shared-cache`).

`BATS_REPOSITORY` names the package repository when `--repository` is not given; the flag wins (`tests/repository-env`). The Rust bats had only the flag.

Each command that writes `build/`, `dist/` or `bats_modules/` (check, build, run, test, clean, lock, add, remove, tree, upload) holds the project's lock, `flock(2)` on `bats.toml` opened read-only (file's `fd_lock`), released when bats exits however it exits; a bats that waits for it says `waiting for another bats running in this project`. `bats run` releases it once the build is done, before the program runs. What bats starts inherits the open file, so a patsopt left running by a killed bats keeps the project locked until it ends. Where the file system has no locks, bats runs unlocked. The Rust bats took no lock, so two runs in one checkout wrote one `build/` at once (`tests/project-lock`).

With `BATS_SLOTS` set (1 to 64; a larger number is 64, anything else is said and ignored), `check`, `build`, `test` and `run`'s build also hold one of that many machine slots, after the project's lock: `flock(2)` on `<BATS_LOCK_DIR>/slot-<i>.lock` (`BATS_LOCK_DIR` defaults to `~/.cache/bats`, made when missing), the files and convention of gen-pwa test's `PWA_TEST_SLOTS` and `PWA_TEST_LOCK_DIR` (bats-lang/pwa#82), so one directory given to both is one pool. Each free slot is tried in turn; when none is, bats says `waiting for another bats on this machine (N at once, BATS_SLOTS; <dir>/slot-0.lock was last taken by bats build in <directory>)` (the holder writes that note as the slot's file's first line and clears it as it releases the slot) and waits for slot 0. The kernel releases a slot however bats ends; what bats starts inherits it, as it inherits the project's lock. While it holds a slot, what bats starts gets `BATS_SLOT_HELD`, the slot's file, and a bats that finds that file locked by another open runs in its parent's slot instead of waiting for one (a command make starts runs in its implicit job slot); a `BATS_SLOT_HELD` whose slot no one holds is ignored. Unset or empty, nothing is read, made or said. A directory, file or lock that fails is said, and bats runs without a slot. The Rust bats had no machine-wide limit (`tests/machine-slots`).

With `BATS_PATSOPT_TIMEOUT_S` (wall clock seconds) and/or `BATS_PATSOPT_MEM_MB` (address space, megabytes) set, every patsopt run (`patsopt_only` in `src/helpers.bats`, the one place patsopt is started) is held to them, because the GMP build of ATS2's solver can run away in time and memory on a proof the machine-integer solver answers at once (one function of quire's `library.bats` passed 6.4 GB in 14 minutes, and an earlier run was killed by the system at 9.9 GB with no module named: bats-lang/quire#594). A run the cap ends fails the build with `error: patsopt on src/m.bats was stopped by the time cap: ...` or `... by the memory cap: ...`, naming the module, the variable and its value, and how to raise it, and bats exits 124 (time) or 125 (memory), not 1 as for a patsopt error. Unset or empty, nothing is read, made or said and patsopt is started by bats itself; anything else than a number from 1 up is said and ignored. This is a resource cap on an external process, not a runtime check of the program: the types say nothing of how long or large the solver gets. It is portable sh and kill, which POSIX has, because there is no `timeout(1)` on macOS and the process package has no setrlimit or kill: a capped patsopt is started by `sh -c`, which lowers its address space (`ulimit -v`) and runs patsopt under it; for the time it keeps patsopt as its child and ends it with SIGALRM after the seconds (a `sleep`, ended when patsopt finishes first, so nothing outlives the run or holds the project's lock), telling that death from any other by wait's status 128 + 14. The memory cap has no such sign (RLIMIT_AS only makes allocations fail), so a patsopt that fails under it with a signal, or whose stderr says its allocator or GMP's failed (`ats_malloc_gc`, `Cannot allocate memory`), is the memory cap's; a patsopt error is still one. What is not portable: a system whose sh cannot lower the limit (`ulimit -v` refused, probed once) is told once and patsopt runs without the memory cap, and macOS, whose `ulimit -v` does not enforce RLIMIT_AS, is untested here; the time cap is whole seconds and needs `kill -s ALRM` and `wait` giving 128 + the signal, which POSIX's `kill -14` and every sh tried (dash) do (`tests/patsopt-cap`). Other tools' caps on a prover, for the record: Why3's manual page gives `--timelimit` in seconds (0 off, default 10) and `--memlimit` in megabytes (default none) for each prover call, which is the same pair of wall clock and memory caps; Dafny offers, besides a time limit, a Z3 resource count (`--resource-limit`, a deterministic counter that stops the solver like a time or memory limit, reproducible under load but not uniform in work), which needs a counter inside the solver, and patsopt's has none, so bats caps the process, per module.

A module that staloads `"_bats_facts.sats"` gets `build/src/_bats_facts` (`src/facts.bats`): `bats_commit_time`, `bats_commit_version` (`YEAR.MONTH.DAY.SECONDS` in UTC), `bats_commit_short` and `bats_commit_sha` of the commit `BATS_COMMIT` names, else `HEAD`; outside a git repository, or for a revision git does not know, it is an error that says so. Its `.sats` never changes and its `.dats` is written only when its bytes change, so a new commit compiles that one module again. A project that does not staload it (the name in a comment or a string is not a staload; bats's own sources write it) gets none. `_bats_*` files in `build/src` are bats's own and are not pruned as orphans (`tests/build-facts`). The Rust bats had none.

A module that staloads `"_bats_inputs.sats"` gets `build/src/_bats_inputs` (`src/inputs.bats`, bats-lang/bats#267): `bats_inputs_sha256 (): string 64`, the sha256, as 64 lowercase hex digits, of a listing of the project's own inputs: the line `bats-inputs 1`, then `<path> <sha256 of the file>` for `bats.toml`, for `bats.lock` when there is one and for every `src/**/*.bats`, in byte order of path (`LC_ALL=C sort`). It reads no git and no clock, so the same bytes give the same digest in any directory, with any mtimes and at any commit, and a dirty tree has an honest one; the dependencies' archives are named in `bats.lock` by their sha256, so the lock stands for them. Its `.sats` never changes and its `.dats` is written only when its bytes change, so a changed input compiles that one module again. A file that cannot be read is an error that says so. A project that does not staload it (the name in a comment or a string is not a staload) gets none and runs nothing; `_bats_*` files are not pruned as orphans. bats's own sources staload it and do not use it yet (the identity of this bats, for the stamp of a `build/` to come). The Rust bats had none (`tests/build-inputs`).

`build/` carries a stamp of who made it, and is kept only when the running bats would write the same one (`src/stamp.bats`, bats-lang/bats#267). `build/.bats_stamp` is plain text, `bats-stamp 1` and then `name value` lines: `bats` (the `_bats_inputs` digest of the running bats's own sources, which bats's own source staloads), `patsopt` (the sha256 of the cksum listing of `bin/patsopt`, `prelude`, `libats`, `share` and `ccomp` that `BATS_CACHE_DIR`'s key also uses, `toolchain_digest` in `src/cache.bats`, made at every build now and not only with that variable set), `cc` (the sha256 of `clang --version` and `clang -dumpmachine`, and of `wasm-ld --version` for a wasm mark, without the lines that name the install directory), `flags` (the flag templates patsopt and cc run with for the mark, `PATSHOME` written `$(PATSHOME)`, both profiles in one template since a `build/` holds both) and `mark` (the target and mode digit of `build/.bats_target`). No line holds a path, so a `build/` copied to another directory, or made on another machine with the same bats, ATS2 and C compiler, keeps (bats-lang/bats#250 made the C path-independent). After `cache_swap` has put the mark's `build/` in place (from its stash if it had been put aside: every stash carries the stamp of whoever made it, and is judged when it is swapped in), `check`, `build`, `test` and `run`'s build compare the stamp they would write with the one in `build/`. Equal: `build/` is kept, and a build that finds nothing changed runs no patsopt for the modules (the entry's generated module is still made again, as before). Different or missing: everything in `build/` but `.stash` is removed, one line on stderr names the first line that differs (`bats: dropping build/ (made by another bats: patsopt differs)`; `no stamp`, `the stamp format differs`, `mark differs` and `the stamp differs` are the others), and the build starts from nothing. A `build/` with no stamp, every one made before this, is dropped once; one that holds no build (no `.bats_target` and no stamp) is not dropped and says nothing. This replaces the hand-bumped `build/.bats_cache_id` (`cache_buster_id`), which went with the removal of every `.o` that it and a changed target caused: with the stamp that removal is dead, since `build/` is empty or this mark's by then (`target_changed` stays as the belt for an unreadable marker). The Rust bats had no stamp, so a `build/` of another compiler was trusted if its mtimes were right. `BATS_CACHE_DIR`'s key begins with the same `bats` digest, where it had the hand-bumped `patsopt-1` (the directory of the entries keeps that name, so entries of older bats are trimmed after 7 days as before). The test is `tests/build-stamp`.

The generated Makefile (`bootstrap/c`, `--to-c`) has `make install`, which puts the compiler at `$(PREFIX)/bin/bats` (`PREFIX` defaults to `~/.bats`).

These are the only allowed divergences. All other flags and behaviors must match the old Rust bats exactly.

## Safety Enforcement

Unsafe constructs (`castfn`, `$extfcall`, `$extval`, `$extype`, `$extkind`, `praxi`, `extern`, `assume`, `mac#`, `ext#`, `while` (`while*` with a metric is fine), `fun`, `fnx`, a `fun` group's `and` member or `fix` without termination metric (the `fun` of an arrow, `=<fun>`, is a function kind, not a declaration), `val rec`, `#pub prfun`/`prfn` without `primplement`, and what allocates without being linear: a `datatype` whose constructor carries data, a boxed tuple, record or list, a `cloref` or `cloptr` closure, a `lam` whose arrow does not make it a plain function or a linear closure, a `ref` made inside a function, a prelude word that builds a non-linear list, option or stream, libats/ML) are detected by the lexer (`SConstruct`, or a rejected `SPub`) and **enforced** before patsopt runs (`validate_project` in `src/lock.bats`, Rust's `preprocess_all`), as is the rule that no `implement` is on a call cycle (`src/recursion.bats`). They, and `%{ ... %}` blocks, are rejected outside `$UNSAFE begin...end` blocks in ALL packages — both safe and unsafe. `$UNSAFE begin...end` blocks themselves are rejected in `unsafe = false` packages.

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

## CI is pinned

Every input to CI is pinned in the source (bats-lang/repository-prototype#269),
so a commit that passes keeps passing:

* `bats.lock` is committed, and CI unpacks exactly the locked versions.
* The seed compiler is `bootstrap/c`, in the tree.
* The package repository is fetched at the commit in
  `.github/repository-version`, so what the fixture tests under `tests/`
  lock (`bats lock` against it, e.g. `lock-namespace`) is pinned too.
* `relock-pins.yml` in bats-lang/repository-prototype is called by commit.

Pins move only through a reviewed pull request that runs the same CI.
The daily `relock.yml` (the shared `relock-pins.yml`) relocks against the
newest repository, moves `.github/repository-version` to it, pushes
`relock/<date>`, opens a pull request listing the old and new versions
and dispatches `check.yml` on it, so a breaking publish shows as a red
relock pull request and main stays green. GITHUB_TOKEN cannot change
workflow files, so without a `RELOCK_TOKEN` secret that pull request lists
a workflow pin that would move instead of moving it.
