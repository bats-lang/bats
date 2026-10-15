(* _bats_inputs -- the digest of what this build is made from, written by bats
   (bats-lang/bats#267); never edited: it is the same for every input *)

(* the sha256 of bats.toml, bats.lock and every src/**.bats, 64 hex digits *)
fun bats_inputs_sha256 (): string 64
