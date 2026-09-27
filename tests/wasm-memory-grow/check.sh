#!/bin/sh
# The wasm runtime's allocator grows the memory when the heap passes its
# end. A wasm page is 65536 bytes; with 524288 taken for it, the
# allocator thought the memory 8 times as large as it is, never grew it,
# and the first write past the initial 16 MiB trapped. main0 allocates
# 40 blocks of 1 MiB, keeps them all, writes the last byte of each, and
# reports the sum of those bytes read back.
# usage: tests/wasm-memory-grow/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wm"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

$UNSAFE begin
%{
__attribute__((import_module("env"), import_name("report")))
extern void web_report(int);
static int grow_sum(void) {
  unsigned char *blocks[40];
  int i, sum = 0;
  for (i = 0; i < 40; i++) {
    blocks[i] = (unsigned char *)malloc(1048576);
    if (!blocks[i]) return -1;
    blocks[i][1048575] = (unsigned char)(i + 1);
  }
  for (i = 0; i < 40; i++) sum += blocks[i][1048575];
  for (i = 0; i < 40; i++) free(blocks[i]);
  return sum;
}
%}
extern fun report (v: int): void = "mac#web_report"
extern fun grow_sum (): int = "mac#grow_sum"
end

implement main0 () = report(grow_sum())
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
cat > run.mjs <<'JS'
import { readFileSync } from "node:fs";
const mod = new WebAssembly.Module(readFileSync("dist/debug/web.wasm"));
let seen = null;
const env = { report: (v) => { seen = v; } };
const { exports } = new WebAssembly.Instance(mod, { env });
exports.bats_dynload();
try { exports.mainats_0_void(); }
catch (e) { console.log("FAIL: " + e.message); process.exit(1); }
if (seen !== 820) { console.log("FAIL: the sum is " + seen + ", not 820"); process.exit(1); }
JS
node run.mjs
echo "wasm-memory-grow: ok"
