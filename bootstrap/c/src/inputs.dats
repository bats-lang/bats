staload "./inputs.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
staload "sha256/src/lib.dats"
(* inputs -- what a build is made from, as a module bats writes
   (bats-lang/bats#267).

   A module that staloads "_bats_inputs.sats" gets build/src/_bats_inputs
   (.sats and .dats), which every module may staload, as any module of
   src/:

     fun bats_inputs_sha256 (): string 64

   It is the sha256, as 64 lowercase hex digits, of a listing of the
   project's own inputs: the line "bats-inputs 1", then a line "<path>
   <sha256 of the file>" for bats.toml, for bats.lock when there is one,
   and for every src/**/*.bats, in byte order of path (LC_ALL=C sort). It
   reads no git and no clock: the same bytes give the same digest in any
   directory, with any mtimes, at any commit, and a dirty tree has an
   honest one. The dependencies' archives are named in bats.lock by their
   sha256, so the lock stands for them. The .sats holds declarations only
   and never changes, so only the .dats changes with the inputs, written
   when its bytes change, and with it one small module is compiled again.
   A project that does not name it gets none, and runs nothing. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"
staload SHA = "sha256/src/lib.sats"

staload "helpers.sats"

(* sh -c script with the arguments: its exit status *)
fn sh_run {sn:nat} (script: string sn, args: $L.listv($P.arg_entry)): int = let
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
  val rc = run_cmd(nul_x | bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4), args)))))
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
in rc end

(* Whether a module of src/ staloads the inputs: a staload, aliased or
   not, of the module's .sats (or with "./" before it). The name merely
   written in a comment or a string is not a staload of it: bats's own
   sources write it. *)
fn inputs_named (): bool = let
  val rc = sh_run("cat src/*.bats src/bin/*.bats 2>/dev/null | grep -q -E 'staload[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*)?\"(\\./)?_bats_inputs\\.sats\"'", $L.list_vt_nil())
in rc = 0 end

(* The sha256 of the file at the path in b, appended to out; b is
   consumed. false when the file cannot be read. *)
fn put_path_sha256 (b: $B.builder_v, out: !$B.builder_v >> $B.builder_v): bool = let
  var p = b
  val () = put_char_v(p, 0)
  val @(pa, pal) = $B.into_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val ok = put_file_sha256_m(bv_p, pal, out)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in ok end

(* Each line of c[i, n), a path, appended to key with the sha256 of its
   file; line holds the bytes of the line read so far. false when a file
   cannot be read or the listing does not end with a newline. *)
fun add_lines {l:agz}{m:pos}{i:nat} .<max(m - i, 0)>.
  (c: !$A.borrow(byte, l, m), i: int i, n: int, m: int m,
   line: $B.builder_v, key: !$B.builder_v >> $B.builder_v, ok: bool): bool =
  if i >= m then let
    val () = $B.builder_free(line)
  in false end
  else if i >= n then
    (if $B.length(line) > 0 then let
       val () = $B.builder_free(line)
     in false end
     else let val () = $B.builder_free(line) in ok end)
  else let
    val b = byte2int0($A.read<byte>(c, i))
  in
    if b = 10 then let
      var path : $B.builder_v = $B.create()
      val () = append_builder(path, line)
      val @(pa, pl) = $B.into_arr(path)
      val @(fz_pa, bv_pa) = $A.freeze<byte>(pa)
      val () = copy_to_builder_v(bv_pa, 0, pl, pl, key)
      val () = put_char_v(key, 32)
      var again : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_pa, 0, pl, pl, again)
      val () = $A.drop<byte>(fz_pa, bv_pa)
      val () = $A.free<byte>($A.thaw<byte>(fz_pa))
      val hashed = put_path_sha256(again, key)
      val () = put_char_v(key, 10)
    in add_lines(c, i + 1, n, m, $B.create(), key, ok && hashed) end
    else let
      var more = line
      val () = put_char_v(more, b)
    in add_lines(c, i + 1, n, m, more, key, ok) end
  end

(* Whether the project's inputs could be listed and read, and their
   digest, 64 hex digits *)
fn inputs_digest (): @(bool, $B.builder_v) = let
  var hex : $B.builder_v = $B.create()
  var a1 : $B.builder_v = $B.create()
  val () = bput_v(a1, "build/.bats_inputs")
  val rc = sh_run("{ echo bats.toml; if [ -f bats.lock ]; then echo bats.lock; fi; find src -type f -name '*.bats'; } | LC_ALL=C sort > \"$1\"",
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_nil()))
  var key : $B.builder_v = $B.create()
  val () = bput_v(key, "bats-inputs 1\n")
  val read = (if rc <> 0 then false
    else let
      val @(lp, lp_len) = str_into_arr("build/.bats_inputs")
      val @(fz_lp, bv_lp) = $A.freeze<byte>(lp)
      val r = (case+ read_whole_m(bv_lp, lp_len) of
        | ~whole_err(_) => false
        | ~whole_ok(ar, piece, m, n) => let
            val @(fz_c, bv_c) = $A.freeze<byte>(piece)
            val ok = add_lines(bv_c, 0, n, m, $B.create(), key, n > 0)
            val () = $A.drop<byte>(fz_c, bv_c)
            val () = whole_free(ar, $A.thaw<byte>(fz_c))
          in ok end): bool
      val () = $A.drop<byte>(fz_lp, bv_lp)
      val () = $A.free<byte>($A.thaw<byte>(fz_lp))
    in r end): bool
  var a2 : $B.builder_v = $B.create()
  val () = bput_v(a2, "build/.bats_inputs")
  val _ = sh_run("rm -f \"$1\"", $L.list_vt_cons(mk_arg(a2), $L.list_vt_nil()))
  (* a listing past the builder's size would have lost bytes *)
  val whole = $B.length(key) < 524288
  val @(ka, kl) = $B.into_arr(key)
  val c = $SHA.proved_init()
  val () = $SHA.proved_update(c, ka, kl)
  val () = $A.free<byte>(ka)
  val digest = $A.alloc<byte>(64)
  val () = $SHA.proved_finish(c, digest)
  val @(fz_d, bv_d) = $A.freeze<byte>(digest)
  val () = copy_to_builder_v(bv_d, 0, 64, 64, hex)
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
in @(read && whole, hex) end

(* Writes build/src/_bats_inputs.sats and .dats when a module names
   them (each only when its bytes change; the .sats, which never
   changes, stamps a .sats change the first time, before it is written), or removes them, with
   their C and object, when none does (a stale object would be linked).
   A file that cannot be read is an error, which says so. *)


implement write_inputs () =
  if ~inputs_named() then let
    val _ = sh_run("rm -f build/src/_bats_inputs.sats build/src/_bats_inputs.dats build/src/_bats_inputs_dats.c build/src/_bats_inputs_dats.o", $L.list_vt_nil())
  in () end
  else let
    val @(good, hex) = inputs_digest()
  in
    if ~good then let
      val () = $B.builder_free(hex)
      val () = prerr! ("error: src/ names _bats_inputs.sats, the digest of the project's inputs, but bats.toml, bats.lock or a file of src/ cannot be listed or read\n")
    in set_build_err() end
    else let
      var sats : $B.builder_v = $B.create()
      val () = bput_v(sats, "(* _bats_inputs -- the digest of what this build is made from, written by bats\n")
      val () = bput_v(sats, "   (bats-lang/bats#267); never edited: it is the same for every input *)\n\n")
      val () = bput_v(sats, "(* the sha256 of bats.toml, bats.lock and every src/**.bats, 64 hex digits *)\n")
      val () = bput_v(sats, "fun bats_inputs_sha256 (): string 64\n")
      val sats_new = write_sats_changed("build/src/_bats_inputs.sats", sats)
      (* the stamp, then the .sats, then the .dats, as build.bats (stamp, write errors): a write
         that fails is said and stops the module, so nothing after it is written *)
      val sats_ok = (case+ sats_new of
        | FileWritten() => true
        | FileSame() => true
        (* said by write_sats_changed *)
        | FileNotWritten() => false): bool
      var dats : $B.builder_v = $B.create()
      val () = bput_v(dats, "(* _bats_inputs -- written by bats from the inputs it names *)\n\n")
      val () = bput_v(dats, "#include \"share/atspre_staload.hats\"\n\n")
      val () = bput_v(dats, "staload \"./_bats_inputs.sats\"\n\n")
      val () = bput_v(dats, "implement bats_inputs_sha256 () = \"")
      val () = append_builder(dats, hex)
      val () = bput_v(dats, "\"\n")
      val () = dats_when(sats_ok, "build/src/_bats_inputs.dats", dats)
    in () end
  end
