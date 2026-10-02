#include "share/atspre_staload.hats"
#pub fn first (): int

implement first () = 0

(* An ML comment is not a doc comment *)
/// Adds two ints.
/// Second line.
#pub fn add (x: int, y: int): int

implement add (x, y) = x + y

///No space after the slashes
  ///   Indented, with extra spaces kept
#pub fn neg (x: int): int

implement neg (x) = ~x

/// A blank line breaks the chain

#pub fn one (): int

implement one () = 1

/// Spans two lines
#pub fn two
  (): int

implement two () = 2

///
/// An empty doc line above
#pub typedef pair = @(int, int)

//// The rest of the file is a comment in ATS2
#pub fn hidden (): int
