---
paths:
  - src/recursion.bats
  - tests/implement-recursion/**
---

# Implement call cycles

An `implement` on a call cycle is rejected: one that calls itself, directly or through other implements or top-level functions, in the package or in a dependency. A metric cannot be given to a function declared in a `.sats`, so ATS never checks an implement's recursion for termination; the Rust bats let it through. The calls are read from the sources (`src/recursion.bats`): a definition calls every definition its body names unqualified, an implement's name being visible in every file and another definition's only in its own, and the calls within a `fun` group, which its metric checks, are left out (`tests/implement-recursion`).

The definitions' names are kept in 64 lists by the hash of their first 256 bytes (the bytes a name is compared by), and an identifier is compared with the definitions that hash as it does and not with all of them (bats#368): quire's 158 files have some 8,000 definitions and 200,000 identifiers, and the comparison of each identifier with each name was 227 G of the 307 G instructions of one validation, which `bats fixtures` pays for each fixture (its probe) and again in the `bats check` it starts. The ids of the definitions, and so the edges and the implements reported, are the ones the single list gave.
