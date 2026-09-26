(* Fixture for CI: a fun whose quantifier uses "==" before its
   termination metric. It is safe and must type-check. *)
#pub fn count_down {n:nat} (n: int n): int

implement count_down {n} (n) = let
  fun loop {i:nat; m:int | i <= n; m == n} .<i>. (i: int i, m: int m): int =
    if i <= 0 then m else loop(i - 1, m)
in loop(n, n) end
