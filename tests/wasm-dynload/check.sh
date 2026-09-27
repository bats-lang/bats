#!/bin/sh
# A wasm module's vals are initialized by its dynload, which a native
# binary's C main runs before main0. A wasm module has no C main: the
# host calls bats_dynload (the entry's dynload, named by
# ATS_DYNLOADNAME) and then mainats_0_void. Without it a module's
# ref<int>(42) is a null pointer, and reading it reads address 0.
# main0 reports the ref's value to the host, which checks it is 42.
# The host provides only report: ref<int> allocates its cell with
# atspre_ptr_alloc_tsz, which the wasm prelude must define (a stub
# returning 0 put the cell at address 0).
# usage: tests/wasm-dynload/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wd"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/cell.bats" <<'BATS'
#include "share/atspre_staload.hats"

#pub fun cell_get(): int

val _cell = ref<int>(42)

implement cell_get() = !_cell
BATS
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

staload "cell.sats"

$UNSAFE begin
%{
__attribute__((import_module("env"), import_name("report")))
extern void web_report(int);
%}
extern fun report (v: int): void = "mac#web_report"
end

implement main0 () = report(cell_get())
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
cat > run.mjs <<'JS'
import { readFileSync } from "node:fs";
const mod = new WebAssembly.Module(readFileSync("dist/debug/web.wasm"));
let seen = null;
const env = { report: (v) => { seen = v; } };
const { exports } = new WebAssembly.Instance(mod, { env });
if (typeof exports.bats_dynload !== "function") { console.log("FAIL: no bats_dynload export"); process.exit(1); }
exports.bats_dynload();
exports.mainats_0_void();
if (seen !== 42) { console.log("FAIL: the ref holds " + seen + ", not 42"); process.exit(1); }
JS
node run.mjs
echo "wasm-dynload: ok"
