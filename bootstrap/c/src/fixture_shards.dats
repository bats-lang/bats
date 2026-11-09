staload "./fixture_shards.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* fixture_shards -- which of the fixture groups (tests/<group>/check.sh) a job of check.yml runs (bats#619, bats#621; keyword: fixture-shards).
   bats fixture-shards plan <pins file> <tests dir> <output file>
     checks the pins file, prints the groups of every shard, fails unless each group is in exactly one shard,
     and appends the line shards=[1,2,...] to the output file ($GITHUB_OUTPUT): the matrix of the jobs.
   bats fixture-shards run <pins file> <tests dir> <shard> <bats> <repository>
     prints the groups of that shard as its first line and runs them with <tests dir>/run-fixtures.sh.
   A group is in the shard the pins file gives it (a line "<group> <shard>"), else in shard
   (sum of the bytes of its name) mod (shards) + 1. The first line of the file is "shards <count>".
   The pins file is src/fixture_shards.txt. The code below reads its arguments with argv[0] = fixture-shards
   (the command line from the subcommand on), so "plan" and "run" are argument 1. *)
#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

(* ============================================================
   Text: a builder_v holds the bytes of a command or a path
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

(* a[i, m) appended to out *)
fun put_arr {l:agz}{n:nat}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (out: !$B.builder_v >> $B.builder_v, a: !$A.arr(byte, l, n), m: int m, i: int i): void =
  if i >= m then ()
  else let
    val () = put_byte_v(out, byte2int0($A.get<byte>(a, i)))
  in put_arr(out, a, m, i + 1) end

(* a[i, m) printed *)
fun print_arr {l:agz}{n:nat}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (a: !$A.arr(byte, l, n), m: int m, i: int i): void =
  if i >= m then ()
  else let
    val () = print_char(int2char0(byte2int0($A.get<byte>(a, i))))
  in print_arr(a, m, i + 1) end

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

fn path_exists (path: $B.builder_v): bool = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_exists(bv, pn)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* ============================================================
   The arguments: NUL-separated in an array of 8192 bytes
   ============================================================ *)

(* The start of the argument n places after p *)
fun arg_start {l:agz}{k:nat | k <= 8192}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, 8192), k: int k, p: int p, n: int): [r:nat | p <= r; r <= k] int r =
  if n <= 0 then p
  else if p >= k then p
  else if byte2int0($A.get<byte>(buf, p)) = 0 then arg_start(buf, k, p + 1, n - 1)
  else arg_start(buf, k, p + 1, n)

fun arg_stop {l:agz}{k:nat | k <= 8192}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, 8192), k: int k, p: int p): [r:nat | p <= r; r <= k] int r =
  if p >= k then p
  else if byte2int0($A.get<byte>(buf, p)) = 0 then p
  else arg_stop(buf, k, p + 1)

fun put_range {l:agz}{s,e:nat | s <= e; e <= 8192} .<e - s>.
  (out: !$B.builder_v >> $B.builder_v, buf: !$A.arr(byte, l, 8192), s: int s, e: int e): void =
  if s >= e then ()
  else let
    val () = put_byte_v(out, byte2int0($A.get<byte>(buf, s)))
  in put_range(out, buf, s + 1, e) end

(* The argument number n (argv[0] is number 0) *)
fn arg_b {l:agz}{k:nat | k <= 8192} (buf: !$A.arr(byte, l, 8192), k: int k, n: int): $B.builder_v = let
  val s = arg_start(buf, k, 0, n)
  val e = arg_stop(buf, k, s)
  var b : $B.builder_v = $B.create()
  val () = put_range(b, buf, s, e)
in b end

(* Whether the argument number n is exactly the string s *)
fn arg_is {l:agz}{k:nat | k <= 8192}{sn:nat} (buf: !$A.arr(byte, l, 8192), k: int k, n: int, s: string sn): bool = let
  fun same {sl:nat}{p:nat}{j:nat | j <= sl} .<sl - j>.
    (buf: !$A.arr(byte, l, 8192), k: int k, p: int p, s: string sl, sl: int sl, j: int j): bool =
    if j >= sl then
      (if p + j >= k then true else byte2int0($A.get<byte>(buf, p + j)) = 0)
    else if p + j >= k then false
    else if byte2int0($A.get<byte>(buf, p + j)) = char2int0(string_get_at(s, j)) then same(buf, k, p, s, sl, j + 1)
    else false
  val st = arg_start(buf, k, 0, n)
in same(buf, k, st, s, g1u2i(string1_length(s)), 0) end

(* ============================================================
   The pins file: lines "<name> <number>"
   ============================================================ *)

fn say_and_stop {sn:nat} (what: string sn): void = let
  val () = println! ("fixture-shards: ", what)
in exit_void(1) end

(* The file's bytes (fewer than 8192) *)
fn read_pins (path: $B.builder_v): [l:agz][k:nat | k < 8192] @($A.arr(byte, l, 8192), int k) = let
  val @(pa, pn) = exact_path(path)
  val @(pfz, pbv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(pbv, pn, $F.ReadOnly(), $F.OpenExisting(), 0)
  val () = $A.drop<byte>(pfz, pbv)
  val () = $A.free<byte>($A.thaw<byte>(pfz))
in
  case+ opened of
  | ~$R.err(_) => let
      val () = say_and_stop("the pins file cannot be read")
      val spare = $A.alloc<byte>(8192)
    in @(spare, 0) end
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(8192)
      val rr = $F.file_read(fd, buf, 8192)
      val k = (case+ rr of | ~$R.ok(n) => n | ~$R.err(_) => 0): [k:nat | k <= 8192] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in
      if k < 8192 then @(buf, k)
      else let
        val () = $A.free<byte>(buf)
        val () = say_and_stop("the pins file has 8192 bytes or more")
        val spare = $A.alloc<byte>(8192)
      in @(spare, 0) end
    end
end

(* The end of the line that starts at p *)
fun eol {l:agz}{k:nat | k <= 8192}{p:nat | p <= k} .<k - p>.
  (text: !$A.arr(byte, l, 8192), k: int k, p: int p): [r:nat | p <= r; r <= k] int r =
  if p >= k then p
  else if byte2int0($A.get<byte>(text, p)) = 10 then p
  else eol(text, k, p + 1)

(* The first space of [p, e), else e *)
fun space_in {l:agz}{k:nat | k <= 8192}{p,e:nat | p <= e; e <= k} .<e - p>.
  (text: !$A.arr(byte, l, 8192), k: int k, p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if byte2int0($A.get<byte>(text, p)) = 32 then p
  else space_in(text, k, p + 1, e)

(* The number whose digits start at p, 0 when there is none; saturates *)
fun number_at {l:agz}{k:nat | k <= 8192}{p:nat | p <= k} .<k - p>.
  (text: !$A.arr(byte, l, 8192), k: int k, p: int p, acc: int): int =
  if p >= k then acc
  else let
    val c = byte2int0($A.get<byte>(text, p))
  in
    if c >= 48 then
      (if c <= 57 then (if acc > 100000 then acc else number_at(text, k, p + 1, acc * 10 + c - 48)) else acc)
    else acc
  end

(* Whether text[p, p + nl) is name[0, nl) *)
fun match_at {l:agz}{la:agz}{k:nat | k <= 8192}{n:nat}{nl:nat | nl <= n}{p:nat}{j:nat | j <= nl} .<nl - j>.
  (text: !$A.arr(byte, l, 8192), k: int k, name: !$A.arr(byte, la, n), nl: int nl, p: int p, j: int j): bool =
  if j >= nl then true
  else if p + j >= k then false
  else if byte2int0($A.get<byte>(text, p + j)) = byte2int0($A.get<byte>(name, j)) then match_at(text, k, name, nl, p, j + 1)
  else false

(* The number of the line "<name> <number>" starting at or after p, 0 when no line is that *)
fun lookup {l:agz}{la:agz}{k:nat | k <= 8192}{n:nat}{nl:nat | nl <= n}{p:nat | p <= k} .<k - p>.
  (text: !$A.arr(byte, l, 8192), k: int k, name: !$A.arr(byte, la, n), nl: int nl, p: int p): int =
  if p >= k then 0
  else let
    val e = eol(text, k, p)
    val value = (if match_at(text, k, name, nl, p, 0) then
      (if p + nl < k then
        (if byte2int0($A.get<byte>(text, p + nl)) = 32 then number_at(text, k, p + nl + 1, 0) else 0)
       else 0)
      else 0): int
  in
    if value > 0 then value
    else if e >= k then 0
    else lookup(text, k, name, nl, e + 1)
  end

fun byte_sum {la:agz}{n:nat}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (name: !$A.arr(byte, la, n), m: int m, i: int i, acc: int): int =
  if i >= m then acc
  else byte_sum(name, m, i + 1, acc + byte2int0($A.get<byte>(name, i)))

(* The shard of a group: its pin, else the sum of the bytes of its name mod the shards, plus one *)
fn shard_of {l:agz}{la:agz}{k:nat | k <= 8192}{n:nat}{m:nat | m <= n}
  (pins: !$A.arr(byte, l, 8192), k: int k, name: !$A.arr(byte, la, n), m: int m, shards: int): int = let
  val pinned = lookup(pins, k, name, m, 0)
in
  if pinned >= 1 then pinned
  else $AR.add_int_int($AR.mod_int_int(byte_sum(name, m, 0, 0), shards), 1)
end

(* A string as an array of 1024 bytes (the rest zero) *)
fn name_of {sn:nat} (s: string sn): [l:agz] $A.arr(byte, l, 1024) = let
  val a = $A.alloc<byte>(1024)
  fun loop {l:agz}{sl:nat}{j:nat | j <= sl} .<sl - j>.
    (a: !$A.arr(byte, l, 1024), s: string sl, sl: int sl, j: int j): void =
    if j >= sl then ()
    else if j >= 1024 then ()
    else let
      val () = $A.set<byte>(a, j, $A.int2byte($AR.low_byte(char2int0(string_get_at(s, j)))))
    in loop(a, s, sl, j + 1) end
  val () = loop(a, s, g1u2i(string1_length(s)), 0)
in a end

(* The number of shards the first line gives: 1 to 64, else the run stops *)
fn shards_of {l:agz}{k:nat | k <= 8192} (pins: !$A.arr(byte, l, 8192), k: int k): int = let
  val nm = name_of("shards")
  val n = lookup(pins, k, nm, 6, 0)
  val () = $A.free<byte>(nm)
in
  if n >= 1 then (if n <= 64 then n else let val () = say_and_stop("shards must be 1 to 64") in exit(1) end)
  else let val () = say_and_stop("the pins file has no line \"shards <count>\"") in exit(1) end
end

(* The path <tests dir>/<name><suffix> *)
fn group_path {l:agz}{k:nat | k <= 8192}{la:agz}{n:nat}{m:nat | m <= n}{ss:nat}
  (args: !$A.arr(byte, l, 8192), k: int k, tests_arg: int, name: !$A.arr(byte, la, n), m: int m, suffix: string ss): $B.builder_v = let
  var b : $B.builder_v = arg_b(args, k, tests_arg)
  val () = put(b, "/")
  val () = put_arr(b, name, m, 0)
  val () = put(b, suffix)
in b end

(* ============================================================
   The lines of the pins file are checked: a group that exists, a shard in range
   ============================================================ *)

(* pins[p, sp) copied to nm[j, ...) *)
fun put_pins_name {l:agz}{la:agz}{p,sp:nat | p <= sp; sp <= 8192}{j:nat | j <= 1024} .<sp - p>.
  (pins: !$A.arr(byte, l, 8192), nm: !$A.arr(byte, la, 1024), p: int p, sp: int sp, j: int j): void =
  if p >= sp then ()
  else if j >= 1024 then ()
  else let
    val () = $A.set<byte>(nm, j, $A.int2byte($AR.low_byte(byte2int0($A.get<byte>(pins, p)))))
  in put_pins_name(pins, nm, p + 1, sp, j + 1) end

(* When on: the message and the name are printed *)
fn complain {la:agz}{n:nat}{m:nat | m <= n}{sn:nat} (on: bool, msg: string sn, nm: !$A.arr(byte, la, n), m: int m): void =
  if on then let
    val () = print! ("fixture-shards: ", msg)
    val () = print_arr(nm, m, 0)
  in print_newline() end
  else ()

(* 1 for a line that is wrong (and said), 0 for one that is right; the name is pins[p, sp) *)
fn check_one {l:agz}{la:agz}{k:nat | k <= 8192}{ka:nat | ka <= 8192}{p,sp,e:nat | p < sp; sp <= e; e <= k}
  (pins: !$A.arr(byte, l, 8192), k: int k, args: !$A.arr(byte, la, 8192), ka: int ka, tests_arg: int, shards: int,
   p: int p, sp: int sp, e: int e): int =
  if sp - p > 1024 then let
    val () = println! ("fixture-shards: a name in the pins file is longer than 1024 bytes")
  in 1 end
  else let
    val width = sp - p
    val nm = $A.alloc<byte>(1024)
    val () = put_pins_name(pins, nm, p, sp, 0)
    val sh = name_of("shards")
    val shards_text = match_at(pins, k, sh, 6, p, 0)
    val () = $A.free<byte>(sh)
    val is_shards = (if width = 6 then shards_text else false): bool
    val value = (if sp < e then number_at(pins, k, sp + 1, 0) else 0): int
    val script_there = path_exists(group_path(args, ka, tests_arg, nm, width, "/check.sh"))
    val exists = (if is_shards then true else script_there): bool
    val in_range = (if value >= 1 then value <= shards else false): bool
    val () = complain(not(exists), "the pins file names a group that is not there: ", nm, width)
    val () = complain(not(is_shards) && not(in_range), "the pins file puts a group in a shard that is not there: ", nm, width)
    val () = $A.free<byte>(nm)
  in
    if exists then (if is_shards then 0 else if in_range then 0 else 1) else 1
  end

fun check_lines {l:agz}{la:agz}{k:nat | k <= 8192}{ka:nat | ka <= 8192}{p:nat | p <= k} .<k - p>.
  (pins: !$A.arr(byte, l, 8192), k: int k, args: !$A.arr(byte, la, 8192), ka: int ka, tests_arg: int, shards: int,
   p: int p, bad: int): int =
  if p >= k then bad
  else let
    val e = eol(pins, k, p)
    val sp = space_in(pins, k, p, e)
    val bad2 = (if sp > p then
        (if byte2int0($A.get<byte>(pins, p)) = 35 then bad
         else bad + check_one(pins, k, args, ka, tests_arg, shards, p, sp, e))
      else bad): int
  in
    if e >= k then bad2 else check_lines(pins, k, args, ka, tests_arg, shards, e + 1, bad2)
  end

(* ============================================================
   The groups of a shard: the directories of the tests directory with a check.sh
   ============================================================ *)

(* When mine: the group's script is added to cmd as a line and, when say, its name is printed *)
fn add_group {l:agz}{la:agz}{ka:nat | ka <= 8192}{n:nat}{m:nat | m <= n}
  (mine: bool, say: bool, cmd: !$B.builder_v >> $B.builder_v, args: !$A.arr(byte, l, 8192), ka: int ka, tests_arg: int,
   nm: !$A.arr(byte, la, n), m: int m): void =
  if mine then let
    val () = put_builder(cmd, group_path(args, ka, tests_arg, nm, m, "/check.sh"))
    val () = put_byte_v(cmd, 10)
  in
    if say then let
      val () = print_char(' ')
    in print_arr(nm, m, 0) end
    else ()
  end
  else ()

(* Walks the entries from i: each group is counted in all, and in found when its shard is want, and then
   its script is added to cmd as a line and, when say, its name is printed *)
fun walk {n,i:nat | i <= n}{l:agz}{la:agz}{k:nat | k <= 8192}{ka:nat | ka <= 8192} .<n - i>.
  (es: !$F.entries(n), i: int i, n: int n, args: !$A.arr(byte, la, 8192), ka: int ka, tests_arg: int,
   pins: !$A.arr(byte, l, 8192), k: int k, shards: int, want: int,
   cmd: !$B.builder_v >> $B.builder_v, say: bool, found: int, all: int): @(int, int) =
  if i >= n then @(found, all)
  else let
    val nm = $A.alloc<byte>(1024)
    val nl = $F.entries_name(es, i, nm, 1024)
    val first = byte2int0($A.get<byte>(nm, 0))
    val script_there = path_exists(group_path(args, ka, tests_arg, nm, nl, "/check.sh"))
    val is_group = (if nl > 0 then (if first = 46 then false else script_there) else false): bool
    val sh = shard_of(pins, k, nm, nl, shards)
    val mine = (if is_group then sh = want else false): bool
    val () = add_group(mine, say, cmd, args, ka, tests_arg, nm, nl)
    val () = $A.free<byte>(nm)
  in
    walk(es, i + 1, n, args, ka, tests_arg, pins, k, shards, want, cmd, say,
      (if mine then found + 1 else found), (if is_group then all + 1 else all))
  end

(* ============================================================
   Running a command: words are lines; the first is the program
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

(* The program run with this process's streams and environment; its exit status, 127 when it did not start *)
fn spawn_wait (command: $B.builder_v): int = let
  val @(program, argv) = command_parts(command)
  val (nul | exec, _) = spawn_path(program)
  val @(fz, bv) = $A.barr_freeze(exec)
  val spawned = $P.spawn_inherit_env_proved(nul | bv, argv, $P.dev_null(), $P.inherit(), $P.inherit())
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

(* ============================================================
   plan and run
   ============================================================ *)

(* The decimal digits of n (0 to 99) appended to out *)
fn put_int (out: !$B.builder_v >> $B.builder_v, n: int): void = let
  val () = (if n >= 10 then put_byte_v(out, 48 + $AR.div_int_int(n, 10)) else ())
in put_byte_v(out, 48 + $AR.mod_int_int(n, 10)) end

(* The line "shards=[1,2,...,n]" *)
fun put_matrix {kk:nat | kk <= 65} .<65 - kk>. (out: !$B.builder_v >> $B.builder_v, shards: int, kk: int kk): void =
  if kk > 64 then ()
  else if kk > shards then ()
  else let
    val () = (if kk > 1 then put(out, ",") else ())
    val () = put_int(out, kk)
  in put_matrix(out, shards, kk + 1) end

(* The builder's text appended to the file at path *)
fn append_text (path: $B.builder_v, text: $B.builder_v): bool = let
  val @(pa, pn) = exact_path(path)
  val @(pfz, pbv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(pbv, pn, $F.WriteOnly(), $F.CreateOrAppend(), 420)
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

(* The shards 1 to shards, each printed with its groups; the groups placed in a shard, and the groups there are *)
fun plan_shards {n:nat}{l:agz}{la:agz}{k:nat | k <= 8192}{ka:nat | ka <= 8192}{kk:nat | kk <= 65} .<65 - kk>.
  (es: !$F.entries(n), n: int n, args: !$A.arr(byte, la, 8192), ka: int ka, tests_arg: int,
   pins: !$A.arr(byte, l, 8192), k: int k, shards: int, kk: int kk, placed: int, all: int): @(int, int) =
  if kk > 64 then @(placed, all)
  else if kk > shards then @(placed, all)
  else let
    val () = print! ("shard ", kk, ":")
    var scratch : $B.builder_v = $B.create()
    val @(found, total) = walk(es, 0, n, args, ka, tests_arg, pins, k, shards, kk, scratch, true, 0, 0)
    val () = $B.builder_free(scratch)
    val () = println! (" (", found, " groups)")
  in plan_shards(es, n, args, ka, tests_arg, pins, k, shards, kk + 1, placed + found, total) end

fn plan {la:agz}{ka:nat | ka <= 8192} (args: !$A.arr(byte, la, 8192), ka: int ka): void = let
  val @(pins, kp) = read_pins(arg_b(args, ka, 2))
  val shards = shards_of(pins, kp)
  val bad = check_lines(pins, kp, args, ka, 3, shards, 0, 0)
  val @(ta, tn) = exact_path(arg_b(args, ka, 3))
  val @(tfz, tbv) = $A.freeze<byte>(ta)
  val listed = $F.dir_read(tbv, tn)
  val () = $A.drop<byte>(tfz, tbv)
  val () = $A.free<byte>($A.thaw<byte>(tfz))
  val ok = (case+ listed of
    | ~$R.err(_) => let val () = println! ("fixture-shards: the tests directory cannot be read") in false end
    | ~$R.ok(es) => let
        val @(placed, all) = plan_shards(es, $F.entries_count(es), args, ka, 3, pins, kp, shards, 1, 0, 0)
        val () = $F.entries_free(es)
        val () = println! ("groups: ", all, ", placed in a shard: ", placed)
      in (if placed = all then (if all > 0 then true else false) else false) end): bool
  val () = $A.free<byte>(pins)
  val () = (if ok then (if bad = 0 then () else say_and_stop("the pins file is wrong")) else say_and_stop("a group is in no shard, or in two, or there is none"))
  var out : $B.builder_v = builder_of("shards=[")
  val () = put_matrix(out, shards, 1)
  val () = put(out, "]\n")
  val () = (if append_text(arg_b(args, ka, 4), out) then () else say_and_stop("the output file cannot be written"))
in end

(* The command's exit status; a shard with no group is not run (run-fixtures.sh would run every group) *)
fn run_or_stop (cmd: $B.builder_v, found: int): int =
  if found > 0 then spawn_wait(cmd)
  else let
    val () = $B.builder_free(cmd)
    val () = say_and_stop("the shard has no group")
  in 1 end

fn run {la:agz}{ka:nat | ka <= 8192} (args: !$A.arr(byte, la, 8192), ka: int ka): void = let
  val @(pins, kp) = read_pins(arg_b(args, ka, 2))
  val shards = shards_of(pins, kp)
  val want = number_at(args, ka, arg_start(args, ka, 0, 4), 0)
  val () = (if want >= 1 then (if want <= shards then () else say_and_stop("the shard is not there")) else say_and_stop("the shard is not there"))
  val @(ta, tn) = exact_path(arg_b(args, ka, 3))
  val @(tfz, tbv) = $A.freeze<byte>(ta)
  val listed = $F.dir_read(tbv, tn)
  val () = $A.drop<byte>(tfz, tbv)
  val () = $A.free<byte>($A.thaw<byte>(tfz))
  var cmd : $B.builder_v = arg_b(args, ka, 3)
  val () = put(cmd, "/run-fixtures.sh\n")
  val () = put_builder(cmd, arg_b(args, ka, 5))
  val () = put_byte_v(cmd, 10)
  val () = put_builder(cmd, arg_b(args, ka, 6))
  val () = put_byte_v(cmd, 10)
  val () = print! ("shard ", want, " of ", shards, ":")
  val found = (case+ listed of
    | ~$R.err(_) => let val () = println! ("fixture-shards: the tests directory cannot be read") in 0 end
    | ~$R.ok(es) => let
        val @(found, _) = walk(es, 0, $F.entries_count(es), args, ka, 3, pins, kp, shards, want, cmd, true, 0, 0)
        val () = $F.entries_free(es)
      in found end): int
  val () = println! ()
  val () = $A.free<byte>(pins)
  val () = fileref_flush(stdout_ref)
  val status = run_or_stop(cmd, found)
in (if status = 0 then () else exit(status)) end

fn dispatch {l:agz}{k:nat | k <= 8192} (args: !$A.arr(byte, l, 8192), k: int k): void =
  if arg_is(args, k, 1, "plan") then plan(args, k)
  else if arg_is(args, k, 1, "run") then run(args, k)
  else let
    val () = println! ("usage: bats fixture-shards plan <pins file> <tests dir> <output file>")
    val () = println! ("       bats fixture-shards run <pins file> <tests dir> <shard> <bats> <repository>")
  in exit_void(2) end

(* The command line from argument p on, as the arguments of a program named by it: dst[0, ...) *)
fun shift_args {l:agz}{ld:agz}{k:nat | k <= 8192}{p:nat | p <= k}{j:nat | j <= 8192} .<k - p>.
  (src: !$A.arr(byte, l, 8192), dst: !$A.arr(byte, ld, 8192), k: int k, p: int p, j: int j): [r:nat | j <= r; r <= 8192] int r =
  if p >= k then j
  else if j >= 8192 then j
  else let
    val () = $A.set<byte>(dst, j, $A.int2byte($AR.low_byte(byte2int0($A.get<byte>(src, p)))))
  in shift_args(src, dst, k, p + 1, j + 1) end

(* dispatch on the command line from argument 1 on *)
fn dispatch_shifted {l:agz}{k:nat | k <= 8192} (args: !$A.arr(byte, l, 8192), k: int k): void = let
  val rest = $A.alloc<byte>(8192)
  val kr = shift_args(args, rest, k, arg_start(args, k, 0, 1), 0)
  val () = dispatch(rest, kr)
in $A.free<byte>(rest) end

(* The command line is dispatched when it names fixture-shards *)
fn dispatch_if {l:agz}{k:nat | k <= 8192} (named: bool, args: !$A.arr(byte, l, 8192), k: int k): void =
  if named then dispatch_shifted(args, k) else ()

(* Runs bats fixture-shards when that is the command given and answers true; false for any other command *)


implement fixture_shards_main () = let
  val args = $A.alloc<byte>(8192)
  val k = (case+ $E.args_read(args, 8192) of | ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= 8192] int k
  val handled = arg_is(args, k, 1, "fixture-shards")
  val () = dispatch_if(handled, args, k)
  val () = $A.free<byte>(args)
in handled end
