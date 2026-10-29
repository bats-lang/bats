(* check_push -- bats check-push [--repository <dir>]: the deterministic first-minute checks of a push, as one subcommand any app's pre-push hook calls (bats-lang/bats#575; keyword: check-push) *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

staload "helpers.sats"
staload "pins.sats"
staload "merge_proof.sats"
staload "_bats_built.sats"

(* ------------------------------------------------------------------ *)
(* Reporting (keyword: check-push). A failed check says what it found on one line of stderr,
   `bats check-push: check <n> (<name>) failed: <what>`, and its constructor says the fix on the
   next, `fix: <the fix>`; the exit status is then 1. *)

fn found_prefix (number: int, name: string): void = let
  val () = prerr! ("bats check-push: check ", number, " (", name, ") failed: ")
in () end

fn say_fix (remedy: string): bool = let
  val () = prerr! ("fix: ", remedy)
  val () = prerr_newline()
  val () = set_exit_code(1)
in false end

(* ------------------------------------------------------------------ *)
(* A pin file: 40 lowercase hex digits and a newline (keyword: check-push) *)

datatype pin_read = PinRead | PinUnreadable | PinNotCommit

fun hex_run {l:agz}{i:nat | i <= 40} .<40 - i>.
  (buf: !$A.arr(byte, l, 4096), i: int i): bool =
  if i >= 40 then true
  else let
    val b = peek_arr(buf, i, 4096)
  in
    if (b >= 48 && b <= 57) || (b >= 97 && b <= 102) then hex_run(buf, i + 1) else false
  end

(* The file at path read into buf: PinRead when it is exactly a full lowercase commit, then buf[0, 40) is it *)
fn read_pin {l:agz}{sn:nat} (path: string sn, buf: !$A.arr(byte, l, 4096)): pin_read = let
  val @(pa, pal) = str_into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val opened = file_open_m(bv_p, pal, $F.ReadOnly(), $F.OpenExisting(), 0)
  val result = (case+ opened of
    | ~$R.err(_) => PinUnreadable()
    | ~$R.ok(fd) => let
        val got = $F.file_read(fd, buf, 4096)
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in
        case+ got of
        | ~$R.err(_) => PinUnreadable()
        | ~$R.ok(k) =>
          if k = 41 && peek_arr(buf, 40, 4096) = 10 then (if hex_run(buf, 0) then PinRead() else PinNotCommit())
          else if k = 40 then (if hex_run(buf, 0) then PinRead() else PinNotCommit())
          else PinNotCommit()
      end): pin_read
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in result end

(* ------------------------------------------------------------------ *)
(* Check 1, locks: every bats.lock of the tree names only versions the package repository holds
   at the commit of .github/repository-version, with the sha256 it holds (keyword: check-push).
   The sidecar is read from that commit (git show), never from the files the clone has checked
   out. No bats command compares a lock's sha256 without building the app. *)

datatype locks_result =
  | LocksPassed
  | LocksPinUnreadable
  | LocksPinNotCommit
  | LocksNoRepository
  | LocksRepositoryLacksPin
  | LocksListingFailed
  | LocksListingTooLong
  | LocksUnreadable
  | LocksMalformed
  | LocksNotInRepository
  | LocksDiffers
  | LocksGitFailed

(* git's exit status for rest (its stdout is not wanted) *)
fn git_status (rest: $L.listv($P.arg_entry)): int = let
  val out = $A.alloc<byte>(4096)
  val @(status, _) = tool_output("git", rest, out)
  val () = $A.free<byte>(out)
in status end

(* git -C <the repository> rest *)
fn git_in_repository {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int, rest: $L.listv($P.arg_entry))
  : $L.listv($P.arg_entry) =
  $L.list_vt_cons(literal_arg("-C"), $L.list_vt_cons(repository_arg(cmd, repo_at, repo_to), rest))

(* The first space or newline of lock[i, n), or n (or m) *)
fun field_end {l:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (lock: !$A.borrow(byte, l, m), i: int i, n: int, m: int m): [r:nat | i <= r; r <= m] int r =
  if i >= m then i
  else if i >= n then i
  else let
    val b = peek(lock, i, m)
  in
    if b = 32 then i else if b = 10 then i else field_end(lock, i + 1, n, m)
  end

(* lock[i, e) appended to out, a slash as an underscore: the name a package's files have in the repository *)
fun put_flat {l:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (lock: !$A.borrow(byte, l, m), i: int i, e: int, m: int m, out: !$B.builder_v >> $B.builder_v): void =
  if i >= e then ()
  else if i >= m then ()
  else let
    val b = peek(lock, i, m)
    val () = put_char_v(out, (if b = 47 then 95 else b))
  in put_flat(lock, i + 1, e, m, out) end

(* Whether lock[i, i + 64) is 64 lowercase hex digits *)
fun hex64 {l:agz}{m:pos}{i:nat}{k:nat | k <= 64} .<64 - k>.
  (lock: !$A.borrow(byte, l, m), i: int i, k: int k, m: int m): bool =
  if k >= 64 then true
  else let
    val b = peek(lock, i + k, m)
  in
    if (b >= 48 && b <= 57) || (b >= 97 && b <= 102) then hex64(lock, i, k + 1, m) else false
  end

(* Whether lock[i, i + 64) are the first 64 bytes of out *)
fun same64 {l,lo:agz}{m:pos}{i:nat}{k:nat | k <= 64} .<64 - k>.
  (lock: !$A.borrow(byte, l, m), i: int i, out: !$A.borrow(byte, lo, 4096), k: int k, m: int m): bool =
  if k >= 64 then true
  else if peek(lock, i + k, m) = peek(out, k, 4096) then same64(lock, i, out, k + 1, m)
  else false

(* The entry <package> <version> <sha256> of one line against the repository at the pin: the sidecar
   `<package>/<package with / as _>_<version>.bats.sha256` of the pin's commit *)
fn check_entry {ll,lp,lc:agz}{m:pos}{na,nt,va,vt,sa:nat | na <= nt; nt <= m}
  (lock: !$A.borrow(byte, ll, m), name_at: int na, name_to: int nt, version_at: int va, version_to: int vt, sha_at: int sa, m: int m,
   pin: !$A.borrow(byte, lp, 4096),
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int): locks_result = let
  var spec : $B.builder_v = $B.create()
  val () = copy_to_builder_v(pin, 0, 40, 4096, spec)
  val () = put_char_v(spec, 58)
  val () = copy_to_builder_v(lock, name_at, name_to, m, spec)
  val () = put_char_v(spec, 47)
  val () = put_flat(lock, name_at, name_to, m, spec)
  val () = put_char_v(spec, 95)
  val () = copy_to_builder_v(lock, version_at, version_to, m, spec)
  val () = bput_v(spec, ".bats.sha256")
  val out = $A.alloc<byte>(4096)
  val @(status, kept) = tool_output("git",
    git_in_repository(cmd, repo_at, repo_to, $L.list_vt_cons(literal_arg("show"), $L.list_vt_cons(mk_arg(spec), $L.list_vt_nil()))), out)
  val @(fz_out, bv_out) = $A.freeze<byte>(out)
  val result = (if status < 0 then LocksGitFailed()
    else if status <> 0 then LocksNotInRepository()
    else if kept < 64 then LocksDiffers()
    else if same64(lock, sha_at, bv_out, 0, m) then LocksPassed()
    else LocksDiffers()): locks_result
  val () = $A.drop<byte>(fz_out, bv_out)
  val () = $A.free<byte>($A.thaw<byte>(fz_out))
in result end

(* Each line of the lock lock[i, n) of m bytes: blank, or <package> <version> <sha256> (64 lowercase hex digits) checked
   against the repository. The first failure is the answer, with the number of its line and where its package and
   version are (a malformed line has none). *)
fun lock_lines {ll,lp,lc:agz}{m:pos}{n:nat | n < m}{i:nat | i <= m} .<m - i>.
  (lock: !$A.borrow(byte, ll, m), n: int n, m: int m, i: int i, line: int,
   pin: !$A.borrow(byte, lp, 4096),
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int)
  : @(locks_result, int, pos_t, int) =
  if i >= n then @(LocksPassed(), line, 0, 0)
  else if peek(lock, i, m) = 10 then lock_lines(lock, n, m, i + 1, line + 1, pin, cmd, repo_at, repo_to)
  else let
    val name_to = field_end(lock, i, n, m)
  in
    if name_to = i then @(LocksMalformed(), line, 0, 0)
    else if name_to >= m then @(LocksMalformed(), line, 0, 0)
    else if peek(lock, name_to, m) <> 32 then @(LocksMalformed(), line, 0, 0)
    else let
      val version_at = name_to + 1
      val version_to = field_end(lock, version_at, n, m)
    in
      if version_to = version_at then @(LocksMalformed(), line, 0, 0)
      else if version_to >= m then @(LocksMalformed(), line, 0, 0)
      else if peek(lock, version_to, m) <> 32 then @(LocksMalformed(), line, 0, 0)
      else let
        val sha_at = version_to + 1
        val sha_to = field_end(lock, sha_at, n, m)
      in
        if sha_to - sha_at <> 64 then @(LocksMalformed(), line, 0, 0)
        else if ~hex64(lock, sha_at, 0, m) then @(LocksMalformed(), line, 0, 0)
        else if sha_to < n && peek(lock, sha_to, m) <> 10 then @(LocksMalformed(), line, 0, 0)
        else let
          val entry = check_entry(lock, i, name_to, version_at, version_to, sha_at, m, pin, cmd, repo_at, repo_to)
        in
          case+ entry of
          | LocksPassed() =>
            if sha_to >= n then @(LocksPassed(), line, 0, 0)
            else if sha_to >= m then @(LocksPassed(), line, 0, 0)
            else lock_lines(lock, n, m, sha_to + 1, line + 1, pin, cmd, repo_at, repo_to)
          | _ => @(entry, line, i, version_to)
        end
      end
    end
  end

(* What a failed line says: the lock's path (files[at, to)), its line, its package and version, and why *)
fn say_lock_entry {lf,ll:agz}{m:pos}
  (files: !$A.borrow(byte, lf, 4096), at: pos_t, to: int,
   lock: !$A.borrow(byte, ll, m), m: int m, result: locks_result, line: int, name_at: pos_t, version_to: int): void = let
  val () = found_prefix(1, "locks")
  val () = prerr_seg(files, at, to, 4096)
  val () = prerr! (":", line, ": ")
  val () = (if version_to > name_at then prerr_seg(lock, name_at, version_to, m) else ())
  val () = (case+ result of
    | LocksMalformed() => prerr! ("is not a line `<package> <version> <sha256>`")
    | LocksNotInRepository() => prerr! (" is not in the package repository at the commit of .github/repository-version")
    | LocksDiffers() => prerr! (" has another sha256 in the package repository at the commit of .github/repository-version")
    | LocksGitFailed() => prerr! (" could not be looked up: git did not run")
    | _ => ())
in prerr_newline() end

(* The locks of the listing files[p, k) (NUL after each path), one after another; the first failure is the answer *)
fun each_lock {lf,lp,lc:agz}{p:nat | p <= 4096} .<4096 - p>.
  (files: !$A.borrow(byte, lf, 4096), k: int, p: int p,
   pin: !$A.borrow(byte, lp, 4096),
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int): locks_result =
  if p >= k then LocksPassed()
  else let
    val path_to = find_nul(files, p)
    var path : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, p, path_to, 4096, path)
    val () = put_char_v(path, 0)
    val @(pa, pal) = $B.into_arr(path)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val read = read_whole_m(bv_p, pal)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
    val here = (case+ read of
      | ~whole_err(_) => let
          val () = found_prefix(1, "locks")
          val () = prerr_seg(files, p, path_to, 4096)
          val () = prerr! (" cannot be read")
          val () = prerr_newline()
        in LocksUnreadable() end
      | ~whole_ok(ar, piece, m, n) => let
          val @(fz_c, bv_c) = $A.freeze<byte>(piece)
          val @(result, line, name_at, version_to) = lock_lines(bv_c, n, m, 0, 1, pin, cmd, repo_at, repo_to)
          val () = (case+ result of
            | LocksPassed() => ()
            | _ => say_lock_entry(files, p, path_to, bv_c, m, result, line, name_at, version_to))
          val () = $A.drop<byte>(fz_c, bv_c)
          val () = whole_free(ar, $A.thaw<byte>(fz_c))
        in result end): locks_result
  in
    case+ here of
    | LocksPassed() => if path_to + 1 > 4096 then LocksPassed() else each_lock(files, k, path_to + 1, pin, cmd, repo_at, repo_to)
    | _ => here
  end

(* The tree's bats.lock files (tracked, or untracked and not ignored), at any depth, checked against the pin *)
fn check_locks_listed {lp,lc:agz}
  (pin: !$A.borrow(byte, lp, 4096), cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int): locks_result = let
  val files = $A.alloc<byte>(4096)
  val @(status, kept) = tool_output("git",
    $L.list_vt_cons(literal_arg("ls-files"), $L.list_vt_cons(literal_arg("--cached"), $L.list_vt_cons(literal_arg("--others"),
    $L.list_vt_cons(literal_arg("--exclude-standard"), $L.list_vt_cons(literal_arg("-z"), $L.list_vt_cons(literal_arg("--"),
    $L.list_vt_cons(literal_arg(":(glob)**/bats.lock"), $L.list_vt_nil()))))))), files)
  val @(fz_f, bv_f) = $A.freeze<byte>(files)
  val result = (if status <> 0 then let
        val () = found_prefix(1, "locks")
        val () = prerr! ("git ls-files did not list the bats.lock files here")
        val () = prerr_newline()
      in LocksListingFailed() end
    else if kept >= 4096 then let
        val () = found_prefix(1, "locks")
        val () = prerr! ("the list of bats.lock files is longer than 4095 bytes")
        val () = prerr_newline()
      in LocksListingTooLong() end
    else each_lock(bv_f, kept, 0, pin, cmd, repo_at, repo_to)): locks_result
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in result end

(* Check 1 *)
fn check_locks {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int): locks_result = let
  val pin = $A.alloc<byte>(4096)
  val read = read_pin(".github/repository-version", pin)
  val @(fz_pin, bv_pin) = $A.freeze<byte>(pin)
  val result = (case+ read of
    | PinUnreadable() => let
        val () = found_prefix(1, "locks")
        val () = prerr! (".github/repository-version cannot be read")
        val () = prerr_newline()
      in LocksPinUnreadable() end
    | PinNotCommit() => let
        val () = found_prefix(1, "locks")
        val () = prerr! (".github/repository-version is not a full lowercase commit (40 hex digits)")
        val () = prerr_newline()
      in LocksPinNotCommit() end
    | PinRead() =>
      if ~repository_known(repo_at) then let
          val () = found_prefix(1, "locks")
          val () = prerr! ("no package repository is named, so the one at the pin cannot be read")
          val () = prerr_newline()
        in LocksNoRepository() end
      else let
        var rev : $B.builder_v = $B.create()
        val () = copy_to_builder_v(bv_pin, 0, 40, 4096, rev)
        val () = bput_v(rev, "^{commit}")
        val have = git_status(git_in_repository(cmd, repo_at, repo_to,
          $L.list_vt_cons(literal_arg("cat-file"), $L.list_vt_cons(literal_arg("-e"), $L.list_vt_cons(mk_arg(rev), $L.list_vt_nil())))))
      in
        if have <> 0 then let
            val () = found_prefix(1, "locks")
            val () = prerr! ("the package repository does not have the commit of .github/repository-version, ")
            val () = prerr_seg(bv_pin, 0, 40, 4096)
            val () = prerr_newline()
          in LocksRepositoryLacksPin() end
        else check_locks_listed(bv_pin, cmd, repo_at, repo_to)
      end): locks_result
  val () = $A.drop<byte>(fz_pin, bv_pin)
  val () = $A.free<byte>($A.thaw<byte>(fz_pin))
in result end

(* Says the fix of a failed lock check; true when it passed *)
fn report_locks (result: locks_result): bool =
  case+ result of
  | LocksPassed() => true
  | LocksPinUnreadable() => say_fix("restore .github/repository-version: the commit of bats-lang/repository-prototype that CI clones")
  | LocksPinNotCommit() => say_fix("write the commit of bats-lang/repository-prototype that CI clones in .github/repository-version, 40 lowercase hex digits")
  | LocksNoRepository() => say_fix("name a clone of bats-lang/repository-prototype: bats check-push --repository <dir>, or BATS_REPOSITORY (an env file read by bats with-env)")
  | LocksRepositoryLacksPin() => say_fix("fetch the commit into the clone: git -C <repository> fetch origin <the commit>")
  | LocksListingFailed() => say_fix("run bats check-push at the root of a git repository")
  | LocksListingTooLong() => say_fix("keep fewer bats.lock files in the tree, or run the checks of each directory of its own")
  | LocksUnreadable() => say_fix("restore the bats.lock the line above names, or remove it")
  | LocksMalformed() => say_fix("relock: bats lock --repository <clone of the package repository at the commit of .github/repository-version> in the directory of the lock")
  | LocksNotInRepository() => say_fix("relock against the pin: bats lock --repository <clone at the commit of .github/repository-version> in the directory of the lock")
  | LocksDiffers() => say_fix("relock against the pin: bats lock --repository <clone at the commit of .github/repository-version> in the directory of the lock")
  | LocksGitFailed() => say_fix("install git, and run bats check-push where it is on PATH")

(* ------------------------------------------------------------------ *)
(* Check 2, compiler: the bats that runs is the one built from the commit of .github/bats-version.
   It knows its commit as a fact of its build (src/built.bats, keyword: built-commit): a record
   beside the binary can be forged or forgotten, this cannot. *)

datatype compiler_result =
  | CompilerIsPin
  | CompilerPinUnreadable
  | CompilerPinNotCommit
  | CompilerUnnamed
  | CompilerOther

fun same_text {l:agz}{i:nat | i <= 40} .<40 - i>.
  (sha: string 40, pin: !$A.borrow(byte, l, 4096), i: int i): bool =
  if i >= 40 then true
  else if char2int0(string_get_at(sha, i)) = peek(pin, i, 4096) then same_text(sha, pin, i + 1)
  else false

(* Check 2 *)
fn check_compiler (): compiler_result = let
  val pin = $A.alloc<byte>(4096)
  val read = read_pin(".github/bats-version", pin)
  val @(fz_pin, bv_pin) = $A.freeze<byte>(pin)
  val result = (case+ read of
    | PinUnreadable() => let
        val () = found_prefix(2, "compiler")
        val () = prerr! (".github/bats-version cannot be read")
        val () = prerr_newline()
      in CompilerPinUnreadable() end
    | PinNotCommit() => let
        val () = found_prefix(2, "compiler")
        val () = prerr! (".github/bats-version is not a full lowercase commit (40 hex digits)")
        val () = prerr_newline()
      in CompilerPinNotCommit() end
    | PinRead() =>
      (case+ bats_built_commit() of
      | ~BuiltUnnamed() => let
          val () = found_prefix(2, "compiler")
          val () = prerr! ("this bats was built without BATS_COMMIT, so it does not know which commit it is")
          val () = prerr_newline()
        in CompilerUnnamed() end
      | ~BuiltFrom(sha) =>
        if same_text(sha, bv_pin, 0) then CompilerIsPin()
        else let
          val () = found_prefix(2, "compiler")
          val () = prerr! ("this bats is built from ", sha, ", .github/bats-version is ")
          val () = prerr_seg(bv_pin, 0, 40, 4096)
          val () = prerr_newline()
        in CompilerOther() end)): compiler_result
  val () = $A.drop<byte>(fz_pin, bv_pin)
  val () = $A.free<byte>($A.thaw<byte>(fz_pin))
in result end

(* Says the fix of a failed compiler check; true when it passed *)
fn report_compiler (result: compiler_result): bool =
  case+ result of
  | CompilerIsPin() => true
  | CompilerPinUnreadable() => say_fix("restore .github/bats-version: the commit of bats-lang/bats that CI builds")
  | CompilerPinNotCommit() => say_fix("write the commit of bats-lang/bats that CI builds in .github/bats-version, 40 lowercase hex digits")
  | CompilerUnnamed() => say_fix("build the compiler of the commit of .github/bats-version with itself, in a checkout of bats at that commit: make -C bootstrap/c debug/bats, then BATS_COMMIT=<that commit> bootstrap/c/debug/bats build --repository <dir>, and put dist/debug first on PATH")
  | CompilerOther() => say_fix("build the compiler of the commit of .github/bats-version with itself, in a checkout of bats at that commit: make -C bootstrap/c debug/bats, then BATS_COMMIT=<that commit> bootstrap/c/debug/bats build --repository <dir>, and put dist/debug first on PATH")

(* ------------------------------------------------------------------ *)
(* Check 3, memory: BATS_PATSOPT_MEM_MB is what CI runs with (keyword: check-push) *)

datatype memory_result = MemoryIsCi | MemoryUnset | MemoryOther

(* Check 3 *)
fn check_memory (): memory_result = let
  var value : $B.builder_v = $B.create()
  val set = env_value("BATS_PATSOPT_MEM_MB", value)
  val @(va, vl) = $B.into_arr(value)
  val @(fz_v, bv_v) = $A.freeze<byte>(va)
  val result = (if ~set then let
        val () = found_prefix(3, "memory")
        val () = prerr! ("BATS_PATSOPT_MEM_MB is not set, CI runs with 4096")
        val () = prerr_newline()
      in MemoryUnset() end
    else if vl = 4 && peek(bv_v, 0, vl) = 52 && peek(bv_v, 1, vl) = 48 && peek(bv_v, 2, vl) = 57 && peek(bv_v, 3, vl) = 54 then MemoryIsCi()
    else let
        val () = found_prefix(3, "memory")
        val () = prerr! ("BATS_PATSOPT_MEM_MB is ")
        val () = prerr_seg(bv_v, 0, vl, vl)
        val () = prerr! (", CI runs with 4096")
        val () = prerr_newline()
      in MemoryOther() end): memory_result
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
in result end

(* Says the fix of a failed memory check; true when it passed *)
fn report_memory (result: memory_result): bool =
  case+ result of
  | MemoryIsCi() => true
  | MemoryUnset() => say_fix("set BATS_PATSOPT_MEM_MB=4096 in the pushing shell (an env file read by bats with-env): a patsopt that needs more fails in CI as it does with this cap")
  | MemoryOther() => say_fix("set BATS_PATSOPT_MEM_MB=4096 in the pushing shell (an env file read by bats with-env): a patsopt that needs more fails in CI as it does with this cap")

(* ------------------------------------------------------------------ *)

(* The three checks in order, each only when the earlier ones passed *)
fn run_checks {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: int): void =
  if ~report_locks(check_locks(cmd, repo_at, repo_to)) then ()
  else if ~report_compiler(check_compiler()) then ()
  else if ~report_memory(check_memory()) then ()
  else println! ("bats check-push: ok (locks, compiler, memory)")

fn usage_error (): void = let
  val () = prerr! ("usage: bats check-push [--repository <dir>]")
  val () = prerr_newline()
in set_exit_code(2) end

(* Where the arguments after check-push start, or ~1 when argv[1] is not check-push *)
fn arguments_at {l:agz}{t:nat | t <= 4096} (cmd: !$A.borrow(byte, l, 4096), total: int t)
  : [r:int | r == ~1 || (0 <= r && r <= 4096)] int r = let
  val a = find_nul(cmd, 0) + 1
in
  if a > 4096 then ~1
  else let
    val z = find_nul(cmd, a)
  in
    if z - a <> 10 then ~1
    else if z + 1 > 4096 then ~1
    else if named_file(cmd, a, z, "check-push", 10) then z + 1
    else ~1
  end
end

(* No arguments, or --repository and a directory *)
fn run_check_push {l:agz}{first:nat | first <= 4096}
  (cmd: !$A.borrow(byte, l, 4096), first: int first, total: int): void =
  if first >= total then run_checks(cmd, ~1, 0)
  else let
    val flag_to = find_nul(cmd, first)
  in
    if flag_to - first <> 12 then usage_error()
    else if ~named_file(cmd, first, flag_to, "--repository", 12) then usage_error()
    else if flag_to + 1 > 4096 then usage_error()
    else let
      val dir_to = find_nul(cmd, flag_to + 1)
    in
      if dir_to = flag_to + 1 then usage_error()
      else if dir_to + 1 <> total then usage_error()
      else run_checks(cmd, flag_to + 1, dir_to)
    end
  end

(* Runs bats check-push when that is the command given and answers true; false for any other command *)
#pub fn check_push_main (): bool

implement check_push_main () = let
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
              val () = prerr! ("error: bats check-push: the command line is longer than 4095 bytes")
              val () = prerr_newline()
            in set_exit_code(2) end
            else run_check_push(cmd, first, total))
        in true end
      end): bool
  val () = $A.drop<byte>(fz, cmd)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
