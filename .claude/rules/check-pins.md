---
paths:
  - src/pins.bats
  - tests/check-pins/**
---

# bats check-pins (bats#390, repository-prototype#353)

`bats check-pins <file>...` fails on the inputs of CI that move under a passing commit. It replaces `scripts/check-pins.sh`, which read `uses:` lines alone (repository-prototype#352 found eight floating inputs it could not see). It is a subcommand written in bats (`src/pins.bats`, run before bats's own arguments are read, as `with-env` is), per quire#646: we write bats, not shell. Name, by research: pinact's `run` and zizmor discover the workflows themselves when none is named; `--discover` is the mode that does it here and no argument stays the usage (status 2), which the setup action's probe relies on.

Name, by research: `check-pins` follows the script it replaces and the repository's verb-noun subcommands (`clone-repository`, `record-commit`); `bats check` is the type-check. Comparable tools: pinact (`run --check`), ratchet (`check`) and zizmor's unpinned-uses audit name the thing checked and read `uses:` only.

## The rules (a workflow or action, by file name anything else than `package.json` and `ats2.bats`)

* `apt-get install` is allowed (the runner image is pinned).
* `peerDependencies` are the package's API, not an install, and are not read. It is read by lines, not parsed (the json package would add a dependency to the compiler).
* the ATS2 pin is in `src/ats2.bats` alone, bats#283.

## Exceptions

`# unpinned: <reason>` on the line of an input, or above it (on a comment line, with only comment lines between), is accepted and listed on stdout (`file:line: unpinned: <reason>`), so each is a decision somebody wrote. An exception with no reason, or one that exempts nothing (a stale decision: a blank line, a code line that is clean, or the end of the file after it), is a failure, as linters that report unused suppressions do (ESLint's `--report-unused-disable-directives`). A `package.json` has no comments, so its exception is a marker file in the directory (below, keyword: check-pins-fixture).

## What is proved, tested and limited

Every read of the file's bytes is proved in range by the types (`src/pins.bats` is the style of `with_env.bats`: `read_byte` with `p < n`, spans indexed, every loop with a metric); no position is moved into range: `byte_in` answers 0 at and past a span's end, a value for a read beyond the span, never a read.
## A pnpm workspace's lock (bats#484, keyword: pnpm workspace lock)

Decision: a `package.json` with dependencies has its lock when a lock is beside it, or when the nearest directory at or above it that holds a `pnpm-workspace.yaml` also holds a `pnpm-lock.yaml`; the walk goes up one directory at a time through the path as named (the empty directory at the top of a relative path is the current directory), stops at the first `pnpm-workspace.yaml` (an inner workspace is its own root, so the outer lock does not cover it), at the filesystem root, and at a `..` component (the path does not say what is above it). No file is read or parsed: only whether the two files exist, so `pnpm-workspace.yaml` is never matched by pattern (YAML is not read in this compiler, quire#646).

Research: pnpm defines a workspace by a `pnpm-workspace.yaml` at its root (pnpm docs, "Workspace") and, with `shared-workspace-lockfile` true (the default; pnpm docs, "Settings"), keeps one `pnpm-lock.yaml` for all members, at that root, with an importer for each; a lock beside each member would contradict the repository that has the workspace. pnpm itself finds the root by looking for `pnpm-workspace.yaml` in the current directory and then each parent, nearest first, which is the walk here. npm (the `workspaces` field of the root `package.json`, one `package-lock.json` at the root), yarn and bun (the same field, `yarn.lock` and `bun.lock` at the root) name their members inside a `package.json`, not in a file whose existence says it: deciding them needs the root's `package.json` read for that field, which this by-lines reader does not do, so a member of those workspaces still needs a lock beside it. `--discover` and the caller's file names are relative to the repository root (the audit runs it there), so the walk reaches the workspace root; a `..` path below a workspace root is not walked past.

Proved: the walk's reads of the path are in range by the types (`component_start` and `parent_dir` index below 4096 and `workspace_lock` has the metric `e - a`).


## A directory of test fixtures: `check-pins-fixture` (bats#504, keyword: check-pins-fixture)

Rule: a file named `check-pins-fixture` in a directory exempts every `package.json` at or below that directory from the exact-version and lock rules, and its first line is the reason (text after blanks are trimmed). Each exempted file is printed on stdout as `<package.json>:1: unpinned: <reason>`, as a workflow exception is. Two failures, as an unused `# unpinned:` is one: a marker whose first line has no text (the package.json files under it are then checked as if it were absent), and a marker with no `package.json` at or below it among the files checked (a stale decision; `--discover` lists markers and package.json files alike, with explicit arguments the marker and the package.json files are named together, as `src/ats2.bats` is). The marker is found by its existence, walking up from the `package.json` one directory at a time exactly as the pnpm workspace lock does (`parent_dir`; the nearest marker decides; the walk stops at the top of the path, the filesystem root and a `..` component), so an inner marker covers its own subtree and a sibling directory or the directory above it is not covered. "At or below" for the stale check is the same walk (`reaches_dir`), not a textual prefix. No YAML or JSON is read, and only the first line of the marker is read, from a whole-file read bounded by the types like the others.

Why a file: a fixture's ranges are the point of the fixture (a relock test moves a dependency inside its range), so they cannot be made exact; weakening the rule for every `package.json`, or listing paths in an allowlist, would hide real floating inputs. A marker travels with the directory it exempts, the reason is a line a reviewer reads in the diff that adds it, and the checker reads existence and bytes only (quire#646).

Research (how comparable tools declare a directory of fixtures):

* ESLint: file ignores are `ignorePatterns`/`ignores` patterns in a config, and a disable comment takes a description after `--` ("must come after the configuration", docs "Configure Rules"); `--report-unused-disable-directives` reports a directive that suppresses nothing, which is the model for the empty and stale cases here. Its path patterns live in a config far from the directory, which is what a marker avoids.
* Dependabot: `ignore` filters dependencies by name, version or update type, and `directories` (globs) says where manifests are looked for (docs "Dependabot options reference"); neither is a per-directory declaration with a reason, and neither reports a stale entry.
* Renovate: `ignorePaths` globs in the config; the `:ignoreModulesAndTests` preset ignores `**/test/**`, `**/tests/**`, `**/__fixtures__/**`, `**/examples/**` and similar by directory name, so a tool skips fixtures by convention. A name convention here would exempt a real `tests/` package and gives no reason, so it is not used.
* zizmor: `rules.<id>.ignore` entries `file[:line[:col]]` in `zizmor.yml`, and `# zizmor: ignore[rule]` inline with an optional trailing explanation; it does not document a report of unused ignores. pinact: `.pinact.yaml` with `files[].pattern` and `ignore_actions` (name and ref regexes), whose own docs steer new configurations to `rules` with `ignore`. All are a central list, and the entry carries no reason.
* npm: `.npmignore` is read in every subdirectory of a package, like `.gitignore` (docs "Developers"), so a file whose existence changes the rules for its directory and below is established practice; its content is patterns, where a marker's content is a reason.

Proved: the walk and the comparison index below 4096 by their types (`same_range` has the metric `len`, `reaches_dir` and `marker_dir` `e - a`), the reason is read inside the file by `line_end`, `skip_blank` and `trim_end`.
