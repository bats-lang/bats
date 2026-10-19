#!/bin/sh
# A patsopt that fails and prints nothing on stderr (bats-lang/bats#301: on
# a full disk patsopt's own messages fail with ENOSPC, so its stderr is
# empty and bats used to print "error: patsopt error:" with no text).
# bats now says the module, the exit status and what patsopt wrote to
# stdout (the first 4096 bytes, then [cut]), and the free space of the build
# as a fact, "(N MB free in build; if that is near 0 the disk is full)", read
# from the last line of df -Pk build: the number before the first token that
# is digits and a percent sign. No threshold: a disk with room says it too.
# Without df's answer (df fails, is missing, says no such token, or an
# Available of more than 9 digits, which an int cannot hold: about 954 GB
# free or more, where a disk is not full and a smaller figure would be a wrong
# fact) the clause is left out and nothing else changes. A failure with no text is never
# reported as "error: patsopt error:". The stand-in patsopt fails with the
# output FAKE names; the stand-in df reports the free space FREE_KIB names, in
# the form DF names.
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
# The solver of a stand-in patsopt is known (bats-lang/bats#264): bats probes a
# toolchain it did not install by running patsopt on two small files, which
# would be runs this test counts, so the answer is written first (the cksum of
# patsopt's bytes and 21, as src/ats2.bats keeps it).
printf '%s 21\n' "$(cksum < "$H/.bats/ats2/bin/patsopt")" > "$H/.bats/ats2.solver"

# the stand-in df: the Available column is FREE_KIB (the 1024-byte blocks), in
# the form DF names: a file system name with a blank in it, a df that fails,
# and an output with no Capacity column
cat > "$TMP/fakebin/df" <<'SH2'
#!/bin/sh
case "${DF:-plain}" in
  plain)
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
    printf '/dev/fake 1000000 900000 %s 90%% /\n' "${FREE_KIB:-5000000}" ;;
  blank)
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
    printf 'map auto_home 0 0 %s 100%% /System/Volumes/Data/home\n' "${FREE_KIB:-5000000}" ;;
  fail)
    printf 'df: cannot read the table\n' >&2
    exit 1 ;;
  nopercent)
    printf 'Filesystem 1024-blocks Used Available Mounted on\n'
    printf '/dev/fake 1000000 900000 %s /\n' "${FREE_KIB:-5000000}" ;;
esac
SH2
chmod +x "$TMP/fakebin/df"
# a PATH with every tool of the system's but df, for the case of no df at all
mkdir "$TMP/nodf"
for f in /usr/bin/* /bin/*; do
  [ "${f##*/}" = df ] || ln -sf "$f" "$TMP/nodf/${f##*/}" 2>/dev/null || true
done

project() { # <directory>: a project of one binary, named p
  mkdir -p "$1/src/bin"
  printf '[package]\nname = "p"\nkind = "bin"\n' > "$1/bats.toml"
  printf 'implement main0 () = println! (1)\n' > "$1/src/bin/p.bats"
}
for d in silent stdout long stderr disk blank dffail nopercent nodf nine ten eleven; do project "$TMP/$d"; done

# run <directory> <fake> [free KiB] [df form] [path]: check in the directory;
# the status in $rc, the output in $TMP/<directory>.log (stdout and stderr
# together)
run() {
  d=$1
  rc=0
  (cd "$TMP/$d" && NO_COLOR=1 HOME="$H" PATH="${5:-$TMP/fakebin:$PATH}" FAKE="$2" FREE_KIB="${3:-5000000}" DF="${4:-plain}" "$BATS" check) > "$TMP/$d.log" 2>&1 || rc=$?
}
fail() { echo "FAIL: $1"; cat "$TMP/$2.log"; exit 1; }

# no text, plenty of room: the module, the status, the free space as a fact
# (5000000 KiB is 4882 MB) and no verdict
run silent silent
[ $rc = 1 ] || fail "a patsopt that fails silently: status $rc, not 1" silent
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing (4882 MB free in build; if that is near 0 the disk is full)\.\$" "$TMP/silent.log" \
  || fail "a silent patsopt failure was not said as one, naming the module, the status and the free space" silent
if grep -q "patsopt error:" "$TMP/silent.log"; then fail "a silent failure was reported as 'error: patsopt error:'" silent; fi
if grep -q "no space" "$TMP/silent.log"; then fail "room was 5 GB and the failure said no space" silent; fi

# stdout is said, after the status
run stdout stdout
[ $rc = 1 ] || fail "a patsopt that writes to stdout and fails: status $rc" stdout
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing (4882 MB free in build; if that is near 0 the disk is full); stdout was: patsopt wrote this to stdout\$" "$TMP/stdout.log" \
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

# a nearly full disk: the same words with the small number (2 MB here)
run disk silent 2048
[ $rc = 1 ] || fail "a silent failure on a nearly full disk: status $rc" disk
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing (2 MB free in build; if that is near 0 the disk is full)\.\$" "$TMP/disk.log" \
  || fail "a nearly full disk was not shown with its free space" disk
if grep -q "no space left" "$TMP/disk.log"; then fail "the message gave a verdict of no space from a number" disk; fi

# a file system name with a blank in it shifts the columns: the free space is
# still the number before the Capacity (7 MB here, not the Used column's 0)
run blank silent 7168 blank
[ $rc = 1 ] || fail "a silent failure, df with a blank in the name: status $rc" blank
grep -q "printed nothing (7 MB free in build; if that is near 0 the disk is full)\.\$" "$TMP/blank.log" \
  || fail "a blank in the file system's name gave the wrong free space" blank

# df fails, is missing, or has no Capacity: the clause is left out, all else as it was
run dffail silent 5000000 fail
[ $rc = 1 ] || fail "a silent failure, df fails: status $rc" dffail
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/dffail.log" \
  || fail "a failing df changed the message" dffail
run nopercent silent 5000000 nopercent
[ $rc = 1 ] || fail "a silent failure, df without a Capacity: status $rc" nopercent
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/nopercent.log" \
  || fail "a df output with no Capacity changed the message" nopercent
run nodf silent 5000000 plain "$TMP/nodf"
[ $rc = 1 ] || fail "a silent failure, no df: status $rc" nodf
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/nodf.log" \
  || fail "a missing df changed the message" nodf

# the widest Available that fits is 9 digits: 999999999 KiB is 976562 MB, as
# computed, not cut
run nine silent 999999999
[ $rc = 1 ] || fail "a silent failure, 9 digits free: status $rc" nine
grep -q "printed nothing (976562 MB free in build; if that is near 0 the disk is full)\.\$" "$TMP/nine.log" \
  || fail "a 9 digit Available was not said exactly" nine
# 10 and 11 digits (about 954 GB and 9.3 TB free): the clause is left out,
# never a figure of a truncated number (1000000000 KiB read as 97656 MB)
run ten silent 1000000000
[ $rc = 1 ] || fail "a silent failure, 10 digits free: status $rc" ten
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/ten.log" \
  || fail "a 10 digit Available changed the message" ten
if grep -q "MB free" "$TMP/ten.log"; then fail "a 10 digit Available was shown as a figure" ten; fi
run eleven silent 10000000000
[ $rc = 1 ] || fail "a silent failure, 11 digits free: status $rc" eleven
grep -q "^error: patsopt on src/bin/p.bats failed with status 1 and printed nothing\.\$" "$TMP/eleven.log" \
  || fail "an 11 digit Available changed the message" eleven
if grep -q "MB free" "$TMP/eleven.log"; then fail "an 11 digit Available was shown as a figure" eleven; fi

echo "patsopt-silent: ok"
