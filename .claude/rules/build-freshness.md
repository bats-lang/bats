---
paths:
  - src/build.bats
  - src/closure.bats
  - tests/build-content-keys/**
  - tests/sats-change/**
  - tests/source-replaced/**
  - tests/toml-fields/**
---

# Build freshness

A build reuses what an earlier build produced when it is still fresh; the Rust bats rewrote every
`.sats` and `.dats` on every build, so its cache (input mtime equal to the recorded one) reran
patsopt on everything. A `.bats` is emitted again only when its bytes are not those its `.dats` was
emitted from (their sha256, kept in `<dats>.src`; an mtime cannot tell, since a relocked
dependency's files keep their archive's older mtimes, `tests/source-replaced`); its `.sats` is
written only when its bytes change, and then `build/.sats_changed` is written. Nothing reads a time
to decide what is fresh (bats#254: a build and its inputs are made in one whole second, a stash is
moved with its mtimes, a file is touched or replaced with an old time; each gave a build that did
the work again, or not at all). A module's C and its object each have a key beside them, `<C>.key`
and `<object>.key`, written after the tool passed and removed before it runs: for a C the check
memo's key (check-memo.md: the sizes and sha256s of the files patsopt read for the module, its
`.dats` and every `.sats`, `.hats` and staloaded dependency `.dats` it reaches, and the names of the
project's `.sats` and `.hats`), and in a build also `build/.sats_changed` (bats#323: a template body
changed in a dependency's `.dats`, its `.sats` the same, is instantiated again in the C of every
module that staloads that `.dats`, which the key of the module's own `.dats` and the stamp did not
see, so a dependent's C and object kept the old body), for an object the sha256 of its C, and for a
native object also a line naming its profile, debug or release (bats#320: the two profiles share
`build/`, a native object's cc flags are the profile's, `-g -O0` or `-O2`, and a release object was
reused by a debug build and the reverse), so a build of the other profile makes the object again,
and the preprocessed text of its C (below); the C's key and a wasm object's name no profile, since
patsopt's C is the same in both and the wasm cc flags are fixed (`-O2`, no `-g`), so a wasm object
is kept across debug and release builds (the other flags, the target and the mode are in
`build/.bats_stamp`, which drops a `build/` that differs). An output is fresh when it is there and
its key equals the one its inputs give now; the sizes are compared first, and a different size is a
changed file with nothing hashed. A key that is missing, short or garbled makes its output again.
`build/.sats_changed` is written whenever an emitted `.sats` changes, with new bytes each time (the
sha256 of what it held), so in a build a change to a `.sats` rebuilds every module's C, as before (a
check and a test do not read it: see check-memo.md), and a body-only change rebuilds its own module
and the modules that staload its `.dats` (a dependent of a library), no others (`tests/sats-change`,
`tests/build-content-keys`). The same keys serve the dependencies under a namespace (bridge, dom),
the extra modules of a dependency, the wasm objects, the binary's own module and the entry's object
(the entry's C is made again by every build, and an object is made again only when that C differs).
The cost: every no-change check reads and hashes each module's `.dats`, each C once, and the
preprocessed text of each object once (the run's digest table below); the tests are
`tests/build-content-keys`, which plays the no-change runs after a cold one with no settling, every
file of `build/` given a time in the future and long ago, a changed body of the same size, a changed
`.sats`, and a garbled or missing key.

## What of bats.toml reaches build/ (bats#381)

A `build/` is restored by content, so what matters of `bats.toml` is whether a field changes what bats writes into `build/` (the emitted modules, the C, the objects, the link) with the sources the same, and what judges it. Two ceilings remain, and both are an error, never a cut copy (keyword: toml-parse-whole; bats#463, toml#46): so neither limit cuts the document silently (the old `parse` copied 65536 bytes and kept 256 entries and said nothing). Before this, `upload`, the docs and the version writer read the first 8192 bytes, `read_toml` the first 65536 without saying so, emission the first 4096 for `unsafe`, and `bats add` the first 4096 and wrote them back over the file. The whole document is parsed first, and a syntax error anywhere is an error of every command, since nothing of it is cached. Target and mode are not fields: they come from the command line and the `#target` lines of the sources, and are the stamp's `mark` line.

### The test is written in bats (toml-fields, bats#446)

`tests/toml-fields` is a bats binary project, not a shell script.

* a walk in bats would be a second implementation of what `diff` is for.
* because `bats test` runs a project's own `$UNITTEST` tests in-process and cannot run the built compiler on a project it plants.

Research: Go's `testscript` runs each script in a fresh working directory with `exec`, `cmp`, `grep` and `exists` as its commands and `stdout`/`stderr` as files to compare (pkg.go.dev/github.com/rogpeppe/go-internal/testscript); rustc's run-make tests are `rmake.rs` programs, "small programs allowing arbitrary Rust code such as `rustc` invocations", compiled and run by compiletest (rustc-dev-guide, tests/compiletest); Zig's standalone tests are directories each with its own `build.zig` that the main build runs (`test/standalone/build.zig.zon`). All three run the compiler as a child process from a test program written in the compiler's own language, in a directory of the test's own, and compare files with a tool or a built-in: this test does the same, with the platform's tools as the comparison.

Failure keeps the work directory (`tests/toml-fields/work`, keep-on-fail.md), which `check.yml` uploads, and prints the log that explains it. Each class the test covers fails on a stand-in compiler, the real bats run with that one fault injected.

## Objects are keyed on what their compile reads and where it found it (bats#394, #338, #395, #477)

**The invariant.** A kept object is the object a clean build would write, except for the location
of the toolchain: the ATS2 home (`-I<PATSHOME>`, the `ccomp/runtime` headers) and the C compiler's
resource directory (`clang -print-resource-dir`, where its own headers such as `stddef.h` are). When
either moves, as a whole or alone, `build/` is kept (stamp.md) and so are the objects. What a kept
object then still carries of the old location, each asserted by `tests/build-toolchain-path` (the
object after the move is byte for byte the object before it, not a clean build's):

* the include file names in a native debug object's line table and declarations, for a header under
  the ATS2 home or the resource directory;
* a string a header under those writes with `__FILE__` or `assert`, in a release object and a wasm
  object too;
* the compilation directory (`DW_AT_comp_dir`, the checkout's directory): the stamp holds no path, a
  `build/` copied elsewhere is kept and its debug objects name the old directory
  (`tests/build-toolchain-path` T-checkout-move);
* the producer string (compiler version), which is in the stamp's `cc` line, so another compiler
  version drops `build/`.

Two things are outside what a key of preprocessed text names, and are not a difference between a
kept object and a clean build's: a file an assembler directive reads by name (`.incbin`, `asm` in a
user's `%{ %}`; bats emits none, and the user's C is in the key), and `__DATE__`, `__TIME__` and
`__TIMESTAMP__` (not in generated C; in a user's C two clean builds differ from each other).

The macOS SDK and sysroot are not in the exception: `SDKROOT`, `DEVELOPER_DIR` and the deployment
targets are hashed into the stamp (`put_cc_environment`), so another SDK path drops `build/`; bats
passes no `-isysroot`. A header an SDK provides is in the listing as found.

**What the compile reads or looks for, and what each is keyed on.**

* The C: its size and sha256 (`kept_size`, `kept_hash`).
* Every line of every header, comments and blank lines included (a native `-g` object's lines): the
  size and sha256 of the text, `clang -E -P -frewrite-includes` with the object's own flags. `-P`
  drops the line markers, the only lines of that text that hold an absolute path. `-P` alone prints
  a gap of more than eight lines as one newline (20 blank lines: 2 lines of output), so a longer
  comment would not be in its text; `-P -frewrite-includes` prints all of them.
* Every conditional, `__has_include` and `__has_include_next` included: `-frewrite-includes`
  writes the outcome of each (`#if 1 /* evaluated by -frewrite-includes */`, or `0`), so a new file
  that flips a branch changes the text.
* `-include FILE`: its bytes are inlined in the text and `-H` does not list it, nor what it
  includes. bats passes `-include` only for `build/_bats_wasm_runtime.h`, a file bats writes that
  holds no `#include`; `-imacros` is passed nowhere. A change that adds either must key its bytes.
* `#embed` (clang 18.1.3 rejects it), `-fprofile-use` and sanitizer lists: bats emits and passes
  none.
* The path each header was found at (a debug object, a `__FILE__` string): the listing, below.
* Flags, environment, compiler, profile: the profile line of the key and the stamp
  (`put_cc_environment` hashes `CPATH`, `C_INCLUDE_PATH`, `SDKROOT`, `DEVELOPER_DIR` and the
  rest, so a changed value of the search path's environment drops `build/`). bats has no
  per-project `-I`: its project directories are the including file's and, for wasm,
  `build/_bats_wasm_stubs`.

* R8. Why not a header's directory by its place in `-v`'s search list: it is injective only while
  the list keeps its shape. A directory created before the one that held the header, with the same
  bytes, takes the same number (`-isystem A -isystem B` with `x.h` in B, then `-isystem A -isystem D
  -isystem B` with `x.h` in D: both `#1 x.h`), so the path the object names changed and the key
  did not.

**Research.** ccache's direct mode records the paths of the include files a compile read with
their hashes and says "header files that were used by the compiler are recorded, but header files
that were not used, but would have been used if they existed, are not", "it currently can't check
with 100% accuracy if the existence of a new header file should invalidate the result", and under
"Caveats" "The direct mode fails to pick up new header files in some rare scenarios"
(https://ccache.dev/manual/latest.html, 4.14.2); it falls back to the preprocessor on a mismatch.
Its preprocessor mode hashes "the preprocessor output from running the compiler with `-E`" and,
with `hash_dir` (on by default), the current directory when the compile makes debug info; its
`base_dir` rewrites an absolute path under a named directory to a relative one in what is hashed
and warns against `/` as the base, which is what the roots are and why R4 refuses `/`. Bazel
(https://bazel.build/reference/be/c-cpp, https://bazel.build/docs/sandboxing): "All header files
that are used in the build must be declared in the `hdrs` or `srcs` of `cc_*` rules. This is
enforced."; the sandbox "prevents the action from accidentally using any input files that are not
declared", so a shadow is seen because an undeclared header is not there. Buck2
(https://buck2.build/docs/rule_authors/dep_files/): a dep file is "simply a list of all the inputs
that were used, one per line"; "If you fail to report some inputs you used, then your command will
not re-run when they change, and you'll get stale output."; it does not address a new header that
shadows one. clang's `-fdebug-prefix-map`, `-ffile-prefix-map` and `-fmacro-prefix-map` rewrite
the paths the compile writes and leave the markers of `-E`'s output as found, and change the
object's own flags. The ticket's other option, the depfile with the search list and an existence
line for each earlier directory of each header, needs the name each header was included as (the
found path less its directory is ambiguous for nested listed directories such as `/usr/include`
and `/usr/include/x86_64-linux-gnu`, so a probe can be of the wrong name and miss a shadow), does
not see `__has_include`, and does not see a listed directory renamed at its place that is not a
root; ccache's own way, the text with its line markers and the base directories rewritten, is a
second pass over megabytes of text and needs the compiler's install directory. Run: clang 18.1.3
(Ubuntu 1:18.1.3-1ubuntu1) and gcc 13.3 (for `-H`'s form only) on Linux; the macOS branches were
not run, and R3 and R7 are the rule for a clang whose output differs from what was run.

**Each file is digested once for a build (bats#398).** The native and the wasm key of a C (a wasm
bin's build makes both for the dependencies' C) both ask for the file's size and sha256 through the
run's digest table (`kept_size`, `kept_hash`, the table of check-memo.md), so the second key of a C
finds the line in the table (`digest_entry`); the preprocessed text is not in the table, since it is
made again for each key; the digest is not passed between the keys. A C's lines in an object's key
are its size and its sha256 (`kept_size`, `kept_hash`), the same for the native and the wasm key.
`-v` says `~ digested <path>` for each file really read, which `tests/build-content-keys` counts (a
C once in a build) and `tests/build-headers` (the entry's C once). The table is emptied at the start
of every build (`digests_forget` in `do_build`, after `cache_swap`), so a C seen by an earlier build
of the process, or of the other mark (its `build/` is another set of files), is read again; within a
build a C is written by patsopt before it is first asked for. So a check, which builds the native
mark and then the wasm one, digests a dependency's C once in each, not once in all: the two marks'
`build/` are different files.
