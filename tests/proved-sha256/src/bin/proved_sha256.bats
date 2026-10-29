(* proved-sha256 -- bats hashes with sha256's proved API and every digest is the one the fast API gave (bats#502); keyword: proved-sha256.
   Four paths on fixed inputs, each reported on its own (a failing path does not stop the others):
   the file hash (sources of 0, 3, 200 and 70000 bytes against the digests of the base commit's run),
   the stamp (its patsopt, libs and link lines against the sha256 of the files they digest), the shared
   cache's key (the entry's name against the sha256 of the key's text, made again here) and the
   fixtures memo (a .res names the sha256 of its .key and ends with the sha256 of the bytes before it).
   Written in bats (bats#502 review): the programs it runs are sha256sum (shasum -a 256 where it is
   absent), awk, cmp, cat, cp, find, tail and grep, third-party tools used as they are. *)
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
  val () = println! ("kept: tests/proved-sha256/work (proved-sha256)")
in exit_void(1) end

fn die {sa,sb:nat} (what: string sa, detail: string sb): void = let
  val () = println! ("FAIL: ", what, detail)
  val () = println! ("kept: tests/proved-sha256/work (proved-sha256)")
in exit_void(1) end

(* A step of setup that must succeed: rm, mkdir *)
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

(* ---- the checks: each gives 0 when it holds and 1 when it failed, after saying so ---- *)

fn fail {sl,sd:nat} (label: string sl, detail: string sd): int = let
  val () = println! ("FAIL: ", label, ": ", detail)
in 1 end

(* got and want hold the same bytes *)
fn same_file {sa,sb,sl:nat} (got: string sa, want: string sb, label: string sl): int = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "cmp\n-s\n")
  val () = put(c, got)
  val () = put(c, "\n")
  val () = put(c, want)
in
  if run_log("", c, "cmp.log") = 0 then 0
  else let
    val () = println! ("FAIL: ", label, ": ", got, " is not ", want)
    val () = println! ("  got:")
    val () = show_file(got)
    val () = println! ("  want:")
    val () = show_file(want)
  in 1 end
end

(* The file copied to dest (a path built at run time, consumed) *)
fn copy_to {sd:nat} (path: $B.builder_v, dest: string sd): int = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "cp\n")
  val () = put_builder(c, path)
  val () = put(c, "\n")
  val () = put(c, dest)
in run_split("", c, "cp.out", "cp.err") end

(* The sha256 of file as 64 hex digits and a line feed, in out: sha256sum, else shasum -a 256 *)
fn sum_of {sf,so,sl:nat} (file: string sf, out: string so, label: string sl): int = let
  val s1 = run_split("", dir_command("sha256sum\n", file, ""), "sum.raw", "sum.err")
  val s2 = (if s1 = 0 then 0
    else run_split("", dir_command("shasum\n-a\n256\n", file, ""), "sum.raw", "sum.err")): int
  val s3 = (if s2 = 0 then run_split("", builder_of("awk\n{print $1}\nsum.raw"), out, "awk.err") else 1): int
in if s3 = 0 then 0 else fail(label, "no sha256 tool could digest the file") end

(* The awk program run on file, its output in out *)
fn awk_to {sp,sf,so,sl:nat} (program: string sp, file: string sf, out: string so, label: string sl): int = let
  var c : $B.builder_v = $B.create()
  val () = put(c, "awk\n")
  val () = put(c, program)
  val () = put(c, "\n")
  val () = put(c, file)
in if run_split("", c, out, "awk.err") = 0 then 0 else fail(label, "awk failed") end

(* The digest in file is the one in out, which a tool made *)
fn digest_is {sf,sw,sl:nat} (file: string sf, stated: string sw, label: string sl): int = let
  val a = sum_of(file, "oracle.txt", label)
in if a = 0 then same_file(stated, "oracle.txt", label) else a end

(* ---- the file hash: put_file_sha256_m writes the digest of build/src/lib.dats into lib.dats.src ---- *)

(* A source in a library of its own: bats check writes its digest (the check itself may fail on a source that is no Bats) *)
fn hash_case {sn,sl,sw:nat} (t: !tool, name: string sn, log: string sl, source: $B.builder_v, want: string sw): int = let
  val () = setup(dir_command("rm\n-rf\n", name, ""), "rm hash")
  val () = setup(dir_command("mkdir\n-p\n", name, "/src"), "mkdir hash")
  val () = put_file(name, "/bats.toml", builder_of("[package]\nname = \"hashed\"\nkind = \"lib\"\n"))
  val () = put_file(name, "/src/lib.bats", source)
  val _ = run_log(name, bats_cmd(t, "check"), log)
  val c1 = copy_to(join(name, "/build/src/lib.dats.src"), "got.txt")
  val () = (if c1 = 0 then () else println! ("FAIL: ", name, ": no build/src/lib.dats.src"))
  val _ = write_text(builder_of("want.txt"), builder_of(want))
  val a = (if c1 = 0 then same_file("got.txt", "want.txt", name) else 1): int
  (* the digest this bats made, for the pull request's evidence of the base commit's run *)
  val () = print! (name, " ")
  val () = (if c1 = 0 then show_file("got.txt") else ())
  val () = println! ()
  (* the tool agrees with the base commit's digest, so the constant is the sha256 of the bytes *)
  val c2 = copy_to(join(name, "/src/lib.bats"), "src_copy.txt")
  val _ = write_text(builder_of("want_nl.txt"), let
    var w : $B.builder_v = $B.create()
    val () = put(w, want)
    val () = put(w, "\n")
  in w end)
  val b = sum_of("src_copy.txt", "oracle.txt", name)
  val c = (if c2 = 0 && b = 0 then same_file("oracle.txt", "want_nl.txt", name) else 1): int
in a + c end

fn case_file_hash (t: !tool): int = let
  val e = hash_case(t, "hash_empty", "hash_empty.log", builder_of(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  val abc = hash_case(t, "hash_abc", "hash_abc.log", builder_of("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  var blocks : $B.builder_v = $B.create()
  val () = put_times(blocks, "aaaaaaaaaaaaaaaaaaaa", 10)
  val b = hash_case(t, "hash_blocks", "hash_blocks.log", blocks,
    "c2a908d98f5df987ade41b5fce213067efbcc21ef2240212a41e54b5e7c28ae5")
  var chunks : $B.builder_v = $B.create()
  val () = put_times(chunks, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 350)
  val c = hash_case(t, "hash_chunks", "hash_chunks.log", chunks,
    "66915c0872933db504e7578828dd85b7e74a4e0a061f9756793b89c4151bd4b5")
in e + abc + b + c end

(* ---- the stamp: its patsopt, libs and link lines digest files of build/ ---- *)

fn stamp_line {sp,sf,sl:nat} (program: string sp, file: string sf, label: string sl): int = let
  val c1 = copy_to(builder_of("hash_abc/build/.bats_stamp"), "stamp_copy.txt")
  val c2 = copy_to(join("hash_abc/build/", file), "digested.txt")
in
  if c1 <> 0 || c2 <> 0 then fail(label, "build/ has no stamp or no such file")
  else let
    val a = awk_to(program, "stamp_copy.txt", "stamp_got.txt", label)
    val b = sum_of("digested.txt", "stamp_want.txt", label)
  in if a = 0 && b = 0 then same_file("stamp_got.txt", "stamp_want.txt", label) else 1 end
end

fn case_stamp (): int = let
  val a = stamp_line("$1==\"patsopt\"{print $2}", ".bats_toolchain", "stamp patsopt line")
  val b = stamp_line("$1==\"libs\"{print $2}", ".bats_libs", "stamp libs line")
  val c = stamp_line("$1==\"link\"{print $2}", ".bats_link", "stamp link line")
  (* many blocks: the listing the patsopt line digests is far past one *)
  val big = (if size_of(builder_of("hash_abc/build/.bats_toolchain")) > 4096 then 0
    else fail("stamp patsopt line", "the toolchain listing is too short to be many blocks")): int
in a + b + c + big end

(* ---- the shared cache's key: the entry is named by the sha256 of the key's text (cache.bats module_key) ---- *)

fn case_cache_key (t: !tool): int = let
  val () = setup(builder_of("rm\n-rf\nkey_project\nkey_cache"), "rm key")
  val () = setup(builder_of("mkdir\n-p\nkey_project/src"), "mkdir key")
  val () = put_file("key_project", "/bats.toml", builder_of("[package]\nname = \"keyed\"\nkind = \"lib\"\n"))
  val () = put_file("key_project", "/src/lib.bats", builder_of("#include \"share/atspre_staload.hats\"\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n"))
  var c : $B.builder_v = $B.create()
  val () = put(c, "env\nBATS_CACHE_DIR=../key_cache\n")
  val () = put_bats(c, t)
  val () = put(c, "check")
  val status = run_log("key_project", c, "key_project.log")
in
  if status <> 0 then fail("cache key", "bats check failed in key_project (key_project.log)")
  else let
    val s1 = copy_to(builder_of("key_project/build/.bats_stamp"), "stamp_copy.txt")
    val s2 = copy_to(builder_of("key_project/build/.bats_toolchain"), "tool_copy.txt")
    val s3 = copy_to(builder_of("key_project/build/src/lib.dats"), "d1_copy.txt")
    val s4 = copy_to(builder_of("key_project/build/src/lib.sats"), "d2_copy.txt")
    val s5 = copy_to(builder_of("key_project/build/.bats_depgen"), "depgen_copy.txt")
  in
    if s1 <> 0 || s2 <> 0 || s3 <> 0 || s4 <> 0 || s5 <> 0 then fail("cache key", "a file of key_project/build is missing")
    else let
      (* the key's text: bats's digest, the toolchain's, patsopt's command, then each file patsopt read *)
      val p1 = awk_to("$1==\"bats\"{print $0}", "stamp_copy.txt", "key_p1.txt", "cache key")
      val q2 = sum_of("tool_copy.txt", "tc.txt", "cache key")
      val p2 = awk_to("{print \"toolchain \" $1}", "tc.txt", "key_p2.txt", "cache key")
      val _ = write_text(builder_of("key_p3.txt"), builder_of("patsopt -IATS build -IATS build/src -IATS build/bats_modules -o build/src/lib_dats.c -d build/src/lib.dats\n"))
      val q4 = sum_of("d1_copy.txt", "d1.txt", "cache key")
      val p4 = awk_to("{print \"build/src/lib.dats \" $1}", "d1.txt", "key_p4.txt", "cache key")
      val q5 = sum_of("d2_copy.txt", "d2.txt", "cache key")
      val p5 = awk_to("{print \"build/src/lib.sats \" $1}", "d2.txt", "key_p5.txt", "cache key")
      val _ = write_text(builder_of("deps_want.txt"), builder_of("build/src/lib.dats\nbuild/src/lib.sats\n"))
      val deps = same_file("depgen_copy.txt", "deps_want.txt", "cache key: the files patsopt read")
      val cat = run_split("", builder_of("cat\nkey_p1.txt\nkey_p2.txt\nkey_p3.txt\nkey_p4.txt\nkey_p5.txt"), "key.txt", "cat.err")
      val q6 = sum_of("key.txt", "key_want.txt", "cache key")
      val found = run_split("", builder_of("find\nkey_cache\n-type\nf\n-name\n*.c\n-exec\nbasename\n{}\n.c\n;"), "key_got.txt", "find.err")
      val prep = p1 + q2 + p2 + q4 + p4 + q5 + p5 + deps + cat + q6 + found
    in
      if prep <> 0 then fail("cache key", "the key's text could not be made again")
      else same_file("key_got.txt", "key_want.txt", "cache key: the entry's name is not the sha256 of the key's text")
    end
  end
end

(* ---- the fixtures memo: a .res names the sha256 of its .key (line 4) and ends with the sha256 of the bytes before it ---- *)

(* The first 65536 bytes of the file, or nothing when it cannot be read *)
fn read_small (path: $B.builder_v): $B.builder_v = let
  val @(pa, pn) = exact_path(path)
  val @(pfz, pbv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(pbv, pn, $F.ReadOnly(), $F.OpenExisting(), 0)
  val () = $A.drop<byte>(pfz, pbv)
  val () = $A.free<byte>($A.thaw<byte>(pfz))
in
  case+ opened of
  | ~$R.err(_) => $B.create()
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(65536)
      val k = (case+ $F.file_read(fd, buf, 65536) of
        | ~$R.ok(n) => n
        | ~$R.err(_) => 0): [k:nat | k <= 65536] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      val @(fz, bv) = $A.freeze<byte>(buf)
      val text = slice_of(bv, 0, k)
      val () = $A.drop<byte>(fz, bv)
      val () = $A.free<byte>($A.thaw<byte>(fz))
    in text end
end

(* One .res (the path in arr, len bytes) and the .key beside it *)
fn memo_entry {l:agz}{cap:pos}{n:nat | n <= cap} (arr: $A.arr(byte, l, cap), len: int n): int = let
  val @(fz, bv) = $A.freeze<byte>(arr)
  val res = slice_of(bv, 0, len)
  var key : $B.builder_v = $B.create()
  val () = (if len >= 4 then put_builder(key, slice_of(bv, 0, len - 4)) else ())
  val () = put(key, ".key")
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  val c1 = copy_to(res, "m_res.txt")
  val c2 = copy_to(key, "m_key.txt")
in
  if c1 <> 0 || c2 <> 0 then fail("fixtures memo", "a .res has no .key beside it")
  else let
    val a1 = awk_to("NR==4", "m_res.txt", "m_line4.txt", "fixtures memo")
    val a2 = sum_of("m_key.txt", "m_key_sum.txt", "fixtures memo")
    val named = (if a1 = 0 && a2 = 0 then same_file("m_line4.txt", "m_key_sum.txt", "fixtures memo: the .res names another digest than its .key's") else 1): int
    val b1 = awk_to("{a[NR]=$0} END{for(i=1;i<NR;i++)print a[i]}", "m_res.txt", "m_body.txt", "fixtures memo")
    val b2 = sum_of("m_body.txt", "m_body_sum.txt", "fixtures memo")
    val b3 = run_split("", builder_of("tail\n-n\n1\nm_res.txt"), "m_last.txt", "tail.err")
    val closed = (if b1 = 0 && b2 = 0 && b3 = 0 then same_file("m_last.txt", "m_body_sum.txt", "fixtures memo: the .res ends with a sum that is not the sha256 of the rest") else 1): int
  in named + closed end
end

fun memo_each {n:nat} .<n>. (xs: $L.list_vt($P.arg_entry, n), sum: int): int =
  case+ xs of
  | ~$L.list_vt_nil() => sum
  | ~$L.list_vt_cons(@(arr, len), tl) => let
      val r = memo_entry(arr, len)
    in memo_each(tl, sum + r) end

fn case_memo (t: !tool): int = let
  val () = setup(builder_of("rm\n-rf\nmemo_proj\nmemo_fx\nmemo_work\nmemo"), "rm memo")
  val () = setup(builder_of("mkdir\n-p\nmemo_proj/src\nmemo_fx/accept/ok\nmemo_fx/reject/bad"), "mkdir memo")
  val () = put_file("memo_proj", "/bats.toml", builder_of("[package]\nname = \"fx\"\nkind = \"lib\"\n"))
  val () = put_file("memo_proj", "/src/lib.bats", builder_of("#include \"share/atspre_staload.hats\"\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n"))
  val () = put_file("memo_fx", "/accept/ok/file", builder_of("src/lib.bats\n"))
  val () = put_file("memo_fx", "/accept/ok/before", builder_of("(* end *)\n"))
  val () = put_file("memo_fx", "/accept/ok/snippet.bats", builder_of("(* fixture-snippet *)\nfn g (x: int): int = x\n"))
  val () = put_file("memo_fx", "/reject/bad/file", builder_of("src/lib.bats\n"))
  val () = put_file("memo_fx", "/reject/bad/before", builder_of("(* end *)\n"))
  val () = put_file("memo_fx", "/reject/bad/snippet.bats", builder_of("(* fixture-snippet *)\nfn h (x: int): int = case+ x of 0 => 1\n"))
  val () = put_file("memo_fx", "/reject/bad/expect", builder_of("function h\nline 2\npattern match is nonexhaustive:\n[^0]\n"))
  val ran = run_log("memo_proj", bats_cmd(t, "fixtures\n../memo_fx\n--work\n../memo_work\n--memo\n../memo"), "memo.log")
  val two = run_log("", builder_of("grep\n-aq\n--\n^fixtures: 2 ok, 0 failed\nmemo.log"), "grep.log")
in
  if ran <> 0 || two <> 0 then let
    val () = show_file("memo.log")
  in fail("fixtures memo", "bats fixtures did not report 2 ok, 0 failed") end
  else let
    val listed = run_split("", builder_of("find\nmemo\n-type\nf\n-name\n*.res"), "res.list", "find.err")
    val text = read_small(builder_of("res.list"))
    val @(arr, total) = $B.into_arr(text)
    val @(fz, bv) = $A.freeze<byte>(arr)
    val entries = reverse_args(split_lines(bv, 0, total, $L.list_vt_nil()), $L.list_vt_nil())
    val () = $A.drop<byte>(fz, bv)
    val () = $A.free<byte>($A.thaw<byte>(fz))
    val each = memo_each(entries, 0)
    val k = run_split("", builder_of("find\nmemo\n-type\nf\n-name\n*.res\n-exec\nawk\nFNR==3\n{}\n+"), "kinds.txt", "find.err")
    val pass = run_log("", builder_of("grep\n-qx\npass\nkinds.txt"), "grep.log")
    val log = run_log("", builder_of("grep\n-qx\nlog\nkinds.txt"), "grep.log")
    val both = (if listed = 0 && k = 0 && pass = 0 && log = 0 then 0
      else fail("fixtures memo", "expected a pass entry and a log entry")): int
  in each + both end
end
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

fn run_all (t: !tool): int = let
  val a = case_file_hash(t)
  val b = case_stamp()
  val c = case_cache_key(t)
  val d = case_memo(t)
in a + b + c + d end

implement main0 () = let
  val given = tool_of_args()
in
  case+ given of
  | ~given_none() => let
      val () = println! ("usage: proved_sha256 <absolute path of the bats under test>")
    in exit_void(2) end
  | ~given_some(t) => let
      val _ = run_show(builder_of("rm\n-rf\nwork"))
      val _ = run_show(builder_of("mkdir\nwork"))
      val inside = chdir_to(builder_of("work"))
      val () = (if inside then () else exit_void(1))
      val failed = run_all(t)
      val _ = chdir_to(builder_of(".."))
      val () = (if failed = 0 then let
          val _ = run_show(builder_of("rm\n-rf\nwork"))
        in println! ("proved-sha256: ok") end
        else let
          val () = println! ("kept: tests/proved-sha256/work (proved-sha256)")
        in exit_void(1) end)
      val+ ~tool_mk(a, _) = t
    in $A.free<byte>(a) end
end
