#!/bin/sh
# bats run shares its stdout and environment with the program and exits
# with its status, as the Rust bats's Command::status did. The program
# used to run with stdout on /dev/null and only PATH in its environment.
# usage: tests/run-stdio/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "runio"\nkind = "bin"\n\n[dependencies]\n"array" = ""\n"env" = ""\n"result" = ""\n"str" = ""\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/runio.bats" <<'PROG'
#include "share/atspre_staload.hats"
#use array as A
#use env as E
#use result as R
#use str as S

(* Prints a line; exits 7 when BATS_RUN_PROBE is in the environment, 8
   when it is not. *)
implement main0 () = let
  val () = println! ("hello from the program")
  var n = @[char][15]('B', 'A', 'T', 'S', '_', 'R', 'U', 'N', '_', 'P', 'R', 'O', 'B', 'E', '\000')
  val name = $S.from_char_array(n, 15)
  val buf = $A.alloc<byte>(16)
  val found = (case+ $E.get_cstr(name, buf, 16) of | ~$R.some(_) => true | ~$R.none() => false): bool
  val () = $A.free<byte>(buf)
  val () = $A.free<byte>(name)
in exit_void (if found then 7 else 8) end
PROG
cd "$TMP/p"
"$BATS" lock --repository "$REPO" > lock.log 2>&1 || { echo "FAIL: lock"; cat lock.log; exit 1; }
rc=0; BATS_RUN_PROBE=1 "$BATS" run --repository "$REPO" > run.log 2>&1 || rc=$?
grep -q "built ./dist/debug/runio (debug)" run.log || { echo "FAIL: build"; cat run.log; exit 1; }
grep -q "hello from the program" run.log || { echo "FAIL: the program's stdout did not reach ours"; cat run.log; exit 1; }
[ "$rc" = 7 ] || { echo "FAIL: exited $rc, want 7 (8: no environment)"; cat run.log; exit 1; }
echo "run-stdio: ok"
