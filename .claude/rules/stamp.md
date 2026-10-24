---
paths:
  - src/stamp.bats
  - tests/build-stamp/**
  - tests/stash-stamp/**
---

# The build stamp

`build/` carries a stamp of who made it, and is kept only when the running bats would write the same
one (`src/stamp.bats`, bats-lang/bats#267). `build/.bats_stamp` is plain text, `bats-stamp 2` and
then `name value` lines: `bats` (the `_bats_inputs` digest of the running bats's own sources, which
bats's own source staloads), `patsopt` (the sha256 of the listing of each file's sha256 of
`bin/patsopt`, `prelude`, `libats`, `share` and `ccomp` that `BATS_CACHE_DIR`'s key also uses,
`toolchain_digest` in `src/cache.bats`, made at every build, with that variable set or not), `cc`
(the sha256 of the digest of `clang --version` and `clang -dumpmachine`, without the lines that name
the install directory, and of the environment clang and the loader read (the loader's names are
below): `CPATH`, `C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, `OBJC_INCLUDE_PATH`,
`OBJCPLUS_INCLUDE_PATH`, `LIBRARY_PATH`, `COMPILER_PATH`, `SDKROOT`, `MACOSX_DEPLOYMENT_TARGET`, the
other Apple platforms' `*_DEPLOYMENT_TARGET`, `RC_DEBUG_PREFIX_MAP`, `RC_DEBUG_OPTIONS`,
`DEVELOPER_DIR`, `CCC_OVERRIDE_OPTIONS` and `CLANG_NO_DEFAULT_CONFIG`, the list in
`put_cc_environment` (`src/stamp.bats`, bats-lang/bats#322): each name and its value, or unset,
digested and never stored, so a `build/` made with another value is dropped as by another clang; the
Darwin names were not run on a Mac; `SOURCE_DATE_EPOCH` is not in the list, since clang reads it
only for `__DATE__` and `__TIME__`, which no emitted C uses, and a reproducible-build setup sets it
per commit, which would drop `build/` on every commit; `LLD_IN_TEST`, `LLD_VERSION` and
`LLVM_OVERRIDE_PRODUCER` are not, since no object or link bats makes reads them, and wasm-ld reads
none of the list), `libs` and `link` (below), `flags` (the flag templates patsopt and cc run with
for the mark, `PATSHOME` written `$(PATSHOME)`, both profiles in one template since a `build/` holds
both) and `mark` (the target and mode digit of `build/.bats_target`). No line holds a path
(each line is a digest, or a template that writes the ATS2 home as `$(PATSHOME)`), so a `build/`
copied to another directory, or made on another machine with the same
bats, ATS2 and C compiler, keeps (bats-lang/bats#250 made the C path-independent), and so do its
objects: the key file of an object (`<object>.key`) holds only the sizes and sha256s of its C, of
its preprocessed text with the listing of where each header was found (`<object>.i`, made and
removed within the run), and of this stamp; the listing writes the ATS2 home and the compiler's
resource directory as the placeholders `A` and `C` and every other path as clang printed it, so the
toolchain moving is not a change and a header found at another path is (build-freshness.md,
`tests/build-toolchain-path`). After `cache_swap` has put the mark's `build/` in place (from its
stash if it had been put aside: every stash carries the stamp of whoever made it, and is judged when
it is swapped in), `check`, `build`, `test` and `run`'s build compare the stamp they would write
with the one in `build/`. Equal: `build/` is kept, and a build that finds nothing changed runs no
patsopt for the modules (the entry's generated module is still made again, as before). Different or
missing: everything in `build/` but `.stash` is removed, one line on stderr names the first line
that differs (`bats: dropping build/ (made by another bats: patsopt differs)`; `no stamp`, `the
stamp format differs`, `mark differs` and `the stamp differs` are the others), and the build starts
from nothing. A `build/` with no stamp, every one made before this, is dropped once; one that holds
no build (no `.bats_target` and no stamp) is not dropped and says nothing. This replaces the
hand-bumped `build/.bats_cache_id` (`cache_buster_id`), which went with the removal of every `.o`
that it and a changed target caused: with the stamp that removal is dead, since `build/` is empty or
this mark's by then (`target_changed` stays as the belt for an unreadable marker). The Rust bats had
no stamp, so a `build/` of another compiler was trusted if its mtimes were right. `BATS_CACHE_DIR`'s
key begins with the same `bats` digest, where it had the hand-bumped `patsopt-1` (the directory of
the entries keeps that name, so entries of older bats are trimmed after 7 days as before).
`build/.bats_toolchain`, the listing the `patsopt` line hashes (made once per process), is no
mark's, as `build/.bats_valid` is: `cache_swap` neither puts it in a stash nor takes one out of a
stash (it removes that copy), since a listing swapped in from a stash made by another bats was
hashed for the stamp of the next mark, the stamp got a `patsopt` digest of nobody's toolchain and
the following check dropped that `build/` for "patsopt differs" and made it again (bats#434: quire's
static fixtures took 10 minutes each after the move of bats from 2ea56e1 to 3f8a5ea, restoring a
cache of the older bats; `tests/stash-stamp` plays a stale listing in `build/` and in the stash).
The test is `tests/build-stamp`.

## Libraries, loader and linker (bats#396, #397)

The stamp after its header is seven lines, in the order of the reason named when a stamp differs: `bats` (bats's own sources), `patsopt` (the ATS2 toolchain), `cc` (the C compiler's version and target and the environment clang and the loader read), `libs` (the shared libraries patsopt loads), `link` (the linker and the files a native link reads), `flags` and `mark` (the environment is in `cc`, which is judged before `libs`, so a `LD_PRELOAD` that adds a library to patsopt's list says `cc differs`, not `libs differs`).

* **`libs`**: the sha256 of the sorted sha256 of each file the dynamic loader resolves for `bin/patsopt`, no path in the line (`LIBS_SCRIPT` in `src/stamp.bats`, into `build/.bats_libs`). On Linux from `ldd` (the interpreter, libc and libgmp here, run at each build's stamp), a library `ldd` says is not found by its name; on macOS from `otool -L` followed through the libraries it names, a name with no file on disk (a dylib in the dyld shared cache) by the system build (`sw_vers -buildVersion`). A patsopt that is not a dynamic executable (a script) has no libraries; neither tool found is an error, as a missing clang is, since the stamp cannot be made. NOT CHECKED: the macOS branch was not run on a Mac. Decision, with what others do: ccache's `compiler_check` hashes only the compiler's mtime and size by default (content is opt-in), sccache hashes a Rust compiler's shared libraries in its sysroot and none for C, Bazel declares a toolchain's inputs at the toolchain; a correct libgmp changes nothing but a broken, patched or preloaded one changes what patsopt computes, so this is bats's: when in doubt rebuild (#317). It is judged as content, never by path: a private `libgmp.so.10` found through `LD_LIBRARY_PATH` and changed in place has one path whatever its bytes.
* **The loader's environment** (`put_cc_environment`, in the `cc` line, digested never stored): Linux `LD_LIBRARY_PATH`, `LD_PRELOAD`, `LD_AUDIT`, `LD_BIND_NOW`, `LD_BIND_NOT`, `LD_DYNAMIC_WEAK`, `LD_HWCAP_MASK`, `LD_ORIGIN_PATH` and `GLIBC_TUNABLES` (the names the glibc 2.39 loader holds, read with `strings`; left out because they only print or place: `LD_DEBUG`, `LD_DEBUG_OUTPUT`, `LD_PROFILE`, `LD_SHOW_AUXV`, `LD_VERBOSE`, `LD_WARN`, `LD_PREFER_MAP_32BIT_EXEC`), macOS the `DYLD_*` library and framework paths, `DYLD_INSERT_LIBRARIES`, `DYLD_IMAGE_SUFFIX` and `DYLD_ROOT_PATH` (not run on a Mac).
* **`link`**: for a native mark, the linker `clang -###` names for a link of an empty program (its `--version` without install-directory lines, and its own sha256) and the sha256 of each file that link reads, found by `-Wl,-t` (the C runtime start-up objects, the C library's linker script `libc.so`, `libc_nonshared.a`, libgcc), sorted, no path (`LINK_SCRIPT`, into `build/.bats_link`; the probe's files are `build/.bats_link_probe.*`, removed). Content only, since the paths differ between distributions (a gcc directory with its version): two machines with the same files have the same line, and a machine with another gcc patch release has another one, which costs a rebuild and never a stale object. For a wasm mark, `wasm-ld --version`, which is the one linker a wasm object is made with. The native link is run at every build, so a changed linker relinks the binary; the stamp names it so that a `build/` kept was made by the linker in use. `tests/build-stamp` plays a private `libgmp` changed in place and put back, `LD_PRELOAD` of a shim, each loader name set (empty is not unset), a linker wrapper found through `-B` that answers `--version` from a file and whose own bytes change, and a start-up object copied beside it and changed.
