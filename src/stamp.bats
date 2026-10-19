(* stamp -- who made build/, and whether this bats may trust it
   (bats-lang/bats#267).

   build/.bats_stamp is plain text, the format first, then a line "name
   value" for each thing a build's files depend on that is not in the
   project:

     bats-stamp 1
     bats     <the digest of the running bats's own inputs, _bats_inputs>
     patsopt  <sha256 of the cksum listing of bin/patsopt, prelude, libats,
               share and ccomp (cache.bats's toolchain_digest)>
     cc       <sha256 of clang --version and clang -dumpmachine, of
               wasm-ld --version for a wasm mark, and of the environment
               clang reads: CPATH, LIBRARY_PATH and the others named in
               put_cc_environment, each a name and its value, digested and
               not stored (bats-lang/bats#322)>
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

#use array as A
#use builder as B
#use env as E
#use list as L
#use process as P
#use result as R
#use sha256 as SHA

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

(* The environment the C compiler reads, whose values change what it makes
   (bats-lang/bats#322). They are digested into the cc line, never stored:
   a build/ made with one value is dropped by a build with another, as by
   another clang. The list is the one place these names are written
   (put_cc_environment). The wasm linker reads none of them: the wasm
   mark's cc line digests the same list only because its C is compiled by
   clang too, and the linker's version is in the same line.

   What was verified, and how: the names clang's manual documents
   (clang.llvm.org/docs/CommandGuide/clang.html, ENVIRONMENT) are CPATH,
   C_INCLUDE_PATH, CPLUS_INCLUDE_PATH, OBJC_INCLUDE_PATH,
   OBJCPLUS_INCLUDE_PATH and MACOSX_DEPLOYMENT_TARGET. The clang 18.1.3
   driver (strings(1) of libclang-cpp.so.18.1, and llvm-project
   llvmorg-18.1.3 source) also reads LIBRARY_PATH and COMPILER_PATH
   (Driver.cpp), SDKROOT (Darwin.cpp), CLANG_NO_DEFAULT_CONFIG
   (Driver.cpp) and CCC_OVERRIDE_OPTIONS (tools/driver/driver.cpp). The
   Darwin driver also reads RC_DEBUG_PREFIX_MAP and RC_DEBUG_OPTIONS
   (-fdebug-prefix-map and debug options, which change the debug
   profile's objects) and the deployment targets of the other Apple
   platforms, IPHONEOS_, TVOS_, WATCHOS_ and DRIVERKIT_DEPLOYMENT_TARGET,
   which pick the target the objects are made for. NOT CHECKED: those
   Darwin names and DEVELOPER_DIR (Apple's xcrun picks the SDK by it) were
   not run on a Mac here; they are listed from the same sources and cost
   nothing on another machine.

   Removed from the list, and why:
   - SOURCE_DATE_EPOCH: clang reads it only for __DATE__ and __TIME__.
     No C that patsopt emits and no ATS2 header uses them, so it changes no
     object here. Reproducible-build setups set it to the commit time, so
     it would drop build/ on every commit and defeat the incremental
     build; a package whose own C uses __DATE__ or __TIME__ is not a pure
     function of its inputs anyway (a clean build differs by time without
     it).
   - LLD_IN_TEST: a test-harness switch of lld's driver (lld.cpp); it
     changes no output.
   - LLD_VERSION: read only by lld's ELF writer for the .comment text, and
     wasm-ld does not read it (the string is the ELF code linked in); bats
     links native with the system's clang and never lld's ELF.
   - LLVM_OVERRIDE_PRODUCER: the bitcode producer string; no bitcode is
     produced (no -flto in either flag template).

   Left out, each reads no compiled output: TMPDIR, TEMP and TMP (temporary
   files), CLANG_MODULE_CACHE_PATH (the module cache, used with -fmodules
   only), CLANG_CRASH_DIAGNOSTICS_DIR, CC_LOG_* and CC_PRINT_* (logs), the
   LLVM symbolizer's, FORCE_CLANG_DIAGNOSTICS_CRASH, and LLD_REPRODUCE (a
   reproducer archive).

   ccache's manual names no hashed variable and sccache's architecture doc
   says its hash covers "Environment variables" without naming them, so
   this list is bats's own. *)

(* The bytes of a builder, hashed into c; the builder is consumed *)
fn hash_builder (c: !$SHA.ctx, b: $B.builder_v): void = let
  val @(ba, bl) = $B.into_arr(b)
  val () = $SHA.update(c, ba, bl)
  val () = $A.free<byte>(ba)
in end

(* A variable that is not set, into c: its name, then " unset" (so unset and
   empty differ). *)
fn hash_env_unset {sn:nat | sn < $B.BUILDER_CAP}
  (name: string sn, c: !$SHA.ctx): void = let
  var h : $B.builder_v = $B.create()
  val () = bput_v(h, name)
  val () = bput_v(h, " unset\n")
in hash_builder(c, h) end

fn hash_env_set {sn:nat | sn < $B.BUILDER_CAP}{l:agz}
  (name: string sn, bv: !$A.borrow(byte, l, 131072), k: int, c: !$SHA.ctx): void = let
  var h : $B.builder_v = $B.create()
  val () = bput_v(h, name)
  val () = bput_v(h, " ")
  val () = put_int_v(h, k)
  val () = bput_v(h, "\n")
  val () = copy_to_builder_v(bv, 0, k, 131072, h)
  val () = bput_v(h, "\n")
in hash_builder(c, h) end

(* One environment variable into c, its name first (hash_env_unset,
   hash_env_set). The value is read whole: getenv's copy is cut at the
   buffer, so a value of 128 KiB or more is not digested short. It is
   refused, with the variable's name and size said, and the stamp is not
   written (exec refuses a string that long, so this is for an environment
   changed inside the process). *)
fn hash_env_var {sn:nat | sn < $B.BUILDER_CAP}
  (name: string sn, c: !$SHA.ctx): bool = let
  val na = str_to_path_arr(name)
  val buf = $A.alloc<byte>(131072)
  val got = $E.get_cstr(na, 524288, buf, 131072)
  val () = $A.free<byte>(na)
  val ok = (case+ got of
    | ~$R.none() => let
        val () = hash_env_unset(name, c)
        val () = $A.free<byte>(buf)
      in true end
    | ~$R.some(k) =>
        if k >= 131072 then let
          val () = $A.free<byte>(buf)
          val () = set_build_err()
          val () = prerr! ("error: the value of ", name, " is ", k, " bytes or more: the stamp of build/ cannot be made with it (the C compiler reads it; set it shorter)\n")
        in false end
        else let
          val @(fz_b, bv_b) = $A.freeze<byte>(buf)
          val () = hash_env_set(name, bv_b, k, c)
          val () = $A.drop<byte>(fz_b, bv_b)
          val () = $A.free<byte>($A.thaw<byte>(fz_b))
        in true end): bool
in ok end

(* The environment the C compiler reads (the names the research comment
   above hash_builder gives), hashed into c in this order. One list, for
   both marks: a native build with one of the wasm mark's set (the same
   list) is dropped, which costs a rebuild and never a wrong object. *)
fn put_cc_environment (c: !$SHA.ctx): bool =
  hash_env_var("CPATH", c)
  && hash_env_var("C_INCLUDE_PATH", c)
  && hash_env_var("CPLUS_INCLUDE_PATH", c)
  && hash_env_var("OBJC_INCLUDE_PATH", c)
  && hash_env_var("OBJCPLUS_INCLUDE_PATH", c)
  && hash_env_var("LIBRARY_PATH", c)
  && hash_env_var("COMPILER_PATH", c)
  && hash_env_var("SDKROOT", c)
  && hash_env_var("DEVELOPER_DIR", c)
  && hash_env_var("MACOSX_DEPLOYMENT_TARGET", c)
  && hash_env_var("IPHONEOS_DEPLOYMENT_TARGET", c)
  && hash_env_var("TVOS_DEPLOYMENT_TARGET", c)
  && hash_env_var("WATCHOS_DEPLOYMENT_TARGET", c)
  && hash_env_var("DRIVERKIT_DEPLOYMENT_TARGET", c)
  && hash_env_var("RC_DEBUG_PREFIX_MAP", c)
  && hash_env_var("RC_DEBUG_OPTIONS", c)
  && hash_env_var("CCC_OVERRIDE_OPTIONS", c)
  && hash_env_var("CLANG_NO_DEFAULT_CONFIG", c)

(* The cc line's digest, 64 hex digits appended to out: the sha256 of
   build/.bats_cc's digest and of the environment above. false when the
   listing cannot be digested or a value is too long. *)
fn put_cc_digest (out: !$B.builder_v >> $B.builder_v): bool = let
  var lst : $B.builder_v = $B.create()
  val listed = put_file_digest("build/.bats_cc", lst)
  val c = $SHA.init()
  val () = hash_builder(c, lst)
  val env = put_cc_environment(c)
  val digest = $A.alloc<byte>(64)
  val () = $SHA.finish(c, digest)
  val @(fz_d, bv_d) = $A.freeze<byte>(digest)
  val () = copy_to_builder_v(bv_d, 0, 64, 64, out)
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
in listed && env end

(* The script that judges build/ against build/.bats_stamp.new, the stamp
   this bats would write, with the mark's digit as $1. Nothing to judge
   (no .bats_target and no stamp): the new stamp is put in place. Else
   the first of the format, the lines in order, and the mark that
   differs is named on stdout, and build/ but its stash goes. *)
#define JUDGE "cd build || exit 1\nif [ ! -f .bats_target ] && [ ! -f .bats_stamp ]; then mv -f .bats_stamp.new .bats_stamp; exit 0; fi\nwhy=\nif [ ! -f .bats_stamp ]; then why='no stamp'\nelif [ \"$(sed -n 1p .bats_stamp)\" != 'bats-stamp 1' ]; then why='the stamp format differs'\nelse\n  for n in bats patsopt cc flags mark; do\n    a=$(sed -n \"s/^$n //p\" .bats_stamp); b=$(sed -n \"s/^$n //p\" .bats_stamp.new)\n    if [ \"$a\" != \"$b\" ]; then why=\"$n differs\"; break; fi\n  done\nfi\nif [ -z \"$why\" ] && [ \"$(cat .bats_target 2>/dev/null)\" != \"$1\" ]; then why='mark differs'; fi\nif [ -z \"$why\" ] && ! cmp -s .bats_stamp .bats_stamp.new; then why='the stamp differs'; fi\nif [ -n \"$why\" ]; then\n  echo \"bats: dropping build/ (made by another bats: $why)\"\n  find . -mindepth 1 -maxdepth 1 ! -name .stash ! -name .bats_valid ! -name .bats_stamp.new -exec rm -rf {} +\n  mkdir -p src/bin bats_modules\nfi\nmv -f .bats_stamp.new .bats_stamp\n"

(* What became of the stamp this bats would write for the mark, into
   build/.bats_stamp.new: written; a part of it could not be had (said
   already); or the file could not be written (said, with the reason) *)
datatype stamp_made =
  | StampMade
  | StampPartMissing
  | StampNotWritten

fn stamp_write {lph:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int, mark: int): stamp_made = let
  var st : $B.builder_v = $B.create()
  val () = bput_v(st, "bats-stamp 1\nbats ")
  val () = bput_v(st, bats_inputs_sha256())
  val () = bput_v(st, "\npatsopt ")
  val tool = toolchain_digest(ph, phlen, st)
  val () = bput_v(st, "\ncc ")
  val cc = (if cc_listed(mark) then put_cc_digest(st) else false): bool
  val () = bput_v(st, "\nflags ")
  val () = (if mark_is_wasm(mark) then bput_v(st, FLAGS_WASM) else bput_v(st, FLAGS_NATIVE))
  val () = bput_v(st, "\nmark ")
  val () = put_int_v(st, mark)
  val () = put_char_v(st, 10)
  val ok = (if tool && cc then true else false): bool
  val p = str_to_path_arr("build/.bats_stamp.new")
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val stv = st
  val made = (if ok then
      (if write_settle(bv_p, 524288, write_file_from_builder(bv_p, 524288, stv)) = 0 then StampMade() else StampNotWritten())
    else let val () = $B.builder_free(stv) in StampPartMissing() end): stamp_made
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in made end

#pub fn stamp_check {lph:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int, mark: int): void

implement stamp_check (ph, phlen, mark) =
  case+ stamp_write(ph, phlen, mark) of
  | StampPartMissing() => let
    val () = set_build_err()
  in prerr! ("error: the stamp of build/ (bats, the toolchain and the C compiler) cannot be made: the C compiler's version or environment could not be read (a message above says which)\n") end
  (* write_settle said why, and failed the build *)
  | StampNotWritten() => ()
  | StampMade() => let
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
