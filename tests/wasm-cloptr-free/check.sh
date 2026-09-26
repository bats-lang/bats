#!/bin/sh
# A wasm binary that frees a closure (cloptr_free, as the ATS library and
# promise do) must not import atspre_cloptr_free: the host provides no
# such function, so the module would fail to instantiate. The wasm
# prelude defines it as ATS's basics.cats does (ATS_MFREE).
# usage: tests/wasm-cloptr-free/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wc"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

fn run (f: (int) -<cloptr1> int): int = let
  val r = f(1)
  val () = cloptr_free($UNSAFE begin $UNSAFE.castvwtp0{cloptr0}(f) end)
in r end

implement main0 () = let
  val k = 2
  val _ = run(lam (x) => x + k)
in () end
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
if grep -q atspre_cloptr_free dist/debug/web.wasm; then
  echo "FAIL: web.wasm imports atspre_cloptr_free"; exit 1
fi
echo "wasm-cloptr-free: ok"
