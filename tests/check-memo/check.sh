#!/bin/sh
# The check memo (bats-lang/bats#267, item 3): in check mode a module whose
# closure (every file patsopt read for it: its .dats and every file its
# staloads reach, to the end) is unchanged is not checked again, and a
# module whose closure changed is, with nothing else. This plays the cases
# a time, or a coarser key, gets wrong, on a bin with a plain dependency
# and several modules:
#   base <- mid <- the bin (tool), other <- the bin, lone (staloaded by none)
#   * the very next check, and one with every file of build/ and of the
#     sources given a time in the future or long ago, runs no patsopt, and
#     says so (-v prints "(unchanged)");
#   * a body-only change, even one that keeps the size and puts the time
#     back, is checked again, alone;
#   * a changed .sats re-checks the modules whose closure holds it (the
#     ones that staload it, and the ones that staload those), and not the
#     others (a coarser key re-checked all of them);
#   * a declaration added before the #pub ones only moves the .sats: the
#     module is checked again and the modules that staload it are not;
#   * a module added or removed (a .sats of build/ that patsopt might have
#     read instead of another) checks everything again; --cold and BATS_COLD check everything again;
#   * a module that fails is never recorded: it fails again, and once fixed
#     it passes and is recorded;
#   * a run stopped while patsopt ran leaves no key behind;
#   * a key that is missing, garbled, cut short, of the old format, with a
#     hash changed, or beside a C that is gone, is not trusted;
#   * the digests kept in memory for a pass (bats#311): three .sats whose
#     paths share a slot of the table are each told apart (a change to one is
#     that one's), a body-only change of a dependency's file is noticed, and
#     the files an older bats kept in build/.bats_dg are neither read nor kept;
#   * a native bin and a wasm bin using a target-dependent .sats, cold and
#     when the wasm bin is added to a native-only project: the second and
#     third checks run no patsopt (each pass names its own build's .sats);
#   * four copies checked side by side, five rounds, never read a torn key.
# usage: tests/check-memo/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../text.sh"
unset BATS_CACHE_DIR BATS_COLD
mkdir -p "$TMP/app/src/bin" "$TMP/plain/src"
printf '[package]\nname = "app"\nkind = "bin"\n\n[dependencies]\n"plain" = { path = "../plain" }\n' > "$TMP/app/bats.toml"
printf '[package]\nname = "plain"\nkind = "lib"\n' > "$TMP/plain/bats.toml"
printf '#pub fun h (): int\n\nimplement h () = 9\n' > "$TMP/plain/src/lib.bats"
printf '#pub fun k (): int\n\nimplement k () = 10\n' > "$TMP/plain/src/more.bats"
A=$TMP/app/src
base() { # <body> [<more #pub>]
  printf '#include "share/atspre_staload.hats"\n\n#pub fun base (): int\n%s\nimplement base () = %s\n' "${2:-}" "$1" > "$A/base.bats"
}
mid() { # <body> [<private lines before the #pub ones>] [<more #pub>]
  printf '#include "share/atspre_staload.hats"\nstaload "base.sats"\n\n%s\n#pub fun mid (): int\n%s\nimplement mid () = %s + base ()\n' "${2:-}" "${3:-}" "$1" > "$A/mid.bats"
}
base 1
mid 2
printf '#include "share/atspre_staload.hats"\n\n#pub fun other (): int\n\nimplement other () = 3\n' > "$A/other.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = 4\n' > "$A/lone.bats"
printf '#target native\n#include "share/atspre_staload.hats"\n#use plain as PL\nstaload "mid.sats"\nstaload "other.sats"\n\nimplement main0 () = println! ("got ", mid () + other () + $PL.h ())\n' > "$A/bin/tool.bats"
# A patsopt that kills the bats that started it, while a flag file is there
# (an interrupted run); otherwise the real one. The same for every run, so
# the toolchain's digest is the same.
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
KILL_FLAG=$TMP/kill-flag
DEPGEN_LOG=$TMP/depgen-starts
: > "$DEPGEN_LOG"
printf '#!/bin/sh\nfor a in "$@"; do if [ "$a" = --depgen ]; then echo x >> "%s"; fi; done\nif [ -f "%s" ]; then kill -9 $PPID; exit 1; fi\nexec "%s" "$@"\n' "$DEPGEN_LOG" "$KILL_FLAG" "$REAL/bin/patsopt" > "$H/.bats/ats2/bin/patsopt"
chmod +x "$H/.bats/ats2/bin/patsopt"
mkdir -p "$H/.bats/ats2" && "$BATS" ats2 marker > "$H/.bats/ats2/.bats-ats2"
export HOME="$H"
cd "$TMP/app"
N=0
run() { # <log> <command...>: bats -v <command>
  l=$1; shift
  N=$((N + 1))
  "$BATS" -v "$@" > "$l" 2>&1 || { echo "FAIL: $*"; cat "$l"; exit 1; }
}
# patsopt runs on a module: the C it makes is named in the line (a module
# is checked once in each of check's two passes, native and wasm; the bin
# only in the native one)
ran() { grep -a -- '+ patsopt' "$1" | grep -ac "$2" || true; }
total() { grep -a -- '+ patsopt' "$1" | grep -avc '(cached)' || true; }
only() { # <log> <what> <module>...: patsopt ran on these and on nothing else
  l=$1; what=$2; shift 2
  for m in base mid other lone tool tgt user web caaaa carbq cbddb cuser; do
    want=0
    for x in "$@"; do [ "$x" = "$m" ] && want=1; done
    got=$(ran "$l" "/${m}_dats.c")
    if [ "$want" = 1 ] && [ "$got" = 0 ]; then echo "FAIL: $what: $m was not checked again"; cat "$l"; exit 1; fi
    if [ "$want" = 0 ] && [ "$got" != 0 ]; then echo "FAIL: $what: $m was checked again"; cat "$l"; exit 1; fi
  done
  for lib in plain/src/lib plain/src/more; do
    want=0
    for x in "$@"; do [ "$x" = "$lib" ] && want=1; done
    got=$(ran "$l" "/${lib}_dats.c")
    if [ "$want" = 1 ] && [ "$got" = 0 ]; then echo "FAIL: $what: $lib was not checked again"; cat "$l"; exit 1; fi
    if [ "$want" = 0 ] && [ "$got" != 0 ]; then echo "FAIL: $what: $lib was checked again"; cat "$l"; exit 1; fi
  done
}
quiet() { # <log> <what>
  [ "$(total "$1")" = 0 ] || { echo "FAIL: $2 ran patsopt"; cat "$1"; exit 1; }
  grep -aq '(unchanged)' "$1" || { echo "FAIL: $2 did not say a module was unchanged"; cat "$1"; exit 1; }
}
# --- a cold check, then the very next ones
run c0.log check
[ "$(total c0.log)" -ge 8 ] || { echo "FAIL: a cold check ran patsopt $(total c0.log) times"; cat c0.log; exit 1; }
# the files patsopt --depgen has told of are kept for the modules of a pass,
# so a file that many reach is read once: fewer starts than modules checked
d0=$(wc -l < "$DEPGEN_LOG")
[ "$d0" -ge 1 ] && [ "$d0" -lt "$(total c0.log)" ] || { echo "FAIL: a cold check started patsopt --depgen $d0 times for $(total c0.log) modules"; exit 1; }
echo "check-memo: a cold check: $(total c0.log) patsopt runs, $d0 depgen starts"
: > "$DEPGEN_LOG"
run c1.log check
[ ! -s "$DEPGEN_LOG" ] || { echo "FAIL: a no-change check started patsopt --depgen"; exit 1; }
quiet c1.log "the first no-change check"
run c2.log check
quiet c2.log "the second no-change check"
# --- times are not read
find build "$A" "$TMP/plain/src" -type f -exec touch -d '2040-01-01 00:00:00' {} +
run t1.log check
quiet t1.log "a check with every file in the future"
find build "$A" "$TMP/plain/src" -type f -exec touch -d '2001-01-01 00:00:00' {} +
run t2.log check
quiet t2.log "a check with every file long ago"
touch "$A/base.bats" "$TMP/plain/src/lib.bats"
run t3.log check
quiet t3.log "a check with sources touched"
# --- a body changed with its size kept and its time put back: alone
base 5
touch -d '2001-01-01 00:00:00' "$A/base.bats"
run b1.log check
only b1.log "a body-only change of base" base
echo "check-memo: a body-only change: $(total b1.log) patsopt runs, $(wc -l < "$DEPGEN_LOG") depgen starts"
run b2.log check
quiet b2.log "the check after it"
# --- a changed .sats: base, mid, whose .sats staloads it, and the bin, which
# staloads mid's: the closure goes to the end; nothing else
base 5 '#pub fun base2 (): int'
printf '\nimplement base2 () = 6\n' >> "$A/base.bats"
run s1.log check
only s1.log "a changed .sats of base" base mid tool
run s2.log check
quiet s2.log "the check after it"
# --- a changed .sats of mid: mid, and the bin that staloads it
mid 2 '' '#pub fun mid2 (): int'
printf '\nimplement mid2 () = 7\n' >> "$A/mid.bats"
run s3.log check
only s3.log "a changed .sats of mid" mid tool
run s4.log check
quiet s4.log "the check after it"
# --- a declaration added before the #pub ones only moves mid's .sats: mid
# is checked again, and the bin, which staloads it, is not
mid 2 'fn private (): int = 8
fn private2 (): int = private () + 1
' '#pub fun mid2 (): int'
printf '\nimplement mid2 () = 7\n' >> "$A/mid.bats"
run m1.log check
only m1.log "a declaration added before the #pub ones" mid
run m2.log check
quiet m2.log "the check after it"
# --- a changed .sats of the dependency: its modules that changed, and the bin
printf '#pub fun h (): int\n#pub fun h2 (): int\n\nimplement h () = 9\nimplement h2 () = 11\n' > "$TMP/plain/src/lib.bats"
run d1.log check
only d1.log "a changed .sats of a dependency" plain/src/lib tool
run d2.log check
quiet d2.log "the check after it"
# --- a .sats that is not the same in check's two passes (native, then
# wasm): the digest of a .sats kept for a pass is not kept for the other
cat > "$A/tgt.bats" <<'TGT'
#include "share/atspre_staload.hats"

#target native begin
#pub fun tv (): int

implement tv () = 1
end
#target wasm begin
#pub fun tv (): int
#pub fun tw (): int

implement tv () = 1
implement tw () = 2
end
TGT
printf '#include "share/atspre_staload.hats"\nstaload "tgt.sats"\n\n#pub fun user (): int\n\nimplement user () = tv ()\n' > "$A/user.bats"
# (a bin for the wasm pass, whose modules are checked only when it has one)
printf '#target wasm binary\n#include "share/atspre_staload.hats"\nstaload "user.sats"\n\nimplement main0 () = let val _ = user () in () end\n' > "$A/bin/web.bats"
run g1.log check
run g2.log check
quiet g2.log "the check after two modules were added"
cat > "$A/tgt.bats" <<'TGT'
#include "share/atspre_staload.hats"

#target native begin
#pub fun tv (): int

implement tv () = 1
end
#target wasm begin
#pub fun tv (): int
#pub fun tw (): int
#pub fun tw2 (): int

implement tv () = 1
implement tw () = 2
implement tw2 () = 3
end
TGT
run g3.log check
only g3.log "a declaration added to the wasm pass's .sats alone" tgt user web
run g4.log check
quiet g4.log "the check after it"
# --- a staload added to a module is in its closure: lone staloads other's
# .sats now, and when that changes lone is checked again (and so is the bin
# that staloads it)
printf '#include "share/atspre_staload.hats"\nstaload "other.sats"\n\n#pub fun lone (): int\n\nimplement lone () = 4 + other ()\n' > "$A/lone.bats"
run l1.log check
only l1.log "a staload added" lone
run l2.log check
quiet l2.log "the check after it"
printf '#include "share/atspre_staload.hats"\n\n#pub fun other (): int\n#pub fun other2 (): int\n\nimplement other () = 3\nimplement other2 () = 5\n' > "$A/other.bats"
run l3.log check
only l3.log "a changed .sats that a staload added reaches" other lone tool
run l4.log check
quiet l4.log "the check after it"
# --- the digests kept for a pass (bats#311). A .sats and every file of
# build/bats_modules is digested once for the modules that reach it, in a
# table of the process, found by the whole path. Three .sats whose paths
# fall in one slot of that table (caaaa, carbq and cbddb: the slot of
# build/src/<name>.sats is the same for the three) are staloaded by one
# module, and a change to the interface of one is the change of that one:
# a lookup that took another entry's digest for it would miss the change.
for name in caaaa carbq cbddb; do
  printf '#include "share/atspre_staload.hats"\n\n#pub fun %s (): int\n\nimplement %s () = 1\n' "$name" "$name" > "$A/$name.bats"
done
printf '#include "share/atspre_staload.hats"\nstaload "caaaa.sats"\nstaload "carbq.sats"\nstaload "cbddb.sats"\n\n#pub fun cuser (): int\n\nimplement cuser () = caaaa () + carbq () + cbddb ()\n' > "$A/cuser.bats"
run h1.log check
run h2.log check
quiet h2.log "the check after three modules whose .sats share a slot were added"
printf '#include "share/atspre_staload.hats"\n\n#pub fun carbq (): int\n#pub fun carbq2 (): int\n\nimplement carbq () = 1\nimplement carbq2 () = 2\n' > "$A/carbq.bats"
run h3.log check
only h3.log "a changed .sats among three that share a slot" carbq cuser
run h4.log check
quiet h4.log "the check after it"
printf '#include "share/atspre_staload.hats"\n\n#pub fun cbddb (): int\n#pub fun cbddb2 (): int\n\nimplement cbddb () = 1\nimplement cbddb2 () = 2\n' > "$A/cbddb.bats"
run h5.log check
only h5.log "a changed .sats of the last of three that share a slot" cbddb cuser
run h6.log check
quiet h6.log "the check after it"
# a body changed with its size kept, in a dependency (a file of
# build/bats_modules, whose digest is kept for the pass): the module that
# staloads it is checked again, and the check after it is quiet
printf '#pub fun h (): int\n#pub fun h2 (): int\n\nimplement h () = 8\nimplement h2 () = 11\n' > "$TMP/plain/src/lib.bats"
run h7.log check
only h7.log "a body-only change of a dependency" plain/src/lib tool
run h8.log check
quiet h8.log "the check after it"
# the digests an older bats kept in files (build/.bats_dg) are not read, and
# are removed: entries that say other digests for the files of a pass do
# not make a module be checked again, nor hide a change
mkdir -p build/.bats_dg
printf 'build/src/base.sats\n1\n0000000000000000000000000000000000000000000000000000000000000000\n' > 'build/.bats_dg/build%src%base.sats'
printf 'garbled' > 'build/.bats_dg/build%src%mid.sats'
run h9.log check
quiet h9.log "a check with digests of an older bats in build/.bats_dg"
[ ! -e build/.bats_dg ] || { echo "FAIL: a check left build/.bats_dg"; ls build/.bats_dg; exit 1; }
# --- a file patsopt might have read instead: a module added makes a .sats
# in build/ (a .sats of that name, earlier on -IATS, could be staloaded
# instead of another); everything is checked again, and again when it goes
printf '#include "share/atspre_staload.hats"\n\n#pub fun extra (): int\n\nimplement extra () = 12\n' > "$A/extra.bats"
run n1.log check
[ "$(total n1.log)" -ge 8 ] || { echo "FAIL: a module added checked $(total n1.log) modules again"; cat n1.log; exit 1; }
run n2.log check
quiet n2.log "the check after it"
rm -f "$A/extra.bats"
run n3.log check
[ "$(total n3.log)" -ge 8 ] || { echo "FAIL: a module removed checked $(total n3.log) modules again"; cat n3.log; exit 1; }
run n4.log check
quiet n4.log "the check after it"
# --- --cold and BATS_COLD ignore the memo, and write it again
run k1.log check --cold
[ "$(total k1.log)" -ge 8 ] || { echo "FAIL: --cold checked $(total k1.log) modules"; cat k1.log; exit 1; }
run k2.log check
quiet k2.log "the check after --cold"
BATS_COLD=1 run k3.log check
[ "$(total k3.log)" -ge 8 ] || { echo "FAIL: BATS_COLD=1 checked $(total k3.log) modules"; cat k3.log; exit 1; }
BATS_COLD=0 run k4.log check
quiet k4.log "a check with BATS_COLD=0"
# --- a module that fails is never recorded
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = "x"\n' > "$A/lone.bats"
if "$BATS" -v check > f1.log 2>&1; then echo "FAIL: a module with a type error passed"; cat f1.log; exit 1; fi
[ "$(ran f1.log /lone_dats.c)" -ge 1 ] || { echo "FAIL: the failing module was not checked"; cat f1.log; exit 1; }
if "$BATS" -v check > f2.log 2>&1; then echo "FAIL: a module that failed passed the next check"; cat f2.log; exit 1; fi
[ "$(ran f2.log /lone_dats.c)" -ge 1 ] || { echo "FAIL: the failing module was skipped"; cat f2.log; exit 1; }
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = 4\n' > "$A/lone.bats"
run f3.log check
[ "$(ran f3.log /lone_dats.c)" -ge 1 ] || { echo "FAIL: the fixed module was not checked"; cat f3.log; exit 1; }
run f4.log check
quiet f4.log "the check after the fix"
# fails again when broken again, and the same bytes as the failed run
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = "x"\n' > "$A/lone.bats"
if "$BATS" -v check > f5.log 2>&1; then echo "FAIL: the module passed when broken again"; cat f5.log; exit 1; fi
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = 4\n' > "$A/lone.bats"
run f6.log check
[ "$(ran f6.log /lone_dats.c)" -ge 1 ] || { echo "FAIL: the module that failed was not checked when fixed again"; cat f6.log; exit 1; }
run f7.log check
quiet f7.log "the check after it passed again"
# --- an interrupted run: patsopt kills bats after the key was dropped. The
# source then goes back to what the old C was made from, so a key left
# behind would match it, and the module is not checked again
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = 5\n' > "$A/lone.bats"
: > "$KILL_FLAG"
if "$BATS" -v check > i1.log 2>&1; then echo "FAIL: the killed run ended well"; cat i1.log; exit 1; fi
rm -f "$KILL_FLAG"
printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = 4\n' > "$A/lone.bats"
run i2.log check
[ "$(ran i2.log /lone_dats.c)" -ge 1 ] || { echo "FAIL: an interrupted run's key was kept"; cat i2.log; exit 1; }
run i3.log check
quiet i3.log "the check after an interrupted run"
# --- keys that must not be trusted: each makes its module checked again
# and nothing else (the garbled ones may be in either pass's cache; the
# module is checked once in each pass, so the key of its native C is made
# bad and only that pass checks it again)
k=build/src/other_dats.c.key
[ -f "$k" ] || k=$(ls build/.stash/*/src/other_dats.c.key | head -n 1)
[ -f "$k" ] || { echo "FAIL: no key of other"; find build -name '*.key' | head; exit 1; }
head -n 1 "$k" | grep -aqx 'bats-memo 1' || { echo "FAIL: the key does not begin with its format"; cat "$k"; exit 1; }
text_line 2 < "$k" | grep -aq '^names [0-9a-f]\{64\}$' || { echo "FAIL: the key has no names line"; cat "$k"; exit 1; }
grep -aqx -- '--' "$k" || { echo "FAIL: the key has no rule"; cat "$k"; exit 1; }
good=$TMP/key.good
cp "$k" "$good"
again() { # <what>: the next check checks other, and only other, again, in one pass
  run "x.log" check
  [ "$(ran x.log /other_dats.c)" -ge 1 ] || { echo "FAIL: $1: other was not checked again"; cat x.log; exit 1; }
  [ "$(total x.log)" = "$(ran x.log /other_dats.c)" ] || { echo "FAIL: $1: another module was checked again"; cat x.log; exit 1; }
  run "y.log" check
  quiet y.log "the check after $1"
  k=$(ls build/src/other_dats.c.key build/.stash/*/src/other_dats.c.key 2>/dev/null | head -n 1)
  cp "$k" "$good"
}
printf 'garbled\n' > "$k"; again "a garbled key"
: > "$k"; again "an empty key"
rm -f "$k"; again "a missing key"
head -c 100 "$good" > "$k"; again "a key cut short"
text_drop_last < "$good" > "$k"; again "a key short of its last line"
printf '%s\n%s\n' "$(sha256sum "$TMP/app/src/other.bats" | cut -d' ' -f1)" "$(sha256sum build/.sats_changed | cut -d' ' -f1)" > "$k"; again "a key of the old format"
text_set_line 1 'bats-memo 2' < "$good" > "$k"; again "a key of another format"
last=$(tail -n 2 "$good" | head -n 1)
text_replace "$last" 0000000000000000000000000000000000000000000000000000000000000000 < "$good" > "$k"; again "a key with a hash changed"
# a size changed
n=$(grep -an -- '^--$' "$good" | cut -d: -f1)
text_set_line $((n + 1)) 1 < "$good" > "$k"; again "a key with a size changed"
# a C that is gone, its key still there
c=${k%.key}
rm -f "$c"; again "a C that is gone"
# --- a native bin and a wasm bin that both use a module with a
# target-dependent .sats (bats#300). Each pass's names are the .sats of its
# own build/: the other target's are in its stash, which the names do not
# take. So the second and third checks run nothing, both cold and when the
# wasm bin is added to a native-only project (the first check there records
# the native bin's names before the wasm pass's .sats exist).
two_bins() { # <dir> <yes|no>: a native bin, and a wasm bin when yes
  mkdir -p "$1/src/bin"
  printf '[package]\nname = "tw"\nkind = "bin"\n' > "$1/bats.toml"
  printf '#include "share/atspre_staload.hats"\n\n#target native begin\n#pub fun tv (): int\n\nimplement tv () = 1\nend\n#target wasm begin\n#pub fun tv (): int\n#pub fun tw (): int\n\nimplement tv () = 1\nimplement tw () = 2\nend\n' > "$1/src/tgt.bats"
  printf '#include "share/atspre_staload.hats"\nstaload "tgt.sats"\n\n#pub fun user (): int\n\nimplement user () = tv ()\n' > "$1/src/user.bats"
  printf '#target native\n#include "share/atspre_staload.hats"\nstaload "user.sats"\n\nimplement main0 () = println! ("got ", user ())\n' > "$1/src/bin/nat.bats"
  if [ "$2" = yes ]; then
    printf '#target wasm binary\n#include "share/atspre_staload.hats"\nstaload "user.sats"\n\nimplement main0 () = let val _ = user () in () end\n' > "$1/src/bin/web.bats"
  fi
}
tw_check() { # <dir> <log>: bats -v check in dir, which must pass
  (cd "$1" && "$BATS" -v check > "$2" 2>&1) || { echo "FAIL: two bins: check in $1 failed"; cat "$2"; exit 1; }
}
TB=$TMP/two-bins
two_bins "$TB" yes
tw_check "$TB" "$TMP/tb1.log"
[ "$(total "$TMP/tb1.log")" -ge 8 ] || { echo "FAIL: a cold two-bin check ran patsopt $(total "$TMP/tb1.log") times"; cat "$TMP/tb1.log"; exit 1; }
tw_check "$TB" "$TMP/tb2.log"
quiet "$TMP/tb2.log" "the second check of two bins"
tw_check "$TB" "$TMP/tb3.log"
quiet "$TMP/tb3.log" "the third check of two bins"
TA=$TMP/native-then-wasm
two_bins "$TA" no
tw_check "$TA" "$TMP/ta1.log"
tw_check "$TA" "$TMP/ta2.log"
quiet "$TMP/ta2.log" "the second check of a native-only project"
two_bins "$TA" yes
tw_check "$TA" "$TMP/ta3.log"
[ "$(ran "$TMP/ta3.log" /web_dats.c)" -ge 1 ] || { echo "FAIL: the wasm bin added was not checked"; cat "$TMP/ta3.log"; exit 1; }
tw_check "$TA" "$TMP/ta4.log"
quiet "$TMP/ta4.log" "the check after a wasm bin is added"
tw_check "$TA" "$TMP/ta5.log"
quiet "$TMP/ta5.log" "the next check after a wasm bin is added"
echo "check-memo: two bins, native and wasm: ok"
# --- four copies side by side, five rounds: never a torn key (each copy
# sits beside its own copy of the plain dependency)
for i in 1 2 3 4; do
  rm -rf "$TMP/c$i"; mkdir -p "$TMP/c$i/app"
  cp -R "$TMP/app/bats.toml" "$TMP/app/src" "$TMP/c$i/app/"
  cp -R "$TMP/plain" "$TMP/c$i/plain"
done
round() { # <round>
  pids=""
  for i in 1 2 3 4; do
    ( cd "$TMP/c$i/app" && printf '#include "share/atspre_staload.hats"\n\n#pub fun lone (): int\n\nimplement lone () = %s\n' "$1" > src/lone.bats \
        && "$BATS" -v check > "$TMP/r$i.log" 2>&1 ) &
    pids="$pids $!"
  done
  for p in $pids; do wait "$p" || { echo "FAIL: a concurrent check failed in round $1"; cat "$TMP"/r?.log; exit 1; }; done
  for i in 1 2 3 4; do
    for f in $(cd "$TMP/c$i/app" && find build -name '*_dats.c.key'); do
      kf="$TMP/c$i/app/$f"
      head -n 1 "$kf" | grep -aqx 'bats-memo 1' || { echo "FAIL: a torn key $kf"; cat "$kf"; exit 1; }
      [ "$(tail -n 1 "$kf" | wc -c)" -ge 65 ] || { echo "FAIL: a key cut short $kf"; cat "$kf"; exit 1; }
    done
    [ -z "$(cd "$TMP/c$i/app" && find build -name '*.key.new')" ] || { echo "FAIL: a temporary key was left"; exit 1; }
  done
}
for r in 1 2 3 4 5; do round "$r"; done
for i in 1 2 3 4; do
  ( cd "$TMP/c$i/app" && "$BATS" -v check > "$TMP/z$i.log" 2>&1 ) || { echo "FAIL: the last check of copy $i"; cat "$TMP/z$i.log"; exit 1; }
  quiet "$TMP/z$i.log" "the last check of copy $i"
done
echo "check-memo: ok"
