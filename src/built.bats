(* built -- the commit this bats is built from, as a module bats writes
   (bats-lang/bats#575; keyword: built-commit).

   A module that staloads "_bats_built.sats" gets build/src/_bats_built
   (.sats and .dats), which every module may staload, as any module of
   src/:

     datavtype built_commit = BuiltFrom of string 40 | BuiltUnnamed of ()
     fun bats_built_commit (): built_commit

   BuiltFrom carries the full SHA of the commit BATS_COMMIT names (any
   revision git takes) in the build's directory; BuiltUnnamed is the build
   made with BATS_COMMIT unset or empty. The commit is a fact of the build,
   not of the sources: bootstrap/c is made with BATS_COMMIT unset
   (scripts/bootstrap-c.sh), so it is the same for every commit (a commit
   cannot name itself), and a compiler built from it is unnamed until it
   builds itself with BATS_COMMIT set. The .sats holds declarations only and
   never changes, so only the .dats changes with the commit, written when its
   bytes change, and with it one small module is compiled again. A project
   that does not name it gets none, and runs no git. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use list as L
#use result as R

staload "helpers.sats"
staload "pins.sats"

(* Whether a module of src/ staloads the built commit: a staload, aliased or
   not, of "_bats_built.sats" (or "./_bats_built.sats"). The name merely
   written in a comment or a string is not a staload of it: bats's own
   sources write it. grep reads src/ itself, so no shell is run. *)
fn built_named (): bool = let
  val out = $A.alloc<byte>(4096)
  val @(status, _) = tool_output("grep",
    $L.list_vt_cons(literal_arg("-r"), $L.list_vt_cons(literal_arg("-q"), $L.list_vt_cons(literal_arg("-E"),
    $L.list_vt_cons(literal_arg("--include=*.bats"), $L.list_vt_cons(literal_arg("-e"),
    $L.list_vt_cons(literal_arg("staload[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*)?\"(\\./)?_bats_built\\.sats\""),
    $L.list_vt_cons(literal_arg("src"), $L.list_vt_nil()))))))), out)
  val () = $A.free<byte>(out)
in status = 0 end

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

(* Writes build/src/_bats_built.sats and .dats, the .dats ending in body (consumed): the text
   after "implement bats_built_commit () = ". Each only when its bytes change; the .sats, which
   never changes, stamps a .sats change the first time, before it is written. *)
fn emit (body: $B.builder_v): void = let
  var sats : $B.builder_v = $B.create()
  val () = bput_v(sats, "(* _bats_built -- the commit this build is made from, written by bats\n")
  val () = bput_v(sats, "   (bats-lang/bats#575); never edited: it is the same for every commit *)\n\n")
  val () = bput_v(sats, "(* the full SHA of the commit BATS_COMMIT named, 40 hex digits, or that it was unset *)\n")
  val () = bput_v(sats, "datavtype built_commit =\n  | BuiltFrom of (string 40)\n  | BuiltUnnamed of ()\n\n")
  val () = bput_v(sats, "fun bats_built_commit (): built_commit\n")
  val sats_new = write_sats_changed("build/src/_bats_built.sats", sats)
  (* the stamp, then the .sats, then the .dats, as build.bats (stamp, write errors): a write
     that fails is said and stops the module, so nothing after it is written *)
  val sats_ok = (case+ sats_new of
    | FileWritten() => true
    | FileSame() => true
    (* said by write_sats_changed *)
    | FileNotWritten() => false): bool
  var dats : $B.builder_v = $B.create()
  val () = bput_v(dats, "(* _bats_built -- written by bats from the commit it names *)\n\n")
  val () = bput_v(dats, "#include \"share/atspre_staload.hats\"\n\n")
  val () = bput_v(dats, "staload \"./_bats_built.sats\"\n\n")
  val () = bput_v(dats, "implement bats_built_commit () = ")
  val () = append_builder(dats, body)
in dats_when(sats_ok, "build/src/_bats_built.dats", dats) end

(* BATS_COMMIT is set: git's full SHA of the commit it names (name, which holds it, is consumed).
   A revision git does not know is an error that says so. *)
fn emit_named (name: $B.builder_v): void = let
  var revision = name
  val () = bput_v(revision, "^{commit}")
  val out = $A.alloc<byte>(4096)
  val @(status, kept) = tool_output("git",
    $L.list_vt_cons(literal_arg("rev-parse"), $L.list_vt_cons(literal_arg("--verify"), $L.list_vt_cons(literal_arg("--quiet"),
    $L.list_vt_cons(mk_arg(revision), $L.list_vt_nil())))), out)
  val @(fz_out, bv_out) = $A.freeze<byte>(out)
in
  if (status = 0) && (kept = 41) && all_hex(bv_out, 0, 40, 4096) && (peek(bv_out, 40, 4096) = 10) then let
    var body : $B.builder_v = $B.create()
    val () = bput_v(body, "BuiltFrom (\"")
    val () = copy_to_builder_v(bv_out, 0, 40, 4096, body)
    val () = bput_v(body, "\")\n")
    val () = emit(body)
    val () = $A.drop<byte>(fz_out, bv_out)
  in $A.free<byte>($A.thaw<byte>(fz_out)) end
  else let
    val () = $A.drop<byte>(fz_out, bv_out)
    val () = $A.free<byte>($A.thaw<byte>(fz_out))
    val () = prerr! ("error: src/ staloads _bats_built.sats, the commit the build is made from, but git names no commit for BATS_COMMIT: set it to a commit of this repository, or unset it\n")
  in set_build_err() end
end

(* The module for BATS_COMMIT: set, name holds it; else name is empty *)
fn emit_for (name: $B.builder_v, set: bool): void =
  if set then emit_named(name)
  else let
    val () = $B.builder_free(name)
    var body : $B.builder_v = $B.create()
    val () = bput_v(body, "BuiltUnnamed ()\n")
  in emit(body) end

(* Writes build/src/_bats_built.sats and .dats when a module names them, or removes them, with
   their C and object, when none does (a stale object would be linked). *)
#pub fn write_built (): void

implement write_built () =
  if ~built_named() then let
    val out = $A.alloc<byte>(4096)
    val _ = tool_output("rm",
      $L.list_vt_cons(literal_arg("-f"), $L.list_vt_cons(literal_arg("build/src/_bats_built.sats"),
      $L.list_vt_cons(literal_arg("build/src/_bats_built.dats"), $L.list_vt_cons(literal_arg("build/src/_bats_built_dats.c"),
      $L.list_vt_cons(literal_arg("build/src/_bats_built_dats.o"), $L.list_vt_nil()))))), out)
  in $A.free<byte>(out) end
  else let
    var name : $B.builder_v = $B.create()
    val set = env_value("BATS_COMMIT", name)
  in emit_for(name, set) end
