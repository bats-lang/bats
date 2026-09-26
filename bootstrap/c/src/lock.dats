staload "./lock.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
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

(* b's bytes to stderr; consumes b *)
fn prerr_builder (b: $B.builder_v): void = let
  val @(ba, bl) = $B.to_arr(b)
  fun loop {lb:agz}{f:nat} .<f>.
    (a: !$A.arr(byte, lb, 524288), i: pos_t, n: int, f: int f): void =
    if f <= 0 then ()
    else if i >= n then ()
    else if i < 0 then ()
    else if i >= 524288 then ()
    else let
      val () = prerr_char(int2char0(byte2int0($A.get<byte>(a, i))))
    in loop(a, i + 1, n, f - 1) end
  val () = loop(ba, 0, bl, 524288)
in $A.free<byte>(ba) end

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

(* The first position in [i, e) of v that is not whitespace, or e *)
fun skip_space {lv:agz}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, 4096), i: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if is_space(peek(v, i, 4096)) then skip_space(v, i + 1, e, f - 1)
  else i

(* e without the whitespace that ends v[s, e) *)
fun trim_end {lv:agz}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, 4096), s: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then s
  else if e <= s then s
  else if is_space(peek(v, e - 1, 4096)) then trim_end(v, s, e - 1, f - 1)
  else e

(* The first ',' in v[i, e), or e *)
fun comma_at {lv:agz}{f:nat} .<f>.
  (v: !$A.borrow(byte, lv, 4096), i: pos_t, e: pos_t, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if peek(v, i, 4096) = 44 then i
  else comma_at(v, i + 1, e, f - 1)

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
    val vs = skip_space(v, s + 2, e, 4096)
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
    val ce = comma_at(v, i, e, 4096)
    val ts = skip_space(v, i, ce, 4096)
    val te = trim_end(v, ts, ce, 4096)
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
   keys[off, len) of doc's [dependencies] (sec) to acc, from src[0, sk);
   false after writing Rust's message to err *)
fun load_keys {lk,ls,lsec:agz}{n:nat}{f:nat} .<f>.
  (doc: !$T.toml_doc, sec: !$A.borrow(byte, lsec, 12),
   keys: !$A.borrow(byte, lk, 65536), off: pos_t, len: int,
   src: !$A.arr(byte, ls, 256), sk: int,
   acc: cons(n), err: !$B.builder_v >> $B.builder_v, f: int f): [m:nat] @(bool, cons(m)) =
  if f <= 0 then @(true, acc)
  else if off >= len then @(true, acc)
  else let
    val z = find_null_bv_from(keys, off, 65536)
    val kl = z - off
  in
    if kl <= 0 then load_keys(doc, sec, keys, z + 1, len, src, sk, acc, err, f - 1)
    else if kl > 65536 then @(true, acc)
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
      var why : $B.builder_v = $B.create()
      val @(ok, acc2) = parse_cons(bv_v, 0, vl, p, pk, src, sk, acc, why, 4096)
      val () = $A.drop<byte>(fz_v, bv_v)
      val () = $A.free<byte>($A.thaw<byte>(fz_v))
      val () = put_why(ok, p, pk, why, err)
      val () = $A.free<byte>(p)
    in
      if ok then load_keys(doc, sec, keys, z + 1, len, src, sk, acc2, err, f - 1)
      else @(false, acc2)
    end
  end

(* The constraints of doc's [dependencies], from src[0, sk) (Rust:
   config::load's dependencies): @(1, them), or @(~1, none) after
   writing Rust's "in [dependencies] '<name>': ..." to err *)
fn doc_cons {ls:agz}
  (doc: !$T.toml_doc, src: !$A.arr(byte, ls, 256), sk: int,
   err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n)) = let
  var sec_c = @[char][12]('d', 'e', 'p', 'e', 'n', 'd', 'e', 'n', 'c', 'i', 'e', 's')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 12))
  val kb = $A.alloc<byte>(65536)
  val kr = $T.keys(doc, bv_s, 12, kb, 65536)
  val kl = (case+ kr of | ~$R.some(x) => x | ~$R.none() => 0): int
  val @(fz_kb, bv_kb) = $A.freeze<byte>(kb)
  val @(ok, cs) = load_keys(doc, bv_s, bv_kb, 0, kl, src, sk, cons_nil(), err, 65536)
  val () = $A.drop<byte>(fz_kb, bv_kb)
  val () = $A.free<byte>($A.thaw<byte>(fz_kb))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in
  if ok then @(1, cs)
  else let
    val () = cons_free(cs)
  in @(~1, cons_nil()) end
end

(* The TOML file at the NUL-terminated path pa, parsed; none when it
   cannot be read *)
fn read_toml {lp:agz} (pa: $A.arr(byte, lp, 524288)): $R.option($T.toml_doc) = let
  val @(fz, bv) = $A.freeze<byte>(pa)
  val fr = $F.file_open(bv, 524288, 0, 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ fr of
  | ~$R.err(_) => $R.none()
  | ~$R.ok(fd) => let
      val tb = $A.alloc<byte>(65536)
      val rr = $F.file_read(fd, tb, 65536)
      val () = $R.discard<int><int>($F.file_close(fd))
      val ok = (case+ rr of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
      val @(fz_t, bv_t) = $A.freeze<byte>(tb)
      val pr = $T.parse(bv_t, 65536)
      val () = $A.drop<byte>(fz_t, bv_t)
      val () = $A.free<byte>($A.thaw<byte>(fz_t))
    in
      case+ pr of
      | ~$R.ok(doc) =>
        if ok then $R.some(doc)
        else let
          val () = $T.toml_free(doc)
        in $R.none() end
      | ~$R.err(_) => $R.none()
    end
end

(* The constraints of the project's bats.toml, from its [package] name:
   @(1, them), @(0, none) when there is no bats.toml, or @(~1, none)
   after writing Rust's message to err *)
fn project_cons (err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n)) =
  case+ read_toml(str_to_path_arr("bats.toml")) of
  | ~$R.none() => @(0, cons_nil())
  | ~$R.some(doc) => let
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
      val r = doc_cons(doc, nb, nk, err)
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
  | ~$R.none() => cons_nil()
  | ~$R.some(doc) => let
      var err : $B.builder_v = $B.create()
      val @(st, cs) = doc_cons(doc, a, k, err)
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

(* Resolves the packages on stack, the newest first, into lock lines;
   all holds every package queued so far, cs the constraints read so far.
   @(0 or ~1 on an error, the number resolved) (Rust: resolve_all) *)
fun resolve_all {s,m,nc:nat}{lr:agz}{f:nat} .<f>.
  (stack: names(s), all: names(m), cs: cons(nc), repo: !$A.borrow(byte, lr, 4096), rl: int,
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
  | ~names_cons(a, k, rest) => let
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
          if ok then resolve_all(stack2, all2, cs2, repo, rl, dev, lock, count + 1, f - 1)
          else let
            val () = names_free(stack2)
            val () = names_free(all2)
            val () = cons_free(cs2)
          in @(~1, count) end
        end
    end

(* Writes lock to bats.lock and reports it, when st says resolving
   succeeded (Rust: generate); consumes lock *)
fn finish_lock (st: int, n: int, lock: $B.builder_v): void =
  if st < 0 then let
    val () = $B.builder_free(lock)
  in set_build_err() end
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

(* Resolves the #use packages of src/ under the project's constraints
   cs and writes bats.lock, when cst says they were read; otherwise
   reports err, Rust's message about them; consumes err *)
fn lock_with {lr:agz}{nc:nat}
  (cst: int, cs: cons(nc), err: $B.builder_v,
   repo: !$A.borrow(byte, lr, 4096), rplen: int, dev: bool): void =
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
    var lock : $B.builder_v = $B.create()
    val @(st, n) = resolve_all(pkgs, all, cs, repo, rplen, dev, lock, 0, 65536)
  in finish_lock(st, n, lock) end

(* bats lock --repository <repo[0, rplen)> [--dev]: resolves the #use
   packages of src/ and writes bats.lock (Rust: cmd_lock, generate).
   rplen is 0 when --repository was not given. *)



implement do_lock {lr} (dev, dry_run, repo, rplen) =
  if rplen <= 0 then let
    val () = set_build_err()
  in prerr! ("error: 'bats lock' requires --repository <dir>\n") end
  else let
    var err : $B.builder_v = $B.create()
    val () = bput_v(err, "error: ")
    val @(cst, cs) = project_cons(err)
  in lock_with(cst, cs, err, repo, rplen, dev <> 0) end
