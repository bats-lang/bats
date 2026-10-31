#!/bin/sh
# The setup action's two awk env-line checks on good and bad lines (bats-lang/bats#511,
# keyword: env-line, .claude/rules/setup-action.md). `bats clone-repository` and
# `bats record-commit` print one NAME=VALUE line that the action appends to GITHUB_ENV, and an
# awk program in the action refuses anything else. The programs are the text of
# .github/actions/setup/action.yml between its `# env-line-repository begin|end` and
# `# env-line-commit begin|end` comment lines, read as text (no YAML), so what runs here is what
# the action runs; each marker must be there exactly once and the program between them must be
# one and have no single quote (it sits in the action's single quotes).
#  * repository: exactly one line, BATS_REPOSITORY= and a value of at least one character that
#    is neither = nor CR.
#  * commit: exactly one line, BATS_COMMIT= and 40 lowercase hex digits (length 52).
#  * Mutants of each program (a dropped NR == 1, a changed length, a dropped anchor, a widened
#    class) are run on the same cases, and each must fail at least one; the case is named.
#    Dropping NR == 1 from the pattern alone is not a mutant: the END block's NR == 1 refuses
#    the same lines, so it is dropped from both places and from the END alone.
# usage: tests/setup-action/check.sh <bats-binary> <repository-dir> (the arguments are not used)
# Non-bats code of ours (quire#646), as the ticket prescribes (bats#511): a check.sh that
# tests/run-fixtures.sh runs with the others. The programs are awk, which the action itself
# runs, and the mutants are text edits of them (tests/text.sh); the avenue exhausted is a bats
# program, which could only be a driver around the same awk and has none to run it (bats#284,
# open: the test driver that runs a built binary with files and an exit status).
set -eu
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../text.sh"
ACTION=$(cd "$(dirname "$0")/../.." && pwd)/.github/actions/setup/action.yml
fail() { echo "FAIL: $1"; exit 1; }

# extract <name> <out>: the lines between `# env-line-<name> begin` and `# env-line-<name> end`
extract() {
  name=$1 out=$2
  : > "$out"
  begins=0 ends=0 on=0
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    case $trimmed in
      "# env-line-$name begin") begins=$((begins + 1)); on=1; continue ;;
      "# env-line-$name end") ends=$((ends + 1)); on=0; continue ;;
    esac
    if [ "$on" -eq 1 ]; then printf '%s\n' "$line" >> "$out"; fi
  done < "$ACTION"
  [ "$begins" -eq 1 ] && [ "$ends" -eq 1 ] || fail "$ACTION has $begins begin and $ends end markers for env-line-$name, not one each"
  [ -s "$out" ] || fail "env-line-$name holds no program"
  case $(cat "$out") in *"'"*) fail "env-line-$name holds a single quote: it would end the action's quoting" ;; esac
}
extract repository "$TMP/repository.awk"
extract commit "$TMP/commit.awk"

H39=0123456789abcdef0123456789abcdef0123456
H40=${H39}7
H41=${H40}8
# case <program> <label> <accept|refuse> <printf format of the file>: the program's answer on the file
verdict() { # <program file> <printf format>: prints accept, refuse or the awk's own failure
  printf "$2" > "$TMP/line.env"
  status=0
  awk -f "$1" "$TMP/line.env" || status=$?
  case $status in 0) echo accept ;; 1) echo refuse ;; *) echo "awk-failed-$status" ;; esac
}
# cases for a program: "program|label|expected|format" lines in $TMP/cases.<name>
cat > "$TMP/cases.repository" <<CASES
the good line|accept|BATS_REPOSITORY=/home/runner/repository\n
the good line with no final newline|accept|BATS_REPOSITORY=/home/runner/repository
no line|refuse|
a blank line|refuse|\n
two good lines|refuse|BATS_REPOSITORY=/a\nBATS_REPOSITORY=/b\n
a good line and another|refuse|BATS_REPOSITORY=/a\nsomething else\n
another line and a good one|refuse|something else\nBATS_REPOSITORY=/a\n
a blank line and a good one|refuse|\nBATS_REPOSITORY=/a\n
an empty value|refuse|BATS_REPOSITORY=\n
a second =|refuse|BATS_REPOSITORY=/a=b\n
a trailing =|refuse|BATS_REPOSITORY=/a=\n
a CR at the end|refuse|BATS_REPOSITORY=/a\r\n
a CR in the value|refuse|BATS_REPOSITORY=/a\rb\n
text before the name|refuse|xBATS_REPOSITORY=/a\n
the name of a commit|refuse|BATS_COMMIT=/a\n
CASES
cat > "$TMP/cases.commit" <<CASES
the good line|accept|BATS_COMMIT=$H40\n
the good line with no final newline|accept|BATS_COMMIT=$H40
no line|refuse|
a blank line|refuse|\n
two good lines|refuse|BATS_COMMIT=$H40\nBATS_COMMIT=$H40\n
a good line and another|refuse|BATS_COMMIT=$H40\nsomething else\n
another line and a good one|refuse|something else\nBATS_COMMIT=$H40\n
a blank line and a good one|refuse|\nBATS_COMMIT=$H40\n
an empty value|refuse|BATS_COMMIT=\n
a commit of 39 digits|refuse|BATS_COMMIT=$H39\n
a commit of 41 digits|refuse|BATS_COMMIT=$H41\n
40 characters that are not hex|refuse|BATS_COMMIT=gggggggggggggggggggggggggggggggggggggggg\n
39 digits and a g (length 52)|refuse|BATS_COMMIT=${H39}g\n
an upper-case digit (length 52)|refuse|BATS_COMMIT=${H39}A\n
all upper-case digits|refuse|BATS_COMMIT=0123456789ABCDEF0123456789ABCDEF01234567\n
a second = (length 52)|refuse|BATS_COMMIT=$H39=\n
a CR at the end (length 53)|refuse|BATS_COMMIT=$H40\r\n
a CR for the last digit (length 52)|refuse|BATS_COMMIT=$H39\r\n
a trailing space (length 53)|refuse|BATS_COMMIT=$H40 \n
a trailing space after 39 digits (length 52)|refuse|BATS_COMMIT=$H39 \n
text before the name (length 52)|refuse|xBATS_COMMIT=$H39\n
the name of a repository|refuse|BATS_REPOSITORY=$H40\n
CASES

# run_cases <name> <program file> <label>: 0 when every case has its expected verdict; the first
# case that does not is in $TMP/first-failure
run_cases() {
  name=$1 prog=$2 label=$3
  : > "$TMP/first-failure"
  wrong=0
  while IFS='|' read -r case_label expected format; do
    got=$(verdict "$prog" "$format")
    if [ "$got" != "$expected" ]; then
      wrong=$((wrong + 1))
      if [ ! -s "$TMP/first-failure" ]; then echo "$case_label (expected $expected, got $got)" > "$TMP/first-failure"; fi
      echo "  $label: '$case_label': expected $expected, got $got"
    fi
  done < "$TMP/cases.$name"
  [ "$wrong" -eq 0 ]
}

# mutant <name> <label> <old> <new> [all]: the program with the first <old> of a line (every one
# with all) made <new> must fail a case
mutant() {
  name=$1 label=$2 old=$3 new=$4
  m="$TMP/mutant-$name-$label.awk"
  if [ "${5:-}" = all ]; then text_replace_all "$old" "$new" < "$TMP/$name.awk" > "$m"; else text_replace "$old" "$new" < "$TMP/$name.awk" > "$m"; fi
  if cmp -s "$TMP/$name.awk" "$m"; then fail "mutant $name/$label changed nothing: '$old' is not in the program"; fi
  if run_cases "$name" "$m" "$name/$label" > "$TMP/mutant.log"; then
    cat "$TMP/mutant.log"
    fail "mutant $name/$label passed every case: the test cannot see it"
  fi
  case $(cat "$TMP/first-failure") in *awk-failed*) fail "mutant $name/$label is not a program: $(cat "$TMP/first-failure")" ;; esac
  echo "ok   mutant $name/$label is caught by '$(cat "$TMP/first-failure")'"
}

for name in repository commit; do
  run_cases "$name" "$TMP/$name.awk" "$name" || fail "the $name program gives a wrong verdict"
  n=$(wc -l < "$TMP/cases.$name")
  echo "ok   the $name program: $n cases"
done

mutant repository no-NR-anywhere 'NR == 1' '1' all
mutant repository no-NR-in-END 'ok && NR == 1' 'ok'
mutant repository empty-value '[^=\r]+$' '[^=\r]*$'
mutant repository no-end-anchor '+$/' '+/'
mutant repository no-start-anchor '/^BATS_REPOSITORY' '/BATS_REPOSITORY'
mutant repository CR-allowed '[^=\r]' '[^=]'
mutant repository second-equals-allowed '[^=\r]+' '[^\r]+'
mutant commit no-NR-anywhere 'NR == 1' '1' all
mutant commit no-NR-in-END 'ok && NR == 1' 'ok'
mutant commit length-51 '== 52' '== 51'
mutant commit length-53 '== 52' '== 53'
mutant commit no-length ' && length($0) == 52' ''
mutant commit upper-case-allowed '[0-9a-f]' '[0-9a-fA-F]'
mutant commit any-letter-allowed '[0-9a-f]' '[0-9a-z]'
mutant commit no-end-anchor '+$/' '+/'
mutant commit no-start-anchor '/^BATS_COMMIT' '/BATS_COMMIT'
echo "setup-action: ok"
