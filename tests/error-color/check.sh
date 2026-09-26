#!/bin/sh
# Errors are colored as Rust's display_fancy colors them (red "error:"
# and caret, blue "-->" and bars) only when stderr is a terminal and
# NO_COLOR is unset. Needs util-linux script(1) for the terminal; the
# expected bytes are the Rust bats' output.
# usage: tests/error-color/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src"
printf '[package]\nname = "col"\nkind = "lib"\n' > "$TMP/p/bats.toml"
printf 'val z = $Q.x\n' > "$TMP/p/src/lib.bats"
cd "$TMP/p"
E=$(printf '\033')
want="error: ${E}[1;31merror:${E}[0m unknown alias 'Q' in qualified access
 ${E}[1;34m-->${E}[0m lib.bats:1:9
   ${E}[1;34m|${E}[0m
 1 ${E}[1;34m|${E}[0m val z = \$Q.x
   ${E}[1;34m|${E}[0m         ${E}[1;31m^${E}[0m"
got=$(env -u NO_COLOR script -qec "$BATS check" /dev/null | tr -d '\r')
[ "$got" = "$want" ] || { echo "FAIL: terminal"; printf '%s\n' "$got" | od -c | head -20; exit 1; }
got=$(NO_COLOR=1 script -qec "$BATS check" /dev/null | tr -d '\r')
case "$got" in *"$E"*) echo "FAIL: NO_COLOR still colored"; exit 1;; esac
got=$(env -u NO_COLOR "$BATS" check 2>&1 || true)
case "$got" in *"$E"*) echo "FAIL: colored without a terminal"; exit 1;; esac
echo "error-color: ok"
