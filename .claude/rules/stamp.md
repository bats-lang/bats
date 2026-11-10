---
paths:
  - src/stamp.bats
  - tests/build-stamp/**
  - tests/stash-stamp/**
---

# The build stamp

`build/` carries a stamp of who made it, and is kept only when the running bats would write the same
one (`src/stamp.bats`, bats-lang/bats#267).
This replaces the
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
* **`link`**: for a native mark, the linker `clang -###` names for a link of an empty program (its `--version` without install-directory lines, and its own sha256) and the sha256 of each file that link reads, found by `-Wl,-t` (the C runtime start-up objects, the C library's linker script `libc.so`, `libc_nonshared.a`, libgcc), sorted, no path (`LINK_SCRIPT`, into `build/.bats_link`; the probe's files are `build/.bats_link_probe.*`, removed). Content only, since the paths differ between distributions (a gcc directory with its version): two machines with the same files have the same line, and a machine with another gcc patch release has another one, which costs a rebuild and never a stale object. For a wasm mark, `wasm-ld --version`, which is the one linker a wasm object is made with. The native link is run at every build, so a changed linker relinks the binary; the stamp names it so that a `build/` kept was made by the linker in use.
## Every digest is sha256's proved code (keyword: proved-sha256, bats#502)

bats hashes with `proved_init`, `proved_update` and `proved_finish` of the sha256 package (the stamp, the cache keys, the fixtures' memo, the validated records, the inputs digest, the file hash), at the types of the fast `init`, `update` and `finish`, so a digest is the one it was (sha256#29: the proved code is `DIGEST256` of FIPS 180-4). The proved code costs more in a debug (`-O0`) build, which is what bats's bootstrap compiler is (sha256's CLAUDE.md); a `bats check` slower by a factor of two is its own p0 ticket for the build flags.
