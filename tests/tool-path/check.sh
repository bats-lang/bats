#!/bin/sh
# bats runs its tools (clang, git, curl, ...) by name through PATH, as the
# Rust bats did; it used to run /usr/bin/clang and similar fixed paths,
# which are elsewhere on the BSDs and macOS. A wrapper clang first in
# PATH must be the one a build uses.
# usage: tests/tool-path/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL=$(command -v clang)
mkdir -p "$TMP/bin" "$TMP/p/src/bin"
printf '#!/bin/sh\necho called >> "%s/called"\nexec "%s" "$@"\n' "$TMP" "$REAL" > "$TMP/bin/clang"
chmod +x "$TMP/bin/clang"
printf '[package]\nname = "toolpath"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/p/src/bin/toolpath.bats"
cd "$TMP/p"
PATH="$TMP/bin:$PATH" "$BATS" build --only debug --only native > build.log 2>&1 || { echo "FAIL: build"; cat build.log; exit 1; }
[ -s "$TMP/called" ] || { echo "FAIL: the build did not run clang from PATH"; exit 1; }
echo "tool-path: ok"
