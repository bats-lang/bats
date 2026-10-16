# bats

The self-hosting Bats compiler. Bats is a programming language that compiles to ATS2.

## Pipeline

`.bats` → lexer → emitter → `.sats`/`.dats` → patsopt → `_dats.c` → cc → binary

## Build

```bash
# Bootstrap build (first time, requires bats-old)
bats-old build --repository ../repository-prototype

# Self-compilation
dist/debug/bats build --repository ../repository-prototype

# Type-check only
dist/debug/bats check --repository ../repository-prototype
```

## Architecture

- `src/bin/bats.bats` — entry point (argument parsing, command dispatch)
- `src/helpers.bats` — globals, string/builder helpers, process spawning, file I/O
- `src/lexer.bats` — tokenizer (produces spans from `.bats` source)
- `src/emitter.bats` — code generator (produces `.sats`/`.dats` from spans)
- `src/build.bats` — build pipeline (preprocessing, patsopt, cc, link)
- `src/commands.bats` — subcommands (init, test, upload, check, run, etc.)
- `src/cache.bats` — patsopt's C made path-independent, and the shared cache (`BATS_CACHE_DIR`)
- `src/facts.bats` — the commit a build is made from, for a project that staloads `_bats_facts.sats`

## Commands

- `bats build [--only debug|release|wasm]` — compile the project
- `bats check` — type-check without linking
- `bats run [--bin name]` — build and run a binary
- `bats lock --repository <dir>` — resolve dependencies to their newest versions and write `bats.lock`; with a `bats.lock`, the other commands use exactly the versions it locks
- `bats init binary|library` — create a new project
- `bats test` — build and run tests
- `bats upload --repository <dir>` — package and publish a library
- `bats clean` — remove build artifacts
- `bats tree` — show dependency tree
- `bats add <package>` / `bats remove <package>` — manage dependencies

## Setting up a machine

- `make install` in `bootstrap/c` (or in a `--to-c` directory) puts the compiler at `~/.bats/bin/bats` (`PREFIX=...` for elsewhere), beside the ATS2 toolchain bats keeps in `~/.bats/ats2`; put `~/.bats/bin` on `PATH` once.
- `BATS_REPOSITORY=<dir>`: the package repository, when `--repository` is not given (the flag wins).
- `BATS_CACHE_DIR=<dir>`: a cache of patsopt's output that every checkout of a project shares. An entry is keyed by the toolchain (patsopt and its prelude and libraries, by content) and by every file the module's staloads reach (by content), and only a run that passed is kept, so a hit never lets through what a cold build rejects. Entries unused for 7 days are removed; removing the directory is always safe.
- `bats with-env <env-file> <command> [args...]` runs a command with the variables of a dotenv file (the settings above), for a shell that reads no profile; the file wins, and the command's arguments and exit status are its own. A command name with no `/` is looked for in the PATH the command runs with (the file's, when it sets one). Limits: the file is at most 64 KiB and sets at most 1024 variables, the command line at most 4095 bytes. Known limits of the platform: bats runs the command as a child rather than replacing itself, so a signal sent to bats (`kill`) does not reach the command (it is left running, and what it holds stays held: in `bats with-env env bats check` the project lock and machine slots of the inner `bats check` stay taken until it ends), and a command ended by a signal has status 1 (bats-lang/process#51, #PROCESS_SIGNAL).

bats takes a lock on the project (flock on `bats.toml`) for every command that writes `build/`, `dist/` or `bats_modules/`, so two bats on one checkout take turns; the one that waits says so. `bats run` releases it before the program runs.

## The commit a build is made from

A module that staloads `"_bats_facts.sats"` gets the commit the build is made from: `BATS_COMMIT` (any revision git takes), else `HEAD`.

```bats
staload F = "_bats_facts.sats"

implement main0 () = println! ($F.bats_commit_version (), " (", $F.bats_commit_short (), ")")
```

`bats_commit_time (): int` (committer time, seconds since 1970), `bats_commit_version ()` (that time in UTC as `YEAR.MONTH.DAY.SECONDS`, as bats versions packages), `bats_commit_short (): string 7` and `bats_commit_sha (): string 40`. They are the commit's, never the build's, and a new commit compiles one small module again and nothing else.

## Dependencies

argparse, array, arith, builder, env, file, path, process, result, sha256, str, toml
