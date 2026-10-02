#!/bin/sh
# A wasm module exports each callback the code it links declares with
# ext# (#pub fun ... = "ext#<name>"), by that name: JS calls it on the
# instance. The names were a list in the compiler, so a new callback
# was not exported until it was added there (#222). probe.bats declares
# bats_probe_called, which no list holds; JS calls it and the module
# reports the value back. A module with no such callback exports the
# entry points and nothing named for a callback it does not have.
# usage: tests/wasm-ext-exports/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin" "$TMP/q/src/bin"
printf '[package]\nname = "wx"\nkind = "bin"\nunsafe = true\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/probe.bats" <<'BATS'
#target wasm begin
#include "share/atspre_staload.hats"

(* JS calls it with a value; it is reported back *)
#pub fun probe_called (v: int): void = "ext#bats_probe_called"

$UNSAFE begin
%{
__attribute__((import_module("env"), import_name("report")))
extern void web_report(int);
%}
extern fun report (v: int): void = "mac#web_report"
end

implement probe_called (v) = report(v + 1)
end
BATS
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary
#include "share/atspre_staload.hats"
staload "probe.sats"

implement main0 () = ()
BATS
printf '[package]\nname = "wy"\nkind = "bin"\n' > "$TMP/q/bats.toml"
cat > "$TMP/q/src/bin/web.bats" <<'BATS'
#target wasm binary
#include "share/atspre_staload.hats"

implement main0 () = ()
BATS
(cd "$TMP/p" && "$BATS" build --only debug) > "$TMP/out" 2>&1 || { echo "FAIL: build"; cat "$TMP/out"; exit 1; }
(cd "$TMP/q" && "$BATS" build --only debug) > "$TMP/out" 2>&1 || { echo "FAIL: build without callbacks"; cat "$TMP/out"; exit 1; }
cat > "$TMP/run.mjs" <<'JS'
import { readFileSync } from "node:fs";
const [withCallback, without] = process.argv.slice(2);
const mod = new WebAssembly.Module(readFileSync(withCallback));
const names = WebAssembly.Module.exports(mod).map(e => e.name);
if (!names.includes("bats_probe_called")) { console.log("FAIL: bats_probe_called not exported: " + names.join(", ")); process.exit(1); }
let seen = null;
const env = { report: (v) => { seen = v; }, bats_host_print: () => {}, bats_host_exit: () => {} };
const { exports } = new WebAssembly.Instance(mod, { env });
exports.bats_dynload();
exports.mainats_0_void();
exports.bats_probe_called(41);
if (seen !== 42) { console.log("FAIL: the callback reported " + seen); process.exit(1); }
const plain = WebAssembly.Module.exports(new WebAssembly.Module(readFileSync(without))).map(e => e.name);
for (const name of ["bats_dynload", "mainats_0_void", "malloc"]) {
  if (!plain.includes(name)) { console.log("FAIL: " + name + " not exported"); process.exit(1); }
}
for (const name of ["bats_probe_called", "bats_on_event"]) {
  if (plain.includes(name)) { console.log("FAIL: " + name + " exported by a module without it"); process.exit(1); }
}
JS
node "$TMP/run.mjs" "$TMP/p/dist/debug/web.wasm" "$TMP/q/dist/debug/web.wasm"
echo "wasm-ext-exports: ok"
