#!/bin/sh
# An object's key does not hold the directories of the toolchain (bats-lang/bats#477,
# stamp.md): the preprocessed text it digests is made with -P, which writes no line markers,
# and the markers are the only place the text names the ATS2 home or the C compiler's install
# directory. So a build/ made where the ATS2 home and the C compiler are in one directory
# keeps its objects when they are in another (the same files), the way the stamp keeps it,
# while a header that shadows another, with other bytes, still makes the object again; a
# shadowing header with the same bytes makes the same object, which is kept. The control is
# the same move with a stand-in clang that drops -P: the markers are back and the object is
# made again, so the move does change them and this test sees it.
# usage: tests/build-toolchain-path/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR
# The compiler's own copy is for Linux, where the resource directory is found beside the
# binary (<bin>/../lib/clang/<version>); the macOS branch is not run
[ "$(uname -s)" = Linux ] || { echo "build-toolchain-path: skipped (not Linux)"; exit 0; }
# bats probes a toolchain it did not install (bats-lang/bats#264); one known by the cksum of
# patsopt's bytes and 21 is not (src/ats2.bats)
known() { printf '%s 21\n' "$(cksum < "$1/.bats/ats2/bin/patsopt")" > "$1/.bats/ats2.solver"; }
make_ats2() { # <home>: a copy of the ATS2 home of this machine
  mkdir -p "$1/.bats/ats2"
  for d in bin prelude libats share ccomp; do cp -R "$HOME/.bats/ats2/$d" "$1/.bats/ats2/"; done
  known "$1"
}
fail() { echo "FAIL: $1"; shift; for f in "$@"; do cat "$f"; done; exit 1; }
REAL_BIN=$(readlink -f "$(command -v clang)")
LLVM_LIB=$(cd "$(dirname "$REAL_BIN")/../lib" && pwd)
RESOURCE=$(clang -print-resource-dir)
make_clang() { # <dir>: the compiler's binary and resource directory, the libraries linked
  mkdir -p "$1/bin" "$1/lib/clang"
  cp "$REAL_BIN" "$1/bin/clang"
  for f in "$LLVM_LIB"/lib*.so*; do ln -s "$f" "$1/lib/$(basename "$f")"; done
  cp -R "$RESOURCE" "$1/lib/clang/$(basename "$RESOURCE")"
  "$1/bin/clang" -print-resource-dir | grep -q "^$1/" ||
    fail "the copy of clang does not use its own resource directory"
}
HDR=$TMP/include
EARLIER=$TMP/earlier
mkdir -p "$HDR" "$EARLIER" "$TMP/shim"
export C_INCLUDE_PATH=$EARLIER:$HDR
mkdir -p "$TMP/pn/src/bin" "$TMP/pw/src/bin"
printf '[package]\nname = "tp"\nkind = "bin"\nunsafe = true\n' > "$TMP/pn/bats.toml"
cp "$TMP/pn/bats.toml" "$TMP/pw/bats.toml"
printf '#target native\n\n$UNSAFE begin\n\n%%{\n#include <stddef.h>\n' > "$TMP/pn/src/bin/tool.bats"
printf '#include <hdr_n.h>\n#include <hdr_same_n.h>\n' >> "$TMP/pn/src/bin/tool.bats"
printf 'size_t tp_native_value (void)\n' >> "$TMP/pn/src/bin/tool.bats"
printf '{ return HDR_N_VALUE + HDR_SAME_N_VALUE; }\n' >> "$TMP/pn/src/bin/tool.bats"
printf '%%}\n\nend\n\nimplement main0 () = ()\n' >> "$TMP/pn/src/bin/tool.bats"
printf '#target wasm binary\n\n$UNSAFE begin\n\n%%{\n' > "$TMP/pw/src/bin/web.bats"
printf '#include <stddef.h>\n' >> "$TMP/pw/src/bin/web.bats"
printf '#include <hdr_w.h>\n#include <hdr_same_w.h>\n' >> "$TMP/pw/src/bin/web.bats"
printf 'size_t tp_wasm_value (void)\n' >> "$TMP/pw/src/bin/web.bats"
printf '{ return HDR_W_VALUE + HDR_SAME_W_VALUE; }\n' >> "$TMP/pw/src/bin/web.bats"
printf '%%}\n\nend\n\nimplement main0 () = ()\n' >> "$TMP/pw/src/bin/web.bats"
printf '#define HDR_N_VALUE 1\n' > "$HDR/hdr_n.h"
printf '#define HDR_W_VALUE 1\n' > "$HDR/hdr_w.h"
printf '#define HDR_SAME_N_VALUE 2\n' > "$HDR/hdr_same_n.h"
printf '#define HDR_SAME_W_VALUE 2\n' > "$HDR/hdr_same_w.h"
# A stand-in clang notes each compile of a keyed object (the runtimes are made at every build
# and are not counted), runs the compiler in REAL_CLANG, and with DROP_P set drops -P from its
# arguments (the control)
CC_LOG=$TMP/cc-runs
export CC_LOG
cat > "$TMP/shim/clang" <<'EOF'
#!/bin/sh
case "$*" in
  *-o\ build/_bats_wasm_runtime*) ;;
  *-o\ build/_bats_native_runtime*) ;;
  *.bats_link_probe*) ;;
  *-c\ -o*) echo "$*" >> "$CC_LOG";;
esac
if [ -n "${DROP_P:-}" ]; then
  n=$#
  i=0
  while [ "$i" -lt "$n" ]; do
    a=$1
    shift
    [ "$a" = -P ] || set -- "$@" "$a"
    i=$((i + 1))
  done
fi
exec "$REAL_CLANG" "$@"
EOF
chmod +x "$TMP/shim/clang"
runs() { grep -c -- "$1" "$CC_LOG" || true; }
# Freshness is by content, so a build needs no settling
build() { # <dir> <log> <home> <llvm> <native|wasm> [env assignment...]: a debug build
  d=$1; l=$2; h=$3; v=$4; t=$5; shift 5
  (cd "$d" && env HOME="$h" REAL_CLANG="$v/bin/clang" PATH="$TMP/shim:$PATH" "$@" \
    "$BATS" -v build --only debug --only "$t" > "$l" 2>&1) || fail "build $t in $d" "$l"
}
kept() { # <log> <what>: no object compiled and build/ not dropped
  [ ! -s "$CC_LOG" ] || fail "$2 made an object again" "$CC_LOG" "$1"
  ! grep -aq '^bats: dropping build/' "$1" || fail "$2 dropped build/" "$1"
}
again() { # <log> <object> <what>: the object compiled once
  [ "$(runs "$2")" = 1 ] || fail "$3 did not make $2 once" "$CC_LOG" "$1"
}
both() { # <name> <home> <llvm> [env...]: the native project and the wasm one, logs <name>.{n,w}.log
  nm=$1; h=$2; v=$3; shift 3
  build "$TMP/pn" "$TMP/$nm.n.log" "$h" "$v" native "$@"
  build "$TMP/pw" "$TMP/$nm.w.log" "$h" "$v" wasm "$@"
}

# The toolchain in one place, and a cold build
make_ats2 "$TMP/a/home"
make_clang "$TMP/a/llvm"
: > "$CC_LOG"
both cold "$TMP/a/home" "$TMP/a/llvm"
again "$TMP/cold.n.log" 'bin/tool_dats.o ' "a cold build"
again "$TMP/cold.w.log" 'bin/web_dats.wasm.o ' "a cold build"
cp "$TMP/pn/build/src/bin/tool_dats.o" "$TMP/tool.cold.o"
cp "$TMP/pw/build/src/bin/web_dats.wasm.o" "$TMP/web.cold.o"
: > "$CC_LOG"
both same "$TMP/a/home" "$TMP/a/llvm"
kept "$TMP/same.n.log" "a build with nothing changed"
kept "$TMP/same.w.log" "a build with nothing changed"

# The text names no directory of the toolchain, where the text with line markers does
for flags in -P ""; do
  (cd "$TMP/pn" && "$TMP/a/llvm/bin/clang" -E $flags -I"$TMP/a/home/.bats/ats2" \
    -I"$TMP/a/home/.bats/ats2/ccomp/runtime" -o "$TMP/text$flags.i" build/src/bin/tool_dats.c)
done
! grep -q -e "$TMP/a" "$TMP/text-P.i" || fail "the text (-P) names a directory of the toolchain"
grep -q -e "$TMP/a/home" "$TMP/text.i" || fail "the text with line markers names no ATS2 home"
grep -q -e "$TMP/a/llvm" "$TMP/text.i" || fail "the text with markers names no compiler directory"

# The ATS2 home and the C compiler's directory moved: the same files in other directories
mkdir -p "$TMP/b"
mv "$TMP/a/home" "$TMP/b/home"
mv "$TMP/a/llvm" "$TMP/b/llvm"
[ ! -e "$TMP/a/home" ] && [ ! -e "$TMP/a/llvm" ] || fail "the first directories are still there"
: > "$CC_LOG"
both moved "$TMP/b/home" "$TMP/b/llvm"
kept "$TMP/moved.n.log" "a native build with the toolchain in other directories"
kept "$TMP/moved.w.log" "a wasm build with the toolchain in other directories"
cmp -s "$TMP/tool.cold.o" "$TMP/pn/build/src/bin/tool_dats.o" || fail "the native object changed"
cmp -s "$TMP/web.cold.o" "$TMP/pw/build/src/bin/web_dats.wasm.o" || fail "the wasm object changed"

# A header that shadows a listed one, with other bytes, still makes the object again
: > "$CC_LOG"
printf '#define HDR_N_VALUE 5\n' > "$EARLIER/hdr_n.h"
printf '#define HDR_W_VALUE 5\n' > "$EARLIER/hdr_w.h"
both shadow "$TMP/b/home" "$TMP/b/llvm"
again "$TMP/shadow.n.log" 'bin/tool_dats.o ' "a shadowing header"
again "$TMP/shadow.w.log" 'bin/web_dats.wasm.o ' "a shadowing header"
! cmp -s "$TMP/tool.cold.o" "$TMP/pn/build/src/bin/tool_dats.o" ||
  fail "the native object holds the shadowed header"
! cmp -s "$TMP/web.cold.o" "$TMP/pw/build/src/bin/web_dats.wasm.o" ||
  fail "the wasm object holds the shadowed header"
: > "$CC_LOG"
both shadow2 "$TMP/b/home" "$TMP/b/llvm"
kept "$TMP/shadow2.n.log" "the build after the shadowing header"
kept "$TMP/shadow2.w.log" "the build after the shadowing header"

# A shadowing header with the same bytes gives the same text, so the same object, which is kept
printf '#define HDR_SAME_N_VALUE 2\n' > "$EARLIER/hdr_same_n.h"
printf '#define HDR_SAME_W_VALUE 2\n' > "$EARLIER/hdr_same_w.h"
both identical "$TMP/b/home" "$TMP/b/llvm"
kept "$TMP/identical.n.log" "a shadowing header with the same bytes"
kept "$TMP/identical.w.log" "a shadowing header with the same bytes"

# The control: with -P dropped the text holds the markers, so moving the toolchain is seen
rm -f "$EARLIER/hdr_n.h" "$EARLIER/hdr_w.h" "$EARLIER/hdr_same_n.h" "$EARLIER/hdr_same_w.h"
rm -rf "$TMP/pn/build" "$TMP/pw/build"
: > "$CC_LOG"
both ctl "$TMP/b/home" "$TMP/b/llvm" DROP_P=1
again "$TMP/ctl.n.log" 'bin/tool_dats.o ' "the control's cold build"
mkdir -p "$TMP/c"
mv "$TMP/b/home" "$TMP/c/home"
mv "$TMP/b/llvm" "$TMP/c/llvm"
: > "$CC_LOG"
both ctlmoved "$TMP/c/home" "$TMP/c/llvm" DROP_P=1
again "$TMP/ctlmoved.n.log" 'bin/tool_dats.o ' "the move, with line markers (control, native)"
again "$TMP/ctlmoved.w.log" 'bin/web_dats.wasm.o ' "the move, with line markers (control, wasm)"
echo "build-toolchain-path: ok"
