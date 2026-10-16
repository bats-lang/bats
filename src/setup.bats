(* setup -- what a CI job does after bats is built (bats-lang/bats#283):
   `bats clone-repository <commit>` and `bats record-commit <commit>`.

   Both take a full commit (40 lowercase hex digits, never a branch or a
   tag: CI is pinned) and print the environment a later step needs as
   NAME=VALUE lines on stdout, everything else on stderr, so a CI step
   redirects stdout to its environment file (GITHUB_ENV's format is this
   one) and bats knows nothing of any CI. git is run through the process
   package; cloning without git is out of scope. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

staload "helpers.sats"

#define REPOSITORY_URL "https://github.com/bats-lang/repository-prototype.git"

(* sh -c script with up to three arguments; sh's exit status. Its stdout
   and stderr are both captured and shown on stderr when it fails: stdout is
   the caller's environment file. *)
fn sh_exec {sn:nat}
  (script: string sn, a1: $B.builder_v, a2: $B.builder_v, a3: $B.builder_v): int = let
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
  val out = $A.alloc<byte>(4096)
  val @(rc, k) = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2),
    $L.list_vt_cons(mk_arg(a3), $L.list_vt_nil()))))))), out)
  val @(fz_o, bv_o) = $A.freeze<byte>(out)
  val () = (if rc <> 0 && k > 0 then prerr_seg(bv_o, 0, k, 4096) else ())
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in rc end

fn bytes_arg {l:agz} (bv: !$A.borrow(byte, l, 4096), n: int): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, 0, n, 4096, b)
in b end

fn text_arg {sn:nat} (s: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, s)
in b end


(* $1 the commit, $2 the directory, $3 the repository's URL. Exit 10: the
   directory is a clone at the commit already. Only a directory that is
   absent, empty or a git clone is replaced. *)
(* the commit is checked first: $1 is a full commit, 40 lowercase hex digits *)
#define CLONE "exec 2>&1\nset -e\ncase $1 in *[!0-9a-f]*|'') echo \"error: '$1' is not a full commit: 40 lowercase hex digits are needed, never a branch or a tag (CI is pinned)\" >&2; exit 1 ;; esac\n[ ${#1} -eq 40 ] || { echo \"error: '$1' is not a full commit: 40 lowercase hex digits are needed\" >&2; exit 1; }\nif [ -d \"$2/.git\" ] && [ \"$(git -C \"$2\" rev-parse HEAD 2>/dev/null)\" = \"$1\" ]; then exit 10; fi\nif [ -e \"$2\" ] && [ ! -d \"$2/.git\" ] && [ -n \"$(ls -A \"$2\" 2>/dev/null)\" ]; then echo \"error: $2 exists, is not empty and is not a git clone, so it is not replaced\" >&2; exit 1; fi\nrm -rf \"$2\"\ngit init -q \"$2\"\ngit -C \"$2\" fetch -q --depth 1 \"$3\" \"$1\"\ngit -C \"$2\" checkout -q FETCH_HEAD\n"

(* $1 the commit: it has to be in the repository of the working directory *)
#define RECORD "exec 2>&1\nset -e\ncase $1 in *[!0-9a-f]*|'') echo \"error: '$1' is not a full commit: 40 lowercase hex digits are needed, never a branch or a tag (CI is pinned)\" >&2; exit 1 ;; esac\n[ ${#1} -eq 40 ] || { echo \"error: '$1' is not a full commit: 40 lowercase hex digits are needed\" >&2; exit 1; }\ngit cat-file -e \"$1^{commit}\" 2>/dev/null || { echo \"error: commit $1 is not in the checkout: a pull request's head is the merge's second parent, so check out with fetch-depth: 2 (or fetch the commit)\" >&2; exit 1; }\n"

(* Prints NAME=VALUE for the caller's environment file *)
fn put_env {l:agz} (name: string, bv: !$A.borrow(byte, l, 4096), n: int): void = let
  val () = print_string(name)
  val () = print_borrow(bv, 0, n, 4096)
in print_newline() end

#pub fn clone_repository {l1,l2:agz}
  (commit: !$A.borrow(byte, l1, 4096), clen: int,
   dir: !$A.borrow(byte, l2, 4096), dlen: int): bool

implement clone_repository (commit, clen, dir, dlen) =
  if clen <= 0 then let
    val () = prerr! ("error: specify the commit of the package repository\nusage: bats clone-repository <commit> --repository <dir>\n")
  in false end
  else if dlen <= 0 then let
    val () = prerr! ("error: specify the directory with --repository <dir> (or BATS_REPOSITORY)\nusage: bats clone-repository <commit> --repository <dir>\n")
  in false end
  else let
    val rc = sh_exec(CLONE, bytes_arg(commit, clen), bytes_arg(dir, dlen), text_arg(REPOSITORY_URL))
  in
    if rc = 0 || rc = 10 then let
      val () = (if rc = 10 then prerr! ("the package repository is at the commit already\n") else ())
      val () = put_env("BATS_REPOSITORY=", dir, dlen)
    in true end
    else false
  end

#pub fn record_commit {l1:agz}
  (commit: !$A.borrow(byte, l1, 4096), clen: int): bool

implement record_commit (commit, clen) =
  if clen <= 0 then let
    val () = prerr! ("error: specify the commit the version names\nusage: bats record-commit <commit>\n")
  in false end
  else let
    val rc = sh_exec(RECORD, bytes_arg(commit, clen), text_arg(""), text_arg(""))
  in
    if rc = 0 then let
      val () = put_env("BATS_COMMIT=", commit, clen)
    in true end
    else false
  end
