#!/bin/sh
# bats upload writes docs/ before packaging and puts it in the archive,
# as the Rust bats does (build::upload, lock::upload). It used to write
# docs/ only after zipping bats.toml and src/.
# usage: tests/upload-docs/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "updocs"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '/// One.\n#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
printf 'docs/\n' > "$TMP/lib/.gitignore"
cd "$TMP/lib"
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
"$BATS" upload --repository "$TMP/repo" > up.log 2>&1 || { echo "FAIL: upload"; cat up.log; exit 1; }
mkdir "$TMP/x" && cd "$TMP/x" && unzip -q "$TMP"/repo/updocs/*.bats
[ -f docs/index.md ] && [ -f docs/lib.md ] || { echo "FAIL: the archive has no docs/"; ls -R; exit 1; }
printf '# lib\n\n### `fun f (): int`\n\nOne.\n' | diff - docs/lib.md || { echo "FAIL: docs/lib.md"; exit 1; }
echo "upload-docs: ok"
