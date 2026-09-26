(* Fixture for CI: deliberately ill-typed, so `bats check` must fail. *)
#pub fn bad (): int

implement bad () = "not an int"
