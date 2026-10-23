#!/bin/sh
# An object is keyed on the headers its compile read (bats-lang/bats#394,
# #338, #395): cc is run with -MD -MF <object>.d, and the object's key holds
# the size and sha256 of each header the depfile lists, re-read at every
# check. A header changed in place (the same name, the same size, another
# byte) makes the object again, native and wasm alike; with nothing changed
# no cc runs; a depfile that is missing or garbled makes the object again.
# The header is found through C_INCLUDE_PATH, which clang reads as a system
# include directory, and which is in the stamp, so its value is the same
# before and after the change: only the header's bytes differ. A generated
# C and each header are read and hashed once for the native and the wasm
# object of a build (-v says `~ digested <path>` for each).
# usage: tests/build-headers/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR
HDR=$TMP/include
mkdir -p "$HDR" "$TMP/p/src/bin"
export C_INCLUDE_PATH=$HDR
printf '[package]\nname = "hd"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
printf '#target native\n\n$UNSAFE begin\n\n%%{\n#include <hdr_native.h>\nint hdr_native_value (void) { return HDR_NATIVE_VALUE; }\n%%}\n\nend\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/tool.bats"
printf '#target wasm binary\n\n$UNSAFE begin\n\n%%{\n#include <hdr_wasm.h>\nint hdr_wasm_value (void) { return HDR_WASM_VALUE; }\n%%}\n\nend\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/web.bats"
printf '#define HDR_NATIVE_VALUE 1\n' > "$HDR/hdr_native.h"
printf '#define HDR_WASM_VALUE 1\n' > "$HDR/hdr_wasm.h"
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
[ -f build/src/bin/tool_dats.o.d ] || { echo "FAIL: no depfile beside the native object"; ls build/src/bin; exit 1; }
grep -q 'hdr_native.h' build/src/bin/tool_dats.o.d || { echo "FAIL: the depfile does not list the header"; cat build/src/bin/tool_dats.o.d; exit 1; }
# the depfile garbled, then gone: the object is made again, once
printf 'garbled\n' > build/src/bin/tool_dats.o.d
build n4.log native
[ "$(runs 'bin/tool_dats.o ')" = 1 ] || { echo "FAIL: a garbled depfile did not make the object again"; cat "$CC_LOG"; exit 1; }
: > "$CC_LOG"
rm -f build/src/bin/tool_dats.o.d
build n5.log native
[ "$(runs 'bin/tool_dats.o ')" = 1 ] || { echo "FAIL: a missing depfile did not make the object again"; cat "$CC_LOG"; exit 1; }
: > "$CC_LOG"
build n6.log native
[ ! -s "$CC_LOG" ] || { echo "FAIL: the build after the depfile came back ran cc"; cat "$CC_LOG"; exit 1; }
# a header the compile read is read and hashed once, whoever names it
for h in $(grep -a '~ digested /' n6.log | sort | uniq -d); do echo "FAIL: $h was digested twice"; exit 1; done
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
[ -f build/src/bin/web_dats.wasm.o.d ] || { echo "FAIL: no depfile beside the wasm object"; ls build/src/bin; exit 1; }
grep -q 'hdr_wasm.h' build/src/bin/web_dats.wasm.o.d || { echo "FAIL: the wasm depfile does not list the header"; cat build/src/bin/web_dats.wasm.o.d; exit 1; }
# a wasm object is kept across the profiles, with its header
PATH="$TMP/shim:$PATH" "$BATS" -v build --only release --only wasm > w4.log 2>&1 || { echo "FAIL: release wasm build"; cat w4.log; exit 1; }
[ ! -s "$CC_LOG" ] || { echo "FAIL: a release wasm build made a wasm object again"; cat "$CC_LOG"; exit 1; }
# the shared digest: in a build of the wasm bin the C of the bin is under a
# native key and a wasm key, and is digested once
n=$(grep -ac '~ digested build/_bats_entry_web_dats.c' w3.log || true)
[ "$n" = 1 ] || { echo "FAIL: the entry's C was digested $n times in one build, not once"; cat w3.log; exit 1; }
echo "build-headers: ok"
