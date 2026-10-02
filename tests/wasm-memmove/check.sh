#!/bin/sh
# clang lowers some copies to memmove and some comparisons to memcmp on
# its own, and a wasm build is linked with -nostdlib: the runtime must
# define both, or the module imports env.memmove and fails to load
# (#220). main0 moves bytes within one buffer both ways (the regions
# overlap), copies a record of 64 ints through two pointers that may
# alias (so clang cannot use memcpy), and compares with memcmp; it
# reports 1 when every result is right. The module may import nothing
# from env but report and the host's print and exit.
# usage: tests/wasm-memmove/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wmm"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

$UNSAFE begin
%{
__attribute__((import_module("env"), import_name("report")))
extern void web_report(int);
typedef struct { int field[64]; } record;
static volatile unsigned int moved = 32;
static void record_copy(record *to, const record *from) { __builtin_memmove(to, from, sizeof(record)); }
static int move_check(void) {
  unsigned char bytes[64];
  unsigned char expected[64];
  record records[2];
  int i;
  for (i = 0; i < 64; i++) bytes[i] = (unsigned char)i;
  /* forward overlap: [0, 32) to [8, 40) */
  __builtin_memmove(bytes + 8, bytes, moved);
  for (i = 0; i < 64; i++) expected[i] = (unsigned char)(i < 8 ? i : i < 40 ? i - 8 : i);
  if (__builtin_memcmp(bytes, expected, 64) != 0) return 2;
  /* backward overlap: [8, 40) back to [0, 32) */
  __builtin_memmove(bytes, bytes + 8, moved);
  for (i = 0; i < 32; i++) expected[i] = (unsigned char)i;
  if (__builtin_memcmp(bytes, expected, 64) != 0) return 3;
  if (__builtin_memcmp(bytes, expected + 1, 4) == 0) return 4;
  for (i = 0; i < 64; i++) records[0].field[i] = i * 7;
  record_copy(&records[1], &records[0]);
  for (i = 0; i < 64; i++) if (records[1].field[i] != i * 7) return 5;
  return 1;
}
%}
extern fun report (v: int): void = "mac#web_report"
extern fun move_check (): int = "mac#move_check"
end

implement main0 () = report(move_check())
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
cat > run.mjs <<'JS'
import { readFileSync } from "node:fs";
const mod = new WebAssembly.Module(readFileSync("dist/debug/web.wasm"));
const allowed = new Set(["report", "bats_host_print", "bats_host_exit"]);
const stray = WebAssembly.Module.imports(mod).filter(i => i.module === "env" && i.kind === "function" && !allowed.has(i.name));
if (stray.length) { console.log("FAIL: imports " + stray.map(i => i.name).join(", ")); process.exit(1); }
let seen = null;
const env = { report: (v) => { seen = v; }, bats_host_print: () => {}, bats_host_exit: () => {} };
const { exports } = new WebAssembly.Instance(mod, { env });
exports.bats_dynload();
try { exports.mainats_0_void(); }
catch (e) { console.log("FAIL: " + e.message); process.exit(1); }
if (seen !== 1) { console.log("FAIL: check " + seen); process.exit(1); }
JS
node run.mjs
echo "wasm-memmove: ok"
