(* _bats_facts -- the commit this build is made from, written by bats
   (bats-lang/bats#250); never edited: it is the same for every commit *)

(* the committer time, in seconds since 1970 *)
fun bats_commit_time (): int

(* the committer time in UTC, YEAR.MONTH.DAY.SECONDS, as bats versions a package *)
fun bats_commit_version (): [n:pos | n < 32] string n

(* the first 7 hex digits of the commit's SHA *)
fun bats_commit_short (): string 7

(* the commit's SHA, 40 hex digits *)
fun bats_commit_sha (): string 40
