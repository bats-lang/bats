#!/bin/bash
# scripts/with-env <env-file> <command> [args...] (bats-lang/bats#277): a
# shell that reads no profile gets a machine's bats settings from a file.
#  * the command's arguments arrive intact, and its exit status is the
#    command's own (7 stays 7, a missing command is 127);
#  * a variable the file sets reaches the command whether or not the file
#    says `export`, and the file wins over the caller's environment;
#  * the bats settings (BATS_SLOTS, BATS_LOCK_DIR, BATS_CACHE_DIR,
#    BATS_REPOSITORY) reach a bats run through it, which then uses them
#    (BATS_REPOSITORY names the package repository);
#  * a usage error (no file, no command, an unreadable file) is 2.
# usage: tests/with-env/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
here=$(cd "$(dirname "$0")" && pwd)
with_env=$here/../../scripts/with-env
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# other tests assume these are unset, and the caller's must not leak in
unset BATS_REPOSITORY BATS_CACHE_DIR BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'plain=one\nexport exported=two\n' > "$TMP/env"

got=$("$with_env" "$TMP/env" printf '%s|' 'a b' '*' '' 'c  d')
[ "$got" = 'a b|*||c  d|' ] || fail "arguments changed: $got"
got=$("$with_env" "$TMP/env" sh -c 'echo "$plain $exported"')
[ "$got" = 'one two' ] || fail "variables did not arrive: $got"
got=$(plain=caller "$with_env" "$TMP/env" sh -c 'echo "$plain"')
[ "$got" = 'one' ] || fail "the file did not win over the caller: $got"
"$with_env" "$TMP/env" sh -c 'exit 7'; [ $? -eq 7 ] || fail "status 7 changed"
"$with_env" "$TMP/env" no-such-command-here 2>/dev/null; [ $? -eq 127 ] || fail "missing command is not 127"
"$with_env" "$TMP/missing" true 2>/dev/null; [ $? -eq 2 ] || fail "no env file is not 2"
"$with_env" "$TMP/env" 2>/dev/null; [ $? -eq 2 ] || fail "no command is not 2"
"$with_env" 2>/dev/null; [ $? -eq 2 ] || fail "no arguments is not 2"

# the settings reach a bats run: BATS_REPOSITORY from the file is the
# repository (an app with no dependencies checks with it), and
# BATS_SLOTS makes the run take a slot in BATS_LOCK_DIR
mkdir -p "$TMP/app/src" "$TMP/locks"
printf '[package]\nname = "withenv"\nkind = "lib"\n' > "$TMP/app/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/app/src/lib.bats"
printf 'BATS_REPOSITORY=%s\nBATS_SLOTS=1\nBATS_LOCK_DIR=%s\n' "$REPO" "$TMP/locks" > "$TMP/bats.env"
(cd "$TMP/app" && "$with_env" "$TMP/bats.env" "$BATS" check) > "$TMP/check.log" 2>&1 \
  || { cat "$TMP/check.log"; fail "bats check through with-env"; }
[ -e "$TMP/locks/slot-0.lock" ] || fail "BATS_SLOTS and BATS_LOCK_DIR did not reach bats"
echo "with-env: ok"
