---
paths:
  - src/check_push.bats
  - src/built.bats
  - tests/check-push/**
  - scripts/bootstrap-c.sh
---

# bats check-push: the first-minute checks of a push (bats#575, from quire#973)

`bats check-push [--repository <dir>]` runs at the root of an app's git checkout (the repository is `--repository`, else `BATS_REPOSITORY`) and does three checks in order, stopping at the first failure. It is a subcommand written in bats (`src/check_push.bats`, run before bats's own arguments are read, as `affected` and `merge-proof` are); a pre-push hook calls it instead of the Python (`scripts/pre-push.py` of quire, a stopgap that names this ticket).

Exit 0 and the line `bats check-push: ok (locks, compiler, memory)`. Exit 1 and, on stderr, `bats check-push: check <n> (<name>) failed: <what>` and one line `fix: <the fix>`. Exit 2 and a usage line for any argument but `--repository <dir>`. Each failure is a constructor of a datatype of its own (`locks_result`, `compiler_result`, `memory_result`), matched with `case+`, so a new outcome is a type error until its fix is written.

1. **locks.** `.github/repository-version` is a full lowercase commit; the repository has that commit (`git cat-file -e <commit>^{commit}`); then every `bats.lock` of the tree (`git ls-files --cached --others --exclude-standard`, so tracked, or untracked and not ignored, at any depth) is read: each line is `<package> <version> <sha256>` (64 lowercase hex digits; blank lines are skipped) and the sidecar `<package>/<package with / as _>_<version>.bats.sha256` of that commit, read by `git show <commit>:<path>` and not from the files the clone has checked out, begins with the same sha256. No bats command compares a lock's sha256 without building the app (`bats lock --dry-run` with a zeroed sha256 printed `no changes`), and only `bats check` does, in minutes. The failure names the lock's path, its line, and the package and version. The listing of lock files is read from a 4095-byte buffer: a longer one is its own constructor, `LocksListingTooLong`, never a silent cut.
2. **compiler.** `.github/bats-version` is a full lowercase commit and this bats was built from it. A bats knows its commit as a fact of its build (`src/built.bats`, keyword built-commit), so there is no record beside the binary to forge or forget.
3. **memory.** `BATS_PATSOPT_MEM_MB` is `4096`, the default of the setup action's `patsopt-mem-mb`, which a pushing shell must have too.

## The built commit (keyword: built-commit)

A module that staloads `"_bats_built.sats"` gets `build/src/_bats_built` (`src/built.bats`, written beside `_bats_facts` and `_bats_inputs` by `write_built` in the build): `bats_built_commit (): built_commit`, a linear datavtype, `BuiltFrom of string 40` (the full SHA git gives for `BATS_COMMIT`, any revision git takes) or `BuiltUnnamed` (`BATS_COMMIT` unset or empty). A `BATS_COMMIT` git does not know is an error that says so. The `.sats` never changes and the `.dats` is written only when its bytes change, so a new commit compiles that one module again. A project that does not staload it (the name in a comment or a string is not a staload; `grep` reads `src/`) gets none and runs nothing.

**Why it is not `_bats_facts`.** The compiler's own commit cannot be in `bootstrap/c`: a commit cannot name itself, so the seed would change with every commit and `Verify bootstrap/c matches sources` could never pass. `scripts/bootstrap-c.sh` therefore unsets `BATS_COMMIT`: the seed has `BuiltUnnamed`, the same for every commit, and a compiler made from it is unnamed. `_bats_facts` would also need git to name a commit and, in a shallow clone (CI's), could not count it. Research: no comparable tool embeds a commit that the commit's own build output contains. Go's `-ldflags -X` and Rust's `build.rs` take the commit from the build, as here, and the Linux kernel's `LOCALVERSION` likewise.

**Naming the compiler** (what check 2 asks): in a checkout of bats at the pin, `make -C bootstrap/c debug/bats` (the seed, unnamed), then `BATS_COMMIT=<pin> bootstrap/c/debug/bats build --repository <dir>`; `dist/debug/bats` is then built from the pin and knows it. A compiler the setup action builds from the seed is unnamed, so CI does not run this check; the hook does, on the worker's machine.

**Bootstrapping this change.** The compiler that builds a source which staloads `_bats_built.sats` must already write the module, so the commit that added it was built in two steps: a compiler from a source without the staload (`check_push.bats` with check 2 stubbed), then that compiler built the final source and made `bootstrap/c` (CI builds the seed from `bootstrap/c`, which then has the module).

## Tested

`tests/check-push/check.sh` builds, from a copy of the sources in a git repository of its own, a compiler without `BATS_COMMIT` and one with it (and an unknown `BATS_COMMIT`, refused), plants a package repository of two commits and an app with pins and two locks, and plays: the all-good case (the repository by flag and by `BATS_REPOSITORY`; the flag wins); for check 1 a sha256 that differs, a version or a package missing, a version only a later commit of the repository holds (so the sidecar is read at the pin), a namespaced package on the second line, a lock deeper in the tree, a line with two or four fields or a sha256 in capitals, an untracked lock (read) and an ignored one (not), blank lines and no final newline, a pin file missing or not a commit, a repository without the pinned commit, no repository named; for check 2 a compiler without a commit, from another commit, and a bad or missing `.github/bats-version`; for check 3 the variable unset, another value and a longer value; the order (locks, then compiler, then memory, one failure reported); the arguments.
