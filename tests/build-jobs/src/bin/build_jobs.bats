(* build-jobs -- bats build --jobs: the compiles run J at once and are waited for before the link, every message comes in the order of the serial build, and what is written does not depend on J (bats#554; keyword: build-jobs; .claude/rules/build-jobs.md) *)
#target native
#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

staload "overlap.sats"

(* ============================================================
   Text: a builder_v holds the bytes of a command, a path or a file
   ============================================================ *)

fn put_byte_v (out: !$B.builder_v >> $B.builder_v, v: int): void =
  if $B.length(out) < 524288 then $B.put_char(out, $AR.low_byte(v)) else ()

fn put {sn:nat} (out: !$B.builder_v >> $B.builder_v, s: string sn): void = let
  fun loop {sl:nat}{i:nat | i <= sl} .<sl - i>.
    (out: !$B.builder_v >> $B.builder_v, s: string sl, slen: int sl, i: int i): void =
    if i >= slen then ()
    else let
      val () = put_byte_v(out, char2int0(string_get_at(s, i)))
    in loop(out, s, slen, i + 1) end
in loop(out, s, g1u2i(string1_length(s)), 0) end

(* s repeated count times *)
fn put_times {sn:nat}{c:nat} (out: !$B.builder_v >> $B.builder_v, s: string sn, count: int c): void = let
  fun loop {k:nat} .<k>. (out: !$B.builder_v >> $B.builder_v, s: string sn, k: int k): void =
    if k <= 0 then () else let val () = put(out, s) in loop(out, s, k - 1) end
in loop(out, s, count) end

(* The bytes of b appended to out; b is consumed *)
fn put_builder (out: !$B.builder_v >> $B.builder_v, b: $B.builder_v): void = let
  fun loop {l:agz}{n:pos}{m:nat | m <= n}{j:nat | j <= m} .<m - j>.
    (out: !$B.builder_v >> $B.builder_v, src: !$A.borrow(byte, l, n), j: int j, m: int m): void =
    if j >= m then ()
    else let
      val () = put_byte_v(out, byte2int0($A.read<byte>(src, j)))
    in loop(out, src, j + 1, m) end
  val @(ba, bl) = $B.into_arr(b)
  val @(fz, bv) = $A.freeze<byte>(ba)
  val () = loop(out, bv, 0, bl)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

fn builder_of {sn:nat} (s: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put(b, s)
in b end

(* A word of a command: the words are the lines of the command's text *)
fn word {sn:nat} (command: !$B.builder_v >> $B.builder_v, s: string sn): void = let
  val () = put(command, s)
in put_byte_v(command, 10) end

(* The path of a file or directory below the work directory: dir, then rest *)
fn join {sd,sr:nat} (dir: string sd, rest: string sr): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put(b, dir)
  val () = put(b, rest)
in b end

(* ============================================================
   Failure: the message, the work directory kept (keep-on-fail), status 1
   ============================================================ *)

(* The exact copy of b followed by a NUL, in an array of its size *)
fn exact_path (b: $B.builder_v): [l:agz][n:pos | n <= 524289] @($A.arr(byte, l, n), int n) = let
  val @(small, len) = $B.into_arr(b)
  val grown = $A.alloc<byte>(len + 1)
  val @(fz, bv) = $A.freeze<byte>(small)
  val @(text, rest) = $A.borrow_split<byte>(fz, bv, len)
  val () = $A.write_borrow(grown, 0, text, len)
  val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, text, rest))
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(grown, len + 1) end

(* The builder's text as a NUL-terminated path for spawn: the NUL is the byte after the text *)
fn spawn_path (b: $B.builder_v)
  : [l:agz][n:pos][cs:$A.cells][k:nat | k < n] ($P.NUL_AT(cs, n, k) | $A.barr(l, n, cs), int k) = let
  val @(small, len) = $B.into_arr(b)
  val grown = $A.alloc<byte>(len + 1)
  val @(fz, bv) = $A.freeze<byte>(small)
  val @(text, rest) = $A.borrow_split<byte>(fz, bv, len)
  val () = $A.write_borrow(grown, 0, text, len)
  val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, text, rest))
  val () = $A.free<byte>($A.thaw<byte>(fz))
  val (cells | a) = $A.barr_of_arr(grown)
  val (set | a) = $A.barr_set(a, len, 0)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  prval nul = $P.NUL_mk(len_ok, nul_ok)
in (nul | a, len) end

(* ============================================================
   Files: the process package has no working directory, so this process
   enters the directory and the children inherit it
   ============================================================ *)

fn chdir_to (path: $B.builder_v): bool = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_chdir(bv, pn)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ r of
  | ~$R.ok(_) => true
  | ~$R.err(_) => false
end

fn path_exists (path: $B.builder_v): bool = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_exists(bv, pn)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* The size of the file in bytes, ~1 when it cannot be had *)
fn size_of (path: $B.builder_v): int = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_size(bv, pn)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ r of
  | ~$R.ok(n) => n
  | ~$R.err(_) => ~1
end

(* Back to the work directory from dir below it: one level for the directory and one for each '/' *)
fn leave_dir {sd:nat} (dir: string sd): void = let
  fun loop {sl:nat}{i:nat | i <= sl} .<sl - i>.
    (s: string sl, slen: int sl, i: int i): void =
    if i >= slen then ()
    else let
      val () = (if char2int0(string_get_at(s, i)) = 47 then let val _ = chdir_to(builder_of("..")) in end else ())
    in loop(s, slen, i + 1) end
  val _ = chdir_to(builder_of(".."))
in loop(dir, g1u2i(string1_length(dir)), 0) end

(* The file at path holds exactly text *)
fn write_text (path: $B.builder_v, text: $B.builder_v): bool = let
  val @(pa, pn) = exact_path(path)
  val @(pfz, pbv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(pbv, pn, $F.WriteOnly(), $F.CreateOrTruncate(), 420)
  val () = $A.drop<byte>(pfz, pbv)
  val () = $A.free<byte>($A.thaw<byte>(pfz))
in
  case+ opened of
  | ~$R.err(_) => let val () = $B.builder_free(text) in false end
  | ~$R.ok(fd) => let
      val @(ta, tn) = exact_path(text)
      val @(tfz, tbv) = $A.freeze<byte>(ta)
      val k = tn - 1
      val @(left, right) = $A.borrow_split<byte>(tfz, tbv, k)
      val wrote = (if k > 0 then (case+ $F.file_write(fd, left, k) of
        | ~$R.ok(_) => true
        | ~$R.err(_) => false) else true): bool
      val () = $A.drop<byte>(tfz, $A.borrow_join<byte>(tfz, left, right))
      val () = $A.free<byte>($A.thaw<byte>(tfz))
      val closed = (case+ $F.file_close(fd) of
        | ~$R.ok(_) => true
        | ~$R.err(_) => false): bool
    in wrote && closed end
end

(* ============================================================
   Running a command: words are lines; the first is the program.
   Its output goes to files, opened here before the directory is entered.
   ============================================================ *)

fun find_newline {lb:agz}{n:pos}{p,t:nat | p <= t; t <= n} .<t - p>.
  (bv: !$A.borrow(byte, lb, n), p: int p, t: int t): [r:nat | p <= r; r <= t] int r =
  if p >= t then p
  else if byte2int0($A.read<byte>(bv, p)) = 10 then p
  else find_newline(bv, p + 1, t)

fn arg_of (b: $B.builder_v): $P.arg_entry = let
  val @(arr, len) = $B.into_arr(b)
in @(arr, len) end

(* bv[s, e) as a builder *)
fn slice_of {lb:agz}{n:pos}{s,e:nat | s <= e; e <= n}
  (bv: !$A.borrow(byte, lb, n), s: int s, e: int e): $B.builder_v = let
  fun loop {j:nat | j <= e} .<e - j>.
    (out: !$B.builder_v >> $B.builder_v, src: !$A.borrow(byte, lb, n), j: int j, e: int e): void =
    if j >= e then ()
    else let
      val () = put_byte_v(out, byte2int0($A.read<byte>(src, j)))
    in loop(out, src, j + 1, e) end
  var b : $B.builder_v = $B.create()
  val () = (if s <= e then loop(b, bv, s, e) else ())
in b end

fun split_lines {lb:agz}{n:pos}{p,t:nat | p <= t; t <= n} .<t - p>.
  (bv: !$A.borrow(byte, lb, n), p: int p, t: int t, acc: $L.listv($P.arg_entry))
  : $L.listv($P.arg_entry) =
  if p >= t then acc
  else let
    val we = find_newline(bv, p, t)
    val acc2 = (if we > p then $L.list_vt_cons(arg_of(slice_of(bv, p, we)), acc) else acc)
      : $L.listv($P.arg_entry)
  in
    if we >= t then acc2 else split_lines(bv, we + 1, t, acc2)
  end

fun reverse_args {n:nat} .<n>.
  (xs: $L.list_vt($P.arg_entry, n), acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  case+ xs of
  | ~$L.list_vt_nil() => acc
  | ~$L.list_vt_cons(x, tl) => reverse_args(tl, $L.list_vt_cons(x, acc))

fun free_args {n:nat} .<n>. (xs: $L.list_vt($P.arg_entry, n)): void =
  case+ xs of
  | ~$L.list_vt_nil() => ()
  | ~$L.list_vt_cons(@(arr, _), tl) => let val () = $A.free<byte>(arr) in free_args(tl) end

(* The first word of the command (the program) and all its words *)
fn command_parts (command: $B.builder_v): @($B.builder_v, $L.listv($P.arg_entry)) = let
  val @(arr, total) = $B.into_arr(command)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val first_end = find_newline(bv, 0, total)
  val program = slice_of(bv, 0, first_end)
  val reversed = split_lines(bv, 0, total, $L.list_vt_nil())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(program, reverse_args(reversed, $L.list_vt_nil())) end

fn open_stream (path: $B.builder_v, opening: $F.opening): $P.stream_config(false) = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(bv, pn, $F.WriteOnly(), opening, 420)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ opened of
  | ~$R.ok(fd) => $P.inherit_fd(fd)
  | ~$R.err(_) => $P.dev_null()
end

(* The program run with the given streams and environment entries added; its exit status, 127 when it did not start *)
fn spawn_wait (command: $B.builder_v, out_cfg: $P.stream_config(false), err_cfg: $P.stream_config(false),
  extra: $L.listv($P.arg_entry)): int = let
  val @(program, argv) = command_parts(command)
  val (nul | exec, _) = spawn_path(program)
  val @(fz, bv) = $A.barr_freeze(exec)
  val spawned = (case+ extra of
    | ~$L.list_vt_nil() =>
      $P.spawn_inherit_env_proved(nul | bv, argv, $P.dev_null(), out_cfg, err_cfg)
    | $L.list_vt_cons(_, _) =>
      $P.spawn_inherit_env_with_proved(nul | bv, argv, extra, $P.dev_null(), out_cfg, err_cfg))
    : $R.result($P.spawn_pipes(false, false, false), int)
  val status = (case+ spawned of
    | ~$R.err(_) => 127
    | ~$R.ok(sp) => let
        val+ ~$P.spawn_pipes_mk(child, in_end, out_end, err_end) = sp
        val () = $P.pipe_end_close(in_end)
        val () = $P.pipe_end_close(out_end)
        val () = $P.pipe_end_close(err_end)
      in
        case+ $P.child_wait(child) of
        | ~$R.ok(n) => n
        | ~$R.err(_) => ~1
      end): int
  val () = $A.cborrow_drop(fz, bv)
  val () = $A.barr_free($A.barr_thaw(fz))
in status end

(* The command run in dir (below the work directory; "" for the work directory itself) *)
fn run_in {sd:nat} (dir: string sd, command: $B.builder_v, out_cfg: $P.stream_config(false),
  err_cfg: $P.stream_config(false), extra: $L.listv($P.arg_entry)): int = let
  val inside = (if string1_length(dir) = 0 then true else chdir_to(builder_of(dir))): bool
  val status = (if inside then spawn_wait(command, out_cfg, err_cfg, extra) else let
      val () = $B.builder_free(command)
      val () = (case+ out_cfg of
        | ~$P.inherit_fd(f) => $R.discard<int><$F.io_error>($F.file_close(f))
        | ~$P.dev_null() => ()
        | ~$P.inherit() => ())
      val () = (case+ err_cfg of
        | ~$P.inherit_fd(f) => $R.discard<int><$F.io_error>($F.file_close(f))
        | ~$P.dev_null() => ()
        | ~$P.inherit() => ())
      val () = free_args(extra)
    in 126 end): int
  val () = (if inside then (if string1_length(dir) = 0 then () else leave_dir(dir)) else ())
in status end

(* ============================================================
   The bats under test, and the steps of a case
   ============================================================ *)

datavtype tool = {l:agz}{n:pos} tool_mk of ($A.arr(byte, l, n), int n)

fn put_bats (command: !$B.builder_v >> $B.builder_v, t: !tool): void = let
  fun loop {l:agz}{n:nat}{i:nat | i <= n} .<n - i>.
    (out: !$B.builder_v >> $B.builder_v, a: !$A.arr(byte, l, n), n: int n, i: int i): void =
    if i >= n then ()
    else let
      val () = put_byte_v(out, byte2int0($A.get<byte>(a, i)))
    in loop(out, a, n, i + 1) end
  val+ @tool_mk(a, n) = t
  val () = loop(command, a, n, 0)
  prval () = fold@(t)
in put_byte_v(command, 10) end
fn nil_env (): $L.listv($P.arg_entry) = $L.list_vt_nil()

fn run_log {sd:nat}{sl:nat} (dir: string sd, command: $B.builder_v, log: string sl): int = let
  val out_cfg = open_stream(builder_of(log), $F.CreateOrTruncate())
  val err_cfg = open_stream(builder_of(log), $F.AppendExisting())
in run_in(dir, command, out_cfg, err_cfg, nil_env()) end

fn run_split {sd:nat}{so:nat}{se:nat} (dir: string sd, command: $B.builder_v, out: string so, err: string se): int = let
  val out_cfg = open_stream(builder_of(out), $F.CreateOrTruncate())
  val err_cfg = open_stream(builder_of(err), $F.CreateOrTruncate())
in run_in(dir, command, out_cfg, err_cfg, nil_env()) end

fn run_show (command: $B.builder_v): int =
  run_in("", command, $P.inherit(), $P.inherit(), nil_env())

fn show_file {sn:nat} (file: string sn): void = let
  val () = fileref_flush(stdout_ref)
  var c : $B.builder_v = $B.create()
  val () = put(c, "cat\n")
  val () = put(c, file)
  val _ = run_show(c)
in end

(* The failure: the message, the file that explains it, the work directory kept (keep-on-fail), status 1 *)
fn die_file {sa,sb,sf:nat} (what: string sa, detail: string sb, file: string sf): void = let
  val () = println! ("FAIL: ", what, detail, " [", file, "]")
  val () = show_file(file)
  val () = println! ("kept: tests/build-jobs/work (build-jobs)")
in exit_void(1) end

fn die {sa,sb:nat} (what: string sa, detail: string sb): void = let
  val () = println! ("FAIL: ", what, detail)
  val () = println! ("kept: tests/build-jobs/work (build-jobs)")
in exit_void(1) end

(* A step of setup that must succeed: rm, mkdir, cp, git *)
fn setup {sc:nat} (command: $B.builder_v, what: string sc): void =
  if run_log("", command, "setup.log") = 0 then () else die_file("setup: ", what, "setup.log")

fn put_file {sd,sr:nat} (dir: string sd, rest: string sr, text: $B.builder_v): void =
  if write_text(join(dir, rest), text) then () else die("cannot write ", rest)

fn dir_command {sp,sd,ss:nat} (front: string sp, dir: string sd, suffix: string ss): $B.builder_v = let
  var c : $B.builder_v = $B.create()
  val () = put(c, front)
  val () = put(c, dir)
  val () = put(c, suffix)
in c end


(* ============================================================
   The stand-ins and the projects
   ============================================================ *)

(* The value of the environment variable name appended to out *)
fn put_env {sn:nat} (out: !$B.builder_v >> $B.builder_v, name: string sn): void = let
  val @(na, nn) = exact_path(builder_of(name))
  val buf = $A.alloc<byte>(4096)
  val got = $E.get_cstr(na, nn, buf, 4096)
  fun loop {l:agz}{k:nat | k <= 4096}{j:nat | j <= k} .<k - j>.
    (out: !$B.builder_v >> $B.builder_v, buf: !$A.arr(byte, l, 4096), k: int k, j: int j): void =
    if j >= k then ()
    else let
      val () = put_byte_v(out, byte2int0($A.get<byte>(buf, j)))
    in loop(out, buf, k, j + 1) end
  val k = (case+ got of
    | ~$R.some(k) => k
    | ~$R.none() => 0): [k:nat | k <= 4096] int k
  val () = loop(out, buf, k, 0)
  val () = $A.free<byte>(buf)
in $A.free<byte>(na) end

(* bats runs with the stand-in clang and getconf first in PATH (dist/debug of this project, seen from work/<project>),
   BATS_CACHE_DIR, BATS_SLOTS and BATS_LOCK_DIR unset; env is NAME=VALUE lines, then the bats words *)
fn bats_cmd {se,sw:nat} (t: !tool, env: string se, words: string sw): $B.builder_v = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "env\n-u\nBATS_CACHE_DIR\n-u\nBATS_SLOTS\n-u\nBATS_LOCK_DIR\nPATH=../../dist/debug:")
  val () = put_env(c, "PATH")
  val () = put(c, "\nSTANDIN_DIR=../../dist/debug\n")
  val () = put(c, env)
  val () = put_bats(c, t)
  val () = put(c, words)
in c end

(* bats in the project dir, its stdout and stderr in two files; the status *)
fn bats_split {sd,se,sw,so,sr:nat} (t: !tool, dir: string sd, env: string se, words: string sw, out: string so, err: string sr): int =
  run_split(dir, bats_cmd(t, env, words), out, err)

#define BUILD "build\n--only\ndebug\n--only\nnative"

(* The log of the stand-in clang has had most n compiles at once and none is running at its end *)
fn overlap_is {sn,sl:nat} (log: string sn, expected: int, label: string sl): void = let
  val @(best, running) = log_overlap(builder_of(log))
in
  if best = expected && running = 0 then ()
  else let
    val () = println! ("FAIL: ", label, ": ", best, " compiles at once (expected ", expected, "), ", running, " still running at the end")
  in die_file(label, ": the log of the compiles ", log) end
end

fn text_is {sf,sx,sl:nat} (file: string sf, expected: string sx, label: string sl): void = let
  val _ = write_text(builder_of("expected.txt"), builder_of(expected))
  var c : $B.builder_v = $B.create()
  val () = put(c, "cmp\n-s\n")
  val () = put(c, file)
  val () = put(c, "\nexpected.txt")
in if run_log("", c, "cmp.log") = 0 then () else die_file(label, ": the content of ", file) end

(* The two files hold the same bytes *)
fn same_file {sa,sb,sl:nat} (a: string sa, b: string sb, label: string sl): void = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "cmp\n")
  val () = put(c, a)
  val () = put(c, "\n")
  val () = put(c, b)
in if run_log("", c, "cmp.log") = 0 then () else die_file(label, ": the files differ: ", "cmp.log") end

(* A line of the file matches pattern (grep -a, basic expressions) *)
fn has {sf,sp,sl:nat} (file: string sf, pattern: string sp, label: string sl): void = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "grep\n-aq\n--\n")
  val () = put(c, pattern)
  val () = put(c, "\n")
  val () = put(c, file)
in if run_log("", c, "grep.log") = 0 then () else die_file(label, ": no line matches ", file) end

(* The two build/ trees hold the same files with the same bytes, without the records and the objects (their debug info names their directory) *)
fn same_tree {sa,sb,sl:nat} (a: string sa, b: string sb, label: string sl): void = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "diff\n-r\n-x\n.bats_valid\n-x\n.stash\n-x\n.bats_graph\n-x\n*.o\n")
  val () = put(c, a)
  val () = put(c, "\n")
  val () = put(c, b)
in if run_split("", c, "tree.diff", "tree.err") = 0 then () else die_file(label, ": the trees differ", "tree.diff") end

(* The program of dir prints expected *)
fn prints {sd,sx,sl:nat} (dir: string sd, expected: string sx, label: string sl): void = let
  val status = run_split(dir, builder_of("./dist/debug/tf"), "program.out", "program.err")
  val () = (if status = 0 then () else die_file(label, ": the program failed", "program.err"))
in text_is("program.out", expected, label) end

(* A project of six modules and a binary, the program prints 21: eight compiles of C files of the project, which a build makes *)
fn module {sd,sn:nat} (dir: string sd, n: string sn): void = let
  var path : $B.builder_v = $B.create()
  val () = put(path, dir)
  val () = put(path, "/src/m")
  val () = put(path, n)
  val () = put(path, ".bats")
  var text : $B.builder_v = $B.create()
  val () = put(text, "#include \"share/atspre_staload.hats\"\n\n#pub fn f_")
  val () = put(text, n)
  val () = put(text, " (): int\n\nimplement f_")
  val () = put(text, n)
  val () = put(text, " () = ")
  val () = put(text, n)
  val () = put(text, "\n")
in (if write_text(path, text) then () else die("cannot write a module of ", dir)) end

fn project {sd:nat} (dir: string sd): void = let
  val () = setup(dir_command("rm\n-rf\n", dir, ""), "rm project")
  val () = setup(dir_command("mkdir\n-p\n", dir, "/src/bin"), "mkdir project")
  val () = put_file(dir, "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\n"))
  val () = module(dir, "1")
  val () = module(dir, "2")
  val () = module(dir, "3")
  val () = module(dir, "4")
  val () = module(dir, "5")
  val () = module(dir, "6")
in put_file(dir, "/src/bin/tf.bats", builder_of("#include \"share/atspre_staload.hats\"\nstaload \"m1.sats\"\nstaload \"m2.sats\"\nstaload \"m3.sats\"\nstaload \"m4.sats\"\nstaload \"m5.sats\"\nstaload \"m6.sats\"\nimplement main0 () = println! (f_1 () + f_2 () + f_3 () + f_4 () + f_5 () + f_6 ())\n")) end

(* A build of a new project in dir that must pass: the compiles overlap as the log shows, the program prints 21 *)
fn overlaps {sd,se,sw,sg,sl:nat} (t: !tool, dir: string sd, env: string se, words: string sw, log: string sg, expected: int, label: string sl): void = let
  val () = project(dir)
  val status = bats_split(t, dir, env, words, "build.out", "build.err")
  val () = (if status = 0 then () else die_file(label, ": the build failed", "build.out"))
  val () = overlap_is(log, expected, label)
in prints(dir, "21\n", label) end

(* ============================================================
   The cases
   ============================================================ *)

(* jobs-count: --jobs 2 runs two compiles at once, and never three *)
fn case_jobs_count (t: !tool): void =
  overlaps(t, "jobs_two", "CC_LOG=../jobs_two.log\nCC_WAIT_FOR=2\n", "build\n--only\ndebug\n--only\nnative\n--jobs\n2", "jobs_two.log", 2, "--jobs 2")

(* jobs-short: -j is --jobs, and a count over what there is to compile runs them all *)
fn case_jobs_short (t: !tool): void = let
  val () = overlaps(t, "jobs_short", "CC_LOG=../jobs_short.log\nCC_WAIT_FOR=3\n", "build\n--only\ndebug\n--only\nnative\n-j\n3", "jobs_short.log", 3, "-j 3")
in overlaps(t, "jobs_one", "CC_LOG=../jobs_one.log\n", "build\n--only\ndebug\n--only\nnative\n--jobs\n1", "jobs_one.log", 1, "--jobs 1") end

(* jobs-cores: the default is the cores, which the stand-in getconf says are 3; the word cores is the same *)
fn case_jobs_cores (t: !tool): void = let
  val () = overlaps(t, "cores_default", "CC_LOG=../cores_default.log\nCC_WAIT_FOR=3\nGETCONF_ANSWER=3\n", BUILD, "cores_default.log", 3, "no --jobs")
in overlaps(t, "cores_word", "CC_LOG=../cores_word.log\nCC_WAIT_FOR=3\nGETCONF_ANSWER=3\n", "build\n--only\ndebug\n--only\nnative\n--jobs\ncores", "cores_word.log", 3, "--jobs cores") end

(* jobs-slots: BATS_SLOTS divides the count, rounded down, at least 1 *)
fn case_jobs_slots (t: !tool): void = let
  val () = overlaps(t, "slots_four", "CC_LOG=../slots_four.log\nCC_WAIT_FOR=2\nBATS_SLOTS=2\nBATS_LOCK_DIR=../slots\n", "build\n--only\ndebug\n--only\nnative\n--jobs\n4", "slots_four.log", 2, "BATS_SLOTS=2 --jobs 4")
in overlaps(t, "slots_cores", "CC_LOG=../slots_cores.log\nGETCONF_ANSWER=3\nBATS_SLOTS=2\nBATS_LOCK_DIR=../slots\n", BUILD, "slots_cores.log", 1, "BATS_SLOTS=2 and 3 cores") end

(* jobs-getconf: a getconf that gives no number from 1 up is said once and is 1 core *)
fn case_jobs_getconf (t: !tool): void = let
  val () = overlaps(t, "getconf_word", "CC_LOG=../getconf_word.log\nGETCONF_ANSWER=many\n", BUILD, "getconf_word.log", 1, "getconf says a word")
  val () = has("build.err", "^warning: getconf _NPROCESSORS_ONLN gave no number from 1 up, so --jobs cores is 1$", "getconf says a word, said")
  val () = overlaps(t, "getconf_fails", "CC_LOG=../getconf_fails.log\n", BUILD, "getconf_fails.log", 1, "getconf fails")
  var c : $B.builder_v = $B.create()
  val () = put(c, "grep\n-ac\n^warning: getconf\nbuild.err")
  val _ = run_split("", c, "warnings.out", "warnings.err")
in text_is("warnings.out", "1\n", "getconf fails, said once") end

(* jobs-same: the files of build/ and what bats printed are the same for --jobs 1, 2 and cores *)
fn case_jobs_same (t: !tool): void = let
  val env = "GETCONF_ANSWER=3\n"
  val () = project("same_one")
  val s1 = bats_split(t, "same_one", env, "build\n--only\ndebug\n--only\nnative\n--jobs\n1", "same_one.out", "same_one.err")
  val () = project("same_two")
  val s2 = bats_split(t, "same_two", env, "build\n--only\ndebug\n--only\nnative\n--jobs\n2", "same_two.out", "same_two.err")
  val () = project("same_cores")
  val s3 = bats_split(t, "same_cores", env, "build\n--only\ndebug\n--only\nnative\n--jobs\ncores", "same_cores.out", "same_cores.err")
  val () = (if s1 = 0 && s2 = 0 && s3 = 0 then () else die_file("a build failed", "", "same_one.err"))
  val () = same_file("same_one.out", "same_two.out", "stdout of --jobs 1 and 2")
  val () = same_file("same_one.out", "same_cores.out", "stdout of --jobs 1 and cores")
  val () = same_file("same_one.err", "same_two.err", "stderr of --jobs 1 and 2")
  val () = same_file("same_one.err", "same_cores.err", "stderr of --jobs 1 and cores")
  val () = same_tree("same_one/build", "same_two/build", "build/ of --jobs 1 and 2")
in same_tree("same_one/build", "same_cores/build", "build/ of --jobs 1 and cores") end

(* jobs-invalid: a value that is not a number from 1 or the word cores is refused before anything is run *)
fn refused {sd,sw,sl:nat} (t: !tool, dir: string sd, words: string sw, label: string sl): void = let
  val () = project(dir)
  val status = bats_split(t, dir, "", words, "refused.out", "refused.err")
  val () = (if status = 1 then () else die_file(label, ": the status is not 1", "refused.err"))
  val () = text_is("refused.err", "error: --jobs takes a number from 1 or the word cores\n", label)
in (if path_exists(join(dir, "/build")) then die(label, ": a build/ was made") else ()) end

fn case_jobs_invalid (t: !tool): void = let
  val () = refused(t, "refused_zero", "build\n--jobs\n0", "--jobs 0")
  val () = refused(t, "refused_word", "build\n--jobs\nmany", "--jobs many")
  val () = refused(t, "refused_digits", "build\n--jobs\n2x", "--jobs 2x")
  val () = refused(t, "refused_empty", "build\n--jobs\n\n--only\ndebug", "--jobs with an empty value")
  val () = refused(t, "refused_check", "check\n-j\n0", "check -j 0")
  val () = project("check_jobs")
  val status = bats_split(t, "check_jobs", "", "check\n--jobs\n2", "check_jobs.out", "check_jobs.err")
in (if status = 0 then () else die_file("check --jobs 2 failed", "", "check_jobs.err")) end

(* A project of two modules, both of which the stand-in fails to compile *)
fn small_project {sd:nat} (dir: string sd): void = let
  val () = setup(dir_command("rm\n-rf\n", dir, ""), "rm project")
  val () = setup(dir_command("mkdir\n-p\n", dir, "/src/bin"), "mkdir project")
  val () = put_file(dir, "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\n"))
  val () = module(dir, "1")
  val () = module(dir, "2")
in put_file(dir, "/src/bin/tf.bats", builder_of("#include \"share/atspre_staload.hats\"\nstaload \"m1.sats\"\nstaload \"m2.sats\"\nimplement main0 () = println! (f_1 () + f_2 ())\n")) end

(* The messages of a build with failing compiles: the compiler's and the notes, not the linker's (which names the directory) *)
fn messages_of {sf,so:nat} (out: string sf, messages: string so): void = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "grep\n-a\n-e\n^stand-in\n-e\n^error: cc failed\n")
  val () = put(c, out)
  val s = run_split("", c, messages, "messages.err")
in (if s = 0 then () else die_file("no message of a failing compile in ", out, out)) end

(* jobs-failure: two compiles fail, the second finishing first: both messages, in the order of --jobs 1, and no compile is left running *)
fn case_jobs_failure (t: !tool): void = let
  val () = small_project("fail_one")
  val s1 = bats_split(t, "fail_one", "CC_LOG=../fail_one.log\nCC_FAIL_A=m1_dats.c\nCC_FAIL_B=m2_dats.c\n", "build\n--only\ndebug\n--only\nnative\n--jobs\n1", "fail_one.out", "fail_one.err")
  val () = (if s1 = 1 then () else die_file("--jobs 1 with two failing compiles did not fail with 1", "", "fail_one.out"))
  val () = messages_of("fail_one.out", "fail_one.msgs")
  val () = has("fail_one.msgs", "^error: cc failed for src module m1_dats.c", "the first failing module is said")
  val () = has("fail_one.msgs", "^error: cc failed for src module m2_dats.c", "the second failing module is said")
  val () = overlap_is("fail_one.log", 1, "--jobs 1 with failures")
  (* the module whose compile starts first is the slow one, so the second failure comes first and is not the one said first *)
  val _ = run_split("", builder_of("grep\n-a\n-m1\n-e\nm1_dats.c\n-e\nm2_dats.c\nfail_one.log"), "first.txt", "first.err")
  val m1_first = (run_split("", builder_of("grep\n-aq\nm1_dats.c\nfirst.txt"), "first.out", "first.err") = 0): bool
  val () = small_project("fail_two")
  val s2 = bats_split(t, "fail_two", (if m1_first then "CC_LOG=../fail_two.log\nCC_WAIT_FOR=2\nCC_SLOW=m1_dats.c\nCC_FAIL_A=m1_dats.c\nCC_FAIL_B=m2_dats.c\n" else "CC_LOG=../fail_two.log\nCC_WAIT_FOR=2\nCC_SLOW=m2_dats.c\nCC_FAIL_A=m1_dats.c\nCC_FAIL_B=m2_dats.c\n"), "build\n--only\ndebug\n--only\nnative\n--jobs\n2", "fail_two.out", "fail_two.err")
  val () = (if s2 = 1 then () else die_file("--jobs 2 with two failing compiles did not fail with 1", "", "fail_two.out"))
  val () = overlap_is("fail_two.log", 2, "--jobs 2 with failures")
  val () = messages_of("fail_two.out", "fail_two.msgs")
in same_file("fail_one.msgs", "fail_two.msgs", "the messages of --jobs 1 and 2") end

fun find_nul {l:agz}{k:nat | k <= 4096}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, 4096), k: int k, p: int p): [r:nat | p <= r; r <= k] int r =
  if p >= k then p
  else if byte2int0($A.get<byte>(buf, p)) = 0 then p
  else find_nul(buf, k, p + 1)

datavtype given = given_none | given_some of tool

(* The second word of the arguments in buf[0, k), copied: it follows the first NUL; it must be an absolute path *)
fn tool_of_buf {l:agz}{k:nat | k <= 4096} (buf: !$A.arr(byte, l, 4096), k: int k): given = let
  val zero = find_nul(buf, k, 0)
  val start = (if zero < k then zero + 1 else k): [s:nat | s <= k] int s
  val stop = find_nul(buf, k, start)
  fun copy {l:agz}{la:agz}{n:pos}{s,e:nat | s <= e; e <= 4096}{j:nat | j <= n} .<n - j>.
    (src: !$A.arr(byte, l, 4096), dst: !$A.arr(byte, la, n), s: int s, e: int e, j: int j, n: int n): void =
    if j >= n then ()
    else if s + j >= e then ()
    else let
      val () = $A.set<byte>(dst, j, $A.int2byte($AR.low_byte(byte2int0($A.get<byte>(src, s + j)))))
    in copy(src, dst, s, e, j + 1, n) end
  val width = stop - start
in
  if width > 0 then let
    val dst = $A.alloc<byte>(width)
    val () = copy(buf, dst, start, stop, 0, width)
    val first = byte2int0($A.get<byte>(dst, 0))
  in
    if first = 47 then given_some(tool_mk(dst, width))
    else let val () = $A.free<byte>(dst) in given_none() end
  end
  else given_none()
end

fn tool_of_args (): given = let
  val buf = $A.alloc<byte>(4096)
  val k = (case+ $E.args_read(buf, 4096) of | ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= 4096] int k
  val result = tool_of_buf(buf, k)
  val () = $A.free<byte>(buf)
in result end


(* jobs-stderr: a failing compile that writes far more than a pipe holds ends, and its first 65536 bytes are printed, then the note *)
fn case_jobs_stderr (t: !tool): void = let
  val () = small_project("stderr_big")
  val s = bats_split(t, "stderr_big", "CC_FAIL_A=m1_dats.c\nCC_BIG=m1_dats.c\n", "build\n--only\ndebug\n--only\nnative\n--jobs\n2", "stderr_big.out", "stderr_big.err")
  val () = (if s = 1 then () else die_file("a failing compile of 200000 bytes did not fail with 1", "", "stderr_big.out"))
  val found = run_split("", builder_of("grep\n-aq\n--\n^x\\{32767\\}x\\{32726\\}error: cc failed for src module m1_dats.c$\nstderr_big.out"), "grep.out", "grep.err")
in (if found = 0 then () else die("the first 65536 bytes of the compiler's messages, then the note, are not in stderr_big.out", "")) end

(* jobs-noisy: a compile that succeeds and writes far more than a pipe holds to stderr is a success (the pipe is read to its end, not closed under the writer) *)
fn case_jobs_noisy (t: !tool): void =
  overlaps(t, "noisy", "CC_LOG=../noisy.log\nCC_NOISY=m1_dats.c\nCC_WAIT_FOR=2\n", "build\n--only\ndebug\n--only\nnative\n--jobs\n2", "noisy.log", 2, "a successful compile with 200000 bytes on stderr")

fn run_all (t: !tool): void = let
  val () = case_jobs_count(t)
  val () = case_jobs_short(t)
  val () = case_jobs_cores(t)
  val () = case_jobs_slots(t)
  val () = case_jobs_getconf(t)
  val () = case_jobs_same(t)
  val () = case_jobs_invalid(t)
  val () = case_jobs_failure(t)
  val () = case_jobs_stderr(t)
in case_jobs_noisy(t) end

implement main0 () = let
  val given = tool_of_args()
in
  case+ given of
  | ~given_none() => let
      val () = println! ("usage: build_jobs <absolute path of the bats under test>")
    in exit_void(2) end
  | ~given_some(t) => let
      val _ = run_show(builder_of("rm\n-rf\nwork"))
      val _ = run_show(builder_of("mkdir\nwork"))
      val inside = chdir_to(builder_of("work"))
      val () = (if inside then () else exit_void(1))
      val () = run_all(t)
      val _ = chdir_to(builder_of(".."))
      val _ = run_show(builder_of("rm\n-rf\nwork"))
      val () = println! ("build-jobs: ok")
      val+ ~tool_mk(a, _) = t
    in $A.free<byte>(a) end
end
