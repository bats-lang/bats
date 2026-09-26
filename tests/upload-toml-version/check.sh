#!/bin/sh
# bats upload with a version from git packages bats.toml with the version
# injected, as the Rust bats does (config::inject_version): after the
# [package] line, or replacing every line whose trim starts with
# "version" and holds '=' when there is one. It used to package bats.toml
# unchanged, with no version.
# usage: tests/upload-toml-version/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
case_toml() { # <name> <bats.toml content> <expected archived bats.toml, with V for the version>
  d="$TMP/$1"; r="$TMP/$1-repo"; mkdir -p "$d/src" "$r"
  printf '%b' "$2" > "$d/bats.toml"
  printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$d/src/lib.bats"
  printf 'build/\ndist/\ndocs/\n' > "$d/.gitignore"
  (cd "$d" && git init -q -b main . && git add -A &&
   git -c user.name=t -c user.email=t@t commit -qm t &&
   "$BATS" upload --repository "$r" > "$TMP/$1.log" 2>&1) || { echo "FAIL: $1: upload"; cat "$TMP/$1.log"; exit 1; }
  arc=$(ls "$r"/*/*.bats)
  v=$(basename "$arc" .bats); v=${v##*_}
  printf '%b' "$3" | sed "s/V/$v/" > "$TMP/$1.want"
  unzip -p "$arc" bats.toml > "$TMP/$1.got"
  diff "$TMP/$1.want" "$TMP/$1.got" || { echo "FAIL: $1: archived bats.toml"; exit 1; }
}
case_toml insert '[package]\nname = "tvi"\nkind = "lib"\n' \
  '[package]\nversion = "V"\nname = "tvi"\nkind = "lib"\n'
case_toml replace '[package]\nname = "tvr"\nkind = "lib"\n\n[meta]\n  version = "0"\n' \
  '[package]\nname = "tvr"\nkind = "lib"\n\n[meta]\nversion = "V"\n'
echo "upload-toml-version: ok"
