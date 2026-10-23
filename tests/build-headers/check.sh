#!/bin/sh
# An object is keyed on the text its compile reads (bats-lang/bats#394, #338,
# #395, #477): cc -E, with the object's own flags, gives the preprocessed text
# of its C, and the key holds the size and sha256 of that text, made again at
# every check. A header changed in place (the same name, the same size,
# another byte) makes the object again, native and wasm alike; so does a
# header that did not exist at the last compile and now shadows one later on
# the search path (an angle include found through C_INCLUDE_PATH, and a
# quoted one that a new file beside the including file now takes); with
# nothing changed no cc runs and no preprocessed text is left behind. The
# search path is in the stamp, so its value is the same before and after:
# only what the preprocessor now finds differs. A generated C is read and
# hashed once for the native and the wasm object of a build (-v says
# `~ digested <path>`).
# usage: tests/build-headers/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR
HDR=$TMP/include
EARLIER=$TMP/earlier
mkdir -p "$HDR" "$EARLIER" "$TMP/p/src/bin"
export C_INCLUDE_PATH=$EARLIER:$HDR
printf '[package]\nname = "hd"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
printf '#target native\n\n$UNSAFE begin\n\n%%{\n#include <hdr_native.h>\n#include "hdr_native_q.h"\nint hdr_native_value (void) { return HDR_NATIVE_VALUE + HDR_NATIVE_Q_VALUE; }\n%%}\n\nend\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/tool.bats"
printf '#target wasm binary\n\n$UNSAFE begin\n\n%%{\n#include <hdr_wasm.h>\n#include "hdr_wasm_q.h"\nint hdr_wasm_value (void) { return HDR_WASM_VALUE + HDR_WASM_Q_VALUE; }\n%%}\n\nend\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/web.bats"
printf '#define HDR_NATIVE_VALUE 1\n' > "$HDR/hdr_native.h"
printf '#define HDR_WASM_VALUE 1\n' > "$HDR/hdr_wasm.h"
printf '#define HDR_NATIVE_Q_VALUE 1\n' > "$HDR/hdr_native_q.h"
printf '#define HDR_WASM_Q_VALUE 1\n' > "$HDR/hdr_wasm_q.h"
# a stand-in clang notes each compile of a keyed object (the runtimes are made at every build and are not counted)
CC_LOG=$TMP/cc-runs
mkdir -p "$TMP/shim"
REAL_CLANG=$(command -v clang)
printf '#!/bin/sh\ncase "$*" in *-o\\ build/_bats_wasm_runtime*) ;; *-o\\ build/_bats_native_runtime*) ;; *.bats_link_probe*) ;; *-c\\ -o*) echo "$*" >> "%s";; esac\nexec "%s" "$@"\n' "$CC_LOG" "$REAL_CLANG" > "$TMP/shim/clang"
chmod +x "$TMP/shim/clang"
cd "$TMP/p"
build() { # <log> <native|wasm>: a debug build
  l=$1; t=$2
  PATH="$TMP/shim:$PATH" "$BATS" -v build --only debug --only "$t" > "$l" 2>&1 || { echo "FAIL: build $t"; cat "$l"; exit 1; }
}
runs() { grep -c -- "$1" "$CC_LOG" || true; }
: > "$CC_LOG"
# native
build n0.log native
[ "$(runs 'bin/tool_dats.o ')" = 1 ] || { echo "FAIL: a cold native build did not compile the bin's object once"; cat "$CC_LOG"; exit 1; }
cp build/src/bin/tool_dats.o "$TMP/tool.before.o"
: > "$CC_LOG"
build n1.log native
[ ! -s "$CC_LOG" ] || { echo "FAIL: a no-change native build ran cc"; cat "$CC_LOG"; exit 1; }
# the header changed in place: the same size, another byte, and no time read
printf '#define HDR_NATIVE_VALUE 2\n' > "$HDR/hdr_native.h"
touch -d '2001-01-01 00:00:00' "$HDR/hdr_native.h"
build n2.log native
[ "$(runs 'bin/tool_dats.o ')" = 1 ] || { echo "FAIL: a native header changed in place did not make the bin's object again"; cat "$CC_LOG"; cat n2.log; exit 1; }
if cmp -s "$TMP/tool.before.o" build/src/bin/tool_dats.o; then echo "FAIL: the native object holds the old header"; exit 1; fi
: > "$CC_LOG"
build n3.log native
[ ! -s "$CC_LOG" ] || { echo "FAIL: the build after the header changed ran cc"; cat "$CC_LOG"; exit 1; }
[ ! -e build/src/bin/tool_dats.o.i ] || { echo "FAIL: the preprocessed text is left beside the native object"; exit 1; }
# a header that did not exist at the last compile, earlier on the search path
# than the one the compile found (bats#477): the stamp's C_INCLUDE_PATH is the
# same, no listed header changed, and the object holds the old value
: > "$CC_LOG"
cp build/src/bin/tool_dats.o "$TMP/tool.beforeshadow.o"
printf '#define HDR_NATIVE_VALUE 5\n' > "$EARLIER/hdr_native.h"
build s0.log native
[ "$(runs 'bin/tool_dats.o ')" = 1 ] || { echo "FAIL: a native header that shadows a listed one earlier on the search path did not make the bin's object again"; cat "$CC_LOG"; cat s0.log; exit 1; }
if cmp -s "$TMP/tool.beforeshadow.o" build/src/bin/tool_dats.o; then echo "FAIL: the native object holds the shadowed header"; exit 1; fi
: > "$CC_LOG"
build s1.log native
[ ! -s "$CC_LOG" ] || { echo "FAIL: the build after the shadowing header ran cc"; cat "$CC_LOG"; exit 1; }
# the same for a quoted include, taken from the directory of the including file
cp build/src/bin/tool_dats.o "$TMP/tool.beforeq.o"
printf '#define HDR_NATIVE_Q_VALUE 7\n' > build/src/bin/hdr_native_q.h
build s2.log native
[ "$(runs 'bin/tool_dats.o ')" = 1 ] || { echo "FAIL: a native quoted header beside the including file did not make the bin's object again"; cat "$CC_LOG"; cat s2.log; exit 1; }
if cmp -s "$TMP/tool.beforeq.o" build/src/bin/tool_dats.o; then echo "FAIL: the native object holds the shadowed quoted header"; exit 1; fi
: > "$CC_LOG"
build s3.log native
[ ! -s "$CC_LOG" ] || { echo "FAIL: the build after the shadowing quoted header ran cc"; cat "$CC_LOG"; exit 1; }
# wasm
: > "$CC_LOG"
build w0.log wasm
[ "$(runs 'bin/web_dats.wasm.o ')" = 1 ] || { echo "FAIL: a cold wasm build did not compile the bin's object once"; cat "$CC_LOG"; exit 1; }
cp build/src/bin/web_dats.wasm.o "$TMP/web.before.o"
: > "$CC_LOG"
build w1.log wasm
[ ! -s "$CC_LOG" ] || { echo "FAIL: a no-change wasm build ran cc"; cat "$CC_LOG"; exit 1; }
printf '#define HDR_WASM_VALUE 2\n' > "$HDR/hdr_wasm.h"
touch -d '2001-01-01 00:00:00' "$HDR/hdr_wasm.h"
build w2.log wasm
[ "$(runs 'bin/web_dats.wasm.o ')" = 1 ] || { echo "FAIL: a wasm header changed in place did not make the bin's object again"; cat "$CC_LOG"; cat w2.log; exit 1; }
if cmp -s "$TMP/web.before.o" build/src/bin/web_dats.wasm.o; then echo "FAIL: the wasm object holds the old header"; exit 1; fi
: > "$CC_LOG"
build w3.log wasm
[ ! -s "$CC_LOG" ] || { echo "FAIL: the wasm build after the header changed ran cc"; cat "$CC_LOG"; exit 1; }
[ ! -e build/src/bin/web_dats.wasm.o.i ] || { echo "FAIL: the preprocessed text is left beside the wasm object"; exit 1; }
# a wasm object is kept across the profiles, with its header
PATH="$TMP/shim:$PATH" "$BATS" -v build --only release --only wasm > w4.log 2>&1 || { echo "FAIL: release wasm build"; cat w4.log; exit 1; }
[ ! -s "$CC_LOG" ] || { echo "FAIL: a release wasm build made a wasm object again"; cat "$CC_LOG"; exit 1; }
# the shared digest: in a build of the wasm bin the C of the bin is under a
# native key and a wasm key, and is digested once
n=$(grep -ac '~ digested build/_bats_entry_web_dats.c' w3.log || true)
[ "$n" = 1 ] || { echo "FAIL: the entry's C was digested $n times in one build, not once"; cat w3.log; exit 1; }
# the same for wasm
cp build/src/bin/web_dats.wasm.o "$TMP/web.beforeshadow.o"
printf '#define HDR_WASM_VALUE 5\n' > "$EARLIER/hdr_wasm.h"
build s4.log wasm
[ "$(runs 'bin/web_dats.wasm.o ')" = 1 ] || { echo "FAIL: a wasm header that shadows a listed one earlier on the search path did not make the bin's object again"; cat "$CC_LOG"; cat s4.log; exit 1; }
if cmp -s "$TMP/web.beforeshadow.o" build/src/bin/web_dats.wasm.o; then echo "FAIL: the wasm object holds the shadowed header"; exit 1; fi
: > "$CC_LOG"
build s5.log wasm
[ ! -s "$CC_LOG" ] || { echo "FAIL: the wasm build after the shadowing header ran cc"; cat "$CC_LOG"; exit 1; }
cp build/src/bin/web_dats.wasm.o "$TMP/web.beforeq.o"
printf '#define HDR_WASM_Q_VALUE 7\n' > build/src/bin/hdr_wasm_q.h
build s6.log wasm
[ "$(runs 'bin/web_dats.wasm.o ')" = 1 ] || { echo "FAIL: a wasm quoted header beside the including file did not make the bin's object again"; cat "$CC_LOG"; cat s6.log; exit 1; }
if cmp -s "$TMP/web.beforeq.o" build/src/bin/web_dats.wasm.o; then echo "FAIL: the wasm object holds the shadowed quoted header"; exit 1; fi
: > "$CC_LOG"
build s7.log wasm
[ ! -s "$CC_LOG" ] || { echo "FAIL: the wasm build after the shadowing quoted header ran cc"; cat "$CC_LOG"; exit 1; }
echo "build-headers: ok"
