(* lock -- bats lock, as the Rust bats's lock::generate and resolve_all *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R
#use str as S
#use toml as T

staload "helpers.sats"
staload "lexer.sats"
staload "docs.sats"
staload "recursion.sats"

(* ============================================================
   Package names
   ============================================================ *)

(* The length of a name in a 256-byte array *)
typedef nlen = [k:nat | k <= 256] int k

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

(* a[i, k) appended to out *)
fun put_bytes {la:agz}{i:nat | i <= 256} .<256 - i>.
  (a: !$A.arr(byte, la, 256), i: int i, k: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= 256 then ()
  else if i >= k then ()
  else let
    val () = put_char_v(out, byte2int0($A.get<byte>(a, i)))
  in put_bytes(a, i + 1, k, out) end

(* The name a[0, k) appended to out *)
fn put_name {la:agz}
  (a: !$A.arr(byte, la, 256), k: int, out: !$B.builder_v >> $B.builder_v): void =
  put_bytes(a, 0, k, out)

(* ============================================================
   The #use packages of a directory (Rust: collect_packages)
   ============================================================ *)

(* seen, with the package of sp added when sp is a #use of a package
   not already there *)
fn add_use {l:agz}{n:pos}{m:nat}
  (src: !$A.borrow(byte, l, n), n: int n, sp: !span(n), seen: names(m)): [m2:nat] names(m2) =
  case+ sp of
  | SUse(_, _, _, s, e, _, _) => let
      val a = $A.alloc<byte>(256)
      val k = copy_name(src, s, e, n, a, 0)
    in
      if k <= 0 then let
        val () = $A.free<byte>(a)
      in seen end
      else if names_has(seen, a, k) then let
        val () = $A.free<byte>(a)
      in seen end
      else names_cons(a, k, seen)
    end
  | _ => seen

(* Adds the packages of the #use spans of xs to seen, newest first,
   skipping those already there *)
fun add_uses {l:agz}{n:pos}{m:nat}{k:nat} .<k>.
  (src: !$A.borrow(byte, l, n), n: int n, xs: !spans(n, k), seen: names(m)): [m2:nat] names(m2) =
  case+ xs of
  | spans_nil() => seen
  | spans_cons(sp, tl) => add_uses(src, n, tl, add_use(src, n, sp, seen))

(* Adds the #use packages of the file at the NUL-terminated path p *)
fn add_file_uses {lp:agz}{m:nat}
  (p: !$A.borrow(byte, lp, 524288), seen: names(m)): [m2:nat] names(m2) =
  case+ read_whole(p, 524288) of
  | ~whole_ok(ar, piece, m, nbytes) => let
      val @(fz_src, bv_src) = $A.freeze<byte>(piece)
      val xs = lex_spans(bv_src, nbytes, m)
      val seen2 = add_uses(bv_src, m, xs, seen)
      val () = spans_free(xs)
      val () = $A.drop<byte>(fz_src, bv_src)
      val () = whole_free(ar, $A.thaw<byte>(fz_src))
    in seen2 end
  | ~whole_err(_) => seen

(* Adds the #use packages of each file in the NUL-separated list
   files[off, len), in order *)
fun add_files_uses {lf:agz}{off:nat | off <= 524288}{m:nat} .<524288 - off>.
  (files: !$A.borrow(byte, lf, 524288), off: int off, len: int,
   seen: names(m)): [m2:nat] names(m2) =
  if off >= len then seen
  else let
    val e = $S.find_null_bv_at(files, off, 524288)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, 524288, pb)
    val @(pa, _) = $B.to_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val seen2 = add_file_uses(bv_p, seen)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in if e >= 524288 then seen2 else add_files_uses(files, e + 1, len, seen2) end

(* The #use packages of the .bats files under dir, newest first: the
   last one first, as Rust's queue pops them *)
fn collect_uses (dir: $B.builder_v): [m:nat] names(m) = let
  val @(fa, flen) = sorted_bats_files(dir)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val seen = add_files_uses(bv_f, 0, flen, names_nil())
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in seen end

(* ============================================================
   Versions (Rust: find_latest_version, Version's order)
   ============================================================ *)

(* A version: its parts as Rust renders them (no '+', no leading zeros)
   in a[0, len), and whether it is a dev version *)
datavtype cand =
  | {l:agz}{n:nat | n <= 256} cand_mk of ($A.arr(byte, l, 256), int n, bool)

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
  val () = put_bytes(a, 0, l, out)
  val () = put_dev1(out, dev)
  prval () = fold@(c)
in end

(* The first '.' in a[i, e), or e *)
fun dot_at {la:agz}{i,e:nat | i <= e; e <= 256} .<e - i>.
  (a: !$A.arr(byte, la, 256), i: int i, e: int e): [r:int | i <= r; r <= e] int r =
  if i >= e then e
  else if byte2int0($A.get<byte>(a, i)) = 46 then i
  else dot_at(a, i + 1, e)

(* Compares a[i, i + n) and b[j, j + n) byte by byte *)
fun bytes_cmp {la,lb:agz}{i,j,n:nat | i + n <= 256; j + n <= 256} .<n>.
  (a: !$A.arr(byte, la, 256), i: int i, b: !$A.arr(byte, lb, 256), j: int j, n: int n): int =
  if n <= 0 then 0
  else let
    val x = byte2int0($A.get<byte>(a, i))
    val y = byte2int0($A.get<byte>(b, j))
  in
    if x < y then ~1
    else if x > y then 1
    else bytes_cmp(a, i + 1, b, j + 1, n - 1)
  end

(* Compares the parts a[ai, ae) and b[bi, be), rendered without leading
   zeros; an empty (missing) part counts as 0 *)
fn part_cmp {la,lb:agz}{ai,ae,bi,be:nat | ai <= ae; ae <= 256; bi <= be; be <= 256}
  (a: !$A.arr(byte, la, 256), ai: int ai, ae: int ae,
   b: !$A.arr(byte, lb, 256), bi: int bi, be: int be): int = let
  val za = (if ae - ai = 1 then byte2int0($A.get<byte>(a, ai)) = 48 else ae <= ai): bool
  val zb = (if be - bi = 1 then byte2int0($A.get<byte>(b, bi)) = 48 else be <= bi): bool
in
  if za && zb then 0
  else if za then ~1
  else if zb then 1
  else if ae - ai < be - bi then ~1
  else if ae - ai > be - bi then 1
  else bytes_cmp(a, ai, b, bi, ae - ai)
end

(* Compares a[ai, al) and b[bi, bl) part by part, padding the shorter
   with zeros (Rust: Version's Ord) *)
fun parts_cmp {la,lb:agz}{ai,al,bi,bl:nat | ai <= al; al <= 256; bi <= bl; bl <= 256}
  .<(al - ai) + (bl - bi)>.
  (a: !$A.arr(byte, la, 256), ai: int ai, al: int al,
   b: !$A.arr(byte, lb, 256), bi: int bi, bl: int bl): int =
  if ai >= al then
    (if bi >= bl then 0
     else let
       val be = dot_at(b, bi, bl)
       val c = part_cmp(a, ai, ai, b, bi, be)
     in
       if c <> 0 then c
       else if be < bl then parts_cmp(a, ai, al, b, be + 1, bl)
       else parts_cmp(a, ai, al, b, bl, bl)
     end)
  else let
    val ae = dot_at(a, ai, al)
    val be = (if bi < bl then dot_at(b, bi, bl) else bi): [r:int | bi <= r; r <= bl] int r
    val c = part_cmp(a, ai, ae, b, bi, be)
  in
    if c <> 0 then c
    else if ae < al then
      (if be < bl then parts_cmp(a, ae + 1, al, b, be + 1, bl)
       else parts_cmp(a, ae + 1, al, b, bl, bl))
    else
      (if be < bl then parts_cmp(a, al, al, b, be + 1, bl)
       else parts_cmp(a, al, al, b, bl, bl))
  end

(* c against v: ~1, 0 or 1; a dev version orders before the release
   with the same parts (Rust: Version's Ord) *)
fn cand_cmp (c: !cand, v: !cand): int = let
  val+ @cand_mk(ca, cl, cdev) = c
  val+ @cand_mk(va, vl, vdev) = v
  val cmp = parts_cmp(ca, 0, cl, va, 0, vl)
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
  val same = (if cl = vl then bytes_cmp(ca, 0, va, 0, cl) = 0 else false): bool
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
fn file_cand {le:agz} (e: !$A.borrow(byte, le, 1024), vs: pos_t, ve: pos_t): $R.option(cand) = let
  val @(c, _, _) = parse_cand(e, 1024, vs, ve)
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
    cons_cons(n + 1) of ($A.arr(byte, lp, 256), nlen, bool, cand,
                         $A.arr(byte, ls, 256), nlen, cons(n))

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
  (p: !$A.arr(byte, lp, 256), pk: nlen, a: !$A.arr(byte, la, 256), k: nlen): bool =
  if pk <> k then false else bytes_cmp(p, 0, a, 0, k) = 0

(* Whether c meets every constraint on the package a[0, k) *)
fun cons_allow {n:nat}{la:agz} .<n>.
  (cs: !cons(n), a: !$A.arr(byte, la, 256), k: nlen, c: !cand): bool =
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
  (cs: !cons(n), a: !$A.arr(byte, la, 256), k: nlen): bool =
  case+ cs of
  | cons_nil() => false
  | @cons_cons(p, pk, _, _, _, _, rest) => let
      val r = (if name_is(p, pk, a, k) then true else cons_about(rest, a, k)): bool
      prval () = fold@(cs)
    in r end

(* ">= <v> (from <src>)", after ", " when sep (Rust: constraint_display
   and the sources of resolve_all) *)
fn put_con {ls:agz}
  (ge: bool, v: !cand, s: !$A.arr(byte, ls, 256), sk: nlen, sep: bool,
   out: !$B.builder_v >> $B.builder_v): void = let
  val () = (if sep then bput_v(out, ", ") else bput_v(out, ""))
  val () = (if ge then bput_v(out, ">= ") else bput_v(out, "!= "))
  val () = put_cand(v, out)
  val () = bput_v(out, " (from ")
  val () = put_name(s, sk, out)
in bput_v(out, ")") end

fn put_con_if {ls:agz}
  (hit: bool, ge: bool, v: !cand, s: !$A.arr(byte, ls, 256), sk: nlen, sep: bool,
   out: !$B.builder_v >> $B.builder_v): void =
  if hit then put_con(ge, v, s, sk, sep, out) else bput_v(out, "")

(* The constraints on the package a[0, k), each as put_con writes it *)
fun put_cons_of {n:nat}{la:agz} .<n>.
  (cs: !cons(n), a: !$A.arr(byte, la, 256), k: nlen, sep: bool,
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
fun skip_space {lv:agz}{n:pos}{i,e:int} .<max(e - i, 0)>.
  (v: !$A.borrow(byte, lv, n), n: int n, i: int i, e: int e)
  : [r:int | min(i, e) <= r; r <= max(i, e)] int r =
  if i >= e then e
  else if is_space(peek(v, i, n)) then skip_space(v, n, i + 1, e)
  else i

(* e without the whitespace that ends v[s, e) *)
fun trim_end {lv:agz}{n:pos}{s,e:int} .<max(e - s, 0)>.
  (v: !$A.borrow(byte, lv, n), n: int n, s: int s, e: int e)
  : [r:int | min(s, e) <= r; r <= max(s, e)] int r =
  if e <= s then s
  else if is_space(peek(v, e - 1, n)) then trim_end(v, n, s, e - 1)
  else e

(* The first byte c in v[i, e), or e *)
fun find_byte {lv:agz}{n:pos}{i,e:int} .<max(e - i, 0)>.
  (v: !$A.borrow(byte, lv, n), n: int n, i: int i, e: int e, c: int)
  : [r:int | min(i, e) <= r; r <= max(i, e)] int r =
  if i >= e then e
  else if peek(v, i, n) = c then i
  else find_byte(v, n, i + 1, e, c)

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
    val vs = skip_space(v, 4096, s + 2, e)
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
fn name_copy {la:agz} (a: !$A.arr(byte, la, 256), k: nlen): [lb:agz] $A.arr(byte, lb, 256) = let
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
fun parse_cons {lv,lp,ls:agz}{n:nat}{i,e:int} .<max(e - i, 0)>.
  (v: !$A.borrow(byte, lv, 4096), i: int i, e: int e,
   p: !$A.arr(byte, lp, 256), pk: nlen, src: !$A.arr(byte, ls, 256), sk: nlen,
   acc: cons(n), why: !$B.builder_v >> $B.builder_v): [m:nat] @(bool, cons(m)) =
  if i >= e then @(true, acc)
  else let
    val ce = find_byte(v, 4096, i, e, 44)
    val ts = skip_space(v, 4096, i, ce)
    val te = trim_end(v, 4096, ts, ce)
  in
    if ts >= te then parse_cons(v, ce + 1, e, p, pk, src, sk, acc, why)
    else case+ parse_con(v, ts, te, why) of
      | ~$R.some(c) => let
          val+ ~con_mk(ge, cv) = c
          val one = cons_cons(name_copy(p, pk), pk, ge, cv, name_copy(src, sk), sk, cons_nil())
        in parse_cons(v, ce + 1, e, p, pk, src, sk, cons_append(acc, one), why) end
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
  (ok: bool, p: !$A.arr(byte, lp, 256), pk: nlen, why: $B.builder_v,
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
fun load_keys {lk,ls,lsec:agz}{n:nat}{off:nat | off <= 65536} .<65536 - off>.
  (doc: !$T.toml_doc, sec: !$A.borrow(byte, lsec, 12),
   keys: !$A.borrow(byte, lk, 65536), off: int off, len: int,
   src: !$A.arr(byte, ls, 256), sk: nlen,
   acc: cons(n), paths: int, err: !$B.builder_v >> $B.builder_v)
  : [m:nat] @(bool, cons(m), int) =
  if off >= len then @(true, acc, paths)
  else let
    val z = $S.find_null_bv_at(keys, off, 65536)
    val kl = z - off
  in
    if kl <= 0 then
      (if z >= 65536 then @(true, acc, paths)
       else load_keys(doc, sec, keys, z + 1, len, src, sk, acc, paths, err))
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
      val @(ok, acc2) = parse_cons(bv_v, 0, (if is_path then 0 else vl): pos_t, p, pk, src, sk, acc, why)
      val () = $A.drop<byte>(fz_v, bv_v)
      val () = $A.free<byte>($A.thaw<byte>(fz_v))
      val () = put_why(ok, p, pk, why, err)
      val () = $A.free<byte>(p)
      val paths2 = (if is_path then paths + 1 else paths): int
    in
      if ~ok then @(false, acc2, paths2)
      else if z >= 65536 then @(true, acc2, paths2)
      else load_keys(doc, sec, keys, z + 1, len, src, sk, acc2, paths2, err)
    end
  end

(* The constraints of doc's [dependencies], from src[0, sk), and the
   number of its path dependencies (Rust: config::load's dependencies):
   @(1, them, the number), or @(~1, none, 0) after writing Rust's
   "in [dependencies] '<name>': ..." to err *)
fn doc_cons {ls:agz}
  (doc: !$T.toml_doc, src: !$A.arr(byte, ls, 256), sk: nlen,
   err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n), int) = let
  var sec_c = @[char][12]('d', 'e', 'p', 'e', 'n', 'd', 'e', 'n', 'c', 'i', 'e', 's')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 12))
  val kb = $A.alloc<byte>(65536)
  val kr = $T.keys(doc, bv_s, 12, kb, 65536)
  val kl = (case+ kr of | ~$R.some(x) => x | ~$R.none() => 0): int
  val @(fz_kb, bv_kb) = $A.freeze<byte>(kb)
  val @(ok, cs, paths) = load_keys(doc, bv_s, bv_kb, 0, kl, src, sk, cons_nil(), 0, err)
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

(* [package] kind (Rust: config::load), or none after Rust's "unknown
   package kind: '<k>'" in err *)
fn doc_kind (doc: !$T.toml_doc, err: !$B.builder_v >> $B.builder_v): $R.option(package_kind) = let
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
  val kind = (if vl < 0 then $R.some(Library())
              else if vl <> 3 then $R.none()
              else if lit_at(bv_v, 0, 256, lib_c, 3) then $R.some(Library())
              else if lit_at(bv_v, 0, 256, bin_c, 3) then $R.some(Binary())
              else $R.none()): $R.option(package_kind)
  val () = put_unknown_kind($R.is_none<package_kind>(kind), bv_v, vl, err)
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
in kind end

#define VMAX 524288

(* The number of decimal digits of n > 0 *)
fun digits {n:nat} .<n>. (n: int n): [d:pos] int d =
  if n < 10 then 1 else 1 + digits(ndiv(n, 10))

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

(* ============================================================
   bats.toml read as Rust's serde reads it into Package (config::load):
   the first field of the wrong type, else a missing name or package,
   as the toml crate reports them
   ============================================================ *)

(* 1-based line and column of offset off in doc's text, with the offset
   its line starts at *)
fun doc_line_col {i,off:int}{l:pos} .<max(off - i, 0)>.
  (doc: !$T.toml_doc, i: int i, off: int off, line: int l, col: pos_t, ls: pos_t)
  : @([l2:pos] int l2, pos_t, pos_t) =
  if i >= off then @(line, col, ls)
  else if $T.byte_at(doc, i) = 10 then doc_line_col(doc, i + 1, off, line + 1, 1, i + 1)
  else doc_line_col(doc, i + 1, off, line, col + 1, ls)

(* The most text a toml_doc holds (the toml's TOML_MAX_BUF): byte_at is
   ~1 from there on *)
#define DOC_MAX 65536

(* The end of the line starting at or holding i: its newline, or the end
   of the text *)
fun doc_line_end {i:int} .<max(DOC_MAX - i, 0)>. (doc: !$T.toml_doc, i: int i): pos_t =
  if i >= DOC_MAX then i
  else let val c = $T.byte_at(doc, i) in
    if c < 0 then i else if c = 10 then i else doc_line_end(doc, i + 1)
  end

(* doc's text [i, e) appended to out *)
fun put_doc {i,e:int} .<max(e - i, 0)>.
  (doc: !$T.toml_doc, i: int i, e: int e, out: !$B.builder_v >> $B.builder_v): void =
  if i >= e then ()
  else let
    val () = put_char_v(out, $T.byte_at(doc, i))
  in put_doc(doc, i + 1, e, out) end

fun put_n {k:int} .<max(k, 0)>. (c: int, k: int k, out: !$B.builder_v >> $B.builder_v): void =
  if k <= 0 then ()
  else let val () = put_char_v(out, c) in put_n(c, k - 1, out) end

(* The toml crate's error for the span [s, e) of doc, with the message
   msg, after "parse error in './bats.toml': " (config::load) *)
fn put_toml_error (doc: !$T.toml_doc, s: pos_t, e: pos_t, msg: $B.builder_v,
   err: !$B.builder_v >> $B.builder_v): void = let
  val @(line, col, ls) = doc_line_col(doc, 0, s, 1, 1, 0)
  val le = doc_line_end(doc, ls)
  val stop = (if e < le then e else le): pos_t
  val carets = (if stop - s > 0 then stop - s else 1): pos_t
  val pad = digits(line)
  val () = bput_v(err, "parse error in './bats.toml': TOML parse error at line ")
  val () = put_int_v(err, line)
  val () = bput_v(err, ", column ")
  val () = put_int_v(err, col)
  val () = put_char_v(err, 10)
  val () = put_n(32, pad + 1, err)
  val () = bput_v(err, "|\n")
  val () = put_int_v(err, line)
  val () = bput_v(err, " | ")
  val () = put_doc(doc, ls, le, err)
  val () = put_char_v(err, 10)
  val () = put_n(32, pad + 1, err)
  val () = bput_v(err, "| ")
  val () = put_n(32, col - 1, err)
  val () = put_n(94, carets, err)
  val () = put_char_v(err, 10)
  val () = append_builder(err, msg)
in put_char_v(err, 10) end

(* Whether doc's text at [s, e) spells the k characters of lit *)
fun doc_is {m:pos}{j:nat | j <= m} .<m - j>.
  (doc: !$T.toml_doc, s: pos_t, e: pos_t, lit: &(@[char][m]), j: int j, m: int m): bool =
  if j >= m then s + j = e
  else if s + j >= e then false
  else if $T.byte_at(doc, s + j) <> char2int0(lit[j]) then false
  else doc_is(doc, s, e, lit, j + 1, m)

(* Whether doc's text [i, e) is an integer: a sign, then digits and _ *)
fun doc_int {i,e:int} .<max(e - i, 0)>. (doc: !$T.toml_doc, i: int i, e: int e, seen: bool): bool =
  if i >= e then seen
  else let val c = $T.byte_at(doc, i) in
    if c = 95 then doc_int(doc, i + 1, e, seen)
    else if c >= 48 then (if c <= 57 then doc_int(doc, i + 1, e, true) else false)
    else false
  end

(* The digit c, or nothing for the _ that TOML allows between digits *)
fn put_digit (c: int, out: !$B.builder_v >> $B.builder_v): void =
  if c = 95 then bput_v(out, "") else put_char_v(out, c)

(* doc's digits in [i, e), without the _ that TOML allows between them *)
fun put_digits {i,e:int} .<max(e - i, 0)>.
  (doc: !$T.toml_doc, i: int i, e: int e, out: !$B.builder_v >> $B.builder_v): void =
  if i >= e then ()
  else let
    val c = $T.byte_at(doc, i)
    val () = put_digit(c, out)
  in put_digits(doc, i + 1, e, out) end


(* What a [package] value is to serde: a quoted string, or a bare true,
   false, sequence, map, integer or float, or none of them (the toml
   crate rejects it as an invalid string) *)
datatype value_class =
  | QuotedString | TrueValue | FalseValue | SequenceValue | MapValue
  | IntegerValue | FloatValue | NotAValue

(* What the bare value doc[s, e) is to serde *)
fn value_class (doc: !$T.toml_doc, s: pos_t, e: pos_t): value_class = let
  var t_c = @[char][4]('t', 'r', 'u', 'e')
  var f_c = @[char][5]('f', 'a', 'l', 's', 'e')
  val c = $T.byte_at(doc, s)
  val sgn = (if c = 43 then 1 else if c = 45 then 1 else 0): pos_t
  val d = $T.byte_at(doc, s + sgn)
in
  if doc_is(doc, s, e, t_c, 0, 4) then TrueValue()
  else if doc_is(doc, s, e, f_c, 0, 5) then FalseValue()
  else if c = 91 then SequenceValue()
  else if c = 123 then MapValue()
  else if doc_int(doc, s + sgn, e, false) then IntegerValue()
  else if d >= 48 then (if d <= 57 then FloatValue() else NotAValue())
  else NotAValue()
end

(* serde's words for a bare value of class cls at doc[s, e) (a float's
   for one that is none of the others, as before) *)
fn put_class (cls: value_class, doc: !$T.toml_doc, s: pos_t, e: pos_t, out: !$B.builder_v >> $B.builder_v): void =
  case+ cls of
  | TrueValue() => bput_v(out, "boolean `true`")
  | FalseValue() => bput_v(out, "boolean `false`")
  | SequenceValue() => bput_v(out, "sequence")
  | MapValue() => bput_v(out, "map")
  | IntegerValue() => let
      val c = $T.byte_at(doc, s)
      val () = bput_v(out, "integer `")
      val () = put_digit((if c = 45 then 45 else 95): int, out)
      val () = put_digits(doc, (if c = 43 then s + 1 else if c = 45 then s + 1 else s): pos_t, e, out)
    in put_char_v(out, 96) end
  | _ => let
      val () = bput_v(out, "floating point `")
      val () = put_doc(doc, s, e, out)
    in put_char_v(out, 96) end

(* What is wrong with a [package] value: nothing (or there is no such
   key), a value of the wrong type, or a bare value that is no TOML
   value *)
datatype field_problem = NoProblem | WrongType | NotTomlValue

(* Whether there is a problem *)
fn is_problem (bad: field_problem): bool = case+ bad of NoProblem() => false | _ => true

(* The span of [package] key's value and what is wrong with it *)
fn field_problem {kk:pos | kk <= 1048576}
  (doc: !$T.toml_doc, kc: &(@[char][kk]), kk: int kk, want_bool: bool): @(pos_t, pos_t, field_problem) = let
  var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(kc, kk))
  val @(s, e, quoted) = $T.value_at(doc, bv_s, 7, bv_k, kk)
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
  val s1 = (if s < 0 then 0 else s): pos_t
  val e1 = (if e < 0 then 0 else e): pos_t
  val bad = (if s < 0 then NoProblem()
    else let
      val cls = (if quoted then QuotedString() else value_class(doc, s1, e1)): value_class
    in
      case+ cls of
      | NotAValue() => NotTomlValue()
      | TrueValue() => (if want_bool then NoProblem() else WrongType())
      | FalseValue() => (if want_bool then NoProblem() else WrongType())
      | QuotedString() => (if want_bool then WrongType() else NoProblem())
      | _ => WrongType()
    end): field_problem
in @(s1, e1, bad) end

(* serde's words for the value at doc[s, e): a string's, quoted, or a
   bare value's class *)
fn put_type (quoted: bool, doc: !$T.toml_doc, s: pos_t, e: pos_t, m: !$B.builder_v >> $B.builder_v): void =
  if quoted then let
    val () = bput_v(m, "string \"")
    val () = put_doc(doc, s + 1, e - 1, m)
  in put_char_v(m, 34) end
  else put_class(value_class(doc, s, e), doc, s, e, m)

(* The message for problem bad of the value at doc[s, e), appended to m;
   want_bool says which type serde expected *)
fn problem_msg (doc: !$T.toml_doc, s: pos_t, e: pos_t, bad: field_problem, want_bool: bool,
   m: !$B.builder_v >> $B.builder_v): void =
  if (case+ bad of NotTomlValue() => true | _ => false) then bput_v(m, "invalid string\nexpected `\"`, `'`")
  else let
    val q = $T.byte_at(doc, s)
    val quoted = (if q = 34 then true else q = 39): bool
    val () = bput_v(m, "invalid type: ")
    val () = put_type(quoted, doc, s, e, m)
  in
    if want_bool then bput_v(m, ", expected a boolean") else bput_v(m, ", expected a string")
  end

(* Whether [package] has key *)
fn has_field {kk:pos | kk <= 1048576} (doc: !$T.toml_doc, kc: &(@[char][kk]), kk: int kk): bool = let
  var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(kc, kk))
  val @(s, _, _) = $T.value_at(doc, bv_s, 7, bv_k, kk)
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in s >= 0 end

(* The earlier of two problems @(start, end, bad, want_bool) *)
fn first_problem (a: @(pos_t, pos_t, field_problem, bool), b: @(pos_t, pos_t, field_problem, bool)): @(pos_t, pos_t, field_problem, bool) =
  if ~is_problem(a.2) then b
  else if ~is_problem(b.2) then a
  else if b.0 < a.0 then b
  else a

(* What a check of bats.toml found: nothing wrong, a problem (a value's,
   or a syntax error), no [package], or no name *)
datatype manifest_check = Fine | Problem | NoPackage | NoName

(* The message for a check's outcome: the problem p, no [package], no
   name *)
fn put_problem (kind: manifest_check, doc: !$T.toml_doc, p: @(pos_t, pos_t, field_problem, bool),
   m: !$B.builder_v >> $B.builder_v): void =
  case+ kind of
  | Problem() => problem_msg(doc, p.0, p.1, p.2, p.3, m)
  | NoPackage() => bput_v(m, "missing field `package`")
  | NoName() => bput_v(m, "missing field `name`")
  | Fine() => ()

(* Whether a check found nothing; else its error, the message m at
   doc[s, e), goes to err. Consumes m *)
fn finish_check (kind: manifest_check, doc: !$T.toml_doc, s: pos_t, e: pos_t, m: $B.builder_v,
   err: !$B.builder_v >> $B.builder_v): bool =
  case+ kind of
  | Fine() => let val () = $B.builder_free(m) in true end
  | _ => let val () = put_toml_error(doc, s, e, m, err) in false end

(* Rust's config::load of doc as serde reads it into TomlConfig: the
   first [package] field of the wrong type, in the file's order, else a
   missing [package], else a missing name, written to err as the toml
   crate reports it; whether there was none *)
(* The toml crate's syntax error in doc, if any, to err (config::load's
   toml::from_str fails before serde reads a field); whether there was
   none *)
fn syntax_check (doc: !$T.toml_doc, err: !$B.builder_v >> $B.builder_v): bool = let
  val mb = $A.alloc<byte>(512)
  val @(off, k) = $T.syntax_error(doc, mb, 512)
  val @(fz_m, bv_m) = $A.freeze<byte>(mb)
  var m : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv_m, 0, k, 512, m)
  val () = $A.drop<byte>(fz_m, bv_m)
  val () = $A.free<byte>($A.thaw<byte>(fz_m))
  val s = (if off < 0 then 0 else off): pos_t
in finish_check((if off < 0 then Fine() else Problem()): manifest_check, doc, s, s, m, err) end

fn serde_check (doc: !$T.toml_doc, err: !$B.builder_v >> $B.builder_v): bool = let
  var n_c = @[char][4]('n', 'a', 'm', 'e')
  var k_c = @[char][4]('k', 'i', 'n', 'd')
  var v_c = @[char][7]('v', 'e', 'r', 's', 'i', 'o', 'n')
  var t_c = @[char][5]('t', 'r', 'u', 'n', 'k')
  var u_c = @[char][6]('u', 'n', 's', 'a', 'f', 'e')
  var a_c = @[char][4]('a', 't', 's', '2')
  val @(s1, e1, b1) = field_problem(doc, n_c, 4, false)
  val @(s2, e2, b2) = field_problem(doc, k_c, 4, false)
  val @(s3, e3, b3) = field_problem(doc, v_c, 7, false)
  val @(s4, e4, b4) = field_problem(doc, t_c, 5, false)
  val @(s5, e5, b5) = field_problem(doc, u_c, 6, true)
  val @(s6, e6, b6) = field_problem(doc, a_c, 4, false)
  val p = first_problem(@(s1, e1, b1, false), @(s2, e2, b2, false))
  val p = first_problem(p, @(s3, e3, b3, false))
  val p = first_problem(p, @(s4, e4, b4, false))
  val p = first_problem(p, @(s5, e5, b5, true))
  val p = first_problem(p, @(s6, e6, b6, false))
  var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
  val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
  val @(hs, he) = $T.section_at(doc, bv_s, 7)
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
  val named = has_field(doc, n_c, 4)
  var m : $B.builder_v = $B.create()
  val kind = (if is_problem(p.2) then Problem() else if hs < 0 then NoPackage()
              else if ~named then NoName() else Fine()): manifest_check
  val () = put_problem(kind, doc, p, m)
  val sp = (case+ kind of
    | Problem() => p.0
    | NoName() => (if hs < 0 then 0 else hs)
    | _ => 0): pos_t
  val ep = (case+ kind of
    | Problem() => (case+ p.2 of NotTomlValue() => p.0 | _ => p.1)
    | NoName() => he
    | _ => (if $T.has_root_keys(doc) then 65536 else 0)): pos_t
in finish_check(kind, doc, sp, ep, m, err) end

(* The constraints of doc (Rust: config::load), from src[0, sk):
   @(1, them), or @(~1, none) after writing Rust's message to err: a
   field of the wrong type or a missing one, an unknown kind, a constraint that does not parse, or a path dependency
   in a lib package, in that order *)
fn config_cons {ls:agz}
  (doc: !$T.toml_doc, src: !$A.arr(byte, ls, 256), sk: nlen,
   err: !$B.builder_v >> $B.builder_v): [n:nat] @(int, cons(n)) = let
  val ok = (if syntax_check(doc, err) then serde_check(doc, err) else false): bool
  val kind = (if ok then doc_kind(doc, err) else $R.none()): $R.option(package_kind)
in
  case+ kind of
  | ~$R.none() => @(~1, cons_nil())
  | ~$R.some(known) => let
    val @(st, cs, paths) = doc_cons(doc, src, sk, err)
  in
    if st < 0 then @(~1, cs)
    else (case+ known of
      | Library() =>
        (if paths > 0 then let
           val () = cons_free(cs)
           val () = bput_v(err, "path dependencies are only supported in binary packages (kind = \"bin\")")
         in @(~1, cons_nil()) end
         else @(1, cs))
      | Binary() => @(1, cs))
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
      val @(tn, e) = (case+ rr of | ~$R.ok(k) => @(k, 0) | ~$R.err(e) => @(0, e)): @([k:nat | k <= 65536] int k, int)
      val @(fz_t, bv_t) = $A.freeze<byte>(tb)
      val pr = $T.parse(bv_t, tn)
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
  val () = put_int_v(err, e)
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
        | ~$R.some(x) => x | ~$R.none() => 0): nlen
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
fn dep_cons {la:agz} (a: !$A.arr(byte, la, 256), k: nlen): [n:nat] cons(n) = let
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
fn unsatisfied {n:nat}{la:agz} (cs: !cons(n), a: !$A.arr(byte, la, 256), k: nlen): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: no version of '")
  val () = put_name(a, k, m)
  val () = bput_v(m, "' satisfies all constraints: ")
  val () = put_cons_of(cs, a, k, false, m)
  val () = put_char_v(m, 10)
in prerr_builder(m) end

(* Whether the file name e[0, el) is <pfx><version>.bats *)
fn is_archive_of {le,lp:agz}
  (e: !$A.borrow(byte, le, 1024), el: pos_t,
   pfx: !$A.borrow(byte, lp, 524288), pl: pos_t): bool = let
  var b_c = @[char][5]('.', 'b', 'a', 't', 's')
  fun starts {i,pl:int} .<max(pl - i, 0)>.
    (e: !$A.borrow(byte, le, 1024), pfx: !$A.borrow(byte, lp, 524288),
     i: int i, pl: int pl): bool =
    if i >= pl then true
    else if $AR.eq_int_int(peek(e, i, 1024), peek(pfx, i, 524288))
    then starts(e, pfx, i + 1, pl)
    else false
in
  if el < pl + 6 then false
  else if ~lit_at(e, el - 5, 1024, b_c, 5) then false
  else starts(e, pfx, 0, pl)
end

(* The newest version among the archives in the directory d whose names
   start with pfx[0, pl) that meets the constraints cs on the package
   a[0, k); dev versions only when dev *)
fun scan_versions {n,i:nat | i <= n}{lp,la:agz}{nc:nat} .<n - i>.
  (d: !$F.entries(n), i: int i, n: int n, pfx: !$A.borrow(byte, lp, 524288), pl: pos_t, dev: bool,
   cs: !cons(nc), a: !$A.arr(byte, la, 256), k: nlen,
   best: $R.option(cand)): $R.option(cand) =
  if i >= n then best
  else let
    val e = $A.alloc<byte>(1024)
    val el = $F.entries_name(d, i, e, 1024)
  in
    let
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
    in scan_versions(d, i + 1, n, pfx, pl, dev, cs, a, k, best2) end
  end

(* The name a[0, k) with '/' made '_', then '_' (Rust: package_to_prefix) *)
fun put_prefix {la:agz}{i:nat | i <= 256} .<256 - i>.
  (a: !$A.arr(byte, la, 256), i: int i, k: nlen, out: !$B.builder_v >> $B.builder_v): void =
  if i >= k then put_char_v(out, 95)
  else let
    val c = byte2int0($A.get<byte>(a, i))
    val () = put_char_v(out, (if c = 47 then 95 else c): int)
  in put_prefix(a, i + 1, k, out) end

(* repo[0, rl) / name *)
fn put_pkg_dir {lr,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: nlen,
   out: !$B.builder_v >> $B.builder_v): void = let
  val () = copy_to_builder_v(repo, 0, rl, 4096, out)
  val () = put_char_v(out, 47)
in put_name(a, k, out) end

(* The newest version of the package a[0, k) in the repository that meets
   the constraints cs (Rust: find_latest_version) *)
fn find_latest {lr,la:agz}{nc:nat}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: nlen,
   dev: bool, cs: !cons(nc)): $R.option(cand) = let
  var dp : $B.builder_v = $B.create()
  val () = put_pkg_dir(repo, rl, a, k, dp)
  val () = put_char_v(dp, 0)
  val @(da, _) = $B.to_arr(dp)
  val @(fz_d, bv_d) = $A.freeze<byte>(da)
  val dr = $F.dir_read(bv_d, 524288)
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
  var pb : $B.builder_v = $B.create()
  val () = put_prefix(a, 0, k, pb)
  val pl = $B.length(pb)
  val @(pa, _) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val r = (case+ dr of
    | ~$R.ok(d) => let
        val best = scan_versions(d, 0, $F.entries_count(d), bv_p, pl, dev, cs, a, k, $R.none())
        val () = $F.entries_free(d)
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
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: nlen,
   v: !cand): @([lo:agz] $A.arr(byte, lo, 524288), int) = let
  var p : $B.builder_v = $B.create()
  val () = put_pkg_dir(repo, rl, a, k, p)
  val () = put_char_v(p, 47)
  val () = put_prefix(a, 0, k, p)
  val () = put_cand(v, p)
  val () = bput_v(p, ".bats")
  val plen = $B.length(p)
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in @(pa, plen) end

(* Whether bats_modules/<name>/src/lib.bats exists *)
fn is_fetched {la:agz} (a: !$A.arr(byte, la, 256), k: nlen): bool = let
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

(* bats_modules/<a[0, k)>/.bats-version, NUL-terminated, and its length
   without the NUL: the version fetch unpacked there *)
fn stamp_path {la:agz} (a: !$A.arr(byte, la, 256), k: nlen): @([lo:agz] $A.arr(byte, lo, 524288), int) = let
  var p : $B.builder_v = $B.create()
  val () = bput_v(p, "bats_modules/")
  val () = put_name(a, k, p)
  val () = bput_v(p, "/.bats-version")
  val plen = $B.length(p)
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in @(pa, plen) end

(* The version in the file of s[0, n) trimmed, when it parses *)
fn text_cand {ls:agz}{m:pos}{n:nat} (s: !$A.borrow(byte, ls, m), m: int m, n: int n): $R.option(cand) = let
  val e = trim_end(s, m, 0, n)
  val @(c, _, _) = parse_cand(s, m, 0, e)
in c end

(* Whether c is v, when there is a c; frees c *)
fn cand_is (c: $R.option(cand), v: !cand): bool =
  case+ c of
  | ~$R.some(cv) => let
      val same = cand_same(cv, v)
      val () = cand_free(cv)
    in same end
  | ~$R.none() => false

(* Whether bats_modules/<a[0, k)>'s bats.toml's [package] version is v *)
fn toml_version_is {la:agz} (a: !$A.arr(byte, la, 256), k: nlen, v: !cand): bool = let
  var p : $B.builder_v = $B.create()
  val () = bput_v(p, "bats_modules/")
  val () = put_name(a, k, p)
  val () = bput_v(p, "/bats.toml")
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in
  case+ read_toml(pa) of
  | ~$R.err(_) => false
  | ~$R.ok(doc) => let
      var section_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
      val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(section_c, 7))
      var key_c = @[char][7]('v', 'e', 'r', 's', 'i', 'o', 'n')
      val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 7))
      val version = $A.alloc<byte>(256)
      val version_len = (case+ $T.get(doc, bv_s, 7, bv_k, 7, version, 256) of
        | ~$R.some(x) => x | ~$R.none() => 0): nlen
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
      val () = $T.toml_free(doc)
      val @(fz_v, bv_v) = $A.freeze<byte>(version)
      val @(c, _, _) = parse_cand(bv_v, 256, 0, version_len)
      val () = $A.drop<byte>(fz_v, bv_v)
      val () = $A.free<byte>($A.thaw<byte>(fz_v))
    in cand_is(c, v) end
end

(* Whether bats_modules/<a[0, k)> holds the version v of the package:
   fetch's stamp says so, or, without one (a package unpacked otherwise),
   its bats.toml's version is v *)
fn installed_at {la:agz} (a: !$A.arr(byte, la, 256), k: nlen, v: !cand): bool = let
  val @(pa, _) = stamp_path(a, k)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val r = (case+ read_whole(bv_p, 524288) of
    | ~whole_ok(ar, piece, m, nbytes) => let
        val @(fz_s, bv_s) = $A.freeze<byte>(piece)
        val c = text_cand(bv_s, m, nbytes)
        val () = $A.drop<byte>(fz_s, bv_s)
        val () = whole_free(ar, $A.thaw<byte>(fz_s))
      in cand_is(c, v) end
    | ~whole_err(_) => toml_version_is(a, k, v)): bool
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in r end

(* m to stderr unless quiet; consumes m *)
fn say (m: $B.builder_v): void =
  if is_quiet() then $B.builder_free(m) else prerr_builder(m)

(* Unpacks the archive arc[0, alen) into bats_modules/<name> and says so
   (Rust: fetch_package) *)
fn fetch {lc,la:agz}
  (arc: !$A.borrow(byte, lc, 524288), alen: int,
   a: !$A.arr(byte, la, 256), k: nlen, v: !cand): void = let
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
  (* The stamp installed_at reads *)
  val @(sa, slen) = stamp_path(a, k)
  val @(fz_s, bv_s) = $A.freeze<byte>(sa)
  var stamp : $B.builder_v = $B.create()
  val () = put_cand(v, stamp)
  val () = put_char_v(stamp, 10)
  val _ = write_file_from_builder(bv_s, 524288, stamp)
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
  var msg : $B.builder_v = $B.create()
  val () = bput_v(msg, "fetched ")
  val () = put_name(a, k, msg)
  val () = bput_v(msg, " v")
  val () = put_cand(v, msg)
  val () = put_char_v(msg, 10)
in say(msg) end

(* fetch, into an emptied bats_modules/<name> *)
fn refetch {lc,la:agz}
  (arc: !$A.borrow(byte, lc, 524288), alen: int,
   a: !$A.arr(byte, la, 256), k: nlen, v: !cand): void = let
  var dir : $B.builder_v = $B.create()
  val () = bput_v(dir, "bats_modules/")
  val () = put_name(a, k, dir)
  val () = remove_tree(dir)
in fetch(arc, alen, a, k, v) end

(* The #use packages of bats_modules/<name>/src, newest first *)
fn dep_uses {la:agz} (a: !$A.arr(byte, la, 256), k: nlen): [m:nat] names(m) = let
  var d : $B.builder_v = $B.create()
  val () = bput_v(d, "bats_modules/")
  val () = put_name(a, k, d)
  val () = bput_v(d, "/src")
in collect_uses(d) end

(* Rust's "package '<name>' not found in repository '<repo>'" *)
fn not_found {lr,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: nlen): void = let
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
  (arc: !$A.borrow(byte, lc, 524288), a: !$A.arr(byte, la, 256), k: nlen, v: !cand,
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
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: nlen,
   cs: !cons(nc)): void =
  if cons_about(cs, a, k) then unsatisfied(cs, a, k) else not_found(repo, rl, a, k)

(* ============================================================
   The packages of the repository: what resolve_all can resolve
   ============================================================ *)

(* The last '/' in lst[i, e), or r when there is none *)
fun last_slash {l:agz}{i,e:int}{r:int} .<max(e - i, 0)>.
  (lst: !$A.borrow(byte, l, VMAX), i: int i, e: int e, r: int r): pos_t =
  if i >= e then r
  else last_slash(lst, i + 1, e, (if peek(lst, i, VMAX) = 47 then i else r): pos_t)

(* acc, with the package of the archive path lst[s, e) added:
   <repo>/<name>/<archive>, whose <repo>/ is rl + 1 bytes *)
fn repo_add {l:agz}{m:nat}
  (lst: !$A.borrow(byte, l, VMAX), s: pos_t, e: pos_t, rl: pos_t, acc: names(m)): [m2:nat] names(m2) = let
  val ns = s + rl + 1
  val ne = last_slash(lst, ns, e, ns)
in
  if ne <= ns then acc
  else let
    val a = $A.alloc<byte>(256)
    val k = copy_name(lst, ns, ne, VMAX, a, 0)
  in
    if k <= 0 then let
      val () = $A.free<byte>(a)
    in acc end
    else names_cons(a, k, acc)
  end
end

fun repo_names {l:agz}{off:nat | off <= VMAX}{m:nat} .<VMAX - off>.
  (lst: !$A.borrow(byte, l, VMAX), off: int off, len: int, rl: pos_t, acc: names(m)): [m2:nat] names(m2) =
  if off >= len then acc
  else let
    val e = $S.find_null_bv_at(lst, off, VMAX)
    val acc2 = repo_add(lst, off, e, rl, acc)
  in if e >= VMAX then acc2 else repo_names(lst, e + 1, len, rl, acc2) end

(* The package of each archive under the repository repo[0, rl), once
   per archive: find_latest finds a version only of one of them *)
fn repo_packages {lr:agz} (repo: !$A.borrow(byte, lr, 4096), rl: int): [u:nat] names(u) = let
  var d : $B.builder_v = $B.create()
  val () = copy_to_builder_v(repo, 0, rl, 4096, d)
  val dl = $B.length(d)
  val @(fa, flen) = sorted_bats_files(d)
  val @(fz, bv) = $A.freeze<byte>(fa)
  val xs = repo_names(bv, 0, flen, dl, names_nil())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in xs end

(* xs without one entry that is the name a[0, k), when it has one *)
datavtype ntaken(int) =
  | {u:nat} NTaken(u + 1) of names(u)
  | {u:nat} NMissed(u) of names(u)

fun names_take {u:nat}{la:agz}{k:pos | k <= 256} .<u>.
  (xs: names(u), a: !$A.arr(byte, la, 256), k: int k): ntaken(u) =
  case+ xs of
  | ~names_nil() => NMissed(names_nil())
  | ~names_cons(b, kb, tl) =>
    if (if kb = k then same_name(b, a, k, 0) else false) then let
      val () = $A.free<byte>(b)
    in NTaken(tl) end
    else (case+ names_take(tl, a, k) of
      | ~NTaken(r) => NTaken(names_cons(b, kb, r))
      | ~NMissed(r) => NMissed(names_cons(b, kb, r)))

(* Resolves the packages on stack, the newest first, into lock lines,
   skipping the path dependencies pn; all holds every package queued so
   far, cs the constraints read so far, avail the packages of the
   repository not yet resolved (repo_packages): each package resolved
   is taken out of it, so the resolution ends.
   @(0 or ~1 on an error, the number resolved) (Rust: resolve_all) *)
fun resolve_all {s,m,nc,np,u:nat}{lr:agz} .<u, s>.
  (stack: names(s), all: names(m), cs: cons(nc), pn: !names(np), avail: names(u),
   repo: !$A.borrow(byte, lr, 4096), rl: int,
   dev: bool, lock: !$B.builder_v >> $B.builder_v, count: int): @(int, int) =
  case+ stack of
  | ~names_nil() => let
      val () = names_free(all)
      val () = cons_free(cs)
      val () = names_free(avail)
    in @(0, count) end
  | ~names_cons(a, k, rest) =>
    (* A path dependency is not resolved from the repository *)
    if names_has(pn, a, k) then let
      val () = $A.free<byte>(a)
    in resolve_all(rest, all, cs, pn, avail, repo, rl, dev, lock, count) end
    else (case+ names_take(avail, a, k) of
      (* Not among the repository's packages: it has no version *)
      | ~NMissed(avail2) => let
          val () = no_version(repo, rl, a, k, cs)
          val () = $A.free<byte>(a)
          val () = names_free(rest)
          val () = names_free(all)
          val () = cons_free(cs)
          val () = names_free(avail2)
        in @(~1, count) end
      | ~NTaken(avail2) => (case+ find_latest(repo, rl, a, k, dev, cs) of
        | ~$R.none() => let
            val () = no_version(repo, rl, a, k, cs)
            val () = $A.free<byte>(a)
            val () = names_free(rest)
            val () = names_free(all)
            val () = cons_free(cs)
            val () = names_free(avail2)
          in @(~1, count) end
        | ~$R.some(v) => let
            val @(arc, alen) = archive_path(repo, rl, a, k, v)
            val @(fz_c, bv_c) = $A.freeze<byte>(arc)
            (* What bats_modules holds of another version is replaced *)
            val () = (if installed_at(a, k, v) then () else refetch(bv_c, alen, a, k, v))
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
            if ok then resolve_all(stack2, all2, cs2, pn, avail2, repo, rl, dev, lock, count + 1)
            else let
              val () = names_free(stack2)
              val () = names_free(all2)
              val () = cons_free(cs2)
              val () = names_free(avail2)
            in @(~1, count) end
          end))

(* ============================================================
   bats lock --dry-run (Rust: read_lockfile, print_diff)
   ============================================================ *)

(* Lock text: bats.lock's bytes or the lines resolve_all wrote *)
#define LOCK_MAX 524288

(* The next line of t after i: @(its trimmed [start, end), where it
   ends) (Rust: lines() and trim()) *)
fn lock_line {lt:agz}{tl,i:int}
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: int tl, i: int i)
  : [le:int | min(i, tl) <= le; le <= max(i, tl)] @(pos_t, pos_t, int le) = let
  val le = find_byte(t, LOCK_MAX, i, tl, 10)
  val ts = skip_space(t, LOCK_MAX, i, le)
  val te = trim_end(t, LOCK_MAX, ts, le)
in @(ts, te, le) end

(* The ends of the package and of the version of the lock line t[s, e):
   the package ends at the first space, the version at the next one or
   at e (Rust: splitn(3, ' ')); a line without a space has no version *)
fn lock_fields {lt:agz}
  (t: !$A.borrow(byte, lt, LOCK_MAX), s: pos_t, e: pos_t): @(pos_t, pos_t) = let
  val pe = find_byte(t, LOCK_MAX, s, e, 32)
  val ve = (if pe < e then find_byte(t, LOCK_MAX, pe + 1, e, 32) else e): pos_t
in @(pe, ve) end

(* Whether a[i, i + k) = b[j, j + k) *)
fun lock_bytes_eq {la,lb:agz}{k:int} .<max(k, 0)>.
  (a: !$A.borrow(byte, la, LOCK_MAX), i: pos_t, b: !$A.borrow(byte, lb, LOCK_MAX), j: pos_t,
   k: int k): bool =
  if k <= 0 then true
  else if peek(a, i, LOCK_MAX) <> peek(b, j, LOCK_MAX) then false
  else lock_bytes_eq(a, i + 1, b, j + 1, k - 1)

(* Whether a[a0, a1) = b[b0, b1) *)
fn lock_range_eq {la,lb:agz}
  (a: !$A.borrow(byte, la, LOCK_MAX), a0: pos_t, a1: pos_t,
   b: !$A.borrow(byte, lb, LOCK_MAX), b0: pos_t, b1: pos_t): bool =
  if a1 - a0 <> b1 - b0 then false
  else lock_bytes_eq(a, a0, b, b0, a1 - a0)

(* The version of the first line of t[i, tl) whose package is
   u[xs, xe), or @(~1, ~1) *)
fun lock_find {lt,lu:agz}{tl,i:int} .<max(tl - i, 0)>.
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: int tl, i: int i,
   u: !$A.borrow(byte, lu, LOCK_MAX), xs: pos_t, xe: pos_t): @(pos_t, pos_t) =
  if i >= tl then @(~1, ~1)
  else let
    val @(ts, te, le) = lock_line(t, tl, i)
  in
    if ts >= te then lock_find(t, tl, le + 1, u, xs, xe)
    else let
      val @(pe, ve) = lock_fields(t, ts, te)
    in
      if pe < te then
        (if lock_range_eq(t, ts, pe, u, xs, xe) then @(pe + 1, ve)
         else lock_find(t, tl, le + 1, u, xs, xe))
      else lock_find(t, tl, le + 1, u, xs, xe)
    end
  end

(* The first line of t[i, tl) without a space, trimmed, or @(~1, ~1)
   (Rust: read_lockfile's "malformed lockfile line") *)
fun lock_malformed {lt:agz}{tl,i:int} .<max(tl - i, 0)>.
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: int tl, i: int i): @(pos_t, pos_t) =
  if i >= tl then @(~1, ~1)
  else let
    val @(ts, te, le) = lock_line(t, tl, i)
  in
    if ts >= te then lock_malformed(t, tl, le + 1)
    else let
      val @(pe, _) = lock_fields(t, ts, te)
    in
      if pe >= te then @(ts, te)
      else lock_malformed(t, tl, le + 1)
    end
  end

(* "  + <pkg> v<new>" or "  ~ <pkg> v<old> -> v<new>" for the new lock
   line u[s, e) against old[0, ol); whether it wrote one *)
fn note_new {lu,lo:agz}
  (u: !$A.borrow(byte, lu, LOCK_MAX), s: pos_t, e: pos_t,
   old: !$A.borrow(byte, lo, LOCK_MAX), ol: pos_t,
   out: !$B.builder_v >> $B.builder_v): bool = let
  val @(pe, ve) = lock_fields(u, s, e)
  val @(os, oe) = lock_find(old, ol, 0, u, s, pe)
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
  val @(ns, _) = lock_find(nw, nl, 0, o, s, pe)
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
fun lock_notes {la,lb:agz}{al,i:int} .<max(al - i, 0)>.
  (a: !$A.borrow(byte, la, LOCK_MAX), al: int al, i: int i,
   b: !$A.borrow(byte, lb, LOCK_MAX), bl: pos_t, fresh: bool, changed: bool,
   out: !$B.builder_v >> $B.builder_v): bool =
  if i >= al then changed
  else let
    val @(ts, te, le) = lock_line(a, al, i)
    val c = note_line(a, ts, te, b, bl, fresh, out)
  in lock_notes(a, al, le + 1, b, bl, fresh, (if c then true else changed): bool, out) end

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
  val @(ms, me) = lock_malformed(bv_o, ol, 0)
  var out : $B.builder_v = $B.create()
  val stale = (if ms >= 0 then let
      val () = bput_v(out, "error: malformed lockfile line: ")
      val () = copy_to_builder_v(bv_o, ms, me, LOCK_MAX, out)
      val () = put_char_v(out, 10)
    in true end
    else let
      val c1 = lock_notes(bv_n, nl, 0, bv_o, ol, true, false, out)
      val c2 = lock_notes(bv_o, ol, 0, bv_n, nl, false, c1, out)
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
  val i0 = skip_space(v, 4096, 1, vl)
  val quoted = peek(v, i0, 4096) = 34
  val ks = (if quoted then i0 + 1 else i0): pos_t
  val key_ok = lit_at(v, ks, 4096, path_c, 4) &&
    (if quoted then peek(v, ks + 4, 4096) = 34 else true)
  val ke = (if quoted then ks + 5 else ks + 4): pos_t
  val i1 = skip_space(v, 4096, ke, vl)
  val i2 = skip_space(v, 4096, i1 + 1, vl)
  val qs = i2 + 1
  val qe = find_byte(v, 4096, qs, vl, 34)
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
fun path_keys {lk,lsec:agz}{off:nat | off <= 65536} .<65536 - off>.
  (doc: !$T.toml_doc, sec: !$A.borrow(byte, lsec, 12),
   keys: !$A.borrow(byte, lk, 65536), off: int off, len: int): [n:nat] pdeps(n) =
  if off >= len then pd_nil()
  else let
    val z = $S.find_null_bv_at(keys, off, 65536)
    val kl = z - off
    fn next (doc: !$T.toml_doc, sec: !$A.borrow(byte, lsec, 12),
             keys: !$A.borrow(byte, lk, 65536)): [n:nat] pdeps(n) =
      if z >= 65536 then pd_nil() else path_keys(doc, sec, keys, z + 1, len)
  in
    if kl <= 0 then next(doc, sec, keys)
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
      in next(doc, sec, keys) end
      else if nk <= 0 then let
        val () = $A.free<byte>(pa)
        val () = $A.free<byte>(na)
      in next(doc, sec, keys) end
      else pd_cons(na, nk, pa, pl, next(doc, sec, keys))
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
  val ds = path_keys(doc, bv_s, bv_kb, 0, kl)
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
  (xs: names(n), a: !$A.arr(byte, la, 256), k: nlen): [m:nat] names(m) =
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
  (a: !$A.arr(byte, la, 256), k: nlen, p: !$A.arr(byte, lp, 256), pl: int): [n:nat] cons(n) = let
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

(* Prints err and fails when the kind is not known; consumes err *)
fn report_config (known: bool, err: $B.builder_v): void =
  if ~known then let
    var e : $B.builder_v = err
    val () = put_char_v(e, 10)
    val () = prerr_builder(e)
  in set_build_err() end
  else $B.builder_free(err)

(* The project's kind as Rust's config::load reads bats.toml, or none
   after printing its error (a bats.toml that cannot be read, an unknown
   kind, a constraint that does not parse, a path dependency in a lib
   package) *)
#pub fn project_kind (): $R.option(package_kind)

implement project_kind () = let
  var err : $B.builder_v = $B.create()
  val () = bput_v(err, "error: ")
  val kind = (case+ read_toml(str_to_path_arr("bats.toml")) of
    | ~$R.err(e) => let
        val () = put_cannot_read(e, err)
      in $R.none() end
    | ~$R.ok(doc) => let
        val nb = $A.alloc<byte>(256)
        val @(st, cs) = config_cons(doc, nb, 0, err)
        val () = cons_free(cs)
        val () = $A.free<byte>(nb)
        var quiet_err : $B.builder_v = $B.create()
        val k = (if st < 0 then $R.none() else doc_kind(doc, quiet_err)): $R.option(package_kind)
        val () = $B.builder_free(quiet_err)
        val () = $T.toml_free(doc)
      in k end): $R.option(package_kind)
  val () = report_config($R.is_some<package_kind>(kind), err)
in kind end

(* ============================================================
   Path dependencies at build time (Rust: build::copy_path_dep)
   ============================================================ *)

(* A NUL-terminated path: a[0, n) + "/" + b[0, bl), and its length *)
fn child_path {la,lb:agz}
  (a: !$A.borrow(byte, la, 524288), n: int, b: !$A.borrow(byte, lb, 1024), bl: int)
  : @([l:agz] $A.arr(byte, l, 524288), int) = let
  var p : $B.builder_v = $B.create()
  val () = copy_to_builder_v(a, 0, n, 524288, p)
  val () = put_char_v(p, 47)
  val () = copy_to_builder_v(b, 0, bl, 1024, p)
  val pl = $B.length(p)
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
in @(pa, pl) end

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
         val ok = (case+ $F.fd_copy(sf, df) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
         val () = $R.discard<int><int>($F.file_close(sf))
         val () = $R.discard<int><int>($F.file_close(df))
       in if ok then copy_mode(s, d) else false end)

(* Whether e[0, el) is ".", "..", or a directory Rust's copy skips:
   build, dist, docs or bats_modules *)
fn skipped_name {le:agz} (e: !$A.borrow(byte, le, 1024), el: int, is_dir: bool): bool = let
  var b_c = @[char][5]('b', 'u', 'i', 'l', 'd')
  var d_c = @[char][4]('d', 'i', 's', 't')
  var o_c = @[char][4]('d', 'o', 'c', 's')
  var m_c = @[char][12]('b', 'a', 't', 's', '_', 'm', 'o', 'd', 'u', 'l', 'e', 's')
in
  if el = 1 then peek(e, 0, 1024) = 46
  else if el = 2 then (if peek(e, 0, 1024) = 46 then peek(e, 1, 1024) = 46 else false)
  else if ~is_dir then false
  else if el = 5 then lit_at(e, 0, 1024, b_c, 5)
  else if el = 4 then (if lit_at(e, 0, 1024, d_c, 4) then true else lit_at(e, 0, 1024, o_c, 4))
  else if el = 12 then lit_at(e, 0, 1024, m_c, 12)
  else false
end

(* Whether the NUL-terminated path p is a directory *)
fn is_directory {lp:agz} (p: !$A.borrow(byte, lp, 524288)): bool =
  case+ $F.dir_open(p, 524288) of
  | ~$R.ok(d) => let
      val () = $R.discard<int><int>($F.dir_close(d))
    in true end
  | ~$R.err(_) => false

(* Copies entries i.. of the directory at s[0, sl) into d[0, dl)
   (Rust: copy_dir_recursive); false on an error. f bounds the depth
   still allowed, far past what a path can reach *)
fun copy_entries {n,i:nat | i <= n}{ls,ld:agz}{f:nat} .<f, 0, n - i>.
  (dir: !$F.entries(n), i: int i, n: int n, s: !$A.borrow(byte, ls, 524288), sl: int,
   d: !$A.borrow(byte, ld, 524288), dl: int, f: int f): bool =
  if i >= n then true
  else let
    val e = $A.alloc<byte>(1024)
    val el = $F.entries_name(dir, i, e, 1024)
  in
    let
      val @(fz_e, bv_e) = $A.freeze<byte>(e)
      val @(ca, cl) = child_path(s, sl, bv_e, el)
      val @(da, dl2) = child_path(d, dl, bv_e, el)
      val @(fz_c, bv_c) = $A.freeze<byte>(ca)
      val @(fz_d, bv_d) = $A.freeze<byte>(da)
      val is_dir = is_directory(bv_c)
      val ok = (if skipped_name(bv_e, el, is_dir) then true
                else if is_dir then (if f > 0 then copy_tree(bv_c, cl, bv_d, dl2, f - 1) else false)
                else copy_file(bv_c, bv_d)): bool
      val () = $A.drop<byte>(fz_d, bv_d)
      val () = $A.free<byte>($A.thaw<byte>(fz_d))
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = $A.free<byte>($A.thaw<byte>(fz_c))
      val () = $A.drop<byte>(fz_e, bv_e)
      val () = $A.free<byte>($A.thaw<byte>(fz_e))
    in
      if ok then copy_entries(dir, i + 1, n, s, sl, d, dl, f) else false
    end
  end

(* Copies the directory s[0, sl) (NUL-terminated) to d[0, dl), creating
   it, without its build, dist, docs and bats_modules directories *)
and copy_tree {ls,ld:agz}{f:nat} .<f, 1, 0>.
  (s: !$A.borrow(byte, ls, 524288), sl: int,
   d: !$A.borrow(byte, ld, 524288), dl: int, f: int f): bool = let
  var mk : $B.builder_v = $B.create()
  val () = copy_to_builder_v(d, 0, dl, 524288, mk)
  val _ = run_mkdir(mk)
in
  case+ $F.dir_read(s, 524288) of
  | ~$R.err(_) => false
  | ~$R.ok(dir) => let
      val ok = copy_entries(dir, 0, $F.entries_count(dir), s, sl, d, dl, f)
      val () = $F.entries_free(dir)
    in ok end
end

(* Rust's "path dependency '<n>': <what> '<p>'<after>" to stderr *)
fn path_dep_error {la,lp:agz}
  (a: !$A.arr(byte, la, 256), k: nlen, what: string, p: !$A.arr(byte, lp, 256), pl: int,
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
  (a: !$A.arr(byte, la, 256), k: nlen, p: !$A.arr(byte, lp, 256), pl: int): bool = let
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

(* Rust's offset_to_line_col: 1-based line and column (in bytes) of
   offset off in src *)
fun line_col {ls:agz}{ns:pos}{i,off:int}{l:pos} .<max(off - i, 0)>.
  (src: !$A.borrow(byte, ls, ns), sm: int ns, i: int i, off: int off, line: int l, col: pos_t)
  : @([l2:pos] int l2, pos_t) =
  if i >= off then @(line, col)
  else if peek(src, i, sm) = 10 then line_col(src, sm, i + 1, off, line + 1, 1)
  else line_col(src, sm, i + 1, off, line, col + 1)

(* The start of the line holding position i *)
fun line_start {ls:agz}{ns:pos}{i:int} .<max(i, 0)>. (src: !$A.borrow(byte, ls, ns), sm: int ns, i: int i): pos_t =
  if i <= 0 then 0
  else if peek(src, i - 1, sm) = 10 then i
  else line_start(src, sm, i - 1)

(* Rust's display_fancy of the error msg at offset off of src[0, n), a
   file labeled lab[l0, l1), appended to out; consumes msg *)
fn put_fancy {ll,ls:agz}{ns:pos}
  (lab: !$A.borrow(byte, ll, VMAX), l0: pos_t, l1: int, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   off: pos_t, msg: $B.builder_v, out: !$B.builder_v >> $B.builder_v): void = let
  val c = use_color()
  val @(line, col) = line_col(src, sm, 0, off, 1, 1)
  val pad = digits(line)
  val ls = line_start(src, sm, off)
  val le = find_byte(src, sm, off, n, 10)
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
  val () = put_int_v(out, line)
  val () = put_char_v(out, 58)
  val () = put_int_v(out, col)
  val () = put_char_v(out, 10)
  val () = put_char_v(out, 32)
  val () = put_n(32, pad, out)
  val () = put_bar(out, c)
  val () = bput_v(out, "\n ")
  val () = put_int_v(out, line)
  val () = put_bar(out, c)
  val () = put_char_v(out, 32)
  val () = copy_to_builder_v(src, ls, le, sm, out)
  val () = put_char_v(out, 10)
  val () = put_char_v(out, 32)
  val () = put_n(32, pad, out)
  val () = put_bar(out, c)
  val () = put_char_v(out, 32)
  val () = put_n(32, col - 1, out)
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

fn is_word_byte (c: int): bool =
  if c = 36 then true else if c = 35 then true
  else if c = 95 then true
  else if c >= 97 then c <= 122
  else if c >= 65 then c <= 90
  else if c >= 48 then c <= 57
  else false

(* The first position at or after i of src[0, e) that is not a word byte
   (letters, digits, _, $ and #) *)
fun word_end {ls:agz}{ns:pos}{i,e:int} .<max(e - i, 0)>. (src: !$A.borrow(byte, ls, ns), sm: int ns, i: int i, e: int e): pos_t =
  if i >= e then i
  else if is_word_byte(peek(src, i, sm)) then word_end(src, sm, i + 1, e)
  else i

(* Whether src[s, s + 7) is "$UNSAFE" *)
fn at_unsafe_kw {ls:agz}{ns:pos} (src: !$A.borrow(byte, ls, ns), sm: int ns, s: pos_t): bool = let
  var u_c = @[char][7]('$', 'U', 'N', 'S', 'A', 'F', 'E')
in lit_at(src, s, sm, u_c, 7) end

(* Whether src[s, s + 4) is "#pub": the unsafe construct is a #pub prfun
   without primplement *)
(* Whether the word at src[s, e) is prfun or prfn *)
fn at_prfun_kw {ls:agz}{ns:pos} (src: !$A.borrow(byte, ls, ns), sm: int ns, s: pos_t, e: pos_t): bool = let
  val we = word_end(src, sm, s, e)
  var a_c = @[char][5]('p', 'r', 'f', 'u', 'n')
  var b_c = @[char][4]('p', 'r', 'f', 'n')
in
  if we - s = 5 then lit_at(src, s, sm, a_c, 5)
  else if we - s = 4 then lit_at(src, s, sm, b_c, 4)
  else false
end

fn at_pub_kw {ls:agz}{ns:pos} (src: !$A.borrow(byte, ls, ns), sm: int ns, s: pos_t): bool = let
  var p_c = @[char][4]('#', 'p', 'u', 'b')
in lit_at(src, s, sm, p_c, 4) end

(* 'src[s, we)' is not allowed outside of $UNSAFE begin...end block *)
fn put_word_msg {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), sm: int ns, s: pos_t, we: pos_t, m: !$B.builder_v >> $B.builder_v): void = let
  val () = put_char_v(m, 39)
  val () = copy_to_builder_v(src, s, we, sm, m)
in bput_v(m, "' is not allowed outside of $UNSAFE begin...end block") end

(* What outside $UNSAFE is rejected: an unsafe construct (or a restricted
   keyword, or a construct that allocates without being linear), or an
   extcode block *)
datatype rejected_span = RejectedConstruct | RejectedExtcode

(* Rust's message for the unsafe construct, restricted keyword or
   extcode block span at src[s, e) outside $UNSAFE (emit::validate) *)
fn construct_msg {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), sm: int ns, rejected: rejected_span, s: pos_t, e: pos_t, m: !$B.builder_v >> $B.builder_v): void = let
  var fun_c = @[char][3]('f', 'u', 'n')
  var fnx_c = @[char][3]('f', 'n', 'x')
  var and_c = @[char][3]('a', 'n', 'd')
  var fix_c = @[char][3]('f', 'i', 'x')
  var val_c = @[char][3]('v', 'a', 'l')
  val we = word_end(src, sm, s, e)
  val w3 = (we - s = 3): bool
  val is_fun = (if w3 then lit_at(src, s, sm, fun_c, 3) else false): bool
  val is_rec = (if w3 then lit_at(src, s, sm, fnx_c, 3) || lit_at(src, s, sm, and_c, 3) ||
                           lit_at(src, s, sm, fix_c, 3) else false): bool
  val is_val_rec = (if w3 && e > we then lit_at(src, s, sm, val_c, 3) else false): bool
  var dt_c = @[char][8]('d', 'a', 't', 'a', 't', 'y', 'p', 'e')
  var clo_c = @[char][3]('c', 'l', 'o')
  var ref_c = @[char][3]('r', 'e', 'f')
  var tup_c = @[char][3]('t', 'u', 'p')
  var rec_c = @[char][3]('r', 'e', 'c')
  var list_c = @[char][4]('l', 'i', 's', 't')
  val b0 = peek(src, s, sm)
  val is_boxed_dollar = (if b0 = 36 then lit_at(src, s + 1, sm, tup_c, 3) ||
    lit_at(src, s + 1, sm, rec_c, 3) || lit_at(src, s + 1, sm, list_c, 4) else false): bool
  val is_datatype = (if we - s = 8 then lit_at(src, s, sm, dt_c, 8) else false): bool
  val is_clo = (if we - s >= 6 then lit_at(src, s, sm, clo_c, 3) else false): bool
  val is_ref = (if we - s >= 3 then lit_at(src, s, sm, ref_c, 3) else false): bool
  var lam_c = @[char][3]('l', 'a', 'm')
  val is_lam = (if w3 then lit_at(src, s, sm, lam_c, 3) else false): bool
  var delay_c = @[char][5]('d', 'e', 'l', 'a', 'y')
  val is_delay = (if b0 = 36 then lit_at(src, s + 1, sm, delay_c, 5) else false): bool
  var staload_c = @[char][7]('s', 't', 'a', 'l', 'o', 'a', 'd')
  var include_c = @[char][8]('#', 'i', 'n', 'c', 'l', 'u', 'd', 'e')
  val is_libats_ml = lit_at(src, s, sm, staload_c, 7) || lit_at(src, s, sm, include_c, 8)
  val built = prelude_build_of(src, s, we, sm)
in
  if (case+ rejected of RejectedExtcode() => true | RejectedConstruct() => false) then
    bput_v(m, "extcode block outside of $UNSAFE begin...end block")
  else if at_unsafe_kw(src, sm, s) then bput_v(m, "$UNSAFE construct outside of $UNSAFE begin...end block")
  else if is_libats_ml then
    bput_v(m, "libats/ML is not allowed outside $UNSAFE; it is ATS's garbage-collected library, whose lists, options, arrays and maps are never freed: use the prelude's linear forms (list_vt, option_vt, arrayptr)")
  else if b0 = 58 then
    bput_v(m, "'::' is not allowed outside $UNSAFE; it is the prelude's list_cons, whose non-linear list is never freed: use list_vt_cons, whose match frees it")
  else if is_delay then
    bput_v(m, "'$delay' is not allowed outside $UNSAFE; a non-linear lazy value is never freed: use $ldelay (a stream_vt)")
  else if prelude_build_is(built, BuildsList()) then let
    val () = put_char_v(m, 39)
    val () = copy_to_builder_v(src, s, we, sm, m)
  in bput_v(m, "' is not allowed outside $UNSAFE; it builds the prelude's non-linear list, which is never freed: use list_vt (list_vt_cons, list_vt_nil and the list_vt functions, or the list package)") end
  else if prelude_build_is(built, BuildsOption()) then let
    val () = put_char_v(m, 39)
    val () = copy_to_builder_v(src, s, we, sm, m)
  in bput_v(m, "' is not allowed outside $UNSAFE; it builds the prelude's non-linear option, which is never freed: use option_vt (Some_vt, None_vt) or result's option ($R.some, $R.none)") end
  else if prelude_build_is(built, BuildsStream()) then let
    val () = put_char_v(m, 39)
    val () = copy_to_builder_v(src, s, we, sm, m)
  in bput_v(m, "' is not allowed outside $UNSAFE; it builds the prelude's non-linear lazy stream, which is never freed: use stream_vt ($ldelay and the stream_vt functions)") end
  else if is_datatype then
    bput_v(m, "'datatype' with a constructor that carries data is not allowed outside $UNSAFE; it allocates and is never freed: use 'datavtype', which its match frees")
  else if b0 = 39 then
    bput_v(m, "a boxed tuple, record or list ('(, '{, '[) is not allowed outside $UNSAFE; it is never freed: use a flat @( ) or @{ }, or a linear $tup_vt, $rec_vt or $list_vt")
  else if is_boxed_dollar then let
    val () = put_char_v(m, 39)
    val () = copy_to_builder_v(src, s, we, sm, m)
  in bput_v(m, "' is not allowed outside $UNSAFE; a boxed tuple, record or list is never freed: use its linear form ($tup_vt, $rec_vt, $list_vt)") end
  else if is_clo then let
    val () = put_char_v(m, 39)
    val () = copy_to_builder_v(src, s, we, sm, m)
  in bput_v(m, "' is not allowed outside $UNSAFE; a non-linear closure is never freed: use lincloptr1 (made with llam, freed with cloptr_free)") end
  else if is_lam then
    bput_v(m, "'lam' is not allowed outside $UNSAFE; given to a cloref parameter it is a closure that is never freed: use 'llam' (a lincloptr1, freed with cloptr_free), or give it the arrow =<fun1> for a plain function")
  else if is_ref then
    bput_v(m, "'ref' inside a function is not allowed outside $UNSAFE; its cell is never freed: make it once, at the top level, or keep the value in a var")
  else if is_fun then
    bput_v(m, "'fun' without termination metric is not allowed outside $UNSAFE; use 'fn' or add '.< metric >.'")
  else if is_rec then let
    val () = put_char_v(m, 39)
    val () = copy_to_builder_v(src, s, we, sm, m)
  in bput_v(m, "' without termination metric is not allowed outside $UNSAFE; add '.< metric >.'") end
  else if is_val_rec then
    bput_v(m, "'val rec' is not allowed outside of $UNSAFE begin...end block")
  else put_word_msg(src, sm, s, we, m)
end

(* Rust's "#pub prfun '<name>' has no primplement; ..." for the #pub
   declaration whose keyword starts src[s, e) *)
fn prfun_msg {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), sm: int ns, s: pos_t, e: pos_t, m: !$B.builder_v >> $B.builder_v): void = let
  val k1 = word_end(src, sm, s, e)
  val n0 = skip_space(src, sm, k1, e)
  val n1 = word_end(src, sm, n0, e)
  val () = bput_v(m, "#pub prfun '")
  val () = copy_to_builder_v(src, n0, n1, sm, m)
in bput_v(m, "' has no primplement; unimplemented proof functions are unsound") end

(* The start of the last component of p[0, pl) *)
fun base_start {lp:agz}{i:int} .<max(i, 0)>. (p: !$A.borrow(byte, lp, VMAX), i: int i): pos_t =
  if i <= 0 then 0
  else if peek(p, i - 1, VMAX) = 47 then i
  else base_start(p, i - 1)

(* cnt, with Rust's "dependency not found" error added to errs unless found *)
fn add_missing {lp,ls,ll:agz}{ns:pos}
  (found: bool, p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   ss: pos_t, ps: pos_t, pe: pos_t, lib: !$A.borrow(byte, ll, VMAX), lbl: int,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if found then cnt
  else let
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "dependency '")
    val () = copy_to_builder_v(src, ps, pe, sm, m)
    val () = bput_v(m, "' not found (expected ")
    val () = copy_to_builder_v(lib, 0, lbl, VMAX, m)
    val () = put_char_v(m, 41)
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, 0, pl, src, sm, n, ss, m, fy)
  in add_error(cnt, fy, errs) end

(* Rust's "dependency '<pkg>' not found (expected <lib.bats>)" for each
   #use whose package has no bats_modules/<pkg>/src/lib.bats, labeled with
   the file's path p[0, pl) (preprocess_one) *)
fn use_missing {lp,ls:agz}{ns:pos}
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   sp: !span(ns), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ sp of
  | SUse(ss, _, _, ps, pe, _, _) => let
      var lb : $B.builder_v = $B.create()
      val () = bput_v(lb, "./bats_modules/")
      val () = copy_to_builder_v(src, ps, pe, sm, lb)
      val () = bput_v(lb, "/src/lib.bats")
      val lbl = $B.length(lb)
      val () = put_char_v(lb, 0)
      val @(la, _) = $B.to_arr(lb)
      val @(fz_l, bv_l) = $A.freeze<byte>(la)
      val found = $F.file_exists(bv_l, VMAX)
      val cnt2 = add_missing(found, p, pl, src, sm, n, ss, ps, pe, bv_l, lbl, cnt, errs)
      val () = $A.drop<byte>(fz_l, bv_l)
      val () = $A.free<byte>($A.thaw<byte>(fz_l))
    in cnt2 end
  | _ => cnt

fun pass_uses {lp,ls:agz}{ns:pos}{k:nat} .<k>.
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   xs: !spans(ns, k), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ xs of
  | spans_nil() => cnt
  | spans_cons(sp, tl) => let
      val cnt2 = use_missing(p, pl, src, sm, n, sp, cnt, errs)
    in pass_uses(p, pl, src, sm, n, tl, cnt2, errs) end

(* Rust's "$UNSAFE requires `unsafe = true` in bats.toml" for each
   $UNSAFE block, labeled with the file's path (preprocess_one); an
   unsafe package skips this pass *)
fn unsafe_block_error {lp,ls:agz}{ns:pos}
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   sp: !span(ns), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ sp of
  | SUnsafeBlock(ss, _, _, _) => let
      var m : $B.builder_v = $B.create()
      val () = bput_v(m, "$UNSAFE requires `unsafe = true` in bats.toml")
      var fy : $B.builder_v = $B.create()
      val () = put_fancy(p, 0, pl, src, sm, n, ss, m, fy)
    in add_error(cnt, fy, errs) end
  | _ => cnt

fun pass_unsafe_blocks {lp,ls:agz}{ns:pos}{k:nat} .<k>.
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   xs: !spans(ns, k), is_unsafe: bool, cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if is_unsafe then cnt
  else case+ xs of
  | spans_nil() => cnt
  | spans_cons(sp, tl) => let
      val cnt2 = unsafe_block_error(p, pl, src, sm, n, sp, cnt, errs)
    in pass_unsafe_blocks(p, pl, src, sm, n, tl, false, cnt2, errs) end

(* cnt, with the unsafe construct's error added to errs when hit *)
fn add_construct {lp,ls:agz}{ns:pos}
  (hit: bool, want_pf: bool, rejected: rejected_span, p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t,
   src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t, ss: pos_t, ws: pos_t, se: pos_t,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if ~hit then cnt
  else let
    var m : $B.builder_v = $B.create()
    val () = (if want_pf then prfun_msg(src, sm, ws, se, m) else construct_msg(src, sm, rejected, ws, se, m)): void
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, b0, pl, src, sm, n, ss, m, fy)
  in add_error(cnt, fy, errs) end

(* The unsafe constructs, restricted keywords and extcode blocks outside
   $UNSAFE, in order, labeled with the file's name p[b0, pl)
   (emit::validate); want_pf selects the #pub prfun ones instead, which
   Rust reports after the others *)
fn construct_error {lp,ls:agz}{ns:pos}
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   sp: !span(ns), want_pf: bool, cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ sp of
  | SConstruct(ss, se) =>
    add_construct(~want_pf, want_pf, RejectedConstruct(), p, b0, pl, src, sm, n, ss, ss, se, cnt, errs)
  | SExtcode(ss, se, _, _, _) =>
    add_construct(~want_pf, want_pf, RejectedExtcode(), p, b0, pl, src, sm, n, ss, ss, se, cnt, errs)
  | SPub(ss, se, restricted, cs) => let
      val is_pf = (if restricted then at_prfun_kw(src, sm, cs, se) else false): bool
      val hit = (if ~restricted then false else if want_pf then is_pf else ~is_pf): bool
    in add_construct(hit, want_pf, RejectedConstruct(), p, b0, pl, src, sm, n, ss, cs, se, cnt, errs) end
  | _ => cnt

fun pass_constructs {lp,ls:agz}{ns:pos}{k:nat} .<k>.
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   xs: !spans(ns, k), want_pf: bool, cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ xs of
  | spans_nil() => cnt
  | spans_cons(sp, tl) => let
      val cnt2 = construct_error(p, b0, pl, src, sm, n, sp, want_pf, cnt, errs)
    in pass_constructs(p, b0, pl, src, sm, n, tl, want_pf, cnt2, errs) end

(* Whether src[a, a + k) and src[b, b + k) hold the same bytes *)
fun same_bytes {ls:agz}{ns:pos}{k:int} .<max(k, 0)>.
  (src: !$A.borrow(byte, ls, ns), sm: int ns, a: pos_t, b: pos_t, k: int k): bool =
  if k <= 0 then true
  else if peek(src, a, sm) <> peek(src, b, sm) then false
  else same_bytes(src, sm, a + 1, b + 1, k - 1)

(* The alias ranges of the #use spans of a source *)
datavtype ranges(int) =
  | ranges_nil(0) of ()
  | {k:nat} ranges_cons(k + 1) of (pos_t, pos_t, ranges(k))

fun ranges_free {k:nat} .<k>. (rs: ranges(k)): void =
  case+ rs of
  | ~ranges_nil() => ()
  | ~ranges_cons(_, _, tl) => ranges_free(tl)

(* The alias of sp, when it is a #use, onto acc *)
fn span_alias {ns:pos}{j:nat} (sp: !span(ns), acc: ranges(j)): [j2:nat] ranges(j2) =
  case+ sp of
  | SUse(_, _, _, _, _, as0, ae) => ranges_cons(as0, ae, acc)
  | _ => acc

(* The aliases of the #use spans of xs, onto acc *)
fun use_aliases {ns:pos}{k,j:nat} .<k>. (xs: !spans(ns, k), acc: ranges(j)): [j2:nat] ranges(j2) =
  case+ xs of
  | spans_nil() => acc
  | spans_cons(sp, tl) => use_aliases(tl, span_alias(sp, acc))

(* Whether one of rs is the alias src[as0, ae) *)
fun alias_known {ls:agz}{ns:pos}{k:nat} .<k>.
  (src: !$A.borrow(byte, ls, ns), sm: int ns, rs: !ranges(k), as0: pos_t, ae: pos_t): bool =
  case+ rs of
  | ranges_nil() => false
  | ranges_cons(us, ue, tl) =>
    if (if ue - us = ae - as0 then same_bytes(src, sm, us, as0, ae - as0) else false) then true
    else alias_known(src, sm, tl, as0, ae)

(* Whether src[0, n) binds the alias src[as0, ae) with ATS's
   staload <alias> = "...", which the Rust bats did not accept (an
   allowed divergence: packages staload bridge modules this way) *)
fun staload_alias {ls:agz}{ns:pos}{i,n:int} .<max(n - i, 0)>.
  (src: !$A.borrow(byte, ls, ns), sm: int ns, i: int i, n: int n, as0: pos_t, ae: pos_t): bool =
  if i + 7 > n then false
  else let
    var s_c = @[char][7]('s', 't', 'a', 'l', 'o', 'a', 'd')
    val at_kw = (if i > 0 then (if is_word_byte(peek(src, i - 1, sm)) then false
                                else lit_at(src, i, sm, s_c, 7))
                 else lit_at(src, i, sm, s_c, 7)): bool
    val k0 = skip_space(src, sm, i + 7, n)
    val k1 = word_end(src, sm, k0, n)
    val k2 = skip_space(src, sm, k1, n)
    val hit = (if ~at_kw then false
               else if k0 = i + 7 then false
               else if k1 - k0 <> ae - as0 then false
               else if ~same_bytes(src, sm, k0, as0, ae - as0) then false
               else peek(src, k2, sm) = 61): bool
  in if hit then true else staload_alias(src, sm, i + 1, n, as0, ae) end

(* cnt, with Rust's "unknown alias" error added to errs when bad *)
fn add_alias_error {lp,ls:agz}{ns:pos}
  (bad: bool, p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t,
   src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t, ss: pos_t, as0: pos_t, ae: pos_t,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if ~bad then cnt
  else let
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "unknown alias '")
    val () = copy_to_builder_v(src, as0, ae, sm, m)
    val () = bput_v(m, "' in qualified access")
    var fy : $B.builder_v = $B.create()
    val () = put_fancy(p, b0, pl, src, sm, n, ss, m, fy)
  in add_error(cnt, fy, errs) end

(* Rust's "unknown alias '<a>' in qualified access" for each $a.member
   whose a no #use names, labeled with the file's name p[b0, pl)
   (emit::validate) *)
fn alias_error {lp,ls:agz}{ns:pos}{j:nat}
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   sp: !span(ns), rs: !ranges(j), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ sp of
  | SQual(ss, _, as0, ae, _, _) => let
      val bad = (if alias_known(src, sm, rs, as0, ae) then false
                 else ~staload_alias(src, sm, 0, n, as0, ae)): bool
    in add_alias_error(bad, p, b0, pl, src, sm, n, ss, as0, ae, cnt, errs) end
  | _ => cnt

fun pass_aliases_in {lp,ls:agz}{ns:pos}{k,j:nat} .<k>.
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   xs: !spans(ns, k), rs: !ranges(j), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ xs of
  | spans_nil() => cnt
  | spans_cons(sp, tl) => let
      val cnt2 = alias_error(p, b0, pl, src, sm, n, sp, rs, cnt, errs)
    in pass_aliases_in(p, b0, pl, src, sm, n, tl, rs, cnt2, errs) end

fn pass_aliases {lp,ls:agz}{ns:pos}{k:nat}
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   xs: !spans(ns, k), cnt: int, errs: !$B.builder_v >> $B.builder_v): int = let
  val rs = use_aliases(xs, ranges_nil())
  val c = pass_aliases_in(p, b0, pl, src, sm, n, xs, rs, cnt, errs)
  val () = ranges_free(rs)
in c end

(* cnt, with sp's lex error added to errs when it is one *)
fn add_lex_error {lp,ls:agz}{ns:pos}
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   sp: !span(ns), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ sp of
  | SLexError(ss, what, e1, e2, run) => let
      var m : $B.builder_v = $B.create()
      val off = (case+ what of UnterminatedUnittest() => ss | _ => e1): pos_t
      val () = (case+ what of
        | EmptyTargetList() => bput_v(m, "empty target list in $UNITTEST.run()")
        | UnknownTarget() => let
            val () = bput_v(m, "unknown test target '")
            val () = copy_to_builder_v(src, e1, e2, sm, m)
          in bput_v(m, "'; expected 'native' or 'wasm'") end
        | UnterminatedCComment() => bput_v(m, "unterminated C-style block comment")
        | UnterminatedMlComment() => bput_v(m, "unterminated ML-style block comment")
        | UnterminatedString() => bput_v(m, "unterminated string literal")
        | UnterminatedExtcode() => bput_v(m, "unterminated extcode block")
        | UnterminatedUnsafe() => bput_v(m, "unterminated $UNSAFE begin...end block")
        | UnterminatedUnittest() =>
          if run then bput_v(m, "unterminated $UNITTEST.run begin...end block")
          else bput_v(m, "unterminated $UNITTEST begin...end block")): void
      var fy : $B.builder_v = $B.create()
      val () = put_fancy(p, b0, pl, src, sm, n, off, m, fy)
    in add_error(cnt, fy, errs) end
  | _ => cnt

(* The lexer's errors, labeled with the file's name p[b0, pl); Rust's
   preprocess_one reports them first *)
fun pass_lex_errors {lp,ls:agz}{ns:pos}{k:nat} .<k>.
  (p: !$A.borrow(byte, lp, VMAX), b0: pos_t, pl: pos_t, src: !$A.borrow(byte, ls, ns), sm: int ns, n: pos_t,
   xs: !spans(ns, k), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ xs of
  | spans_nil() => cnt
  | spans_cons(sp, tl) => let
      val cnt2 = add_lex_error(p, b0, pl, src, sm, n, sp, cnt, errs)
    in pass_lex_errors(p, b0, pl, src, sm, n, tl, cnt2, errs) end

(* The errors of the file at the NUL-terminated path p[0, pl), whose
   package is unsafe or not, added to errs (Rust: preprocess_one, in its
   order), when wanted *)
fn check_file {lp:agz}
  (p: !$A.borrow(byte, lp, VMAX), pl: pos_t, wanted: bool, is_unsafe: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if ~wanted then cnt else
  case+ read_whole(p, VMAX) of
  | ~whole_err(_) => cnt
  | ~whole_ok(ar, piece, sm, n) => let
      val @(fz_s, bv_s) = $A.freeze<byte>(piece)
      val xs = lex_spans(bv_s, n, sm)
      val b0 = base_start(p, pl)
      val c0 = pass_lex_errors(p, b0, pl, bv_s, sm, n, xs, cnt, errs)
      val c1 = pass_uses(p, pl, bv_s, sm, n, xs, c0, errs)
      val c2 = pass_unsafe_blocks(p, pl, bv_s, sm, n, xs, is_unsafe, c1, errs)
      val c3 = pass_constructs(p, b0, pl, bv_s, sm, n, xs, false, c2, errs)
      val c3a = pass_aliases(p, b0, pl, bv_s, sm, n, xs, c3, errs)
      val c4 = pass_constructs(p, b0, pl, bv_s, sm, n, xs, true, c3a, errs)
      val () = spans_free(xs)
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = whole_free(ar, $A.thaw<byte>(fz_s))
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
fun dep_root_end {lp:agz}{i,pl:int} .<max(pl - i, 0)>. (p: !$A.borrow(byte, lp, VMAX), i: int i, pl: int pl): pos_t =
  if i + 5 > pl then pl
  else let
    var s_c = @[char][5]('/', 's', 'r', 'c', '/')
  in
    if lit_at(p, i, VMAX, s_c, 5) then i else dep_root_end(p, i + 1, pl)
  end

(* Whether the dependency owning the file p[0, pl) is unsafe (Rust:
   preprocess_all's config::load of its root) *)
fn dep_unsafe {lp:agz} (p: !$A.borrow(byte, lp, VMAX), pl: pos_t): bool = let
  val re = dep_root_end(p, 15, pl)
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

(* Which files of a list are checked, and under which unsafe flag: the
   package's shared modules (not src/bin/, not named lib.bats), the
   dependencies (each under its own unsafe flag), or every file *)
datatype checked = SharedModules | Dependencies | EveryFile

(* Checks each file of the NUL-separated list files[off, len), as mode
   says *)
fun check_list {lf:agz}{off:nat | off <= VMAX} .<VMAX - off>.
  (files: !$A.borrow(byte, lf, VMAX), off: int off, len: int, mode: checked, own_unsafe: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if off >= len then cnt
  else let
    val e = $S.find_null_bv_at(files, off, VMAX)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, VMAX, pb)
    val pl = e - off
    val @(pa, _) = $B.to_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val b0 = base_start(bv_p, pl)
    val skip = (case+ mode of
      | SharedModules() => (if in_bin(bv_p) then true else is_lib_name(bv_p, b0, pl))
      | _ => false): bool
    val uns = (case+ mode of Dependencies() => dep_unsafe(bv_p, pl) | _ => own_unsafe): bool
    val cnt2 = check_file(bv_p, pl, ~skip, uns, cnt, errs)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in if e >= VMAX then cnt2 else check_list(files, e + 1, len, mode, own_unsafe, cnt2, errs) end

(* Checks the .bats files under dir (./src, ./bats_modules or
   ./src/bin) in mode, as check_list does *)
fn check_dir {sn:nat} (dir: string sn, mode: checked, own_unsafe: bool,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int = let
  var d : $B.builder_v = $B.create()
  val () = bput_v(d, dir)
  val @(fa, flen) = sorted_bats_files(d)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val c = check_list(bv_f, 0, flen, mode, own_unsafe, cnt, errs)
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in c end

(* ============================================================
   Recursion through an implement (recursion.bats)
   ============================================================ *)

(* cnt, with the error for the implement src[ns, ne) of the file at
   files[fi, NUL), whose keyword is at kw, added to errs *)
fn add_cycle_error {lf:agz}
  (files: !$A.borrow(byte, lf, VMAX), fi: pos_t, kw: pos_t, ns: pos_t, ne: pos_t,
   cnt: int, errs: !$B.builder_v >> $B.builder_v): int = let
  val e = find_null_bv_from(files, fi, VMAX)
  var pb : $B.builder_v = $B.create()
  val () = copy_to_builder_v(files, fi, e + 1, VMAX, pb)
  val pl = e - fi
  val @(pa, _) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val c = (case+ read_whole(bv_p, VMAX) of
    | ~whole_err(_) => cnt
    | ~whole_ok(ar, piece, sm, n) => let
        val @(fz_s, bv_s) = $A.freeze<byte>(piece)
        var m : $B.builder_v = $B.create()
        val () = bput_v(m, "'implement ")
        val () = copy_to_builder_v(bv_s, ns, ne, sm, m)
        val () = bput_v(m, "' calls itself, directly or through other functions, and an implement has no termination metric; recurse in a local 'fun' with '.< metric >.'")
        var fy : $B.builder_v = $B.create()
        val () = put_fancy(bv_p, base_start(bv_p, pl), pl, bv_s, sm, n, kw, m, fy)
        val () = $A.drop<byte>(fz_s, bv_s)
        val () = whole_free(ar, $A.thaw<byte>(fz_s))
      in add_error(cnt, fy, errs) end): int
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in c end

fun add_cycle_errors {lf:agz}{k:nat} .<k>.
  (files: !$A.borrow(byte, lf, VMAX), hs: cycle_hits(k), cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  case+ hs of
  | ~cycle_hits_nil() => cnt
  | ~cycle_hits_cons(fi, kw, ns, ne, tl) => let
      val c = add_cycle_error(files, fi, kw, ns, ne, cnt, errs)
    in add_cycle_errors(files, tl, c, errs) end

(* cnt, with the errors for the implements on a call cycle among the
   files files[off, len) of one package *)
fn check_cycles {lf:agz}{off:nat | off <= VMAX}
  (files: !$A.borrow(byte, lf, VMAX), off: int off, len: int, cnt: int, errs: !$B.builder_v >> $B.builder_v): int = let
  val+ ~Cycles(hs, too_many) = implement_cycles(files, off, len)
  val c = add_cycle_errors(files, hs, cnt, errs)
in
  if ~too_many then c
  else let
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "more than 1048576 definitions in one package; they are not checked for recursion through an implement")
  in add_error(c, m, errs) end
end

(* Whether files[a, a + k) and files[b, b + k) hold the same bytes *)
fun same_prefix {lf:agz}{i:nat | i <= VMAX} .<VMAX - i>.
  (files: !$A.borrow(byte, lf, VMAX), a: pos_t, b: pos_t, i: int i, k: int): bool =
  if i >= k then true
  else if i >= VMAX then true
  else if peek(files, a + i, VMAX) <> peek(files, b + i, VMAX) then false
  else same_prefix(files, a, b, i + 1, k)

(* The first entry of files[o, len) that does not start with
   files[g, g + k) (or len) *)
fun group_end {lf:agz}{o:nat | o <= VMAX} .<VMAX - o>.
  (files: !$A.borrow(byte, lf, VMAX), o: int o, len: int, g: pos_t, k: int): [r:int | r >= o] int r =
  if o >= len then o
  else if ~same_prefix(files, g, o, 0, k) then o
  else let
    val e = $S.find_null_bv_at(files, o, VMAX)
  in if e >= VMAX then e else group_end(files, e + 1, len, g, k) end

(* cnt, with the recursion errors of each dependency package among the
   files files[off, len) of ./bats_modules, each package's files being
   together in the list *)
fun check_dep_cycles {lf:agz}{off:nat | off <= VMAX} .<VMAX - off>.
  (files: !$A.borrow(byte, lf, VMAX), off: int off, len: int, cnt: int, errs: !$B.builder_v >> $B.builder_v): int =
  if off >= len then cnt
  else let
    val e = $S.find_null_bv_at(files, off, VMAX)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, VMAX, pb)
    val @(pa, _) = $B.to_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    (* ./bats_modules/<pkg>/: the package's root and the slash after it *)
    val k = dep_root_end(bv_p, 15, e - off) + 1
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in
    if e >= VMAX then check_cycles(files, off, e, cnt, errs)
    else let
      val ge = group_end(files, e + 1, len, off, k)
      val c = check_cycles(files, off, ge, cnt, errs)
    in
      if ge >= VMAX then c else check_dep_cycles(files, ge, len, c, errs)
    end
  end

(* The recursion errors of the package's own files (dep = false) or of
   each dependency (the files under ./bats_modules) *)
fn check_dir_cycles {sn:nat} (dir: string sn, dep: bool, cnt: int, errs: !$B.builder_v >> $B.builder_v): int = let
  var d : $B.builder_v = $B.create()
  val () = bput_v(d, dir)
  val @(fa, flen) = sorted_bats_files(d)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val c = (if dep then check_dep_cycles(bv_f, 0, flen, cnt, errs) else check_cycles(bv_f, 0, flen, cnt, errs)): int
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
#pub fn validate_project (): bool

implement validate_project () = let
  val own_unsafe = toml_unsafe(str_to_path_arr("./bats.toml"))
  var errs : $B.builder_v = $B.create()
  val c1 = check_dir("./src", SharedModules(), own_unsafe, 0, errs)
  val c2 = check_dir("./bats_modules", Dependencies(), own_unsafe, c1, errs)
  val lp = str_to_path_arr("./src/lib.bats")
  val @(fz_l, bv_l) = $A.freeze<byte>(lp)
  val c3 = check_file(bv_l, 14, $F.file_exists(bv_l, VMAX), own_unsafe, c2, errs)
  val () = $A.drop<byte>(fz_l, bv_l)
  val () = $A.free<byte>($A.thaw<byte>(fz_l))
  val c4 = check_dir("./src/bin", EveryFile(), own_unsafe, c3, errs)
  val c5 = check_dir_cycles("./bats_modules", true, c4, errs)
  val c6 = check_dir_cycles("./src", false, c5, errs)
in
  report_errors(c6, errs)
end

(* ============================================================
   Locked dependencies: with a bats.lock, check, build, run and test
   use exactly the versions it locks
   ============================================================ *)

(* Whether ./bats.lock exists *)
fn lock_exists (): bool = let
  val lp = str_to_path_arr("bats.lock")
  val @(fz_lp, bv_lp) = $A.freeze<byte>(lp)
  val r = $F.file_exists(bv_lp, 524288)
  val () = $A.drop<byte>(fz_lp, bv_lp)
  val () = $A.free<byte>($A.thaw<byte>(fz_lp))
in r end

(* acc, with the package of each lock line of t[i, tl) added once *)
fun lock_names {lt:agz}{tl,i:int}{m:nat} .<max(tl - i, 0)>.
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: int tl, i: int i, acc: names(m)): [m2:nat] names(m2) =
  if i >= tl then acc
  else let
    val @(ts, te, le) = lock_line(t, tl, i)
  in
    if ts >= te then lock_names(t, tl, le + 1, acc)
    else let
      val @(pe, _) = lock_fields(t, ts, te)
      val a = $A.alloc<byte>(256)
      val k = copy_name(t, ts, pe, LOCK_MAX, a, 0)
    in
      if k <= 0 then let
        val () = $A.free<byte>(a)
      in lock_names(t, tl, le + 1, acc) end
      else if names_has(acc, a, k) then let
        val () = $A.free<byte>(a)
      in lock_names(t, tl, le + 1, acc) end
      else lock_names(t, tl, le + 1, names_cons(a, k, acc))
    end
  end

(* The [start, end) of the version and of the sha256 on the first lock
   line of t[0, tl) whose package is a[0, k), or ~1s when none is *)
fn lock_entry {lt,la:agz}{tl:int}
  (t: !$A.borrow(byte, lt, LOCK_MAX), tl: int tl, a: !$A.arr(byte, la, 256), k: nlen)
  : @(pos_t, pos_t, pos_t, pos_t) = let
  var name : $B.builder_v = $B.create()
  val () = put_name(a, k, name)
  val @(name_arr, _) = $B.to_arr(name)
  val @(fz_n, bv_n) = $A.freeze<byte>(name_arr)
  val @(vs, ve) = lock_find(t, tl, 0, bv_n, 0, k)
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
in
  if vs < 0 then @(~1, ~1, ~1, ~1)
  else let
    val line_end = find_byte(t, LOCK_MAX, ve, tl, 10)
    val hash_end = trim_end(t, LOCK_MAX, ve, line_end)
    val hash_start = (if ve < hash_end then ve + 1 else hash_end): pos_t
  in @(vs, ve, hash_start, hash_end) end
end

(* "error: bats.lock locks <name> v<v>" *)
fn put_locked {la:agz}
  (a: !$A.arr(byte, la, 256), k: nlen, v: !cand, out: !$B.builder_v >> $B.builder_v): void = let
  val () = bput_v(out, "error: bats.lock locks ")
  val () = put_name(a, k, out)
  val () = bput_v(out, " v")
in put_cand(v, out) end

(* What a stale bats.lock's error ends with *)
fn put_relock (out: !$B.builder_v >> $B.builder_v): void =
  bput_v(out, "; bats.lock is stale: run 'bats lock --repository <dir>' and commit it\n")

(* Installs version v of the package a[0, k), whose archive's sha256
   bats.lock gives as t[hash_start, hash_end), from the repository
   repo[0, rl) into bats_modules; false after saying why it cannot: no
   repository, no such archive in it, or an archive of another sha256 *)
fn install_locked {lr,lt,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int,
   t: !$A.borrow(byte, lt, LOCK_MAX), hash_start: pos_t, hash_end: pos_t,
   a: !$A.arr(byte, la, 256), k: nlen, v: !cand): bool =
  if rl <= 0 then let
    var m : $B.builder_v = $B.create()
    val () = put_locked(a, k, v, m)
    val () = bput_v(m, ", which is not in bats_modules. Use --repository <dir> to fetch it.\n")
    val () = prerr_builder(m)
  in false end
  else let
    val @(arc, alen) = archive_path(repo, rl, a, k, v)
    val @(fz_c, bv_c) = $A.freeze<byte>(arc)
    var hash : $B.builder_v = $B.create()
    val found = put_file_sha256(bv_c, hash)
    val @(hash_arr, _) = $B.to_arr(hash)
    val @(fz_h, bv_h) = $A.freeze<byte>(hash_arr)
    val same = (if found then lock_range_eq(bv_h, 0, 64, t, hash_start, hash_end) else false): bool
    val () = $A.drop<byte>(fz_h, bv_h)
    val () = $A.free<byte>($A.thaw<byte>(fz_h))
    val () = (if same then refetch(bv_c, alen, a, k, v)
      else let
        var m : $B.builder_v = $B.create()
        val () = put_locked(a, k, v, m)
        val () = (if found then bput_v(m, ", but its archive '")
                  else bput_v(m, ", which is not in repository '"))
        val () = (if found then copy_to_builder_v(bv_c, 0, alen, 524288, m)
                  else copy_to_builder_v(repo, 0, rl, 4096, m))
        val () = (if found then bput_v(m, "' does not have the sha256 bats.lock gives\n")
                  else bput_v(m, "'\n"))
      in prerr_builder(m) end)
    val () = $A.drop<byte>(fz_c, bv_c)
    val () = $A.free<byte>($A.thaw<byte>(fz_c))
  in same end

(* "error: <name> is used but bats.lock does not lock it" and the hint *)
fn not_locked {la:agz} (a: !$A.arr(byte, la, 256), k: nlen): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: ")
  val () = put_name(a, k, m)
  val () = bput_v(m, " is used but bats.lock does not lock it")
  val () = put_relock(m)
in prerr_builder(m) end

(* Says that bats.lock locks each package of xs, which nothing uses;
   whether xs was empty *)
fun report_unused {n:nat} .<n>. (xs: names(n), none: bool): bool =
  case+ xs of
  | ~names_nil() => none
  | ~names_cons(a, k, rest) => let
      var m : $B.builder_v = $B.create()
      val () = bput_v(m, "error: bats.lock locks ")
      val () = put_name(a, k, m)
      val () = bput_v(m, ", which nothing uses")
      val () = put_relock(m)
      val () = prerr_builder(m)
      val () = $A.free<byte>(a)
    in report_unused(rest, false) end

(* Walks the packages on stack as resolve_all does, but each one's
   version is the one the lock t[0, tl) gives, not the repository's
   newest: it must meet the constraints cs read so far, and is installed
   unless bats_modules holds it. all holds every package queued so far,
   pn the path dependencies, avail the lock's packages not yet reached,
   which nothing uses when the walk ends. Whether every package was
   locked, allowed and installed (ok so far), and nothing locked was
   unused *)
fun walk_locked {s,m,nc,np,u:nat}{lr,lt:agz}{tl:int} .<u, s>.
  (stack: names(s), all: names(m), cs: cons(nc), pn: !names(np), avail: names(u),
   t: !$A.borrow(byte, lt, LOCK_MAX), tl: int tl,
   repo: !$A.borrow(byte, lr, 4096), rl: int, ok: bool): bool =
  case+ stack of
  | ~names_nil() => let
      val () = names_free(all)
      val () = cons_free(cs)
      val none_unused = report_unused(avail, true)
    in if ok then none_unused else false end
  | ~names_cons(a, k, rest) =>
    (* A path dependency is not locked *)
    if names_has(pn, a, k) then let
      val () = $A.free<byte>(a)
    in walk_locked(rest, all, cs, pn, avail, t, tl, repo, rl, ok) end
    else (case+ names_take(avail, a, k) of
      | ~NMissed(avail2) => let
          val () = not_locked(a, k)
          val () = $A.free<byte>(a)
        in walk_locked(rest, all, cs, pn, avail2, t, tl, repo, rl, false) end
      | ~NTaken(avail2) => let
          val @(vs, ve, hash_start, hash_end) = lock_entry(t, tl, a, k)
          val @(parsed, _, _) = parse_cand(t, LOCK_MAX, vs, ve)
        in
          case+ parsed of
          | ~$R.none() => let
              var m : $B.builder_v = $B.create()
              val () = bput_v(m, "error: bats.lock's version of ")
              val () = put_name(a, k, m)
              val () = bput_v(m, " does not parse\n")
              val () = prerr_builder(m)
              val () = $A.free<byte>(a)
              val () = names_free(rest)
              val () = names_free(all)
              val () = cons_free(cs)
              val () = names_free(avail2)
            in false end
          | ~$R.some(v) =>
            if ~cons_allow(cs, a, k, v) then let
              var m : $B.builder_v = $B.create()
              val () = put_locked(a, k, v, m)
              val () = bput_v(m, ", which does not meet ")
              val () = put_cons_of(cs, a, k, false, m)
              val () = put_relock(m)
              val () = prerr_builder(m)
              val () = cand_free(v)
              val () = $A.free<byte>(a)
              val () = names_free(rest)
              val () = names_free(all)
              val () = cons_free(cs)
              val () = names_free(avail2)
            in false end
            else let
              val installed = (if installed_at(a, k, v) then true
                               else install_locked(repo, rl, t, hash_start, hash_end, a, k, v)): bool
              val () = cand_free(v)
            in
              if ~installed then let
                val () = $A.free<byte>(a)
                val () = names_free(rest)
                val () = names_free(all)
                val () = cons_free(cs)
                val () = names_free(avail2)
              in false end
              else let
                val cs2 = cons_append(cs, dep_cons(a, k))
                val ts = dep_uses(a, k)
                val @(stack2, all2) = push_new(ts, rest, all)
                val () = $A.free<byte>(a)
              in walk_locked(stack2, all2, cs2, pn, avail2, t, tl, repo, rl, ok) end
            end
        end)

(* locked_deps under the project's constraints cs, when cst says they
   were read; otherwise reports err, Rust's message about them; consumes
   err *)
fn locked_with {n,nc:nat}{lr:agz}
  (cst: int, cs: cons(nc), err: $B.builder_v,
   ds: !pdeps(n), repo: !$A.borrow(byte, lr, 4096), rl: int): bool =
  if cst < 0 then let
    val () = cons_free(cs)
    var e : $B.builder_v = err
    val () = put_char_v(e, 10)
    val () = prerr_builder(e)
  in false end
  else let
    val () = $B.builder_free(err)
    val @(lock_arr, lock_len) = read_old_lock()
    val @(fz_o, bv_o) = $A.freeze<byte>(lock_arr)
    val @(ms, me) = lock_malformed(bv_o, lock_len, 0)
    val ok = (if ms >= 0 then let
        var m : $B.builder_v = $B.create()
        val () = bput_v(m, "error: malformed lockfile line: ")
        val () = copy_to_builder_v(bv_o, ms, me, LOCK_MAX, m)
        val () = put_char_v(m, 10)
        val () = prerr_builder(m)
        val () = cons_free(cs)
      in false end
      else let
        var src : $B.builder_v = $B.create()
        val () = bput_v(src, "src")
        val pkgs = collect_uses(src)
        val all = names_copy(pkgs)
        val @(stack, all2, cs2) = add_pdeps(ds, pkgs, all, cs)
        val pn = pdeps_names(ds)
        val avail = lock_names(bv_o, lock_len, 0, names_nil())
        val r = walk_locked(stack, all2, cs2, pn, avail, bv_o, lock_len, repo, rl, true)
        val () = names_free(pn)
      in r end): bool
    val () = $A.drop<byte>(fz_o, bv_o)
    val () = $A.free<byte>($A.thaw<byte>(fz_o))
  in ok end

(* With a bats.lock: installs into bats_modules exactly the versions it
   locks, fetching from the repository repo[0, rl) those it does not
   hold, and fails when the lock does not match the project: a package
   used but not locked, one locked but not used, or a locked version
   bats.toml's constraints rule out (what 'bats lock' would change other
   than to newer versions). ds: the path dependencies, already copied *)
fn locked_deps {n:nat}{lr:agz}
  (ds: !pdeps(n), repo: !$A.borrow(byte, lr, 4096), rl: int): bool = let
  var err : $B.builder_v = $B.create()
  val () = bput_v(err, "error: ")
  val @(cst, cs) = project_cons(err)
in locked_with(cst, cs, err, ds, repo, rl) end

(* Before build, check or test: with a bats.lock, bats_modules holds
   exactly the versions it locks (locked_deps); without one, every #use
   package of src/ that is not a path dependency must be in bats_modules,
   and the missing ones are fetched from the repository repo[0, rplen),
   or reported when there is none (Rust: build::resolve_deps). false
   after an error. *)
#pub fn resolve_deps {lr:agz} (repo: !$A.borrow(byte, lr, 4096), rplen: int): bool

implement resolve_deps {lr} (repo, rplen) = let
  val ds = project_pdeps()
  (* Path dependencies are copied first, fresh each time *)
  val copied = copy_path_deps(ds)
in
  if ~copied then let
    val () = pdeps_free(ds)
    val () = set_build_err()
  in false end
  else if lock_exists() then let
    val ok = locked_deps(ds, repo, rplen)
    val () = pdeps_free(ds)
    val () = (if ok then () else set_build_err())
  in ok end
  else let
    var src : $B.builder_v = $B.create()
    val () = bput_v(src, "src")
    val pkgs = names_rev(collect_uses(src), names_nil())
    val pn = pdeps_names(ds)
    val () = pdeps_free(ds)
    val missing = names_missing(pkgs, pn)
    val () = names_free(pn)
  in
    if names_empty(missing) then let
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
    val @(st, n) = resolve_all(stack, all2, cs2, pn, repo_packages(repo, rplen), repo, rplen, dev, lock, 0)
    val () = names_free(pn)
  in finish_lock(st, n, lock, dry) end

(* bats lock --repository <repo[0, rplen)> [--dev] [--dry-run]: resolves
   the #use packages of src/ and writes bats.lock, or with --dry-run
   compares them with it (Rust: cmd_lock, generate).
   rplen is 0 when --repository was not given. *)
#pub fn do_lock {lr:agz}
  (dev: bool, dry_run: bool, repo: !$A.borrow(byte, lr, 4096), rplen: int): void

implement do_lock {lr} (dev, dry_run, repo, rplen) =
  if rplen <= 0 then let
    val () = set_build_err()
  in prerr! ("error: 'bats lock' requires --repository <dir>\n") end
  else let
    var err : $B.builder_v = $B.create()
    val () = bput_v(err, "error: ")
    val @(cst, cs) = project_cons(err)
  in lock_with(cst, cs, err, repo, rplen, dev, dry_run) end
