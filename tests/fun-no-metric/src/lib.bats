(* Fixture for CI: a recursive fun with "==" in its quantifier but no
   termination metric. It can diverge, so it must be rejected. *)
#pub fn count_down {n:nat} (n: int n): int

implement count_down {n} (n) = let
  fun loop {i:int; m:int | m == n} (i: int i, m: int m): int =
    if i <= 0 then m else loop(i - 1, m)
in loop(n, n) end
