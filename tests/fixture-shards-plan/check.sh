#!/bin/bash
# fixture_shards (bats-lang/bats#619, keyword: fixture-shards): the shards of the fixture groups of check.yml.
# The real pins file places every group of tests/ in exactly one of its shards; a pins file that names a group
# that is not there, a shard that is not there or no shard count is refused; a shard with no group is not run
# (run-fixtures.sh with no group would run all of them).
# The tool is the subcommand bats fixture-shards (src/fixture_shards.bats, pins file src/fixture_shards.txt, bats#621) of the compiler under test.
# usage: tests/fixture-shards-plan/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")/.." && pwd)
PINS=$HERE/../src/fixture_shards.txt
. "$(dirname "$0")/../keep-on-fail.sh"
fail() { echo "FAIL: $*" >&2; echo "--- stdout" >&2; cat "$TMP/out" >&2; echo "--- stderr" >&2; cat "$TMP/err" >&2; exit 1; }

: > "$TMP/out"
: > "$TMP/err"
tool() { "$BATS" fixture-shards "$@"; }

# a stand-in for run-fixtures.sh that records its arguments, beside one empty group for each group of tests/
mkdir "$TMP/groups"
for script in "$HERE"/*/check.sh; do
  name=$(basename "$(dirname "$script")")
  mkdir "$TMP/groups/$name"
  : > "$TMP/groups/$name/check.sh"
done
printf '#!/bin/sh\nshift 2\nprintf "%%s\\n" "$@" >> "%s/ran"\n' "$TMP" > "$TMP/groups/run-fixtures.sh"
chmod +x "$TMP/groups/run-fixtures.sh"

# the real pins file: every group is in exactly one shard, and the matrix is written
: > "$TMP/github-output"
tool plan "$PINS" "$TMP/groups" "$TMP/github-output" > "$TMP/out" 2> "$TMP/err" || fail "plan refused the real pins file"
[ "$(cat "$TMP/github-output")" = "shards=[1,2,3,4]" ] || fail "the matrix is not shards=[1,2,3,4]: $(cat "$TMP/github-output")"
groups=$(ls "$TMP/groups" | grep -c -v run-fixtures.sh)
grep -q "^groups: $groups, placed in a shard: $groups\$" "$TMP/out" || fail "not every one of the $groups groups is placed"

# the shards run together are the groups there are, none twice
: > "$TMP/ran"
for shard in 1 2 3 4; do
  tool run "$PINS" "$TMP/groups" "$shard" bats repository > "$TMP/out" 2> "$TMP/err" || fail "run of shard $shard failed"
  head -n 1 "$TMP/out" | grep -q "^shard $shard of 4: " || fail "the first line of shard $shard does not list its groups"
done
sort "$TMP/ran" > "$TMP/ran.sorted"
for script in "$HERE"/*/check.sh; do echo "$TMP/groups/$(basename "$(dirname "$script")")/check.sh"; done | sort > "$TMP/listing.sorted"
cmp -s "$TMP/ran.sorted" "$TMP/listing.sorted" || fail "the shards do not run each group exactly once"

# a pins file is refused, with a message that names the fault
refused() { # <what> <message> <pins text>
  printf '%b' "$3" > "$TMP/pins"
  : > "$TMP/github-output"
  if tool plan "$TMP/pins" "$TMP/groups" "$TMP/github-output" > "$TMP/out" 2> "$TMP/err"; then fail "plan accepted: $1"; fi
  grep -q "$2" "$TMP/out" || fail "plan refused ($1) without saying $2"
  [ ! -s "$TMP/github-output" ] || fail "plan wrote the matrix for: $1"
}
refused "a group that is not there" "names a group that is not there: no-such-group" 'shards 2\nno-such-group 1\n'
refused "a shard that is not there" "a shard that is not there: check-memo" 'shards 2\ncheck-memo 3\n'
refused "shard 0" "a shard that is not there: check-memo" 'shards 2\ncheck-memo 0\n'
refused "no shard count" "no line \"shards <count>\"" 'check-memo 1\n'
refused "more than 64 shards" "shards must be 1 to 64" 'shards 65\n'

# a shard with no group is not run
printf 'shards 2\n' > "$TMP/pins"
mkdir "$TMP/one"
mkdir "$TMP/one/only"
: > "$TMP/one/only/check.sh"
cp "$TMP/groups/run-fixtures.sh" "$TMP/one/"
: > "$TMP/ran"
for shard in 1 2; do
  if tool run "$TMP/pins" "$TMP/one" "$shard" bats repository > "$TMP/out.$shard" 2> "$TMP/err"; then ok=$shard; else empty=$shard; fi
done
[ -n "${ok:-}" ] && [ -n "${empty:-}" ] || fail "of two shards with one group, exactly one must run"
grep -q "the shard has no group" "$TMP/out.$empty" || fail "the empty shard does not say so"
[ "$(wc -l < "$TMP/ran")" = 1 ] || fail "the groups were run $(wc -l < "$TMP/ran") times"
cp "$TMP/out.$empty" "$TMP/out"

# an unknown action is a usage error, and the usage text and the completions list the subcommand
if tool nonsense > "$TMP/out" 2> "$TMP/err"; then fail "an unknown action was accepted"; fi
grep -q "usage: bats fixture-shards plan" "$TMP/out" || fail "an unknown action: no usage"
"$BATS" --help | grep -q "fixture-shards run" || fail "the usage text does not list fixture-shards"
for shell in bash zsh fish; do
  "$BATS" completions $shell | grep -q 'fixture-shards' || fail "$shell completions do not list fixture-shards"
done
echo "fixture-shards-plan: ok"
