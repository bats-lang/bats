(* facts -- the commit a build is made from, as a module bats writes
   (bats-lang/bats#250).

   A module that staloads "_bats_facts.sats" gets build/src/_bats_facts
   (.sats and .dats), which every module may staload, as any module of
   src/:

     fun bats_commit_time (): int        committer time, seconds since 1970
     fun bats_commit_version (): string  YEAR.MONTH.DAY.SECONDS of it in UTC,
                                         as bats versions a package
     fun bats_commit_short (): string 7  the first 7 hex digits of its SHA
     fun bats_commit_sha (): string 40

   The commit is BATS_COMMIT when set (any revision git takes; CI names a
   pull request's head with it), else HEAD. The values are the commit's,
   never the build's: one commit gives the same bytes on any machine and
   in any time zone. The .sats holds declarations only and never changes,
   so nothing that staloads it is ever checked again for a new commit:
   only the .dats changes, written when its bytes change, and with it one
   small module is compiled again. A project that does not name it gets
   none, and runs no git. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use list as L
#use process as P
#use result as R

staload "helpers.sats"

(* bv[0, n) as a builder *)
fn builder_of {l:agz}{nb:pos}{n:nat | n <= nb} (bv: !$A.borrow(byte, l, nb), n: int n): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, 0, n, n, b)
in b end

(* Writes b to the path when the file does not hold exactly its bytes:
   what became of it (file_changed); b is consumed *)
fn write_changed {sn:nat | sn < $B.BUILDER_CAP} (path: string sn, b: $B.builder_v): file_changed = let
  val @(p, pl) = str_into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val @(ba, bl) = $B.into_arr(b)
  val @(fz_b, bv_b) = $A.freeze<byte>(ba)
  val same = file_has_bytes_m(bv_p, pl, bv_b, bl)
  val again = builder_of(bv_b, bl)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
  val wrote = (if same then let
      val () = $B.builder_free(again)
    in FileSame() end
    else (if write_settle(bv_p, pl, write_file_from_builder_m(bv_p, pl, again)) = 0 then FileWritten()
      else FileNotWritten())): file_changed
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in wrote end

(* The .dats of the .sats just written: written when that .sats is in place
   (sats_ok), else b is given back, so nothing follows a failed write *)
fn dats_when {sn:nat | sn < $B.BUILDER_CAP} (sats_ok: bool, path: string sn, b: $B.builder_v): void =
  if sats_ok then let
    val _ = write_changed(path, b)
  in end
  else $B.builder_free(b)

(* sh -c script, its stdout into out: its exit status and the length *)
fn sh_capture {sn:nat}{lo:agz} (script: string sn, out: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k) = let
  val exec = str_to_path_arr("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, script)
  val r = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))), out)
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in r end

(* Whether a module of src/ staloads the facts: a staload, aliased or
   not, of "_bats_facts.sats" (or "./_bats_facts.sats"). The name merely
   written in a comment or a string is not a staload of it: bats's own
   sources write it, and a build that made facts of them would differ
   from commit to commit. *)
fn facts_named (): bool = let
  val out = $A.alloc<byte>(4096)
  val @(rc, _) = sh_capture("cat src/*.bats src/bin/*.bats 2>/dev/null | grep -q -E 'staload[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*)?\"(\\./)?_bats_facts\\.sats\"'", out)
  val () = $A.free<byte>(out)
in rc = 0 end

(* Whether c[i, e) is all lowercase hex digits *)
fun all_hex {l:agz}{n:pos}{i:int} .<max(n - i, 0)>.
  (c: !$A.borrow(byte, l, n), i: int i, e: int, n: int n): bool =
  if i >= e then true
  else if i >= n then false
  else let
    val b = peek(c, i, n)
  in
    if (b >= 48 && b <= 57) || (b >= 97 && b <= 102) then all_hex(c, i + 1, e, n)
    else false
  end

(* The first newline in c[i, k), or k *)
fun line_end {l:agz}{n:pos}{i,k:nat} .<max(n - i, 0)>.
  (c: !$A.borrow(byte, l, n), i: int i, k: int k, n: int n): [r:nat] int r =
  if i >= k then k
  else if i >= n then i
  else if peek(c, i, n) = 10 then i
  else line_end(c, i + 1, k, n)

(* Writes build/src/_bats_facts.sats and .dats when a module names them
   (each only when its bytes change; the .sats, which never changes,
   stamps a .sats change the first time), or removes them when none
   does. A commit git cannot name is an error, which says so. *)
#pub fn write_facts (): void

implement write_facts () =
  if ~facts_named() then let
    val exec = str_to_path_arr("rm")
    val @(fz_x, bv_x) = $A.freeze<byte>(exec)
    var b1 = $B.create()
    val () = bput_v(b1, "rm")
    var b2 = $B.create()
    val () = bput_v(b2, "-f")
    var b3 = $B.create()
    val () = bput_v(b3, "build/src/_bats_facts.sats")
    var b4 = $B.create()
    val () = bput_v(b4, "build/src/_bats_facts.dats")
    val _ = run_cmd(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
      $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4), $L.list_vt_nil())))))
    val () = $A.drop<byte>(fz_x, bv_x)
  in $A.free<byte>($A.thaw<byte>(fz_x)) end
  else let
    (* the committer time, then the full SHA, of the commit *)
    val out = $A.alloc<byte>(4096)
    val @(rc, k) = sh_capture("git log -1 --format='%ct%n%H' \"${BATS_COMMIT:-HEAD}\" -- 2>/dev/null", out)
    val seconds = parse_decimal(out, k, 4096)
    val @(fz_o, bv_o) = $A.freeze<byte>(out)
    val e1 = line_end(bv_o, 0, k, 4096)
    val s0 = e1 + 1
    val e2 = line_end(bv_o, s0, k, 4096)
    val good = (rc = 0) && (e1 > 0) && (e2 - s0 = 40) && all_hex(bv_o, s0, e2, 4096) && (seconds >= 0)
  in
    if ~good then let
      val () = $A.drop<byte>(fz_o, bv_o)
      val () = $A.free<byte>($A.thaw<byte>(fz_o))
      val () = prerr! ("error: src/ staloads _bats_facts.sats, the commit the build is made from, but git names no commit here (BATS_COMMIT, else HEAD): build from a git repository, or set BATS_COMMIT to a commit of one\n")
    in set_build_err() end
    else let
      val @(year, month, day, secs) = timestamp_to_calver(seconds)
      var sats : $B.builder_v = $B.create()
      val () = bput_v(sats, "(* _bats_facts -- the commit this build is made from, written by bats\n")
      val () = bput_v(sats, "   (bats-lang/bats#250); never edited: it is the same for every commit *)\n\n")
      val () = bput_v(sats, "(* the committer time, in seconds since 1970 *)\n")
      val () = bput_v(sats, "fun bats_commit_time (): int\n\n")
      val () = bput_v(sats, "(* the committer time in UTC, YEAR.MONTH.DAY.SECONDS, as bats versions a package *)\n")
      val () = bput_v(sats, "fun bats_commit_version (): [n:pos | n < 32] string n\n\n")
      val () = bput_v(sats, "(* the first 7 hex digits of the commit's SHA *)\n")
      val () = bput_v(sats, "fun bats_commit_short (): string 7\n\n")
      val () = bput_v(sats, "(* the commit's SHA, 40 hex digits *)\n")
      val () = bput_v(sats, "fun bats_commit_sha (): string 40\n")
      val sats_new = write_changed("build/src/_bats_facts.sats", sats)
      (* the stamp of a changed .sats, and the .dats only once the .sats is in
         place: a stamp that cannot be written is said by touch_sats_stamp
         (write_settle, which fails the build), and nothing after a failed
         write is written (write-errors.md) *)
      val sats_ok = (case+ sats_new of
        | FileWritten() => touch_sats_stamp() = 0
        | FileSame() => true
        (* said by write_changed *)
        | FileNotWritten() => false): bool
      var dats : $B.builder_v = $B.create()
      val () = bput_v(dats, "(* _bats_facts -- written by bats from the commit it names *)\n\n")
      val () = bput_v(dats, "#include \"share/atspre_staload.hats\"\n\n")
      val () = bput_v(dats, "staload \"./_bats_facts.sats\"\n\n")
      val () = bput_v(dats, "implement bats_commit_time () = ")
      val () = put_int_v(dats, seconds)
      val () = bput_v(dats, "\nimplement bats_commit_version () = \"")
      val () = put_int_v(dats, year)
      val () = put_char_v(dats, 46)
      val () = put_int_v(dats, month)
      val () = put_char_v(dats, 46)
      val () = put_int_v(dats, day)
      val () = put_char_v(dats, 46)
      val () = put_int_v(dats, secs)
      val () = bput_v(dats, "\"\nimplement bats_commit_short () = \"")
      val () = copy_to_builder_v(bv_o, s0, s0 + 7, 4096, dats)
      val () = bput_v(dats, "\"\nimplement bats_commit_sha () = \"")
      val () = copy_to_builder_v(bv_o, s0, e2, 4096, dats)
      val () = bput_v(dats, "\"\n")
      val () = dats_when(sats_ok, "build/src/_bats_facts.dats", dats)
      val () = $A.drop<byte>(fz_o, bv_o)
    in $A.free<byte>($A.thaw<byte>(fz_o)) end
  end
