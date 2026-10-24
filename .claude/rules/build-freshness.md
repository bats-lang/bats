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

A `build/` is restored by content, so what matters of `bats.toml` is whether a field changes what bats writes into `build/` (the emitted modules, the C, the objects, the link) with the sources the same, and what judges it. Every reader of the file is in the second table below, found by searching `src/` for every read of the path `bats.toml` and for each name that reaches one (`read_toml`, `read_manifest`, `read_whole`, `T.get`, `T.keys`, `T.value_at`; the searches and their output are in bats#429). A reader that parses (every one but `write_with_version` and the hashes) calls `read_toml` or `read_manifest` of `src/helpers.bats`: the file is read whole (`read_whole_m`), and then parsed. Two ceilings remain, and both are an error, never a cut copy: a file of 268435455 bytes or more is refused by the arena that holds it (`whole_of_open`, `src/helpers.bats`), and a manifest over 65536 bytes is refused by `read_toml` (`FileTooLarge`), because the toml package's `parse` copies 65536 bytes of its input and no more, and stops after 256 entries (a `[section]` header is an entry) without saying so (bats-lang/toml#46). The 65536 is refused here; the 256th entry is not seen from bats, so a key past it reads as unset until toml#46 is fixed. Before this, `upload`, the docs and the version writer read the first 8192 bytes, `read_toml` the first 65536 without saying so, emission the first 4096 for `unsafe`, and `bats add` the first 4096 and wrote them back over the file (`tests/toml-fields` has a library manifest of 8840 bytes whose `name` is past 8192, manifests of 65536 and 65537 bytes, and a `bats add` on one of 8767 bytes). The whole document is parsed first, and a syntax error anywhere is an error of every command, since nothing of it is cached. Target and mode are not fields: they come from the command line and the `#target` lines of the sources, and are the stamp's `mark` line. `tests/toml-fields` plays each row: a `build/` made under one manifest and restored under the other is kept whole and equals the cold build's `build/` (the objects aside, whose debug info names their directory), or the change is refused or rebuilt as the row says.

| field | effect | reaches `build/` | judged by |
|---|---|---|---|
| `[package] name` | names the archive of `upload`, the docs, and the package in a constraint's error text | no | nothing needs to: read whole at each command (`read_manifest`) |
| `[package] kind` | `build` and `run` refuse `lib`; `check` says library or binary and writes docs for a library; a path dependency in a `lib` is an error; default `lib` | no: `do_build` walks `src/` and `src/bin/` whatever the kind (a flip leaves the other kind's modules in `build/`, never linked) | read whole at each command (`project_kind`, `do_upload`, `generate_lib_docs`), never from `build/` |
| `[package] version` | the version `upload` injects, and the version of an installed dependency (`toml_version_is`) | no | read whole at each command (`package_value`, `write_with_version`, which zips the manifest whole into the archive) |
| `[package] trunk` | the branch `upload` takes a version from | no | read whole at each command (`package_value`) |
| `[package] ats2` | read by nothing; only its type (a string) is checked | no | n/a |
| `[package] unsafe` | a `$UNSAFE` block is emitted in an unsafe package and an error in a safe one; the dependencies are always emitted as unsafe | yes, the emitted `.dats` of the package's own modules, and only where the source has a `$UNSAFE` block | validation: its record's key has the flag, and it runs before any emission in `check`, `build`, `test` and `run`, so the flag false over a `build/` made with it true is an error; a failed emission leaves its `<dats>.src` empty, so it is never fresh. One reader of the flag, `read_unsafe_flag`, reads the whole file (the ceilings above) for emission, validation and the test runner |
| `[dependencies]` keys and constraints (`>=`, `!=`) | with a `bats.lock`, a locked version a constraint rules out is an error; without one, a package already in `bats_modules` is kept and the constraint is not applied to it (as the Rust bats) | only through the sources of `bats_modules`, which are keyed by content (`<dats>.src`, the closure keys): a relock that changes a version replaces its files and the modules are made again | the lock check (`walk_locked`), then content |
| `[dependencies]` `{ path = ... }` | the directory is copied afresh into `bats_modules/<name>` before each build | only through those sources | content |
| any other key or table (`[build]`, `[test]`) | none: bats reads none | no | n/a |

### Every reader of `bats.toml`

| reader | where (the search that finds it) | serves | bytes read | does | fields judged |
|---|---|---|---|---|---|
| `read_toml`, `read_manifest` | `read_toml` and `read_manifest` in `src/helpers.bats`: `grep -n -E 'implement read_toml|implement read_manifest' src/helpers.bats` | every parsing reader below | whole (`read_whole_m`); over 65536 is `FileTooLarge` | reads only | all |
| `package_value` | `package_value` in `src/commands.bats`: `grep -n 'fn package_value' src/commands.bats` | `upload` (via `read_trunk`, and the version) | whole | reads only | `version`, `trunk` |
| `do_upload` | `do_upload` in `src/commands.bats`: `grep -n 'implement do_upload' src/commands.bats` | `upload` | whole | reads only | `name`, `kind` |
| `write_with_version` | `write_with_version` in `src/commands.bats`: `grep -n 'fn write_with_version' src/commands.bats` | `upload` | whole (`read_whole`) | reads; writes the manifest with the version injected to `build/upload/bats.toml`, whole (the archive's copy) | `version` (rewritten) |
| the `zip` of `upload` | `do_upload` in `src/commands.bats`: `grep -n 'build/upload/bats.toml' src/commands.bats` | `upload` | whole (the zip command) | reads; archives | none |
| `generate_lib_docs` | `generate_lib_docs` in `src/docs.bats`: `grep -n 'implement generate_lib_docs' src/docs.bats` | `check` | whole | reads only | `name`, `kind` |
| `project_kind` | `project_kind` in `src/lock.bats`: `grep -n 'fn project_kind' src/lock.bats` | `build`, `run`, `check`, `lock` | whole | reads only | `kind` |
| `project_cons` | `project_cons` in `src/lock.bats`: `grep -n 'fn project_cons' src/lock.bats` | `lock`, `check`, `build` | whole | reads only | `[package] name`, `[dependencies]` |
| `project_pdeps` | `project_pdeps` in `src/lock.bats`: `grep -n 'fn project_pdeps' src/lock.bats` | `build`, `check` | whole | reads only | `[dependencies]` paths |
| a dependency's constraints | `dep_cons` in `src/lock.bats`: `grep -n 'fn dep_cons' src/lock.bats` | `lock` | whole | reads only | `[dependencies]` |
| a path dependency's constraints | `pdep_cons` in `src/lock.bats`: `grep -n 'fn pdep_cons' src/lock.bats` | `lock` | whole | reads only | `[dependencies]` |
| `toml_version_is` | `toml_version_is` in `src/lock.bats`: `grep -n 'fn toml_version_is' src/lock.bats` | `lock`, `fetch` | whole | reads only | `[package] version` |
| `toml_unsafe` via `read_unsafe_flag` and `dep_unsafe` | `toml_unsafe`, `read_unsafe_flag` and `dep_unsafe` in `src/lock.bats`: `grep -n -E 'toml_unsafe|read_unsafe_flag|dep_unsafe' src/lock.bats` | emission, validation (`grep -n -E 'read_unsafe_flag|dep_unsafe' src/build.bats src/lock.bats`), the test runner (`grep -n 'read_unsafe_flag' src/commands.bats`) | whole | reads only | `unsafe` |
| `do_add` (`bats add`) | `do_add` in `src/commands.bats`: `grep -n 'implement do_add' src/commands.bats` | `add` | none: opens bats.toml for appending (`append_file_from_builder`, `src/helpers.bats`) | appends one line; the rest of the file is neither read nor written | none |
| `do_remove` (`bats remove`) | `do_remove` in `src/commands.bats`: `grep -n 'implement do_remove' src/commands.bats` | `remove` | whole (`read_whole`) | rewrites whole through `write_settle`, only when a line names the package; no external tool | none |
| `put_file_sha256_m` | `put_file_sha256_m` in `src/helpers.bats` (the project's input digest, `inputs_digest` of `src/inputs.bats`) and `path_sha` in `src/fixtures.bats`: `grep -n -E 'put_file_sha256_m|path_sha' src/helpers.bats src/fixtures.bats` | the inputs digest, the fixtures' memo | whole, in 64 KiB chunks | reads only | none: the file's content |
| `project_lock_take` | `project_lock_take` in `src/helpers.bats`: `grep -n 'implement project_lock_take' src/helpers.bats` | `check`, `build`, `test`, `run`, `lock`, ... | none: `flock` on the file opened read-only | reads nothing | none |
| `init` in `src/commands.bats` and the existence checks of `src/build.bats`: `grep -n '"bats.toml"' src/commands.bats` and `grep -n '/bats.toml' src/build.bats` | `init`, `fetch`, the closure walk | none: whether the file exists | reads nothing | none |

The output buffers of the toml package's calls are not readers of the file; each is a ceiling on one value, and a value that does not fit makes `T.get` answer none, read as unset: a name, a version or a kind of 256 bytes or more (32 for the kind, 16 for `unsafe`), and a constraint or a path of more than 4096 bytes (`grep -n 'T.get' src/lock.bats`; the whole document is 65536 bytes at most). The key lists (`T.keys`, `grep -n 'T.keys' src/lock.bats`) have 65536 bytes, as many as the document holds.

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

**The rules** (`src/helpers.bats`, the preprocess keyword).

* R1. The preprocess input. For an object whose C is `<dir>/<name>`, bats writes
  `<dir>/<name>.pre.c` holding the one line `#include "<name>"` and preprocesses that:
  `clang <the object's flags> -E -P -frewrite-includes -H -o <object>.i <dir>/<name>.pre.c`. The
  compile reads the C itself. A quoted include in the C is still searched from the C's directory
  (the wrapper is in it). What differs between the wrapper and the compile is `__INCLUDE_LEVEL__`
  and `__BASE_FILE__`, which are constants of the C's path and bytes, both in the key, and which
  bats's emitted C uses neither. The text and the listing the key digests are the ones made before
  the compile (`run_cc` preprocesses, then compiles, then `key_record` digests what was made), so a
  header changed while cc runs is a key that is not equal at the next check, never a stale hit.
  The wrapper, `<object>.i` and the listing file `<object>.h` are removed after.
* R2. The stream. clang's stderr is read in 64 KiB chunks by a state machine that holds one line
  (at most 512 KiB, 128 times PATH_MAX; longer is a failure) and nothing else, so its total size
  has no bound; stdout is `/dev/null`. A line that starts with d >= 1 dots is a header line when a
  space and a non-empty path follow the dots to the end of the line; a line of only dots, or dots
  and a space with no path, is a failure; dots followed by anything else (`./inc/a.h:3:1: warning:
  ...`) are a diagnostic and are ignored, as is a line with no dot first. (GCC's manual for `-H`:
  "Print the name of each header file used, in addition to other normal activities. Each name is
  indented to show how deep in the '#include' stack it is.")
* R3. The positive control. The first header line must be depth 1 with the path of the C as handed
  to the preprocess; anything else is a failure. A clang that prints no `-H` lines, prints them
  elsewhere or in another form is therefore a failure for every object, and a C with no include of
  its own (the wasm runtime header is `-include`d, which `-H` does not list) has exactly one line.
  The marker string of `-frewrite-includes` is not read.
* R4. The roots. The ATS2 home (`ph`, kind `A`) and the compiler's resource directory (kind `C`),
  asked once per run and kind as `clang <that kind's flags> -print-resource-dir` (native: no flags;
  wasm: `--target=wasm32 -O2 -nostdlib -ffreestanding ...`, the list `wasm_cc_argv` builds). A root
  has its trailing slashes stripped and must be absolute and not `/`; the answer must be one line
  and exit 0, else it is a failure. A `..` in it is used as printed. Roots and header paths are
  compared as spelled, never resolved (`-print-resource-dir` and the path `-H` prints for a builtin
  header are the same string, for a compiler reached through a link as well). A path is under a root
  when it begins with the root and a slash; the rest is the path after that slash; the longest root
  wins, and equal roots are one root of kind `A`.
* R5. The roots are per run, in memory: asked where `ph` is made (the start of a check, build, test
  or run's build) and carried in `ph`'s array ([0, 4096) the ATS2 home, [4096, 8192) the native
  resource directory, [8192, 12288) the wasm one) to the callers of the preprocess. No file.
* R6. The line. Each header line becomes `<dots> <kind> <rest>` with kind `A` or `C` and the rest
  below the root, or `<dots> - <path>` for a path under no root. Distinct paths give distinct lines
  unless they differ only in the prefix of a root. The listing is appended to `<object>.i`, which
  the key digests (size, then sha256); the key file holds only sizes and hashes.
* R7. A failure (R2, R3, R4, a clang that exits non-zero, a stderr read that fails, a listing that
  cannot be written): `<object>.i`, the wrapper and the listing are removed, no key is written, the
  object is made again at every check, never kept, and one line is said on stderr (`bats: <C>:
  clang's header listing could not be used (<what>): the object is made again`; a root's failure
  once per run and kind). The compile and the build go on.
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

**The tests** (`tests/cc-cases.sh` is their library; `tests/<file>/check.sh <bats> <repository>
<case>` runs one case alone, with no case all of them, reporting each that fails):
`tests/build-headers` (43 cases: shadows by `C_INCLUDE_PATH`, `CPATH`, a quoted header beside the
including file and the wasm stubs directory, with other bytes and with the very same bytes, native
debug, native release and wasm, each equal to a clean build's; a shadow deleted again;
`__has_include`; `#include_next`; a directory created later; a symlinked directory; relative and
nested spellings; a quoted header over one found by `-I`, both outside the system directories;
a header changed in place; blank and comment lines grown from nine to twenty,
which `-P` alone prints as one newline; a header edited while cc runs; clang's output varied (no
`-H`, a line of dots, a diagnostic that begins with a dot, dots with no path, noise, an unreadable
header, the marker renamed, the resource directory failing, empty, relative, on two lines, `/` and
with `..`); a C with no include of its own; 12,000 headers) and `tests/build-toolchain-path` (28
cases: the toolchain moved whole and in part, native debug, native release and wasm; the roots
nested in each other; a sibling directory whose name starts with the ATS2 home's; a relative
directory that spells like the rest of a path under a root; roots behind links; a trailing slash;
a native and a wasm resource directory that differ; the search list gaining and losing a directory;
the toolchain moved onto a directory the environment lists; shadows after the move and in the
toolchain's directories; `SDKROOT`; a `build/` copied to another directory; and the control, a
stand-in clang that drops `-P`, whose move makes the object again) and the stamp's.

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
