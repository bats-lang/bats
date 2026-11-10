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
the work again, or not at all).
## What of bats.toml reaches build/ (bats#381)

A `build/` is restored by content, so what matters of `bats.toml` is whether a field changes what bats writes into `build/` (the emitted modules, the C, the objects, the link) with the sources the same, and what judges it. Two ceilings remain, and both are an error, never a cut copy (keyword: toml-parse-whole; bats#463, toml#46): so neither limit cuts the document silently (the old `parse` copied 65536 bytes and kept 256 entries and said nothing). Before this, `upload`, the docs and the version writer read the first 8192 bytes, `read_toml` the first 65536 without saying so, emission the first 4096 for `unsafe`, and `bats add` the first 4096 and wrote them back over the file. The whole document is parsed first, and a syntax error anywhere is an error of every command, since nothing of it is cached. Target and mode are not fields: they come from the command line and the `#target` lines of the sources, and are the stamp's `mark` line.

### The test is written in bats (toml-fields, bats#446)

`tests/toml-fields` is a bats binary project, not a shell script.

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

