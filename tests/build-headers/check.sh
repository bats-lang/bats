#!/bin/sh
# An object is keyed on what its compile reads and the path it found each header at
# (bats-lang/bats#477, build-freshness.md): the text of its C preprocessed with
# -P -frewrite-includes, and the list of the headers clang entered (-H). A header changed in place,
# a header that now shadows another earlier on the search path (other bytes or the very same: a
# native -g object, a __FILE__ string in any object, names the path), a conditional that a new
# file flips (__has_include), a header changed only in blank lines or comments (the lines of a -g
# object) make the object again, and it is the object a clean build writes; with nothing changed
# no cc runs. A change of clang's output that this reads (-H, the resource directory) is a
# failure: the object is made again, never kept, and one line says so.
# usage: tests/build-headers/check.sh <bats-binary> <repository-dir> [case...]
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
shift 2
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../cc-cases.sh"

shadow_case() { # <angle|cpath|quoted|stubs> <other|same> <nd|nr|w>
  route=$1
  bytes=$2
  mode=$3
  if [ "$mode" = w ]; then new_case wasm; else new_case native; fi
  standard_headers
  write_src
  set_env
  case $route in
    angle) dir=$E1 name=h_angle.h src=$HDR/h_angle.h kind=angle val=5 keep=;;
    cpath) dir=$E2 name=h_cpath.h src=$HDR2/h_cpath.h kind=cpath val=6 keep=;;
    quoted) dir=$P/build/src/bin name=h_quoted.h src=$HDR/h_quoted.h kind=quoted val=7
      keep=build/src/bin/h_quoted.h;;
    stubs) dir=$P/build/_bats_wasm_stubs name=h_angle.h src=$HDR/h_angle.h kind=angle val=5
      keep=build/_bats_wasm_stubs/h_angle.h;;
  esac
  build cold.log "$mode"
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mkdir -p "$dir"
  if [ "$bytes" = same ]; then cp "$src" "$dir/$name"; else mkhdr "$dir/$name" "$kind" "$val"; fi
  : > "$CC_LOG"
  build shadow.log "$mode"
  again shadow.log "a header that shadows a listed one ($route, $bytes bytes, $mode)"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object holds the header it found before the shadow"
  : > "$CC_LOG"
  build next.log "$mode"
  no_cc "the build after the shadow"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log "$mode" $keep
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept after the shadow is not a clean build's"
}
for r in angle cpath quoted stubs; do
  for b in other same; do
    for m in nd nr w; do
      eval "case_shadow_${r}_${b}_${m}() { shadow_case $r $b $m; }"
    done
  done
done
ALL_CASES="shadow-angle-other-nd shadow-angle-other-nr shadow-angle-other-w
shadow-angle-same-nd shadow-angle-same-nr shadow-angle-same-w
shadow-cpath-other-nd shadow-cpath-same-nd
shadow-quoted-other-nd shadow-quoted-same-nd shadow-quoted-other-w shadow-quoted-same-w
shadow-stubs-other-w shadow-stubs-same-w"

case_shadow_removed() { # the shadow of a header with the same bytes deleted again
  new_case native
  standard_headers
  write_src
  set_env
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  cp "$HDR/h_angle.h" "$E1/h_angle.h"
  build shadow.log nd
  rm "$E1/h_angle.h"
  : > "$CC_LOG"
  build removed.log nd
  again removed.log "a shadow deleted again"
  same "$CASE_DIR/before.o" "$P/$OBJ" "the object after the shadow was deleted is not the first one"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept after the shadow was deleted is not clean"
}
case_has_include() { # a new file flips a branch that only defines a macro
  new_case native
  standard_headers
  printf '#if __has_include(<h_flag.h>)\n#define CC_FLAG 1\n#else\n#define CC_FLAG 0\n#endif\n' \
    > "$CASE_DIR/extra.inc"
  printf 'int cc_flag (void) { return CC_FLAG; }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  printf '#define UNRELATED 1\n' > "$E1/h_flag.h"
  : > "$CC_LOG"
  build flip.log nd
  again flip.log "a new file that flips __has_include"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object holds the branch before the file"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept after the flip is not a clean build's"
}
case_include_next() { # a same-bytes copy between the including header's directory and the next
  new_case native
  standard_headers
  MID=$CASE_DIR/mid
  mkdir -p "$MID"
  printf '#include <h_next.h>\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_next (void) { return h_next_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  printf '#include_next <h_next.h>\n' > "$E1/h_next.h"
  mkhdr "$HDR/h_next.h" next 4
  set_env "$E1:$MID:$HDR"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  cp "$HDR/h_next.h" "$MID/h_next.h"
  : > "$CC_LOG"
  build next.log nd
  again next.log "a same-bytes copy that #include_next now takes"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header #include_next took before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
created_dir_case() { # <nd|w>: a directory the environment names, created later, same bytes
  if [ "$1" = w ]; then new_case wasm; else new_case native; fi
  LATE=$CASE_DIR/late
  mkhdr "$E1/h_angle.h" angle 1
  mkhdr "$E1/h_cpath.h" cpath 2
  mkhdr "$E1/h_quoted.h" quoted 3
  printf '#include <h_late.h>\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_late (void) { return h_late_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  mkhdr "$HDR/h_late.h" late 8
  set_env "$E1:$LATE:$HDR" ""
  build cold.log "$1"
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mkdir -p "$LATE"
  cp "$HDR/h_late.h" "$LATE/h_late.h"
  : > "$CC_LOG"
  build late.log "$1"
  again late.log "a directory created later with a same-bytes header"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header at the path it had before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log "$1"
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
case_created_dir_nd() { created_dir_case nd; }
case_created_dir_w() { created_dir_case w; }
case_symlink() { # a symlinked directory retargeted to the same bytes, then to other bytes
  new_case native
  standard_headers
  mkdir -p "$CASE_DIR/real1" "$CASE_DIR/real2" "$CASE_DIR/real3"
  mkhdr "$CASE_DIR/real1/h_link.h" link 9
  cp "$CASE_DIR/real1/h_link.h" "$CASE_DIR/real2/h_link.h"
  mkhdr "$CASE_DIR/real3/h_link.h" link 10
  LNK=$CASE_DIR/link
  ln -s real1 "$LNK"
  printf '#include <h_link.h>\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_link (void) { return h_link_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env "$LNK:$HDR"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  ln -sfn real2 "$LNK"
  : > "$CC_LOG"
  build same.log nd
  no_cc "a symlinked directory retargeted to the same bytes"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept after the retarget is not a clean build's"
  ln -sfn real3 "$LNK"
  : > "$CC_LOG"
  build other.log nd
  again other.log "a symlinked directory retargeted to other bytes"
}
case_spelling() { # relative, trailing slash, ., // and nested directories; a shadow in the first
  new_case native
  standard_headers
  mkdir -p "$P/inc/sub"
  mkhdr "$P/inc/sub/h_sp.h" sp 11
  printf '#include <h_sp.h>\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_sp (void) { return h_sp_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env "$E1:$HDR" "inc/:./inc//sub:$E2:$HDR2"
  build cold.log nd
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  cp "$P/inc/sub/h_sp.h" "$P/inc/h_sp.h"
  : > "$CC_LOG"
  build sp.log nd
  again sp.log "a same-bytes copy in the first of two nested relative directories"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header at the path it had before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
inplace_case() { # <nd|w>
  if [ "$1" = w ]; then new_case wasm; else new_case native; fi
  standard_headers
  write_src
  set_env
  build cold.log "$1"
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  printf '#define H_ANGLE 2\nstatic inline const char *h_angle_file (void) { return __FILE__; }\n' \
    > "$HDR/h_angle.h"
  touch -d '2001-01-01 00:00:00' "$HDR/h_angle.h"
  : > "$CC_LOG"
  build inplace.log "$1"
  again inplace.log "a header changed in place (same size, the time put back)"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object holds the old header"
  : > "$CC_LOG"
  build next.log "$1"
  no_cc "the build after the header changed"
}
case_inplace_nd() { inplace_case nd; }
case_inplace_w() { inplace_case w; }
comment_case() { # <nd|w>: blank lines, then comment lines, grown past what -P collapses
  if [ "$1" = w ]; then new_case wasm; else new_case native; fi
  standard_headers
  # nine blank lines and nine comment lines: -P alone prints a gap of more than eight as one
  # newline, so growing them to twenty changes the lines of the object and not the text -P gives
  { for i in 1 2 3 4 5 6 7 8 9; do printf '// only a comment, line %s\n' $i; done
    printf 'static inline int h_nested_value (void) { return 3; }\n'; } > "$HDR/h_nested.h"
  { printf '#include <h_nested.h>\n'; for i in 1 2 3 4 5 6 7 8 9; do printf '\n'; done
    printf 'static inline int h_lines_value (void) { return h_nested_value (); }\n'
  } > "$HDR/h_lines.h"
  printf '#include <h_lines.h>\n' > "$CASE_DIR/extra.inc"
  printf 'int cc_lines (void) { return h_lines_value (); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env
  build cold.log "$1"
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  { printf '#include <h_nested.h>\n'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do printf '\n'; done
    printf 'static inline int h_lines_value (void) { return h_nested_value (); }\n'
  } > "$HDR/h_lines.h"
  : > "$CC_LOG"
  build blank.log "$1"
  again blank.log "the blank lines of a header grown from nine to twenty"
  if [ "$1" = nd ]; then differs "$CASE_DIR/before.o" "$P/$OBJ" "the object holds the old lines"
  else same "$CASE_DIR/before.o" "$P/$OBJ" "a blank run changed the wasm object (no debug info)"; fi
  cp "$P/$OBJ" "$CASE_DIR/blank.o"
  clean_rebuild clean.log "$1"
  same "$CASE_DIR/blank.o" "$P/$OBJ" "the object kept after the blank lines is not a clean build's"
  { for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      printf '// only a comment, line %s\n' $i; done
    printf 'static inline int h_nested_value (void) { return 3; }\n'; } > "$HDR/h_nested.h"
  : > "$CC_LOG"
  build comment.log "$1"
  again comment.log "the comment lines of a header included by a header grown from nine to twenty"
  if [ "$1" = nd ]; then differs "$CASE_DIR/blank.o" "$P/$OBJ" "the object holds the old lines"; fi
  cp "$P/$OBJ" "$CASE_DIR/comment.o"
  clean_rebuild clean2.log "$1"
  same "$CASE_DIR/comment.o" "$P/$OBJ" "the object kept after the comments is not a clean build's"
}
case_comment_nd() { comment_case nd; }
case_comment_w() { comment_case w; }
ALL_CASES="$ALL_CASES shadow-removed has-include include-next created-dir-nd created-dir-w symlink
spelling inplace-nd inplace-w comment-nd comment-w"

case_edit_during_cc() { # a header edited while cc runs: the key is of the text made before cc
  new_case native
  standard_headers
  write_src
  set_env
  build cold.log nd SHIM_EDIT="$HDR/h_angle.h"
  cp "$P/$OBJ" "$CASE_DIR/first.o"
  : > "$CC_LOG"
  build next.log nd
  again next.log "a header edited while cc ran"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  : > "$CC_LOG"
  build again.log nd
  no_cc "the build after the header settled"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}
case_shadow_nonsystem_same_w() { # a quoted header beside the includer over one found by -I
  new_case wasm
  standard_headers
  mkdir -p "$P/build/_bats_wasm_stubs"
  mkhdr "$P/build/_bats_wasm_stubs/h_ns.h" ns 14
  printf '#include "h_ns.h"\n' > "$CASE_DIR/extra.inc"
  printf 'const char *cc_ns (void) { return h_ns_file (); }\n' > "$CASE_DIR/extra.c"
  write_src
  set_env
  build cold.log w
  cp "$P/$OBJ" "$CASE_DIR/before.o"
  mkdir -p "$P/build/src/bin"
  cp "$P/build/_bats_wasm_stubs/h_ns.h" "$P/build/src/bin/h_ns.h"
  : > "$CC_LOG"
  build ns.log w
  again ns.log "a same-bytes quoted header over one found in a -I directory"
  differs "$CASE_DIR/before.o" "$P/$OBJ" "the object names the header at the path it had before"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log w build/_bats_wasm_stubs/h_ns.h build/src/bin/h_ns.h
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
}

format_case() { # <name> <expect: again|kept> VAR=value...: clang's output varied, three builds
  name=$1
  expect=$2
  shift 2
  new_case native
  standard_headers
  write_src
  set_env
  build cold.log nd "$@"
  for n in 1 2; do
    : > "$CC_LOG"
    build "next$n.log" nd "$@"
    if [ "$expect" = again ]; then
      again "next$n.log" "$name (check $n)"
      grep -aq "could not be used\|could not be asked\|is not known" "$CASE_DIR/next$n.log" ||
        fail "$name (check $n) was not said" "$CASE_DIR/next$n.log"
    else
      no_cc "$name (check $n)"
      ! grep -aq "could not be used\|could not be asked\|is not known" "$CASE_DIR/next$n.log" ||
        fail "$name (check $n) was said though the object is kept" "$CASE_DIR/next$n.log"
    fi
  done
}
case_format_no_H() { format_case "clang printing no -H lines" again SHIM_DROP_H=1; }
case_format_unknown_form() { format_case "a line of dots" again 'SHIM_STDERR=....'; }
case_format_dot_diagnostic() { # before clang's own lines: a diagnostic taken for a header shows
  format_case "a diagnostic that names a relative header" kept \
    'SHIM_STDERR_FIRST=./inc/a.h:3:1: warning: x'
}
case_format_dot_no_path() { format_case "a run of dots with no path" again 'SHIM_STDERR=... '; }
case_format_noise() { format_case "extra lines that do not start with a dot" kept \
  'SHIM_STDERR=In file included from x.c:1:\nnote: something'; }
case_format_unreadable() { format_case "clang stopping at an unreadable header" again \
  "SHIM_FAIL=fatal error: cannot open file 'x.h': Permission denied"; }
case_format_marker_renamed() {
  format_case "the rewritten-include marker renamed" kept SHIM_RENAME_MARKER=1
}
case_format_root_fails() { format_case "-print-resource-dir failing" again SHIM_RD=fail; }
case_format_root_empty() { format_case "-print-resource-dir printing nothing" again SHIM_RD=empty; }
case_format_root_relative() {
  format_case "-print-resource-dir printing a relative path" again SHIM_RD=relative
}
case_format_root_multi() {
  format_case "-print-resource-dir printing two lines" again SHIM_RD=multi
}
case_format_root_slash() { format_case "-print-resource-dir printing /" again SHIM_RD=slash; }
case_format_root_dotdot() {
  format_case "-print-resource-dir printing a path with .." kept SHIM_RD=dotdot
}
ALL_CASES="$ALL_CASES edit-during-cc shadow-nonsystem-same-w format-no-H format-unknown-form
format-dot-diagnostic format-dot-no-path
format-noise format-unreadable format-marker-renamed format-root-fails format-root-empty
format-root-relative format-root-multi format-root-slash format-root-dotdot"

case_no_include_w() { # a wasm C whose only include is the -include runtime header
  new_case wasm
  printf '%s\n\nimplement main0 () = ()\n' "$TARGET" > "$SRC"
  set_env
  build cold.log w
  : > "$CC_LOG"
  build next.log w
  no_cc "a wasm C with no include of its own"
}
case_no_include_n() { # a native C with no include of its own: the ATS2 runtime headers only
  new_case native
  printf '%s\n\nimplement main0 () = ()\n' "$TARGET" > "$SRC"
  set_env
  build cold.log nd
  : > "$CC_LOG"
  build next.log nd
  no_cc "a native C with no include of its own"
}
case_big() { # a C that includes 12000 headers (a listing over 512 KiB); its peak memory is said
  new_case native
  standard_headers
  mkdir -p "$CASE_DIR/many"
  : > "$CASE_DIR/extra.inc"
  i=1
  while [ $i -le 12000 ]; do
    printf '#define BIG_%s 1\n' $i > "$CASE_DIR/many/big_header_with_a_long_name_$i.h"
    printf '#include <big_header_with_a_long_name_%s.h>\n' $i >> "$CASE_DIR/extra.inc"
    i=$((i + 1))
  done
  write_src
  set_env "$E1:$HDR:$CASE_DIR/many"
  build cold.log nd
  : > "$CC_LOG"
  build_peak next.log nd
  big_kb=$PEAK_KB
  no_cc "a C that includes 12000 headers"
  cp "$P/$OBJ" "$CASE_DIR/kept.o"
  clean_rebuild clean.log nd
  same "$CASE_DIR/kept.o" "$P/$OBJ" "the object kept is not a clean build's"
  new_case native one
  standard_headers
  write_src
  set_env
  build cold1.log nd
  build_peak next1.log nd
  echo "peak resident size of the check: $big_kb kB with 12000 headers, $PEAK_KB kB with 3"
  [ "$big_kb" -le $((PEAK_KB + 65536)) ] ||
    fail "the check of a C with 12000 headers used $big_kb kB, more than 64 MiB over $PEAK_KB kB"
}
ALL_CASES="$ALL_CASES no-include-w no-include-n big"

run_all "$@" || exit 1
echo "build-headers: ok"
