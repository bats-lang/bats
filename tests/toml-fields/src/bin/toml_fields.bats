(* toml-fields -- which bats.toml fields reach build/, and bats add and remove on whole manifests (bats#429, bats#381, bats#446); keyword: toml-fields *)
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
   Failure: the message, the work directory removed, status 1
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

(* bats runs with BATS_CACHE_DIR unset, as the cases need a build/ of their own; tail is the words after it *)
fn bats_cmd {sn:nat} (t: !tool, tail: string sn): $B.builder_v = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "env\n-u\nBATS_CACHE_DIR\n")
  val () = put_bats(c, t)
  val () = put(c, tail)
in c end

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
  val () = println! ("kept: tests/toml-fields/work (toml-fields)")
in exit_void(1) end

fn die {sa,sb:nat} (what: string sa, detail: string sb): void = let
  val () = println! ("FAIL: ", what, detail)
  val () = println! ("kept: tests/toml-fields/work (toml-fields)")
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

(* ---- the checks on files ---- *)

(* The file holds exactly expected *)
fn text_is {sf,sx,sl:nat} (file: string sf, expected: string sx, label: string sl): void = let
  val _ = write_text(builder_of("expected.txt"), builder_of(expected))
  var c : $B.builder_v = $B.create()
  val () = put(c, "cmp\n-s\n")
  val () = put(c, file)
  val () = put(c, "\nexpected.txt")
in if run_log("", c, "cmp.log") = 0 then () else die_file(label, ": the content of " , file) end

(* A line of the file matches pattern (grep -a, basic expressions) *)
fn has {sf,sp,sl:nat} (file: string sf, pattern: string sp, label: string sl): void = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "grep\n-aq\n--\n")
  val () = put(c, pattern)
  val () = put(c, "\n")
  val () = put(c, file)
in if run_log("", c, "grep.log") = 0 then () else die_file(label, ": no line matches ", file) end

fn lacks {sf,sp,sl:nat} (file: string sf, pattern: string sp, label: string sl): void = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "grep\n-aq\n--\n")
  val () = put(c, pattern)
  val () = put(c, "\n")
  val () = put(c, file)
in if run_log("", c, "grep.log") = 1 then () else die_file(label, ": a line matches ", file) end

(* patsopt ran for no module of the log but the entry's generated one, and no cached one *)
fn none_ran {sf,sl:nat} (log: string sf, label: string sl): void = let
  var first : $B.builder_v = $B.create()
  val () = put(first, "grep\n-a\n--\n+ patsopt\n")
  val () = put(first, log)
  val s1 = run_split("", first, "ran1.out", "ran.err")
  val s2 = run_split("", builder_of("grep\n-av\n--\n_bats_entry_\nran1.out"), "ran2.out", "ran.err")
  val s3 = run_split("", builder_of("grep\n-avq\n--\n(cached)\nran2.out"), "ran3.out", "ran.err")
in if s1 <= 1 && s2 <= 1 && s3 = 1 then () else die_file(label, ": patsopt ran again in ", log) end

(* The two build/ trees hold the same files with the same bytes, without records, stash, graph and objects *)
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

(* ---- bats in a directory ---- *)

fn build_ok {sd,sl,se:nat} (t: !tool, dir: string sd, log: string sl, extra: string se): void = let
  val c = bats_cmd(t, "-v\nbuild\n--only\ndebug\n--only\nnative")
  var c2 : $B.builder_v = c
  val () = put(c2, extra)
in if run_log(dir, c2, log) = 0 then () else die_file("build failed in ", dir, log) end

(* build without -v; out and err are kept apart *)
fn build_plain {sd,sl,so,se:nat} (t: !tool, dir: string sd, extra: string se, out: string sl, err: string so): int = let
  val c = bats_cmd(t, "build\n--only\ndebug\n--only\nnative")
  var c2 : $B.builder_v = c
  val () = put(c2, extra)
in run_split(dir, c2, out, err) end

fn bats_ok {sd,sw,sl:nat} (t: !tool, dir: string sd, words: string sw, log: string sl): void = let
  val c = bats_cmd(t, words)
in if run_log(dir, c, log) = 0 then () else die_file("bats failed in ", dir, log) end

(* ---- the projects ---- *)

#define BASE "[package]\nname = \"tf\"\nkind = \"bin\"\n"
#define YES_UNSAFE "[package]\nname = \"tf\"\nkind = \"bin\"\nunsafe = true\n"
#define PADDING "# a line of padding that makes the manifest longer than the buffer it was once read in\n"

(* A binary of two modules under dir *)
fn module {sd:nat} (dir: string sd, toml: $B.builder_v): void = let
  val () = setup(dir_command("rm\n-rf\n", dir, ""), "rm module")
  val () = setup(dir_command("mkdir\n-p\n", dir, "/src/bin"), "mkdir module")
  val () = put_file(dir, "/bats.toml", toml)
  val () = put_file(dir, "/src/m.bats", builder_of("#include \"share/atspre_staload.hats\"\n\n#pub fn f (): int\n\nimplement f () = 1\n"))
in put_file(dir, "/src/bin/tf.bats", builder_of("#include \"share/atspre_staload.hats\"\nstaload \"m.sats\"\nimplement main0 () = println! (f ())\n")) end

(* The module with a $UNSAFE block, which only an unsafe package may have *)
fn unsafe_module {sd:nat} (dir: string sd, toml: $B.builder_v): void = let
  val () = module(dir, toml)
in put_file(dir, "/src/m.bats", builder_of("#include \"share/atspre_staload.hats\"\n\n#pub fn f (): int\n\n$UNSAFE begin\n%{\nstatic int unused_helper (void) { return 3; }\n%}\nend\n\nimplement f () = 1\n")) end

fn padded {sn:nat} (text: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_times(b, PADDING, 100)
  val () = put(b, text)
in b end

(* ============================================================
   The cases
   ============================================================ *)

(* unchanged-fields: fields the build does not read leave a restored build/ whole and equal to a cold one *)
fn unchanged {sl,sm:nat} (t: !tool, label: string sl, second: string sm): void = let
  val () = module("first", builder_of(BASE))
  val () = build_ok(t, "first", "first.log", "")
  val () = module("restored", builder_of(second))
  val () = setup(builder_of("cp\n-R\nfirst/build\nrestored/build"), "cp build")
  val () = build_ok(t, "restored", "restored.log", "")
  val () = none_ran("restored.log", label)
  val () = lacks("restored.log", "^bats: dropping build/", label)
  val () = module("cold", builder_of(second))
  val () = build_ok(t, "cold", "cold.log", "")
  val () = same_tree("restored/build", "cold/build", label)
in prints("restored", "1\n", label) end

fn case_unchanged (t: !tool): void = let
  val () = unchanged(t, "name", "[package]\nname = \"another\"\nkind = \"bin\"\n")
  val () = unchanged(t, "version, trunk and ats2", "[package]\nname = \"tf\"\nkind = \"bin\"\nversion = \"1.2.3\"\ntrunk = \"master\"\nats2 = \"x\"\n")
  val () = unchanged(t, "tables nothing reads", "[package]\nname = \"tf\"\nkind = \"bin\"\n\n[build]\nopt = 3\n\n[test]\ntimeout = 9\n")
in unchanged(t, "unsafe = true with no unsafe block", "[package]\nname = \"tf\"\nkind = \"bin\"\nunsafe = true\n") end

(* kind: bats build refuses a library whatever build/ holds, and a bin again builds from the same build/ *)
fn case_kind (t: !tool): void = let
  val () = module("kind_project", builder_of(BASE))
  val () = build_ok(t, "kind_project", "kind_first.log", "")
  val () = put_file("kind_project", "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"lib\"\n"))
  val status = build_plain(t, "kind_project", "", "kind_lib.out", "kind_lib.err")
  val () = (if status = 1 then () else die_file("kind = lib built", "", "kind_lib.err"))
  val () = text_is("kind_lib.err", "error: 'bats build' is only for binary packages (kind = \"bin\")\n", "kind = lib")
  val () = put_file("kind_project", "/bats.toml", builder_of(BASE))
  val () = build_ok(t, "kind_project", "kind_again.log", "")
in none_ran("kind_again.log", "kind back to bin") end

(* unsafe: the field the emitted modules depend on; false over a restored build/ is an error, true builds *)
fn case_unsafe (t: !tool): void = let
  val () = unsafe_module("unsafe_project", builder_of(YES_UNSAFE))
  val () = build_ok(t, "unsafe_project", "unsafe_first.log", "")
  val () = put_file("unsafe_project", "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\nunsafe = false\n"))
  val () = setup(builder_of("rm\n-f\nunsafe_project/dist/debug/tf"), "rm program")
  val status = build_plain(t, "unsafe_project", "", "unsafe_false.out", "unsafe_false.err")
  val () = (if status = 1 then () else die_file("unsafe = false over a restored build/ built", "", "unsafe_false.err"))
  val () = has("unsafe_false.err", "^error: error: .UNSAFE requires .unsafe = true. in bats.toml", "unsafe = false")
  val () = (if path_exists(builder_of("unsafe_project/dist/debug/tf")) then die("unsafe = false left a program", "") else ())
  val () = put_file("unsafe_project", "/bats.toml", builder_of(YES_UNSAFE))
  val () = build_ok(t, "unsafe_project", "unsafe_again.log", "")
in prints("unsafe_project", "1\n", "unsafe again") end

(* a manifest over 8192 bytes: emission reads `unsafe = true` as validation does *)
fn case_large_manifest (t: !tool): void = let
  val () = unsafe_module("large_project", padded(YES_UNSAFE))
  val () = (if size_of(builder_of("large_project/bats.toml")) > 8192 then () else die("the manifest is not large", ""))
  val () = build_ok(t, "large_project", "large_manifest.log", "")
in prints("large_project", "1\n", "large manifest") end

(* large-library: a manifest over 8192 bytes with [package] after the padding is read whole by upload and the docs *)
fn case_large_library (t: !tool): void = let
  val () = setup(builder_of("rm\n-rf\nlarge_library\nlarge_repository"), "rm large")
  val () = setup(builder_of("mkdir\n-p\nlarge_library/src\nlarge_repository"), "mkdir large")
  val () = put_file("large_library", "/bats.toml", padded("[package]\nname = \"tflarge\"\nkind = \"lib\"\n"))
  val () = (if size_of(builder_of("large_library/bats.toml")) > 8192 then () else die("the library manifest is not large", ""))
  val () = put_file("large_library", "/src/lib.bats", builder_of("#pub fun f (): int\n\nimplement f () = 1\n"))
  val () = put_file("large_library", "/.gitignore", builder_of("build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n"))
  val git = "large_git.log"
  val () = (if run_log("large_library", builder_of("git\ninit\n-q\n-b\nmain\n."), git) = 0 then () else die_file("git init", "", git))
  val () = (if run_log("large_library", builder_of("git\nadd\n-A"), git) = 0 then () else die_file("git add", "", git))
  val () = (if run_log("large_library", builder_of("git\n-c\nuser.name=t\n-c\nuser.email=t@t\ncommit\n-q\n-m\nlarge"), git) = 0
    then () else die_file("git commit", "", git))
  val () = bats_ok(t, "large_library", "upload\n--repository\n../large_repository", "large_upload.log")
  val unzipped = run_split("", builder_of("unzip\n-p\nlarge_repository/tflarge/tflarge_*.bats\nbats.toml"), "archived.toml", "unzip.err")
  val () = (if unzipped = 0 then () else die_file("unzip of the archive", "", "unzip.err"))
  val () = has("archived.toml", "^name = \"tflarge\"$", "the archived manifest lacks the name")
  val () = has("archived.toml", "^version = \"", "the archived manifest lacks the version")
  val () = (if size_of(builder_of("archived.toml")) > size_of(builder_of("large_library/bats.toml")) then ()
    else die("the archived manifest is cut", ""))
  val () = has("archived.toml", "^# a line of padding", "the archived manifest lost its first lines")
  val () = bats_ok(t, "large_library", "check\n--repository\n../large_repository", "large_check.log")
in has("large_library/docs/index.md", "^# tflarge$", "the docs lack the package name") end

(* A library tfdep whose f is value, committed at date and uploaded to repo *)
fn publish {sd,sv:nat} (t: !tool, date: string sd, value: string sv): void = let
  val () = setup(builder_of("rm\n-rf\npublished"), "rm published")
  val () = setup(builder_of("mkdir\n-p\npublished/src"), "mkdir published")
  val () = put_file("published", "/bats.toml", builder_of("[package]\nname = \"tfdep\"\nkind = \"lib\"\n"))
  var lib : $B.builder_v = $B.create()
  val () = put(lib, "#pub fun f (): int\n\nimplement f () = ")
  val () = put(lib, value)
  val () = put(lib, "\n")
  val () = put_file("published", "/src/lib.bats", lib)
  val () = put_file("published", "/.gitignore", builder_of("build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n"))
  val git = "publish_git.log"
  val () = (if run_log("published", builder_of("git\ninit\n-q\n-b\nmain\n."), git) = 0 then () else die_file("git init", "", git))
  val () = (if run_log("published", builder_of("git\nadd\n-A"), git) = 0 then () else die_file("git add", "", git))
  var commit : $B.builder_v = $B.create()
  val () = put(commit, "git\n-c\nuser.name=t\n-c\nuser.email=t@t\ncommit\n-q\n-m\n")
  val () = put(commit, date)
  var entry : $B.builder_v = $B.create()
  val () = put(entry, "GIT_COMMITTER_DATE=")
  val () = put(entry, date)
  val extra = $L.list_vt_cons(arg_of(entry), $L.list_vt_nil()): $L.listv($P.arg_entry)
  val out_cfg = open_stream(builder_of(git), $F.CreateOrTruncate())
  val err_cfg = open_stream(builder_of(git), $F.AppendExisting())
  val () = (if run_in("published", commit, out_cfg, err_cfg, extra) = 0 then () else die_file("git commit", "", git))
in bats_ok(t, "published", "upload\n--repository\n../repo", "publish_upload.log") end

fn dependent {sd,sv:nat} (dir: string sd, constraint: string sv): void = let
  val () = setup(builder_of("rm\n-rf\ndependent/src"), "rm dependent src")
  val () = setup(builder_of("mkdir\n-p\ndependent/src/bin"), "mkdir dependent")
  var toml : $B.builder_v = $B.create()
  val () = put(toml, "[package]\nname = \"tf\"\nkind = \"bin\"\n\n[dependencies]\n\"tfdep\" = ")
  val () = put(toml, constraint)
  val () = put(toml, "\n")
  val () = put_file(dir, "/bats.toml", toml)
in put_file(dir, "/src/bin/tf.bats", builder_of("#use tfdep as D\n\nimplement main0 () = println! ($D.f ())\n")) end

(* dependencies: a constraint reaches build/ through the version it picks, a path dependency through its directory *)
fn case_dependencies (t: !tool): void = let
  val () = setup(builder_of("rm\n-rf\nrepo\ndependent"), "rm repo")
  val () = setup(builder_of("mkdir\n-p\nrepo\ndependent"), "mkdir repo")
  val () = publish(t, "2026-01-03T00:00:03Z", "1")
  val () = publish(t, "2026-01-04T00:00:04Z", "2")
  val () = dependent("dependent", "\"\"")
  val () = bats_ok(t, "dependent", "lock\n--repository\n../repo", "dependent_lock.log")
  val () = build_ok(t, "dependent", "dependent_first.log", "\n--repository\n../repo")
  val () = prints("dependent", "2\n", "constraint none: the newest")
  val () = put_file("dependent", "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\n\n[dependencies]\n\"tfdep\" = \"!= 2026.1.4.4\"\n"))
  val status = build_plain(t, "dependent", "\n--repository\n../repo", "dependent_ruled_out.out", "dependent_ruled_out.err")
  val () = (if status = 1 then () else die_file("a constraint that rules out the locked version built", "", "dependent_ruled_out.err"))
  val () = has("dependent_ruled_out.err", "which does not meet", "a constraint that rules out the locked version")
  val () = bats_ok(t, "dependent", "lock\n--repository\n../repo", "dependent_relock.log")
  val () = build_ok(t, "dependent", "dependent_not_newest.log", "\n--repository\n../repo")
  val () = prints("dependent", "1\n", "constraint != the newest")
  val () = put_file("dependent", "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\n\n[dependencies]\n\"tfdep\" = \"\"\n"))
  val () = bats_ok(t, "dependent", "lock\n--repository\n../repo", "dependent_relock_again.log")
  val () = build_ok(t, "dependent", "dependent_dropped.log", "\n--repository\n../repo")
in prints("dependent", "2\n", "constraint dropped") end

fn case_path_dependency (t: !tool): void = let
  val () = setup(builder_of("rm\n-rf\npath_dependency"), "rm path_dependency")
  val () = setup(builder_of("mkdir\n-p\npath_dependency/one/src\npath_dependency/two/src\npath_dependency/app/src/bin"), "mkdir path_dependency")
  val () = put_file("path_dependency/one", "/bats.toml", builder_of("[package]\nname = \"tfdep\"\nkind = \"lib\"\n"))
  val () = put_file("path_dependency/two", "/bats.toml", builder_of("[package]\nname = \"tfdep\"\nkind = \"lib\"\n"))
  val () = put_file("path_dependency/one", "/src/lib.bats", builder_of("#pub fun f (): int\n\nimplement f () = 7\n"))
  val () = put_file("path_dependency/two", "/src/lib.bats", builder_of("#pub fun f (): int\n\nimplement f () = 8\n"))
  val () = put_file("path_dependency/app", "/src/bin/tf.bats", builder_of("#use tfdep as D\n\nimplement main0 () = println! ($D.f ())\n"))
  val () = put_file("path_dependency/app", "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\n\n[dependencies]\n\"tfdep\" = { path = \"../one\" }\n"))
  val () = build_ok(t, "path_dependency/app", "path_dependency_first.log", "")
  val () = prints("path_dependency/app", "7\n", "path dependency one")
  val () = put_file("path_dependency/app", "/bats.toml", builder_of("[package]\nname = \"tf\"\nkind = \"bin\"\n\n[dependencies]\n\"tfdep\" = { path = \"../two\" }\n"))
  val () = build_ok(t, "path_dependency/app", "path_dependency2.log", "")
in prints("path_dependency/app", "8\n", "path dependency two") end

(* The manifest of 65536 or 65537 bytes: comment lines, then YES_UNSAFE, then a blank line when the bytes call for it *)
fn limit_manifest {sn,sb:nat} (lines: int sn, blank: string sb): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_times(b, "#\n", lines)
  val () = put(b, YES_UNSAFE)
  val () = put(b, blank)
in b end

(* toml-limit: a manifest of exactly 65536 bytes is read to its end, one byte more is refused, never parsed cut *)
fn case_limit (t: !tool): void = let
  val () = unsafe_module("limit_project", builder_of(YES_UNSAFE))
  val () = put_file("limit_project", "/bats.toml", limit_manifest(32743, "\n"))
  val () = (if size_of(builder_of("limit_project/bats.toml")) = 65536 then () else die("the manifest at the limit is not 65536 bytes", ""))
  val () = build_ok(t, "limit_project", "limit.log", "")
  val () = prints("limit_project", "1\n", "manifest of 65536 bytes")
  val () = put_file("limit_project", "/bats.toml", limit_manifest(32744, ""))
  val () = (if size_of(builder_of("limit_project/bats.toml")) = 65537 then () else die("the manifest over the limit is not 65537 bytes", ""))
  val () = setup(builder_of("rm\n-rf\nlimit_project/build\nlimit_project/dist"), "rm limit build")
  val status = build_plain(t, "limit_project", "", "limit_over.out", "limit_over.err")
  val () = (if status = 1 then () else die_file("a manifest of 65537 bytes built", "", "limit_over.err"))
  val () = has("limit_over.err", "bats.toml", "a manifest of 65537 bytes")
in (if path_exists(builder_of("limit_project/dist/debug/tf")) then die("a manifest of 65537 bytes left a program", "") else ()) end

(* add and remove: the manifest is kept whole *)
fn add_before (): $B.builder_v = padded("[package]\nname = \"tf\"\nkind = \"bin\"\n\n[dependencies]\n\"existing\" = \"\"\n")

fn tail_of {sn:nat} (head: $B.builder_v, tail: string sn): $B.builder_v = let
  var b : $B.builder_v = head
  val () = put(b, tail)
in b end

fn case_add (t: !tool): void = let
  val () = module("add_project", builder_of(BASE))
  val () = put_file("add_project", "/bats.toml", add_before())
  val () = (if size_of(builder_of("add_project/bats.toml")) > 8192 then () else die("the manifest of bats add is not large", ""))
  val () = bats_ok(t, "add_project", "add\nadded", "add.log")
  val () = has("add.log", "^added 'added' to \\[dependencies\\]$", "bats add said")
  val () = put_file("", "expected_add.toml", tail_of(add_before(), "\"added\" = \"\"\n"))
  var c : $B.builder_v = builder_of("cmp\n-s\nexpected_add.toml\nadd_project/bats.toml")
in if run_log("", c, "cmp.log") = 0 then () else die("bats add changed more than the one line", "") end

(* The package removed in dir; its message is in log *)
fn remove_run {sd,sl,sp:nat} (t: !tool, dir: string sd, log: string sl, package: string sp): void = let
  var c : $B.builder_v = bats_cmd(t, "remove\n")
  val () = put(c, package)
  val _ = run_log(dir, c, log)
in end

(* The manifest of dir is exactly expected *)
fn manifest_is {sd,sl:nat} (dir: string sd, expected: $B.builder_v, label: string sl): void = let
  val () = put_file("", "expected_remove.toml", expected)
  val same = run_log("", dir_command("cmp\n-s\nexpected_remove.toml\n", dir, "/bats.toml"), "cmp.log")
in if same = 0 then () else die(label, "") end

fn case_remove (t: !tool): void = let
  val () = module("remove_project", builder_of(BASE))
  val () = put_file("remove_project", "/bats.toml", tail_of(add_before(), "\"added\" = \"\"\n\"added-too\" = \"\"\n"))
  val () = remove_run(t, "remove_project", "remove.log", "added")
  val () = has("remove.log", "^removed 'added' from \\[dependencies\\]$", "bats remove said")
  val () = manifest_is("remove_project", tail_of(add_before(), "\"added-too\" = \"\"\n"), "bats remove changed more than the one line")
  val () = remove_run(t, "remove_project", "remove_absent.log", "absent")
  val () = has("remove_absent.log", "^error: package 'absent' not found in \\[dependencies\\]$", "bats remove of an absent package said")
in manifest_is("remove_project", tail_of(add_before(), "\"added-too\" = \"\"\n"), "bats remove of an absent package changed the manifest") end

(* remove-cases: no final newline, a second table, an empty file, over 65536 bytes *)
fn case_remove_shapes (t: !tool): void = let
  val () = module("remove_no_newline", builder_of(BASE))
  val () = put_file("remove_no_newline", "/bats.toml", builder_of("[dependencies]\n\"other\" = \"\"\n\"added\" = \"\""))
  val () = remove_run(t, "remove_no_newline", "remove_no_newline.log", "added")
  val () = manifest_is("remove_no_newline", builder_of("[dependencies]\n\"other\" = \"\"\n"), "bats remove (no final newline)")
  val () = module("remove_second_table", builder_of(BASE))
  val () = put_file("remove_second_table", "/bats.toml", builder_of("[dependencies]\n\"other\" = \"\"\n\n[dev-dependencies]\n\"added\" = \"\"\n\"last\" = \"\"\n"))
  val () = remove_run(t, "remove_second_table", "remove_second_table.log", "added")
  val () = manifest_is("remove_second_table", builder_of("[dependencies]\n\"other\" = \"\"\n\n[dev-dependencies]\n\"last\" = \"\"\n"), "bats remove (second table)")
  val () = module("remove_empty", builder_of(BASE))
  val () = put_file("remove_empty", "/bats.toml", builder_of(""))
  val () = remove_run(t, "remove_empty", "remove_empty.log", "added")
  val () = manifest_is("remove_empty", builder_of(""), "bats remove (empty file)")
  val () = has("remove_empty.log", "^error: package 'added' not found in \\[dependencies\\]$", "bats remove on an empty file said")
  val () = module("remove_over_limit", builder_of(BASE))
  var before : $B.builder_v = $B.create()
  val () = put_times(before, "#\n", 35000)
  val () = put(before, "\"other\" = \"\"\n\"added\" = \"\"\n")
  val () = put_file("remove_over_limit", "/bats.toml", before)
  val () = remove_run(t, "remove_over_limit", "remove_over_limit.log", "added")
  var after : $B.builder_v = $B.create()
  val () = put_times(after, "#\n", 35000)
  val () = put(after, "\"other\" = \"\"\n")
  val () = manifest_is("remove_over_limit", after, "bats remove (over 65536 bytes)")
in has("remove_over_limit.log", "^removed 'added' from \\[dependencies\\]$", "bats remove over 65536 bytes said") end

(* remove-lookalikes: a commented "added", a string value holding "added", an indented "added" stay, only the real line goes (bats#445) *)
fn case_remove_lookalikes (t: !tool): void = let
  val after = "[dependencies]\n# \"added\" = \"\"\n\"note\" = \"added\"\n  \"added\" = \"\"\n\"last\" = \"\"\n"
  val () = module("remove_lookalikes", builder_of(BASE))
  val () = put_file("remove_lookalikes", "/bats.toml", builder_of("[dependencies]\n# \"added\" = \"\"\n\"note\" = \"added\"\n  \"added\" = \"\"\n\"added\" = \"\"\n\"last\" = \"\"\n"))
  val () = remove_run(t, "remove_lookalikes", "remove_lookalikes.log", "added")
  val () = manifest_is("remove_lookalikes", builder_of(after), "bats remove among look-alikes")
  val () = has("remove_lookalikes.log", "^removed 'added' from \\[dependencies\\]$", "bats remove among look-alikes said")
  val () = remove_run(t, "remove_lookalikes", "remove_lookalikes_again.log", "added")
  val () = has("remove_lookalikes_again.log", "^error: package 'added' not found in \\[dependencies\\]$", "bats remove of a name left only in look-alikes said")
in manifest_is("remove_lookalikes", builder_of(after), "bats remove of a name left only in look-alikes changed the manifest") end

(* ============================================================
   The program: the bats under test is the first argument, an absolute path
   ============================================================ *)

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

fn run_all (t: !tool): void = let
  val () = case_unchanged(t)
  val () = case_kind(t)
  val () = case_unsafe(t)
  val () = case_large_manifest(t)
  val () = case_large_library(t)
  val () = case_dependencies(t)
  val () = case_path_dependency(t)
  val () = case_limit(t)
  val () = case_add(t)
  val () = case_remove(t)
  val () = case_remove_shapes(t)
in case_remove_lookalikes(t) end

implement main0 () = let
  val given = tool_of_args()
in
  case+ given of
  | ~given_none() => let
      val () = println! ("usage: toml_fields <absolute path of the bats under test>")
    in exit_void(2) end
  | ~given_some(t) => let
      val _ = run_show(builder_of("rm\n-rf\nwork"))
      val _ = run_show(builder_of("mkdir\nwork"))
      val inside = chdir_to(builder_of("work"))
      val () = (if inside then () else exit_void(1))
      val () = run_all(t)
      val _ = chdir_to(builder_of(".."))
      val _ = run_show(builder_of("rm\n-rf\nwork"))
      val () = println! ("toml-fields: ok")
      val+ ~tool_mk(a, _) = t
    in $A.free<byte>(a) end
end
