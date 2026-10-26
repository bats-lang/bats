---
paths:
  - src/overrides.bats
  - tests/foreign-implement/**
---

# Implement that replaces another package's implementation (overrides, bats#421)

An `implement` that replaces what another package implements is rejected before patsopt runs, with a message that names the function and the declaring package. A `#pub` template is for a dependent to instantiate, not to replace.

**What the build does.** A file's dats loads a dependency's lib.dats without an alias, and that opens none of its names. A bare `implement{} name` therefore binds only to a declaration of the file's own package, so a package may declare and implement a name its dependency declares too (toml's and array's `get`). An unqualified implement of a name only the dependency declares fails in patsopt, and is left to it. What reaches a dependency's name is the qualified `implement{} $A.name`, with `A` bound in the same file by `#use P as A` (the lib file of P), by `staload A = "<root>/src/m.sats"` (that file), or by an unaliased staload of a file of another package (its names open unqualified). Only the bound file's own `#pub` names are reached, never a module its lib file staloads, so nothing is walked. The experiment that shows this is in the pull request of #421.

**A hit.** The reached file declares the name with `#pub`, and the package that declares it also implements that name: generically, or for the same instance (the text of the `<...>` after the name, blanks removed). A name a package leaves for its dependents to implement is an extension point and is not rejected: promise's `dispose`, which bridge implements for each payload type, is implemented by promise only for a few concrete types.

**Builds.** The implement, the binding, the declaration and the declarer's implement must be live in one build (native or wasm, test or not). A `#target` or `$UNITTEST` block that the emitter blanks (`next_state`) holds no live fact, so a use the build loads nothing for creates no rejection. Every fact is read once with the builds it is live in, so the record of a file does not depend on the build.

**Limits.** A type spelled another way than the declarer's instance is not matched. A staload whose path leaves the package is followed only for the unqualified case above and for `staload A = "<root>/src/m.sats"`. Every package of `./bats_modules` is checked, so a dependency replacing its own dependency's implement is found as a direct one is. A package is named by its root under `./bats_modules`, the text of its `#use`; the package itself is package 0.

**Names and bounds.** Names are compared in full. The length of a name is bounded by the array allocation, in the type of `name_of_range`; a name longer than that is a fact of its own (`OversizedName`) and the check reports the file, since it cannot compare it. Offsets and package numbers carry their bounds in their types.

**Records.** The facts of a file are kept in `build/.bats_valid/facts <path>` as the `uses` records are (`validated.md`): the key holds the sha256 of bats's inputs, the path and the bytes of the file, so a record written by another compiler is not trusted, and `-v` says each file lexed (`  ~ facts lexed <path>`). `tests/foreign-implement` plays the rejected cases, the accepted ones and the record.
