#!/bin/sh
# scripts/check-pins.sh passes a pinned `uses:` and fails every way a pin
# moves or hides (bats-lang/bats#274). usage: tests/setup-action/pins-check.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sha=11d5960a326750d5838078e36cf38b85af677262
ok() { # <name> <uses line>
  printf 'jobs:\n  j:\n    steps:\n%s\n' "$2" > "$tmp/$1.yml"
  "$root/scripts/check-pins.sh" "$tmp/$1.yml" > "$tmp/out" 2>&1 || { echo "FAIL: $1 was refused"; cat "$tmp/out"; exit 1; }
  echo "ok   $1"
}
bad() { # <name> <uses line> <what the message says>
  printf 'jobs:\n  j:\n    steps:\n%s\n' "$2" > "$tmp/$1.yml"
  if "$root/scripts/check-pins.sh" "$tmp/$1.yml" > "$tmp/out" 2>&1; then echo "FAIL: $1 passed"; exit 1; fi
  grep -q "$3" "$tmp/out" || { echo "FAIL: $1 was refused for another reason"; cat "$tmp/out"; exit 1; }
  echo "ok   $1 (refused)"
}
ok pinned "      - uses: actions/checkout@$sha # v4"
ok pinned-subpath "      - uses: bats-lang/bats/.github/actions/setup@$sha # setup"
ok pinned-workflow "    uses: bats-lang/repository-prototype/.github/workflows/relock-pins.yml@$sha # main"
ok local "      - uses: ./.github/actions/setup"
ok quoted "      - uses: \"actions/checkout@$sha\" # v4"
bad tag "      - uses: actions/checkout@v4" "not pinned"
bad branch "      - uses: actions/checkout@main # main" "not pinned"
bad short "      - uses: actions/checkout@11d5960 # v4" "not pinned"
bad upper "      - uses: actions/checkout@11D5960A326750D5838078E36CF38B85AF677262 # v4" "not pinned"
bad no-ref "      - uses: actions/checkout # v4" "not pinned"
bad docker "      - uses: docker://alpine:3 # x" "not pinned"
bad no-comment "      - uses: actions/checkout@$sha" "no comment"
bad second "      - uses: ./local
      - uses: actions/setup-node@v4" "not pinned"
