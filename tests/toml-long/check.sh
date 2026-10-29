#!/bin/sh
# A bats.toml of 20000 bytes whose trunk, version, name, kind and unsafe all come after
# byte 8192 (and after a long comment) is read whole by every reader: bats check, bats
# build, the docs that check writes, and bats upload, which zips the manifest whole
# (bats#430, keyword: manifest in .claude/rules/build-freshness.md). The readers used to
# take the first 8192 bytes, so the fields were unset and the archive's bats.toml was cut.
# Non-bats code of ours (quire#646): the avenue exhausted is a bats test, and none can
# run a built binary in a scratch repository with git until the driver of bats#284 exists
# (tests/toml-fields is bats but plays the build-freshness rows, not an upload).
# usage: tests/toml-long/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
. "$(dirname "$0")/../keep-on-fail.sh"
GIT_CEILING_DIRECTORIES=$TMP
export GIT_CEILING_DIRECTORIES

comment_line="# $(printf '%76s' '' | tr ' ' 'x')"   # 78 bytes and a newline
# make_manifest <file> <version line or empty> <kind>: [package], 9600 bytes of comment, the five
# fields, and a last comment line that makes the file 20000 bytes exactly
make_manifest() {
  { printf '[package]\n'
    i=0; while [ "$i" -lt 120 ]; do printf '%s\n' "$comment_line"; i=$((i + 1)); done
    printf 'trunk = "release"\n'
    if [ -n "$2" ]; then printf '%s\n' "$2"; fi
    printf 'name = "tomllong"\nkind = "%s"\nunsafe = true\n' "$3"
  } > "$1"
  size=$(wc -c < "$1" | tr -d ' ')
  rest=$((20000 - size))
  [ "$rest" -ge 2 ] || { echo "FAIL: the fields end at $size"; exit 1; }
  { printf '#'; printf '%*s' $((rest - 2)) '' | tr ' ' 'y'; printf '\n'; } >> "$1"
  [ "$(wc -c < "$1" | tr -d ' ')" -eq 20000 ] || { echo "FAIL: manifest is not 20000 bytes"; exit 1; }
  # every field is past byte 8192
  [ "$(head -c 8192 "$1" | grep -c -e 'trunk' -e 'name' -e 'kind' -e 'unsafe' -e 'version' || true)" -eq 0 ] ||
    { echo "FAIL: a field is in the first 8192 bytes"; exit 1; }
}
make_project() { # <dir> <version line or empty> [bin]
  mkdir -p "$1/src"
  make_manifest "$1/bats.toml" "$2" "${3:-lib}"
  # a C block: rejected unless the whole manifest said unsafe = true
  { printf '$UNSAFE begin\n\n%%{\nint tomllong_one(void) { return 1; }\n%%}\n\nend\n\n'
    printf '#pub fun f (): int\n\n/// Doc of f.\nimplement f () = 1\n'
  } > "$1/src/lib.bats"
  printf 'build/\ndist/\ndocs/\n' > "$1/.gitignore"
}

# C: a binary, for bats build: kind and name are read (a binary's name names the program).
make_project "$TMP/c" 'version = "1.2.3"' bin
mkdir -p "$TMP/c/src/bin"
{ printf '$UNSAFE begin\n\n%%{\nint tomllong_one(void) { return 1; }\n%%}\n\nend\n\n'
  printf 'implement main0 () = println! ("tomllong")\n'
} > "$TMP/c/src/bin/tomllong.bats"
rm "$TMP/c/src/lib.bats"
cd "$TMP/c"
"$BATS" build --repository "$REPO" > "$TMP/build.log" 2>&1 || { echo "FAIL: build"; cat "$TMP/build.log"; exit 1; }
[ "$(dist/debug/tomllong)" = "tomllong" ] || { echo "FAIL: build made no tomllong program"; ls dist/debug; exit 1; }

# A: version set. check, build, the docs and the upload read name, kind, unsafe and version.
make_project "$TMP/a" 'version = "1.2.3"'
cd "$TMP/a"
"$BATS" check --repository "$REPO" > "$TMP/check.log" 2>&1 || { echo "FAIL: check"; cat "$TMP/check.log"; exit 1; }
grep -q "generated docs (1 module(s))" "$TMP/check.log" || { echo "FAIL: check wrote no docs (kind or name not read)"; cat "$TMP/check.log"; exit 1; }
[ -f docs/index.md ] || { echo "FAIL: no docs/index.md"; exit 1; }
grep -q "tomllong" docs/index.md || { echo "FAIL: the docs do not carry the name"; cat docs/index.md; exit 1; }
git init -q -b main . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
mkdir -p "$TMP/repo"
"$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1 || { echo "FAIL: upload"; cat "$TMP/up.log"; exit 1; }
arc="$TMP/repo/tomllong/tomllong_1.2.3.bats"
[ -f "$arc" ] || { echo "FAIL: no tomllong_1.2.3.bats (name or version not read)"; ls -R "$TMP/repo"; exit 1; }
unzip -p "$arc" bats.toml > "$TMP/archived.toml"
cmp "$TMP/a/bats.toml" "$TMP/archived.toml" || { echo "FAIL: the archived bats.toml is not the source's"; exit 1; }

# B: no version, so the upload takes it from git, and the trunk is the manifest's "release":
# on that branch the version has no dev1, which it would have if the trunk were read as main.
make_project "$TMP/b" ''
cd "$TMP/b"
git init -q -b release . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
mkdir -p "$TMP/repo-b"
"$BATS" upload --repository "$TMP/repo-b" > "$TMP/up-b.log" 2>&1 || { echo "FAIL: upload without a version"; cat "$TMP/up-b.log"; exit 1; }
arc_b=$(ls "$TMP"/repo-b/tomllong/*.bats)
case "$arc_b" in
  *dev1.bats) echo "FAIL: $arc_b: the trunk was not read"; exit 1 ;;
esac
echo "toml-long: ok"
