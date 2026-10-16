#!/bin/sh
# bats ats2 install (bats-lang/bats#283): the pinned ATS2 (src/ats2.bats)
# downloaded, checked against its SHA-256, built and put in ~/.bats/ats2,
# once. A private HOME per case; curl and make are stand-ins on the PATH
# (curl serves the real pinned tarball, fetched once with the real curl,
# or junk, or fails; make writes a patsopt, or fails like a build without
# libgmp), so a case takes a second and patsopt is not built.
#  * a download whose SHA-256 is not the pin's is refused, named, removed
#  * a failed download, and a failed build, install nothing and leave
#    nothing (no ats2, no ats2.new, no tarball)
#  * a good install leaves bin/patsopt and the marker of the pin
#  * the second run does nothing (no curl, the marker untouched)
#  * a toolchain bats did not make is used as it is, never replaced
#  * a marker of another pin is replaced; what a killed run left is cleared
#  * a link to another pin's toolchain is refused before any download or build
#  * a marker with no patsopt (half made) is replaced
#  * no HOME is an error
#  * the pin is in src/ats2.bats alone
# usage: tests/ats2-install/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ok() { echo "ok   $1"; }
name=$(sed -n 's/^#define ATS2_NAME "\(.*\)"$/\1/p' "$ROOT/src/ats2.bats")
sha=$(sed -n 's/^#define ATS2_SHA256 "\(.*\)"$/\1/p' "$ROOT/src/ats2.bats")
url=$(sed -n 's/^#define ATS2_URL "\(.*\)"$/\1/p' "$ROOT/src/ats2.bats")
[ ${#sha} -eq 64 ] || fail "the pin's sha256 is '$sha'"
case $url in https://*"/$name.tgz") ;; *) fail "the pin's url is '$url'" ;; esac
unset BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_CACHE_DIR
curl -fsSL "$url" -o "$TMP/real.tgz"
[ "$(sha256sum "$TMP/real.tgz" | cut -d' ' -f1)" = "$sha" ] || fail "the pinned tarball is not the pin"
FAKE=$TMP/fakebin
mkdir -p "$FAKE"
cat > "$FAKE/curl" <<SH
#!/bin/sh
echo "curl \$*" >> "$TMP/calls"
out=
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && out=\$2; shift; done
case \$(cat "$TMP/curl-mode") in
  real) [ -f "$TMP/curl-sleep" ] && sleep 2; cp "$TMP/real.tgz" "\$out" ;;
  modified) cp "$TMP/modified.tgz" "\$out" ;;
  junk) echo not a tarball > "\$out" ;;
  fail) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;;
esac
SH
cat > "$FAKE/make" <<SH
#!/bin/sh
echo "make \$*" >> "$TMP/calls"
if [ "\$(cat "$TMP/make-mode")" = fail ]; then echo "gmp.h: No such file or directory" >&2; exit 2; fi
dir=
for a in "\$@"; do case \$a in -C) ;; *) [ -d "\$a" ] && dir=\$a ;; esac; done
printf '#!/bin/sh\n' > "\$dir/patsopt"; chmod +x "\$dir/patsopt"
SH
chmod +x "$FAKE/curl" "$FAKE/make"
newhome() { H="$TMP/home-$1"; rm -rf "$H"; mkdir -p "$H"; : > "$TMP/calls"; }
run() { HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out" 2>&1; }
leftovers() { [ ! -e "$H/.bats/ats2.new" ] && [ ! -e "$H/.bats/ats2.tgz.part" ] && [ -z "$(ls -d "$H"/.bats/ats2-download.* 2>/dev/null)" ]; }

# a valid tarball of the same ATS2 with one file changed
mkdir "$TMP/unpacked"; tar -xzf "$TMP/real.tgz" -C "$TMP/unpacked"
echo "# changed" >> "$TMP/unpacked/$name/Makefile"
tar -czf "$TMP/modified.tgz" -C "$TMP/unpacked" "$name"
[ "$(sha256sum "$TMP/modified.tgz" | cut -d' ' -f1)" != "$sha" ] || fail "the modified tarball has the pin's digest"

echo modified > "$TMP/curl-mode"; echo ok > "$TMP/make-mode"
newhome modified
run && fail "a modified but valid tarball was installed"
grep -q "not the pinned" "$TMP/out" || fail "the modified tarball is not refused for its digest"
[ ! -e "$H/.bats/ats2" ] && leftovers || fail "a modified tarball left files"
grep -q '^make' "$TMP/calls" && fail "make ran on a modified tarball"
ok "a valid tarball with one file changed is refused"

echo junk > "$TMP/curl-mode"; echo ok > "$TMP/make-mode"
newhome junk
run && fail "a download that is not the pin was installed"
grep -q "not the pinned" "$TMP/out" || { cat "$TMP/out"; fail "the refusal does not say why"; }
[ ! -e "$H/.bats/ats2" ] && leftovers || fail "a refused download left files"
grep -q '^make' "$TMP/calls" && fail "make ran on a refused download"
ok "a download that is not the pin is refused"

echo fail > "$TMP/curl-mode"
newhome nodownload
run && fail "a failed download was installed"
[ ! -e "$H/.bats/ats2" ] && leftovers || fail "a failed download left files"
ok "a failed download installs nothing"

echo real > "$TMP/curl-mode"; echo fail > "$TMP/make-mode"
newhome nobuild
run && fail "a failed build was installed"
grep -q "libgmp" "$TMP/out" || fail "a failed build does not mention libgmp"
[ ! -e "$H/.bats/ats2" ] && leftovers || fail "a failed build left files"
ok "a failed build installs nothing and leaves nothing"

echo ok > "$TMP/make-mode"
newhome "with space"
run || { cat "$TMP/out"; fail "the install in a HOME with a space failed"; }
[ -x "$H/.bats/ats2/bin/patsopt" ] || fail "no patsopt in a HOME with a space"
ok "a HOME with a space"

# two installs at once on a fresh HOME: both succeed, one downloads
newhome concurrent
touch "$TMP/curl-sleep"
( HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out1" 2>&1; echo $? > "$TMP/rc1" ) &
( HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out2" 2>&1; echo $? > "$TMP/rc2" ) &
wait
rm -f "$TMP/curl-sleep"
[ "$(cat "$TMP/rc1")" = 0 ] && [ "$(cat "$TMP/rc2")" = 0 ] || { cat "$TMP/out1" "$TMP/out2"; fail "two installs at once: one failed"; }
[ "$(grep -c '^curl' "$TMP/calls")" = 1 ] || fail "two installs at once downloaded $(grep -c '^curl' "$TMP/calls") times"
[ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$name $sha" ] && leftovers || fail "two installs at once left a bad state"
ok "two installs at once take turns"

newhome fresh
run || { cat "$TMP/out"; fail "the install failed"; }
[ -x "$H/.bats/ats2/bin/patsopt" ] || fail "no bin/patsopt"
[ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$name $sha" ] || fail "the marker is not the pin"
[ -f "$H/.bats/ats2/ccomp/runtime/pats_ccomp_basics.h" ] || fail "the tarball was not unpacked into ats2"
leftovers || fail "the install left files"
ok "a fresh install"

: > "$TMP/calls"; stamp=$(ls -l --time-style=full-iso "$H/.bats/ats2/.bats-ats2")
run || fail "the second run failed"
grep -q "already installed" "$TMP/out" || fail "the second run does not say so"
[ ! -s "$TMP/calls" ] || fail "the second run downloaded or built"
[ "$stamp" = "$(ls -l --time-style=full-iso "$H/.bats/ats2/.bats-ats2")" ] || fail "the marker changed"
ok "the second run does nothing"

newhome foreign
mkdir -p "$H/.bats/ats2/bin"; printf '#!/bin/sh\n' > "$H/.bats/ats2/bin/patsopt"; chmod +x "$H/.bats/ats2/bin/patsopt"
run || fail "a foreign toolchain failed"
grep -q "was not installed by bats" "$TMP/out" || fail "a foreign toolchain is not said"
HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install 2>&1 >/dev/null | grep -q "bats#264" || fail "the warning is not on stderr"
[ ! -s "$TMP/calls" ] && [ ! -e "$H/.bats/ats2/.bats-ats2" ] || fail "a foreign toolchain was touched"
ok "a toolchain bats did not make is used as it is"

newhome stale
mkdir -p "$H/.bats/ats2/bin"; printf '#!/bin/sh\nold\n' > "$H/.bats/ats2/bin/patsopt"; chmod +x "$H/.bats/ats2/bin/patsopt"
echo "ATS2-Postiats-gmp-0.0.1 0000" > "$H/.bats/ats2/.bats-ats2"
mkdir -p "$H/.bats/ats2.new/x" "$H/.bats/ats2-download.old"; echo half > "$H/.bats/ats2.tgz.part"
run || { cat "$TMP/out"; fail "replacing an older pin failed"; }
[ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$name $sha" ] || fail "the older pin stayed"
leftovers || fail "what a killed run left stayed"
ok "an older pin is replaced and a killed run's files are cleared"

# anything bats did not make is replaced never: a directory with other files, a
# link, and what a killed run of an older bats left
newhome precious
mkdir -p "$H/.bats/ats2/work"; echo precious > "$H/.bats/ats2/work/notes"
before=$(cd "$H/.bats" && find ats2 | sort; cd ats2 && cksum work/notes)
run && fail "a directory with other files was replaced"
grep -q "does not replace" "$TMP/out" || { cat "$TMP/out"; fail "the refusal does not say why"; }
after=$(cd "$H/.bats" && find ats2 | sort; cd ats2 && cksum work/notes)
[ "$before" = "$after" ] || fail "the directory was touched"
[ ! -s "$TMP/calls" ] || fail "something was downloaded or built for a directory that is not replaced"
newhome link
mkdir -p "$H/.bats" "$TMP/linked-target"; echo precious > "$TMP/linked-target/notes"; ln -s "$TMP/linked-target" "$H/.bats/ats2"
run && fail "a link was replaced"
[ -L "$H/.bats/ats2" ] && [ "$(cat "$TMP/linked-target/notes")" = precious ] || fail "the link or its target was touched"
newhome emptydir
mkdir -p "$H/.bats/ats2"
run || { cat "$TMP/out"; fail "an empty directory was refused"; }
[ -x "$H/.bats/ats2/bin/patsopt" ] || fail "an empty directory was not installed into"
ok "a directory bats did not make is never replaced (checked before and after), an empty one is"

# a link to a toolchain of another pin is refused before anything is downloaded or built
newhome linkforeign
mkdir -p "$H/.bats" "$TMP/linked-foreign/bin"; printf '#!/bin/sh\n' > "$TMP/linked-foreign/bin/patsopt"; chmod +x "$TMP/linked-foreign/bin/patsopt"
echo "ATS2-Postiats-gmp-0.0.1 0000" > "$TMP/linked-foreign/.bats-ats2"; ln -s "$TMP/linked-foreign" "$H/.bats/ats2"
run && fail "a link to another pin's toolchain was replaced"
grep -q "does not replace" "$TMP/out" || { cat "$TMP/out"; fail "the refusal does not say why"; }
[ ! -s "$TMP/calls" ] || { cat "$TMP/calls"; fail "a link to another pin's toolchain downloaded or built before it was refused"; }
[ -L "$H/.bats/ats2" ] && [ "$(cat "$TMP/linked-foreign/.bats-ats2")" = "ATS2-Postiats-gmp-0.0.1 0000" ] || fail "the link or its toolchain was touched"
ok "a link to another pin's toolchain is refused before anything is downloaded"

# a marker with no patsopt is what a killed or half-made install left: replaced
newhome markeronly
mkdir -p "$H/.bats/ats2"; echo "ATS2-Postiats-gmp-0.0.1 0000" > "$H/.bats/ats2/.bats-ats2"
run || { cat "$TMP/out"; fail "a marker with no patsopt was not replaced"; }
[ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$name $sha" ] && [ -x "$H/.bats/ats2/bin/patsopt" ] || fail "the install over a marker with no patsopt is wrong"
ok "a marker with no patsopt is replaced"

newhome extra
HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install extra > "$TMP/out" 2>&1 && fail "an extra argument was accepted"
HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 > "$TMP/out" 2>&1 && fail "ats2 alone was accepted"
HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats3 > /dev/null 2>&1 || true
[ ! -e "$H/.bats/ats2" ] || fail "a refused command installed"
HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install --release > "$TMP/out" 2>&1 && fail "an unknown option was accepted"
HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install -- extra > "$TMP/out" 2>&1 && fail "words after -- were accepted"
HOME="$H" PATH="$FAKE:$PATH" "$BATS" axs2 install > "$TMP/out" 2>&1; [ ! -e "$H/.bats/ats2" ] || fail "a command that only starts like ats2 installed"
ok "an extra argument, an unknown option, words after --, and a near miss of the command word are refused"

env -u HOME PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out" 2>&1 && fail "no HOME was accepted"
grep -q "HOME" "$TMP/out" || fail "no HOME is not said"
ok "no HOME is an error"

if grep -rIlE "$sha|ATS2-Postiats-gmp" "$ROOT/.github" "$ROOT/scripts" > "$TMP/dups" 2>/dev/null && [ -s "$TMP/dups" ]; then
  cat "$TMP/dups"; fail "the pin is named outside src/ats2.bats"
fi
ok "the pin is in one place"
echo "all passed"
