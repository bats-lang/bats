#!/bin/sh
# A choice is a datatype matched with case+, never an int: a match that
# leaves a constructor out does not type-check ("pattern match is
# nonexhaustive"), so adding a constructor makes every match that misses
# it an error. The compiler's own choices (its commands, the --only
# profiles and targets, a package's kind, a shell, why there is no
# upload version, which binary bats run runs) rely on it.
# usage: tests/choice-exhaustive/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <body>
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "ce%s"\nkind = "lib"\nunsafe = false\n' "$n" > "$d/bats.toml"
  printf '#include "share/atspre_staload.hats"\n%s\n' "$1" > "$d/src/lib.bats"
}
choice='datatype shell = Bash | Zsh | Fish
#pub fn name_length (): int'
lib "$choice
fn length_of (s: shell): int = case+ s of Bash() => 4 | Zsh() => 3
implement name_length () = length_of(Fish())"
if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
  echo "FAIL: a case+ that leaves Fish out type-checked"; exit 1
fi
grep -qF "pattern match is nonexhaustive" "$d/log" ||
  { echo "FAIL: rejected, but not as nonexhaustive"; grep error "$d/log" | head -3; exit 1; }
lib "$choice
fn length_of (s: shell): int = case+ s of Bash() => 4 | Zsh() => 3 | Fish() => 4
implement name_length () = length_of(Fish())"
(cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: an exhaustive case+ was rejected"; grep error "$d/log" | head -3; exit 1; }
echo "choice-exhaustive: ok"
