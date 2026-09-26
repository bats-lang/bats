#!/bin/sh
# The tools bats runs (clang, patsopt, git, ...) get the user's
# environment, as with the Rust bats's Command; they used to get only
# PATH=/usr/bin:/usr/local/bin:/bin (and patsopt only PATSHOME). A
# wrapper clang first in PATH records a variable set for bats build.
# usage: tests/tool-env/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL=$(command -v clang)
mkdir -p "$TMP/bin" "$TMP/p/src/bin"
printf '#!/bin/sh\necho "probe=$BATS_ENV_PROBE" >> "%s/seen"\nexec "%s" "$@"\n' "$TMP" "$REAL" > "$TMP/bin/clang"
chmod +x "$TMP/bin/clang"
printf '[package]\nname = "toolenv"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/p/src/bin/toolenv.bats"
cd "$TMP/p"
BATS_ENV_PROBE=from-user PATH="$TMP/bin:$PATH" "$BATS" build --only debug --only native > build.log 2>&1 || { echo "FAIL: build"; cat build.log; exit 1; }
grep -q "probe=from-user" "$TMP/seen" || { echo "FAIL: clang did not get the user's environment"; cat "$TMP/seen"; exit 1; }
echo "tool-env: ok"
