staload "./lock.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* lock -- bats lock, as the Rust bats's lock::generate and resolve_all *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

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

(* Compares the digits a[i, i + n) and b[j, j + n) *)
fun digits_cmp {la,lb:agz}{f:nat} .<f>.
  (a: !$A.arr(byte, la, 256), i: pos_t, b: !$A.arr(byte, lb, 256), j: pos_t, n: int, f: int f): int =
  if f <= 0 then 0
  else if n <= 0 then 0
  else let
    val x = peek256(a, i)
    val y = peek256(b, j)
  in
    if x < y then ~1
    else if x > y then 1
    else digits_cmp(a, i + 1, b, j + 1, n - 1, f - 1)
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
  else digits_cmp(a, ai, b, bi, ae - ai, 256)
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

(* Whether c orders after best; a dev version orders before the release
   with the same parts *)
fn cand_newer (c: !cand, best: !cand): bool = let
  val+ @cand_mk(ca, cl, cdev) = c
  val+ @cand_mk(ba, bl, bdev) = best
  val cmp = parts_cmp(ca, 0, cl, ba, 0, bl, 256)
  val d1 = cdev
  val d2 = bdev
  prval () = fold@(best)
  prval () = fold@(c)
in
  if cmp > 0 then true
  else if cmp < 0 then false
  else if d2 then ~d1
  else false
end

(* src[0, n) (n <= 256 checked) into a new name-sized array *)
fun copy_text {ls,ld:agz}{i:nat | i <= 256} .<256 - i>.
  (src: !$A.arr(byte, ls, 524288), n: int, dst: !$A.arr(byte, ld, 256), i: int i): void =
  if i >= 256 then ()
  else if i >= n then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in copy_text(src, n, dst, i + 1) end

(* The version in e[vs, ve) of a file name, parsed and rendered as Rust's
   Version::parse and Display do; none when it does not parse *)
fn parse_cand {le:agz}
  (e: !$A.borrow(byte, le, 256), vs: pos_t, ve: pos_t): $R.option(cand) = let
  var d_c = @[char][4]('d', 'e', 'v', '1')
  val dev = (if ve - vs >= 4 then lit_at(e, ve - 4, 256, d_c, 4) else false): bool
  val be = (if dev then ve - 4 else ve): pos_t
  var out : $B.builder_v = $B.create()
  val @(bad, _) = parse_version_parts(e, vs, be, 256, out)
  val vl = $B.length(out)
  val @(va, _) = $B.to_arr(out)
in
  if bad >= 0 then let
    val () = $A.free<byte>(va)
  in $R.none() end
  else if vl > 256 then let
    val () = $A.free<byte>(va)
  in $R.none() end
  else let
    val t = $A.alloc<byte>(256)
    val () = copy_text(va, vl, t, 0)
    val () = $A.free<byte>(va)
  in $R.some(cand_mk(t, vl, dev)) end
end

(* best, or c when c orders after it; frees the other *)
fn keep_newer (best: $R.option(cand), c: cand): $R.option(cand) =
  case+ best of
  | ~$R.none() => $R.some(c)
  | ~$R.some(b) =>
    if cand_newer(c, b) then let
      val () = cand_free(b)
    in $R.some(c) end
    else let
      val () = cand_free(c)
    in $R.some(b) end

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
   start with pfx[0, pl); dev versions only when dev *)
fun scan_versions {lp:agz}{fuel:nat} .<fuel>.
  (d: !$F.dir, pfx: !$A.borrow(byte, lp, 524288), pl: pos_t, dev: bool,
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
               then parse_cand(bv_e, pl, el - 5) else $R.none()): $R.option(cand)
      val () = $A.drop<byte>(fz_e, bv_e)
      val () = $A.free<byte>($A.thaw<byte>(fz_e))
      val best2 = (case+ c of
        | ~$R.some(cv) =>
          if cand_dev(cv) && ~dev then let
            val () = cand_free(cv)
          in best end
          else keep_newer(best, cv)
        | ~$R.none() => best): $R.option(cand)
    in scan_versions(d, pfx, pl, dev, best2, fuel - 1) end
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

(* The newest version of the package a[0, k) in the repository
   (Rust: find_latest_version) *)
fn find_latest {lr,la:agz}
  (repo: !$A.borrow(byte, lr, 4096), rl: int, a: !$A.arr(byte, la, 256), k: int,
   dev: bool): $R.option(cand) = let
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
        val best = scan_versions(d, bv_p, pl, dev, $R.none(), 65536)
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

(* Resolves the packages on stack, the newest first, into lock lines;
   all holds every package queued so far. @(0 or ~1 on an error, the
   number resolved) (Rust: resolve_all) *)
fun resolve_all {s,m:nat}{lr:agz}{f:nat} .<f>.
  (stack: names(s), all: names(m), repo: !$A.borrow(byte, lr, 4096), rl: int,
   dev: bool, lock: !$B.builder_v >> $B.builder_v, count: int, f: int f): @(int, int) =
  if f <= 0 then let
    val () = names_free(stack)
    val () = names_free(all)
  in @(0, count) end
  else case+ stack of
  | ~names_nil() => let
      val () = names_free(all)
    in @(0, count) end
  | ~names_cons(a, k, rest) => let
      val latest = find_latest(repo, rl, a, k, dev)
    in
      case+ latest of
      | ~$R.none() => let
          val () = not_found(repo, rl, a, k)
          val () = $A.free<byte>(a)
          val () = names_free(rest)
          val () = names_free(all)
        in @(~1, count) end
      | ~$R.some(v) => let
          val @(arc, alen) = archive_path(repo, rl, a, k, v)
          val @(fz_c, bv_c) = $A.freeze<byte>(arc)
          val () = (if is_fetched(a, k) then () else fetch(bv_c, alen, a, k, v))
          val ts = dep_uses(a, k)
          val ok = put_lock_line(bv_c, a, k, v, lock)
          val () = (if ok then () else cannot_read(bv_c, alen))
          val () = $A.drop<byte>(fz_c, bv_c)
          val () = $A.free<byte>($A.thaw<byte>(fz_c))
          val () = cand_free(v)
          val @(stack2, all2) = push_new(ts, rest, all)
          val () = $A.free<byte>(a)
        in
          if ok then resolve_all(stack2, all2, repo, rl, dev, lock, count + 1, f - 1)
          else let
            val () = names_free(stack2)
            val () = names_free(all2)
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

(* bats lock --repository <repo[0, rplen)> [--dev]: resolves the #use
   packages of src/ and writes bats.lock (Rust: cmd_lock, generate).
   rplen is 0 when --repository was not given. *)



implement do_lock {lr} (dev, dry_run, repo, rplen) =
  if rplen <= 0 then let
    val () = set_build_err()
  in prerr! ("error: 'bats lock' requires --repository <dir>\n") end
  else let
    var src : $B.builder_v = $B.create()
    val () = bput_v(src, "src")
    val pkgs = collect_uses(src)
    val all = names_copy(pkgs)
    var lock : $B.builder_v = $B.create()
    val @(st, n) = resolve_all(pkgs, all, repo, rplen, dev <> 0, lock, 0, 65536)
  in finish_lock(st, n, lock) end
