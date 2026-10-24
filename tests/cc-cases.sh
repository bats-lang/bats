# The cases of the keys of objects (bats-lang/bats#477, build-freshness.md), sourced by
# tests/build-headers/check.sh and tests/build-toolchain-path/check.sh after they set BATS, REPO
# and TMP (keep-on-fail.sh) and define their case_<name> functions and ALL_CASES.
#
# A case builds a project of its own in $TMP/case-<name> and exits 1 with a FAIL line when what it
# asserts is not so. `check.sh <bats> <repository> <case>...` runs the named cases alone; with no
# case it runs all of them, reports every one that failed and exits 1 at the end.
# The stand-in clang (SHIM_* variables) notes each compile of a keyed object in $CC_LOG, runs
# $REAL_CLANG and plays one variation of clang's output, so a format change of clang is a case.
unset BATS_CACHE_DIR
REAL_CLANG=$(command -v clang)
export REAL_CLANG
SHIMDIR=$TMP/shim
mkdir -p "$SHIMDIR"
cat > "$SHIMDIR/clang" <<'EOF'
#!/bin/sh
# The stand-in clang of tests/cc-cases.sh
real=${REAL_CLANG:?}
pre=0
printrd=0
for a in "$@"; do
  case "$a" in -E) pre=1;; -print-resource-dir) printrd=1;; esac
done
case "$*" in
  *-o\ build/_bats_wasm_runtime*) ;;
  *-o\ build/_bats_native_runtime*) ;;
  *.bats_link_probe*) ;;
  *-c\ -o*) [ -z "${CC_LOG:-}" ] || echo "$*" >> "$CC_LOG";;
esac
rd=
case "$*" in
  *--target=wasm32*) rd=${SHIM_RD_WASM:-};;
  *) rd=${SHIM_RD_NATIVE:-};;
esac
n=$#
i=0
while [ "$i" -lt "$n" ]; do
  a=$1
  shift
  case "$a" in
    -P) [ -n "${SHIM_DROP_P:-}" ] || set -- "$@" "$a";;
    -H) [ -n "${SHIM_DROP_H:-}" ] || set -- "$@" "$a";;
    *) set -- "$@" "$a";;
  esac
  i=$((i + 1))
done
[ -z "$rd" ] || set -- "$@" -resource-dir "$rd"
[ -z "${SHIM_EXTRA_SYS:-}" ] || set -- "$@" -isystem "$SHIM_EXTRA_SYS"
if [ "$printrd" = 1 ] && [ -n "${SHIM_RD:-}" ]; then
  case "$SHIM_RD" in
    fail) echo "error: cannot print the resource directory" >&2; exit 1;;
    empty) echo; exit 0;;
    relative) echo lib/clang/18; exit 0;;
    slash) echo /; exit 0;;
    multi) "$real" "$@"; echo /second/line; exit 0;;
    trailing) printf '%s/\n' "$("$real" "$@")"; exit 0;;
    dotdot) printf '%s/../%s\n' "$("$real" "$@")" "$(basename "$("$real" "$@")")"; exit 0;;
  esac
fi
if [ "$pre" = 0 ] && [ -n "${SHIM_EDIT:-}" ] && [ ! -e "$SHIM_EDIT.edited" ]; then
  case "$*" in
    *-c\ -o\ build/src/bin/tool_dats.o*)
      "$real" "$@"
      rc=$?
      printf '/* edited while cc ran */\n' >> "$SHIM_EDIT"
      : > "$SHIM_EDIT.edited"
      exit $rc;;
  esac
fi
if [ "$pre" = 1 ]; then
  [ -z "${SHIM_STDERR_FIRST:-}" ] || printf '%b\n' "$SHIM_STDERR_FIRST" >&2
  errf=$(mktemp)
  "$real" "$@" 2> "$errf"
  rc=$?
  cat "$errf" >&2
  rm -f "$errf"
  [ -z "${SHIM_STDERR:-}" ] || printf '%b\n' "$SHIM_STDERR" >&2
  if [ -n "${SHIM_RENAME_MARKER:-}" ]; then
    prev=
    for a in "$@"; do
      if [ "$prev" = -o ] && [ -f "$a" ]; then
        awk '{ gsub(/__CLANG_REWRITTEN_INCLUDES/, "__CLANG_RENAMED_INCLUDES"); print }' "$a" \
          > "$a.tmp" && mv "$a.tmp" "$a"
      fi
      prev=$a
    done
  fi
  if [ -n "${SHIM_FAIL:-}" ]; then
    printf '%b\n' "$SHIM_FAIL" >&2
    exit 1
  fi
  exit $rc
fi
exec "$real" "$@"
EOF
chmod +x "$SHIMDIR/clang"

fail() { # <what> [file...]: a case failed
  echo "FAIL: $1"
  shift
  for f in "$@"; do [ ! -f "$f" ] || cat "$f"; done
  exit 1
}
runs() { grep -c -- "$1" "$CC_LOG" || true; }

new_case() { # <native|wasm> [suffix]: the project, its object and the headers' directories
  P=$CASE_DIR/p${2:-}
  mkdir -p "$P/src/bin"
  E1=$CASE_DIR/e1 E2=$CASE_DIR/e2 HDR=$CASE_DIR/h1 HDR2=$CASE_DIR/h2
  mkdir -p "$E1" "$E2" "$HDR" "$HDR2"
  printf '[package]\nname = "cc"\nkind = "bin"\nunsafe = true\n' > "$P/bats.toml"
  if [ "$1" = wasm ]; then
    SRC=$P/src/bin/web.bats OBJ=build/src/bin/web_dats.wasm.o PAT='bin/web_dats.wasm.o '
    TARGET='#target wasm binary'
  else
    SRC=$P/src/bin/tool.bats OBJ=build/src/bin/tool_dats.o PAT='bin/tool_dats.o '
    TARGET='#target native'
  fi
  : > "$CASE_DIR/extra.inc"
  : > "$CASE_DIR/extra.c"
}
mkhdr() { # <path> <name> <value>: a header with a macro and a function that names its file
  up=$(printf '%s' "$2" | tr 'a-z' 'A-Z')
  printf '#define H_%s %s\nstatic inline const char *h_%s_file (void) { return __FILE__; }\n' \
    "$up" "$3" "$2" > "$1"
}
standard_headers() {
  mkhdr "$HDR/h_angle.h" angle 1
  mkhdr "$HDR2/h_cpath.h" cpath 2
  mkhdr "$HDR/h_quoted.h" quoted 3
}
write_src() { # the project's source: three headers by three routes, and the extra lines
  {
    printf '%s\n\n$UNSAFE begin\n\n%%{\n' "$TARGET"
    printf '#include <h_angle.h>\n#include <h_cpath.h>\n#include "h_quoted.h"\n'
    cat "$CASE_DIR/extra.inc"
    printf 'const char *cc_angle (void) { return h_angle_file (); }\n'
    printf 'const char *cc_cpath (void) { return h_cpath_file (); }\n'
    printf 'const char *cc_quoted (void) { return h_quoted_file (); }\n'
    printf 'int cc_value (void) { return H_ANGLE + H_CPATH + H_QUOTED; }\n'
    cat "$CASE_DIR/extra.c"
    printf '%%}\n\nend\n\nimplement main0 () = ()\n'
  } > "$SRC"
}
set_env() { # the search path's environment of the standard routes
  C_INCLUDE_PATH=${1:-$E1:$HDR}
  CPATH=${2-$E2:$HDR2}
  export C_INCLUDE_PATH CPATH
}
build() { # <log> <nd|nr|w> [VAR=value...]: a build with the stand-in clang first on PATH
  l=$1
  m=$2
  shift 2
  case $m in
    nd) a="--only debug --only native";;
    nr) a="--only release --only native";;
    w) a="--only debug --only wasm";;
  esac
  (cd "$P" && env PATH="$SHIMDIR:$PATH" "$@" "$BATS" -v build $a --repository "$REPO" \
    > "$CASE_DIR/$l" 2>&1) || fail "build $m in $P" "$CASE_DIR/$l"
}
build_peak() { # <log> <nd|nr|w>: a build whose peak resident size (VmHWM, kB) is read into PEAK_KB
  l=$1
  m=$2
  case $m in
    nd) a="--only debug --only native";;
    nr) a="--only release --only native";;
    w) a="--only debug --only wasm";;
  esac
  (cd "$P" && exec env PATH="$SHIMDIR:$PATH" "$BATS" -v build $a --repository "$REPO" \
    > "$CASE_DIR/$l" 2>&1) &
  bpid=$!
  PEAK_KB=0
  while kill -0 "$bpid" 2> /dev/null; do
    v=$(awk '/^VmHWM:/ { print $2 }' "/proc/$bpid/status" 2> /dev/null)
    [ -z "$v" ] || PEAK_KB=$v
    sleep 0.02
  done
  wait "$bpid" || fail "build $m in $P" "$CASE_DIR/$l"
}
again() { # <log> <what>: the object was compiled once
  [ "$(runs "$PAT")" = 1 ] ||
    fail "$2 did not make the object again" "$CC_LOG" "$CASE_DIR/$1"
}
no_cc() { # <what>: nothing was compiled
  [ ! -s "$CC_LOG" ] || fail "$1 ran cc" "$CC_LOG"
}
differs() { # <before> <after> <what>
  ! cmp -s "$1" "$2" || fail "$3"
}
same() { # <before> <after> <what>
  cmp -s "$1" "$2" || fail "$3"
}
clean_rebuild() { # <log> <mode> [file of build/ to keep...]: the object a clean build writes
  l=$1
  m=$2
  shift 2
  for f in "$@"; do
    mkdir -p "$CASE_DIR/save/$(dirname "$f")"
    cp -p "$P/$f" "$CASE_DIR/save/$f"
  done
  rm -rf "$P/build"
  for f in "$@"; do
    mkdir -p "$P/$(dirname "$f")"
    cp -p "$CASE_DIR/save/$f" "$P/$f"
  done
  build "$l" "$m"
}

run_all() { # <case>...: run the named cases, or ALL_CASES
  failed=0
  names=${*:-$ALL_CASES}
  for name in $names; do
    fn=case_$(printf '%s' "$name" | tr - _)
    if ! command -v "$fn" > /dev/null 2>&1; then
      echo "no such case: $name"
      failed=1
      continue
    fi
    CASE_DIR=$TMP/case-$name
    rm -rf "$CASE_DIR"
    mkdir -p "$CASE_DIR"
    CC_LOG=$CASE_DIR/cc-runs
    export CC_LOG
    : > "$CC_LOG"
    started=$(date +%s)
    if (CASE_DIR=$CASE_DIR; "$fn") > "$CASE_DIR.log" 2>&1; then
      echo "ok   $name ($(($(date +%s) - started)) s)"
      [ -n "${KEEP_CASES:-}" ] || rm -rf "$CASE_DIR" "$CASE_DIR.log"
    else
      echo "FAIL $name"
      cat "$CASE_DIR.log"
      failed=1
    fi
  done
  [ -z "${KEEP_CASES:-}" ] || failed=1 # KEEP_CASES: keep the directories of the cases to read
  return $failed
}
