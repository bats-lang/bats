#!/bin/sh
# A comment, string, %{ ... %} block or $UNSAFE begin...end block with
# no close is an error with the Rust bats's message, at the place it
# starts (Rust's lexer errors); one closed on the file's last bytes is
# not. A string whose last byte is an escaping backslash is unterminated
# too: the Rust bats stepped past the end of the file there and
# panicked.
# usage: tests/unterminated/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <unsafe> <body>: a scratch library in $TMP/p$n
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "un%s"\nkind = "lib"\nunsafe = %s\n' "$n" "$1" > "$d/bats.toml"
  printf '%s' "$2" > "$d/src/lib.bats"
}
reject() { # <unsafe> <message> <line> <body>
  lib "$1" "$4"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
    echo "FAIL: accepted: $4"; exit 1
  fi
  grep -qxF "error: error: $2" "$d/log" && grep -q "^ --> lib.bats:$3:" "$d/log" ||
    { echo "FAIL: rejected, but not with \"$2\" at line $3: $4"; cat "$d/log"; exit 1; }
}
accept() { # <unsafe> <body>
  lib "$1" "$2"
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $2"; cat "$d/log"; exit 1; }
}
reject false "unterminated C-style block comment" 2 'val x = 1
/* never closed
val y = 2
'
reject false "unterminated ML-style block comment" 2 'val x = 1
(* never (* nested *) closed
'
reject false "unterminated string literal" 1 'val x = "never closed
'
reject false "unterminated string literal" 1 'val x = "ends in an escape\'
reject true "unterminated extcode block" 2 'val x = 1
%{
int x;
'
reject true "unterminated \$UNSAFE begin...end block" 1 '$UNSAFE begin
val x = 1
'
accept false 'val x = 1
/* closed on the last bytes */'
accept false 'val x = 1
(* closed (* nested *) on the last bytes *)'
accept false 'val x = "closed on the last byte"'
echo "unterminated: ok"
