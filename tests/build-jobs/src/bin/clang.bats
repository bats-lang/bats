(* build-jobs -- the stand-in clang of tests/build-jobs (keyword: build-jobs).
   A compile (-c, not -E) appends "S <C file>" to the file CC_LOG; one of a module (a C file
   named *_dats.c) then waits until the log has had CC_WAIT_FOR compiles running at once (3 s
   at most), so the compiles that overlap are the ones the caller starts together, and holds
   0.3 s (1.8 s for the C file whose name ends with CC_SLOW); it then, when the name ends with CC_NOISY, writes 200000 bytes to stderr and succeeds, or either fails (a C file whose name ends with
   CC_FAIL_A or CC_FAIL_B: a message on stderr, and, 0.5 s later, 200000 more bytes when the name ends with CC_BIG,
   "F <C file>" in the log, status 1, no object)
   or runs the real clang with the very arguments and appends "E <C file>"; every other call
   (the preprocess, the link, -print-resource-dir) runs the real clang at once. The real clang
   is the first "clang" in PATH outside STANDIN_DIR. *)
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

fn builder_of {sn:nat} (s: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put(b, s)
in b end

(* The builder's text and a NUL after it, in an array of that size *)
fn exact_path (b: $B.builder_v): [l:agz][n:pos | n <= 524289] @($A.arr(byte, l, n), int n) = let
  val @(small, len) = $B.into_arr(b)
  val grown = $A.alloc<byte>(len + 1)
  val @(fz, bv) = $A.freeze<byte>(small)
  val @(text, rest) = $A.borrow_split<byte>(fz, bv, len)
  val () = $A.write_borrow(grown, 0, text, len)
  val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, text, rest))
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(grown, len + 1) end

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

fn path_exists (path: $B.builder_v): bool = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_exists(bv, pn)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* The value of the environment variable name, in buf[0, k); 0 when it is not set *)
fn env_into {l:agz}{sn:nat} (name: string sn, buf: !$A.arr(byte, l, 4096)): [k:nat | k <= 4096] int k = let
  val @(na, nn) = exact_path(builder_of(name))
  val got = $E.get_cstr(na, nn, buf, 4096)
  val () = $A.free<byte>(na)
in
  case+ got of
  | ~$R.some(k) => k
  | ~$R.none() => 0
end

(* The bytes of buf[s, e) appended to out *)
fn put_range {l:agz}{n:pos}{s,e:nat | s <= e; e <= n} (out: !$B.builder_v >> $B.builder_v, buf: !$A.arr(byte, l, n), s: int s, e: int e): void = let
  fun loop {l:agz}{n:pos}{e:nat | e <= n}{j:nat | j <= e} .<e - j>.
    (out: !$B.builder_v >> $B.builder_v, src: !$A.arr(byte, l, n), j: int j, e: int e): void =
    if j >= e then ()
    else let
      val () = put_byte_v(out, byte2int0($A.get<byte>(src, j)))
    in loop(out, src, j + 1, e) end
in loop(out, buf, s, e) end

fn arg_of (b: $B.builder_v): $P.arg_entry = let
  val @(arr, len) = $B.into_arr(b)
in @(arr, len) end

(* Where the byte c is in buf[p, k), else k *)
fun find_byte {l:agz}{n:pos}{k:nat | k <= n}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, n), k: int k, p: int p, c: int): [r:nat | p <= r; r <= k] int r =
  if p >= k then p
  else if byte2int0($A.get<byte>(buf, p)) = c then p
  else find_byte(buf, k, p + 1, c)

(* Whether a[sa, sa + m) and b[sb, sb + m) hold the same bytes, from j *)
fun same_bytes {l:agz}{n:pos}{lb:agz}{nb:pos}{m:nat}{sa:nat | sa + m <= n}{sb:nat | sb + m <= nb}{j:nat | j <= m} .<m - j>.
  (a: !$A.arr(byte, l, n), sa: int sa, b: !$A.arr(byte, lb, nb), sb: int sb, m: int m, j: int j): bool =
  if j >= m then true
  else if byte2int0($A.get<byte>(a, sa + j)) = byte2int0($A.get<byte>(b, sb + j)) then same_bytes(a, sa, b, sb, m, j + 1)
  else false

(* Whether the word buf[s, e) ends with the m bytes of tail (m > 0) *)
fn ends_with {l:agz}{n:pos}{lb:agz}{nb:pos}{m:pos | m <= nb}{s,e:nat | s <= e; e <= n}
  (buf: !$A.arr(byte, l, n), s: int s, e: int e, tail: !$A.arr(byte, lb, nb), m: int m): bool =
  if e - s < m then false
  else same_bytes(buf, e - m, tail, 0, m, 0)

(* Whether the word buf[s, e) is the text w *)
fn word_is {l:agz}{n:pos}{sw:nat}{s,e:nat | s <= e; e <= n} (buf: !$A.arr(byte, l, n), s: int s, e: int e, w: string sw): bool = let
  fun cmp {l:agz}{n:pos}{sw:nat}{s,e:nat | s <= e; e <= n}{j:nat | j <= sw} .<sw - j>.
    (buf: !$A.arr(byte, l, n), s: int s, e: int e, w: string sw, swn: int sw, j: int j): bool =
    if j >= swn then true
    else if s + j >= e then false
    else if byte2int0($A.get<byte>(buf, s + j)) = char2int0(string_get_at(w, j)) then cmp(buf, s, e, w, swn, j + 1)
    else false
  val swn = g1u2i(string1_length(w))
in (if e - s = swn then cmp(buf, s, e, w, swn, 0) else false) end

(* Whether some word of buf[p, k) is the text w *)
fun any_word {l:agz}{n:pos}{sw:nat}{k:nat | k <= n}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, n), k: int k, p: int p, w: string sw): bool =
  if p >= k then false
  else let
    val e = find_byte(buf, k, p, 0)
  in
    if word_is(buf, p, e, w) then true else if e >= k then false else any_word(buf, k, e + 1, w)
  end

(* The start of the first word of buf[p, k) that ends with ".c", else k *)
fun first_c {l:agz}{n:pos}{k:nat | k <= n}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, n), k: int k, p: int p): [r:nat | r <= k] int r =
  if p >= k then k
  else let
    val e = find_byte(buf, k, p, 0)
    val ends_c = (if e - p >= 3 then (if byte2int0($A.get<byte>(buf, e - 1)) = 99 then byte2int0($A.get<byte>(buf, e - 2)) = 46 else false) else false): bool
  in
    if ends_c then p
    else if e >= k then k
    else first_c(buf, k, e + 1)
  end

(* The argument entries of the words of buf[p, k) *)
fun args_of {l:agz}{n:pos}{k:nat | k <= n}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, n), k: int k, p: int p): $L.listv($P.arg_entry) =
  if p >= k then $L.list_vt_nil()
  else let
    val e = find_byte(buf, k, p, 0)
    var b : $B.builder_v = $B.create()
    val () = put_range(b, buf, p, e)
    val rest = (if e >= k then $L.list_vt_nil() else args_of(buf, k, e + 1)): $L.listv($P.arg_entry)
  in $L.list_vt_cons(arg_of(b), rest) end

(* <path[p, e)>/clang as a path *)
fn candidate_of {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} (path: !$A.arr(byte, l, n), p: int p, e: int e): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_range(b, path, p, e)
  val () = put(b, "/clang")
in b end

(* The first path of "clang" in the directories of path[p, k) but standin[0, sk): empty when there is none *)
fun real_clang {l:agz}{n:pos}{k:nat | k <= n}{p:nat | p <= k}{ls:agz}{ns:pos}{sk:nat | sk <= ns} .<k - p>.
  (path: !$A.arr(byte, l, n), k: int k, p: int p, standin: !$A.arr(byte, ls, ns), sk: int sk): $B.builder_v =
  if p >= k then $B.create()
  else let
    val e = find_byte(path, k, p, 58)
    val is_standin = (if e - p = sk then same_bytes(path, p, standin, 0, sk, 0) else false): bool
    val usable = (if e > p then ~is_standin else false): bool
    val exists = (if usable then path_exists(candidate_of(path, p, e)) else false): bool
  in
    if exists then candidate_of(path, p, e)
    else if e >= k then $B.create()
    else real_clang(path, k, e + 1, standin, sk)
  end

(* The file at path gets text appended (O_APPEND: a line is one write) *)
fn append_line (path: $B.builder_v, text: $B.builder_v): void = let
  val @(pa, pn) = exact_path(path)
  val @(pfz, pbv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(pbv, pn, $F.WriteOnly(), $F.CreateOrAppend(), 420)
  val () = $A.drop<byte>(pfz, pbv)
  val () = $A.free<byte>($A.thaw<byte>(pfz))
in
  case+ opened of
  | ~$R.err(_) => $B.builder_free(text)
  | ~$R.ok(fd) => let
      val @(ta, tn) = exact_path(text)
      val @(tfz, tbv) = $A.freeze<byte>(ta)
      val k = tn - 1
      val @(left, right) = $A.borrow_split<byte>(tfz, tbv, k)
      val () = (if k > 0 then (case+ $F.file_write(fd, left, k) of
        | ~$R.ok(_) => ()
        | ~$R.err(_) => ()) else ())
      val () = $A.drop<byte>(tfz, $A.borrow_join<byte>(tfz, left, right))
      val () = $A.free<byte>($A.thaw<byte>(tfz))
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
end

fun free_args {n:nat} .<n>. (xs: $L.list_vt($P.arg_entry, n)): void =
  case+ xs of
  | ~$L.list_vt_nil() => ()
  | ~$L.list_vt_cons(@(arr, _), tl) => let val () = $A.free<byte>(arr) in free_args(tl) end

(* The program run with argv, sharing this process's streams; its exit status, 127 when it did not start *)
fn run_inherit (program: $B.builder_v, argv: $L.listv($P.arg_entry)): int = let
  val (nul | exec, _) = spawn_path(program)
  val @(fz, bv) = $A.barr_freeze(exec)
  val spawned = $P.spawn_inherit_env_proved(nul | bv, argv, $P.inherit(), $P.inherit(), $P.inherit())
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

fn sleep_for {sn:nat} (seconds: string sn): void = let
  val argv = $L.list_vt_cons(arg_of(builder_of("sleep")), $L.list_vt_cons(arg_of(builder_of(seconds)), $L.list_vt_nil()))
  val _ = run_inherit(builder_of("sleep"), argv)
in end

(* n bytes x on stderr, no line feed: a message of the size CC_BIG asks for, more than a pipe holds *)
fun err_x {n:nat} .<n>. (n: int n): void =
  if n <= 0 then ()
  else let val () = prerr_char('x') in err_x(n - 1) end

(* The text of b on stderr *)
fn prerr_text (b: $B.builder_v): void = let
  fun loop {l:agz}{n:pos}{m:nat | m <= n}{j:nat | j <= m} .<m - j>.
    (src: !$A.arr(byte, l, n), j: int j, m: int m): void =
    if j >= m then ()
    else let
      val () = prerr_char(int2char0(byte2int0($A.get<byte>(src, j))))
    in loop(src, j + 1, m) end
  val @(arr, len) = $B.into_arr(b)
  val () = loop(arr, 0, len)
in $A.free<byte>(arr) end

(* The path of the log, lbuf[0, lk) *)
fn log_path {ll:agz}{lk:nat | lk <= 4096} (lbuf: !$A.arr(byte, ll, 4096), lk: int lk): $B.builder_v = let
  var path : $B.builder_v = $B.create()
  val () = put_range(path, lbuf, 0, lk)
in path end

(* One line of the log: the text before, the C file buf[s, e), the text after *)
fn log_text {l:agz}{n:pos}{s,e:nat | s <= e; e <= n}{sg,sh:nat}
  (buf: !$A.arr(byte, l, n), s: int s, e: int e, before: string sg, after: string sh): $B.builder_v = let
  var text : $B.builder_v = $B.create()
  val () = put(text, before)
  val () = put_range(text, buf, s, e)
  val () = put(text, after)
in text end

(* Whether the word buf[s, e) ends with the variable name's value (not set or empty: no) *)
fn named_by {l:agz}{n:pos}{s,e:nat | s <= e; e <= n}{sn:nat}
  (buf: !$A.arr(byte, l, n), s: int s, e: int e, name: string sn): bool = let
  val vbuf = $A.alloc<byte>(4096)
  val vk = env_into(name, vbuf)
  val m1 = (if vk >= 1 then vk else 1): [m:pos | m <= 4096] int m
  val ends = ends_with(buf, s, e, vbuf, m1)
  val yes = (if vk >= 1 then ends else false): bool
  val () = $A.free<byte>(vbuf)
in yes end

(* Whether the word buf[s, e) ends with the text w *)
fn ends_text {l:agz}{n:pos}{s,e:nat | s <= e; e <= n}{sw:nat}
  (buf: !$A.arr(byte, l, n), s: int s, e: int e, w: string sw): bool = let
  val wn = g1u2i(string1_length(w))
in if e - s < wn then false else word_is(buf, e - wn, e, w) end

(* The number the variable name holds (digits), 1 when it is not set or is not one *)
fn env_number {sn:nat} (name: string sn): int = let
  val vbuf = $A.alloc<byte>(4096)
  val vk = env_into(name, vbuf)
  fun digits {l:agz}{k:nat | k <= 4096}{p:nat | p <= k} .<k - p>.
    (buf: !$A.arr(byte, l, 4096), k: int k, p: int p, acc: int): int =
    if p >= k then acc
    else let
      val c = byte2int0($A.get<byte>(buf, p))
    in if c < 48 then 1 else if c > 57 then 1 else digits(buf, k, p + 1, acc * 10 + (c - 48)) end
  val n = digits(vbuf, vk, 0, 0)
  val () = $A.free<byte>(vbuf)
in (if vk >= 1 then n else 1) end

(* Waits, at most tries * 0.05 s, until the log has had target compiles running at once *)
fun wait_peak {l:agz}{lk:nat | lk <= 4096}{t:nat} .<t>.
  (lbuf: !$A.arr(byte, l, 4096), lk: int lk, target: int, tries: int t): void =
  if tries <= 0 then ()
  else if target <= 1 then ()
  else let
    val @(best, _) = log_overlap(log_path(lbuf, lk))
  in
    if best >= target then ()
    else let val () = sleep_for("0.05") in wait_peak(lbuf, lk, target, tries - 1) end
  end

implement main0 () = let
  val args = $A.alloc<byte>(16384)
  val k = (case+ $E.args_read(args, 16384) of
    | ~$R.some(k) => k
    | ~$R.none() => 0): [k:nat | k <= 16384] int k
  val has_c = any_word(args, k, 0, "-c")
  val has_e = any_word(args, k, 0, "-E")
  val cs = first_c(args, k, 0)
  val ce = find_byte(args, k, cs, 0)
  val is_dats = ends_text(args, cs, ce, "_dats.c")
  val do_compile = (has_c && ~has_e && cs < k): bool
  val path = $A.alloc<byte>(4096)
  val pk = env_into("PATH", path)
  val standin = $A.alloc<byte>(4096)
  val sk = env_into("STANDIN_DIR", standin)
  val real = real_clang(path, pk, 0, standin, sk)
  val () = $A.free<byte>(path)
  val () = $A.free<byte>(standin)
  val lbuf = $A.alloc<byte>(4096)
  val lk = env_into("CC_LOG", lbuf)
  val lk_compile = (if do_compile then lk else 0): [k:nat | k <= 4096] int k
  val wait_for = (if do_compile && is_dats then env_number("CC_WAIT_FOR") else 1): int
  val () = append_line(log_path(lbuf, lk_compile), log_text(args, cs, ce, "S ", "\n"))
  val () = wait_peak(lbuf, lk_compile, wait_for, 60)
  val slow = named_by(args, cs, ce, "CC_SLOW")
  val fail_a = named_by(args, cs, ce, "CC_FAIL_A")
  val fail_b = named_by(args, cs, ce, "CC_FAIL_B")
  val fails = (fail_a || fail_b): bool
  val big = named_by(args, cs, ce, "CC_BIG")
  val noisy = named_by(args, cs, ce, "CC_NOISY")
  val path_e = log_path(lbuf, lk_compile)
  val text_e = log_text(args, cs, ce, "E ", "\n")
  val path_f = log_path(lbuf, lk_compile)
  val text_f = log_text(args, cs, ce, "F ", "\n")
  val message = log_text(args, cs, ce, "stand-in clang: ", " failed\n")
  val run_args = args_of(args, k, 0)
  val () = $A.free<byte>(lbuf)
  val () = $A.free<byte>(args)
  val status = (if do_compile then let
      val () = (if is_dats then (if slow then sleep_for("1.8") else sleep_for("0.3")) else ())
    in
      if fails then let
        val () = free_args(run_args)
        val () = $B.builder_free(real)
        val () = $B.builder_free(text_e)
        val () = $B.builder_free(path_e)
        val () = prerr_text(message)
        val () = (if big then let val () = sleep_for("0.5") in err_x(200000) end else ())
        val () = append_line(path_f, text_f)
      in 1 end
      else let
        val () = (if noisy then err_x(200000) else ())
        val st = run_inherit(real, run_args)
        val () = append_line(path_e, text_e)
        val () = $B.builder_free(text_f)
        val () = $B.builder_free(path_f)
        val () = $B.builder_free(message)
      in st end
    end
    else let
      val () = $B.builder_free(text_e)
      val () = $B.builder_free(path_e)
      val () = $B.builder_free(text_f)
      val () = $B.builder_free(path_f)
      val () = $B.builder_free(message)
    in run_inherit(real, run_args) end): int
in exit_void(status) end
