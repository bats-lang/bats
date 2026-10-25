---
paths:
  - src/overrides.bats
  - tests/foreign-implement/**
---

# Implement of another package's name (overrides, bats#421)

An `implement` of a name that a package it can see declares with `#pub` is rejected before patsopt runs, with a message naming the function and the declaring package. A `#pub` template is for a dependent to instantiate, not replace.

**Reading implemented (the visible set).** The packages an implementing package sees are itself and the closure of its `#use` lines over the packages of `./bats_modules`: a file's dats loads its own sats, then the lib.dats of each package its `#use` lines name (`build_prelude`, `src/emitter.bats`), and that lib.dats loads its own (`src/closure.bats`), so a transitive dependency is seen. The implementing package declaring the same name does not exempt the implement (its sats comes first in the prelude, so a seen declaration can be what the implement binds to). Two packages that do not `#use` each other do not see each other: neither is rejected for a generic name both declare.

Names are compared in full. Facts of a file are kept in `build/.bats_valid/facts <path>` as `uses` records are (`validated.md`).
