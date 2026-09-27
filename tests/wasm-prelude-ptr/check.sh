#!/bin/sh
# A wasm binary that tests a pointer for null (as array's arena_create
# does, with ptr1_isnot_null) must not import atspre_ptr1_isnot_null or
# its kin: the host provides no such functions, so the binary did not
# instantiate. The wasm prelude defines them as ATS's pointer.cats does.
# usage: tests/wasm-prelude-ptr/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wp"\nkind = "bin"\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

fn nul {l:addr} (p: ptr l): bool = ptr1_is_null(p)

fn some {l:addr} (p: ptr l): bool = ptr1_isnot_null(p)

fn some0 (p: ptr): bool = ptr0_isnot_null(p)

fn nul0 (p: ptr): bool = ptr0_is_null(p)

implement main0 () = let
  val _ = nul(the_null_ptr)
  val _ = some(the_null_ptr)
  val _ = some0(the_null_ptr)
  val _ = nul0(the_null_ptr)
in () end
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
for f in atspre_ptr1_isnot_null atspre_ptr0_isnot_null atspre_ptr_isnot_null atspre_ptr1_is_null atspre_ptr0_is_null atspre_ptr_is_null; do
  if grep -q "$f" dist/debug/web.wasm; then
    echo "FAIL: web.wasm imports $f"; exit 1
  fi
done
echo "wasm-prelude-ptr: ok"
