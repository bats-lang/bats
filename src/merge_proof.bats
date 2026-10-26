(* merge_proof -- bats merge-proof <reviewed> <head>: whether the head is the reviewed head plus a merge of main (bats-lang/bats#530; keyword: merge-proof) *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use list as L
#use process as P
#use result as R

staload "helpers.sats"
staload "pins.sats"

(* ------------------------------------------------------------------ *)
(* Arguments for the process package (keyword: merge-proof) *)

(* A word of the command, then the rest *)
fn word {sn:nat | sn < $B.BUILDER_CAP}
  (s: string sn, rest: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  $L.list_vt_cons(literal_arg(s), rest)

(* lead, bv[from, to) and ending as one argument *)
fn wrapped_arg {lb:agz}{pn,sn:nat}
  (lead: string pn, bv: !$A.borrow(byte, lb, 4096), from: pos_t, to: int, ending: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, lead)
  val () = copy_to_builder_v(bv, from, to, 4096, b)
  val () = bput_v(b, ending)
in mk_arg(b) end

(* The file of a diff in the git directory dir[0, dir_to): lead, dir, "/merge-proof-", the commit sha[sha_at, sha_to) and ending *)
fn diff_file_arg {ld,ls:agz}{pn,sn:nat}
  (lead: string pn, dir: !$A.borrow(byte, ld, 4096), dir_to: int,
   ids: !$A.borrow(byte, ls, 4096), sha_at: pos_t, sha_to: int, ending: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, lead)
  val () = copy_to_builder_v(dir, 0, dir_to, 4096, b)
  val () = bput_v(b, "/merge-proof-")
  val () = copy_to_builder_v(ids, sha_at, sha_to, 4096, b)
  val () = bput_v(b, ending)
in mk_arg(b) end

(* The paths of a diff: the whole tree, but bootstrap/c, which the regenerated copy judges *)
fn tree_pathspecs (): $L.listv($P.arg_entry) =
  word("--", word(":/", word(":(top,exclude)bootstrap/c", $L.list_vt_nil())))

(* ------------------------------------------------------------------ *)
(* Running tools (keyword: merge-proof) *)

(* Runs a tool, keeping the first 4096 bytes of its stdout in out; the status is its exit status, or ~1 when it did not run or its output could not be read, and the length is what was kept *)
fn tool_capture {lo:agz}{sn:nat | sn < $B.BUILDER_CAP}
  (name: string sn, rest: $L.listv($P.arg_entry), out: !$A.arr(byte, lo, 4096))
  : @(int, [k:nat | k <= 4096] int k) = let
  val (nul_tool | tool_exec) = $P.path_of_string_proved(name)
  val @(fz_tool, bv_tool) = $A.barr_freeze(tool_exec)
  val argv = word(name, rest)
  val outcome = run_cmd_capture_outcome(nul_tool | bv_tool, argv, out)
  val result = (case+ outcome of
    | ~CaptureFits(n) => @(0, n)
    | ~CaptureFailed(status, n) => @(status, n)
    | ~CaptureLonger(status, _) => @(status, 4096)
    | ~CaptureReadFailed(_, _, _) => @(~1, 0)
    | ~CaptureNotRun(_) => @(~1, 0)): @(int, [k:nat | k <= 4096] int k)
  val () = $A.cborrow_drop(fz_tool, bv_tool)
  val () = $A.barr_free($A.barr_thaw(fz_tool))
in result end

(* The exit status of a tool whose stdout is not wanted *)
fn tool_status {sn:nat | sn < $B.BUILDER_CAP}
  (name: string sn, rest: $L.listv($P.arg_entry)): int = let
  val out = $A.alloc<byte>(4096)
  val @(status, _) = tool_capture(name, rest, out)
  val () = $A.free<byte>(out)
in status end

(* Runs git with this process's own stdout and stderr, so what it prints is this command's output; the exit status, or ~1 when it did not run *)
fn git_show (rest: $L.listv($P.arg_entry)): int = let
  val (nul_git | git_exec) = $P.path_of_string_proved("git")
  val @(fz_git, bv_git) = $A.barr_freeze(git_exec)
  val argv = word("git", rest)
  val status = (case+ run_program(nul_git | bv_git, argv) of
    | ~Exited(n) => n
    | ~NotStarted() => ~1): int
  val () = $A.cborrow_drop(fz_git, bv_git)
  val () = $A.barr_free($A.barr_thaw(fz_git))
in status end

(* Runs git with the arguments given and keeps its first 4096 bytes of output in out *)
fn git_capture {lo:agz}
  (rest: $L.listv($P.arg_entry), out: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k) =
  tool_capture("git", rest, out)

fn git_status (rest: $L.listv($P.arg_entry)): int = tool_status("git", rest)

(* Runs a program of the checkout with its stdout discarded and its stderr shared; the exit status, or ~1 when it did not run *)
fn script_status {sn:nat | sn < $B.BUILDER_CAP}
  (path: string sn, rest: $L.listv($P.arg_entry)): int = let
  val (nul_script | script_exec) = $P.path_of_string_proved(path)
  val @(fz_script, bv_script) = $A.barr_freeze(script_exec)
  val argv = word(path, rest)
  val spawned = spawn_child(nul_script | bv_script, argv, $P.inherit(), $P.dev_null(), $P.inherit())
  val status = (case+ spawned of
    | ~$R.ok(pipes) => let
        val+ ~$P.spawn_pipes_mk(child, stdin_end, stdout_end, stderr_end) = pipes
        val () = $P.pipe_end_close(stdin_end)
        val () = $P.pipe_end_close(stdout_end)
        val () = $P.pipe_end_close(stderr_end)
      in
        (case+ $P.child_wait(child) of
          | ~$R.ok(n) => n
          | ~$R.err(_) => ~1)
      end
    | ~$R.err(_) => ~1): int
  val () = $A.cborrow_drop(fz_script, bv_script)
  val () = $A.barr_free($A.barr_thaw(fz_script))
in status end

(* ------------------------------------------------------------------ *)
(* Reading what git answered (keyword: merge-proof) *)

(* The first newline at or after p of bv[0, 4096), or 4096 *)
fun newline_at {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (bv: !$A.borrow(byte, l, 4096), p: int p): [r:nat | p <= r; r <= 4096] int r =
  if p >= 4096 then p
  else if byte2int0($A.read<byte>(bv, p)) = 10 then p
  else newline_at(bv, p + 1)

(* Whether x[a, a + len) and y[b, b + len) hold the same bytes, from the byte i on *)
fun span_equal {lx,ly:agz}{a,b,len,i:nat | a + len <= 4096; b + len <= 4096; i <= len} .<len - i>.
  (x: !$A.borrow(byte, lx, 4096), a: int a, y: !$A.borrow(byte, ly, 4096), b: int b,
   len: int len, i: int i): bool =
  if i >= len then true
  else if byte2int0($A.read<byte>(x, a + i)) = byte2int0($A.read<byte>(y, b + i)) then
    span_equal(x, a, y, b, len, i + 1)
  else false

(* Prints bv[a, a + len) from the byte i on *)
fun print_span {l:agz}{a,len,i:nat | a + len <= 4096; i <= len} .<len - i>.
  (bv: !$A.borrow(byte, l, 4096), a: int a, len: int len, i: int i): void =
  if i >= len then ()
  else let
    val () = print_char(int2char0(byte2int0($A.read<byte>(bv, a + i))))
  in print_span(bv, a, len, i + 1) end

(* ------------------------------------------------------------------ *)
(* The verdicts: OK on stdout with exit 0, NOT OK and its reason on stdout with exit 1, a git that did not answer on stderr with exit 2 *)

fn not_ok (why: string): void = let
  val () = println! ("NOT OK: ", why)
in set_exit_code(1) end

fn git_error (what: string): void = let
  val () = prerr! ("error: bats merge-proof: ", what)
  val () = prerr_newline()
in set_exit_code(2) end

(* ------------------------------------------------------------------ *)
(* The proofs, one after another; each later one runs only when the earlier ones held (keyword: merge-proof) *)

(* The repository the regeneration builds against: --repository, else BATS_REPOSITORY *)
fn repository_known (repo_at: pos_t): bool =
  if repo_at >= 0 then true
  else let
    var b : $B.builder_v = $B.create()
    val has = env_value("BATS_REPOSITORY", b)
    val @(text, _) = $B.into_arr(b)
    val () = $A.free<byte>(text)
  in has end

fn repository_arg {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = (if repo_at >= 0 then copy_to_builder_v(cmd, repo_at, repo_to, 4096, b)
    else let val _ = env_value("BATS_REPOSITORY", b) in () end)
in mk_arg(b) end

(* Whether the one line git printed for HEAD is the head sha[at, at + len) *)
fn checked_out {ls:agz}{l:nat | 2 * l + 2 <= 4096}
  (ids: !$A.borrow(byte, ls, 4096), head_at: int (l + 1), len: int l): bool = let
  val buf = $A.alloc<byte>(4096)
  val @(status, kept) = git_capture(word("rev-parse", word("HEAD", $L.list_vt_nil())), buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val same = (if status = 0 && kept = len + 1 then span_equal(ids, head_at, bv, 0, len, 0) else false): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in same end

(* The last proof: regenerating bootstrap/c from the head's sources leaves no change in it. The checkout must be the head, with no tracked file changed, since the script writes into it *)
fn bootstrap_proof {lc,ls,lp:agz}{l:nat | 2 * l + 2 <= 4096}{o:nat | o + l <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), argv0_to: int, repo_at: pos_t, repo_to: int,
   ids: !$A.borrow(byte, ls, 4096), len: int l,
   parents: !$A.borrow(byte, lp, 4096), other_at: int o): void =
  if not(checked_out(ids, len + 1, len)) then
    not_ok("the working tree is not at the head; run the command in a checkout of it")
  else if git_status(word("diff", word("--quiet", word("HEAD", $L.list_vt_nil())))) <> 0 then
    not_ok("a tracked file of the working tree differs from the head; bootstrap/c cannot be regenerated in it")
  else if not(repository_known(repo_at)) then
    git_error("the repository is not named: --repository <dir> names it")
  else let
    val binary = wrapped_arg("", cmd, 0, argv0_to, "")
    val built = script_status("scripts/bootstrap-c.sh", $L.list_vt_cons(binary, $L.list_vt_cons(repository_arg(cmd, repo_at, repo_to), $L.list_vt_nil())))
  in
    if built <> 0 then git_error("scripts/bootstrap-c.sh did not run to its end")
    else let
      val buf = $A.alloc<byte>(4096)
      val @(status, kept) = git_capture(
        word("status", word("--porcelain", word("--", word("bootstrap/c", $L.list_vt_nil())))), buf)
      val () = $A.free<byte>(buf)
    in
      if status <> 0 then git_error("git status did not answer")
      else if kept > 0 then let
        val () = not_ok("bootstrap/c is stale: regenerating it from the head's sources changes")
        val _ = git_show(word("status", word("--porcelain", word("--", word("bootstrap/c", $L.list_vt_nil())))))
      in () end
      else let
        val () = print! ("OK: ")
        val () = print_span(ids, len + 1, len, 0)
        val () = print! (" is the reviewed ")
        val () = print_span(ids, 0, len, 0)
        val () = print! (" and a merge of main ")
        val () = print_span(parents, other_at, len, 0)
        val () = print_newline()
      in () end
    end
  end

(* The arguments of the git that writes the diff of the head or the reviewed head (rev_at) against main into a file named by the head *)
fn write_diff_args {ld,ls:agz}{l:nat | 2 * l + 2 <= 4096}{sn:nat}
  (dir: !$A.borrow(byte, ld, 4096), dir_to: int, ids: !$A.borrow(byte, ls, 4096),
   len: int l, rev_at: pos_t, ending: string sn): $L.listv($P.arg_entry) =
  word("diff", word("--no-ext-diff", word("--no-color",
    $L.list_vt_cons(diff_file_arg("--output=", dir, dir_to, ids, len + 1, 2 * len + 1, ending),
    $L.list_vt_cons(wrapped_arg("origin/main...", ids, rev_at, rev_at + len, ""), tree_pathspecs())))))

(* The arguments of the git that compares the two diff files, the index lines of the two left out *)
fn compare_diff_args {ld,ls:agz}{l:nat | 2 * l + 2 <= 4096}
  (dir: !$A.borrow(byte, ld, 4096), dir_to: int, ids: !$A.borrow(byte, ls, 4096), len: int l)
  : $L.listv($P.arg_entry) =
  word("diff", word("--no-index", word("--no-ext-diff", word("--no-color", word("--exit-code", word("-I^index ",
    $L.list_vt_cons(diff_file_arg("", dir, dir_to, ids, len + 1, 2 * len + 1, "-reviewed.diff"),
    $L.list_vt_cons(diff_file_arg("", dir, dir_to, ids, len + 1, 2 * len + 1, "-head.diff"), $L.list_vt_nil()))))))))

(* Removes the two diff files *)
fn remove_diff_files {ld,ls:agz}{l:nat | 2 * l + 2 <= 4096}
  (dir: !$A.borrow(byte, ld, 4096), dir_to: int, ids: !$A.borrow(byte, ls, 4096), len: int l): void = let
  val _ = tool_status("rm", word("-f", word("--",
    $L.list_vt_cons(diff_file_arg("", dir, dir_to, ids, len + 1, 2 * len + 1, "-reviewed.diff"),
    $L.list_vt_cons(diff_file_arg("", dir, dir_to, ids, len + 1, 2 * len + 1, "-head.diff"), $L.list_vt_nil())))))
in () end

(* The pull request's own diff against main is the same at the head as at the reviewed head, byte for byte but for the index lines *)
fn diff_proof {lc,ls,lp:agz}{l:nat | 2 * l + 2 <= 4096}{o:nat | o + l <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), argv0_to: int, repo_at: pos_t, repo_to: int,
   ids: !$A.borrow(byte, ls, 4096), len: int l,
   parents: !$A.borrow(byte, lp, 4096), other_at: int o): void = let
  val dir_buf = $A.alloc<byte>(4096)
  val @(dir_status, dir_kept) = git_capture(word("rev-parse", word("--absolute-git-dir", $L.list_vt_nil())), dir_buf)
  val @(fz_dir, dir) = $A.freeze<byte>(dir_buf)
  val () = (if dir_status <> 0 || dir_kept < 2 then git_error("git did not name its directory")
    else let
      val dir_to = dir_kept - 1
      val wrote_reviewed = git_status(write_diff_args(dir, dir_to, ids, len, 0, "-reviewed.diff"))
      val wrote_head = git_status(write_diff_args(dir, dir_to, ids, len, len + 1, "-head.diff"))
    in
      if wrote_reviewed <> 0 || wrote_head <> 0 then let
        val () = remove_diff_files(dir, dir_to, ids, len)
      in git_error("git did not write the diffs") end
      else let
        val compared = git_status(compare_diff_args(dir, dir_to, ids, len))
      in
        if compared = 0 then let
          val () = remove_diff_files(dir, dir_to, ids, len)
        in bootstrap_proof(cmd, argv0_to, repo_at, repo_to, ids, len, parents, other_at) end
        else if compared = 1 then let
          val () = not_ok("the diff of the head against main differs from the diff of the reviewed head; the differing hunks follow")
          val _ = git_show(compare_diff_args(dir, dir_to, ids, len))
        in remove_diff_files(dir, dir_to, ids, len) end
        else let
          val () = remove_diff_files(dir, dir_to, ids, len)
        in git_error("git did not compare the diffs") end
      end
    end)
  val () = $A.drop<byte>(fz_dir, dir)
  val () = $A.free<byte>($A.thaw<byte>(fz_dir))
in () end

(* A merge with a hand-resolved conflict prints its resolved hunks and nothing else; any other merge goes on *)
fn conflict_proof {lc,ls,lp:agz}{l:nat | 2 * l + 2 <= 4096}{o:nat | o + l <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), argv0_to: int, repo_at: pos_t, repo_to: int,
   ids: !$A.borrow(byte, ls, 4096), len: int l,
   parents: !$A.borrow(byte, lp, 4096), other_at: int o): void = let
  fn combined (ids: !$A.borrow(byte, ls, 4096), len: int l): $L.listv($P.arg_entry) =
    word("diff-tree", word("--cc", word("--no-commit-id", word("--no-ext-diff", word("--no-color", word("-p",
      $L.list_vt_cons(wrapped_arg("", ids, len + 1, 2 * len + 1, ""), tree_pathspecs())))))))
  val buf = $A.alloc<byte>(4096)
  val @(status, kept) = git_capture(combined(ids, len), buf)
  val () = $A.free<byte>(buf)
in
  if status <> 0 then git_error("git did not answer for the combined diff of the merge")
  else if kept > 0 then let
    val _ = git_show(combined(ids, len))
  in set_exit_code(1) end
  else diff_proof(cmd, argv0_to, repo_at, repo_to, ids, len, parents, other_at)
end

(* The other parent is a commit of main *)
fn main_proof {lc,ls,lp:agz}{l:nat | 2 * l + 2 <= 4096}{o:nat | o + l <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), argv0_to: int, repo_at: pos_t, repo_to: int,
   ids: !$A.borrow(byte, ls, 4096), len: int l,
   parents: !$A.borrow(byte, lp, 4096), other_at: int o): void = let
  val status = git_status(word("merge-base", word("--is-ancestor",
    $L.list_vt_cons(wrapped_arg("", parents, other_at, other_at + len, ""),
    $L.list_vt_cons(literal_arg("origin/main"), $L.list_vt_nil())))))
in
  if status = 0 then conflict_proof(cmd, argv0_to, repo_at, repo_to, ids, len, parents, other_at)
  else if status = 1 then not_ok("the other parent of the head is not a commit of main")
  else git_error("git did not answer for the ancestry of the other parent")
end

(* The head has exactly two parents, and one of them is the reviewed head *)
fn parents_proof {lc,ls:agz}{l:nat | 2 * l + 2 <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), argv0_to: int, repo_at: pos_t, repo_to: int,
   ids: !$A.borrow(byte, ls, 4096), len: int l): void = let
  val has_second = git_status(word("rev-parse", word("--verify", word("--quiet",
    $L.list_vt_cons(wrapped_arg("", ids, len + 1, 2 * len + 1, "^2"), $L.list_vt_nil())))))
  val has_third = git_status(word("rev-parse", word("--verify", word("--quiet",
    $L.list_vt_cons(wrapped_arg("", ids, len + 1, 2 * len + 1, "^3"), $L.list_vt_nil())))))
in
  if has_second = 1 then not_ok("the head is not a merge")
  else if has_second <> 0 then git_error("git did not answer for the second parent")
  else if has_third = 0 then not_ok("the head has a third parent")
  else if has_third <> 1 then git_error("git did not answer for the third parent")
  else let
    val buf = $A.alloc<byte>(4096)
    val @(status, kept) = git_capture(word("rev-parse",
      $L.list_vt_cons(wrapped_arg("", ids, len + 1, 2 * len + 1, "^1"),
      $L.list_vt_cons(wrapped_arg("", ids, len + 1, 2 * len + 1, "^2"), $L.list_vt_nil()))), buf)
    val @(fz, parents) = $A.freeze<byte>(buf)
    val () = (if status <> 0 || kept <> 2 * len + 2 then git_error("git did not name the parents of the head")
      else if span_equal(ids, 0, parents, 0, len, 0) then
        main_proof(cmd, argv0_to, repo_at, repo_to, ids, len, parents, len + 1)
      else if span_equal(ids, 0, parents, len + 1, len, 0) then
        main_proof(cmd, argv0_to, repo_at, repo_to, ids, len, parents, 0)
      else not_ok("neither parent of the head is the reviewed head"))
    val () = $A.drop<byte>(fz, parents)
    val () = $A.free<byte>($A.thaw<byte>(fz))
  in () end
end

(* Resolves the two revisions to their commits: line 0 of ids is the reviewed head, line 1 the head *)
fn prove {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), argv0_to: int, reviewed_at: pos_t, reviewed_to: int,
   head_at: pos_t, head_to: int, repo_at: pos_t, repo_to: int): void = let
  val buf = $A.alloc<byte>(4096)
  val @(status, kept) = git_capture(word("rev-parse",
    $L.list_vt_cons(wrapped_arg("", cmd, reviewed_at, reviewed_to, "^{commit}"),
    $L.list_vt_cons(wrapped_arg("", cmd, head_at, head_to, "^{commit}"), $L.list_vt_nil()))), buf)
  val @(fz, ids) = $A.freeze<byte>(buf)
  val len = newline_at(ids, 0)
  val () = (if status <> 0 then git_error("git does not know both revisions")
    else if len > 2047 then git_error("git named a commit longer than the buffer holds")
    else if kept <> 2 * len + 2 then git_error("git did not name both commits")
    else parents_proof(cmd, argv0_to, repo_at, repo_to, ids, len))
  val () = $A.drop<byte>(fz, ids)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in () end

(* ------------------------------------------------------------------ *)
(* The command line (keyword: merge-proof) *)

fn usage_error (): void = let
  val () = prerr! ("usage: bats merge-proof <reviewed-sha> <head> [--repository <dir>] (neither revision starts with -)")
  val () = prerr_newline()
in set_exit_code(2) end

(* Reads the arguments after merge-proof, cmd[first, total): two revisions, then optionally --repository and a directory *)
fn run_merge_proof {l:agz}{first:nat | first <= 4096}
  (cmd: !$A.borrow(byte, l, 4096), argv0_to: int, first: int first, total: int): void = let
  val reviewed_to = find_nul(cmd, first)
in
  if reviewed_to + 1 > 4096 then usage_error()
  else let
    val head_at = reviewed_to + 1
    val head_to = find_nul(cmd, head_at)
  in
    if reviewed_to = first then usage_error()
    else if head_to = head_at then usage_error()
    else if head_to + 1 > 4096 then usage_error()
    else if byte2int0($A.read<byte>(cmd, first)) = 45 then usage_error()
    else if byte2int0($A.read<byte>(cmd, head_at)) = 45 then usage_error()
    else if head_to + 1 = total then
      prove(cmd, argv0_to, first, reviewed_to, head_at, head_to, ~1, 0)
    else let
      val flag_at = head_to + 1
      val flag_to = find_nul(cmd, flag_at)
    in
      if flag_to - flag_at <> 12 then usage_error()
      else if not(named_file(cmd, flag_at, flag_to, "--repository", 12)) then usage_error()
      else if flag_to + 1 > 4096 then usage_error()
      else let
        val repo_at = flag_to + 1
        val repo_to = find_nul(cmd, repo_at)
      in
        if repo_to = repo_at then usage_error()
        else if repo_to + 1 <> total then usage_error()
        else prove(cmd, argv0_to, first, reviewed_to, head_at, head_to, repo_at, repo_to)
      end
    end
  end
end

(* Where the arguments after merge-proof start, or ~1 when argv[1] is not merge-proof *)
fn arguments_at {l:agz}
  (cmd: !$A.borrow(byte, l, 4096)): [r:int | r == ~1 || (0 <= r && r <= 4096)] int r = let
  val a = find_nul(cmd, 0) + 1
in
  if a > 4096 then ~1
  else let
    val z = find_nul(cmd, a)
  in
    if z - a <> 11 then ~1
    else if z + 1 > 4096 then ~1
    else if named_file(cmd, a, z, "merge-proof", 11) then z + 1
    else ~1
  end
end

(* Runs bats merge-proof when that is the command given and answers true; false for any other command *)
#pub fn merge_proof_main (): bool

implement merge_proof_main () = let
  val buf = $A.alloc<byte>(4096)
  val read = $E.args_read(buf, 4096)
  val @(fz, cmd) = $A.freeze<byte>(buf)
  val handled = (case+ read of
    | ~$R.none() => false
    | ~$R.some(total) => let
        val first = arguments_at(cmd)
      in
        if first < 0 then false
        else let
          val argv0_to = find_nul(cmd, 0)
          val () = (if total >= 4096 then let
              val () = prerr! ("error: bats merge-proof: the command line is longer than 4095 bytes")
              val () = prerr_newline()
            in set_exit_code(2) end
            else if first >= total then usage_error()
            else run_merge_proof(cmd, argv0_to, first, total))
        in true end
      end): bool
  val () = $A.drop<byte>(fz, cmd)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
