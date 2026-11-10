---
paths:
  - src/overrides.bats
  - tests/foreign-implement/**
---

# Implement of another package's template (overrides, bats#421, bats#565)

An `implement` that replaces what another package implements is rejected before patsopt runs, with a message that names the function and the declaring package. A `#pub` template is for a dependent to instantiate, not to replace.

**A hit.** A name a package leaves for its dependents to implement is an extension point and is not rejected: promise's `dispose`, which bridge implements for each payload type, is implemented by promise only for a few concrete types.

## The orphan rule (bats#565)

**The rule.** An `implement` of a template that another package declares (`#pub fun{...} name`, with the braces before the name) is for a type of the implementing package: the instance (the text of the `<...>` after the name) must name a type that a file of the implementing package declares, and the same instance is implemented once by the package. It does not depend on what the declaring package implements, now or later (quire#890: `dispose<Int>` was refused only because promise implemented it, while `dispose<jchunk>` beside it was accepted). The template of the package itself, and an ordinary function (not a template), are not under it; an ordinary function keeps the check above.

A `typedef` is an alias, not a type (`typedef x = int` makes `dispose<x>` the instance `dispose<int>`), so it does not count. With several arguments one owned argument is enough, as in Rust's rule that one of the types is local. The head of an argument is its type: `list_vt(mine)` has the head `list_vt`, which is a prelude type, as Rust's `Vec<Local>` is not local.

**Warning first.** The rule refuses code that compiled, so in the first compiler version that has it the findings are warnings (`warning:`, printed before the errors, the status unchanged), and `BATS_ORPHAN_ERROR=1` (anything but 0) makes them errors, as Swift's SE-0364 warns first and GHC's `-Worphans` is a warning only. The second step (error by default, the variable gone) is bats#568 (p2), filed with the change. What bats#421 refuses stays an error in this version: when the declaring package implements the instance the dependent replaces, the check prints the orphan finding as a warning and the replace error as before; with `BATS_ORPHAN_ERROR=1` the orphan error stands alone, so the error for an instance is the same whether the declaring package implements it or leaves it out (`orphan_dep_without` and `orphan_dep_with` in `tests/foreign-implement` have the same expected text).
**Research** (bats#565): Rust RFC 2451 (local type, no uncovered parameter before it, an error since 1.0), Swift SE-0364 (a warning for a retroactive conformance, `@retroactive` to say it is meant), GHC `-Worphans` (a warning only). The comment on the ticket has the sources and the choice.
