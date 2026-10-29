#!/bin/sh
# bats hashes with sha256's proved API, and every digest is the one the fast API gave
# (bats-lang/bats#502, keyword: proved-sha256). Three paths, each on fixed inputs:
#  * the file hash (put_file_sha256_m, which the stamp's toolchain line, the cache's file
#    digests and the build's freshness check use): a source file of 0 bytes, "abc", 200 bytes
#    (several 64-byte blocks) and 70000 bytes (past the 65536-byte read chunk) is kept in
#    build/src/lib.dats.src as its sha256, compared with the numbers the fast API gave on the
#    base commit (7aceac5), which sha256sum agrees with;
#  * the stamp: its patsopt, libs and link lines are the sha256 of build/.bats_toolchain
#    (47 KB, hundreds of blocks), build/.bats_libs and build/.bats_link;
#  * the fixtures memo: a .res names the sha256 of its .key's bytes (the context hash of
#    put_sha_of) and ends with the sha256 of every byte before it, for a pass and for a log.
# A build that changes one byte of one digest fails each path (the pull request shows it).
# usage: tests/proved-sha256/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COLD
if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
sum256() { $SUM | cut -d' ' -f1; }
fail() { echo "FAIL: $*"; exit 1; }

# ---- the file hash, on four sources; the expected digests are the base commit's run ----
EMPTY=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
ABC=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
BLOCKS=c2a908d98f5df987ade41b5fce213067efbcc21ef2240212a41e54b5e7c28ae5
CHUNKS=66915c0872933db504e7578828dd85b7e74a4e0a061f9756793b89c4151bd4b5
for spec in empty:0:$EMPTY abc:3:$ABC blocks:200:$BLOCKS chunks:70000:$CHUNKS; do
  name=${spec%%:*}; rest=${spec#*:}; size=${rest%%:*}; want=${rest#*:}
  d=$TMP/$name
  mkdir -p "$d/src"
  printf '[package]\nname = "hashed"\nkind = "lib"\n' > "$d/bats.toml"
  if [ "$name" = abc ]; then printf abc > "$d/src/lib.bats"
  else head -c "$size" /dev/zero | tr '\0' 'a' > "$d/src/lib.bats"; fi
  (cd "$d" && "$BATS" lock --repository "$REPO" > lock.log 2>&1) || { cat "$d/lock.log"; fail "$name: lock"; }
  # the source is not Bats, so the check fails, after the .src is written (an empty one passes)
  (cd "$d" && "$BATS" check --repository "$REPO" > check.log 2>&1) || true
  got=$(cat "$d/build/src/lib.dats.src" 2>/dev/null || true)
  [ "$got" = "$want" ] || fail "$name ($size bytes): the source's digest is '$got', the base commit's is '$want'"
  [ "$(sum256 < "$d/src/lib.bats")" = "$want" ] || fail "$name: $SUM disagrees with the base commit's digest"
done

# ---- the stamp: the lines that digest a file of build/ ----
b=$TMP/abc/build
for pair in patsopt:.bats_toolchain libs:.bats_libs link:.bats_link; do
  line=${pair%%:*}; file=${pair#*:}
  got=$(grep -a "^$line " "$b/.bats_stamp" | cut -d' ' -f2)
  want=$(sum256 < "$b/$file")
  [ -n "$got" ] && [ "$got" = "$want" ] || fail "stamp: the $line line is '$got', the sha256 of $file is '$want'"
done
[ "$(wc -c < "$b/.bats_toolchain")" -gt 4096 ] || fail "stamp: the toolchain listing is too short to be many blocks"

# ---- the fixtures memo: .res names its .key's digest, and its own sum ----
P=$TMP/proj; F=$TMP/fixtures; M=$TMP/memo
mkdir -p "$P/src" "$F/accept/ok" "$F/reject/bad"
printf '[package]\nname = "fx"\nkind = "lib"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n' > "$P/src/lib.bats"
(cd "$P" && "$BATS" lock --repository "$REPO" > "$TMP/fx-lock.log" 2>&1) || { cat "$TMP/fx-lock.log"; fail "fixtures: lock"; }
for n in accept/ok reject/bad; do printf 'src/lib.bats\n' > "$F/$n/file"; printf '(* end *)\n' > "$F/$n/before"; done
printf '(* fixture-snippet *)\nfn g (x: int): int = x\n' > "$F/accept/ok/snippet.bats"
printf '(* fixture-snippet *)\nfn h (x: int): int = case+ x of 0 => 1\n' > "$F/reject/bad/snippet.bats"
printf 'function h\nline 2\npattern match is nonexhaustive:\n[^0]\n' > "$F/reject/bad/expect"
(cd "$P" && "$BATS" fixtures "$F" --work "$TMP/work" --memo "$M" > "$TMP/fx.log" 2>&1) || { cat "$TMP/fx.log"; fail "fixtures: the run"; }
grep -aq '^fixtures: 2 ok, 0 failed' "$TMP/fx.log" || { cat "$TMP/fx.log"; fail "fixtures: not 2 ok"; }
kinds=
for res in "$M"/*/*.res; do
  key=${res%.res}.key
  [ -f "$key" ] || fail "fixtures: $res has no .key"
  closure=$(awk 'NR == 4' "$res")
  [ "$closure" = "$(sum256 < "$key")" ] || fail "fixtures: $res names '$closure' for its .key, the sha256 of the .key is '$(sum256 < "$key")'"
  total=$(wc -l < "$res" | tr -d ' ')
  head -n $((total - 1)) "$res" > "$TMP/res.body"
  [ "$(tail -n 1 "$res")" = "$(sum256 < "$TMP/res.body")" ] || fail "fixtures: $res ends with a sum that is not the sha256 of the rest"
  kinds="$kinds $(awk 'NR == 3' "$res")"
done
case $kinds in *pass*log*|*log*pass*) ;; *) fail "fixtures: expected a pass and a log entry, got:$kinds" ;; esac

echo "proved-sha256: ok"
