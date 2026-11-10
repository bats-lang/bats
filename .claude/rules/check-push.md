---
paths:
  - src/check_push.bats
  - src/built.bats
  - tests/check-push/**
  - scripts/bootstrap-c.sh
---

# bats check-push: the first-minute checks of a push (bats#575, from quire#973)

`bats check-push [--repository <dir>]` runs at the root of an app's git checkout (the repository is `--repository`, else `BATS_REPOSITORY`) and does three checks in order, stopping at the first failure. It is a subcommand written in bats (`src/check_push.bats`, run before bats's own arguments are read, as `affected` and `merge-proof` are); a pre-push hook calls it instead of the Python (`scripts/pre-push.py` of quire, a stopgap that names this ticket).

1. No bats command compares a lock's sha256 without building the app (`bats lock --dry-run` with a zeroed sha256 printed `no changes`), and only `bats check` does, in minutes.
2. A bats knows its commit as a fact of its build (`src/built.bats`, keyword built-commit), so there is no record beside the binary to forge or forget.
3. `BATS_PATSOPT_MEM_MB` is `4096`, the default of the setup action's `patsopt-mem-mb`, which a pushing shell must have too.

## The built commit (keyword: built-commit)

**Why it is not `_bats_facts`.** The compiler's own commit cannot be in `bootstrap/c`: a commit cannot name itself, so the seed would change with every commit and `Verify bootstrap/c matches sources` could never pass. `scripts/bootstrap-c.sh` therefore unsets `BATS_COMMIT`: the seed has `BuiltUnnamed`, the same for every commit, and a compiler made from it is unnamed. `_bats_facts` would also need git to name a commit and, in a shallow clone (CI's), could not count it. Research: no comparable tool embeds a commit that the commit's own build output contains. Go's `-ldflags -X` and Rust's `build.rs` take the commit from the build, as here, and the Linux kernel's `LOCALVERSION` likewise.

**Naming the compiler** (what check 2 asks): in a checkout of bats at the pin, `make -C bootstrap/c debug/bats` (the seed, unnamed), then `BATS_COMMIT=<pin> bootstrap/c/debug/bats build --repository <dir>`; `dist/debug/bats` is then built from the pin and knows it. A compiler the setup action builds from the seed is unnamed, so CI does not run this check; the hook does, on the worker's machine.

**Bootstrapping this change.** The compiler that builds a source which staloads `_bats_built.sats` must already write the module, so the commit that added it was built in two steps: a compiler from a source without the staload (`check_push.bats` with check 2 stubbed), then that compiler built the final source and made `bootstrap/c` (CI builds the seed from `bootstrap/c`, which then has the module).

