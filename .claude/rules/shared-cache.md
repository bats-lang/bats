---
paths:
  - src/cache.bats
  - tests/shared-cache/**
---

# The shared cache (BATS_CACHE_DIR)

patsopt's C names the project's files relative to the project (`build/src/m.dats`): after patsopt succeeds, `src/cache.bats` takes the project's directory out of the paths it wrote, plain in comments and mangled into symbol names, where it is followed by `build/` (`build_057_`), as GCC's `-ffile-prefix-map` or Rust's `--remap-path-prefix` do. The same sources give the same C at any path, so a `build/` and the shared cache below are valid wherever the checkout is; ATS's `$mylocation` names its file relative to the project. The Rust bats's C held the absolute path, so a `build/` was valid only where it was made. patsopt writes `<C>.raw`, which is rewritten beside the C and renamed into place, so a bats stopped at any point never leaves a C that is half written or still holds the path (`tests/project-lock`, `tests/shared-cache`).

With `BATS_CACHE_DIR` set, patsopt's C is kept there, under a key of what patsopt reads: the toolchain (a listing of `$PATSHOME/bin/patsopt` and the files of `prelude/`, `libats/`, `share/`, `ccomp/` by `cksum`, made once per process), patsopt's arguments, and the module's `.dats` with every file its staloads and includes reach (`patsopt --depgen`, followed to the end), each by path and sha256. A module bats would run patsopt on is looked up first; a hit is copied into place and checked as patsopt's output is (template instances, capturing lambdas), and only a run that passed those checks is kept, so a hit never passes what a cold build fails. Entries are written beside their place and renamed into it, so checkouts share the cache with no lock; one unused for 7 days is removed (at most once a day, after a store). The Rust bats had no cache shared between checkouts (`tests/shared-cache`).
