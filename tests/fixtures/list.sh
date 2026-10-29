#!/bin/sh
# bats fixtures <dir> --list-affected <path>... (bats-lang/bats#570; the rule is in
# .claude/rules/fixtures.md, "--list-affected"): prints, one `accept/<name>` or `reject/<name>`
# a line, every fixture a change to the paths reaches: the module the snippet is put into is one
# of them, one of the fixture's own files (file, before, snippet.bats, expect) is one, a file its
# memo entry records patsopt read is one (a module `src/X.bats` stands for the `build/src/X.sats`
# patsopt reads), or it has no usable memo entry (listed, so nothing is missed).
# Why this is a shell script (quire#646, CLAUDE.md "we do not write shell scripts"): a bats test
# would have to plant a project, run the built `bats` in it and read its output, which `bats test`
# ($UNITTEST blocks, in-process) cannot do and for which bats#284 (a test driver in bats for
# tests/*/check.sh) is the open ticket; this follows tests/fixtures/bless.sh, which names the
# avenues searched (process, file packages: no working directory for a child, no copy, no unlink).
#
#  * a changed module lists the fixture put into it, and no other;
#  * a changed module the fixture's module staloads lists it (through the memo's recorded reads);
#  * an unrelated path lists none;
#  * a changed snippet.bats, before, file or expect lists its fixture;
#  * a fixture with no memo entry is listed for any path, one with an entry is not;
#  * "./src/x.bats" and the absolute path name the same file as "src/x.bats";
#  * several paths list the union, --only keeps the listing to the members it names;
#  * nothing is run or written: no `fixtures:` line, the fixtures' files are as they were;
#  * --bless and --prune are usage errors with it (status 2).
#
# usage: tests/fixtures/list.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COMMIT BATS_COLD BATS_MEMO_DIR XDG_CACHE_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
P=$TMP/proj
mkdir -p "$P/src" "$TMP/tmp"
printf '[package]\nname = "fx"\nkind = "lib"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub stadef limit = 1\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n' > "$P/src/lib.bats"
printf '#include "share/atspre_staload.hats"\nstaload "lib.sats"\n\n#pub fn one (): int(limit)\n\nimplement one () = 1\n\n(* end *)\n' > "$P/src/other.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fn three (): int\n\nimplement three () = 3\n\n(* end *)\n' > "$P/src/third.bats"
printf 'not a module\n' > "$P/README.md"
export TMPDIR=$TMP/tmp
MEMO=$TMP/memo
FX=$P/fx
# fixture <accept|reject> <name> <module> <snippet text> [<expect text>]
fixture() {
  d=$FX/$1/$2; mkdir -p "$d"
  printf '%s\n' "$3" > "$d/file"
  printf '(* end *)\n' > "$d/before"
  printf '%s\n' "$4" > "$d/snippet.bats"
  [ $# -lt 5 ] || printf '%s\n' "$5" > "$d/expect"
}
fixture accept reads-lib src/other.bats 'fn g (x: int): int = x'
fixture accept alone src/third.bats 'fn g (x: int): int = x'
fixture reject bad src/third.bats 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
stale'
run() { # <log> args...: bats fixtures in the project, its status in $rc
  l=$1; shift
  (cd "$P" && "$BATS" fixtures fx --memo "$MEMO" --work "$TMP/work" "$@") > "$l" 2>&1; rc=$?
}
# listed <name> <expected members, one text with line feeds> args...
listed() {
  n=$1; want=$2; shift 2
  run "$TMP/$n.log" "$@"
  [ $rc = 0 ] || { cat "$TMP/$n.log"; fail "$n: status $rc"; }
  printf '%s' "$want" > "$TMP/$n.want"
  cmp -s "$TMP/$n.want" "$TMP/$n.log" || { echo "--- wanted"; cat "$TMP/$n.want"; echo "--- got"; cat "$TMP/$n.log"; fail "$n: wrong list"; }
}

# the memo is filled by a run of the fixtures (the reject's expect is wrong on purpose: its entry is kept all the same)
run "$TMP/fill.log" 
grep -aq '^ok   accept/reads-lib' "$TMP/fill.log" || { cat "$TMP/fill.log"; fail "fill: accept/reads-lib did not pass"; }
find "$MEMO" -name '*.key' | grep -q . || fail "fill: the memo holds no entry"
cp -R "$FX" "$TMP/fx-before"

listed module  'accept/reads-lib
' --list-affected src/other.bats
listed module-two 'accept/alone
reject/bad
' --list-affected src/third.bats
# a module the fixture's module staloads: its recorded reads hold build/src/lib.sats
listed staloaded 'accept/reads-lib
' --list-affected src/lib.bats
listed unrelated '' --list-affected README.md src/nothing.bats
# the fixture's own files
listed snippet 'accept/alone
' --list-affected fx/accept/alone/snippet.bats
listed before 'accept/reads-lib
' --list-affected fx/accept/reads-lib/before
listed file 'accept/reads-lib
' --list-affected fx/accept/reads-lib/file
listed expect 'reject/bad
' --list-affected fx/reject/bad/expect
# the same file spelt another way
listed dot 'accept/reads-lib
' --list-affected ./src/lib.bats
listed absolute 'accept/reads-lib
' --list-affected "$P/src/lib.bats"
# several paths, the union; the option may follow other options
listed several 'accept/reads-lib
reject/bad
' --list-affected fx/reject/bad/expect src/lib.bats
listed after-option 'accept/reads-lib
' --cold --list-affected src/lib.bats
listed only 'accept/alone
' --only accept/alone --list-affected src/other.bats src/third.bats
# no path at all: only a fixture with no entry is listed, and all have one
listed no-path '' --list-affected
# a fixture with no memo entry is listed, whatever the path
fixture accept fresh src/third.bats 'fn k (x: int): int = x'
listed no-entry 'accept/fresh
' --list-affected README.md
# its siblings keep their entries, so a path that reaches one of them lists it with the new one
listed no-entry-and 'accept/fresh
reject/bad
' --list-affected fx/reject/bad/snippet.bats
# nothing was run or written: no summary line, the fixtures' files and the memo as they were
rm -rf "$FX/accept/fresh"
diff -r "$TMP/fx-before" "$FX" > /dev/null || fail "the fixtures changed"
# a memo that is not there: every fixture is listed
rm -rf "$TMP/nomemo"
(cd "$P" && "$BATS" fixtures fx --memo "$TMP/nomemo" --work "$TMP/work" --list-affected README.md) > "$TMP/nomemo.log" 2>&1 || { cat "$TMP/nomemo.log"; fail "nomemo: status"; }
printf 'accept/alone\naccept/reads-lib\nreject/bad\n' > "$TMP/nomemo.want"
cmp -s "$TMP/nomemo.want" "$TMP/nomemo.log" || { cat "$TMP/nomemo.log"; fail "nomemo: not every fixture listed"; }
# usage errors
run "$TMP/b.log" --bless --list-affected src/lib.bats
[ $rc = 2 ] || { cat "$TMP/b.log"; fail "--bless with --list-affected: status $rc"; }
run "$TMP/b2.log" --list-affected src/lib.bats --bless
[ $rc = 2 ] || { cat "$TMP/b2.log"; fail "--list-affected with --bless: status $rc"; }
run "$TMP/p.log" --list-affected src/lib.bats --prune
[ $rc = 2 ] || { cat "$TMP/p.log"; fail "--prune with --list-affected: status $rc"; }
grep -q -- '--list-affected' "$TMP/p.log" || fail "the usage error does not name --list-affected"
echo "list: ok"
