#!/bin/sh
# The names listing and the depgen graph of build/ (bats-lang/bats#336): the
# check memo's `names` line is the sha256 of build/.bats_names, which the
# first module of a process lists (and which clears build/.bats_graph and
# build/.bats_dg with it), and the graph of --depgen's answers is only as good
# as the files it was made from. So a change to a .sats or a .hats must be
# seen by the next check, and a dropped clear must show. This plays, on a bin
# with modules base <- mid <- the bin, other (staloaded by mid from a later
# step) and extra (added, then removed), each step of the issue:
#   * a .sats added (a module added): the next check checks every module
#     (the names changed), and the one after it is quiet;
#   * a .sats that a module now staloads (mid staloads other), then a change
#     to that .sats: the check after the change checks other, mid and the bin,
#     and not base or extra. The graph kept by an earlier check would hold
#     mid's closure without other.sats, so mid would not be checked again;
#   * a .sats removed (extra's): the next check checks every module, the
#     removed .sats is gone from build/, and the one after it is quiet;
#   * a .hats added to build/ that shadows the name a module includes (the
#     -IATS build directory comes first): the next check checks every module,
#     and removed again, the next check does too. bats writes no .hats of its
#     own, so the test writes one into each mark's build/ (build/ and every
#     build/.stash/<mark>, which a mark's build/ is swapped in from).
# usage: tests/names-graph/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_COLD
P=$TMP/app
mkdir -p "$P/src/bin"
printf '[package]\nname = "app"\nkind = "bin"\n' > "$P/bats.toml"
ALL="base mid other extra app"
base() {
  printf '#include "share/atspre_staload.hats"\n\n#pub fun base (): int\n\nimplement base () = 1\n' > "$P/src/base.bats"
}
mid() { # [with-other]: mid staloads other.sats when given
  if [ "${1:-}" = with-other ]; then
    printf '#include "share/atspre_staload.hats"\nstaload "base.sats"\nstaload "other.sats"\n\n#pub fun mid (): int\n\nimplement mid () = 2 + base () + other ()\n' > "$P/src/mid.bats"
  else
    printf '#include "share/atspre_staload.hats"\nstaload "base.sats"\n\n#pub fun mid (): int\n\nimplement mid () = 2 + base ()\n' > "$P/src/mid.bats"
  fi
}
other() { # [more]: a second #pub function changes other.sats
  if [ "${1:-}" = more ]; then
    printf '#include "share/atspre_staload.hats"\n\n#pub fun other (): int\n#pub fun other2 (): int\n\nimplement other () = 3\nimplement other2 () = 5\n' > "$P/src/other.bats"
  else
    printf '#include "share/atspre_staload.hats"\n\n#pub fun other (): int\n\nimplement other () = 3\n' > "$P/src/other.bats"
  fi
}
extra() {
  printf '#include "share/atspre_staload.hats"\n\n#pub fun extra (): int\n\nimplement extra () = 4\n' > "$P/src/extra.bats"
}
base
mid
other
printf '#target native\n#include "share/atspre_staload.hats"\nstaload "mid.sats"\n\nimplement main0 () = println! ("got ", mid ())\n' > "$P/src/bin/app.bats"
cd "$P"
N=0
run() { # <log> [bats arguments]: bats -v check, which must pass
  l=$1; shift
  N=$((N + 1))
  "$BATS" -v check > "$l" 2>&1 || { echo "FAIL: bats check failed at $l"; cat "$l"; exit 1; }
}
# patsopt ran on a module: the C it made is named in the line
ran() { grep -a -- '+ patsopt' "$1" | grep -ac -- "$2" || true; }
total() { grep -a -- '+ patsopt' "$1" | grep -avc '(cached)' || true; }
only() { # <log> <what> <module>...: patsopt ran on these modules and on no other of ALL
  l=$1; what=$2; shift 2
  for m in $ALL; do
    want=0
    for x in "$@"; do [ "$x" = "$m" ] && want=1; done
    got=$(ran "$l" "/${m}_dats.c")
    if [ "$want" = 1 ] && [ "$got" = 0 ]; then echo "FAIL: $what: $m was not checked"; cat "$l"; exit 1; fi
    if [ "$want" = 0 ] && [ "$got" != 0 ]; then echo "FAIL: $what: $m was checked"; cat "$l"; exit 1; fi
  done
  echo "names-graph: $what: $* checked, the others not"
}
quiet() { # <log> <what>
  [ "$(total "$1")" = 0 ] || { echo "FAIL: $2 ran patsopt"; cat "$1"; exit 1; }
  grep -aq '(unchanged)' "$1" || { echo "FAIL: $2 did not say a module was unchanged"; cat "$1"; exit 1; }
  echo "names-graph: $2: quiet"
}
# --- a cold check, and the very next one
run c0.log check
run c1.log check
quiet c1.log "the check after a cold check"
# --- a .sats added: a module added
extra
run a1.log check
only a1.log "a .sats added is seen by the next check" $ALL
run a2.log check
quiet a2.log "the check after a .sats was added"
# --- a .sats a module now staloads, and then a change to that .sats
mid with-other
run m1.log check
only m1.log "mid staloads other.sats" mid app
run m2.log check
quiet m2.log "the check after mid staloads other.sats"
other more
run m3.log check
only m3.log "a change to other.sats reaches mid, which staloads it" other mid app
run m4.log check
quiet m4.log "the check after the change to other.sats"
# --- a .sats removed: the module is taken out of src/
rm -f "$P/src/extra.bats"
run r1.log check
only r1.log "a .sats removed is seen by the next check" base mid other app
[ -z "$(find build -name 'extra*')" ] || { echo "FAIL: the removed .sats is still in build/"; find build -name 'extra*'; exit 1; }
run r2.log check
quiet r2.log "the check after a .sats was removed"
# --- a .hats added to build/ that shadows a name, in every mark's build/
addhats() {
  for d in build build/.stash/*; do
    [ -d "$d" ] && printf '#pub fun names_graph_shadow (): int\n' > "$d/names_graph_shadow.hats"
  done
  return 0
}
rmhats() {
  for d in build build/.stash/*; do
    [ -d "$d" ] && rm -f "$d/names_graph_shadow.hats"
  done
  return 0
}
addhats
run h1.log check
only h1.log "a .hats added is seen by the next check" base mid other app
run h2.log check
quiet h2.log "the check after a .hats was added"
rmhats
run h3.log check
only h3.log "a .hats removed is seen by the next check" base mid other app
run h4.log check
quiet h4.log "the check after a .hats was removed"
echo "names-graph: ok"
