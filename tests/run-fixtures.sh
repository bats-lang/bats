#!/bin/sh
# Runs every fixture group (tests/*/check.sh) and prints how long each group and each ok case took (bats-lang/bats#595, keyword: fixture-times).
# usage: tests/run-fixtures.sh <bats-binary> <repository-dir> [check.sh ...]
# Avenue exhausted for shell: bats has no clock, and the groups are shell scripts already.
set -u
bats=$1
repository=$2
shift 2
if [ $# -eq 0 ]; then
  set -- "$(dirname "$0")"/*/check.sh
fi

# fixture-times: a clock of this script (a duration from date, never a file's time), in milliseconds so a whole second is a floor
now_ms() {
  echo $(($(date +%s%N) / 1000000))
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
times=$work/times
: > "$times"

# fixture-times: each ok line of a group gets the whole seconds since the group's previous ok line, or its start, as the line passes
stamp_cases() {
  last=$(now_ms)
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      ok | "ok "*)
        at=$(now_ms)
        printf '%s in %s s\n' "$line" $(((at - last) / 1000))
        last=$at
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

# fixture-times: the summary is printed after the last group, the failed one included
summary() {
  echo "slowest groups:"
  sort -s -k1,1nr "$times" | head -n 10 | while read -r seconds name; do
    printf '%6s s  %s\n' "$seconds" "$name"
  done
  echo "total: $((($(now_ms) - started) / 1000)) s"
}

started=$(now_ms)
for group in "$@"; do
  name=$(basename "$(dirname "$group")")
  group_started=$(now_ms)
  { "$group" "$bats" "$repository"; echo $? > "$work/status"; } | stamp_cases
  status=$(cat "$work/status")
  seconds=$((($(now_ms) - group_started) / 1000))
  echo "$seconds $name" >> "$times"
  if [ "$status" -eq 0 ]; then
    echo "group $name: ok in $seconds s"
  else
    echo "group $name: FAILED with status $status in $seconds s"
    summary
    exit "$status"
  fi
done
summary
