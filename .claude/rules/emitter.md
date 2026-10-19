---
paths:
  - src/emitter.bats
  - src/helpers.bats
  - tests/staload-alias/**
  - tests/dep-cross-module/**
  - tests/template-instances/**
  - tests/capturing-function/**
---

# Emitter and patsopt's output

`$X.member` is accepted when `X` is bound by ATS's `staload X = "..."` as well as by `#use ... as X`; packages staload bridge modules this way. The Rust bats reported "unknown alias" for a staload alias (`tests/staload-alias`).

A dependency's `#pub` names are not renamed. The Rust bats renamed each dependency file's `#pub` names to `__BATS__<pkg>_<name>` on its own, so a call from one module of a dependency to another module's `#pub` function (as in bridge) no longer resolved (`tests/dep-cross-module`).

A template instance patsopt finds no implementation for (`PMVtmpltcstmat` in the C it emits) fails `bats check` and `bats build` right after patsopt, with an error that names the template, shows the instance, and points to the `.bats` line that uses it. The Rust bats's check passed it, since check runs no cc, and only cc rejected it at build, with an error in the generated C (`tests/template-instances`). So does a lambda whose kind is a plain function but which captures a variable (`ATSERRORnotenvless` in the C), pointing to its `.bats` line (`tests/capturing-function`).
