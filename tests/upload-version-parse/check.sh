#!/bin/sh
# An explicit [package] version goes through the Rust bats' Version::parse
# (version.rs): a "dev1" suffix split off, then '.'-separated parts that
# must each be a u32 (an optional '+', digits, at most 4294967295). An
# invalid part stops the upload with "invalid version part '<p>' in
# '<v>'"; a valid version is uploaded as parsed and printed back, so
# "+1.2" becomes 1.2 and "007.1" 7.1. It used to be used as written.
# usage: tests/upload-version-parse/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
upload() { # <version>: upload a scratch package with that version
  n=$((n + 1)); d="$TMP/p$n"; r="$TMP/r$n"
  mkdir -p "$d/src" "$r"
  printf '[package]\nname = "vp"\nversion = "%s"\nkind = "lib"\n' "$1" > "$d/bats.toml"
  printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$d/src/lib.bats"
  (cd "$d" && "$BATS" upload --repository "$r") > "$TMP/log" 2>&1 && ok=1 || ok=0
}
valid() { # <version> <archive version>
  upload "$1"
  [ $ok = 1 ] && [ -f "$r/vp/vp_$2.bats" ] || { echo "FAIL: '$1' should upload as $2"; cat "$TMP/log"; ls "$r"/* 2>/dev/null; exit 1; }
}
invalid() { # <version> <part>
  upload "$1"
  [ $ok = 0 ] || { echo "FAIL: '$1' was accepted"; exit 1; }
  grep -qxF "error: invalid version part '$2' in '$1'" "$TMP/log" || { echo "FAIL: '$1': wrong message"; cat "$TMP/log"; exit 1; }
  [ -z "$(ls "$r")" ] || { echo "FAIL: '$1' wrote into the repository"; exit 1; }
}
valid "+1.2" "1.2"
valid "007.1" "7.1"
valid "1.2dev1" "1.2dev1"
valid "4294967295.0" "4294967295.0"
invalid "1.2.x" "x"
invalid "4294967296.1" "4294967296"
invalid "1..2" ""
invalid "" ""
invalid "1.2dev2" "2dev2"
invalid "1.2dev1dev1" "2dev1"
invalid "1." ""
echo "upload-version-parse: ok"
