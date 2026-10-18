#!/bin/sh
# Freshness is by content, never by time (bats-lang/bats#254): a module's
# C is made again only when the key beside it (<C>.key: the sizes and
# sha256 of the files patsopt read for it, and in a build of
# build/.sats_changed) differs from the one its inputs give, and an object
# when the key of its C does. This plays the cases a time gets wrong, with a native and a wasm bin, a dependency under
# a namespace (bats_modules/<namespace>/<name>, as bridge and dom) and a
# plain one, each of two modules:
#  * the very next no-change check and build, after a cold one, run no
#    patsopt and no cc outside the entry's (no settling runs);
#  * every file of build/ given a time in the future, and then one long
#    ago, changes nothing (touch -d);
#  * a source whose bytes change with its size kept, and its time put
#    back, is made again, and only its module (its .sats is the same);
#  * a changed .sats makes every module made again;
#  * a template body changed in a dependency's .dats (its .sats the same)
#    makes the C and object of a bin that instantiates it again in a build
#    (bats-lang/bats#323), and a dependency file it does not staload does not;
#  * a key that is missing or garbled makes its output made again;
#  * a build of the other profile (release over debug, and the reverse)
#    makes a native object again, since the profile is in its key
#    (bats-lang/bats#320), and its debug info is the profile's;
#  * a wasm object is kept across release, debug and release builds (its
#    cc flags are fixed, -O2 and no -g, so its key names no profile).
# usage: tests/build-content-keys/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR
mkdir -p "$TMP/app/src/bin" "$TMP/mine/src" "$TMP/plain/src"
printf '[package]\nname = "app"\nkind = "bin"\n\n[dependencies]\n"ns.example/mine" = { path = "../mine" }\n"plain" = { path = "../plain" }\n' > "$TMP/app/bats.toml"
printf '[package]\nname = "mine"\nkind = "lib"\n' > "$TMP/mine/bats.toml"
printf '[package]\nname = "plain"\nkind = "lib"\n' > "$TMP/plain/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 7\n' > "$TMP/mine/src/lib.bats"
printf '#pub fun g (): int\n\nimplement g () = 8\n' > "$TMP/mine/src/util.bats"
printf '#pub fun h (): int\n\nimplement h () = 9\n' > "$TMP/plain/src/lib.bats"
printf '#pub fun k (): int\n\nimplement k () = 10\n' > "$TMP/plain/src/more.bats"
printf '#target native\n#include "share/atspre_staload.hats"\n#use ns.example/mine as M\n#use plain as PL\n\nimplement main0 () = println! ("got ", $M.f () + $PL.h ())\n' > "$TMP/app/src/bin/tool.bats"
printf '#target wasm binary\n#include "share/atspre_staload.hats"\n#use ns.example/mine as M\n#use plain as PL\n\nimplement main0 () = let val _ = $M.f () + $PL.h () in () end\n' > "$TMP/app/src/bin/web.bats"
# A patsopt that kills the bats that started it, while a flag file is there
# (an interrupted run); otherwise the real one. The same for every run, so
# the toolchain's digest is the same.
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
KILL_FLAG=$TMP/kill-flag
DEPGEN_FLAG=$TMP/depgen-flag
printf '#!/bin/sh\nif [ -f "%s" ]; then kill -9 $PPID; exit 1; fi\nif [ -f "%s" ]; then case "$*" in *--depgen*) exit 1;; esac; fi\nexec "%s" "$@"\n' "$KILL_FLAG" "$DEPGEN_FLAG" "$REAL/bin/patsopt" > "$H/.bats/ats2/bin/patsopt"
chmod +x "$H/.bats/ats2/bin/patsopt"
cd "$TMP/app"
N=0
run() { # <log> <command...>: bats -v <command>
  l=$1; shift
  N=$((N + 1))
  HOME="$H" "$BATS" -v "$@" > "$l" 2>&1 || { echo "FAIL: $*"; cat "$l"; exit 1; }
}
# runs of a tool (the entry's generated module too: its C is the same
# bytes, so it is not made again)
count() { grep -a -- "+ $2" "$1" | grep -avc '(cached)' || true; }
quiet() { # <log> <what>: no patsopt and no cc
  [ "$(count "$1" patsopt)" = 0 ] || { echo "FAIL: $2 ran patsopt"; cat "$1"; exit 1; }
  [ "$(count "$1" cc)" = 0 ] || { echo "FAIL: $2 ran cc"; cat "$1"; exit 1; }
}
ran_on() { grep -a -- '+ patsopt' "$1" | grep -ac "$2" || true; }
cold() { # <log> <what> <patsopt at least>
  [ "$(count "$1" patsopt)" -ge "$3" ] || { echo "FAIL: $2 ran patsopt $(count "$1" patsopt) times, expected $3 at least"; cat "$1"; exit 1; }
}
# A cold check, then the very next one and the one after: nothing is made
run c0.log check
cold c0.log "a cold check" 9
run c1.log check
quiet c1.log "the first no-change check"
run c2.log check
quiet c2.log "the second no-change check"
# Times are not read: all of build/ in the future, then long ago
find build -type f -exec touch -d '2040-01-01 00:00:00' {} +
run c3.log check
quiet c3.log "a check with every file of build/ in the future"
find build -type f -exec touch -d '2001-01-01 00:00:00' {} +
run c4.log check
quiet c4.log "a check with every file of build/ long ago"
# The same bytes under a new time: the dependency is copied again by every
# build, with new times, and nothing is made again
touch -d '2040-01-01 00:00:00' "$TMP/plain/src/lib.bats" "$TMP/mine/src/util.bats"
run c5.log check
quiet c5.log "a check with sources touched"
# A key that is garbled, or gone, makes its own output again
k=build/bats_modules/plain/src/lib_dats.c.key
[ -f "$k" ] || { echo "FAIL: no $k"; ls build/bats_modules/plain/src; exit 1; }
printf 'garbled\n' > "$k"
run c6.log check
[ "$(count c6.log patsopt)" = 1 ] || { echo "FAIL: a garbled key did not make its C again, once"; cat c6.log; exit 1; }
rm -f build/bats_modules/ns.example/mine/src/util_dats.o.key
run c7.log check
[ "$(count c7.log patsopt)" = 0 ] && [ "$(count c7.log cc)" = 1 ] || { echo "FAIL: a missing key did not make its object again, once"; cat c7.log; exit 1; }
run c8.log check
quiet c8.log "the check after those"
# A source changed with its size kept and its time put back is made again,
# alone (its .sats is the same)
cp "$TMP/plain/src/lib.bats" "$TMP/lib.keep"
printf '#pub fun h (): int\n\nimplement h () = 5\n' > "$TMP/plain/src/lib.bats"
touch -d '2001-01-01 00:00:00' "$TMP/plain/src/lib.bats"
run c9.log check
# (check makes two passes, the native one and the wasm one: the library's
# module once in each, and each bin once, whose closure holds the
# dependency's .dats it staloads; the others are not checked again)
[ "$(count c9.log patsopt)" = 4 ] || { echo "FAIL: a changed body ran patsopt $(count c9.log patsopt) times, not on the module and the two bins that staload it"; cat c9.log; exit 1; }
[ "$(grep -a -- '+ patsopt' c9.log | grep -avc 'plain/src/lib_dats.c\|src/bin/tool_dats.c\|src/bin/web_dats.c')" = 0 ] || { echo "FAIL: patsopt ran on another module than plain's lib and the bins"; cat c9.log; exit 1; }
run c10.log check
quiet c10.log "the check after a changed body"
# A changed .sats: the modules whose closure holds it are checked again
# (a dependency replaced by another version: only its .sats differs, and
# its files are older than everything), not the others (bats#267)
printf '#pub fun h (): int\n#pub fun h2 (): int\n\nimplement h () = 5\nimplement h2 () = 6\n' > "$TMP/plain/src/lib.bats"
touch -d '2001-01-01 00:00:00' "$TMP/plain/src/lib.bats"
run c11.log check
cold c11.log "a changed .sats" 4
grep -aq 'src/bin/tool_dats.c' c11.log || { echo "FAIL: the dependent bin's C was not made again"; cat c11.log; exit 1; }
[ "$(ran_on c11.log 'ns.example/mine')" = 0 ] || { echo "FAIL: a dependency that does not staload it was made again"; cat c11.log; exit 1; }
run c12.log check
quiet c12.log "the check after a changed .sats"
# An interrupted run: patsopt kills bats after the key was dropped. The
# source then goes back to what the old C was made from, so a key left
# behind would match it; the C is made again
cp "$TMP/plain/src/lib.bats" "$TMP/lib.settled"
printf '#pub fun h (): int\n#pub fun h2 (): int\n\nimplement h () = 4\nimplement h2 () = 6\n' > "$TMP/plain/src/lib.bats"
: > "$KILL_FLAG"
if HOME="$H" "$BATS" -v check > k1.log 2>&1; then echo "FAIL: the killed run ended well"; cat k1.log; exit 1; fi
rm -f "$KILL_FLAG"
cp "$TMP/lib.settled" "$TMP/plain/src/lib.bats"
run k2.log check
[ "$(count k2.log patsopt)" -ge 1 ] || { echo "FAIL: an interrupted run's C was kept"; cat k2.log; exit 1; }
grep -aq 'plain/src/lib_dats.c' k2.log || { echo "FAIL: not plain's lib"; cat k2.log; exit 1; }
run k3.log check
quiet k3.log "the check after an interrupted run"
# The stamp ahead of the .sats (bats killed after touching it, before it
# wrote the .sats; it touches the stamp first): a check does not read it
# any more, its modules' keys name the files they were checked from
# (bats#267); a build does, and makes every module again (below)
printf 'x' >> build/.sats_changed
run s1.log check
quiet s1.log "a check with the .sats stamp ahead"
# The same for a build (another mark: a cold one first)
run b0.log build --only debug --only native
cold b0.log "a cold build" 5
run b1.log build --only debug --only native
quiet b1.log "the first no-change build"
run b2.log build --only debug --only native
quiet b2.log "the second no-change build"
find build -type f -exec touch -d '2040-01-01 00:00:00' {} +
run b3.log build --only debug --only native
quiet b3.log "a build with every file of build/ in the future"
# the stamp ahead of the .sats: every C is made again by a build
printf 'x' >> build/.sats_changed
run b4.log build --only debug --only native
cold b4.log "a build with the stamp ahead of the .sats" 3
run b5.log build --only debug --only native
quiet b5.log "the build after it"
# A dependency's .dats is staloaded by its dependents, so a template body
# changed in it (its .sats the same) is instantiated again in their C
# (bats-lang/bats#323): the dependent's C and object were kept, with the
# old body. The bin calls a template of the plain dependency; a build with
# the template added, then one with its body changed.
tmpl() { # <body>: plain's lib with the template implemented as <body>
  printf '#pub fun h (): int\n#pub fun h2 (): int\n#pub fun {a:t@ype} tmpl_id (x: a): a\n\nimplement h () = 4\nimplement h2 () = 6\nimplement {a} tmpl_id (x) = %s\n' "$1" > "$TMP/plain/src/lib.bats"
}
tmpl 'let val _ = 1 in x end'
printf '#target native\n#include "share/atspre_staload.hats"\n#use ns.example/mine as M\n#use plain as PL\n\nimplement main0 () = println! ("got ", $M.f () + $PL.h () + $PL.tmpl_id<int> (3))\n' > "$TMP/app/src/bin/tool.bats"
run t0.log build --only debug --only native
cold t0.log "a build with a template added" 3
run t1.log build --only debug --only native
quiet t1.log "the build after it"
cp build/src/bin/tool_dats.c "$TMP/tool.before.c"
tool_dats=build/src/bin/tool_dats.c
tool_obj=build/src/bin/tool_dats.o
# the body only: the dependency's .sats is the same
tmpl 'x'
run t2.log build --only debug --only native
[ "$(ran_on t2.log 'src/bin/tool_dats.c')" = 1 ] || { echo "FAIL: a changed template body in a dependency did not make its dependent's C again"; cat t2.log; exit 1; }
[ "$(grep -ac -- "+ cc -c -o $tool_obj" t2.log || true)" = 1 ] || { echo "FAIL: a changed template body in a dependency did not make its dependent's object again"; cat t2.log; exit 1; }
if cmp -s "$TMP/tool.before.c" "$tool_dats"; then echo "FAIL: the dependent's C holds the old template body"; exit 1; fi
# what a cold build of the same sources makes
cp "$tool_dats" "$TMP/tool.after.c"
run t3.log build --only debug --only native
quiet t3.log "the build after a changed template body"
cmp -s "$TMP/tool.after.c" "$tool_dats" || { echo "FAIL: a no-change build changed the dependent's C"; exit 1; }
rm -rf build
run t4.log build --only debug --only native
cmp -s "$TMP/tool.after.c" "$tool_dats" || { echo "FAIL: the incremental C is not a cold build's"; exit 1; }
# a dependency's file the module does not staload does not make it again:
# mine's util is not in the bin's closure
cp "$tool_dats" "$TMP/tool.keep.c"
printf '#pub fun g (): int\n\nimplement g () = 18\n' > "$TMP/mine/src/util.bats"
run t5.log build --only debug --only native
[ "$(ran_on t5.log 'src/bin/tool_dats.c')" = 0 ] || { echo "FAIL: a dependency's module the bin does not staload made the bin's C again"; cat t5.log; exit 1; }
[ "$(ran_on t5.log 'mine/src/util_dats.c')" = 1 ] || { echo "FAIL: the changed dependency module was not made again"; cat t5.log; exit 1; }
run t6.log build --only debug --only native
quiet t6.log "the build after it"
# a module whose --depgen fails gets no key, which -v says, and is made
# again at the next build (when in doubt, recompute)
printf '#pub fun g (): int\n\nimplement g () = 19\n' > "$TMP/mine/src/util.bats"
: > "$DEPGEN_FLAG"
run t7.log build --only debug --only native
rm -f "$DEPGEN_FLAG"
grep -aq 'no key for build/bats_modules/ns.example/mine/src/util_dats.c' t7.log || { echo "FAIL: a module with no key was not said"; cat t7.log; exit 1; }
run t8.log build --only debug --only native
[ "$(ran_on t8.log 'mine/src/util_dats.c')" = 1 ] || { echo "FAIL: a module with no key was not made again"; cat t8.log; exit 1; }
run t9.log build --only debug --only native
quiet t9.log "the build after it"
# The profile is in a native object's key (bats-lang/bats#320): the two
# profiles share build/, and the release object was reused by a debug build
# (and the other way round). Each switch makes the bin's object again, the
# object has the debug info of its profile, and the same profile again
# reuses it. A garbled or missing key makes it again.
obj=build/src/bin/tool_dats.o
# (verbose prints the output path and the input path with a NUL between
# them, so the pattern ends at the path's own last byte)
ccs() { grep -ac -- "+ cc -c -o $obj" "$1" || true; }
has_debug_info() { grep -aq '\.debug_info' "$obj"; }
run r0.log build --only release --only native
[ "$(ccs r0.log)" = 1 ] || { echo "FAIL: a release build after a debug one did not make the bin's object again"; cat r0.log; exit 1; }
if has_debug_info; then echo "FAIL: the release object has debug info"; exit 1; fi
run r1.log build --only debug --only native
[ "$(ccs r1.log)" = 1 ] || { echo "FAIL: a debug build reused the release object"; cat r1.log; exit 1; }
has_debug_info || { echo "FAIL: the debug object has no debug info"; exit 1; }
run r2.log build --only debug --only native
[ "$(ccs r2.log)" = 0 ] || { echo "FAIL: a second debug build made the bin's object again"; cat r2.log; exit 1; }
run r3.log build --only release --only native
[ "$(ccs r3.log)" = 1 ] || { echo "FAIL: a release build reused the debug object"; cat r3.log; exit 1; }
if has_debug_info; then echo "FAIL: the release object has debug info after a release build"; exit 1; fi
run r4.log build --only release --only native
[ "$(ccs r4.log)" = 0 ] || { echo "FAIL: a second release build made the bin's object again"; cat r4.log; exit 1; }
printf 'garbled\n' > "$obj.key"
run r5.log build --only release --only native
[ "$(ccs r5.log)" = 1 ] || { echo "FAIL: a garbled object key did not make the object again, once"; cat r5.log; exit 1; }
rm -f "$obj.key"
run r6.log build --only release --only native
[ "$(ccs r6.log)" = 1 ] || { echo "FAIL: a missing object key did not make the object again, once"; cat r6.log; exit 1; }
run r7.log build --only release --only native
quiet r7.log "the build after those"
# A wasm object's key names no profile (its cc flags are fixed: -O2, no -g):
# it is made once, and a build of the other profile keeps it. The wasm cc is
# found on the PATH, so a stand-in notes each run that writes a keyed .wasm.o (the
# runtime's is made at every build, whatever changed, and is not counted).
CC_LOG=$TMP/wasm-cc-runs
mkdir -p "$TMP/shim"
REAL_CLANG=$(command -v clang)
printf '#!/bin/sh\ncase "$*" in *-o\ build/_bats_wasm_runtime*) ;; *.wasm.o*) echo "$*" >> "%s";; esac\nexec "%s" "$@"\n' "$CC_LOG" "$REAL_CLANG" > "$TMP/shim/clang"
chmod +x "$TMP/shim/clang"
: > "$CC_LOG"
PATH="$TMP/shim:$PATH" run w0.log build --only release --only wasm
[ "$(wc -l < "$CC_LOG")" -ge 1 ] || { echo "FAIL: a cold wasm build ran no wasm cc"; cat w0.log; exit 1; }
wasm_runs=$(wc -l < "$CC_LOG")
PATH="$TMP/shim:$PATH" run w1.log build --only debug --only wasm
PATH="$TMP/shim:$PATH" run w2.log build --only release --only wasm
[ "$(wc -l < "$CC_LOG")" = "$wasm_runs" ] || { echo "FAIL: a wasm object was made again by a build of the other profile"; cat "$CC_LOG"; cat w1.log w2.log; exit 1; }
echo "build-content-keys: ok"
