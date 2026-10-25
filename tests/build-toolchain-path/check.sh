#!/bin/sh
# An object's key is the same wherever the toolchain is (bats-lang/bats#477, build-freshness.md):
# the ATS2 home and the C compiler's resource directory are named by a placeholder in the list of
# the headers clang entered, so a build/ made where they are in one place keeps its objects when
# they are in another (the same files), the way the stamp keeps it: moved as a whole or one at a
# time, nested in each other, reached through a symlink, the object after the move is byte for
# byte the object before it. A header found at another path in any other directory (a shadow with
# other bytes or the same, in a toolchain directory too) makes the object again and it is the
# object a clean build writes. The control is the same move with a stand-in clang that drops -P,
# whose move makes the object again.
# usage: tests/build-toolchain-path/check.sh <bats-binary> <repository-dir> [case...]
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
shift 2
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../ats2-marker.sh"
. "$(dirname "$0")/../cc-cases.sh"
# The compiler's own copy is for Linux, where the resource directory is found beside the
# binary (<bin>/../lib/clang/<version>); the macOS branch is not run
[ "$(uname -s)" = Linux ] || { echo "build-toolchain-path: skipped (not Linux)"; exit 0; }
START_HOME=$HOME
make_ats2() { # <home>: a copy of the ATS2 home of this machine
  mkdir -p "$1/.bats/ats2"
  for d in bin prelude libats share ccomp; do
    cp -R "$START_HOME/.bats/ats2/$d" "$1/.bats/ats2/"
  done
  ats2_marker "$1"
}
REAL_BIN=$(readlink -f "$(command -v clang)")
LLVM_LIB=$(cd "$(dirname "$REAL_BIN")/../lib" && pwd)
RESOURCE=$(clang -print-resource-dir)
RES_NAME=$(basename "$RESOURCE")
make_clang() { # <dir>: the compiler's binary and resource directory, the libraries linked
  mkdir -p "$1/bin" "$1/lib/clang"
  cp "$REAL_BIN" "$1/bin/clang"
  for f in "$LLVM_LIB"/lib*.so*; do ln -s "$f" "$1/lib/$(basename "$f")"; done
  cp -R "$RESOURCE" "$1/lib/clang/$RES_NAME"
  "$1/bin/clang" -print-resource-dir | grep -q "^$1/" ||
    fail "the copy of clang does not use its own resource directory"
}
use() { # <home> <llvm>: the toolchain the next builds use
  HOME=$1
  REAL_CLANG=$2/bin/clang
  export HOME REAL_CLANG
}
kept() { # <log> <what>: no object compiled and build/ not dropped
  no_cc "$2"
  ! grep -aq '^bats: dropping build/' "$CASE_DIR/$1" || fail "$2 dropped build/" "$CASE_DIR/$1"
}
tb_case() { # <native|wasm>: a project with the standard headers and a toolchain in a/
  new_case "$1"
  standard_headers
  write_src
  set_env
  A=$CASE_DIR/a B=$CASE_DIR/b
  mkdir -p "$B"
  make_ats2 "$A/home"
  make_clang "$A/llvm"
  use "$A/home" "$A/llvm"
}
move_case() { # <mode> <home|llvm|both>: the toolchain, or a part of it, moved to other directories
  case $1 in w) tb_case wasm;; *) tb_case native;; esac
  build cold.log "$1"
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  case $2 in
    home|both) mv "$A/home" "$B/home";;
  esac
  case $2 in
    llvm|both) mv "$A/llvm" "$B/llvm";;
  esac
  [ -d "$B/home" ] && h=$B/home || h=$A/home
  [ -d "$B/llvm" ] && v=$B/llvm || v=$A/llvm
  use "$h" "$v"
  : > "$CC_LOG"
  build moved.log "$1"
  kept moved.log "a build with the toolchain ($2) in other directories"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the toolchain ($2) moved"
}
for m in nd nr w; do
  for part in home llvm both; do
    eval "case_move_${part}_${m}() { move_case $m $part; }"
  done
done
ALL_CASES="move-both-nd move-both-nr move-both-w move-home-nd move-home-nr move-home-w
move-llvm-nd move-llvm-nr move-llvm-w"

case_nested_resource_under_home() { # the compiler is inside the ATS2 home; it moves alone
  tb_case native
  make_clang "$A/home/.bats/ats2/cc"
  use "$A/home" "$A/home/.bats/ats2/cc"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$A/home/.bats/ats2/cc" "$B/llvm"
  use "$A/home" "$B/llvm"
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "a compiler moved out of the ATS2 home"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the compiler moved"
}
case_nested_home_under_resource() { # the ATS2 home is inside the compiler's resource directory
  tb_case native
  inner=$A/llvm/lib/clang/$RES_NAME/inner
  make_ats2 "$inner"
  use "$inner" "$A/llvm"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$inner" "$B/home"
  use "$B/home" "$A/llvm"
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "an ATS2 home moved out of the resource directory"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the ATS2 home moved"
}
case_sibling_root() { # a user directory named like the ATS2 home plus a letter, and one under it
  tb_case native
  ph=$A/home/.bats/ats2
  mkdir -p "${ph}x"
  mkhdr "${ph}x/h_sib.h" sib 12
  printf '#include <h_sib.h>\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_sib (void) { return h_sib_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env "$ph/x:${ph}x:$E1:$HDR"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  # the ATS2 home moves alone (its own directory, marker inside): the sibling
  # directory is in no root, and stays where it is
  mkdir -p "$B/home/.bats"
  mv "$ph" "$B/home/.bats/ats2"
  use "$B/home" "$A/llvm"
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "a build with the ATS2 home moved, a sibling directory named like it left"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the ATS2 home moved"
  mkdir -p "$ph/x"
  cp "${ph}x/h_sib.h" "$ph/x/h_sib.h"
  : > "$CC_LOG"
  build sib.log nd
  again sib.log "a same-bytes header under the ATS2 home, the first copy beside its name"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header at the path it had before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
case_kind_letter() { # a relative directory whose spelling equals the rest of a path under a root
  tb_case native
  printf '#include <stddef.h>\n' > "$CASE_DIR/extra.inc"
  printf 'size_t cc_size (void) { return sizeof (size_t); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env "include:$E1:$HDR"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mkdir -p "$P/include"
  cp "$A/llvm/lib/clang/$RES_NAME/include/__stddef_size_t.h" "$P/include/__stddef_size_t.h"
  : > "$CC_LOG"
  build kind.log nd
  again kind.log "a relative include/__stddef_size_t.h that takes the compiler's"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header at the path it had before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
case_home_symlink() { # the ATS2 home reached through a link, retargeted to the moved copy
  tb_case native
  LNK=$CASE_DIR/homelink
  ln -s "$A/home" "$LNK"
  use "$LNK" "$A/llvm"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$A/home" "$B/home"
  ln -sfn "$B/home" "$LNK"
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "a build with the ATS2 home behind a retargeted link"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the link was retargeted"
}
case_llvm_symlink() { # the compiler reached through a link, retargeted to the moved copy
  tb_case native
  LNK=$CASE_DIR/llvmlink
  ln -s "$A/llvm" "$LNK"
  use "$A/home" "$LNK"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$A/llvm" "$B/llvm"
  ln -sfn "$B/llvm" "$LNK"
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "a build with the compiler behind a retargeted link"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the link was retargeted"
}
case_root_trailing_slash() { # the resource directory printed with a trailing slash, moved
  tb_case native
  SHIM_RD=trailing
  export SHIM_RD
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$A/llvm" "$B/llvm"
  use "$A/home" "$B/llvm"
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "a compiler moved, its resource directory printed with a trailing slash"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when the compiler moved"
}
case_target_differs() { # a native and a wasm compiler with a resource directory each
  tb_case native
  RDN=$CASE_DIR/rdn RDW=$CASE_DIR/rdw
  cp -R "$A/llvm/lib/clang/$RES_NAME" "$RDN"
  cp -R "$A/llvm/lib/clang/$RES_NAME" "$RDW"
  SHIM_RD_NATIVE=$RDN SHIM_RD_WASM=$RDW
  export SHIM_RD_NATIVE SHIM_RD_WASM
  PN=$P
  ON=$OBJ
  printf '#include <stddef.h>\n' > "$CASE_DIR/extra.inc"
  printf 'size_t cc_size (void) { return sizeof (size_t); }\n' > "$CASE_DIR/extra.c"
  write_src
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.n.o"
  new_case wasm w
  standard_headers
  printf '#include <stddef.h>\n' > "$CASE_DIR/extra.inc"
  printf 'size_t cc_size (void) { return sizeof (size_t); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env
  build coldw.log w
  cp "$P/$OBJ" "$CASE_DIR/before.w.o"
  mv "$RDN" "$CASE_DIR/rdn2"
  mv "$RDW" "$CASE_DIR/rdw2"
  SHIM_RD_NATIVE=$CASE_DIR/rdn2 SHIM_RD_WASM=$CASE_DIR/rdw2
  export SHIM_RD_NATIVE SHIM_RD_WASM
  : > "$CC_LOG"
  build movedw.log w
  kept movedw.log "a wasm build with its resource directory moved"
  same "$CASE_DIR/before.w.o" "$P/$OBJ" "the wasm object changed when its resource directory moved"
  P=$PN
  OBJ=$ON
  PAT='bin/tool_dats.o '
  build moved.log nd
  kept moved.log "a native build with its resource directory moved"
  same "$CASE_DIR/before.n.o" "$P/$OBJ" "the native object changed with its resource directory"
}
case_shape_empty() { # the search list gains a directory that holds nothing
  tb_case native
  X=$CASE_DIR/extra-sys
  SHIM_EXTRA_SYS=$X
  export SHIM_EXTRA_SYS
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mkdir -p "$X"
  : > "$CC_LOG"
  build shape.log nd
  kept shape.log "a build whose search list gained an empty directory"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed with an empty directory"
}
case_shape_lost() { # the search list loses a directory that held nothing
  tb_case native
  X=$CASE_DIR/extra-sys
  mkdir -p "$X"
  SHIM_EXTRA_SYS=$X
  export SHIM_EXTRA_SYS
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  rmdir "$X"
  : > "$CC_LOG"
  build shape.log nd
  kept shape.log "a build whose search list lost an empty directory"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed with the directory gone"
}
case_shape_header() { # the search list gains a directory that holds a same-bytes header
  tb_case native
  X=$CASE_DIR/extra-sys
  SHIM_EXTRA_SYS=$X
  export SHIM_EXTRA_SYS
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mkdir -p "$X"
  cp "$HDR/h_angle.h" "$X/h_angle.h"
  : > "$CC_LOG"
  build shape.log nd
  again shape.log "a build whose search list gained a directory with a same-bytes header"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header at the path it had before"
}
case_duplicate() { # the toolchain moved onto a directory the environment lists
  tb_case native
  set_env "$B/home/.bats/ats2:$E1:$HDR"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$A/home" "$B/home"
  use "$B/home" "$A/llvm"
  build moved.log nd
  if ! cmp -s "$CASE_DIR/before.o" "$P/$OBJ"; then
    cp "$P/$OBJ" "$CASE_DIR/kept.o"
    clean_rebuild clean.log nd
    same "$CASE_DIR/kept.o" "$P/$OBJ" "the object after the move is neither before nor clean"
  fi
}
moved_shadow_case() { # <other|same>: a shadow after the whole toolchain moved
  tb_case native
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mv "$A/home" "$B/home"
  mv "$A/llvm" "$B/llvm"
  use "$B/home" "$B/llvm"
  build moved.log nd
  if [ "$1" = same ]; then cp "$HDR/h_angle.h" "$E1/h_angle.h"
  else mkhdr "$E1/h_angle.h" angle 5; fi
  : > "$CC_LOG"
  build shadow.log nd
  again shadow.log "a shadow ($1 bytes) after the toolchain moved"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object holds the header it found before the shadow"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
case_shadow_after_move_other() { moved_shadow_case other; }
case_shadow_after_move_same() { moved_shadow_case same; }
toolchain_shadow_case() { # <other|same>: a header in the ATS2 home before the compiler's own
  tb_case native
  mkhdr "$A/llvm/lib/clang/$RES_NAME/include/h_tc.h" tc 13
  printf '#include <h_tc.h>\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_tc (void) { return h_tc_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  if [ "$1" = same ]
  then cp "$A/llvm/lib/clang/$RES_NAME/include/h_tc.h" "$A/home/.bats/ats2/h_tc.h"
  else mkhdr "$A/home/.bats/ats2/h_tc.h" tc 14; fi
  : > "$CC_LOG"
  build tc.log nd
  again tc.log "a header ($1 bytes) in the ATS2 home before the compiler's own"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object holds the header it found before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
case_shadow_toolchain_other() { toolchain_shadow_case other; }
case_shadow_toolchain_same() { toolchain_shadow_case same; }
case_sdkroot() { # another SDKROOT is another build/, not a kept one
  tb_case native
  build cold.log nd SDKROOT=/sdk/one
  : > "$CC_LOG"
  build other.log nd SDKROOT=/sdk/two
  grep -aq '^bats: dropping build/' "$CASE_DIR/other.log" ||
    fail "another SDKROOT did not drop build/" "$CASE_DIR/other.log"
  again other.log "another SDKROOT"
}
case_checkout_move() { # build/ copied to another directory: kept, debug objects name the old one
  tb_case native
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  cp -a "$P" "$CASE_DIR/p-moved"
  P=$CASE_DIR/p-moved
  : > "$CC_LOG"
  build moved.log nd
  kept moved.log "a build/ copied to another directory"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object changed when build/ was copied"
}
case_control() { # the same move with a stand-in clang that drops -P: the object is made again
  tb_case native
  SHIM_DROP_P=1
  export SHIM_DROP_P
  build cold.log nd
  mv "$A/home" "$B/home"
  mv "$A/llvm" "$B/llvm"
  use "$B/home" "$B/llvm"
  : > "$CC_LOG"
  build moved.log nd
  again moved.log "the move, with line markers (control)"
}
ALL_CASES="$ALL_CASES nested-resource-under-home nested-home-under-resource sibling-root kind-letter
home-symlink llvm-symlink root-trailing-slash target-differs shape-empty shape-lost shape-header
duplicate
shadow-after-move-other shadow-after-move-same shadow-toolchain-other shadow-toolchain-same sdkroot
checkout-move control"

run_all "$@" || exit 1
echo "build-toolchain-path: ok"
