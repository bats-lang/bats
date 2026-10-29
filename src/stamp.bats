(* stamp -- who made build/, and whether this bats may trust it
   (bats-lang/bats#267).

   build/.bats_stamp is plain text, the format first, then a line "name
   value" for each thing a build's files depend on that is not in the
   project:

     bats-stamp 2
     bats     <the digest of the running bats's own inputs, _bats_inputs>
     patsopt  <sha256 of the listing of each file's sha256 (sha256sum, or
               shasum -a 256 where it is absent) of bin/patsopt, prelude,
               libats, share and ccomp (cache.bats's toolchain_digest;
               bats-lang/bats#318: cksum's 32 bits missed a change)>
     cc       <sha256 of clang --version and clang -dumpmachine, and of the
               environment clang and the loader read: CPATH, LIBRARY_PATH,
               LD_PRELOAD and the others named in put_cc_environment, each a
               name and its value, digested and not stored (bats#322, #396)>
     libs     <sha256 of the sorted sha256 of each shared library file the
               loader resolves for bin/patsopt (ldd, or otool -L), no path
               (bats-lang/bats#396)>
     link     <sha256 of the linker of the mark: for a native mark the
               linker clang -### names (version and sha256) and the sha256 of
               each file a link reads, sorted, no path; for a wasm mark
               wasm-ld --version (bats-lang/bats#397)>
     flags    <the flag templates patsopt and cc are run with for this
               mark, PATSHOME written $(PATSHOME)>
     mark     <the target and mode digit of build/.bats_target>

   No line holds a path: the C names none (bats-lang/bats#250), the
   listing is of contents, and the flags write PATSHOME as a variable, so
   a build/ copied to another directory, or made on another machine with
   the same bats, ATS2 and C compiler, has the same stamp.

   Format and content are told apart (bats-lang/bats#364). The format is
   the first line, `bats-stamp 2`, and every line after it is a name, a
   space and a value (at least one of each): a line of another shape (a
   `junk` line, a blank one) is a format error, "the stamp format differs".
   A name bats does not know is well formed, so a line `zzz 1` is not a
   format error: the stamp differs from the one this bats writes, and that
   is what is said.

   At the start of a build (after cache_swap, which has put this mark's
   build/ in place, from its stash if it had been put aside), the stamp
   this bats would write is compared with the one in build/. Equal: build/
   is kept. Different or missing: everything in build/ but .stash goes, one
   line on stderr names the first line that differs, and the build starts
   from nothing. A stash carries the stamp of whoever made it (cache_swap
   moves every file of build/ but .bats_valid and .bats_toolchain, the
   toolchain's listing, bats#434), so it is judged when it is swapped in. A
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
   the argument lists in helpers.bats (native_cc_argv, wasm_cc_argv, patsopt_only) and
   build.bats (compile_wasm_runtime, the wasm-ld and link
   commands). The digest of bats's own source is the stamp's first line,
   so a change to the flags there is a change of bats whether or not
   this text follows; this line says which flags a stamp was made with,
   for whoever reads it (flags keyword; `pre` is the preprocessed text the key of an
   object holds, preprocess keyword, bats#477). The profile's choice (-O2, or -g -O0) is in
   the template, since one build/ holds both profiles' work. The text is written by
   put_flags_common and then put_flags_native or put_flags_wasm, in pieces that fit a line. *)
fn put_flags_common (st: !$B.builder_v >> $B.builder_v): void = let
  val () = bput_v(st, "patsopt -IATS build -IATS build/src -IATS build/bats_modules -o OUT -d IN; ")
  val () = bput_v(st, "cc clang -c -o OUT IN [-O2 | -g -O0] -I$(PATSHOME) ")
  val () = bput_v(st, "-I$(PATSHOME)/ccomp/runtime; pre clang -E -P -frewrite-includes -H ")
  val () = bput_v(st, "-o OUT.i WRAP [-O2 | -g -O0] ")
  val () = bput_v(st, "-I$(PATSHOME) -I$(PATSHOME)/ccomp/runtime; ")
in end

fn put_flags_native (st: !$B.builder_v >> $B.builder_v): void = let
  val () = bput_v(st, "runtime clang -c -o build/_bats_native_runtime.o ")
  val () = bput_v(st, "build/_bats_native_runtime.c; link clang -o BIN OBJECTS [-O2 | -g -O0]")
in end

fn put_flags_wasm (st: !$B.builder_v >> $B.builder_v): void = let
  val () = bput_v(st, "wasm cc clang --target=wasm32 -O2 -nostdlib -ffreestanding ")
  val () = bput_v(st, "-fvisibility=default -D_ATS_CCOMP_HEADER_NONE_ ")
  val () = bput_v(st, "-D_ATS_CCOMP_EXCEPTION_NONE_ ")
  val () = bput_v(st, "-D_ATS_CCOMP_PRELUDE_NONE_ -D_ATS_CCOMP_RUNTIME_NONE_ -include ")
  val () = bput_v(st, "build/_bats_wasm_runtime.h -I build/_bats_wasm_stubs ")
  val () = bput_v(st, "-Wno-implicit-function-declaration -Wno-int-conversion -c -o OUT IN; wasm ")
  val () = bput_v(st, "pre the wasm cc with -E -P -frewrite-includes -H -o OUT.i WRAP in place of ")
  val () = bput_v(st, "-c -o OUT; ")
  val () = bput_v(st, "link wasm-ld --no-entry --allow-undefined --lto-O2 -z stack-size=1048576 ")
  val () = bput_v(st, "--initial-memory=16777216 --max-memory=268435456 --export=bats_dynload ")
  val () = bput_v(st, "--export=mainats_0_void --export=malloc -o OUT OBJECTS")
in end

(* The mark is a wasm one: 1, or 3 in check and test mode *)
fn mark_is_wasm (mark: int): bool = (mark = 1 || mark = 3)

(* sh -c script, with args as $1, ...: sh's exit status, -1 when it
   could not be run; its stdout is captured into out and the number of
   its bytes is returned beside the status *)
fn sh_capture {sn:nat}{lo:agz}
  (script: string sn, args: $L.listv($P.arg_entry), out: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k) = let
  val (nul_x | exec) = $P.path_of_string_proved("sh")
  val @(fz_x, bv_x) = $A.barr_freeze(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, script)
  var b4 = $B.create()
  val () = bput_v(b4, "sh")
  val outcome = run_cmd_capture_outcome(nul_x | bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4), args)))), out)
  (* a longer output keeps its first 4096 bytes and the child's own status (capture area) *)
  val r = (case+ outcome of
    | ~CaptureFits(n) => @(0, n)
    | ~CaptureFailed(status, n) => @(status, n)
    | ~CaptureLonger(status, _, _) => @(status, 4096)
    | ~CaptureReadFailed(n, _) => @(~1, n)
    | ~CaptureWaitFailed(n, _, _) => @(~1, n)
    | ~CaptureNotRun(e) => @(0 - e, 0)): @(int, [k:nat | k <= 4096] int k)
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
in r end

(* The sha256 of the file at the path, appended to out; false when it
   cannot be read *)
fn put_file_digest {sn:nat | sn < $B.BUILDER_CAP}
  (path: string sn, out: !$B.builder_v >> $B.builder_v): bool = let
  val @(p, p_len) = str_into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val ok = put_file_sha256_m(bv_p, p_len, out)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in ok end

(* build/.bats_cc: the C compiler's version and target, install paths left out (stamp keyword) *)
fn cc_listed (): bool = let
  val none = $A.alloc<byte>(4096)
  val r = sh_capture("{ clang --version; clang -dumpmachine; } 2>&1 | grep -v -e '^InstalledDir:' -e '^Configuration file:' > build/.bats_cc",
    $L.list_vt_nil(), none)
  val () = $A.free<byte>(none)
in r.0 = 0 end

(* build/.bats_libs: the sha256 of each shared library patsopt loads, sorted, no path (stamp keyword) *)
#define LIBS_SCRIPT "p=\"$1/bin/patsopt\"\nif command -v sha256sum >/dev/null 2>&1; then h=sha256sum; else h='shasum -a 256'; fi\nraw=build/.bats_libs.raw\nrm -f \"$raw\" \"$raw.todo\" \"$raw.new\" \"$raw.known\" \"$raw.sorted\"\nif command -v ldd >/dev/null 2>&1; then\n  ldd \"$p\" > \"$raw\" 2>&1; rc=$?\n  if [ $rc -ne 0 ] && ! grep -q 'not a dynamic' \"$raw\"; then echo \"error: ldd cannot list the shared libraries patsopt loads, so the stamp cannot be made from them\" >&2; exit 1; fi\n  { grep -o '/[^ ]*' \"$raw\" | LC_ALL=C sort -u | while IFS= read -r f; do if [ -f \"$f\" ]; then $h \"$f\"; fi; done | cut -d ' ' -f1 | LC_ALL=C sort; grep 'not found' \"$raw\" | cut -d ' ' -f1 | LC_ALL=C sort; } > build/.bats_libs\nelif command -v otool >/dev/null 2>&1; then\n  printf '%s\\n' \"$p\" > \"$raw.todo\"; : > \"$raw.known\"\n  while [ -s \"$raw.todo\" ]; do\n    : > \"$raw.new\"\n    while IFS= read -r f; do otool -L \"$f\" 2>/dev/null | tail -n +2 | cut -d ' ' -f1 | tr -d '\\t' >> \"$raw.new\"; done < \"$raw.todo\"\n    LC_ALL=C sort -u \"$raw.new\" > \"$raw.sorted\"\n    LC_ALL=C comm -23 \"$raw.sorted\" \"$raw.known\" > \"$raw.todo\"\n    cat \"$raw.todo\" >> \"$raw.known\"; LC_ALL=C sort -u \"$raw.known\" -o \"$raw.known\"\n  done\n  { while IFS= read -r f; do if [ -f \"$f\" ]; then $h \"$f\" | cut -d ' ' -f1; else echo \"no file, system build $(sw_vers -buildVersion 2>/dev/null)\"; fi; done < \"$raw.known\"; } | LC_ALL=C sort -u > build/.bats_libs\nelse\n  echo \"error: neither ldd nor otool is found, so the shared libraries patsopt loads cannot be listed and the stamp cannot be made\" >&2; exit 1\nfi\nrm -f \"$raw\" \"$raw.todo\" \"$raw.new\" \"$raw.known\" \"$raw.sorted\"\n"

fn libs_listed {lph:agz}(ph: !$A.borrow(byte, lph, 12288), phlen: int): bool = let
  var home : $B.builder_v = $B.create()
  val () = copy_to_builder_v(ph, 0, phlen, 12288, home)
  val none = $A.alloc<byte>(4096)
  val r = sh_capture(LIBS_SCRIPT, $L.list_vt_cons(mk_arg(home), $L.list_vt_nil()), none)
  val () = $A.free<byte>(none)
in r.0 = 0 end

(* build/.bats_link: the mark's linker and the files a native link reads, by content (stamp keyword) *)
#define LINK_SCRIPT "if command -v sha256sum >/dev/null 2>&1; then h=sha256sum; else h='shasum -a 256'; fi\nprobe=build/.bats_link_probe\nout=build/.bats_link\nif [ \"$1\" = wasm ]; then\n  wasm-ld --version 2>&1 | grep -v -e '^InstalledDir:' -e '^Configuration file:' > \"$out\"\n  exit $?\nfi\nprintf 'int main (void) { return 0; }\\n' > \"$probe.c\" || exit 1\nclang -c -o \"$probe.o\" \"$probe.c\" || exit 1\nld=$(clang -### -o \"$probe.out\" \"$probe.o\" 2>&1 | grep '^ \"' | tail -n 1 | cut -d '\"' -f 2)\n[ -n \"$ld\" ] || { echo \"error: clang -### does not name the linker of a native link, so the stamp cannot be made from it\" >&2; exit 1; }\nclang -Wl,-t -o \"$probe.out\" \"$probe.o\" > \"$probe.trace\" 2>&1 || { echo \"error: a native link of an empty program fails, so the stamp cannot be made from its inputs\" >&2; cat \"$probe.trace\" >&2; exit 1; }\n{\n  { \"$ld\" --version || \"$ld\" -v; } 2>&1 | grep -v -e '^InstalledDir:' -e '^Configuration file:'\n  $h \"$ld\" | cut -d ' ' -f1\n  grep -o '/[^ ()]*' \"$probe.trace\" | LC_ALL=C sort -u | while IFS= read -r f; do if [ -f \"$f\" ]; then $h \"$f\"; fi; done | cut -d ' ' -f1 | LC_ALL=C sort\n} > \"$out\"\nrm -f \"$probe.c\" \"$probe.o\" \"$probe.out\" \"$probe.trace\"\n"

fn link_listed (mark: int): bool = let
  var which : $B.builder_v = $B.create()
  val () = (if mark_is_wasm(mark) then bput_v(which, "wasm") else bput_v(which, "native"))
  val none = $A.alloc<byte>(4096)
  val r = sh_capture(LINK_SCRIPT, $L.list_vt_cons(mk_arg(which), $L.list_vt_nil()), none)
  val () = $A.free<byte>(none)
in r.0 = 0 end

(* The environment the C compiler reads, whose values change what it makes
   (bats-lang/bats#322). They are digested into the cc line, never stored:
   a build/ made with one value is dropped by a build with another, as by
   another clang. The list is the one place these names are written
   (put_cc_environment). The wasm linker reads none of them: the wasm
   mark's cc line digests the same list only because its C is compiled by
   clang too; the wasm linker's version is in the link line (link keyword).

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
  val na = str_to_exact_arr(name)
  val buf = $A.alloc<byte>(131072)
  val got = $E.get_cstr(na, g1u2i(string1_length(name)) + 1, buf, 131072)
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
  && hash_env_var("LD_LIBRARY_PATH", c)
  && hash_env_var("LD_PRELOAD", c)
  && hash_env_var("LD_AUDIT", c)
  && hash_env_var("LD_BIND_NOW", c)
  && hash_env_var("LD_BIND_NOT", c)
  && hash_env_var("LD_DYNAMIC_WEAK", c)
  && hash_env_var("LD_HWCAP_MASK", c)
  && hash_env_var("LD_ORIGIN_PATH", c)
  && hash_env_var("GLIBC_TUNABLES", c)
  && hash_env_var("DYLD_LIBRARY_PATH", c)
  && hash_env_var("DYLD_FALLBACK_LIBRARY_PATH", c)
  && hash_env_var("DYLD_VERSIONED_LIBRARY_PATH", c)
  && hash_env_var("DYLD_FRAMEWORK_PATH", c)
  && hash_env_var("DYLD_FALLBACK_FRAMEWORK_PATH", c)
  && hash_env_var("DYLD_VERSIONED_FRAMEWORK_PATH", c)
  && hash_env_var("DYLD_INSERT_LIBRARIES", c)
  && hash_env_var("DYLD_IMAGE_SUFFIX", c)
  && hash_env_var("DYLD_ROOT_PATH", c)

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

(* The sha256 of build/.bats_libs (stamp keyword) *)
fn put_libs_digest (out: !$B.builder_v >> $B.builder_v): bool = put_file_digest("build/.bats_libs", out)

(* The sha256 of build/.bats_link (stamp keyword) *)
fn put_link_digest (out: !$B.builder_v >> $B.builder_v): bool = put_file_digest("build/.bats_link", out)

(* The script that judges build/ against build/.bats_stamp.new, the stamp
   this bats would write, with the mark's digit as $1. Nothing to judge
   (no .bats_target and no stamp): the new stamp is put in place. Else
   the first of the format, the lines in order, and the mark that
   differs is named on stdout, and build/ but its stash goes. *)
#define JUDGE "cd build || exit 1\nif [ ! -f .bats_target ] && [ ! -f .bats_stamp ]; then mv -f .bats_stamp.new .bats_stamp; exit 0; fi\nwhy=\nif [ ! -f .bats_stamp ]; then why='no stamp'\nelif [ \"$(sed -n 1p .bats_stamp)\" != 'bats-stamp 2' ] || sed -n '2,$p' .bats_stamp | grep -q -v -E '^[^ ]+ .+$'; then why='the stamp format differs'\nelse\n  for n in bats patsopt cc libs link flags mark; do\n    a=$(sed -n \"s/^$n //p\" .bats_stamp); b=$(sed -n \"s/^$n //p\" .bats_stamp.new)\n    if [ \"$a\" != \"$b\" ]; then why=\"$n differs\"; break; fi\n  done\nfi\nif [ -z \"$why\" ] && [ \"$(cat .bats_target 2>/dev/null)\" != \"$1\" ]; then why='mark differs'; fi\nif [ -z \"$why\" ] && ! cmp -s .bats_stamp .bats_stamp.new; then why='the stamp differs'; fi\nif [ -n \"$why\" ]; then\n  echo \"bats: dropping build/ (made by another bats: $why)\"\n  find . -mindepth 1 -maxdepth 1 ! -name .stash ! -name .bats_valid ! -name .bats_stamp.new -exec rm -rf {} +\n  mkdir -p src/bin bats_modules\nfi\nmv -f .bats_stamp.new .bats_stamp\n"

(* What became of the stamp this bats would write for the mark, into
   build/.bats_stamp.new: written; a part of it could not be had (said
   already); or the file could not be written (said, with the reason) *)
datatype stamp_made =
  | StampMade
  | StampPartMissing
  | StampNotWritten

fn stamp_write {lph:agz}
  (ph: !$A.borrow(byte, lph, 12288), phlen: int, mark: int): stamp_made = let
  var st : $B.builder_v = $B.create()
  val () = bput_v(st, "bats-stamp 2\nbats ")
  val () = bput_v(st, bats_inputs_sha256())
  val () = bput_v(st, "\npatsopt ")
  val tool = toolchain_digest(ph, phlen, st)
  val () = bput_v(st, "\ncc ")
  val cc = (if cc_listed() then put_cc_digest(st) else false): bool
  val () = bput_v(st, "\nlibs ")
  val libs = (if libs_listed(ph, phlen) then put_libs_digest(st) else false): bool
  val () = bput_v(st, "\nlink ")
  val link = (if link_listed(mark) then put_link_digest(st) else false): bool
  val () = bput_v(st, "\nflags ")
  val () = (let val () = put_flags_common(st) in
    if mark_is_wasm(mark) then put_flags_wasm(st) else put_flags_native(st) end)
  val () = bput_v(st, "\nmark ")
  val () = put_int_v(st, mark)
  val () = put_char_v(st, 10)
  val ok = (if tool && libs && cc && link then true else false): bool
  val @(p, p_len) = str_into_arr("build/.bats_stamp.new")
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val stv = st
  val made = (if ok then
      (if write_settle(bv_p, p_len, write_file_from_builder_m(bv_p, p_len, stv)) = 0 then StampMade() else StampNotWritten())
    else let val () = $B.builder_free(stv) in StampPartMissing() end): stamp_made
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in made end

#pub fn stamp_check {lph:agz}
  (ph: !$A.borrow(byte, lph, 12288), phlen: int, mark: int): void

implement stamp_check (ph, phlen, mark) =
  case+ stamp_write(ph, phlen, mark) of
  | StampPartMissing() => let
    val () = set_build_err()
  in prerr! ("error: the stamp of build/ (bats, the toolchain and the C compiler) cannot be made: a part of it could not be read (the C compiler's version or environment, patsopt's shared libraries or the linker; a message above says which)\n") end
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
