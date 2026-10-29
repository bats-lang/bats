(* _bats_built -- the commit this build is made from, written by bats
   (bats-lang/bats#575); never edited: it is the same for every commit *)

(* the full SHA of the commit BATS_COMMIT named, 40 hex digits, or that it was unset *)
datavtype built_commit =
  | BuiltFrom of (string 40)
  | BuiltUnnamed of ()

fun bats_built_commit (): built_commit
