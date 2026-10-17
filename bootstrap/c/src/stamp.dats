staload "./stamp.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* stamp -- who made build/, and whether this bats may trust it
   (bats-lang/bats#267).

   build/.bats_stamp is plain text, the format first, then a line "name
   value" for each thing a build's files depend on that is not in the
   project:

     bats-stamp 1
     bats     <the digest of the running bats's own inputs, _bats_inputs>
     patsopt  <sha256 of the cksum listing of bin/patsopt, prelude, libats,
               share and ccomp (cache.bats's toolchain_digest)>
     cc       <sha256 of clang --version and clang -dumpmachine, and of
               wasm-ld --version for a wasm mark>
     flags    <the flag templates patsopt and cc are run with for this
               mark, PATSHOME written $(PATSHOME)>
     mark     <the target and mode digit of build/.bats_target>

   No line holds a path: the C names none (bats-lang/bats#250), the
   listing is of contents, and the flags write PATSHOME as a variable, so
   a build/ copied to another directory, or made on another machine with
   the same bats, ATS2 and C compiler, has the same stamp.

   At the start of a build (after cache_swap, which has put this mark's
   build/ in place, from its stash if it had been put aside), the stamp
   this bats would write is compared with the one in build/. Equal: build/
   is kept. Different or missing: everything in build/ but .stash goes, one
   line on stderr names the first line that differs, and the build starts
   from nothing. A stash carries the stamp of whoever made it (cache_swap
   moves every file of build/), so it is judged when it is swapped in. A
   build/ that holds no build (no .bats_target and no stamp) is not
   dropped, and says nothing. build/.bats_valid/ (validated.bats) is kept
   through a drop, as through a change of mark (build.bats's cache_swap): its
   records are keyed by what they were judged from, bats's own inputs
   among them, and read nothing of the toolchain, the target or the
   mode. This replaces the hand-bumped build/
   .bats_cache_id: a compiler change needs no bump, since the compiler's
   own inputs are in the stamp. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"
staload "cache.sats"
staload "_bats_inputs.sats"

(* The flag templates, one line each, written out here and not read off
   the argument lists in helpers.bats (run_cc, patsopt_only) and
   build.bats (run_wasm_cc, compile_wasm_runtime, the wasm-ld and link
   commands). The digest of bats's own source is the stamp's first line,
   so a change to the flags there is a change of bats whether or not
   this text follows; this line says which flags a stamp was made with,
   for whoever reads it. The profile's choice (-O2, or -g -O0) is in
   the template, since one build/ holds both profiles' work. *)
#define FLAGS_NATIVE "patsopt -IATS build -IATS build/src -IATS build/bats_modules -o OUT -d IN; cc clang -c -o OUT IN [-O2 | -g -O0] -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime; runtime clang -c -o build/_bats_native_runtime.o build/_bats_native_runtime.c; link clang -o BIN OBJECTS [-O2 | -g -O0]"
#define FLAGS_WASM "patsopt -IATS build -IATS build/src -IATS build/bats_modules -o OUT -d IN; cc clang -c -o OUT IN [-O2 | -g -O0] -I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime; wasm cc clang --target=wasm32 -O2 -nostdlib -ffreestanding -fvisibility=default -D_ATS_CCOMP_HEADER_NONE_ -D_ATS_CCOMP_EXCEPTION_NONE_ -D_ATS_CCOMP_PRELUDE_NONE_ -D_ATS_CCOMP_RUNTIME_NONE_ -include build/_bats_wasm_runtime.h -I build/_bats_wasm_stubs -Wno-implicit-function-declaration -Wno-int-conversion -c -o OUT IN; link wasm-ld --no-entry --allow-undefined --lto-O2 -z stack-size=1048576 --initial-memory=16777216 --max-memory=268435456 --export=bats_dynload --export=mainats_0_void --export=malloc -o OUT OBJECTS"

(* The mark is a wasm one: 1, or 3 in check and test mode *)
fn mark_is_wasm (mark: int): bool = (mark = 1 || mark = 3)

(* sh -c script, with args as $1, ...: sh's exit status, -1 when it
   could not be run; its stdout is captured into out and the number of
   its bytes is returned beside the status *)
fn sh_capture {sn:nat}{lo:agz}
  (script: string sn, args: $L.listv($P.arg_entry), out: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k) = let
  val exec = str_to_path_arr("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, script)
  var b4 = $B.create()
  val () = bput_v(b4, "sh")
  val r = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4), args)))), out)
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in r end

(* The sha256 of the file at the path, appended to out; false when it
   cannot be read *)
fn put_file_digest {sn:nat | sn < $B.BUILDER_CAP}
  (path: string sn, out: !$B.builder_v >> $B.builder_v): bool = let
  val p = str_to_path_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val ok = put_file_sha256(bv_p, out)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in ok end

(* What build/.bats_cc is made of: the C compiler's version and target,
   and the wasm linker's for a wasm mark, without the lines that name
   where they are installed (a path is not part of what they are) *)
fn cc_listed (mark: int): bool = let
  var which : $B.builder_v = $B.create()
  val () = (if mark_is_wasm(mark) then bput_v(which, "wasm") else bput_v(which, "native"))
  val none = $A.alloc<byte>(4096)
  val r = sh_capture("{ clang --version; clang -dumpmachine; if [ \"$1\" = wasm ]; then wasm-ld --version; fi; } 2>&1 | sed -e '/^InstalledDir:/d' -e '/^Configuration file:/d' > build/.bats_cc",
    $L.list_vt_cons(mk_arg(which), $L.list_vt_nil()), none)
  val () = $A.free<byte>(none)
in r.0 = 0 end

(* The script that judges build/ against build/.bats_stamp.new, the stamp
   this bats would write, with the mark's digit as $1. Nothing to judge
   (no .bats_target and no stamp): the new stamp is put in place. Else
   the first of the format, the lines in order, and the mark that
   differs is named on stdout, and build/ but its stash goes. *)
#define JUDGE "cd build || exit 1\nif [ ! -f .bats_target ] && [ ! -f .bats_stamp ]; then mv -f .bats_stamp.new .bats_stamp; exit 0; fi\nwhy=\nif [ ! -f .bats_stamp ]; then why='no stamp'\nelif [ \"$(sed -n 1p .bats_stamp)\" != 'bats-stamp 1' ]; then why='the stamp format differs'\nelse\n  for n in bats patsopt cc flags mark; do\n    a=$(sed -n \"s/^$n //p\" .bats_stamp); b=$(sed -n \"s/^$n //p\" .bats_stamp.new)\n    if [ \"$a\" != \"$b\" ]; then why=\"$n differs\"; break; fi\n  done\nfi\nif [ -z \"$why\" ] && [ \"$(cat .bats_target 2>/dev/null)\" != \"$1\" ]; then why='mark differs'; fi\nif [ -z \"$why\" ] && ! cmp -s .bats_stamp .bats_stamp.new; then why='the stamp differs'; fi\nif [ -n \"$why\" ]; then\n  echo \"bats: dropping build/ (made by another bats: $why)\"\n  find . -mindepth 1 -maxdepth 1 ! -name .stash ! -name .bats_valid ! -name .bats_stamp.new -exec rm -rf {} +\n  mkdir -p src/bin bats_modules\nfi\nmv -f .bats_stamp.new .bats_stamp\n"

(* The stamp this bats would write for the mark, into build/.bats_stamp.new:
   false (and said) when a part of it cannot be had *)
fn stamp_write {lph:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int, mark: int): bool = let
  var st : $B.builder_v = $B.create()
  val () = bput_v(st, "bats-stamp 1\nbats ")
  val () = bput_v(st, bats_inputs_sha256())
  val () = bput_v(st, "\npatsopt ")
  val tool = toolchain_digest(ph, phlen, st)
  val () = bput_v(st, "\ncc ")
  val cc = (if cc_listed(mark) then put_file_digest("build/.bats_cc", st) else false): bool
  val () = bput_v(st, "\nflags ")
  val () = (if mark_is_wasm(mark) then bput_v(st, FLAGS_WASM) else bput_v(st, FLAGS_NATIVE))
  val () = bput_v(st, "\nmark ")
  val () = put_int_v(st, mark)
  val () = put_char_v(st, 10)
  val ok = (if tool && cc then true else false): bool
  val p = str_to_path_arr("build/.bats_stamp.new")
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val wrote = (write_file_from_builder(bv_p, 524288, st) = 0): bool
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in ok && wrote end




implement stamp_check (ph, phlen, mark) =
  if ~stamp_write(ph, phlen, mark) then let
    val () = set_build_err()
  in prerr! ("error: the stamp of build/ (bats, the toolchain and the C compiler) cannot be made: is clang installed and is ATS2 whole?\n") end
  else let
    var d : $B.builder_v = $B.create()
    val () = put_int_v(d, mark)
    val out = $A.alloc<byte>(4096)
    val @(rc, k) = sh_capture(JUDGE, $L.list_vt_cons(mk_arg(d), $L.list_vt_nil()), out)
    val @(fz_o, bv_o) = $A.freeze<byte>(out)
    val () = (if k > 0 then prerr_seg(bv_o, 0, k, 4096) else ())
    val () = $A.drop<byte>(fz_o, bv_o)
    val () = $A.free<byte>($A.thaw<byte>(fz_o))
  in
    if rc = 0 then ()
    else let
      val () = set_build_err()
    in prerr! ("error: build/ cannot be judged against its stamp\n") end
  end
