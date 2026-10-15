#include "share/atspre_staload.hats"
staload F = "_bats_facts.sats"

implement main0 () = println! ($F.bats_commit_sha ())
