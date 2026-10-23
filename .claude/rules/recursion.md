---
paths:
  - src/recursion.bats
  - tests/implement-recursion/**
---

# Implement call cycles

An `implement` on a call cycle is rejected: one that calls itself, directly or through other implements or top-level functions, in the package or in a dependency. A metric cannot be given to a function declared in a `.sats`, so ATS never checks an implement's recursion for termination; the Rust bats let it through. The calls are read from the sources (`src/recursion.bats`): a definition calls every definition its body names unqualified, an implement's name being visible in every file and another definition's only in its own, and the calls within a `fun` group, which its metric checks, are left out (`tests/implement-recursion`).

The definitions' names are kept in 64 lists by the hash of their first 256 bytes (the bytes a name is compared by), and an identifier is compared with the definitions that hash as it does and not with all of them (bats#368): quire's 158 files have some 8,000 definitions and 200,000 identifiers, and the comparison of each identifier with each name was 227 G of the 307 G instructions of one validation, which `bats fixtures` pays for each fixture (its probe) and again in the `bats check` it starts. The ids of the definitions, and so the edges and the implements reported, are the ones the single list gave. **Name hash.** A definition also keeps the full hash of its name (below 2^20), and an identifier is compared byte by byte only with a definition of the same hash; the 64 lists are the hash modulo 64.

**Scan memo.** `bats fixtures` checks one project once for each fixture with a module changed, so its probe calls `remember_scans` and the call-cycle check keeps the scan of each file for the next fixture of the same process. A kept scan is the file's definitions (identifiers as positions, each group moved by the difference of the group counter) and its own copy of the bytes. It is used only when the path, the size and every byte are the same, so no hash or time decides freshness, and a file of other bytes is scanned and kept beside it. The names are rebuilt from the bytes at the fixture's file index. A scan not used for 64 calls of `implement_cycles` is dropped. `bats check` and `bats build` keep nothing. Tested by `tests/fixtures/check.sh` (a snippet of the same size as an earlier one's; its mutant 22).
