#!/bin/sh
# manifest: which bats.toml fields reach build/, and add/remove on whole manifests; shell is a stopgap that bats#446 moves to bats
# usage: tests/toml-fields/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR

# patsopt-count: patsopt runs, not counting the entry's generated module that every build makes again
ran() { grep -a -- '+ patsopt' "$1" | grep -av '_bats_entry_' | grep -avc '(cached)' || true; }
build() { # <directory> <log file> [bats arguments]: -v build in <directory>, which must succeed
  directory=$1; log_file=$2; shift 2
  (cd "$directory" && "$BATS" -v build --only debug --only native "$@") > "$log_file" 2>&1 || { echo "FAIL: build in $directory"; cat "$log_file"; exit 1; }
}
program() { (cd "$1" && ./dist/debug/tf); }
# build-tree: the files of build/ with their digests, without records, stash, graph and objects (not the build's)
tree() { (cd "$1/build" && find . -type f ! -path './.bats_valid/*' ! -path './.stash/*' ! -name .bats_graph ! -name '*.o' | LC_ALL=C sort | while read -r file_name; do printf '%s %s\n' "$(cksum < "$file_name")" "$file_name"; done); }

module() { # <directory> <bats.toml text>: a binary of two modules
  rm -rf "$1"; mkdir -p "$1/src/bin"
  printf '%s' "$2" > "$1/bats.toml"
  printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\nimplement f () = 1\n' > "$1/src/m.bats"
  printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nimplement main0 () = println! (f ())\n' > "$1/src/bin/tf.bats"
}

# unchanged-fields: fields the build does not read leave a restored build/ whole and equal to a cold one
base='[package]
name = "tf"
kind = "bin"
'
unchanged() { # <case name> <second manifest>
  module "$TMP/first" "$base"
  build "$TMP/first" "$TMP/first.log"
  module "$TMP/restored" "$2"
  cp -R "$TMP/first/build" "$TMP/restored/build"
  build "$TMP/restored" "$TMP/restored.log"
  [ "$(ran "$TMP/restored.log")" = 0 ] || { echo "FAIL: $1: a restored build/ made $(ran "$TMP/restored.log") modules again"; cat "$TMP/restored.log"; exit 1; }
  if grep -aq '^bats: dropping build/' "$TMP/restored.log"; then echo "FAIL: $1: build/ was dropped"; cat "$TMP/restored.log"; exit 1; fi
  module "$TMP/cold" "$2"
  build "$TMP/cold" "$TMP/cold.log"
  tree "$TMP/restored" > "$TMP/restored.tree"; tree "$TMP/cold" > "$TMP/cold.tree"
  cmp -s "$TMP/restored.tree" "$TMP/cold.tree" || { echo "FAIL: $1: the restored build/ is not the cold build's"; diff "$TMP/restored.tree" "$TMP/cold.tree"; exit 1; }
  [ "$(program "$TMP/restored")" = 1 ] || { echo "FAIL: $1: the program"; exit 1; }
}
unchanged "name" '[package]
name = "another"
kind = "bin"
'
unchanged "version, trunk and ats2" '[package]
name = "tf"
kind = "bin"
version = "1.2.3"
trunk = "master"
ats2 = "x"
'
unchanged "tables nothing reads" '[package]
name = "tf"
kind = "bin"

[build]
opt = 3

[test]
timeout = 9
'
unchanged "unsafe = true with no unsafe block" '[package]
name = "tf"
kind = "bin"
unsafe = true
'

# kind: bats build refuses a library whatever build/ holds, and a bin again builds from the same build/
module "$TMP/kind_project" "$base"
build "$TMP/kind_project" "$TMP/kind_first.log"
printf '[package]\nname = "tf"\nkind = "lib"\n' > "$TMP/kind_project/bats.toml"
exit_code=0; (cd "$TMP/kind_project" && "$BATS" build --only debug --only native) > "$TMP/kind_lib.out" 2> "$TMP/kind_lib.err" || exit_code=$?
[ "$exit_code" = 1 ] && [ "$(cat "$TMP/kind_lib.err")" = "error: 'bats build' is only for binary packages (kind = \"bin\")" ] || { echo "FAIL: kind = lib built (exit code $exit_code)"; cat "$TMP/kind_lib.err"; exit 1; }
printf '%s' "$base" > "$TMP/kind_project/bats.toml"
build "$TMP/kind_project" "$TMP/kind_again.log"
[ "$(ran "$TMP/kind_again.log")" = 0 ] || { echo "FAIL: kind back to bin made modules again"; cat "$TMP/kind_again.log"; exit 1; }

# unsafe: the field the emitted modules depend on; false over a restored build/ is an error, true builds
unsafe_module() { # <dir> <bats.toml text>
  module "$1" "$2"
  printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\n$UNSAFE begin\n%%{\nstatic int unused_helper (void) { return 3; }\n%%}\nend\n\nimplement f () = 1\n' > "$1/src/m.bats"
}
yes_unsafe='[package]
name = "tf"
kind = "bin"
unsafe = true
'
unsafe_module "$TMP/unsafe_project" "$yes_unsafe"
build "$TMP/unsafe_project" "$TMP/unsafe_first.log"
printf '[package]\nname = "tf"\nkind = "bin"\nunsafe = false\n' > "$TMP/unsafe_project/bats.toml"
rm -f "$TMP/unsafe_project/dist/debug/tf"
exit_code=0; (cd "$TMP/unsafe_project" && "$BATS" build --only debug --only native) > "$TMP/unsafe_false.out" 2> "$TMP/unsafe_false.err" || exit_code=$?
[ "$exit_code" = 1 ] && grep -aq '^error: error: .UNSAFE requires .unsafe = true. in bats.toml' "$TMP/unsafe_false.err" && [ ! -e "$TMP/unsafe_project/dist/debug/tf" ] || { echo "FAIL: unsafe = false over a restored build/ (exit code $exit_code)"; cat "$TMP/unsafe_false.err"; exit 1; }
printf '%s' "$yes_unsafe" > "$TMP/unsafe_project/bats.toml"
build "$TMP/unsafe_project" "$TMP/unsafe_again.log"
[ "$(program "$TMP/unsafe_project")" = 1 ] || { echo "FAIL: unsafe again: the program"; exit 1; }

# a manifest over 8192 bytes: emission reads `unsafe = true` as validation does
{ for line_number in $(seq 1 100); do printf '# a line of padding that makes the manifest longer than the buffer it was once read in\n'; done; printf '%s' "$yes_unsafe"; } > "$TMP/large_manifest.toml"
[ "$(wc -c < "$TMP/large_manifest.toml")" -gt 8192 ] || { echo "FAIL: the manifest is not large"; exit 1; }
unsafe_module "$TMP/large_project" "$(cat "$TMP/large_manifest.toml")"
build "$TMP/large_project" "$TMP/large_manifest.log"
[ "$(program "$TMP/large_project")" = 1 ] || { echo "FAIL: large manifest: the program"; exit 1; }

# large-library: a manifest over 8192 bytes with [package] after the padding is read whole by upload and the docs
mkdir -p "$TMP/large_library/src" "$TMP/large_repository"
{ for line_number in $(seq 1 100); do printf '# a line of padding that makes the manifest longer than the buffer it was once read in\n'; done; printf '[package]\nname = "tflarge"\nkind = "lib"\n'; } > "$TMP/large_library/bats.toml"
[ "$(wc -c < "$TMP/large_library/bats.toml")" -gt 8192 ] || { echo "FAIL: the library manifest is not large"; exit 1; }
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/large_library/src/lib.bats"
printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/large_library/.gitignore"
(cd "$TMP/large_library" && git init -q -b main . && git add -A &&
 git -c user.name=t -c user.email=t@t commit -q -m large &&
 "$BATS" upload --repository "$TMP/large_repository" > "$TMP/large_upload.log" 2>&1) || { echo "FAIL: upload of a large manifest"; cat "$TMP/large_upload.log"; exit 1; }
archive=$(ls "$TMP"/large_repository/tflarge/tflarge_*.bats)
unzip -p "$archive" bats.toml > "$TMP/archived.toml"
grep -aq '^name = "tflarge"$' "$TMP/archived.toml" && grep -aq '^version = "' "$TMP/archived.toml" || { echo "FAIL: the archived manifest lacks the name or the version"; exit 1; }
[ "$(wc -c < "$TMP/archived.toml")" -gt "$(wc -c < "$TMP/large_library/bats.toml")" ] || { echo "FAIL: the archived manifest is cut"; exit 1; }
grep -aq '^# a line of padding' "$TMP/archived.toml" || { echo "FAIL: the archived manifest lost its first lines"; exit 1; }
(cd "$TMP/large_library" && "$BATS" check --repository "$TMP/large_repository" > "$TMP/large_check.log" 2>&1) || { echo "FAIL: check of a large library manifest"; cat "$TMP/large_check.log"; exit 1; }
grep -aq '^# tflarge$' "$TMP/large_library/docs/index.md" || { echo "FAIL: the docs lack the package name"; exit 1; }

# dependencies: a constraint reaches build/ through the version it picks, a path dependency through its directory
mkdir -p "$TMP/repo"
publish() { # <name> <commit date> <value>: a library whose f is value
  rm -rf "$TMP/published"; mkdir -p "$TMP/published/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$TMP/published/bats.toml"
  printf '#pub fun f (): int\n\nimplement f () = %s\n' "$3" > "$TMP/published/src/lib.bats"
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/published/.gitignore"
  (cd "$TMP/published" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/upload.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/upload.log"; exit 1; }
}
publish tfdep "2026-01-03T00:00:03Z" 1
publish tfdep "2026-01-04T00:00:04Z" 2
dependent() { # <dir> <[dependencies] value>
  rm -rf "$1/src"; mkdir -p "$1/src/bin"
  printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = %s\n' "$2" > "$1/bats.toml"
  printf '#use tfdep as D\n\nimplement main0 () = println! ($D.f ())\n' > "$1/src/bin/tf.bats"
}
# lock-constraint: a constraint ruling out the locked version is an error, and after the relock build/ is made again
mkdir -p "$TMP/dependent"
dependent "$TMP/dependent" '""'
(cd "$TMP/dependent" && "$BATS" lock --repository "$TMP/repo") > "$TMP/dependent_lock.log" 2>&1 || { echo "FAIL: lock"; cat "$TMP/dependent_lock.log"; exit 1; }
build "$TMP/dependent" "$TMP/dependent_first.log" --repository "$TMP/repo"
[ "$(program "$TMP/dependent")" = 2 ] || { echo "FAIL: constraint none: the newest"; exit 1; }
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = "!= 2026.1.4.4"\n' > "$TMP/dependent/bats.toml"
exit_code=0; (cd "$TMP/dependent" && "$BATS" build --only debug --only native --repository "$TMP/repo") > "$TMP/dependent_ruled_out.out" 2> "$TMP/dependent_ruled_out.err" || exit_code=$?
[ "$exit_code" = 1 ] && grep -aq 'which does not meet' "$TMP/dependent_ruled_out.err" || { echo "FAIL: a constraint that rules out the locked version (exit code $exit_code)"; cat "$TMP/dependent_ruled_out.err"; exit 1; }
(cd "$TMP/dependent" && "$BATS" lock --repository "$TMP/repo") > "$TMP/dependent_relock.log" 2>&1 || { echo "FAIL: relock"; cat "$TMP/dependent_relock.log"; exit 1; }
build "$TMP/dependent" "$TMP/dependent_not_newest.log" --repository "$TMP/repo"
[ "$(program "$TMP/dependent")" = 1 ] || { echo "FAIL: constraint != the newest: the program"; cat "$TMP/dependent_not_newest.log"; exit 1; }
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = ""\n' > "$TMP/dependent/bats.toml"
(cd "$TMP/dependent" && "$BATS" lock --repository "$TMP/repo") > "$TMP/dependent_relock_again.log" 2>&1 || { echo "FAIL: relock again"; cat "$TMP/dependent_relock_again.log"; exit 1; }
build "$TMP/dependent" "$TMP/dependent_dropped.log" --repository "$TMP/repo"
[ "$(program "$TMP/dependent")" = 2 ] || { echo "FAIL: constraint dropped: the program"; cat "$TMP/dependent_dropped.log"; exit 1; }

mkdir -p "$TMP/path_dependency/one/src" "$TMP/path_dependency/two/src" "$TMP/path_dependency/app/src/bin"
for library in one two; do printf '[package]\nname = "tfdep"\nkind = "lib"\n' > "$TMP/path_dependency/$library/bats.toml"; done
printf '#pub fun f (): int\n\nimplement f () = 7\n' > "$TMP/path_dependency/one/src/lib.bats"
printf '#pub fun f (): int\n\nimplement f () = 8\n' > "$TMP/path_dependency/two/src/lib.bats"
printf '#use tfdep as D\n\nimplement main0 () = println! ($D.f ())\n' > "$TMP/path_dependency/app/src/bin/tf.bats"
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = { path = "../one" }\n' > "$TMP/path_dependency/app/bats.toml"
build "$TMP/path_dependency/app" "$TMP/path_dependency_first.log"
[ "$(program "$TMP/path_dependency/app")" = 7 ] || { echo "FAIL: path dependency one"; exit 1; }
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = { path = "../two" }\n' > "$TMP/path_dependency/app/bats.toml"
build "$TMP/path_dependency/app" "$TMP/path_dependency2.log"
[ "$(program "$TMP/path_dependency/app")" = 8 ] || { echo "FAIL: path dependency two: the program"; cat "$TMP/path_dependency2.log"; exit 1; }
# toml-limit: a manifest of exactly 65536 bytes is read to its end, one byte more is refused, never parsed cut
filler() { yes '#' | head -c "$1"; }
filler_manifest() { # <bytes in all>: comment lines, then yes_unsafe, then blank lines to fill
  tail_length=$(printf '%s' "$yes_unsafe" | wc -c)
  { filler $(( ($1 - tail_length) / 2 * 2 )); printf '%s' "$yes_unsafe"; [ $(( ($1 - tail_length) % 2 )) = 0 ] || printf '\n'; }
}
unsafe_module "$TMP/limit_project" "$yes_unsafe"
filler_manifest 65536 > "$TMP/limit_project/bats.toml"
[ "$(wc -c < "$TMP/limit_project/bats.toml")" = 65536 ] || { echo "FAIL: the manifest at the limit is not 65536 bytes"; exit 1; }
build "$TMP/limit_project" "$TMP/limit.log"
[ "$(program "$TMP/limit_project")" = 1 ] || { echo "FAIL: manifest of 65536 bytes: the program"; exit 1; }
filler_manifest 65537 > "$TMP/limit_project/bats.toml"
[ "$(wc -c < "$TMP/limit_project/bats.toml")" = 65537 ] || { echo "FAIL: the manifest over the limit is not 65537 bytes"; exit 1; }
rm -rf "$TMP/limit_project/build" "$TMP/limit_project/dist"
exit_code=0; (cd "$TMP/limit_project" && "$BATS" build --only debug --only native) > "$TMP/limit_over.out" 2> "$TMP/limit_over.err" || exit_code=$?
[ "$exit_code" = 1 ] && grep -aq "bats.toml" "$TMP/limit_over.err" && [ ! -e "$TMP/limit_project/dist/debug/tf" ] || { echo "FAIL: a manifest of 65537 bytes (exit code $exit_code)"; cat "$TMP/limit_over.err"; exit 1; }

# add: the manifest is kept whole (more than 4096 bytes before the line)
{ for line_number in $(seq 1 100); do printf '# a line of padding that makes the manifest longer than the buffer it was once read in\n'; done; printf '%s' "$base"; printf '\n[dependencies]\n"existing" = ""\n'; } > "$TMP/add_before.toml"
[ "$(wc -c < "$TMP/add_before.toml")" -gt 8192 ] || { echo "FAIL: the manifest of bats add is not large"; exit 1; }
module "$TMP/add_project" "$base"
cp "$TMP/add_before.toml" "$TMP/add_project/bats.toml"
(cd "$TMP/add_project" && "$BATS" add added) > "$TMP/add.log" 2>&1 || { echo "FAIL: bats add"; cat "$TMP/add.log"; exit 1; }
grep -aq "^added 'added' to \[dependencies\]$" "$TMP/add.log" || { echo "FAIL: bats add said"; cat "$TMP/add.log"; exit 1; }
{ cat "$TMP/add_before.toml"; printf '"added" = ""\n'; } > "$TMP/add_expected.toml"
cmp -s "$TMP/add_expected.toml" "$TMP/add_project/bats.toml" || { echo "FAIL: bats add changed more than the one line ($(wc -c < "$TMP/add_project/bats.toml") bytes, $(wc -c < "$TMP/add_expected.toml") expected)"; exit 1; }
# remove: the manifest is kept whole, only the lines naming the package go
module "$TMP/remove_project" "$base"
{ cat "$TMP/add_before.toml"; printf '"added" = ""\n"added-too" = ""\n'; } > "$TMP/remove_before.toml"
cp "$TMP/remove_before.toml" "$TMP/remove_project/bats.toml"
(cd "$TMP/remove_project" && "$BATS" remove added) > "$TMP/remove.log" 2>&1 || { echo "FAIL: bats remove"; cat "$TMP/remove.log"; exit 1; }
grep -aq "^removed 'added' from \[dependencies\]$" "$TMP/remove.log" || { echo "FAIL: bats remove said"; cat "$TMP/remove.log"; exit 1; }
{ cat "$TMP/add_before.toml"; printf '"added-too" = ""\n'; } > "$TMP/remove_expected.toml"
cmp -s "$TMP/remove_expected.toml" "$TMP/remove_project/bats.toml" || { echo "FAIL: bats remove changed more than the one line"; exit 1; }
(cd "$TMP/remove_project" && "$BATS" remove absent) > "$TMP/remove_absent.log" 2>&1 || true
grep -aq "^error: package 'absent' not found in \[dependencies\]$" "$TMP/remove_absent.log" || { echo "FAIL: bats remove of an absent package said"; cat "$TMP/remove_absent.log"; exit 1; }
cmp -s "$TMP/remove_expected.toml" "$TMP/remove_project/bats.toml" || { echo "FAIL: bats remove of an absent package changed the manifest"; exit 1; }
# remove-cases: no final newline, a second table, an empty file, over 65536 bytes, each compared with cmp
remove_case() { # <name> <package> <before file> <expected file>
  module "$TMP/remove_$1" "$base"
  cp "$3" "$TMP/remove_$1/bats.toml"
  (cd "$TMP/remove_$1" && "$BATS" remove "$2") > "$TMP/remove_$1.log" 2>&1 || true
  cmp -s "$4" "$TMP/remove_$1/bats.toml" || { echo "FAIL: bats remove ($1): $(wc -c < "$TMP/remove_$1/bats.toml") bytes, $(wc -c < "$4") expected"; cat "$TMP/remove_$1.log"; exit 1; }
}
printf '[dependencies]\n"other" = ""\n"added" = ""' > "$TMP/nonl_before.toml"
printf '[dependencies]\n"other" = ""\n' > "$TMP/nonl_expected.toml"
remove_case no_newline added "$TMP/nonl_before.toml" "$TMP/nonl_expected.toml"
printf '[dependencies]\n"other" = ""\n\n[dev-dependencies]\n"added" = ""\n"last" = ""\n' > "$TMP/table_before.toml"
printf '[dependencies]\n"other" = ""\n\n[dev-dependencies]\n"last" = ""\n' > "$TMP/table_expected.toml"
remove_case second_table added "$TMP/table_before.toml" "$TMP/table_expected.toml"
: > "$TMP/empty_before.toml"
remove_case empty added "$TMP/empty_before.toml" "$TMP/empty_before.toml"
grep -aq "^error: package 'added' not found in \[dependencies\]$" "$TMP/remove_empty.log" || { echo "FAIL: bats remove on an empty file said"; cat "$TMP/remove_empty.log"; exit 1; }
{ filler 70000; printf '"other" = ""\n"added" = ""\n'; } > "$TMP/big_before.toml"
{ filler 70000; printf '"other" = ""\n'; } > "$TMP/big_expected.toml"
remove_case over_limit added "$TMP/big_before.toml" "$TMP/big_expected.toml"
grep -aq "^removed 'added' from \[dependencies\]$" "$TMP/remove_over_limit.log" || { echo "FAIL: bats remove over 65536 bytes said"; cat "$TMP/remove_over_limit.log"; exit 1; }
# remove-lookalikes: a commented "added", a string value holding "added", an indented "added" stay, only the real line goes (bats#445)
printf '[dependencies]\n# "added" = ""\n"note" = "added"\n  "added" = ""\n"added" = ""\n"last" = ""\n' > "$TMP/lookalike_before.toml"
printf '[dependencies]\n# "added" = ""\n"note" = "added"\n  "added" = ""\n"last" = ""\n' > "$TMP/lookalike_expected.toml"
remove_case lookalikes added "$TMP/lookalike_before.toml" "$TMP/lookalike_expected.toml"
grep -aq "^removed 'added' from \[dependencies\]$" "$TMP/remove_lookalikes.log" || { echo "FAIL: bats remove among look-alikes said"; cat "$TMP/remove_lookalikes.log"; exit 1; }
(cd "$TMP/remove_lookalikes" && "$BATS" remove added) > "$TMP/remove_lookalikes_again.log" 2>&1 || true
grep -aq "^error: package 'added' not found in \[dependencies\]$" "$TMP/remove_lookalikes_again.log" || { echo "FAIL: bats remove of a name left only in look-alikes said"; cat "$TMP/remove_lookalikes_again.log"; exit 1; }
cmp -s "$TMP/lookalike_expected.toml" "$TMP/remove_lookalikes/bats.toml" || { echo "FAIL: bats remove of a name left only in look-alikes changed the manifest"; exit 1; }
echo "toml-fields: ok"
