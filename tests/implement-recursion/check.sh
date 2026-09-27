#!/bin/sh
# An implement's body is not checked for termination (a metric cannot be
# given to a .sats declaration), so bats check and bats build reject an
# implement on a call cycle: one that calls itself, through other
# implements, through a local fn, or in a dependency. Recursion in a
# fun with a metric, a call through a qualified name, and a name in a
# string or a comment are not calls.
#
# usage: tests/implement-recursion/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
p=$TMP/p
mkdir -p "$p/src/bin" "$p/bats_modules/dep/src"
printf '[package]\nname = "ir"\nkind = "bin"\n' > "$p/bats.toml"
printf '[package]\nname = "dep"\nkind = "lib"\n' > "$p/bats_modules/dep/bats.toml"
cat > "$p/src/self.bats" <<'X'
#pub fn down (n: int): int

implement down (n) = if n > 0 then down(n - 1) else 0
X
cat > "$p/src/ping.bats" <<'X'
#pub fn ping (n: int): int

implement ping (n) = if n > 0 then pong(n - 1) else 0
X
cat > "$p/src/pong.bats" <<'X'
staload "./ping.sats"

#pub fn pong (n: int): int

implement pong (n) = ping(n)
X
cat > "$p/src/helper.bats" <<'X'
#pub fn outer (): int

fn helper (): int = outer()

implement outer () = helper()
X
cat > "$p/src/fine.bats" <<'X'
#pub fn total (): int

fun count {n:nat} .<n>. (n: int n): int =
  if n = 0 then 0 else 1 + count(n - 1)

(* total, as a comment would name it *)
implement total () = let
  val s = "total"
in count(3) end
X
cat > "$p/bats_modules/dep/src/lib.bats" <<'X'
#pub fn spin (): int

implement spin () = spin()
X
printf 'implement main0 () = ()\n' > "$p/src/bin/m.bats"
for cmd in check build; do
  rc=0
  (cd "$p" && NO_COLOR=1 "$BATS" $cmd) > "$TMP/out" 2> "$TMP/err" || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: $cmd: rc $rc"; cat "$TMP/err"; exit 1; }
  cmp -s "$TMP/err" "$HERE/expected.txt" || { echo "FAIL: $cmd"; diff "$HERE/expected.txt" "$TMP/err"; exit 1; }
  [ ! -d "$p/build" ] || { echo "FAIL: $cmd: ran patsopt"; exit 1; }
done
echo "implement-recursion: ok"
