#!/bin/bash
# bats with-env <env-file> <command> [args...] (bats-lang/bats#277): a
# shell that reads no profile gets a machine's bats settings from a file.
#  * the command's arguments arrive intact, and its exit status is the
#    command's own (7 stays 7, a missing command is 127);
#  * a variable the file sets reaches the command whether or not the file
#    says `export`, and the file wins over the caller's environment;
#  * the bats settings (BATS_SLOTS, BATS_LOCK_DIR, BATS_CACHE_DIR,
#    BATS_REPOSITORY) reach a bats run through it, which then uses them
#    (BATS_REPOSITORY names the package repository);
#  * a usage error (no file, no command, an unreadable file) is 2.
#  * the file is read as dotenv (no shell is run): export, quotes, $NAME
#    and ${NAME} from the caller's environment, a later line wins;
#  * the file's limits (64 KiB, 1024 variables, 255-byte names, 64 KiB
#    values) are refused as usage errors, never cut short, and a file that
#    sets one variable on many lines, or is all comments, takes no time;
#  * a command with no / is looked for in the PATH the file gives it;
#  * 126 says why; stdin and the empty argument pass through; a command a
#    signal ends is status 1 and a signal to bats does not reach the command
#    (both are limits of the process package, said in .claude/rules/with-env.md).
# usage: tests/with-env/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
here=$(cd "$(dirname "$0")" && pwd)
with_env() { "$BATS" with-env "$@"; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# other tests assume these are unset, and the caller's must not leak in
unset BATS_REPOSITORY BATS_CACHE_DIR BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'plain=one\nexport exported=two\n' > "$TMP/env"

got=$(with_env "$TMP/env" printf '%s|' 'a b' '*' '' 'c  d')
[ "$got" = 'a b|*||c  d|' ] || fail "arguments changed: $got"
got=$(with_env "$TMP/env" sh -c 'echo "$plain $exported"')
[ "$got" = 'one two' ] || fail "variables did not arrive: $got"
got=$(plain=caller "$BATS" with-env "$TMP/env" sh -c 'echo "$plain"')
[ "$got" = 'one' ] || fail "the file did not win over the caller: $got"
with_env "$TMP/env" sh -c 'exit 7'; [ $? -eq 7 ] || fail "status 7 changed"
with_env "$TMP/env" no-such-command-here 2>/dev/null; [ $? -eq 127 ] || fail "missing command is not 127"
with_env "$TMP/missing" true 2>/dev/null; [ $? -eq 2 ] || fail "no env file is not 2"
with_env "$TMP/env" 2>/dev/null; [ $? -eq 2 ] || fail "no command is not 2"
with_env 2>/dev/null; [ $? -eq 2 ] || fail "no arguments is not 2"

# the settings reach a bats run: BATS_REPOSITORY from the file is the
# repository (an app with no dependencies checks with it), and
# BATS_SLOTS makes the run take a slot in BATS_LOCK_DIR
mkdir -p "$TMP/app/src" "$TMP/locks"
printf '[package]\nname = "withenv"\nkind = "lib"\n' > "$TMP/app/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/app/src/lib.bats"
printf 'BATS_REPOSITORY=%s\nBATS_SLOTS=1\nBATS_LOCK_DIR=%s\n' "$REPO" "$TMP/locks" > "$TMP/bats.env"
(cd "$TMP/app" && with_env "$TMP/bats.env" "$BATS" check) > "$TMP/check.log" 2>&1 \
  || { cat "$TMP/check.log"; fail "bats check through with-env"; }
[ -e "$TMP/locks/slot-0.lock" ] || fail "BATS_SLOTS and BATS_LOCK_DIR did not reach bats"
cat > "$TMP/dot.env" <<'DOT'
export A="x $plain y"
B='$plain'
# a comment

C=  spaced  
A=last $plain ${plain}z
DOT
got=$(plain=P with_env "$TMP/dot.env" sh -c 'echo "[$A][$B][$C]"')
[ "$got" = '[last P Pz][$plain][spaced]' ] || fail "dotenv parsing: $got"

# the dotenv corners
printf 'A=$\nB=${\nC=$UNSET_VARIABLE_FOR_TEST|\nD="unbalanced\nE=\\$plain\nF=x # not a comment\nG=\n' > "$TMP/corner.env"
got=$(plain=P with_env "$TMP/corner.env" sh -c 'echo "[$A][$B][$C][$D][$E][$F][$G]"')
[ "$got" = '[$][${][|]["unbalanced][\P][x # not a comment][]' ] || fail "dotenv corners: $got"
printf 'A=1\r\nB="x y"\r\nexport C=3\r\n' > "$TMP/crlf.env"
got=$(with_env "$TMP/crlf.env" sh -c 'printf "%s" "$A$B$C"' | od -An -c | tr -d ' \n')
[ "$got" = '1xy3' ] || fail "CRLF left a carriage return: $got"

# the 64 KiB limit is exact, and what is near it finishes quickly
slow() { # slow <seconds> <command...>: the command's status, or fails when too slow
  local limit=$1; shift
  local start=$SECONDS
  "$@" > /dev/null 2>&1; local status=$?
  [ $((SECONDS - start)) -le "$limit" ] || fail "too slow: $*"
  return $status
}
python3 -c "import sys; sys.stdout.write('A=' + 'x' * (65536 - 3) + '\n')" > "$TMP/exact.env"
[ "$(wc -c < "$TMP/exact.env")" -eq 65536 ] || fail "test file is not 65536 bytes"
slow 5 "$BATS" with-env "$TMP/exact.env" true || fail "a file of exactly 64 KiB is refused"
python3 -c "import sys; sys.stdout.write('A=' + 'x' * (65537 - 3) + '\n')" > "$TMP/over.env"
slow 5 "$BATS" with-env "$TMP/over.env" true; [ $? -eq 2 ] || fail "a file over 64 KiB is not 2"
python3 -c "import sys; sys.stdout.write('#\n' * 32768)" > "$TMP/comments.env"
slow 5 "$BATS" with-env "$TMP/comments.env" true || fail "a 64 KiB file of comments"
python3 -c "import sys; sys.stdout.write('A=1\n' * 16384)" > "$TMP/repeated.env"
slow 5 "$BATS" with-env "$TMP/repeated.env" true || fail "one variable on 16384 lines"
python3 -c "import sys; sys.stdout.write(''.join('V%d=x\n' % i for i in range(1024)))" > "$TMP/thousand.env"
got=$(with_env "$TMP/thousand.env" sh -c 'echo $V0 $V1023')
[ "$got" = 'x x' ] || fail "1024 variables: $got"
# the same 1024 names set again: the table keeps 1024 entries and each one
# holds its last value (a chain that is searched too little adds copies)
python3 -c "import sys; sys.stdout.write(''.join('V%d=a\n' % i for i in range(1024)) + ''.join('V%d=b\n' % i for i in range(1024)))" > "$TMP/reset.env"
got=$(with_env "$TMP/reset.env" sh -c 'env | grep -c "^V[0-9]*=b$"')
[ "$got" = '1024' ] || fail "1024 variables set again do not all hold their last value: $got"
got=$(with_env "$TMP/reset.env" sh -c 'env | grep -c "^V[0-9]*=a$"')
[ "$got" = '0' ] || fail "a variable holds its first value after being set again: $got"
python3 -c "import sys; sys.stdout.write(''.join('V%d=x\n' % i for i in range(1025)))" > "$TMP/over-thousand.env"
slow 5 "$BATS" with-env "$TMP/over-thousand.env" true; [ $? -eq 2 ] || fail "1025 variables are not refused"
python3 -c "import sys; sys.stdout.write(''.join('V%d=x\n' % i for i in range(9000)))" > "$TMP/many.env"
slow 5 "$BATS" with-env "$TMP/many.env" true; [ $? -eq 2 ] || fail "a 64 KiB file of assignments is not refused quickly"

# nothing is cut short: a name over 255 bytes and a value over 64 KiB
# are usage errors that name the variable
printf 'LONG_NAME=${%s}\n' "$(python3 -c "print('n' * 256)")" > "$TMP/longname.env"
with_env "$TMP/longname.env" true 2> "$TMP/err"; [ $? -eq 2 ] || fail "a name over 255 bytes is not 2"
grep -q 'LONG_NAME' "$TMP/err" || fail "the error does not name the variable: $(cat "$TMP/err")"
printf 'ok=1\nLONG_NAME=${%s}\n' "$(python3 -c "print('n' * 255)")" > "$TMP/name255.env"
with_env "$TMP/name255.env" true || fail "a name of 255 bytes is refused"
BIG=$(python3 -c "print('y' * 65537)")
printf 'COPY=$BIG\n' > "$TMP/bigvalue.env"
BIG=$BIG with_env "$TMP/bigvalue.env" true 2> "$TMP/err"; [ $? -eq 2 ] || fail "a value over 64 KiB is not 2"
grep -q 'COPY' "$TMP/err" || fail "the error does not name the variable: $(cat "$TMP/err")"
BIG=$(python3 -c "print('y' * 65536)")
got=$(BIG=$BIG with_env "$TMP/bigvalue.env" sh -c 'echo ${#COPY}')
[ "$got" = '65536' ] || fail "a value of 64 KiB is cut: $got"

# the command line: a program's arguments are 4095 bytes at most
with_env "$TMP/env" true "$(python3 -c "print('x' * 4100)")" 2>/dev/null; [ $? -eq 2 ] || fail "a command line over 4095 bytes is not 2"

# a command with no / is found in the PATH the file gives it
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "mine $*"\n' > "$TMP/bin/mine-for-test"
chmod +x "$TMP/bin/mine-for-test"
printf 'PATH=%s/bin:$PATH\n' "$TMP" > "$TMP/path.env"
got=$(with_env "$TMP/path.env" mine-for-test a b)
[ "$got" = 'mine a b' ] || fail "a command only the file's PATH has: $got"
with_env "$TMP/env" mine-for-test 2>/dev/null; [ $? -eq 127 ] || fail "found with the caller's PATH, which lacks it"
printf 'PATH=%s/bin\n' "$TMP" > "$TMP/only.env"
with_env "$TMP/only.env" sh -c 'true' 2>/dev/null; [ $? -eq 127 ] || fail "sh found outside the file's PATH"
got=$(PATH="$TMP/bin:$PATH" with_env "$TMP/env" mine-for-test c)
[ "$got" = 'mine c' ] || fail "the caller's PATH, the file setting none: $got"
got=$(cd "$TMP/bin" && printf 'PATH=:/nonexistent\n' > "$TMP/dot.path.env" && with_env "$TMP/dot.path.env" mine-for-test d)
[ "$got" = 'mine d' ] || fail "an empty PATH entry is the current directory: $got"

# 126 says why; a directory or a file with no execute bit is not a command
: > "$TMP/bin/not-executable"
mkdir -p "$TMP/bin/a-directory"
with_env "$TMP/path.env" not-executable 2> "$TMP/err"; [ $? -eq 126 ] || fail "no execute bit is not 126"
grep -q 'Permission denied' "$TMP/err" || fail "126 does not say why: $(cat "$TMP/err")"
with_env "$TMP/path.env" a-directory 2>/dev/null; [ $? -eq 126 ] || fail "a directory is not 126"
with_env "$TMP/env" "$TMP/bin/a-directory" 2> "$TMP/err"; [ $? -eq 126 ] || fail "running a directory by path is not 126"
grep -q 'cannot run' "$TMP/err" || fail "126 by path does not say so: $(cat "$TMP/err")"

# a directory and a file with no execute bit are passed over for a real
# command of the same name later in the PATH
mkdir -p "$TMP/skip/first/dd" "$TMP/skip/second"
printf '#!/bin/sh\necho "noexec second"\n' > "$TMP/skip/first/noexec"
chmod 644 "$TMP/skip/first/noexec"
printf '#!/bin/sh\necho "noexec second"\n' > "$TMP/skip/second/noexec"
printf '#!/bin/sh\necho "dd second"\n' > "$TMP/skip/second/dd"
chmod 755 "$TMP/skip/second/noexec" "$TMP/skip/second/dd"
printf 'PATH=%s/skip/first:%s/skip/second\n' "$TMP" "$TMP" > "$TMP/skip.env"
got=$(with_env "$TMP/skip.env" noexec)
[ "$got" = 'noexec second' ] || fail "a file with no execute bit was not passed over: $got"
got=$(with_env "$TMP/skip.env" dd)
[ "$got" = 'dd second' ] || fail "a directory was not passed over: $got"

# limits that exec would refuse late are refused at once
BIG=$(python3 -c "print('y' * 65536)")
python3 -c "import sys; sys.stdout.write(''.join('V%d=\$BIG\$BIG\$BIG\$BIG\$BIG\n' % i for i in range(1024)))" > "$TMP/expand.env"
BIG=$BIG slow 5 "$BATS" with-env "$TMP/expand.env" true; [ $? -eq 2 ] || fail "1024 large expansions are not refused at once"
BIG=$BIG with_env "$TMP/expand.env" true 2> "$TMP/err"
grep -q 'V1023\|V0' "$TMP/err" || fail "the error does not name the variable: $(cat "$TMP/err")"
printf 'TWO=$BIG$BIG\n' > "$TMP/two.env"
BIG=$BIG with_env "$TMP/two.env" true 2>/dev/null; [ $? -eq 2 ] || fail "an entry over 131071 bytes is not refused"
printf 'ONE=$BIG\nTWO=$BIG\n' > "$TMP/one.env"
got=$(BIG=$BIG with_env "$TMP/one.env" sh -c 'echo ${#ONE} ${#TWO}')
[ "$got" = '65536 65536' ] || fail "two values of 64 KiB: $got"

# the exact bounds: an entry is at most 131071 bytes (Linux's MAX_ARG_STRLEN
# less the NUL), and the entries together at most 524287 with a NUL after
# each (the process package's builder for the environment, 524288 bytes)
A=$(python3 -c "print('y' * 65534)")
export A
printf 'EE=${A}${A}\n' > "$TMP/entry-ok.env"
got=$(with_env "$TMP/entry-ok.env" sh -c 'echo $((${#EE} + 3))')
[ "$got" = '131071' ] || fail "an entry of 131071 bytes is not accepted: $got"
printf 'EEE=${A}${A}\n' > "$TMP/entry-over.env"
with_env "$TMP/entry-over.env" true 2> "$TMP/err"; [ $? -eq 2 ] || fail "an entry of 131072 bytes is not 2"
grep -q 'EEE' "$TMP/err" || fail "the error does not name the variable: $(cat "$TMP/err")"
printf 'Ea=${A}${A}\nEb=${A}${A}\nEc=${A}${A}\nF=${A}${A}\n' > "$TMP/total-ok.env"
got=$(with_env "$TMP/total-ok.env" sh -c 'echo ${#Ea} ${#F}')
[ "$got" = '131068 131068' ] || fail "entries together 524287 bytes are not accepted: $got"
printf 'Ea=${A}${A}\nEb=${A}${A}\nEc=${A}${A}\nFF=${A}${A}\n' > "$TMP/total-over.env"
with_env "$TMP/total-over.env" true 2> "$TMP/err"; [ $? -eq 2 ] || fail "entries together 524288 bytes are not 2 (and not a late 126)"
grep -q 'cannot be made' "$TMP/err" || fail "the error is not the 'cannot be made' one: $(cat "$TMP/err")"
grep -q 'value of Ea ' "$TMP/err" || fail "the error does not name the entry that crossed the limit: $(cat "$TMP/err")"
printf 'Ea=${A}${A}\nEb=${A}${A}\nEc=${A}${A}\nEd=${A}${A}\n' > "$TMP/four.env"
with_env "$TMP/four.env" true 2>/dev/null; [ $? -eq 2 ] || fail "four entries of 131071 bytes are not 2 (a late 126)"
# a literal tail after expansions counts too: 2 + 1 + 65534 + 65534 + 1 is
# 131072, one over the limit (with the fits check removed, exec refuses 126)
printf 'EX=${A}${A}x\n' > "$TMP/tail-over.env"
with_env "$TMP/tail-over.env" true 2> "$TMP/err"; [ $? -eq 2 ] || fail "an entry of 131072 bytes with a literal tail is not 2"
grep -q 'EX' "$TMP/err" || fail "the error does not name the variable: $(cat "$TMP/err")"
unset A

# a NUL byte in the file is a usage error that names its line
printf 'A=1\nB=2\0C=3\nD=4\n' > "$TMP/nul.env"
with_env "$TMP/nul.env" true 2> "$TMP/err"; [ $? -eq 2 ] || fail "a NUL in the file is not 2"
grep -q 'line 2' "$TMP/err" || fail "the error does not name the line: $(cat "$TMP/err")"
printf 'A=1\0B=2\nC=3' > "$TMP/nul1.env"
with_env "$TMP/nul1.env" sh -c 'echo "$B$C"' 2>/dev/null; [ $? -eq 2 ] || fail "a NUL on line 1 injects variables"

# the usage text lists with-env
"$BATS" --help | grep -q 'with-env <env-file> <command>' || fail "bats --help does not list with-env"
for shell in bash zsh fish; do
  "$BATS" completions $shell | grep -q 'with-env' || fail "$shell completions do not list with-env"
done


# standard input passes through, an empty argument stays
got=$(printf 'from stdin' | with_env "$TMP/env" cat)
[ "$got" = 'from stdin' ] || fail "stdin: $got"
got=$(with_env "$TMP/env" sh -c 'echo "$#"' sh '' '' x)
[ "$got" = '3' ] || fail "empty arguments: $got"

# a command a signal ended has status 1 (the process package's child_wait
# does not say which signal), and a signal to bats does not reach it (bats
# does not replace itself with the command): both are said in
# .claude/rules/with-env.md and
# are to change with bats-lang/process
with_env "$TMP/env" sh -c 'kill -KILL $$'; [ $? -eq 1 ] || fail "a command killed by a signal has a status other than 1"
rm -f "$TMP/child.pid"
"$BATS" with-env "$TMP/env" sh -c 'echo $$ > "$1"; exec sleep 60' sh "$TMP/child.pid" &
waiting=$!
for _ in $(seq 100); do [ -s "$TMP/child.pid" ] && break; sleep 0.1; done
[ -s "$TMP/child.pid" ] || fail "the command did not start"
kill -TERM "$waiting"
wait "$waiting" 2>/dev/null
if kill -0 "$(cat "$TMP/child.pid")" 2>/dev/null; then
  kill -KILL "$(cat "$TMP/child.pid")"
else
  fail "the signal reached the command: bats now replaces itself, so say it in .claude/rules/with-env.md and make this test expect it"
fi
echo "with-env: ok"
