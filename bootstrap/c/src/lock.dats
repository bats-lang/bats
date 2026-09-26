staload "./lock.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
staload "str/src/lib.dats"
staload "toml/src/lib.dats"
(* lock -- bats lock, as the Rust bats's lock::generate and resolve_all *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"
staload S = "str/src/lib.sats"
staload T = "toml/src/lib.sats"

staload "helpers.sats"
staload "lexer.sats"
staload "docs.sats"

(* ============================================================
   Package names
   ============================================================ *)

(* A list of package names, each name[0, k) of a 256-byte array *)
datavtype names(int) =
  | names_nil(0) of ()
  | {l:agz}{k:pos | k <= 256}{n:nat}
    names_cons(n + 1) of ($A.arr(byte, l, 256), int k, names(n))

fun names_free {n:nat} .<n>. (xs: names(n)): void =
  case+ xs of
  | ~names_nil() => ()
  | ~names_cons(a, _, rest) => let
      val () = $A.free<byte>(a)
    in names_free(rest) end

(* Whether a[0, k) and b[0, k) hold the same bytes *)
fun same_name {la,lb:agz}{k:nat | k <= 256}{i:nat | i <= k} .<k - i>.
  (a: !$A.arr(byte, la, 256), b: !$A.arr(byte, lb, 256), k: int k, i: int i): bool =
  if i >= k then true
  else if $AR.eq_int_int(byte2int0($A.get<byte>(a, i)), byte2int0($A.get<byte>(b, i)))
  then same_name(a, b, k, i + 1)
  else false

(* Whether xs holds the name b[0, kb) *)
fun names_has {n:nat}{lb:agz}{kb:pos | kb <= 256} .<n>.
  (xs: !names(n), b: !$A.arr(byte, lb, 256), kb: int kb): bool =
  case+ xs of
  | names_nil() => false
  | @names_cons(a, ka, rest) => let
      val hit = (if ka = kb then same_name(a, b, kb, 0) else false): bool
      val r = (if hit then true else names_has(rest, b, kb)): bool
      prval () = fold@(xs)
    in r end

(* src[s, e), at most 256 bytes of it, copied into a name array *)
fun copy_name {l:agz}{n:pos}{la:agz}{i:nat | i <= 256} .<256 - i>.
  (src: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, n: int n,
   a: !$A.arr(byte, la, 256), i: int i): [k:nat | k <= 256] int k =
  if i >= 256 then i
  else if s + i >= e then i
  else let
    val () = $A.set<byte>(a, i, $A.int2byte($AR.low_byte(peek(src, s + i, n))))
  in copy_name(src, s, e, n, a, i + 1) end

(* a[i], or 0 outside [0, 256) *)
fn peek256 {la:agz} (a: !$A.arr(byte, la, 256), i: pos_t): int =
  if i < 0 then 0
  else if i >= 256 then 0
  else byte2int0($A.get<byte>(a, i))

(* a[i, k) appended to out *)
fun put_bytes {la:agz}{f:nat} .<f>.
  (a: !$A.arr(byte, la, 256), i: pos_t, k: int, out: !$B.builder_v >> $B.builder_v, f: int f): void =
  if f <= 0 then ()
  else if i >= k then ()
  else let
    val () = put_char_v(out, peek256(a, i))
  in put_bytes(a, i + 1, k, out, f - 1) end

(* The name a[0, k) appended to out *)
fn put_name {la:agz}
  (a: !$A.arr(byte, la, 256), k: int, out: !$B.builder_v >> $B.builder_v): void =
  put_bytes(a, 0, k, out, 256)

(* ============================================================
   The #use packages of a directory (Rust: collect_packages)
   ============================================================ *)

(* Adds the packages of the #use spans spans[idx, count) of src to seen,
   newest first, skipping those already there *)
fun add_uses {l,ls:agz}{n:pos}{m:nat}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), n: int n,
   spans: !$A.borrow(byte, ls, 524288), idx: pos_t, count: int,
   seen: names(m), fuel: int fuel): [m2:nat] names(m2) =
  if fuel <= 0 then seen
  else if idx >= count then seen
  else if peek(spans, idx * 28, 524288) <> 1 then
    add_uses(src, n, spans, idx + 1, count, seen, fuel - 1)
  else let
    val s = span_i32(spans, idx * 28 + 10, 524288)
    val e = span_i32(spans, idx * 28 + 14, 524288)
    val a = $A.alloc<byte>(256)
    val k = copy_name(src, s, e, n, a, 0)
  in
    if k <= 0 then let
      val () = $A.free<byte>(a)
    in add_uses(src, n, spans, idx + 1, count, seen, fuel - 1) end
    else if names_has(seen, a, k) then let
      val () = $A.free<byte>(a)
    in add_uses(src, n, spans, idx + 1, count, seen, fuel - 1) end
    else add_uses(src, n, spans, idx + 1, count, names_cons(a, k, seen), fuel - 1)
  end

(* Adds the #use packages of the file at the NUL-terminated path p *)
fn add_file_uses {lp:agz}{m:nat}
  (p: !$A.borrow(byte, lp, 524288), seen: names(m)): [m2:nat] names(m2) =
  case+ $F.file_open(p, 524288, 0, 0) of
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(524288)
      val nbytes = (case+ $F.file_read(fd, buf, 524288) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 524288] int k
      val () = $R.discard<int><int>($F.file_close(fd))
      val @(fz_src, bv_src) = $A.freeze<byte>(buf)
      val @(span_arr, _, span_count) = do_lex(bv_src, nbytes, 524288)
      val @(fz_sp, bv_sp) = $A.freeze<byte>(span_arr)
      val seen2 = add_uses(bv_src, 524288, bv_sp, 0, span_count, seen, 1048576)
      val () = $A.drop<byte>(fz_sp, bv_sp)
      val () = $A.free<byte>($A.thaw<byte>(fz_sp))
      val () = $A.drop<byte>(fz_src, bv_src)
      val () = $A.free<byte>($A.thaw<byte>(fz_src))
    in seen2 end
  | ~$R.err(_) => seen

(* Adds the #use packages of each file in the NUL-separated list
   files[off, len), in order *)
fun add_files_uses {lf:agz}{m:nat}{fuel:nat} .<fuel>.
  (files: !$A.borrow(byte, lf, 524288), off: pos_t, len: int,
   seen: names(m), fuel: int fuel): [m2:nat] names(m2) =
  if fuel <= 0 then seen
  else if off >= len then seen
  else let
    val e = find_null_bv_from(files, off, 524288)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, 524288, pb)
    val @(pa, _) = $B.to_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val seen2 = add_file_uses(bv_p, seen)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in add_files_uses(files, e + 1, len, seen2, fuel - 1) end

(* The #use packages of the .bats files under dir, newest first: the
   last one first, as Rust's queue pops them *)
fn collect_uses (dir: $B.builder_v): [m:nat] names(m) = let
  val @(fa, flen) = sorted_bats_files(dir)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val seen = add_files_uses(bv_f, 0, flen, names_nil(), 65536)
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in seen end

(* ============================================================
   Versions (Rust: find_latest_version, Version's order)
   ============================================================ *)

(* A version: its parts as Rust renders them (no '+', no leading zeros)
   in a[0, len), and whether it is a dev version *)
datavtype cand =
  | {l:agz}{n:int} cand_mk of ($A.arr(byte, l, 256), int n, bool)

fn cand_free (c: cand): void = let
  val+ ~cand_mk(a, _, _) = c
in $A.free<byte>(a) end

fn cand_dev (c: !cand): bool = let
  val+ @cand_mk(_, _, dev) = c
  val d = dev
  prval () = fold@(c)
in d end

(* The version's text, dev1 included, appended to out *)
fn put_cand (c: !cand, out: !$B.builder_v >> $B.builder_v): void = let
  val+ @cand_mk(a, l, dev) = c
  val () = put_bytes(a, 0, l, out, 256)
  val () = put_dev1(out, dev)
  prval () = fold@(c)
in end

(* The first '.' in a[i, e), or e *)
fun dot_at {la:agz}{f:nat} .<f>.
  (a: !$A.arr(byte, la, 256), i: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if peek256(a, i) = 46 then i
  else dot_at(a, i + 1, e, f - 1)

(* Compares a[i, i + n) and b[j, j + n) byte by byte *)
fun bytes_cmp {la,lb:agz}{f:nat} .<f>.
  (a: !$A.arr(byte, la, 256), i: pos_t, b: !$A.arr(byte, lb, 256), j: pos_t, n: int, f: int f): int =
  if f <= 0 then 0
  else if n <= 0 then 0
  else let
    val x = peek256(a, i)
    val y = peek256(b, j)
  in
    if x < y then ~1
    else if x > y then 1
    else bytes_cmp(a, i + 1, b, j + 1, n - 1, f - 1)
  end

(* Compares the parts a[ai, ae) and b[bi, be), rendered without leading
   zeros; an empty (missing) part counts as 0 *)
fn part_cmp {la,lb:agz}
  (a: !$A.arr(byte, la, 256), ai: pos_t, ae: pos_t,
   b: !$A.arr(byte, lb, 256), bi: pos_t, be: pos_t): int = let
  val za = (if ae - ai = 1 then peek256(a, ai) = 48 else ae <= ai): bool
  val zb = (if be - bi = 1 then peek256(b, bi) = 48 else be <= bi): bool
in
  if za && zb then 0
  else if za then ~1
  else if zb then 1
  else if ae - ai < be - bi then ~1
  else if ae - ai > be - bi then 1
  else bytes_cmp(a, ai, b, bi, ae - ai, 256)
end

(* Compares a[ai, al) and b[bi, bl) part by part, padding the shorter
   with zeros (Rust: Version's Ord) *)
fun parts_cmp {la,lb:agz}{f:nat} .<f>.
  (a: !$A.arr(byte, la, 256), ai: pos_t, al: pos_t,
   b: !$A.arr(byte, lb, 256), bi: pos_t, bl: pos_t, f: int f): int =
  if f <= 0 then 0
  else if ai >= al && bi >= bl then 0
  else let
    val ae = (if ai < al then dot_at(a, ai, al, 256) else ai): pos_t
    val be = (if bi < bl then dot_at(b, bi, bl, 256) else bi): pos_t
    val c = part_cmp(a, ai, ae, b, bi, be)
  in
    if c <> 0 then c
    else parts_cmp(a, (if ae < al then ae + 1 else al), al,
                   b, (if be < bl then be + 1 else bl), bl, f - 1)
  end

(* c against v: ~1, 0 or 1; a dev version orders before the release
   with the same parts (Rust: Version's Ord) *)
fn cand_cmp (c: !cand, v: !cand): int = let
  val+ @cand_mk(ca, cl, cdev) = c
  val+ @cand_mk(va, vl, vdev) = v
  val cmp = parts_cmp(ca, 0, cl, va, 0, vl, 256)
  val d1 = cdev
  val d2 = vdev
  prval () = fold@(v)
  prval () = fold@(c)
in
  if cmp <> 0 then cmp
  else if d1 = d2 then 0
  else if d1 then ~1
  else 1
end

(* Whether c and v are the same version part for part (Rust: Version's
   derived ==, under which 1.0 and 1.0.0 differ) *)
fn cand_same (c: !cand, v: !cand): bool = let
  val+ @cand_mk(ca, cl, cdev) = c
  val+ @cand_mk(va, vl, vdev) = v
  val same = (if cl = vl then bytes_cmp(ca, 0, va, 0, cl, 256) = 0 else false): bool
  val d1 = cdev
  val d2 = vdev
  prval () = fold@(v)
  prval () = fold@(c)
in
  if same then d1 = d2 else false
end

(* src[0, n) (n <= 256 checked) into a new name-sized array *)
fun copy_text {ls,ld:agz}{i:nat | i <= 256} .<256 - i>.
  (src: !$A.arr(byte, ls, 524288), n: int, dst: !$A.arr(byte, ld, 256), i: int i): void =
  if i >= 256 then ()
  else if i >= n then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in copy_text(src, n, dst, i + 1) end

(* The version in e[vs, ve), parsed and rendered as Rust's
   Version::parse and Display do: @(it, ~1, ~1), or @(none, the invalid
   part's [start, end)) when it does not parse *)
fn parse_cand {le:agz}{n:pos}
  (e: !$A.borrow(byte, le, n), n: int n, vs: pos_t, ve: pos_t)
  : @($R.option(cand), pos_t, pos_t) = let
  var d_c = @[char][4]('d', 'e', 'v', '1')
  val dev = (if ve - vs >= 4 then lit_at(e, ve - 4, n, d_c, 4) else false): bool
  val be = (if dev then ve - 4 else ve): pos_t
  var out : $B.builder_v = $B.create()
  val @(bs, bz) = parse_version_parts(e, vs, be, n, out)
  val vl = $B.length(out)
  val @(va, _) = $B.to_arr(out)
in
  if bs >= 0 then let
    val () = $A.free<byte>(va)
  in @($R.none(), bs, bz) end
  (* Longer than a version array holds: the whole of it is the bad part *)
  else if vl > 256 then let
    val () = $A.free<byte>(va)
  in @($R.none(), vs, be) end
  else let
    val t = $A.alloc<byte>(256)
    val () = copy_text(va, vl, t, 0)
    val () = $A.free<byte>(va)
  in @($R.some(cand_mk(t, vl, dev)), ~1, ~1) end
end

(* The version in the file name e[vs, ve), when it parses *)
fn file_cand {le:agz} (e: !$A.borrow(byte, le, 256), vs: pos_t, ve: pos_t): $R.option(cand) = let
  val @(c, _, _) = parse_cand(e, 256, vs, ve)
in c end

(* best, or c when c orders after it; frees the other *)
fn keep_newer (best: $R.option(cand), c: cand): $R.option(cand) =
  case+ best of
  | ~$R.none() => $R.some(c)
  | ~$R.some(b) =>
    if cand_cmp(c, b) > 0 then let
      val () = cand_free(b)
    in $R.some(c) end
    else let
      val () = cand_free(c)
    in $R.some(b) end

(* ============================================================
   Constraints (Rust: Constraint, parse_constraints and the merged
   constraints of resolve_all)
   ============================================================ *)

(* Constraints in the order they were read, each on the package
   pkg[0, pk): >= (true) or != (false) the version v, from the bats.toml
   of the package src[0, sk) *)
datavtype cons(int) =
  | cons_nil(0) of ()
  | {lp,ls:agz}{n:nat}
    cons_cons(n + 1) of ($A.arr(byte, lp, 256), int, bool, cand,
                         $A.arr(byte, ls, 256), int, cons(n))

fun cons_free {n:nat} .<n>. (cs: cons(n)): void =
  case+ cs of
  | ~cons_nil() => ()
  | ~cons_cons(p, _, _, v, s, _, rest) => let
      val () = $A.free<byte>(p)
      val () = cand_free(v)
      val () = $A.free<byte>(s)
    in cons_free(rest) end

(* xs followed by ys *)
fun cons_append {n,m:nat} .<n>. (xs: cons(n), ys: cons(m)): cons(n + m) =
  case+ xs of
  | ~cons_nil() => ys
  | ~cons_cons(p, pk, ge, v, s, sk, rest) =>
    cons_cons(p, pk, ge, v, s, sk, cons_append(rest, ys))

(* Whether p[0, pk) is the name a[0, k) *)
fn name_is {lp,la:agz}
  (p: !$A.arr(byte, lp, 256), pk: int, a: !$A.arr(byte, la, 256), k: int): bool =
  if pk <> k then false else bytes_cmp(p, 0, a, 0, k, 256) = 0

(* Whether c meets every constraint on the package a[0, k) *)
fun cons_allow {n:nat}{la:agz} .<n>.
  (cs: !cons(n), a: !$A.arr(byte, la, 256), k: int, c: !cand): bool =
  case+ cs of
  | cons_nil() => true
  | @cons_cons(p, pk, ge, v, _, _, rest) => let
      val ok = (if ~name_is(p, pk, a, k) then true
                else if ge then cand_cmp(c, v) >= 0
                else ~cand_same(c, v)): bool
      val r = (if ok then cons_allow(rest, a, k, c) else false): bool
      prval () = fold@(cs)
    in r end

(* Whether any constraint is on the package a[0, k) *)
fun cons_about {n:nat}{la:agz} .<n>.
  (cs: !cons(n), a: !$A.arr(byte, la, 256), k: int): bool =
  case+ cs of
  | cons_nil() => false
  | @cons_cons(p, pk, _, _, _, _, rest) => let
      val r = (if name_is(p, pk, a, k) then true else cons_about(rest, a, k)): bool
      prval () = fold@(cs)
    in r end

(* ">= <v> (from <src>)", after ", " when sep (Rust: constraint_display
   and the sources of resolve_all) *)
fn put_con {ls:agz}
  (ge: bool, v: !cand, s: !$A.arr(byte, ls, 256), sk: int, sep: bool,
   out: !$B.builder_v >> $B.builder_v): void = let
  val () = (if sep then bput_v(out, ", ") else bput_v(out, ""))
  val () = (if ge then bput_v(out, ">= ") else bput_v(out, "!= "))
  val () = put_cand(v, out)
  val () = bput_v(out, " (from ")
  val () = put_name(s, sk, out)
in bput_v(out, ")") end

fn put_con_if {ls:agz}
  (hit: bool, ge: bool, v: !cand, s: !$A.arr(byte, ls, 256), sk: int, sep: bool,
   out: !$B.builder_v >> $B.builder_v): void =
  if hit then put_con(ge, v, s, sk, sep, out) else bput_v(out, "")

(* The constraints on the package a[0, k), each as put_con writes it *)
fun put_cons_of {n:nat}{la:agz} .<n>.
  (cs: !cons(n), a: !$A.arr(byte, la, 256), k: int, sep: bool,
   out: !$B.builder_v >> $B.builder_v): void =
  case+ cs of
  | cons_nil() => ()
  | @cons_cons(p, pk, ge, v, s, sk, rest) => let
      val hit = name_is(p, pk, a, k)
      val () = put_con_if(hit, ge, v, s, sk, sep, out)
      val () = put_cons_of(rest, a, k, (if hit then true else sep): bool, out)
      prval () = fold@(cs)
    in end

(* Whether c is whitespace to Rust's str::trim *)
fn is_space (c: int): bool =
  if c = 32 then true else if c < 9 then false else c <= 13

(* The first position in v[i, e) that is not whitespace, or e *)
fun skip_space {lv:agz}{n:pos}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, n), n: int n, i: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if is_space(peek(v, i, n)) then skip_space(v, n, i + 1, e, f - 1)
  else i

(* e without the whitespace that ends v[s, e) *)
fun trim_end {lv:agz}{n:pos}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, n), n: int n, s: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then s
  else if e <= s then s
  else if is_space(peek(v, e - 1, n)) then trim_end(v, n, s, e - 1, f - 1)
  else e

(* The first byte c in v[i, e), or e *)
fun find_byte {lv:agz}{n:pos}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, n), n: int n, i: pos_t, e: pos_t, c: int, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if peek(v, i, n) = c then i
  else find_byte(v, n, i + 1, e, c, f - 1)

(* A constraint read from bats.toml: >= (true) or != (false) a version *)
datavtype con = con_mk of (bool, cand)

(* The constraint v[s, e), trimmed and not empty (Rust: one part of
   parse_constraints); none after writing Rust's message to why *)
fn parse_con {lv:agz}
  (v: !$A.borrow(byte, lv, 4096), s: pos_t, e: pos_t,
   why: !$B.builder_v >> $B.builder_v): $R.option(con) = let
  val c0 = peek(v, s, 4096)
  val c1 = peek(v, s + 1, 4096)
  val two = e - s >= 2
  val ge = (if two then (if c0 = 62 then c1 = 61 else false) else false): bool
  val ne = (if two then (if c0 = 33 then c1 = 61 else false) else false): bool
in
  if ge || ne then let
    val vs = skip_space(v, 4096, s + 2, e, 4096)
    val @(r, bs, bz) = parse_cand(v, 4096, vs, e)
  in
    case+ r of
    | ~$R.some(c) => $R.some(con_mk(ge, c))
    | ~$R.none() => let
        val () = bput_v(why, "invalid version part '")
        val () = copy_to_builder_v(v, bs, bz, 4096, why)
        val () = bput_v(why, "' in '")
        val () = copy_to_builder_v(v, vs, e, 4096, why)
        val () = bput_v(why, "'")
      in $R.none() end
  end
  else let
    val () = bput_v(why, "invalid constraint '")
    val () = copy_to_builder_v(v, s, e, 4096, why)
    val () = bput_v(why, "': must start with >= or !=")
  in $R.none() end
end

(* A copy of the name a[0, k) *)
fn name_copy {la:agz} (a: !$A.arr(byte, la, 256), k: int): [lb:agz] $A.arr(byte, lb, 256) = let
  val b = $A.alloc<byte>(256)
  fun loop {lb:agz}{i:nat | i <= 256} .<256 - i>.
    (a: !$A.arr(byte, la, 256), b: !$A.arr(byte, lb, 256), k: int, i: int i): void =
    if i >= 256 then ()
    else if i >= k then ()
    else let
      val () = $A.set<byte>(b, i, $A.get<byte>(a, i))
    in loop(a, b, k, i + 1) end
  val () = loop(a, b, k, 0)
in b end

(* Appends the constraints of the value v[i, e) (Rust: parse_constraints)
   on the package p[0, pk) from src[0, sk) to acc; false after writing
   Rust's message to why *)
fun parse_cons {lv,lp,ls:agz}{n:nat}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, 4096), i: pos_t, e: pos_t,
   p: !$A.arr(byte, lp, 256), pk: int, src: !$A.arr(byte, ls, 256), sk: int,
   acc: cons(n), why: !$B.builder_v >> $B.builder_v, f: int f): [m:nat] @(bool, cons(m)) =
  if f <= 0 then @(true, acc)
  else if i >= e then @(true, acc)
  else let
    val ce = find_byte(v, 4096, i, e, 44, 4096)
    val ts = skip_space(v, 4096, i, ce, 4096)
    val te = trim_end(v, 4096, ts, ce, 4096)
  in
    if ts >= te then parse_cons(v, ce + 1, e, p, pk, src, sk, acc, why, f - 1)
    else case+ parse_con(v, ts, te, why) of
      | ~$R.some(c) => let
          val+ ~con_mk(ge, cv) = c
          val one = cons_cons(name_copy(p, pk), pk, ge, cv, name_copy(src, sk), sk, cons_nil())
        in parse_cons(v, ce + 1, e, p, pk, src, sk, cons_append(acc, one), why, f - 1) end
      | ~$R.none() => @(false, acc)
  end

(* a[i, n) = keys[off + i, off + n) *)
fun fill_key {lk,la:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(byte, la, n), n: int n, keys: !$A.borrow(byte, lk, 65536), off: pos_t, i: int i): void =
  if i >= n then ()
  else let
    val () = $A.set<byte>(a, i, $A.int2byte($AR.low_byte(peek(keys, off + i, 65536))))
  in fill_key(a, n, keys, off, i + 1) end

(* Rust's "in [dependencies] '<name>': <why>" appended to err when not
   ok; consumes why *)
fn put_why {lp:agz}
  (ok: bool, p: !$A.arr(byte, lp, 256), pk: int, why: $B.builder_v,
   err: !$B.builder_v >> $B.builder_v): void =
  if ok then let
    val () = $B.builder_free(why)
  in bput_v(err, "") end
  else let
    val @(wa, wl) = $B.to_arr(why)
    val @(fz_w, bv_w) = $A.freeze<byte>(wa)
    val () = bput_v(err, "in [dependencies] '")
    val () = put_name(p, pk, err)
    val () = bput_v(err, "': ")
    val () = copy_to_builder_v(bv_w, 0, wl, 524288, err)
    val () = $A.drop<byte>(fz_w, bv_w)
  in $A.free<byte>($A.thaw<byte>(fz_w)) end

(* Appends the constraints of each key in the NUL-separated list
   keys[off, len) of doc's [dependencies] (sec) to acc, from src[0, sk),
   and counts in paths the path dependencies ({ path = ... }, whose
   value this toml keeps as written): @(true, them, the count), or
   @(false, ...) after writing Rust's message to err *)
fun load_keys {lk,ls,lsec:agz}{n:nat}{f:nat} .<f>.
  (doc: !$T.toml_doc, sec: !$A.borrow(byte, lsec, 12),
   keys: !$A.borrow(byte, lk, 65536), off: pos_t, len: int,
   src: !$A.arr(byte, ls, 256), sk: int,
   acc: cons(n), paths: int, err: !$B.builder_v >> $B.builder_v, f: int f)
  : [m:nat] @(bool, cons(m), int) =
  if f <= 0 then @(true, acc, paths)
  else if off >= len then @(true, acc, paths)
  else let
    val z = find_null_bv_from(keys, off, 65536)
    val kl = z - off
  in
    if kl <= 0 then load_keys(doc, sec, keys, z + 1, len, src, sk, acc, paths, err, f - 1)
    else if kl > 65536 then @(true, acc, paths)
    else let
      val ka = $A.alloc<byte>(kl)
      val () = fill_key(ka, kl, keys, off, 0)
      val @(fz_k, bv_k) = $A.freeze<byte>(ka)
      val vb = $A.alloc<byte>(4096)
      val vr = $T.get(doc, sec, 12, bv_k, kl, vb, 4096)
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val vl = (case+ vr of | ~$R.some(x) => x | ~$R.none() => 0): [v:nat] int v
      val p = $A.alloc<byte>(256)
      val pk = copy_name(keys, off, z, 65536, p, 0)
      val @(fz_v, bv_v) = $A.freeze<byte>(vb)
      (* An inline table: Rust's DepValue::Path, not a constraint *)
      val is_path = (if vl > 0 then peek(bv_v, 0, 4096) = 123 else false): bool
      var why : $B.builder_v = $B.create()
      val @(ok, acc2) = parse_cons(bv_v, 0, (if is_path then 0 else vl): pos_t, p, pk, src, sk, acc, why, 4096)
      val () = $A.drop<byte>(fz_v, bv_v)
      val () = $A.free<byte>($A.thaw<byte>(fz_v))
      val () = put_why(ok, p, pk, why, err)
      val () = $A.free<byte>(p)
      val paths2 = (if is_path then paths + 1 else paths): int
    in
      if ok then load_keys(doc, sec, keys, z + 1, len, src, sk, acc2, paths2, err, f - 1)
      else @(false, acc2, paths2)
    end
  end

(* The constraints of doc's [dependencies], from src[0, sk), and the
   number of its path dependencies (Rust: config::load's dependencies):
   @(1, them, the number), or @(~1, none, 0) after writing Rust's
   "in [dependencies] '<name>': ..." to err *)
fn doc_cons {ls:agz}
  (doc: !$T.toml_doc, src: !$A.arr(byte, ls, 256), sk: int,
   err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n), int) = let
  var sec_c = @[char][12]('d', 'e', 'p', 'e', 'n', 'd', 'e', 'n', 'c', 'i', 'e', 's')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 12))
  val kb = $A.alloc<byte>(65536)
  val kr = $T.keys(doc, bv_s, 12, kb, 65536)
  val kl = (case+ kr of | ~$R.some(x) => x | ~$R.none() => 0): int
  val @(fz_kb, bv_kb) = $A.freeze<byte>(kb)
  val @(ok, cs, paths) = load_keys(doc, bv_s, bv_kb, 0, kl, src, sk, cons_nil(), 0, err, 65536)
  val () = $A.drop<byte>(fz_kb, bv_kb)
  val () = $A.free<byte>($A.thaw<byte>(fz_kb))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in
  if ok then @(1, cs, paths)
  else let
    val () = cons_free(cs)
  in @(~1, cons_nil(), 0) end
end

(* Rust's "unknown package kind: '<v[0, vl)>'" appended to err when
   bad *)
fn put_unknown_kind {lv:agz}
  (bad: bool, v: !$A.borrow(byte, lv, 256), vl: int, err: !$B.builder_v >> $B.builder_v): void =
  if bad then let
    val () = bput_v(err, "unknown package kind: '")
    val () = copy_to_builder_v(v, 0, vl, 256, err)
  in bput_v(err, "'") end
  else bput_v(err, "")

(* [package] kind (Rust: config::load): 1 for lib, which is the
   default, 2 for bin, or ~1 after Rust's "unknown package kind: '<k>'"
   in err *)
fn doc_kind (doc: !$T.toml_doc, err: !$B.builder_v >> $B.builder_v): int = let
  var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
  var key_c = @[char][4]('k', 'i', 'n', 'd')
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 4))
  val vb = $A.alloc<byte>(256)
  val vl = (case+ $T.get(doc, bv_s, 7, bv_k, 4, vb, 256) of
    | ~$R.some(x) => x | ~$R.none() => ~1): int
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
  val @(fz_v, bv_v) = $A.freeze<byte>(vb)
  var lib_c = @[char][3]('l', 'i', 'b')
  var bin_c = @[char][3]('b', 'i', 'n')
  val kind = (if vl < 0 then 1
              else if vl <> 3 then ~1
              else if lit_at(bv_v, 0, 256, lib_c, 3) then 1
              else if lit_at(bv_v, 0, 256, bin_c, 3) then 2
              else ~1): int
  val () = put_unknown_kind(kind < 0, bv_v, vl, err)
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
in kind end

(* The constraints of doc (Rust: config::load), from src[0, sk):
   @(1, them), or @(~1, none) after writing Rust's message to err: an
   unknown kind, a constraint that does not parse, or a path dependency
   in a lib package, in that order *)
fn config_cons {ls:agz}
  (doc: !$T.toml_doc, src: !$A.arr(byte, ls, 256), sk: int,
   err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n)) = let
  val kind = doc_kind(doc, err)
in
  if kind < 0 then @(~1, cons_nil())
  else let
    val @(st, cs, paths) = doc_cons(doc, src, sk, err)
  in
    if st < 0 then @(~1, cs)
    else if kind = 1 then
      (if paths > 0 then let
         val () = cons_free(cs)
         val () = bput_v(err, "path dependencies are only supported in binary packages (kind = \"bin\")")
       in @(~1, cons_nil()) end
       else @(1, cs))
    else @(1, cs)
  end
end

(* The TOML file at the NUL-terminated path pa, parsed, or the errno
   of why it could not be read *)
fn read_toml {lp:agz} (pa: $A.arr(byte, lp, 524288)): $R.result($T.toml_doc, int) = let
  val @(fz, bv) = $A.freeze<byte>(pa)
  val fr = $F.file_open(bv, 524288, 0, 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ fr of
  | ~$R.err(e) => $R.err(e)
  | ~$R.ok(fd) => let
      val tb = $A.alloc<byte>(65536)
      val rr = $F.file_read(fd, tb, 65536)
      val () = $R.discard<int><int>($F.file_close(fd))
      val e = (case+ rr of | ~$R.ok(_) => 0 | ~$R.err(e) => e): int
      val @(fz_t, bv_t) = $A.freeze<byte>(tb)
      val pr = $T.parse(bv_t, 65536)
      val () = $A.drop<byte>(fz_t, bv_t)
      val () = $A.free<byte>($A.thaw<byte>(fz_t))
    in
      case+ pr of
      | ~$R.ok(doc) =>
        if e = 0 then $R.ok(doc)
        else let
          val () = $T.toml_free(doc)
        in $R.err(e) end
      | ~$R.err(_) => $R.err(e)
    end
end

(* Rust's "cannot read './bats.toml': <text> (os error <e>)" appended
   to err (config::load, io::Error's Display) *)
fn put_cannot_read (e: int, err: !$B.builder_v >> $B.builder_v): void = let
  val buf = $A.alloc<byte>(256)
  val k = $P.os_error_text(e, buf, 256)
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val () = bput_v(err, "cannot read './bats.toml': ")
  val () = copy_to_builder_v(bv_b, 0, k, 256, err)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
  val () = bput_v(err, " (os error ")
  val () = bput_int_v(err, e)
in bput_v(err, ")") end

(* The constraints of the project's bats.toml, from its [package] name:
   @(1, them), or @(~1, none) after writing Rust's message to err, as
   when bats.toml cannot be read (Rust: cmd_lock's config::load) *)
fn project_cons (err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n)) =
  case+ read_toml(str_to_path_arr("bats.toml")) of
  | ~$R.err(e) => let
      val () = put_cannot_read(e, err)
    in @(~1, cons_nil()) end
  | ~$R.ok(doc) => let
      var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
      val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
      var key_c = @[char][4]('n', 'a', 'm', 'e')
      val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 4))
      val nb = $A.alloc<byte>(256)
      (* Rust requires the name; without one config::load fails first *)
      val nk = (case+ $T.get(doc, bv_s, 7, bv_k, 4, nb, 256) of
        | ~$R.some(x) => x | ~$R.none() => 0): int
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
      val r = config_cons(doc, nb, nk, err)
      val () = $A.free<byte>(nb)
      val () = $T.toml_free(doc)
    in r end

(* The constraints of the bats.toml of the fetched package a[0, k); none
   when it cannot be read or does not parse, as Rust ignores a dependency
   whose config::load fails *)
fn dep_cons {la:agz} (a: !$A.arr(byte, la, 256), k: int): [n:nat] cons(n) = let
  var p : $B.builder_v = $B.create()
  val () = bput_v(p, "bats_modules/")
  val () = put_name(a, k, p)
  val () = bput_v(p, "/bats.toml")
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in
  case+ read_toml(pa) of
  | ~$R.err(_) => cons_nil()
  | ~$R.ok(doc) => let
      var err : $B.builder_v = $B.create()
      val @(st, cs) = config_cons(doc, a, k, err)
      val () = $B.builder_free(err)
      val () = $T.toml_free(doc)
    in
      if st > 0 then cs
      else let
        val () = cons_free(cs)
      in cons_nil() end
    end
end

(* Rust's "no version of '<name>' satisfies all constraints: ..." *)
fn unsatisfied {n:nat}{la:agz} (cs: !cons(n), a: !$A.arr(byte, la, 256), k: int): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: no version of '")
  val () = put_name(a, k, m)
  val () = bput_v(m, "' satisfies all constraints: ")
  val () = put_cons_of(cs, a, k, false, m)
  val () = put_char_v(m, 10)
in prerr_builder(m) end

(* Whether the file name e[0, el) is <pfx><version>.bats *)
fn is_archive_of {le,lp:agz}
  (e: !$A.borrow(byte, le, 256), el: pos_t,
   pfx: !$A.borrow(byte, lp, 524288), pl: pos_t): bool = let
  var b_c = @[char][5]('.', 'b', 'a', 't', 's')
  fun starts {f:nat} .<f>.
    (e: !$A.borrow(byte, le, 256), pfx: !$A.borrow(byte, lp, 524288),
     i: pos_t, pl: pos_t, f: int f): bool =
    if f <= 0 then false
    else if i >= pl then true
    else if $AR.eq_int_int(peek(e, i, 256), peek(pfx, i, 524288))
    then starts(e, pfx, i + 1, pl, f - 1)
    else false
in
  if el < pl + 6 then false
  else if ~lit_at(e, el - 5, 256, b_c, 5) then false
  else starts(e, pfx, 0, pl, 256)
end

(* The newest version among the archives in the directory d whose names
   start with pfx[0, pl) that meets the constraints cs on the package
   a[0, k); dev versions only when dev *)
fun scan_versions {lp,la:agz}{nc:nat}{fuel:nat} .<fuel>.
  (d: !$F.dir, pfx: !$A.borrow(byte, lp, 524288), pl: pos_t, dev: bool,
   cs: !cons(nc), a: !$A.arr(byte, la, 256), k: int,
   best: $R.option(cand), fuel: int fuel): $R.option(cand) =
  if fuel <= 0 then best
  else let
    val e = $A.alloc<byte>(256)
    val el = dir_name_len($F.dir_next(d, e, 256))
  in
    if el < 0 then let
      val () = $A.free<byte>(e)
    in best end
    else let
      val @(fz_e, bv_e) = $A.freeze<byte>(e)
      val c = (if is_archive_of(bv_e, el, pfx, pl)
               then file_cand(bv_e, pl, el - 5) else $R.none()): $R.option(cand)
      val () = $A.drop<byte>(fz_e, bv_e)
      val () = $A.free<byte>($A.thaw<byte>(fz_e))
      val best2 = (case+ c of
        | ~$R.some(cv) =>
          if cand_dev(cv) && ~dev then let
            val () = cand_free(cv)
          in best end
          else if ~cons_allow(cs, a, k, cv) then let
            val () = cand_free(cv)
          in best end
          else keep_newer(best, cv)
        | ~$R.none() => best): $R.option(cand)
    in scan_versions(d, pfx, pl, dev, cs, a, k, best2, fuel - 1) end
  end

(* The name a[0, k) with '/' made '_', then '_' (Rust: package_to_prefix) *)
fun put_prefix {la:agz}{f:nat} .<f>.
  (a: !$A.arr(byte, la, 256), i: pos_t, k: int, out: !$B.builder_v >> $B.builder_v, f: int f): void =
  if f <= 0 then ()
  else if i >= k then put_char_v(out, 95)
  else let
    val c = peek256(a, i)
    val () = put_char_v(out, (if c = 47 then 95 else c): int)
  in put_prefix(a, i + 1, k, out, f - 1) end

(* repo[0, rl) / name *)
fn put_pkg_dir {lr,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: int,
   out: !$B.builder_v >> $B.builder_v): void = let
  val () = copy_to_builder_v(repo, 0, rl, 4096, out)
  val () = put_char_v(out, 47)
in put_name(a, k, out) end

(* The newest version of the package a[0, k) in the repository that meets
   the constraints cs (Rust: find_latest_version) *)
fn find_latest {lr,la:agz}{nc:nat}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: int,
   dev: bool, cs: !cons(nc)): $R.option(cand) = let
  var dp : $B.builder_v = $B.create()
  val () = put_pkg_dir(repo, rl, a, k, dp)
  val () = put_char_v(dp, 0)
  val @(da, _) = $B.to_arr(dp)
  val @(fz_d, bv_d) = $A.freeze<byte>(da)
  val dr = $F.dir_open(bv_d, 524288)
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
  var pb : $B.builder_v = $B.create()
  val () = put_prefix(a, 0, k, pb, 256)
  val pl = $B.length(pb)
  val @(pa, _) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val r = (case+ dr of
    | ~$R.ok(d) => let
        val best = scan_versions(d, bv_p, pl, dev, cs, a, k, $R.none(), 65536)
        val () = $R.discard<int><int>($F.dir_close(d))
      in best end
    | ~$R.err(_) => $R.none()): $R.option(cand)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in r end

(* ============================================================
   Resolving (Rust: resolve_all, fetch_package, generate)
   ============================================================ *)

(* dst[i, k) = src[i, k) *)
fun copy_arr_name {la,lb:agz}{k:nat | k <= 256}{i:nat | i <= k} .<k - i>.
  (src: !$A.arr(byte, la, 256), dst: !$A.arr(byte, lb, 256), k: int k, i: int i): void =
  if i >= k then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in copy_arr_name(src, dst, k, i + 1) end

(* A copy of xs *)
fun names_copy {n:nat} .<n>. (xs: !names(n)): names(n) =
  case+ xs of
  | names_nil() => names_nil()
  | @names_cons(a, k, rest) => let
      val b = $A.alloc<byte>(256)
      val () = copy_arr_name(a, b, k, 0)
      val kk = k
      val rest2 = names_copy(rest)
      prval () = fold@(xs)
    in names_cons(b, kk, rest2) end

(* The names of ts not in all, added to all and to the front of stack in
   ts's order, so the newest of them is resolved next (Rust: the
   queue.push of each transitive package) *)
fun push_new {t,s,m:nat} .<t>.
  (ts: names(t), stack: names(s), all: names(m)): [s2,m2:nat] @(names(s2), names(m2)) =
  case+ ts of
  | ~names_nil() => @(stack, all)
  | ~names_cons(a, k, rest) =>
    if names_has(all, a, k) then let
      val () = $A.free<byte>(a)
    in push_new(rest, stack, all) end
    else let
      val b = $A.alloc<byte>(256)
      val () = copy_arr_name(a, b, k, 0)
      val @(stack2, all2) = push_new(rest, stack, names_cons(b, k, all))
    in @(names_cons(a, k, stack2), all2) end

(* The archive of version v of a[0, k): repo/<name>/<prefix><v>.bats,
   NUL-terminated, and its length without the NUL *)
fn archive_path {lr,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: int,
   v: !cand): @([lo:agz] $A.arr(byte, lo, 524288), int) = let
  var p : $B.builder_v = $B.create()
  val () = put_pkg_dir(repo, rl, a, k, p)
  val () = put_char_v(p, 47)
  val () = put_prefix(a, 0, k, p, 256)
  val () = put_cand(v, p)
  val () = bput_v(p, ".bats")
  val plen = $B.length(p)
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in @(pa, plen) end

(* Whether bats_modules/<name>/src/lib.bats exists *)
fn is_fetched {la:agz} (a: !$A.arr(byte, la, 256), k: int): bool = let
  var p : $B.builder_v = $B.create()
  val () = bput_v(p, "bats_modules/")
  val () = put_name(a, k, p)
  val () = bput_v(p, "/src/lib.bats")
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_exists(bv, 524288)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* m to stderr unless quiet; consumes m *)
fn say (m: $B.builder_v): void =
  if is_quiet() then $B.builder_free(m) else prerr_builder(m)

(* Unpacks the archive arc[0, alen) into bats_modules/<name> and says so
   (Rust: fetch_package) *)
fn fetch {lc,la:agz}
  (arc: !$A.borrow(byte, lc, 524288), alen: int,
   a: !$A.arr(byte, la, 256), k: int, v: !cand): void = let
  var md : $B.builder_v = $B.create()
  val () = bput_v(md, "bats_modules/")
  val () = put_name(a, k, md)
  val _ = run_mkdir(md)
  val uz = str_to_path_arr("unzip")
  val @(fz_uz, bv_uz) = $A.freeze<byte>(uz)
  var u1 = $B.create()
  val () = bput_v(u1, "unzip")
  var u2 = $B.create()
  val () = bput_v(u2, "-o")
  var u3 = $B.create()
  val () = bput_v(u3, "-q")
  var u4 = $B.create()
  val () = copy_to_builder_v(arc, 0, alen, 524288, u4)
  var u5 = $B.create()
  val () = bput_v(u5, "-d")
  var u6 = $B.create()
  val () = bput_v(u6, "bats_modules/")
  val () = put_name(a, k, u6)
  val _ = run_cmd(bv_uz, $L.list_vt_cons(mk_arg(u1), $L.list_vt_cons(mk_arg(u2),
    $L.list_vt_cons(mk_arg(u3), $L.list_vt_cons(mk_arg(u4), $L.list_vt_cons(mk_arg(u5),
    $L.list_vt_cons(mk_arg(u6), $L.list_vt_nil())))))))
  val () = $A.drop<byte>(fz_uz, bv_uz)
  val () = $A.free<byte>($A.thaw<byte>(fz_uz))
  var msg : $B.builder_v = $B.create()
  val () = bput_v(msg, "fetched ")
  val () = put_name(a, k, msg)
  val () = bput_v(msg, " v")
  val () = put_cand(v, msg)
  val () = put_char_v(msg, 10)
in say(msg) end

(* The #use packages of bats_modules/<name>/src, newest first *)
fn dep_uses {la:agz} (a: !$A.arr(byte, la, 256), k: int): [m:nat] names(m) = let
  var d : $B.builder_v = $B.create()
  val () = bput_v(d, "bats_modules/")
  val () = put_name(a, k, d)
  val () = bput_v(d, "/src")
in collect_uses(d) end

(* Rust's "package '<name>' not found in repository '<repo>'" *)
fn not_found {lr,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: int): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: package '")
  val () = put_name(a, k, m)
  val () = bput_v(m, "' not found in repository '")
  val () = copy_to_builder_v(repo, 0, rl, 4096, m)
  val () = bput_v(m, "'\n")
in prerr_builder(m) end

(* Rust's "cannot read '<archive>'" *)
fn cannot_read {lc:agz} (arc: !$A.borrow(byte, lc, 524288), alen: int): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: cannot read '")
  val () = copy_to_builder_v(arc, 0, alen, 524288, m)
  val () = bput_v(m, "'\n")
in prerr_builder(m) end

(* The lock line of the package a[0, k) at version v, whose archive is
   arc: "<name> <version> <sha256>\n"; false when the archive cannot be
   read *)
fn put_lock_line {lc,la:agz}
  (arc: !$A.borrow(byte, lc, 524288), a: !$A.arr(byte, la, 256), k: int, v: !cand,
   lock: !$B.builder_v >> $B.builder_v): bool = let
  val () = put_name(a, k, lock)
  val () = put_char_v(lock, 32)
  val () = put_cand(v, lock)
  val () = put_char_v(lock, 32)
  val ok = put_file_sha256(arc, lock)
  val () = put_char_v(lock, 10)
in ok end

(* not_found, or unsatisfied when a constraint is on the package a[0, k)
   (Rust: resolve_all's map_err) *)
fn no_version {lr,la:agz}{nc:nat}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: int,
   cs: !cons(nc)): void =
  if cons_about(cs, a, k) then unsatisfied(cs, a, k) else not_found(repo, rl, a, k)

(* Resolves the packages on stack, the newest first, into lock lines,
   skipping the path dependencies pn; all holds every package queued so
   far, cs the constraints read so far.
   @(0 or ~1 on an error, the number resolved) (Rust: resolve_all) *)
fun resolve_all {s,m,nc,np:nat}{lr:agz}{f:nat} .<f>.
  (stack: names(s), all: names(m), cs: cons(nc), pn: !names(np),
   repo: !$A.borrow(byte, lr, 4096), rl: int,
   dev: bool, lock: !$B.builder_v >> $B.builder_v, count: int, f: int f): @(int, int) =
  if f <= 0 then let
    val () = names_free(stack)
    val () = names_free(all)
    val () = cons_free(cs)
  in @(0, count) end
  else case+ stack of
  | ~names_nil() => let
      val () = names_free(all)
      val () = cons_free(cs)
    in @(0, count) end
  | ~names_cons(a, k, rest) =>
    (* A path dependency is not resolved from the repository *)
    if names_has(pn, a, k) then let
      val () = $A.free<byte>(a)
    in resolve_all(rest, all, cs, pn, repo, rl, dev, lock, count, f - 1) end
    else let
      val latest = find_latest(repo, rl, a, k, dev, cs)
    in
      case+ latest of
      | ~$R.none() => let
          val () = no_version(repo, rl, a, k, cs)
          val () = $A.free<byte>(a)
          val () = names_free(rest)
          val () = names_free(all)
          val () = cons_free(cs)
        in @(~1, count) end
      | ~$R.some(v) => let
          val @(arc, alen) = archive_path(repo, rl, a, k, v)
          val @(fz_c, bv_c) = $A.freeze<byte>(arc)
          val () = (if is_fetched(a, k) then () else fetch(bv_c, alen, a, k, v))
          val cs2 = cons_append(cs, dep_cons(a, k))
          val ts = dep_uses(a, k)
          val ok = put_lock_line(bv_c, a, k, v, lock)
          val () = (if ok then () else cannot_read(bv_c, alen))
          val () = $A.drop<byte>(fz_c, bv_c)
          val () = $A.free<byte>($A.thaw<byte>(fz_c))
          val () = cand_free(v)
          val @(stack2, all2) = push_new(ts, rest, all)
          val () = $A.free<byte>(a)
        in
          if ok then resolve_all(stack2, all2, cs2, pn, repo, rl, dev, lock, count + 1, f - 1)
          else let
            val () = names_free(stack2)
            val () = names_free(all2)
            val () = cons_free(cs2)
          in @(~1, count) end
        end
    end

(* ============================================================
   bats lock --dry-run (Rust: read_lockfile, print_diff)
   ============================================================ *)

(* Lock text: bats.lock's bytes or the lines resolve_all wrote *)
#define LOCK_MAX 524288

(* The next line of t after i: @(its trimmed [start, end), where it
   ends) (Rust: lines() and trim()) *)
fn lock_line {lt:agz}
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: pos_t, i: pos_t): @(pos_t, pos_t, pos_t) = let
  val le = find_byte(t, LOCK_MAX, i, tl, 10, LOCK_MAX)
  val ts = skip_space(t, LOCK_MAX, i, le, LOCK_MAX)
  val te = trim_end(t, LOCK_MAX, ts, le, LOCK_MAX)
in @(ts, te, le) end

(* The ends of the package and of the version of the lock line t[s, e):
   the package ends at the first space, the version at the next one or
   at e (Rust: splitn(3, ' ')); a line without a space has no version *)
fn lock_fields {lt:agz}
  (t: !$A.borrow(byte, lt, LOCK_MAX), s: pos_t, e: pos_t): @(pos_t, pos_t) = let
  val pe = find_byte(t, LOCK_MAX, s, e, 32, LOCK_MAX)
  val ve = (if pe < e then find_byte(t, LOCK_MAX, pe + 1, e, 32, LOCK_MAX) else e): pos_t
in @(pe, ve) end

(* Whether a[i, i + k) = b[j, j + k) *)
fun lock_bytes_eq {la,lb:agz}{f:nat} .<f>.
  (a: !$A.borrow(byte, la, LOCK_MAX), i: pos_t, b: !$A.borrow(byte, lb, LOCK_MAX), j: pos_t,
   k: int, f: int f): bool =
  if f <= 0 then true
  else if k <= 0 then true
  else if peek(a, i, LOCK_MAX) <> peek(b, j, LOCK_MAX) then false
  else lock_bytes_eq(a, i + 1, b, j + 1, k - 1, f - 1)

(* Whether a[a0, a1) = b[b0, b1) *)
fn lock_range_eq {la,lb:agz}
  (a: !$A.borrow(byte, la, LOCK_MAX), a0: pos_t, a1: pos_t,
   b: !$A.borrow(byte, lb, LOCK_MAX), b0: pos_t, b1: pos_t): bool =
  if a1 - a0 <> b1 - b0 then false
  else lock_bytes_eq(a, a0, b, b0, a1 - a0, LOCK_MAX)

(* The version of the first line of t[i, tl) whose package is
   u[xs, xe), or @(~1, ~1) *)
fun lock_find {lt,lu:agz}{f:nat} .<f>.
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: pos_t, i: pos_t,
   u: !$A.borrow(byte, lu, LOCK_MAX), xs: pos_t, xe: pos_t, f: int f): @(pos_t, pos_t) =
  if f <= 0 then @(~1, ~1)
  else if i >= tl then @(~1, ~1)
  else let
    val @(ts, te, le) = lock_line(t, tl, i)
  in
    if ts >= te then lock_find(t, tl, le + 1, u, xs, xe, f - 1)
    else let
      val @(pe, ve) = lock_fields(t, ts, te)
    in
      if pe < te then
        (if lock_range_eq(t, ts, pe, u, xs, xe) then @(pe + 1, ve)
         else lock_find(t, tl, le + 1, u, xs, xe, f - 1))
      else lock_find(t, tl, le + 1, u, xs, xe, f - 1)
    end
  end

(* The first line of t[i, tl) without a space, trimmed, or @(~1, ~1)
   (Rust: read_lockfile's "malformed lockfile line") *)
fun lock_malformed {lt:agz}{f:nat} .<f>.
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: pos_t, i: pos_t, f: int f): @(pos_t, pos_t) =
  if f <= 0 then @(~1, ~1)
  else if i >= tl then @(~1, ~1)
  else let
    val @(ts, te, le) = lock_line(t, tl, i)
  in
    if ts >= te then lock_malformed(t, tl, le + 1, f - 1)
    else let
      val @(pe, _) = lock_fields(t, ts, te)
    in
      if pe >= te then @(ts, te)
      else lock_malformed(t, tl, le + 1, f - 1)
    end
  end

(* "  + <pkg> v<new>" or "  ~ <pkg> v<old> -> v<new>" for the new lock
   line u[s, e) against old[0, ol); whether it wrote one *)
fn note_new {lu,lo:agz}
  (u: !$A.borrow(byte, lu, LOCK_MAX), s: pos_t, e: pos_t,
   old: !$A.borrow(byte, lo, LOCK_MAX), ol: pos_t,
   out: !$B.builder_v >> $B.builder_v): bool = let
  val @(pe, ve) = lock_fields(u, s, e)
  val @(os, oe) = lock_find(old, ol, 0, u, s, pe, LOCK_MAX)
in
  if os < 0 then let
    val () = bput_v(out, "  + ")
    val () = copy_to_builder_v(u, s, pe, LOCK_MAX, out)
    val () = bput_v(out, " v")
    val () = copy_to_builder_v(u, pe + 1, ve, LOCK_MAX, out)
    val () = put_char_v(out, 10)
  in true end
  else if lock_range_eq(old, os, oe, u, pe + 1, ve) then let
    val () = bput_v(out, "")
  in false end
  else let
    val () = bput_v(out, "  ~ ")
    val () = copy_to_builder_v(u, s, pe, LOCK_MAX, out)
    val () = bput_v(out, " v")
    val () = copy_to_builder_v(old, os, oe, LOCK_MAX, out)
    val () = bput_v(out, " -> v")
    val () = copy_to_builder_v(u, pe + 1, ve, LOCK_MAX, out)
    val () = put_char_v(out, 10)
  in true end
end

(* "  - <pkg> v<old>" for the old lock line o[s, e) when new[0, nl) has
   no line for its package; whether it wrote one *)
fn note_old {lo,ln:agz}
  (o: !$A.borrow(byte, lo, LOCK_MAX), s: pos_t, e: pos_t,
   nw: !$A.borrow(byte, ln, LOCK_MAX), nl: pos_t,
   out: !$B.builder_v >> $B.builder_v): bool = let
  val @(pe, ve) = lock_fields(o, s, e)
  val @(ns, _) = lock_find(nw, nl, 0, o, s, pe, LOCK_MAX)
in
  if ns >= 0 then let
    val () = bput_v(out, "")
  in false end
  else let
    val () = bput_v(out, "  - ")
    val () = copy_to_builder_v(o, s, pe, LOCK_MAX, out)
    val () = bput_v(out, " v")
    val () = copy_to_builder_v(o, pe + 1, ve, LOCK_MAX, out)
    val () = put_char_v(out, 10)
  in true end
end

(* note_new or note_old for the trimmed line a[s, e), when not empty *)
fn note_line {la,lb:agz}
  (a: !$A.borrow(byte, la, LOCK_MAX), s: pos_t, e: pos_t,
   b: !$A.borrow(byte, lb, LOCK_MAX), bl: pos_t, fresh: bool,
   out: !$B.builder_v >> $B.builder_v): bool =
  if s >= e then let
    val () = bput_v(out, "")
  in false end
  else if fresh then note_new(a, s, e, b, bl, out)
  else note_old(a, s, e, b, bl, out)

(* Notes each line of a[i, al) against b[0, bl): the new lines with
   note_new when fresh, the old ones with note_old; whether any note
   was written *)
fun lock_notes {la,lb:agz}{f:nat} .<f>.
  (a: !$A.borrow(byte, la, LOCK_MAX), al: pos_t, i: pos_t,
   b: !$A.borrow(byte, lb, LOCK_MAX), bl: pos_t, fresh: bool, changed: bool,
   out: !$B.builder_v >> $B.builder_v, f: int f): bool =
  if f <= 0 then changed
  else if i >= al then changed
  else let
    val @(ts, te, le) = lock_line(a, al, i)
    val c = note_line(a, ts, te, b, bl, fresh, out)
  in lock_notes(a, al, le + 1, b, bl, fresh, (if c then true else changed): bool, out, f - 1) end

(* bats.lock's bytes and their count; none when there is no bats.lock *)
fn read_old_lock (): @([l:agz] $A.arr(byte, l, LOCK_MAX), pos_t) = let
  val lp = str_to_path_arr("bats.lock")
  val @(fz_lp, bv_lp) = $A.freeze<byte>(lp)
  val fr = $F.file_open(bv_lp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_lp, bv_lp)
  val () = $A.free<byte>($A.thaw<byte>(fz_lp))
  val buf = $A.alloc<byte>(LOCK_MAX)
in
  case+ fr of
  | ~$R.err(_) => @(buf, 0)
  | ~$R.ok(fd) => let
      val n = (case+ $F.file_read(fd, buf, LOCK_MAX) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): pos_t
      val () = $R.discard<int><int>($F.file_close(fd))
    in @(buf, n) end
end

(* Prints out: an error when bad (a malformed bats.lock), otherwise the
   diff unless quiet, then Rust's "lockfile is stale" when stale;
   consumes out *)
fn report_dry (bad: bool, stale: bool, out: $B.builder_v): void =
  if bad then let
    val () = prerr_builder(out)
  in set_build_err() end
  else let
    val () = say(out)
  in
    if stale then let
      val () = prerr! ("error: lockfile is stale\n")
    in set_build_err() end
    else ()
  end

(* Compares the resolved lock with bats.lock instead of writing it
   (Rust: generate with dry_run, print_diff); consumes lock *)
fn dry_run_lock (lock: $B.builder_v): void = let
  var nb : $B.builder_v = lock
  val nl = $B.length(nb)
  val @(na, _) = $B.to_arr(nb)
  val @(fz_n, bv_n) = $A.freeze<byte>(na)
  val @(oa, ol) = read_old_lock()
  val @(fz_o, bv_o) = $A.freeze<byte>(oa)
  val @(ms, me) = lock_malformed(bv_o, ol, 0, LOCK_MAX)
  var out : $B.builder_v = $B.create()
  val stale = (if ms >= 0 then let
      val () = bput_v(out, "error: malformed lockfile line: ")
      val () = copy_to_builder_v(bv_o, ms, me, LOCK_MAX, out)
      val () = put_char_v(out, 10)
    in true end
    else let
      val c1 = lock_notes(bv_n, nl, 0, bv_o, ol, true, false, out, LOCK_MAX)
      val c2 = lock_notes(bv_o, ol, 0, bv_n, nl, false, c1, out, LOCK_MAX)
      val () = (if c2 then bput_v(out, "") else bput_v(out, "no changes\n"))
    in c2 end): bool
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
in
  report_dry(ms >= 0, stale, out)
end

(* Writes lock to bats.lock and reports it, when st says resolving
   succeeded, or compares it with bats.lock when dry (Rust: generate);
   consumes lock *)
fn finish_lock (st: int, n: int, lock: $B.builder_v, dry: bool): void =
  if st < 0 then let
    val () = $B.builder_free(lock)
  in set_build_err() end
  else if dry then dry_run_lock(lock)
  else let
    val lp = str_to_path_arr("bats.lock")
    val @(fz_lp, bv_lp) = $A.freeze<byte>(lp)
    val _ = write_file_from_builder(bv_lp, 524288, lock)
    val () = $A.drop<byte>(fz_lp, bv_lp)
    val () = $A.free<byte>($A.thaw<byte>(fz_lp))
  in
    if is_quiet() then ()
    else if n = 0 then prerr! ("wrote bats.lock (no dependencies)\n")
    else prerr! ("wrote bats.lock (", n, " dependencies)\n")
  end

(* ============================================================
   Path dependencies (Rust: config's DepValue::Path, resolve_all)
   ============================================================ *)

(* The path dependencies of the project, in [dependencies] order: each
   name[0, k) and its directory path[0, pl) *)
datavtype pdeps(int) =
  | pd_nil(0) of ()
  | {ln,lp:agz}{k:pos | k <= 256}{n:nat}
    pd_cons(n + 1) of ($A.arr(byte, ln, 256), int k, $A.arr(byte, lp, 256), int, pdeps(n))

fun pdeps_free {n:nat} .<n>. (ds: pdeps(n)): void =
  case+ ds of
  | ~pd_nil() => ()
  | ~pd_cons(a, _, p, _, rest) => let
      val () = $A.free<byte>(a)
      val () = $A.free<byte>(p)
    in pdeps_free(rest) end

(* The names of ds *)
fun pdeps_names {n:nat} .<n>. (ds: !pdeps(n)): names(n) =
  case+ ds of
  | pd_nil() => names_nil()
  | @pd_cons(a, k, _, _, rest) => let
      val b = $A.alloc<byte>(256)
      val () = copy_arr_name(a, b, k, 0)
      val kk = k
      val r = pdeps_names(rest)
      prval () = fold@(ds)
    in names_cons(b, kk, r) end

(* The path of the inline table v[0, vl) = { path = "<path>" }, as
   [start, end), or @(~1, ~1) *)
fn path_value {lv:agz} (v: !$A.borrow(byte, lv, 4096), vl: pos_t): @(pos_t, pos_t) = let
  var path_c = @[char][4]('p', 'a', 't', 'h')
  val i0 = skip_space(v, 4096, 1, vl, 4096)
  val quoted = peek(v, i0, 4096) = 34
  val ks = (if quoted then i0 + 1 else i0): pos_t
  val key_ok = lit_at(v, ks, 4096, path_c, 4) &&
    (if quoted then peek(v, ks + 4, 4096) = 34 else true)
  val ke = (if quoted then ks + 5 else ks + 4): pos_t
  val i1 = skip_space(v, 4096, ke, vl, 4096)
  val i2 = skip_space(v, 4096, i1 + 1, vl, 4096)
  val qs = i2 + 1
  val qe = find_byte(v, 4096, qs, vl, 34, 4096)
in
  if ~key_ok then @(~1, ~1)
  else if peek(v, i1, 4096) <> 61 then @(~1, ~1)
  else if peek(v, i2, 4096) <> 34 then @(~1, ~1)
  else if qe >= vl then @(~1, ~1)
  else @(qs, qe)
end

(* v[ps, pe) copied into pa when ps >= 0; its length *)
fn copy_path {lv,lp:agz}
  (v: !$A.borrow(byte, lv, 4096), ps: pos_t, pe: pos_t, pa: !$A.arr(byte, lp, 256)): int =
  if ps >= 0 then copy_name(v, ps, pe, 4096, pa, 0) else 0

(* The path dependencies among the keys keys[off, len) of doc's
   [dependencies] (sec), in order *)
fun path_keys {lk,lsec:agz}{f:nat} .<f>.
  (doc: !$T.toml_doc, sec: !$A.borrow(byte, lsec, 12),
   keys: !$A.borrow(byte, lk, 65536), off: pos_t, len: int, f: int f): [n:nat] pdeps(n) =
  if f <= 0 then pd_nil()
  else if off >= len then pd_nil()
  else let
    val z = find_null_bv_from(keys, off, 65536)
    val kl = z - off
  in
    if kl <= 0 then path_keys(doc, sec, keys, z + 1, len, f - 1)
    else if kl > 65536 then pd_nil()
    else let
      val ka = $A.alloc<byte>(kl)
      val () = fill_key(ka, kl, keys, off, 0)
      val @(fz_k, bv_k) = $A.freeze<byte>(ka)
      val vb = $A.alloc<byte>(4096)
      val vr = $T.get(doc, sec, 12, bv_k, kl, vb, 4096)
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val vl = (case+ vr of | ~$R.some(x) => x | ~$R.none() => 0): pos_t
      val @(fz_v, bv_v) = $A.freeze<byte>(vb)
      val @(ps, pe) = (if vl > 0 then (if peek(bv_v, 0, 4096) = 123 then path_value(bv_v, vl)
                                      else @(~1, ~1)) else @(~1, ~1)): @(pos_t, pos_t)
      val pa = $A.alloc<byte>(256)
      val pl = copy_path(bv_v, ps, pe, pa)
      val () = $A.drop<byte>(fz_v, bv_v)
      val () = $A.free<byte>($A.thaw<byte>(fz_v))
      val na = $A.alloc<byte>(256)
      val nk = copy_name(keys, off, z, 65536, na, 0)
    in
      if ps < 0 then let
        val () = $A.free<byte>(pa)
        val () = $A.free<byte>(na)
      in path_keys(doc, sec, keys, z + 1, len, f - 1) end
      else if nk <= 0 then let
        val () = $A.free<byte>(pa)
        val () = $A.free<byte>(na)
      in path_keys(doc, sec, keys, z + 1, len, f - 1) end
      else pd_cons(na, nk, pa, pl, path_keys(doc, sec, keys, z + 1, len, f - 1))
    end
  end

(* The path dependencies of doc's [dependencies] *)
fn doc_pdeps (doc: !$T.toml_doc): [n:nat] pdeps(n) = let
  var sec_c = @[char][12]('d', 'e', 'p', 'e', 'n', 'd', 'e', 'n', 'c', 'i', 'e', 's')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 12))
  val kb = $A.alloc<byte>(65536)
  val kl = (case+ $T.keys(doc, bv_s, 12, kb, 65536) of
    | ~$R.some(x) => x | ~$R.none() => 0): int
  val @(fz_kb, bv_kb) = $A.freeze<byte>(kb)
  val ds = path_keys(doc, bv_s, bv_kb, 0, kl, 65536)
  val () = $A.drop<byte>(fz_kb, bv_kb)
  val () = $A.free<byte>($A.thaw<byte>(fz_kb))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in ds end

(* The project's path dependencies; none when bats.toml cannot be read *)
fn project_pdeps (): [n:nat] pdeps(n) =
  case+ read_toml(str_to_path_arr("bats.toml")) of
  | ~$R.err(_) => pd_nil()
  | ~$R.ok(doc) => let
      val ds = doc_pdeps(doc)
      val () = $T.toml_free(doc)
    in ds end

(* xs without the name a[0, k) *)
fun names_remove {n:nat}{la:agz} .<n>.
  (xs: names(n), a: !$A.arr(byte, la, 256), k: int): [m:nat] names(m) =
  case+ xs of
  | ~names_nil() => names_nil()
  | ~names_cons(b, kb, rest) =>
    if name_is(b, kb, a, k) then let
      val () = $A.free<byte>(b)
    in names_remove(rest, a, k) end
    else names_cons(b, kb, names_remove(rest, a, k))

(* The constraints of the bats.toml in the path dependency's directory
   p[0, pl), from its name a[0, k); none when it does not load *)
fn pdep_cons {la,lp:agz}
  (a: !$A.arr(byte, la, 256), k: int, p: !$A.arr(byte, lp, 256), pl: int): [n:nat] cons(n) = let
  var b : $B.builder_v = $B.create()
  val () = put_name(p, pl, b)
  val () = bput_v(b, "/bats.toml")
  val () = put_char_v(b, 0)
  val @(ba, _) = $B.to_arr(b)
in
  case+ read_toml(ba) of
  | ~$R.err(_) => cons_nil()
  | ~$R.ok(doc) => let
      var err : $B.builder_v = $B.create()
      val @(st, cs) = config_cons(doc, a, k, err)
      val () = $B.builder_free(err)
      val () = $T.toml_free(doc)
    in
      if st > 0 then cs
      else let
        val () = cons_free(cs)
      in cons_nil() end
    end
end

(* For each path dependency: the #use packages of its src join stack and
   all, the dependency itself leaves them, and the constraints of its
   bats.toml join cs (Rust: resolve_all, before resolving) *)
fun add_pdeps {n,s,m,c:nat} .<n>.
  (ds: !pdeps(n), stack: names(s), all: names(m), cs: cons(c))
  : [s2,m2,c2:nat] @(names(s2), names(m2), cons(c2)) =
  case+ ds of
  | pd_nil() => @(stack, all, cs)
  | @pd_cons(a, k, p, pl, rest) => let
      var d : $B.builder_v = $B.create()
      val () = put_name(p, pl, d)
      val () = bput_v(d, "/src")
      val ts = collect_uses(d)
      val @(stack1, all1) = push_new(ts, stack, all)
      val stack2 = names_remove(stack1, a, k)
      val all2 = names_remove(all1, a, k)
      val cs2 = cons_append(cs, pdep_cons(a, k, p, pl))
      val r = add_pdeps(rest, stack2, all2, cs2)
      prval () = fold@(ds)
    in r end

(* ============================================================
   Missing dependencies (Rust: build::resolve_deps, lock::ensure_deps)
   ============================================================ *)

(* xs reversed onto acc *)
fun names_rev {n,m:nat} .<n>. (xs: names(n), acc: names(m)): names(n + m) =
  case+ xs of
  | ~names_nil() => acc
  | ~names_cons(a, k, rest) => names_rev(rest, names_cons(a, k, acc))

fn names_empty {n:nat} (xs: !names(n)): bool =
  case+ xs of
  | names_nil() => true
  | names_cons(_, _, _) => false

(* The names of xs, in order, that are neither path dependencies (pn)
   nor already in bats_modules *)
fun names_missing {n,np:nat} .<n>. (xs: names(n), pn: !names(np)): [m:nat] names(m) =
  case+ xs of
  | ~names_nil() => names_nil()
  | ~names_cons(a, k, rest) =>
    if names_has(pn, a, k) then let
      val () = $A.free<byte>(a)
    in names_missing(rest, pn) end
    else if is_fetched(a, k) then let
      val () = $A.free<byte>(a)
    in names_missing(rest, pn) end
    else names_cons(a, k, names_missing(rest, pn))

(* ", " when sep *)
fn put_sep (sep: bool, out: !$B.builder_v >> $B.builder_v): void =
  if sep then bput_v(out, ", ") else bput_v(out, "")

(* The names of xs joined by ", " *)
fun put_names_list {n:nat} .<n>.
  (xs: !names(n), sep: bool, out: !$B.builder_v >> $B.builder_v): void =
  case+ xs of
  | names_nil() => bput_v(out, "")
  | @names_cons(a, k, rest) => let
      val () = put_sep(sep, out)
      val () = put_name(a, k, out)
      val () = put_names_list(rest, true, out)
      prval () = fold@(xs)
    in end

(* Fetches the newest version of each package of xs that meets cs
   (Rust: ensure_deps); false after reporting one not found *)
fun fetch_missing {n,nc:nat}{lr:agz} .<n>.
  (xs: names(n), cs: !cons(nc), repo: !$A.borrow(byte, lr, 4096), rl: int): bool =
  case+ xs of
  | ~names_nil() => true
  | ~names_cons(a, k, rest) =>
    (case+ find_latest(repo, rl, a, k, false, cs) of
     | ~$R.none() => let
         val () = not_found(repo, rl, a, k)
         val () = $A.free<byte>(a)
         val () = names_free(rest)
       in false end
     | ~$R.some(v) => let
         val @(arc, alen) = archive_path(repo, rl, a, k, v)
         val @(fz_c, bv_c) = $A.freeze<byte>(arc)
         val () = fetch(bv_c, alen, a, k, v)
         val () = $A.drop<byte>(fz_c, bv_c)
         val () = $A.free<byte>($A.thaw<byte>(fz_c))
         val () = cand_free(v)
         val () = $A.free<byte>(a)
       in fetch_missing(rest, cs, repo, rl) end)

(* Fetches missing under the project's constraints, when cst says they
   were read; otherwise reports err; consumes err *)
fn fetch_with {nm,nc:nat}{lr:agz}
  (cst: int, cs: cons(nc), err: $B.builder_v, missing: names(nm),
   repo: !$A.borrow(byte, lr, 4096), rl: int): bool =
  if cst < 0 then let
    val () = cons_free(cs)
    val () = names_free(missing)
    var e : $B.builder_v = err
    val () = put_char_v(e, 10)
    val () = prerr_builder(e)
  in false end
  else let
    val () = $B.builder_free(err)
    val ok = fetch_missing(missing, cs, repo, rl)
    val () = cons_free(cs)
  in ok end

(* Rust's "missing dependencies: <a, b>. Use --repository <dir> to fetch
   them."; consumes missing *)
fn report_missing {nm:nat} (missing: names(nm)): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: missing dependencies: ")
  val () = put_names_list(missing, false, m)
  val () = bput_v(m, ". Use --repository <dir> to fetch them.\n")
  val () = names_free(missing)
in prerr_builder(m) end

(* kind, after printing err and failing when kind < 0; consumes err *)
fn report_config (kind: int, err: $B.builder_v): int =
  if kind < 0 then let
    var e : $B.builder_v = err
    val () = put_char_v(e, 10)
    val () = prerr_builder(e)
    val () = set_build_err()
  in kind end
  else let
    val () = $B.builder_free(err)
  in kind end

(* The project's kind as Rust's config::load reads bats.toml: 1 for lib,
   2 for bin, or ~1 after printing its error (a bats.toml that cannot be
   read, an unknown kind, a constraint that does not parse, a path
   dependency in a lib package) *)


implement project_kind () = let
  var err : $B.builder_v = $B.create()
  val () = bput_v(err, "error: ")
  val kind = (case+ read_toml(str_to_path_arr("bats.toml")) of
    | ~$R.err(e) => let
        val () = put_cannot_read(e, err)
      in ~1 end
    | ~$R.ok(doc) => let
        val nb = $A.alloc<byte>(256)
        val @(st, cs) = config_cons(doc, nb, 0, err)
        val () = cons_free(cs)
        val () = $A.free<byte>(nb)
        var quiet_err : $B.builder_v = $B.create()
        val k = (if st < 0 then ~1 else doc_kind(doc, quiet_err)): int
        val () = $B.builder_free(quiet_err)
        val () = $T.toml_free(doc)
      in k end): int
in
  report_config(kind, err)
end

(* ============================================================
   Path dependencies at build time (Rust: build::copy_path_dep)
   ============================================================ *)

(* A NUL-terminated path: a[0, n) + "/" + b[0, bl), and its length *)
fn child_path {la,lb:agz}
  (a: !$A.borrow(byte, la, 524288), n: int, b: !$A.borrow(byte, lb, 256), bl: int)
  : @([l:agz] $A.arr(byte, l, 524288), int) = let
  var p : $B.builder_v = $B.create()
  val () = copy_to_builder_v(a, 0, n, 524288, p)
  val () = put_char_v(p, 47)
  val () = copy_to_builder_v(b, 0, bl, 256, p)
  val pl = $B.length(p)
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in @(pa, pl) end

(* Writes buf[0, k) to dst; whether all of it was written; frees buf *)
fn write_prefix {l:agz}{k:pos | k <= 65536}
  (dst: !$F.fd, buf: $A.arr(byte, l, 65536), k: int k): bool = let
  val @(left, right) = $A.split<byte>(buf, k)
  val @(fz, bv) = $A.freeze<byte>(left)
  val w = (case+ $F.file_write(dst, bv, k) of | ~$R.ok(x) => x | ~$R.err(_) => ~1): int
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.join<byte>($A.thaw<byte>(fz), right))
in w = k end

(* Writes the bytes read from src to dst, 64 KiB at a time; false on an
   error *)
fun copy_bytes {f:nat} .<f>. (src: !$F.fd, dst: !$F.fd, f: int f): bool =
  if f <= 0 then true
  else let
    val buf = $A.alloc<byte>(65536)
  in
    case+ $F.file_read(src, buf, 65536) of
    | ~$R.err(_) => let
        val () = $A.free<byte>(buf)
      in false end
    | ~$R.ok(k) =>
      if k <= 0 then let
        val () = $A.free<byte>(buf)
      in true end
      else if write_prefix(dst, buf, k) then copy_bytes(src, dst, f - 1)
      else false
  end

(* Copies the file at the NUL-terminated path s to d (Rust: fs::copy);
   false on an error *)
(* Gives d the permission bits of s, as Rust's fs::copy does *)
fn copy_mode {ls,ld:agz}
  (s: !$A.borrow(byte, ls, 524288), d: !$A.borrow(byte, ld, 524288)): bool =
  case+ $F.file_mode(s, 524288) of
  | ~$R.err(_) => false
  | ~$R.ok(m) =>
    (case+ $F.file_chmod(d, 524288, m) of
     | ~$R.ok(_) => true
     | ~$R.err(_) => false)

fn copy_file {ls,ld:agz}
  (s: !$A.borrow(byte, ls, 524288), d: !$A.borrow(byte, ld, 524288)): bool =
  case+ $F.file_open(s, 524288, 0, 0) of
  | ~$R.err(_) => false
  | ~$R.ok(sf) =>
    (case+ $F.file_open(d, 524288, 1 + 64 + 512, 420) of
     | ~$R.err(_) => let
         val () = $R.discard<int><int>($F.file_close(sf))
       in false end
     | ~$R.ok(df) => let
         val ok = copy_bytes(sf, df, 1048576)
         val () = $R.discard<int><int>($F.file_close(sf))
         val () = $R.discard<int><int>($F.file_close(df))
       in if ok then copy_mode(s, d) else false end)

(* Whether e[0, el) is ".", "..", or a directory Rust's copy skips:
   build, dist, docs or bats_modules *)
fn skipped_name {le:agz} (e: !$A.borrow(byte, le, 256), el: int, is_dir: bool): bool = let
  var b_c = @[char][5]('b', 'u', 'i', 'l', 'd')
  var d_c = @[char][4]('d', 'i', 's', 't')
  var o_c = @[char][4]('d', 'o', 'c', 's')
  var m_c = @[char][12]('b', 'a', 't', 's', '_', 'm', 'o', 'd', 'u', 'l', 'e', 's')
in
  if el = 1 then peek(e, 0, 256) = 46
  else if el = 2 then (if peek(e, 0, 256) = 46 then peek(e, 1, 256) = 46 else false)
  else if ~is_dir then false
  else if el = 5 then lit_at(e, 0, 256, b_c, 5)
  else if el = 4 then (if lit_at(e, 0, 256, d_c, 4) then true else lit_at(e, 0, 256, o_c, 4))
  else if el = 12 then lit_at(e, 0, 256, m_c, 12)
  else false
end

(* Whether the NUL-terminated path p is a directory *)
fn is_directory {lp:agz} (p: !$A.borrow(byte, lp, 524288)): bool =
  case+ $F.dir_open(p, 524288) of
  | ~$R.ok(d) => let
      val () = $R.discard<int><int>($F.dir_close(d))
    in true end
  | ~$R.err(_) => false

(* Copies the entries of the open directory d, at s[0, sl), into
   d[0, dl) (Rust: copy_dir_recursive); false on an error *)
fun copy_entries {ls,ld:agz}{f:nat} .<f, 0>.
  (dir: !$F.dir, s: !$A.borrow(byte, ls, 524288), sl: int,
   d: !$A.borrow(byte, ld, 524288), dl: int, f: int f): bool =
  if f <= 0 then true
  else let
    val e = $A.alloc<byte>(256)
    val el = dir_name_len($F.dir_next(dir, e, 256))
  in
    if el < 0 then let
      val () = $A.free<byte>(e)
    in true end
    else let
      val @(fz_e, bv_e) = $A.freeze<byte>(e)
      val @(ca, cl) = child_path(s, sl, bv_e, el)
      val @(da, dl2) = child_path(d, dl, bv_e, el)
      val @(fz_c, bv_c) = $A.freeze<byte>(ca)
      val @(fz_d, bv_d) = $A.freeze<byte>(da)
      val is_dir = is_directory(bv_c)
      val ok = (if skipped_name(bv_e, el, is_dir) then true
                else if is_dir then copy_tree(bv_c, cl, bv_d, dl2, f - 1)
                else copy_file(bv_c, bv_d)): bool
      val () = $A.drop<byte>(fz_d, bv_d)
      val () = $A.free<byte>($A.thaw<byte>(fz_d))
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = $A.free<byte>($A.thaw<byte>(fz_c))
      val () = $A.drop<byte>(fz_e, bv_e)
      val () = $A.free<byte>($A.thaw<byte>(fz_e))
    in
      if ok then copy_entries(dir, s, sl, d, dl, f - 1) else false
    end
  end

(* Copies the directory s[0, sl) (NUL-terminated) to d[0, dl), creating
   it, without its build, dist, docs and bats_modules directories *)
and copy_tree {ls,ld:agz}{f:nat} .<f, 1>.
  (s: !$A.borrow(byte, ls, 524288), sl: int,
   d: !$A.borrow(byte, ld, 524288), dl: int, f: int f): bool = let
  var mk : $B.builder_v = $B.create()
  val () = copy_to_builder_v(d, 0, dl, 524288, mk)
  val _ = run_mkdir(mk)
in
  case+ $F.dir_open(s, 524288) of
  | ~$R.err(_) => false
  | ~$R.ok(dir) => let
      val ok = copy_entries(dir, s, sl, d, dl, f)
      val () = $R.discard<int><int>($F.dir_close(dir))
    in ok end
end

(* rm -rf the path in b; consumes b (Rust: remove_dir_all) *)
fn remove_tree (b: $B.builder_v): void = let
  val exec = str_to_path_arr("rm")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "rm")
  var b2 = $B.create()
  val () = bput_v(b2, "-rf")
  val _ = run_cmd(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b), $L.list_vt_nil()))))
  val () = $A.drop<byte>(fz_x, bv_x)
in $A.free<byte>($A.thaw<byte>(fz_x)) end

(* Rust's "path dependency '<n>': <what> '<p>'<after>" to stderr *)
fn path_dep_error {la,lp:agz}
  (a: !$A.arr(byte, la, 256), k: int, what: string, p: !$A.arr(byte, lp, 256), pl: int,
   after: string): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: path dependency '")
  val () = put_name(a, k, m)
  val () = bput_v(m, "': ")
  val () = prerr_builder(m)
  val () = prerr! (what)
  var q : $B.builder_v = $B.create()
  val () = bput_v(q, " '")
  val () = put_name(p, pl, q)
  val () = bput_v(q, "'")
  val () = prerr_builder(q)
in prerr! (after, "\n") end

(* Copies the path dependency a[0, k) from its directory p[0, pl) into
   bats_modules/<name>, replacing what is there (Rust: copy_path_dep);
   false after reporting an error *)
fn copy_path_dep {la,lp:agz}
  (a: !$A.arr(byte, la, 256), k: int, p: !$A.arr(byte, lp, 256), pl: int): bool = let
  var sb : $B.builder_v = $B.create()
  val () = put_name(p, pl, sb)
  val sl = $B.length(sb)
  val () = put_char_v(sb, 0)
  val @(sa, _) = $B.to_arr(sb)
  val @(fz_s, bv_s) = $A.freeze<byte>(sa)
  var lb : $B.builder_v = $B.create()
  val () = put_name(p, pl, lb)
  val () = bput_v(lb, "/src/lib.bats")
  val () = put_char_v(lb, 0)
  val @(la2, _) = $B.to_arr(lb)
  val @(fz_l, bv_l) = $A.freeze<byte>(la2)
  val has_dir = $F.file_exists(bv_s, 524288)
  val has_lib = $F.file_exists(bv_l, 524288)
  val () = $A.drop<byte>(fz_l, bv_l)
  val () = $A.free<byte>($A.thaw<byte>(fz_l))
  var db : $B.builder_v = $B.create()
  val () = bput_v(db, "bats_modules/")
  val () = put_name(a, k, db)
  val dl = $B.length(db)
  val () = put_char_v(db, 0)
  val @(da, _) = $B.to_arr(db)
  val @(fz_d, bv_d) = $A.freeze<byte>(da)
  val ok = (if ~has_dir then let
      val () = path_dep_error(a, k, "directory", p, pl, " does not exist")
    in false end
    else if ~has_lib then let
      val () = path_dep_error(a, k, "no src/lib.bats found in", p, pl, "")
    in false end
    else let
      var rb : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_d, 0, dl, 524288, rb)
      val () = remove_tree(rb)
    in copy_tree(bv_s, sl, bv_d, dl, 65536) end): bool
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in ok end

(* Copies each path dependency of ds into bats_modules, in order; false
   after the first error *)
fun copy_path_deps {n:nat} .<n>. (ds: !pdeps(n)): bool =
  case+ ds of
  | pd_nil() => true
  | @pd_cons(a, k, p, pl, rest) => let
      val ok = copy_path_dep(a, k, p, pl)
      val r = (if ok then copy_path_deps(rest) else false): bool
      prval () = fold@(ds)
    in r end

(* ============================================================
   Validation before building (Rust: project::preprocess_all and
   preprocess_one, emit::validate, BatsError::display_fancy)
   ============================================================ *)

#define VMAX 524288

(* Rust's offset_to_line_col: 1-based line and column (in bytes) of
   offset off in src *)
fun line_col {ls:agz}{f:nat} .<f>.
  (src: !$A.borrow(byte, ls, VMAX), i: pos_t, off: int, line: int, col: int, f: int f): @(int, int) =
  if f <= 0 then @(line, col)
  else if i >= off then @(line, col)
  else if peek(src, i, VMAX) = 10 then line_col(src, i + 1, off, line + 1, 1, f - 1)
  else line_col(src, i + 1, off, line, col + 1, f - 1)

(* The start of the line holding position i *)
fun line_start {ls:agz}{f:nat} .<f>. (src: !$A.borrow(byte, ls, VMAX), i: pos_t, f: int f): pos_t =
  if f <= 0 then i
  else if i <= 0 then 0
  else if peek(src, i - 1, VMAX) = 10 then i
  else line_start(src, i - 1, f - 1)

fun put_spaces {f:nat} .<f>. (k: int, out: !$B.builder_v >> $B.builder_v, f: int f): void =
  if f <= 0 then ()
  else if k <= 0 then ()
  else let
    val () = put_char_v(out, 32)
  in put_spaces(k - 1, out, f - 1) end

(* b's bytes appended to out; consumes b *)
fn append_builder (out: !$B.builder_v >> $B.builder_v, b: $B.builder_v): void = let
  val @(ba, bl) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(ba)
  val () = copy_to_builder_v(bv, 0, bl, VMAX, out)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

(* The number of decimal digits of n > 0 *)
fun digits {f:nat} .<f>. (n: int, f: int f): int =
  if f <= 0 then 1 else if n < 10 then 1 else 1 + digits(n / 10, f - 1)

(* Whether errors are colored, as Rust's display_fancy decides: standard
   error is a terminal and NO_COLOR is not set *)
fn use_color (): bool =
  if ~$E.stderr_is_terminal() then false
  else let
    var k_c = @[char][8]('N', 'O', '_', 'C', 'O', 'L', 'O', 'R')
    val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(k_c, 8))
    val vb = $A.alloc<byte>(16)
    val set = (case+ $E.get(bv_k, 8, vb, 16) of | ~$R.some(_) => true | ~$R.none() => false): bool
    val () = $A.free<byte>(vb)
    val () = $A.drop<byte>(fz_k, bv_k)
    val () = $A.free<byte>($A.thaw<byte>(fz_k))
  in ~set end

(* Rust's ANSI escapes, or nothing when c is false *)
fn put_red (out: !$B.builder_v >> $B.builder_v, c: bool): void =
  if c then bput_v(out, "\033[1;31m") else bput_v(out, "")
fn put_blue (out: !$B.builder_v >> $B.builder_v, c: bool): void =
  if c then bput_v(out, "\033[1;34m") else bput_v(out, "")
fn put_reset (out: !$B.builder_v >> $B.builder_v, c: bool): void =
  if c then bput_v(out, "\033[0m") else bput_v(out, "")

(* " |" with the bar in blue *)
fn put_bar (out: !$B.builder_v >> $B.builder_v, c: bool): void = let
  val () = put_char_v(out, 32)
  val () = put_blue(out, c)
  val () = put_char_v(out, 124)
in put_reset(out, c) end

(* Rust's display_fancy of the error msg at offset off of src[0, n), a
   file labeled lab[l0, l1), appended to out; consumes msg *)
fn put_fancy {ll,ls:agz}
  (lab: !$A.borrow(byte, ll, VMAX), l0: pos_t, l1: int, src: !$A.borrow(byte, ls, VMAX), n: pos_t,
   off: pos_t, msg: $B.builder_v, out: !$B.builder_v >> $B.builder_v): void = let
  val c = use_color()
  val @(line, col) = line_col(src, 0, off, 1, 1, VMAX)
  val pad = digits(line, 16)
  val ls = line_start(src, off, VMAX)
  val le = find_byte(src, VMAX, off, n, 10, VMAX)
  val () = put_red(out, c)
  val () = bput_v(out, "error:")
  val () = put_reset(out, c)
  val () = put_char_v(out, 32)
  val () = append_builder(out, msg)
  val () = bput_v(out, "\n ")
  val () = put_blue(out, c)
  val () = bput_v(out, "-->")
  val () = put_reset(out, c)
  val () = put_char_v(out, 32)
  val () = copy_to_builder_v(lab, l0, l1, VMAX, out)
  val () = put_char_v(out, 58)
  val () = bput_int_v(out, line)
  val () = put_char_v(out, 58)
  val () = bput_int_v(out, col)
  val () = put_char_v(out, 10)
  val () = put_char_v(out, 32)
  val () = put_spaces(pad, out, 16)
  val () = put_bar(out, c)
  val () = bput_v(out, "\n ")
  val () = bput_int_v(out, line)
  val () = put_bar(out, c)
  val () = put_char_v(out, 32)
  val () = copy_to_builder_v(src, ls, le, VMAX, out)
  val () = put_char_v(out, 10)
  val () = put_char_v(out, 32)
  val () = put_spaces(pad, out, 16)
  val () = put_bar(out, c)
  val () = put_char_v(out, 32)
  val () = put_spaces(col - 1, out, VMAX)
  val () = put_red(out, c)
  val () = put_char_v(out, 94)
  val () = put_reset(out, c)
in put_char_v(out, 10) end

(* errs + fancy, separated by a blank line as Rust's join("\n") does;
   the count of errors after it *)
fn add_error (cnt: int, fancy: $B.builder_v, errs: !$B.builder_v >> $B.builder_v): int = let
  val () = (if cnt > 0 then put_char_v(errs, 10) else bput_v(errs, ""))
  val () = append_builder(errs, fancy)
in cnt + 1 end

(* The kind of span idx *)
fn span_kind {lp:agz} (spans: !$A.borrow(byte, lp, VMAX), idx: pos_t): int =
  peek(spans, idx * 28, VMAX)

fn is_word_byte (c: int): bool =
  if c = 36 then true else if c = 35 then true
  else if c = 95 then true
  else if c >= 97 then c <= 122
  else if c >= 65 then c <= 90
  else if c >= 48 then c <= 57
  else false

(* The first position at or after i of src[0, e) that is not a word byte
   (letters, digits, _, $ and #) *)
fun word_end {ls:agz}{f:nat} .<f>. (src: !$A.borrow(byte, ls, VMAX), i: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then i
  else if i >= e then i
  else if is_word_byte(peek(src, i, VMAX)) then word_end(src, i + 1, e, f - 1)
  else i

(* Whether src[s, s + 7) is "$UNSAFE" *)
fn at_unsafe_kw {ls:agz} (src: !$A.borrow(byte, ls, VMAX), s: pos_t): bool = let
  var u_c = @[char][7]('$', 'U', 'N', 'S', 'A', 'F', 'E')
in lit_at(src, s, VMAX, u_c, 7) end

(* Whether src[s, s + 4) is "#pub": the unsafe construct is a #pub prfun
   without primplement *)
(* Whether the word at src[s, e) is prfun or prfn *)
fn at_prfun_kw {ls:agz} (src: !$A.borrow(byte, ls, VMAX), s: pos_t, e: pos_t): bool = let
  val we = word_end(src, s, e, VMAX)
  var a_c = @[char][5]('p', 'r', 'f', 'u', 'n')
  var b_c = @[char][4]('p', 'r', 'f', 'n')
in
  if we - s = 5 then lit_at(src, s, VMAX, a_c, 5)
  else if we - s = 4 then lit_at(src, s, VMAX, b_c, 4)
  else false
end

fn at_pub_kw {ls:agz} (src: !$A.borrow(byte, ls, VMAX), s: pos_t): bool = let
  var p_c = @[char][4]('#', 'p', 'u', 'b')
in lit_at(src, s, VMAX, p_c, 4) end

(* 'src[s, we)' is not allowed outside of $UNSAFE begin...end block *)
fn put_word_msg {ls:agz}
  (src: !$A.borrow(byte, ls, VMAX), s: pos_t, we: pos_t, m: !$B.builder_v >> $B.builder_v): void = let
  val () = put_char_v(m, 39)
  val () = copy_to_builder_v(src, s, we, VMAX, m)
in bput_v(m, "' is not allowed outside of $UNSAFE begin...end block") end

(* Rust's message for the unsafe construct, restricted keyword or
   extcode block span at src[s, e) outside $UNSAFE (emit::validate) *)
fn construct_msg {ls:agz}
  (src: !$A.borrow(byte, ls, VMAX), kind: int, s: pos_t, e: pos_t, m: !$B.builder_v >> $B.builder_v): void = let
  var fun_c = @[char][3]('f', 'u', 'n')
  val we = word_end(src, s, e, VMAX)
  val is_fun = (if we - s = 3 then lit_at(src, s, VMAX, fun_c, 3) else false): bool
in
  if kind = 6 then bput_v(m, "extcode block outside of $UNSAFE begin...end block")
  else if at_unsafe_kw(src, s) then bput_v(m, "$UNSAFE construct outside of $UNSAFE begin...end block")
  else if is_fun then
    bput_v(m, "'fun' without termination metric is not allowed outside $UNSAFE; use 'fn' or add '.< metric >.'")
  else put_word_msg(src, s, we, m)
end

(* Rust's "#pub prfun '<name>' has no primplement; ..." for the #pub
   declaration whose keyword starts src[s, e) *)
fn prfun_msg {ls:agz}
  (src: !$A.borrow(byte, ls, VMAX), s: pos_t, e: pos_t, m: !$B.builder_v >> $B.builder_v): void = let
  val k1 = word_end(src, s, e, VMAX)
  val n0 = skip_space(src, VMAX, k1, e, VMAX)
  val n1 = word_end(src, n0, e, VMAX)
  val () = bput_v(m, "#pub prfun '")
  val () = copy_to_builder_v(src, n0, n1, VMAX, m)
in bput_v(m, "' has no primplement; unimplemented proof functions are unsound") end

(* The start of the last component of p[0, pl) *)
fun base_start {lp:agz}{f:nat} .<f>. (p: !$A.borrow(byte, lp, VMAX), i: pos_t, f: int f): pos_t =
  if f <= 0 then i
  else if i <= 0 then 0
  else if peek(p, i - 1, VMAX) = 47 then i
  else base_start(p, i - 1, f - 1)

(* A span's start and end *)
fn span_range {lp:agz} (spans: !$A.borrow(byte, lp, VMAX), idx: pos_t): @(pos_t, pos_t) =
  @(span_i32(spans, idx * 28 + 2, VMAX), span_i32(spans, idx * 28 + 6, VMAX))

(* Rust's "dependency '<pkg>' not found (expected <lib.bats>)" for each
   #use whose package has no bats_modules/<pkg>/src/lib.bats, labeled with
   the file's path p[0, pl) (preprocess_one) *)
fun pass_uses {lp,ls,lsp:agz}{f:nat} .<f>.
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, VMAX), n: pos_t,
   spans: !$A.borrow(byte, lsp, VMAX), idx: pos_t, count: int,
   cnt: int, errs: !$B.builder_v >> $B.builder_v, f: int f): int =
  if f <= 0 then cnt
  else if idx >= count then cnt
  else if span_kind(spans, idx) <> 1 then pass_uses(p, pl, src, n, spans, idx + 1, count, cnt, errs, f - 1)
  else let
    val @(ss, _) = span_range(spans, idx)
    val ps = span_i32(spans, idx * 28 + 10, VMAX)
    val pe = span_i32(spans, idx * 28 + 14, VMAX)
    var lb : $B.builder_v = $B.create()
    val () = bput_v(lb, "./bats_modules/")
    val () = copy_to_builder_v(src, ps, pe, VMAX, lb)
    val () = bput_v(lb, "/src/lib.bats")
    val lbl = $B.length(lb)
    val () = put_char_v(lb, 0)
    val @(la, _) = $B.to_arr(lb)
    val @(fz_l, bv_l) = $A.freeze<byte>(la)
    val found = $F.file_exists(bv_l, VMAX)
    val cnt2 = add_missing(found, p, pl, src, n, ss, ps, pe, bv_l, lbl, cnt, errs)
    val () = $A.drop<byte>(fz_l, bv_l)
    val () = $A.free<byte>($A.thaw<byte>(fz_l))
  in pass_uses(p, pl, src, n, spans, idx + 1, count, cnt2, errs, f - 1) end

and add_missing {lp,ls,ll:agz}
  (found: bool, p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, VMAX), n: pos_t,
   ss: pos_t, ps: pos_t, pe: pos_t, lib: !$A.borrow(byte, ll, VMAX), lbl: int,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if found then cnt
  else let
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "dependency '")
    val () = copy_to_builder_v(src, ps, pe, VMAX, m)
    val () = bput_v(m, "' not found (expected ")
    val () = copy_to_builder_v(lib, 0, lbl, VMAX, m)
    val () = put_char_v(m, 41)
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, 0, pl, src, n, ss, m, fy)
  in add_error(cnt, fy, errs) end

(* Rust's "$UNSAFE requires `unsafe = true` in bats.toml" for each
   $UNSAFE block, labeled with the file's path (preprocess_one); an
   unsafe package passes a count of 0 *)
fun pass_unsafe_blocks {lp,ls,lsp:agz}{f:nat} .<f>.
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, VMAX), n: pos_t,
   spans: !$A.borrow(byte, lsp, VMAX), idx: pos_t, count: int,
   cnt: int, errs: !$B.builder_v >> $B.builder_v, f: int f): int =
  if f <= 0 then cnt
  else if idx >= count then cnt
  else if span_kind(spans, idx) <> 4 then
    pass_unsafe_blocks(p, pl, src, n, spans, idx + 1, count, cnt, errs, f - 1)
  else let
    val @(ss, _) = span_range(spans, idx)
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "$UNSAFE requires `unsafe = true` in bats.toml")
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, 0, pl, src, n, ss, m, fy)
    val cnt2 = add_error(cnt, fy, errs)
  in pass_unsafe_blocks(p, pl, src, n, spans, idx + 1, count, cnt2, errs, f - 1) end

(* The unsafe constructs, restricted keywords and extcode blocks outside
   $UNSAFE, in order, labeled with the file's name p[b0, pl)
   (emit::validate); want_pf selects the #pub prfun ones instead, which
   Rust reports after the others *)
fun pass_constructs {lp,ls,lsp:agz}{f:nat} .<f>.
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, VMAX), n: pos_t,
   spans: !$A.borrow(byte, lsp, VMAX), idx: pos_t, count: int, want_pf: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v, f: int f): int =
  if f <= 0 then cnt
  else if idx >= count then cnt
  else let
    val kind = span_kind(spans, idx)
    val @(ss, se) = span_range(spans, idx)
    val is_pub = (if kind = 5 then at_pub_kw(src, ss) else false): bool
    val ws = (if is_pub then span_i32(spans, idx * 28 + 10, VMAX) else ss): pos_t
    val is_pf = (if is_pub then at_prfun_kw(src, ws, se) else false): bool
    val hit = (if want_pf then is_pf
               else if kind = 6 then true
               else if kind = 9 then true
               else if kind = 5 then ~is_pf
               else false): bool
    val cnt2 = add_construct(hit, want_pf, kind, p, b0, pl, src, n, ss, ws, se, cnt, errs)
  in pass_constructs(p, b0, pl, src, n, spans, idx + 1, count, want_pf, cnt2, errs, f - 1) end

and add_construct {lp,ls:agz}
  (hit: bool, want_pf: bool, kind: int, p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t,
   src: !$A.borrow(byte, ls, VMAX), n: pos_t, ss: pos_t, ws: pos_t, se: pos_t,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if ~hit then cnt
  else let
    var m : $B.builder_v = $B.create()
    val () = (if want_pf then prfun_msg(src, ws, se, m) else construct_msg(src, kind, ws, se, m)): void
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, b0, pl, src, n, ss, m, fy)
  in add_error(cnt, fy, errs) end

(* Whether src[a, a + k) and src[b, b + k) hold the same bytes *)
fun same_bytes {ls:agz}{f:nat} .<f>.
  (src: !$A.borrow(byte, ls, VMAX), a: pos_t, b: pos_t, k: int, f: int f): bool =
  if f <= 0 then false
  else if k <= 0 then true
  else if peek(src, a, VMAX) <> peek(src, b, VMAX) then false
  else same_bytes(src, a + 1, b + 1, k - 1, f - 1)

(* Whether a #use span of spans[idx, count) names the alias src[as, ae) *)
fun alias_known {ls,lsp:agz}{f:nat} .<f>.
  (src: !$A.borrow(byte, ls, VMAX), spans: !$A.borrow(byte, lsp, VMAX), idx: pos_t, count: int,
   as0: pos_t, ae: pos_t, f: int f): bool =
  if f <= 0 then false
  else if idx >= count then false
  else if span_kind(spans, idx) <> 1 then alias_known(src, spans, idx + 1, count, as0, ae, f - 1)
  else let
    val us = span_i32(spans, idx * 28 + 18, VMAX)
    val ue = span_i32(spans, idx * 28 + 22, VMAX)
  in
    if (if ue - us = ae - as0 then same_bytes(src, us, as0, ae - as0, VMAX) else false) then true
    else alias_known(src, spans, idx + 1, count, as0, ae, f - 1)
  end

(* Whether src[0, n) binds the alias src[as0, ae) with ATS's
   staload <alias> = "...", which the Rust bats did not accept (an
   allowed divergence: packages staload bridge modules this way) *)
fun staload_alias {ls:agz}{f:nat} .<f>.
  (src: !$A.borrow(byte, ls, VMAX), i: pos_t, n: pos_t, as0: pos_t, ae: pos_t, f: int f): bool =
  if f <= 0 then false
  else if i + 7 > n then false
  else let
    var s_c = @[char][7]('s', 't', 'a', 'l', 'o', 'a', 'd')
    val at_kw = (if i > 0 then (if is_word_byte(peek(src, i - 1, VMAX)) then false
                                else lit_at(src, i, VMAX, s_c, 7))
                 else lit_at(src, i, VMAX, s_c, 7)): bool
    val k0 = skip_space(src, VMAX, i + 7, n, VMAX)
    val k1 = word_end(src, k0, n, VMAX)
    val k2 = skip_space(src, VMAX, k1, n, VMAX)
    val hit = (if ~at_kw then false
               else if k0 = i + 7 then false
               else if k1 - k0 <> ae - as0 then false
               else if ~same_bytes(src, k0, as0, ae - as0, VMAX) then false
               else peek(src, k2, VMAX) = 61): bool
  in if hit then true else staload_alias(src, i + 1, n, as0, ae, f - 1) end

(* Rust's "unknown alias '<a>' in qualified access" for each $a.member
   whose a no #use names, labeled with the file's name p[b0, pl)
   (emit::validate) *)
fun pass_aliases {lp,ls,lsp:agz}{f:nat} .<f>.
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, VMAX), n: pos_t,
   spans: !$A.borrow(byte, lsp, VMAX), idx: pos_t, count: int,
   cnt: int, errs: !$B.builder_v >> $B.builder_v, f: int f): int =
  if f <= 0 then cnt
  else if idx >= count then cnt
  else let
    val is_q = (span_kind(spans, idx) = 3): bool
    val @(ss, _) = span_range(spans, idx)
    val as0 = span_i32(spans, idx * 28 + 10, VMAX)
    val ae = span_i32(spans, idx * 28 + 14, VMAX)
    val bad = (if ~is_q then false
               else if alias_known(src, spans, 0, count, as0, ae, VMAX) then false
               else ~staload_alias(src, 0, n, as0, ae, VMAX)): bool
    val cnt2 = add_alias_error(bad, p, b0, pl, src, n, ss, as0, ae, cnt, errs)
  in pass_aliases(p, b0, pl, src, n, spans, idx + 1, count, cnt2, errs, f - 1) end

and add_alias_error {lp,ls:agz}
  (bad: bool, p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t,
   src: !$A.borrow(byte, ls, VMAX), n: pos_t, ss: pos_t, as0: pos_t, ae: pos_t,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if ~bad then cnt
  else let
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "unknown alias '")
    val () = copy_to_builder_v(src, as0, ae, VMAX, m)
    val () = bput_v(m, "' in qualified access")
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, b0, pl, src, n, ss, m, fy)
  in add_error(cnt, fy, errs) end

(* The errors of the file at the NUL-terminated path p[0, pl), whose
   package is unsafe or not, added to errs (Rust: preprocess_one, in its
   order), when wanted *)
fn check_file {lp:agz}
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, wanted: bool, is_unsafe: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if ~wanted then cnt else
  case+ $F.file_open(p, VMAX, 0, 0) of
  | ~$R.err(_) => cnt
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(VMAX)
      val n = (case+ $F.file_read(fd, buf, VMAX) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= VMAX] int k
      val () = $R.discard<int><int>($F.file_close(fd))
      val @(fz_s, bv_s) = $A.freeze<byte>(buf)
      val @(span_arr, _, count) = do_lex(bv_s, n, VMAX)
      val @(fz_sp, bv_sp) = $A.freeze<byte>(span_arr)
      val b0 = base_start(p, pl, VMAX)
      val c1 = pass_uses(p, pl, bv_s, n, bv_sp, 0, count, cnt, errs, VMAX)
      val c2 = pass_unsafe_blocks(p, pl, bv_s, n, bv_sp, 0, (if is_unsafe then 0 else count): int, c1, errs, VMAX)
      val c3 = pass_constructs(p, b0, pl, bv_s, n, bv_sp, 0, count, false, c2, errs, VMAX)
      val c3a = pass_aliases(p, b0, pl, bv_s, n, bv_sp, 0, count, c3, errs, VMAX)
      val c4 = pass_constructs(p, b0, pl, bv_s, n, bv_sp, 0, count, true, c3a, errs, VMAX)
      val () = $A.drop<byte>(fz_sp, bv_sp)
      val () = $A.free<byte>($A.thaw<byte>(fz_sp))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
    in c4 end

(* Whether the bats.toml at the NUL-terminated path in pa sets
   unsafe = true *)
fn toml_unsafe {lp:agz} (pa: $A.arr(byte, lp, 524288)): bool =
  case+ read_toml(pa) of
  | ~$R.err(_) => false
  | ~$R.ok(doc) => let
      var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
      val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
      var key_c = @[char][6]('u', 'n', 's', 'a', 'f', 'e')
      val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 6))
      val vb = $A.alloc<byte>(16)
      val vl = (case+ $T.get(doc, bv_s, 7, bv_k, 6, vb, 16) of
        | ~$R.some(x) => x | ~$R.none() => 0): int
      val @(fz_v, bv_v) = $A.freeze<byte>(vb)
      var t_c = @[char][4]('t', 'r', 'u', 'e')
      val yes = (if vl = 4 then lit_at(bv_v, 0, 16, t_c, 4) else false): bool
      val () = $A.drop<byte>(fz_v, bv_v)
      val () = $A.free<byte>($A.thaw<byte>(fz_v))
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
      val () = $T.toml_free(doc)
    in yes end

(* The package root of the dependency file p[0, pl) =
   ./bats_modules/<pkg>/src/...: the end of ./bats_modules/<pkg> *)
fun dep_root_end {lp:agz}{f:nat} .<f>. (p: !$A.borrow(byte, lp, VMAX), i: pos_t, pl: pos_t, f: int f): pos_t =
  if f <= 0 then pl
  else if i + 5 > pl then pl
  else let
    var s_c = @[char][5]('/', 's', 'r', 'c', '/')
  in
    if lit_at(p, i, VMAX, s_c, 5) then i else dep_root_end(p, i + 1, pl, f - 1)
  end

(* Whether the dependency owning the file p[0, pl) is unsafe (Rust:
   preprocess_all's config::load of its root) *)
fn dep_unsafe {lp:agz} (p: !$A.borrow(byte, lp, VMAX), pl: pos_t): bool = let
  val re = dep_root_end(p, 15, pl, VMAX)
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(p, 0, re, VMAX, b)
  val () = bput_v(b, "/bats.toml")
  val () = put_char_v(b, 0)
  val @(ba, _) = $B.to_arr(b)
in toml_unsafe(ba) end

(* Whether the file p[b0, pl) is named lib.bats *)
fn is_lib_name {lp:agz} (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t): bool = let
  var l_c = @[char][8]('l', 'i', 'b', '.', 'b', 'a', 't', 's')
in if pl - b0 = 8 then lit_at(p, b0, VMAX, l_c, 8) else false end

(* Whether p starts with ./src/bin/ *)
fn in_bin {lp:agz} (p: !$A.borrow(byte, lp, VMAX)): bool = let
  var b_c = @[char][10]('.', '/', 's', 'r', 'c', '/', 'b', 'i', 'n', '/')
in lit_at(p, 0, VMAX, b_c, 10) end

(* Checks each file of the NUL-separated list files[off, len): mode 0
   the package's shared modules (not src/bin/, not named lib.bats), 1
   the dependencies (each under its own unsafe flag), 2 every file *)
fun check_list {lf:agz}{f:nat} .<f>.
  (files: !$A.borrow(byte, lf, VMAX), off: pos_t, len: int, mode: int, own_unsafe: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v, f: int f): int =
  if f <= 0 then cnt
  else if off >= len then cnt
  else let
    val e = find_null_bv_from(files, off, VMAX)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, VMAX, pb)
    val pl = e - off
    val @(pa, _) = $B.to_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val b0 = base_start(bv_p, pl, VMAX)
    val skip = (if mode = 0 then (if in_bin(bv_p) then true else is_lib_name(bv_p, b0, pl)) else false): bool
    val uns = (if mode = 1 then dep_unsafe(bv_p, pl) else own_unsafe): bool
    val cnt2 = check_file(bv_p, pl, ~skip, uns, cnt, errs)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in check_list(files, e + 1, len, mode, own_unsafe, cnt2, errs, f - 1) end

(* Checks the .bats files under dir (./src, ./bats_modules or
   ./src/bin) in mode, as check_list does *)
fn check_dir {sn:nat} (dir: string sn, mode: int, own_unsafe: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int = let
  var d : $B.builder_v = $B.create()
  val () = bput_v(d, dir)
  val @(fa, flen) = sorted_bats_files(d)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val c = check_list(bv_f, 0, flen, mode, own_unsafe, cnt, errs, 65536)
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in c end

(* Prints cnt errors as Rust does; whether there were none *)
fn report_errors (cnt: int, errs: $B.builder_v): bool =
  if cnt <= 0 then let val () = $B.builder_free(errs) in true end
  else let
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "error: ")
    val () = append_builder(m, errs)
    val () = put_char_v(m, 10)
    val () = prerr_builder(m)
    val () = set_build_err()
  in false end

(* Before check, build or test: the errors Rust's preprocess_all finds in
   the package's modules, its dependencies, src/lib.bats and its binaries,
   in that order, printed as Rust prints them; false when there were
   any *)


implement validate_project () = let
  val own_unsafe = toml_unsafe(str_to_path_arr("./bats.toml"))
  var errs : $B.builder_v = $B.create()
  val c1 = check_dir("./src", 0, own_unsafe, 0, errs)
  val c2 = check_dir("./bats_modules", 1, own_unsafe, c1, errs)
  val lp = str_to_path_arr("./src/lib.bats")
  val @(fz_l, bv_l) = $A.freeze<byte>(lp)
  val c3 = check_file(bv_l, 14, $F.file_exists(bv_l, VMAX), own_unsafe, c2, errs)
  val () = $A.drop<byte>(fz_l, bv_l)
  val () = $A.free<byte>($A.thaw<byte>(fz_l))
  val c4 = check_dir("./src/bin", 2, own_unsafe, c3, errs)
in
  report_errors(c4, errs)
end

(* Before build, check or test: every #use package of src/ that is not a
   path dependency must be in bats_modules; the missing ones are fetched
   from the repository repo[0, rplen), or reported when there is none
   (Rust: build::resolve_deps). false after an error. *)


implement resolve_deps {lr} (repo, rplen) = let
  var src : $B.builder_v = $B.create()
  val () = bput_v(src, "src")
  val pkgs = names_rev(collect_uses(src), names_nil())
  val ds = project_pdeps()
  (* Path dependencies are copied first, fresh each time *)
  val copied = copy_path_deps(ds)
  val pn = pdeps_names(ds)
  val () = pdeps_free(ds)
  val missing = names_missing(pkgs, pn)
  val () = names_free(pn)
in
  if ~copied then let
    val () = names_free(missing)
    val () = set_build_err()
  in false end
  else if names_empty(missing) then let
    val () = names_free(missing)
  in true end
  else if rplen <= 0 then let
    val () = report_missing(missing)
    val () = set_build_err()
  in false end
  else let
    var err : $B.builder_v = $B.create()
    val () = bput_v(err, "error: ")
    val @(cst, cs) = project_cons(err)
    val ok = fetch_with(cst, cs, err, missing, repo, rplen)
    val () = (if ok then () else set_build_err())
  in ok end
end

(* Resolves the #use packages of src/ under the project's constraints
   cs and writes bats.lock, when cst says they were read; otherwise
   reports err, Rust's message about them; consumes err *)
fn lock_with {lr:agz}{nc:nat}
  (cst: int, cs: cons(nc), err: $B.builder_v,
   repo: !$A.borrow(byte, lr, 4096), rplen: int, dev: bool, dry: bool): void =
  if cst < 0 then let
    val () = cons_free(cs)
    var e : $B.builder_v = err
    val () = put_char_v(e, 10)
    val () = prerr_builder(e)
  in set_build_err() end
  else let
    val () = $B.builder_free(err)
    var src : $B.builder_v = $B.create()
    val () = bput_v(src, "src")
    val pkgs = collect_uses(src)
    val all = names_copy(pkgs)
    val ds = project_pdeps()
    val @(stack, all2, cs2) = add_pdeps(ds, pkgs, all, cs)
    val pn = pdeps_names(ds)
    val () = pdeps_free(ds)
    var lock : $B.builder_v = $B.create()
    val @(st, n) = resolve_all(stack, all2, cs2, pn, repo, rplen, dev, lock, 0, 65536)
    val () = names_free(pn)
  in finish_lock(st, n, lock, dry) end

(* bats lock --repository <repo[0, rplen)> [--dev] [--dry-run]: resolves
   the #use packages of src/ and writes bats.lock, or with --dry-run
   compares them with it (Rust: cmd_lock, generate).
   rplen is 0 when --repository was not given. *)



implement do_lock {lr} (dev, dry_run, repo, rplen) =
  if rplen <= 0 then let
    val () = set_build_err()
  in prerr! ("error: 'bats lock' requires --repository <dir>\n") end
  else let
    var err : $B.builder_v = $B.create()
    val () = bput_v(err, "error: ")
    val @(cst, cs) = project_cons(err)
  in lock_with(cst, cs, err, repo, rplen, dev <> 0, dry_run <> 0) end
