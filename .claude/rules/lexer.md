---
paths:
  - src/lexer.bats
  - tests/restricted-keywords/**
  - tests/unsafe-extcode-end/**
  - tests/unittest-blocks/**
  - tests/unterminated/**
  - tests/linear-heap/**
  - tests/recursion-metrics/**
  - tests/prelude-builders/**
---

# Lexer checks and linearity

`castfn`, `praxi`, `extern` and `assume` at the start of a `#pub` declaration are rejected as unsafe constructs; the Rust bats let a `#pub` declaration through unchecked (`tests/restricted-keywords`).

The `end` that closes `$UNSAFE begin` is found in code only; the word `end` in the C of a `%{ ... %}` block (a comment, say) does not close it. The Rust bats closed the block there, which broke the build (`tests/unsafe-extcode-end`).

Every recursion needs a termination metric outside `$UNSAFE`, as a `fun` does: `fnx`, the `and` members of a `fun` or `fnx` group, and `fix` lambdas are rejected without `.< metric >.`, and `val rec` (which cannot carry one) is rejected. The Rust bats checked only the `fun` keyword, so these recursed with no termination proof (`tests/recursion-metrics`).

A `$UNITTEST` block is lexed as code, like a `#target` block (a begin span, its contents' spans, an end span), so an unsafe construct in it is rejected as anywhere else; the Rust bats copied a block's text verbatim, unchecked. A block closes at its own `end`, not at the first `end` inside it (a `let`'s), where the Rust bats closed it. A `#target` block inside a `#target` block keeps its code; it was dropped (`tests/unittest-blocks`).

A string literal whose last byte is an escaping backslash is an unterminated string, reported as the Rust bats reports any other ("unterminated string literal"); the Rust bats's lexer stepped past the end of the file there and panicked (`tests/unterminated`).

What allocates must be linear outside `$UNSAFE`, since wasm has no garbage collector and a non-linear boxed value is never freed. Each of these is rejected, with a message that names the linear form to use: a `datatype` with a constructor that carries data (use `datavtype`; `of ()` is nullary); a boxed tuple, record or list (`'(`, `'{`, `'[`, `$tup`, `$rec`, `$list` and their `_t` forms; use `@( )`, `@{ }`, `$tup_vt`, `$rec_vt`, `$list_vt`); a non-linear closure (`cloref`, `cloref0`, `cloref1`, `cloptr`, `cloptr0`, `cloptr1`; use `lincloptr1`, made with `llam`); a `lam` whose arrow leaves its kind to its context (given to a cloref parameter, the prelude's included, it is a `cloref1` closure; use `llam`, or the arrow `=<fun1>` for a plain function; `lam@` is a flat closure and stays); and a `ref` made inside a function (`ref<...>(` or `ref_make_elt` on an indented line; a top-level one is made once and stays). So are the prelude's own non-linear builders, which the source names without writing a `datatype`: the constructors of `list`, `option` and `stream_con` (`list_cons`, `list_nil`, `Some`, `None`, `stream_cons`, `stream_nil`) and the macros `nil`, `cons` and `::` (unless the file declares its own `nil` or `cons`, as the list package does over `list_vt`); every prelude function whose result is a non-linear list, option or stream built from something that is not one (enumerated from the prelude's SATS files: `list_append`, `list_vt2t`, `option_of_option_vt`, `stream_make_nil`, ...); `$delay`; and libats/ML, ATS's garbage-collected library (its `list0`, `Some0`, ..., and any staload or include of it). A qualified name (`$R.some`) is another package's and stays; the messages name `list_vt`, `option_vt` or result's `option`, and `stream_vt` (`tests/prelude-builders`). The Rust bats let them all through (`tests/linear-heap`).

The words of the prelude (and libats/ML) that build a non-linear list, option or stream are kept in a table for each first letter, with the lead its words share (`list_builds`, `option_builds` and `stream_builds` in `src/helpers.bats`), and an identifier is looked for only in the table of its first letter and only when it begins with the lead (bats#368): it was looked for in the three whole lists, word by word, which was 54 G of the 80 G instructions that lexing quire's 158 files took, and a `bats fixtures` run lexed them for each fixture. The words are the same ones.
