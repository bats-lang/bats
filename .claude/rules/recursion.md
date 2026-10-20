---
paths:
  - src/recursion.bats
  - tests/implement-recursion/**
---

# Implement call cycles

An `implement` on a call cycle is rejected: one that calls itself, directly or through other implements or top-level functions, in the package or in a dependency. A metric cannot be given to a function declared in a `.sats`, so ATS never checks an implement's recursion for termination; the Rust bats let it through. The calls are read from the sources (`src/recursion.bats`): a definition calls every definition its body names unqualified, an implement's name being visible in every file and another definition's only in its own, and the calls within a `fun` group, which its metric checks, are left out (`tests/implement-recursion`).
