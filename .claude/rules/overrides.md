---
paths:
  - src/overrides.bats
  - tests/foreign-implement/**
---

# Implement that replaces another package's implementation (overrides, bats#421)

An `implement` that replaces what another package implements is rejected before patsopt runs, with a message naming the function and the declaring package. A `#pub` template is for a dependent to instantiate, not replace.

**What the build does (experiment, raw output in the PR, E1 to E5).** A file's dats loads a dependency's lib.dats without an alias, and that opens none of its names: a bare `implement{} name` binds only to a declaration of the file's own package, so a package may declare and implement a name its dependency declares too (`toml`'s and `array`'s `get`; E1 and E2 build and print the package's own body for `get()` and the dependency's for `$D.get()`), and an unqualified implement of a name only the dependency declares fails in patsopt (E3). What reaches a dependency's name is the qualified `implement{} $A.name` with `A` bound in the same file (E4 replaces the dependency's body), by `#use P as A` (the lib file of P), by `staload A = "<root>/src/m.sats"` (that file), or an unaliased staload of a file of another package (its names open unqualified). Only the bound file's own `#pub` names are reached: a module its lib file staloads is not (E5), so nothing is walked or closed.

**A hit.** The qualified (or opened) name is declared by a `#pub` of the reached file; the package that declares it also implements that name (generic, or the same instance, the text of the `<...>` after the name with its blanks removed), so a name a package leaves for its dependents to implement is an extension point and is not rejected (promise's `dispose`, which bridge implements for each payload type: promise implements only `dispose<int>`, `<Int>` and `<bool>`); and the implement, the binding, the declaration and the declarer's implement are live in one of the four builds (native or wasm, test or not). A `#target` or `$UNITTEST` block the emitter blanks (`next_state`) holds no live fact, so a use the build loads nothing for creates no rejection. A type spelled another way than the declarer's instance is not matched. A staload whose path leaves the package is followed only for the unqualified case above and `staload A = "<root>/src/m.sats"`; a path that names no file of the project reaches nothing. Every package of `./bats_modules` is checked, so a transitive override (a dependency overriding its own dependency) is found as a direct one is.

Names are compared in full. Facts of a file are kept in `build/.bats_valid/facts <path>` as `uses` records are (`validated.md`).
