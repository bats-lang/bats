#!/bin/sh
# The native runtime header's exit when malloc answers NULL (bats-lang/bats#510, keyword:
# native-malloc, .claude/rules/runtime-header.md): `bats_alloc`, behind ATS_MALLOC,
# atspre_ptr_alloc_tsz and ATSINScloptr_make in the header `bats build --to-c` writes, prints
# "bats: out of memory" to stderr and exits with status 1, where ATS2's own allocator would
# hand the NULL on. The header is the one this compiler writes (a tiny project built with
# --to-c), compiled into a C program that asks for more bytes than any address space has
# (SIZE_MAX, held in a volatile so the C compiler cannot fold the call), so malloc answers
# NULL by the C library's own rule on Linux, macOS and the BSDs alike.
#  * Why not `ulimit -v` (the way tests/patsopt-cap does): macOS does not enforce RLIMIT_AS
#    (patsopt-caps.md), so the first allocation would succeed there. Why not an interposed
#    malloc in a C stand-in: bats_alloc is a static inline over the C library's malloc, and
#    an interposer is linked in differently on Linux (symbol order), macOS (two-level
#    namespaces) and the BSDs; a request no heap can hold needs neither.
#  * No runtime assertion is added to the product: the header already holds the exit; this
#    only plays it.
#  * A control allocates 16 bytes and must succeed with no message.
#  * Mutants of the header, each of which must fail the cases: the NULL returned with the
#    message (no exit), the NULL returned with no message, exit status 0, no message with the
#    exit, and the exit status 2.
# usage: tests/native-malloc/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../text.sh"
fail() { echo "FAIL: $1"; exit 1; }
unset BATS_REPOSITORY BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_CACHE_DIR BATS_COMMIT

# a tiny project: its --to-c output carries _bats_native_runtime.h
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "nativemalloc"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf 'implement main0 () = println! ("hello")\n' > "$TMP/p/src/bin/nativemalloc.bats"
(cd "$TMP/p" && "$BATS" build --to-c "$TMP/c" --repository "$REPO" > "$TMP/build.log" 2>&1) \
  || { tail -5 "$TMP/build.log"; fail "--to-c did not build the project"; }
[ -f "$TMP/c/_bats_native_runtime.h" ] || fail "--to-c wrote no _bats_native_runtime.h"

cat > "$TMP/alloc.c" <<'C'
#include "_bats_native_runtime.h"
/* c: how the allocation is asked for; s is the 16-byte control */
int main(int argc, char **argv) {
  volatile size_t huge = (size_t)-1;
  void *block = 0;
  if (argc < 2) return 2;
  switch (argv[1][0]) {
  case 's': block = ATS_MALLOC(16); ATS_MFREE(block); return 0;
  case 'm': block = ATS_MALLOC(huge); break;
  case 'a': block = atspre_ptr_alloc_tsz(huge); break;
  case 'c': ATSINScloptr_make(block, huge); break;
  default: return 2;
  }
  fputs("survived\n", stdout);
  return 0;
}
C

# build_and_play <header dir> <label>: 0 when every case does what the header documents
play() {
  dir=$1 label=$2
  ${CC:-cc} -D_ATS_CCOMP_HEADER_NONE_ -D_ATS_CCOMP_EXCEPTION_NONE_ -D_ATS_CCOMP_PRELUDE_NONE_ \
    -D_ATS_CCOMP_RUNTIME_NONE_ -I"$dir" -o "$dir/alloc" "$TMP/alloc.c" > "$dir/cc.log" 2>&1 \
    || { cat "$dir/cc.log"; echo "FAIL: $label: the program does not compile"; return 1; }
  status=0
  "$dir/alloc" s > "$dir/out" 2> "$dir/err" || status=$?
  if [ "$status" -ne 0 ] || [ -s "$dir/err" ] || [ -s "$dir/out" ]; then
    echo "$label: control (16 bytes): status $status, stderr '$(cat "$dir/err")'"
    return 1
  fi
  good=0
  for c in m a c; do
    status=0
    "$dir/alloc" $c > "$dir/out" 2> "$dir/err" || status=$?
    msg=$(cat "$dir/err")
    echo "$label: case $c: status $status, stderr '$msg', stdout '$(cat "$dir/out")'"
    if [ "$status" -ne 1 ] || [ "$msg" != "bats: out of memory" ] || [ -s "$dir/out" ]; then good=1; fi
  done
  return $good
}

mkdir "$TMP/real"
cp "$TMP/c/_bats_native_runtime.h" "$TMP/real/"
play "$TMP/real" header || fail "the header does not exit with status 1 and 'bats: out of memory' on NULL"

# mutant <name> <old> <new>: the header with the first <old> of a line made <new> must fail play
mutant() {
  mkdir "$TMP/m-$1"
  text_edit_from=$TMP/real/_bats_native_runtime.h
  text_replace "$2" "$3" < "$text_edit_from" > "$TMP/m-$1/_bats_native_runtime.h"
  if cmp -s "$text_edit_from" "$TMP/m-$1/_bats_native_runtime.h"; then fail "mutant $1 changed nothing: the header's bats_alloc is not the text this test mutates"; fi
  if play "$TMP/m-$1" "mutant $1"; then fail "mutant $1 passed: the test cannot see it"; fi
  echo "ok   mutant $1 is caught"
}
mutant return-null-keep-message 'stderr); exit(1); } return block;' 'stderr); } return block;'
mutant return-null-no-message 'fputs("bats: out of memory\n", stderr); exit(1); } return block;' '} return block;'
mutant exit-0 'stderr); exit(1); }' 'stderr); exit(0); }'
mutant exit-2 'stderr); exit(1); }' 'stderr); exit(2); }'
mutant exit-no-message 'fputs("bats: out of memory\n", stderr); exit(1);' 'exit(1);'
echo "native-malloc: ok"
