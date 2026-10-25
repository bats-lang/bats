#!/bin/sh
# bats ats2 install (bats-lang/bats#283, #264): the pinned ATS2 (src/ats2.bats)
# downloaded, checked against its SHA-256, built in ~/.bats/ats2-temp with its
# marker inside, and moved to ~/.bats/ats2 with one rename. A private HOME per
# case; curl and make are stand-ins on the PATH (curl serves the real pinned
# tarball, fetched once with the real curl, or junk, or fails; make writes a
# patsopt, or fails like a build without libgmp), so a case takes a second and
# patsopt is not built.
#  * a download whose SHA-256 is not the pin's is refused, named, removed
#  * a failed download, and a failed build, install nothing and leave nothing
#  * a good install leaves bin/patsopt and the marker of the pin; the second
#    run does nothing
#  * the marker is inside the directory that is renamed (a stand-in mv reads it
#    just before the rename); a run killed right before the rename leaves no
#    ~/.bats/ats2 and the next install clears ats2-temp and installs; a run
#    killed right after leaves a complete marked toolchain
#  * a leftover ats2-temp and ats2-download.* are cleared
#  * a marker that cannot be written fails the install and leaves no ats2
#  * for build, check, test, run and ats2 install: a ~/.bats/ats2 with no marker,
#    another pin's marker, or the pin's marker and no bin/patsopt fails with the
#    error and nothing is deleted; the pin's marker is used; an absent one is
#    installed
#  * ats2 install --force replaces a toolchain with no marker, another pin's, a
#    directory with other files and a link (its target untouched), installs again
#    over the pin's own, and a build that fails leaves what was there; --force
#    elsewhere, twice, with another word or option is a usage error (exit 1)
#  * no HOME is an error; the pin is in src/ats2.bats alone
# usage: tests/ats2-install/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$(dirname "$0")/../keep-on-fail.sh"
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
if [ "\$(cat "$TMP/make-mode")" = marker-dir ]; then mkdir -p "\$dir/../../.bats-ats2"; fi
printf '#!/bin/sh\n' > "\$dir/patsopt"; chmod +x "\$dir/patsopt"
SH
chmod +x "$FAKE/curl" "$FAKE/make"
newhome() { H="$TMP/home-$1"; rm -rf "$H"; mkdir -p "$H"; : > "$TMP/calls"; }
run() { HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out" 2>&1; }
leftovers() { [ ! -e "$H/.bats/ats2-temp" ] && [ -z "$(ls -d "$H"/.bats/ats2-download.* 2>/dev/null)" ]; }

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

# --- what is at ~/.bats/ats2 is bats's own, whole, or it is not used (#264) ---
PROJ=$TMP/proj
mkdir -p "$PROJ/src/bin"
printf '[package]\nname = "app"\nkind = "bin"\n' > "$PROJ/bats.toml"
printf 'implement main0 () = ()\n' > "$PROJ/src/bin/app.bats"
printf '#include "share/atspre_staload.hats"\n\n$UNITTEST.run begin\nfn test_one (): bool = 1 + 1 = 2\nend\n' > "$PROJ/src/unit.bats"
pinmark="$name $sha"
othermark="ATS2-Postiats-gmp-0.0.1 0000"
cmd() { ( cd "$PROJ" && HOME="$H" PATH="$FAKE:$PATH" "$BATS" "$@" ) > "$TMP/out" 2>&1; }
sig() { ( cd "$H/.bats" && { [ -L ats2 ] && echo "link $(readlink ats2)"; find ats2/ -print | sort; find ats2/ -type f -exec cksum {} + | sort; } 2>/dev/null ); }
# a stand-in patsopt that records that it was used
stub() { mkdir -p "$1/bin"; printf '#!/bin/sh\necho used >> "%s"\nexit 1\n' "$TMP/patsopt-used" > "$1/bin/patsopt"; chmod +x "$1/bin/patsopt"; }
nostub_used() { [ ! -e "$TMP/patsopt-used" ]; }
echo real > "$TMP/curl-mode"; echo ok > "$TMP/make-mode"

# a toolchain with no marker (a developer's own, an -int build): every command fails
# with the error, and nothing is deleted or downloaded
for c in build check test run "ats2 install"; do
  newhome nomarker; rm -f "$TMP/patsopt-used"
  stub "$H/.bats/ats2"; echo precious > "$H/.bats/ats2/notes"
  before=$(sig); rc=0
  cmd $c || rc=$?
  [ "$rc" -ne 0 ] || { cat "$TMP/out"; fail "$c: a toolchain with no marker was used"; }
  grep -q "has no marker .bats-ats2" "$TMP/out" || { cat "$TMP/out"; fail "$c: the error does not say there is no marker"; }
  grep -q "bats never deletes what is at ~/.bats/ats2 by itself" "$TMP/out" || { cat "$TMP/out"; fail "$c: the error does not say bats deletes nothing"; }
  grep -q "bats ats2 install --force" "$TMP/out" || { cat "$TMP/out"; fail "$c: the error does not name --force"; }
  [ "$before" = "$(sig)" ] || fail "$c: a toolchain with no marker was touched"
  [ ! -s "$TMP/calls" ] && nostub_used || fail "$c: a toolchain with no marker was downloaded over or run"
done
ok "build, check, test, run and ats2 install fail on a toolchain with no marker, and delete nothing"

# an empty directory, a directory with other files and a link have no marker either
for kind in emptydir files link; do
  newhome "no-marker-$kind"
  case $kind in
    emptydir) mkdir -p "$H/.bats/ats2" ;;
    files) mkdir -p "$H/.bats/ats2/work"; echo precious > "$H/.bats/ats2/work/notes" ;;
    link) mkdir -p "$H/.bats" "$TMP/linked-$kind"; echo precious > "$TMP/linked-$kind/notes"; ln -s "$TMP/linked-$kind" "$H/.bats/ats2" ;;
  esac
  before=$(sig); rc=0
  cmd ats2 install || rc=$?
  [ "$rc" -ne 0 ] && grep -q "has no marker" "$TMP/out" || { cat "$TMP/out"; fail "$kind: not refused"; }
  [ "$before" = "$(sig)" ] && [ ! -s "$TMP/calls" ] || fail "$kind: touched"
done
ok "an empty directory, a directory with other files and a link are refused and left as they were"

# another pin's marker: the error names both pins; nothing is deleted
for c in build check test run "ats2 install"; do
  newhome otherpin; rm -f "$TMP/patsopt-used"
  stub "$H/.bats/ats2"; echo "$othermark" > "$H/.bats/ats2/.bats-ats2"
  before=$(sig); rc=0
  cmd $c || rc=$?
  [ "$rc" -ne 0 ] || { cat "$TMP/out"; fail "$c: another pin's toolchain was used"; }
  grep -qF "the marker '$othermark' and this bats needs '$pinmark'" "$TMP/out" || { cat "$TMP/out"; fail "$c: the error does not name both pins"; }
  grep -q "bats ats2 install --force" "$TMP/out" || fail "$c: the error does not name --force"
  [ "$before" = "$(sig)" ] && [ ! -s "$TMP/calls" ] && nostub_used || fail "$c: another pin's toolchain was touched or run"
done
ok "build, check, test, run and ats2 install fail on another pin's marker, naming both, and delete nothing"

# the pin's marker with no bin/patsopt is not a whole toolchain
newhome markeronly
mkdir -p "$H/.bats/ats2"; echo "$pinmark" > "$H/.bats/ats2/.bats-ats2"
before=$(sig); rc=0
cmd ats2 install || rc=$?
[ "$rc" -ne 0 ] && grep -q "no bin/patsopt" "$TMP/out" && [ "$before" = "$(sig)" ] && [ ! -s "$TMP/calls" ] || { cat "$TMP/out"; fail "the pin's marker with no patsopt was not refused"; }
ok "the pin's marker with no bin/patsopt is refused and left as it was"

# the pin's marker: used, nothing downloaded
for c in build check test run "ats2 install"; do
  newhome pinned; rm -f "$TMP/patsopt-used"
  stub "$H/.bats/ats2"; echo "$pinmark" > "$H/.bats/ats2/.bats-ats2"
  cmd $c || true
  grep -q "marker" "$TMP/out" && { cat "$TMP/out"; fail "$c: the pin's toolchain was refused"; }
  [ ! -s "$TMP/calls" ] || fail "$c: the pin's toolchain was downloaded over"
  # past the toolchain's marker, the build reads the toolchain itself (the stand-in has no prelude)
  case $c in build|check) grep -q "has no prelude" "$TMP/out" || { cat "$TMP/out"; fail "$c: the build did not go on with the pin's toolchain"; } ;; esac
done
grep -q "already installed" "$TMP/out" || fail "ats2 install does not say it is installed"
ok "build, check, test, run and ats2 install use a toolchain with the pin's marker"

# nothing at ~/.bats/ats2: installed, then used
for c in build check test run "ats2 install"; do
  newhome absent
  cmd $c || true
  [ "$(grep -c '^curl' "$TMP/calls")" = 1 ] || { cat "$TMP/out"; fail "$c: an absent toolchain was not installed once"; }
  [ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$pinmark" ] && [ -x "$H/.bats/ats2/bin/patsopt" ] && leftovers || fail "$c: the install is wrong"
done
ok "build, check, test, run and ats2 install install an absent toolchain"

# the stand-in mv: reads what is inside the directory it renames, then (by flag)
# kills bats and its shell right before or right after the rename
MVBIN=$TMP/mv-bin
mkdir -p "$MVBIN"
cat > "$MVBIN/mv" <<SH
#!/bin/sh
last=
for a in "\$@"; do last=\$a; done
case \$last in
  */.bats/ats2)
    cat "\$1/.bats-ats2" > "$TMP/mv-saw" 2>/dev/null
    bats_pid=\$(ps -o ppid= -p \$PPID | tr -d ' ')
    if [ -f "$TMP/kill-before" ]; then kill -KILL \$PPID "\$bats_pid"; exit 1; fi
    "$(command -v mv)" "\$@" || exit \$?
    if [ -f "$TMP/kill-after" ]; then kill -KILL \$PPID "\$bats_pid"; exit 1; fi
    exit 0 ;;
esac
exec "$(command -v mv)" "\$@"
SH
chmod +x "$MVBIN/mv"
mvrun() { HOME="$H" PATH="$MVBIN:$FAKE:$PATH" "$BATS" ats2 install > "$TMP/out" 2>&1; }

rm -f "$TMP/mv-saw"
touch "$TMP/kill-before"
newhome killbefore
mvrun && fail "a bats killed before the rename succeeded"
[ "$(cat "$TMP/mv-saw")" = "$pinmark" ] || fail "the marker was not inside the directory that is renamed"
[ ! -e "$H/.bats/ats2" ] && [ ! -L "$H/.bats/ats2" ] || fail "a run killed before the rename left ~/.bats/ats2"
[ -d "$H/.bats/ats2-temp" ] || fail "the kill did not happen between the build and the rename"
rm -f "$TMP/kill-before"; : > "$TMP/calls"
mvrun || { cat "$TMP/out"; fail "the install after a run killed before the rename failed"; }
[ "$(grep -c '^curl' "$TMP/calls")" = 1 ] && [ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$pinmark" ] && [ -x "$H/.bats/ats2/bin/patsopt" ] && leftovers || fail "the next install did not clear ats2-temp and install"
ok "a run killed right before the rename leaves no ats2, and the next install clears ats2-temp and installs"

touch "$TMP/kill-after"
newhome killafter
mvrun && fail "a bats killed after the rename succeeded"
rm -f "$TMP/kill-after"
[ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$pinmark" ] && [ -x "$H/.bats/ats2/bin/patsopt" ] && [ ! -e "$H/.bats/ats2-temp" ] || { cat "$TMP/out"; fail "a run killed after the rename did not leave a complete marked toolchain"; }
: > "$TMP/calls"
run || fail "the run after a kill after the rename failed"
grep -q "already installed" "$TMP/out" && [ ! -s "$TMP/calls" ] || fail "the toolchain a run killed after the rename left is not used"
ok "a run killed right after the rename leaves a complete marked toolchain"

# what a killed run left is cleared
newhome leftover
mkdir -p "$H/.bats/ats2-temp/x" "$H/.bats/ats2-download.old"; echo half > "$H/.bats/ats2-temp/.bats-ats2"
run || { cat "$TMP/out"; fail "the install over a leftover ats2-temp failed"; }
leftovers && [ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$pinmark" ] || fail "a leftover ats2-temp stayed"
ok "a leftover ats2-temp and ats2-download.* are cleared"

# the marker is bats's write, inside ats2-temp (a directory at its place): the
# install fails with the write's own line and leaves no ats2
echo real > "$TMP/curl-mode"; echo marker-dir > "$TMP/make-mode"
newhome markerdir
run && fail "an install whose marker could not be written succeeded"
grep -qxF "error: cannot write '$H/.bats/ats2-temp/.bats-ats2': Is a directory (os error 21)" "$TMP/out" || { cat "$TMP/out"; fail "the marker's write is not said as a write is"; }
[ ! -e "$H/.bats/ats2" ] && leftovers || { cat "$TMP/out"; fail "an install whose marker failed left a toolchain or files"; }
echo ok > "$TMP/make-mode"
ok "a marker that cannot be written fails the install with the write's line and leaves no toolchain"

# a marker write that leaves a FILE behind (bats#372): a file-size limit of 0 on
# bats's own writes (SIGXFSZ ignored, so a write past it fails with EFBIG). The
# programs bats starts lift the limit for themselves (wrappers here), so the
# first write that fails is the marker's.
WRAP=$TMP/limit-bin
mkdir -p "$WRAP"
for t in curl make; do
  printf '#!/bin/sh\nulimit -S -f unlimited\nexec "%s" "$@"\n' "$FAKE/$t" > "$WRAP/$t"
done
for t in tar cp; do
  printf '#!/bin/sh\nulimit -S -f unlimited\nexec "%s" "$@"\n' "$(command -v $t)" > "$WRAP/$t"
done
chmod +x "$WRAP"/*
newhome markerfile
( trap '' XFSZ; ulimit -S -f 0; st=0; HOME="$H" PATH="$WRAP:$FAKE:$PATH" "$BATS" ats2 install 2>&1 || st=$?; echo "rc=$st" ) | cat > "$TMP/out"
grep -qxF "rc=1" "$TMP/out" || { cat "$TMP/out"; fail "an install whose marker write failed did not end with status 1"; }
grep -qxF "error: cannot write '$H/.bats/ats2-temp/.bats-ats2': File too large (os error 27)" "$TMP/out" || { cat "$TMP/out"; fail "the marker's write is not said as a write is"; }
[ ! -e "$H/.bats/ats2" ] && leftovers || { cat "$TMP/out"; fail "a marker write that left a file left a toolchain or files"; }
ok "a marker write that leaves a file: no toolchain, no ats2-temp"

# --- ats2 install --force ---
frun() { HOME="$H" PATH="$FAKE:$PATH" "$BATS" ats2 install --force > "$TMP/out" 2>&1; }
replaced() { [ "$(cat "$H/.bats/ats2/.bats-ats2")" = "$pinmark" ] && [ -x "$H/.bats/ats2/bin/patsopt" ] && [ ! -L "$H/.bats/ats2" ] && [ ! -e "$H/.bats/ats2/notes" ] && [ ! -e "$H/.bats/ats2/work" ] && leftovers; }
for kind in nomarker otherpin files link ownpin; do
  newhome "force-$kind"
  case $kind in
    nomarker) stub "$H/.bats/ats2"; echo precious > "$H/.bats/ats2/notes" ;;
    otherpin) stub "$H/.bats/ats2"; echo "$othermark" > "$H/.bats/ats2/.bats-ats2"; echo precious > "$H/.bats/ats2/notes" ;;
    files) mkdir -p "$H/.bats/ats2/work"; echo precious > "$H/.bats/ats2/work/notes" ;;
    link) mkdir -p "$H/.bats" "$TMP/force-target"; stub "$TMP/force-target"; echo precious > "$TMP/force-target/notes"; echo "$othermark" > "$TMP/force-target/.bats-ats2"
          ln -s "$TMP/force-target" "$H/.bats/ats2" ;;
    ownpin) frun; : > "$TMP/calls"; echo precious > "$H/.bats/ats2/notes" ;;
  esac
  frun || { cat "$TMP/out"; fail "--force over $kind failed"; }
  replaced || { cat "$TMP/out"; fail "--force over $kind did not replace it"; }
  [ "$(grep -c '^curl' "$TMP/calls")" = 1 ] || fail "--force over $kind did not install again"
  if [ $kind = link ]; then
    [ "$(cat "$TMP/force-target/notes")" = precious ] && [ "$(cat "$TMP/force-target/.bats-ats2")" = "$othermark" ] && [ -x "$TMP/force-target/bin/patsopt" ] || fail "--force touched the target of the link"
  fi
done
ok "--force replaces no marker, another pin's marker, a directory with other files and a link (its target untouched), and installs again over the pin's own"

# a build that fails under --force leaves what was there
echo fail > "$TMP/make-mode"
for kind in nomarker ownpin; do
  newhome "force-fail-$kind"
  if [ $kind = nomarker ]; then stub "$H/.bats/ats2"; echo precious > "$H/.bats/ats2/notes"; else echo ok > "$TMP/make-mode"; frun; echo fail > "$TMP/make-mode"; : > "$TMP/calls"; fi
  before=$(sig)
  frun && fail "--force with a failed build succeeded"
  grep -q "libgmp" "$TMP/out" || fail "a failed build under --force does not mention libgmp"
  [ "$before" = "$(sig)" ] && leftovers || fail "a failed build under --force touched ~/.bats/ats2"
done
echo ok > "$TMP/make-mode"
ok "a build that fails under --force leaves ~/.bats/ats2 as it was"

# usage errors: exit 1, nothing downloaded or installed
usage() { # <bats arguments>
  newhome usage
  rc=0
  ( cd "$PROJ" && HOME="$H" PATH="$FAKE:$PATH" "$BATS" "$@" ) > "$TMP/out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || { cat "$TMP/out"; fail "bats $*: exit status $rc, not 1"; }
  [ ! -s "$TMP/calls" ] && [ ! -e "$H/.bats/ats2" ] || fail "bats $*: installed or downloaded"
}
usage ats2 install --force --force
usage ats2 install --force extra
usage ats2 install --release
usage ats2 install --force --release
usage ats2 install --force -- extra
usage build --force
usage check --force
usage test --force
usage run --force
usage lock --force
usage clone-repository --force
usage record-commit --force
usage --force build
ok "--force on any other command, twice, with another word or another option is a usage error (exit 1)"

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

[ "$("$BATS" ats2 marker)" = "$name $sha" ] || fail "ats2 marker is not the pin's name and SHA-256"
"$BATS" ats2 marker --force > "$TMP/out" 2>&1 && fail "ats2 marker --force was accepted"
ok "ats2 marker prints the pin's marker text, the one the tests write into their toolchains"

if grep -rIlE "$sha|ATS2-Postiats-gmp" "$ROOT/.github" "$ROOT/scripts" > "$TMP/dups" 2>/dev/null && [ -s "$TMP/dups" ]; then
  cat "$TMP/dups"; fail "the pin is named outside src/ats2.bats"
fi
ok "the pin is in one place"
echo "all passed"
