staload "./affected.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* affected -- bats affected <base> <head>: whether a change reaches nothing the heavy jobs of CI build or test (bats-lang/bats#481; keyword: affected rule) *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"
staload "pins.sats"

(* ------------------------------------------------------------------ *)
(* THE INERT PATHS (keyword: affected rule), the one place that names
   them. A change is inert when every path it touches is a *.md file that
   is not under tests/ or bootstrap/ (the rules in .claude/rules, README.md,
   CLAUDE.md): nothing the compiler, its tests, bootstrap/c or the workflow
   reads. They are git pathspecs, compared by git as globs, never parsed
   here. Pass 1 lists the changed paths that are not *.md files; pass 2
   lists the changed *.md files under the two directories that are read. *)

fn pathspecs_outside_markdown (): $L.listv($P.arg_entry) =
  $L.list_vt_cons(literal_arg(":/"),
  $L.list_vt_cons(literal_arg(":(top,exclude,glob)**/*.md"), $L.list_vt_nil()))

fn pathspecs_markdown_that_is_read (): $L.listv($P.arg_entry) =
  $L.list_vt_cons(literal_arg(":(top,glob)tests/**/*.md"),
  $L.list_vt_cons(literal_arg(":(top,glob)bootstrap/**/*.md"), $L.list_vt_nil()))

(* ------------------------------------------------------------------ *)

(* The pathspecs of a pass: 0 none (every changed path), 1 the paths outside
   the markdown files, 2 the markdown files that are read *)
fn pathspecs_of_pass (pass: int): $L.listv($P.arg_entry) =
  if pass = 1 then pathspecs_outside_markdown()
  else if pass = 2 then pathspecs_markdown_that_is_read()
  else $L.list_vt_nil()

(* cmd[from, to) as an argument for the process package *)
fn copy_arg {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), from: pos_t, to: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, from, to, 4096, b)
in mk_arg(b) end

(* How many of the paths changed from base to head a pass lists: 0 none, 1 some,
   2 when git did not answer (it failed, or did not run). A list longer than
   git's first 4096 bytes is some. Renames are listed as a delete and an add
   (--no-renames), so a file moved out of an inert path is seen at both ends *)
fn changed_by_pass {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), base_at: pos_t, base_to: int, head_at: pos_t, head_to: int,
   pass: int): int = let
  val (nul_git | git_exec) = $P.path_of_string_proved("git")
  val @(fz_git, bv_git) = $A.barr_freeze(git_exec)
  val argv = $L.list_vt_cons(literal_arg("git"), $L.list_vt_cons(literal_arg("diff"),
    $L.list_vt_cons(literal_arg("--name-only"), $L.list_vt_cons(literal_arg("--no-renames"),
    $L.list_vt_cons(literal_arg("-z"), $L.list_vt_cons(copy_arg(cmd, base_at, base_to),
    $L.list_vt_cons(copy_arg(cmd, head_at, head_to), $L.list_vt_cons(literal_arg("--"),
    pathspecs_of_pass(pass)))))))))
  val out = $A.alloc<byte>(4096)
  val outcome = run_cmd_capture_outcome(nul_git | bv_git, argv, out)
  val answer = (case+ outcome of
    | ~CaptureFits(n) => (if n = 0 then 0 else 1)
    | ~CaptureFailed(_, _) => 2
    | ~CaptureLonger(status, _) => (if status = 0 then 1 else 2)
    | ~CaptureReadFailed(_, _, _) => 2
    | ~CaptureNotRun(_) => 2): int
  val () = $A.free<byte>(out)
  val () = $A.cborrow_drop(fz_git, bv_git)
  val () = $A.barr_free($A.barr_thaw(fz_git))
in answer end

(* Says why on stderr and the verdict on stdout, as a line a CI step appends to its output file *)
fn verdict (inert: bool, why: string): void = let
  val () = prerr! ("bats affected: ")
  val () = prerr! (why)
  val () = prerr_newline()
in
  if inert then println! ("inert=true") else println! ("inert=false")
end

(* The verdict for the change cmd[base_at, base_to) to cmd[head_at, head_to): inert
   only when something changed, nothing outside the markdown files did, and no
   markdown file under tests/ or bootstrap/ did. Anything else, git failing
   included, is not inert: the whole check runs *)
fn decide {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), base_at: pos_t, base_to: int, head_at: pos_t, head_to: int): void = let
  val changed = changed_by_pass(cmd, base_at, base_to, head_at, head_to, 0)
in
  if changed = 2 then verdict(false, "git could not list the change; the whole check runs")
  else if changed = 0 then verdict(false, "no path changed; the whole check runs")
  else let
    val outside = changed_by_pass(cmd, base_at, base_to, head_at, head_to, 1)
  in
    if outside = 2 then verdict(false, "git could not list the change; the whole check runs")
    else if outside = 1 then verdict(false, "a path outside the markdown files changed; the whole check runs")
    else let
      val read = changed_by_pass(cmd, base_at, base_to, head_at, head_to, 2)
    in
      if read = 2 then verdict(false, "git could not list the change; the whole check runs")
      else if read = 1 then verdict(false, "a markdown file under tests/ or bootstrap/ changed; the whole check runs")
      else verdict(true, "only markdown files outside tests/ and bootstrap/ changed; only the cheap jobs run")
    end
  end
end

fn usage_error (): void = let
  val () = prerr! ("usage: bats affected <base> <head> (two revisions, neither starting with -)")
  val () = prerr_newline()
in set_exit_code(2) end

(* Where the arguments after affected start, or ~1 when argv[1] is not affected *)
fn arguments_at {l:agz}{t:nat | t <= 4096} (cmd: !$A.borrow(byte, l, 4096), total: int t)
  : [r:int | r == ~1 || (0 <= r && r <= 4096)] int r = let
  val a = find_nul(cmd, 0) + 1
in
  if a > 4096 then ~1
  else let
    val z = find_nul(cmd, a)
  in
    if z - a <> 8 then ~1
    else if z + 1 > 4096 then ~1
    else if named_file(cmd, a, z, "affected", 8) then z + 1
    else ~1
  end
end

(* Reads the two revisions cmd[first, ...) and decides; anything but exactly two
   non-empty arguments that do not start with - (git would take one for an option)
   is a usage error *)
fn run_affected {l:agz}{first:nat | first <= 4096}
  (cmd: !$A.borrow(byte, l, 4096), first: int first, total: int): void = let
  val base_to = find_nul(cmd, first)
in
  if base_to + 1 > 4096 then usage_error()
  else let
    val head_at = base_to + 1
    val head_to = find_nul(cmd, head_at)
  in
    if base_to = first then usage_error()
    else if head_to = head_at then usage_error()
    else if head_to + 1 <> total then usage_error()
    else if byte2int0($A.read<byte>(cmd, first)) = 45 then usage_error()
    else if byte2int0($A.read<byte>(cmd, head_at)) = 45 then usage_error()
    else decide(cmd, first, base_to, head_at, head_to)
  end
end

(* Runs bats affected when that is the command given and answers true; false for any other command *)


implement affected_main () = let
  val buf = $A.alloc<byte>(4096)
  val read = $E.args_read(buf, 4096)
  val @(fz, cmd) = $A.freeze<byte>(buf)
  val handled = (case+ read of
    | ~$R.none() => false
    | ~$R.some(total) => let
        val first = arguments_at(cmd, total)
      in
        if first < 0 then false
        else let
          val () = (if total >= 4096 then let
              val () = prerr! ("error: bats affected: the command line is longer than 4095 bytes")
              val () = prerr_newline()
            in set_exit_code(2) end
            else if first >= total then usage_error()
            else run_affected(cmd, first, total))
        in true end
      end): bool
  val () = $A.drop<byte>(fz, cmd)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
