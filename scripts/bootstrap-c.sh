#!/bin/sh
# Regenerate the checked-in bootstrap C seed (bootstrap/c) from the current
# sources, using an already-built bats compiler.
#
# usage: scripts/bootstrap-c.sh <bats-binary> <repository-dir> [out-dir]
#
# out-dir defaults to bootstrap/c. The output is normalized so it is
# byte-identical on every machine: patsopt's timestamp line is dropped and
# absolute paths (in location comments and in mangled symbol names)
# are made relative. CI regenerates into
# a scratch dir and diffs it against bootstrap/c.
set -eu

BATS=$1
REPO=$2
OUT=${3:-bootstrap/c}
ROOT=$(pwd)
PATSHOME_DIR=${PATSHOME:-$HOME/.bats/ats2}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$BATS" build --to-c "$TMP/c" --repository "$REPO" >/dev/null

find "$TMP/c" -name '*.o' -exec rm -f {} +

esc() { printf '%s\n' "$1" | sed -e 's/[]\/$*.^[|]/\\&/g'; }
root_re=$(esc "$ROOT/")
# patsopt also mangles each file's absolute path into C symbol names
# (e.g. /a/b/ -> _057_a_057_b_057_); strip that prefix the same way.
mangle() {
  printf '%s' "$1" | od -An -v -tu1 | tr -s ' ' '\n' | while read -r c; do
    [ -n "$c" ] || continue
    if { [ "$c" -ge 48 ] && [ "$c" -le 57 ]; } ||    # 0-9
       { [ "$c" -ge 65 ] && [ "$c" -le 90 ]; } ||    # A-Z
       { [ "$c" -ge 97 ] && [ "$c" -le 122 ]; } ||   # a-z
       [ "$c" -eq 95 ]; then                         # _
      printf "\\$(printf '%03o' "$c")"
    else
      printf '_%03o_' "$c"
    fi
  done
}
mroot_re=$(esc "$(mangle "$ROOT/")")
pats_re=$(esc "$PATSHOME_DIR")

find "$TMP/c" -type f \( -name '*.c' -o -name '*.dats' -o -name '*.sats' \) | while read -r f; do
  sed -e '/^\*\* The starting compilation time is:/d' \
      -e "s|$mroot_re||g" \
      -e "s|$root_re||g" \
      -e "s|$pats_re|\$(PATSHOME)|g" "$f" > "$f.norm"
  mv "$f.norm" "$f"
done

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -R "$TMP/c" "$OUT"
