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

. "$(dirname "$0")/../tests/keep-on-fail.sh"

# The seed is the same for every commit: a commit cannot name itself, so the compiler built from it
# is unnamed (src/built.bats, keyword: built-commit) whatever BATS_COMMIT the caller has set
unset BATS_COMMIT

"$BATS" build --to-c "$TMP/c" --repository "$REPO" >/dev/null

find "$TMP/c" -name '*.o' -exec rm -f {} +
# The build's .sats change stamp is there only when this build wrote a
# .sats, so it depends on the cache, not on the sources
rm -f "$TMP/c/.sats_changed"
# So are the shared cache's working files (BATS_CACHE_DIR's toolchain
# listing and depgen output), there only when the build used it
rm -f "$TMP/c/.bats_toolchain" "$TMP/c/.bats_depgen"
# A build keeps the files of each module's key (bats#323), as a check does:
# the listing of the project's .sats and .hats names, the graph of
# patsopt --depgen's answers and the digests kept for the run
rm -rf "$TMP/c/.bats_names" "$TMP/c/.bats_graph" "$TMP/c/.bats_dg"
# patsopt's stdout (bats-lang/bats#301), an empty file after a clean run
rm -f "$TMP/c/.patsopt_stdout"
# The build's stamp and the listing of the C compiler it hashes name this
# machine's toolchain (bats-lang/bats#267), not the sources
rm -f "$TMP/c/.bats_stamp" "$TMP/c/.bats_stamp.new" "$TMP/c/.bats_cc" "$TMP/c/.bats_libs" "$TMP/c/.bats_link"

# What validation judged (bats-lang/bats#296) is a record of this checkout's
# files, there when the project's build/ was
rm -rf "$TMP/c/.bats_valid"

# Each C and object has a key beside it (bats#254) that hashes patsopt's
# raw C, which names this machine's paths; the seed's Makefile uses none
find "$TMP/c" -name '*.key' -exec rm -f {} +
# and a depfile (bats#394) names this machine's headers
find "$TMP/c" -name '*.o.d' -exec rm -f {} +

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
