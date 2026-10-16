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
  real) cp "$TMP/real.tgz" "\$out" ;;
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
newhome() { H=$TMP/home-$1; rm -rf "$H"; mkdir -p "$H"; : > "$TMP/calls"; }
run() { HOME=$H PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out" 2>&1; }
leftovers() { [ ! -e "$H/.bats/ats2.new" ] && [ ! -e "$H/.bats/ats2.tgz.part" ]; }

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
grep -q "not installed by bats" "$TMP/out" || fail "a foreign toolchain is not said"
[ ! -s "$TMP/calls" ] && [ ! -e "$H/.bats/ats2/.bats-ats2" ] || fail "a foreign toolchain was touched"
ok "a toolchain bats did not make is used as it is"

newhome stale
mkdir -p "$H/.bats/ats2/bin"; printf '#!/bin/sh\nold\n' > "$H/.bats/ats2/bin/patsopt"; chmod +x "$H/.bats/ats2/bin/patsopt"
echo "ATS2-Postiats-gmp-0.0.1 0000" > "$H/.bats/ats2/.bats-ats2"
mkdir -p "$H/.bats/ats2.new/x"; echo half > "$H/.bats/ats2.tgz.part"
run || { cat "$TMP/out"; fail "replacing an older pin failed"; }
[ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$name $sha" ] || fail "the older pin stayed"
leftovers || fail "what a killed run left stayed"
ok "an older pin is replaced and a killed run's files are cleared"

env -u HOME PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out" 2>&1 && fail "no HOME was accepted"
grep -q "HOME" "$TMP/out" || fail "no HOME is not said"
ok "no HOME is an error"

if grep -rIlE "$sha|ATS2-Postiats-gmp" "$ROOT/.github" "$ROOT/scripts" > "$TMP/dups" 2>/dev/null && [ -s "$TMP/dups" ]; then
  cat "$TMP/dups"; fail "the pin is named outside src/ats2.bats"
fi
ok "the pin is in one place"
echo "all passed"
