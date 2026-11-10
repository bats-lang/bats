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

* **`libs`**: the sha256 of the sorted sha256 of each file the dynamic loader resolves for `bin/patsopt`, no path in the line (`LIBS_SCRIPT` in `src/stamp.bats`, into `build/.bats_libs`). NOT CHECKED: the macOS branch was not run on a Mac. Decision, with what others do: ccache's `compiler_check` hashes only the compiler's mtime and size by default (content is opt-in), sccache hashes a Rust compiler's shared libraries in its sysroot and none for C, Bazel declares a toolchain's inputs at the toolchain; a correct libgmp changes nothing but a broken, patched or preloaded one changes what patsopt computes, so this is bats's: when in doubt rebuild (#317). It is judged as content, never by path: a private `libgmp.so.10` found through `LD_LIBRARY_PATH` and changed in place has one path whatever its bytes.
## Every digest is sha256's proved code (keyword: proved-sha256, bats#502)

bats hashes with `proved_init`, `proved_update` and `proved_finish` of the sha256 package (the stamp, the cache keys, the fixtures' memo, the validated records, the inputs digest, the file hash), at the types of the fast `init`, `update` and `finish`, so a digest is the one it was (sha256#29: the proved code is `DIGEST256` of FIPS 180-4). The proved code costs more in a debug (`-O0`) build, which is what bats's bootstrap compiler is (sha256's CLAUDE.md); a `bats check` slower by a factor of two is its own p0 ticket for the build flags.
