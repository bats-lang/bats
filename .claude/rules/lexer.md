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

What allocates must be linear outside `$UNSAFE`, since wasm has no garbage collector and a non-linear boxed value is never freed. The Rust bats let them all through (`tests/linear-heap`).

an identifier is looked for only in the table of its first letter (bats#368): it was looked for in the three whole lists, word by word, which was 54 G of the 80 G instructions that lexing quire's 158 files took.

`lit_at` makes no array for the literal: the lexer calls it for every keyword test, so a cost per call is a cost per source byte.
