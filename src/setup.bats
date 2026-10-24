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
  val out = $A.alloc<byte>(4096)
  val @(rc, k) = run_cmd_capture(nul_x | bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2),
    $L.list_vt_cons(mk_arg(a3), $L.list_vt_nil()))))))), out)
  val @(fz_o, bv_o) = $A.freeze<byte>(out)
  val () = (if rc <> 0 && k > 0 then prerr_seg(bv_o, 0, k, 4096) else ())
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
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
(* $1 the commit, $2 the directory, $3 the repository's URL. Exit 10: the
   directory is a clone at the commit already. Nothing is ever deleted that
   this run did not make: a directory that is a git repository is used
   only when its origin is $3 (then fetched and checked out in place); an
   absent or empty path gets a clone made in a sibling directory of this
   run's own (marked, so that a killed run's is cleared by the next one) and moved into place, removed again on any failure or signal, with the empty directory's mode copied; a symbolic link is refused; any
   other path is refused and left exactly as it was. *)
#define CLONE "exec 2>&1\nset -e\ncase $1 in *[!0-9a-f]*|'') echo \"error: '$1' is not a full commit: 40 lowercase hex digits are needed, never a branch or a tag (CI is pinned)\"; exit 1 ;; esac\n[ ${#1} -eq 40 ] || { echo \"error: '$1' is not a full commit: 40 lowercase hex digits are needed\"; exit 1; }\n[ \"$(printf '%s' \"$2\" | tr -d '[:cntrl:]')\" = \"$2\" ] || { echo \"error: the directory has a control character in its name, which an environment file cannot hold\"; exit 1; }\np=$2\nwhile [ ${#p} -gt 1 ] && [ \"${p%/}\" != \"$p\" ]; do p=${p%/}; done\nif [ -L \"$p\" ]; then echo \"error: $p is a symbolic link, which is neither followed nor replaced\"; exit 1; fi\nreuse() {\n  origin=$(git -C \"$p\" config --get remote.origin.url 2>/dev/null || true)\n  [ \"$origin\" = \"$2\" ] || { if [ -z \"$origin\" ]; then echo \"error: $p is a git repository with no origin, so it is not a clone of the package repository (a repository made by git init, as the old setup action made one, has none): it is not touched; remove it to clone again\"; else echo \"error: $p is a git repository but not a clone of the package repository (its origin is '$origin'), so it is not touched\"; fi; exit 1; }\n  if [ \"$(git -C \"$p\" rev-parse HEAD 2>/dev/null)\" = \"$1\" ]; then exit 10; fi\n  git -C \"$p\" fetch -q --depth 1 origin \"$1\"\n  git -C \"$p\" checkout -q FETCH_HEAD\n  exit 0\n}\noccupied() { if [ -e \"$p\" ] && { [ ! -d \"$p\" ] || [ -n \"$(ls -A -- \"$p\")\" ]; }; then echo \"error: $p exists and is neither an empty directory nor a clone of the package repository, so it is not replaced\"; exit 1; fi; }\nif [ -d \"$p/.git\" ]; then reuse \"$1\" \"$3\"; fi\noccupied\ntop=$p; q=$p\nwhile :; do q=$(dirname -- \"$q\"); [ -e \"$q\" ] && break; top=$q; done\nmkdir -p -- \"$(dirname -- \"$p\")\"\nt=\nundo() { [ -z \"$t\" ] || rm -rf -- \"$t\"; [ \"$top\" = \"$p\" ] && return 0; q=$(dirname -- \"$p\"); while rmdir -- \"$q\" 2>/dev/null && [ \"$q\" != \"$top\" ]; do q=$(dirname -- \"$q\"); done; return 0; }\ntrap undo EXIT\nfor old in \"$p\".new.*; do\n  if [ -d \"$old\" ] && [ ! -L \"$old\" ] && [ -f \"$old/.bats-clone-pending\" ] && ! kill -0 \"$(cat \"$old/.bats-clone-pending\")\" 2>/dev/null; then rm -rf -- \"$old\"; fi\ndone\nt=$(mktemp -d -- \"$p.new.XXXXXX\")\ntrap 'exit 1' INT TERM\necho $$ > \"$t/.bats-clone-pending\"\ngit init -q -- \"$t\"\ngit -C \"$t\" remote add origin \"$3\"\ngit -C \"$t\" fetch -q --depth 1 origin \"$1\"\ngit -C \"$t\" checkout -q FETCH_HEAD\nrm -f -- \"$t/.bats-clone-pending\"\nbase=$(basename -- \"$t\")\ntries=0\nwhile :; do\ntries=$((tries + 1))\nlost=\nmx=\nif [ -d \"$p\" ]; then\n  m=$(ls -ld -- \"$p\" | cut -c2-10)\n  rwx=$(echo \"$m\" | sed 's/[st]/x/g; s/[ST]/-/g')\n  mx=\"u=$(echo \"$rwx\" | cut -c1-3 | tr -d -)$(echo \"$m\" | cut -c3 | sed -n 's/[sS]/s/p'),g=$(echo \"$rwx\" | cut -c4-6 | tr -d -)$(echo \"$m\" | cut -c6 | sed -n 's/[sS]/s/p'),o=$(echo \"$rwx\" | cut -c7-9 | tr -d -)$(echo \"$m\" | cut -c9 | sed -n 's/[tT]/t/p')\"\n  chmod -- \"$mx\" \"$t\"\n  rmdir -- \"$p\" 2>/dev/null || lost=1\nelse\n  chmod 755 -- \"$t\"\nfi\nif [ -z \"$lost\" ]; then\n  if ! mv -- \"$t\" \"$p\"; then [ -z \"$mx\" ] || { mkdir -- \"$p\" && chmod -- \"$mx\" \"$p\"; }; exit 1; fi\n  if [ ! -e \"$p/$base\" ]; then trap - EXIT; exit 0; fi\n  mv -- \"$p/$base\" \"$t\" || { rm -rf -- \"$p/$base\"; t=; exit 1; }\nfi\nif [ -d \"$p/.git\" ]; then reuse \"$1\" \"$3\"; fi\noccupied\n[ $tries -lt 5 ] || { echo \"error: $p kept changing while this run moved its clone into place, so it is left as it is; run again\"; exit 1; }\ndone\n"

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
