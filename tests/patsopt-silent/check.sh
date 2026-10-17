#!/bin/sh
# A patsopt that fails and prints nothing on stderr (bats-lang/bats#301: on
# a full disk patsopt's own messages fail with ENOSPC, so its stderr is
# empty and bats used to print "error: patsopt error:" with no text).
# bats now says the module, the exit status and what patsopt wrote to
# stdout (the first 4096 bytes, then [cut]), and, when the build's file system has
# under 64 MB free (df -Pk build), "no space left on device (N MB free in
# build)". A failure with no text is never reported as "error: patsopt
# error:". The stand-in patsopt fails with the output FAKE names; the
# stand-in df reports the free space FREE_KIB names.
# usage: tests/patsopt-silent/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_PATSOPT_TIMEOUT_S BATS_PATSOPT_MEM_MB
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin" "$TMP/fakebin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done

# the stand-in patsopt: fails (status 1) after writing what FAKE says to
# stdout, to stderr for FAKE=stderr, or nothing at all
cat > "$H/.bats/ats2/bin/patsopt" <<'SH2'
#!/bin/sh
case "${FAKE:-silent}" in
  silent) ;;
  stdout) printf 'patsopt wrote this to stdout\n' ;;
  long) i=0; while [ $i -lt 1000 ]; do printf '0123456789'; i=$((i + 1)); done ;;
  stderr) printf 'the message of patsopt\n' >&2 ;;
esac
exit 1
SH2
chmod +x "$H/.bats/ats2/bin/patsopt"

# the stand-in df: the Available column is FREE_KIB (the 1024-byte blocks)
cat > "$TMP/fakebin/df" <<'SH2'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/fake 1000000 900000 %s 90%% /\n' "${FREE_KIB:-5000000}"
SH2
chmod +x "$TMP/fakebin/df"

project() { # <directory>: a project of one binary, named p
  mkdir -p "$1/src/bin"
  printf '[package]\nname = "p"\nkind = "bin"\n' > "$1/bats.toml"
  printf 'implement main0 () = println! (1)\n' > "$1/src/bin/p.bats"
}
for d in silent stdout long stderr disk; do project "$TMP/$d"; done

# run <directory> <fake> [free KiB]: check in the directory; the status in
# $rc, the output in $TMP/<directory>.log (stdout and stderr together)
run() {
  d=$1
  rc=0
  (cd "$TMP/$d" && NO_COLOR=1 HOME="$H" PATH="$TMP/fakebin:$PATH" FAKE="$2" FREE_KIB="${3:-5000000}" "$BATS" check) > "$TMP/$d.log" 2>&1 || rc=$?
}
fail() { echo "FAIL: $1"; cat "$TMP/$2.log"; exit 1; }

# no text, enough room: the module, the status, nothing else
run silent silent
[ $rc = 1 ] || fail "a patsopt that fails silently: status $rc, not 1" silent
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/silent.log" \
  || fail "a silent patsopt failure was not said as one, naming the module and the status" silent
if grep -q "patsopt error:" "$TMP/silent.log"; then fail "a silent failure was reported as 'error: patsopt error:'" silent; fi
if grep -q "no space" "$TMP/silent.log"; then fail "room was 5 GB and the failure said no space" silent; fi

# stdout is said, after the status
run stdout stdout
[ $rc = 1 ] || fail "a patsopt that writes to stdout and fails: status $rc" stdout
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing; stdout was: patsopt wrote this to stdout\$" "$TMP/stdout.log" \
  || fail "patsopt's stdout was not said after the status" stdout

# stdout is cut at 4096 bytes: 10000 bytes of digits give 4096 of them
run long long
[ $rc = 1 ] || fail "a patsopt with a long stdout: status $rc" long
grep -q "stdout was: " "$TMP/long.log" || fail "a long stdout was not said" long
digits=$(sed -n 's/.*stdout was: //p' "$TMP/long.log" | tr -cd '0-9' | wc -c)
[ "$digits" = 4096 ] || fail "stdout said $digits digits, not 4096 (the cap)" long
grep -q "\[cut\]" "$TMP/long.log" || fail "a cut stdout was not marked [cut]" long

# a failure that has stderr is still the patsopt error it was
run stderr stderr
[ $rc = 1 ] || fail "a patsopt with stderr: status $rc" stderr
grep -q "^error: patsopt error:" "$TMP/stderr.log" || fail "a patsopt error with stderr was not reported as one" stderr
if grep -q "printed nothing" "$TMP/stderr.log"; then fail "a failure with stderr said it printed nothing" stderr; fi

# under 64 MB free in build/: the disk is named (2 MB here)
run disk silent 2048
[ $rc = 1 ] || fail "a silent failure on a nearly full disk: status $rc" disk
grep -q "^error: no space left on device (2 MB free in build): patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/disk.log" \
  || fail "a nearly full disk was not named with its free space" disk

echo "patsopt-silent: ok"
