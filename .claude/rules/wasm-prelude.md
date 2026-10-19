---
paths:
  - src/build.bats
  - tests/build-wasm/**
  - tests/wasm-*/**
---

# The wasm prelude

The wasm prelude defines `atspre_cloptr_free` (as ATS's `basics.cats` does, with `ATS_MFREE`). The Rust bats's wasm prelude lacked it, so a wasm binary that freed a closure imported it from a host that has none and failed to instantiate (`tests/wasm-cloptr-free`).

The wasm prelude defines `atspre_g0int_nmod_int`, `atspre_g1int_nmod_int`, `atspre_g1int_mod_int` and `atspre_neg_bool0`/`atspre_neg_bool1` (as ATS's `integer.cats` and `bool.cats` do). The Rust bats's wasm prelude lacked them, so `nmod` and `~b` in a wasm binary were imported from the host, which stubbed them to return 0 (`tests/wasm-prelude-arith`).

The wasm prelude defines `atspre_ptr_is_null`, `atspre_ptr_isnot_null` and their `ptr0`/`ptr1` forms (as ATS's pointer.cats does). The Rust bats's wasm prelude had only `atspre_ptr_isnot_null` and `atspre_ptr0_isnot_null`, so a wasm binary that made an arena (array's `arena_create` tests its region with `ptr1_isnot_null`) imported the rest from a host that has none and failed to instantiate (`tests/wasm-prelude-ptr`).

The wasm prelude defines ATS's literal pattern checks `ATSCKpat_int`, `ATSCKpat_bool`, `ATSCKpat_char` and `ATSCKpat_float` (as `pats_ccomp_instrset.h` does), which patsopt emits for a `case` on a literal. The Rust bats's wasm prelude had only `ATSCKpat_con0` and `ATSCKpat_con1`, so a wasm binary with such a `case` (css's unit table) imported `ATSCKpat_int` from a host that has none and failed to instantiate (`tests/wasm-prelude-patterns`).

The wasm prelude's `ATSCKpat_con1` checks that the value is a pointer (at least `ATS_DATACONMAX`, 1024) before it reads the constructor tag, as ATS's `pats_ccomp_instrset.h` does. The Rust bats's did not, so in a wasm binary a nullary constructor (a small integer) matched against a constructor with fields was read as an address: with its tag read as 0 it was taken for the first constructor, whose fields were then read and freed (`tests/wasm-prelude-con1`).

The wasm prelude defines the `uint` operations (`atspre_g0int2uint_int_uint`, `atspre_g0uint2int_uint_int`, `atspre_g0uint_add_uint` and the other arithmetic, comparison and bit operations, their `g1uint` forms) and the char comparisons (`atspre_eq_char0_char0`, `atspre_neq_char1_char1`, ...), as ATS's `integer.cats` and `char.cats` do. The Rust bats's wasm prelude lacked them, so a wasm binary that hashed with sha256 or compared chars imported them from a host that has none and failed to instantiate (`tests/wasm-prelude-uint`).

A wasm binary exports `bats_dynload`, the entry's dynload (named with ATS's `ATS_DYNLOADNAME`), which the host calls before `mainats_0_void`. The Rust bats's wasm had no way to run the dynloads, which a native binary's C `main` runs, so no module `val` was ever initialized: a module's `ref<int>(42)` was a null pointer, and reading it read address 0 (`tests/wasm-dynload`). The wasm prelude also defines `atspre_ptr_alloc_tsz`, with which `ref` allocates its cell, as ATS's pointer.cats does.
