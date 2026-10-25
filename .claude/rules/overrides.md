---
paths:
  - src/overrides.bats
  - tests/foreign-implement/**
---

# Implement of another package's name (overrides, bats#421)

An `implement` of a name that a package it can see declares with `#pub` is rejected before patsopt runs, with a message naming the function and the declaring package. A `#pub` template is for a dependent to instantiate, not replace.

**Reading implemented (what the implementing file sees).** Exactly what the build loads, not what closure.bats links: a file's dats loads its own sats, the lib.dats of each package it `#use`s (its sats gets the alias only, which opens nothing, `emit_one`/`build_prelude`), and the sats of each module it staloads unaliased (`staload "./m.bats"`, both sats and dats). A lib.dats loads what a dats loads (its `#use` packages' lib.dats, its staloaded modules' sats); a sats loads only what it staloads. So the files seen from an implementing file are reached from its own `#use` and staload lines, through the lib file of each package, and a dependency's other modules open nothing but through lib's staloads. The implementing file's package declaring the same name does not exempt the implement (its sats comes first in the prelude, so a seen declaration can be what the implement binds to). Two packages that do not load each other are not rejected for a generic name both declare. A package is named by its root under `./bats_modules` (the text of its `#use`).

Names are compared in full. Facts of a file are kept in `build/.bats_valid/facts <path>` as `uses` records are (`validated.md`).
