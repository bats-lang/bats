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
cp -R bootstrap/c /tmp/seed && make -C /tmp/seed debug/bats
```

Every change to `src/` or `bats.lock` must commit a regenerated `bootstrap/c` in the same PR. A worker does not run the local regeneration (about twelve minutes, a long run, which is a CI job): it pushes the change, and when the step "Verify bootstrap/c matches sources" fails, the run uploads the tree it regenerated as the artifact `bootstrap-c-regenerated-<head sha>`. Download it, copy it over `bootstrap/c`, commit and push; the next run verifies it (`.claude/rules/runtime-header.md`, "Getting the regenerated tree from CI"):

```bash
gh run download <run id> --name bootstrap-c-regenerated-<head sha> --dir /tmp/bootstrap-c-new
rm -rf bootstrap/c && cp -R /tmp/bootstrap-c-new bootstrap/c
```

`scripts/bootstrap-c.sh dist/debug/bats ../repository-prototype` is the command the artifact is made by.

CI builds the compiler from `bootstrap/c`, regenerates, and fails if the result differs. It also checks the fixpoint (the compiler built by itself emits the same C). Never edit `bootstrap/c/` by hand.

## Architecture

Entry point: `src/bin/bats.bats`
Shared modules: `src/helpers.bats`, `src/lexer.bats`, `src/emitter.bats`, `src/build.bats`, `src/docs.bats`, `src/commands.bats`, `src/lock.bats`, `src/recursion.bats`, `src/closure.bats`, `src/cache.bats`, `src/facts.bats`, `src/inputs.bats`, `src/pins.bats`, `src/affected.bats`

Dependencies: argparse, array, arith, builder, env, file, path, process, result, sha256, str, toml

## Workflow

All changes, even one byte, in ANY repo in bats-lang, must go through branch -> PR -> green -> merge. NEVER commit directly to main. Use `gh pr merge --merge` (no squash).

When creating a new repo: push an empty initial commit to main first (`git commit --allow-empty -m "Initial commit" && git push -u origin main`), then create a feature branch for the actual content. The first branch you push becomes the default, so main must exist before any feature branches.

Never blocked by another PR — add finishing that PR to the task list instead.

Never ask permission to keep going. Keep going until the success criterion is met.

Never wait. A PR in flight (CI running, a package publishing, a review pending) is never a reason to stop or idle: pick up the next independent task from the task list (this project always has one) and come back to the PR when its event arrives. Stopping is only for a decision that is the user's to make.

## Allowed Divergences from old Rust bats

These are the only allowed divergences. All other flags and behaviors must match the old Rust bats exactly.

Each divergence is kept with the notes of the area it is in, in `.claude/rules/` (the index at the end of this file names them; each loads when a file it covers is touched).

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

## Area notes

The notes are in `.claude/rules/`, each with `paths:` frontmatter, so a note loads only when a file it covers is touched. Each keeps its decisions, the research behind them, and what is proved apart from what is only tested.

A comment states its reason in one line and names the area by keyword; the detail lives in `.claude/rules/*.md`: search them for the keyword before changing the code.

| File | Area |
|---|---|
| `.claude/rules/cli.md` | Command line and repository |
| `.claude/rules/lexer.md` | Lexer checks and linearity |
| `.claude/rules/emitter.md` | Emitter and patsopt's output |
| `.claude/rules/wasm-prelude.md` | The wasm prelude |
| `.claude/rules/test-command.md` | bats test |
| `.claude/rules/recursion.md` | Implement call cycles |
| `.claude/rules/lock.md` | The lock and locked packages |
| `.claude/rules/build-freshness.md` | Build freshness |
| `.claude/rules/check-memo.md` | The check memo |
| `.claude/rules/shared-cache.md` | The shared cache (BATS_CACHE_DIR) |
| `.claude/rules/validated.md` | Validated records and the #use memo |
| `.claude/rules/ats2-install.md` | ATS2 install and the setup commands |
| `.claude/rules/runtime-header.md` | The C runtime header and bootstrap/c |
| `.claude/rules/project-lock.md` | Project lock |
| `.claude/rules/machine-slots.md` | Machine slots |
| `.claude/rules/patsopt-caps.md` | patsopt caps |
| `.claude/rules/write-errors.md` | Write errors |
| `.claude/rules/facts-and-inputs.md` | Facts and inputs modules |
| `.claude/rules/stamp.md` | The build stamp |
| `.claude/rules/fixtures.md` | bats fixtures |
| `.claude/rules/fixtures-memo.md` | The fixtures' memo |
| `.claude/rules/with-env.md` | bats with-env |
| `.claude/rules/setup-action.md` | The setup step other bats repositories call (#274) |
| `.claude/rules/check-pins.md` | bats check-pins: floating CI inputs (#390) |
| `.claude/rules/capture.md` | Captured runs: the outcome of a child whose output is longer than the buffer (#444) |
| `.claude/rules/affected.md` | The affected rule: which jobs of check.yml a change runs (#481) |
| `.claude/rules/keep-on-fail.md` | Test temp directories: `tests/keep-on-fail.sh` (#478) |
