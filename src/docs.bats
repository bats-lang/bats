(* docs -- docs/ for a library, as the Rust bats's doc.rs writes them:
   docs/<module>.md for each src .bats file with #pub declarations,
   each one "### `signature`" followed by its /// comment, and
   docs/index.md listing the modules. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use toml as T
#use str as S

staload "helpers.sats"
staload "lexer.sats"

(* ============================================================
   Doc comments: the /// lines right above a #pub
   ============================================================ *)

fn is_blank(b: int): bool = b = 32 || b = 9

(* Whitespace that Rust's str::trim removes, among ASCII bytes *)
fn is_trim_ws(b: int): bool =
  b = 32 || b = 9 || b = 10 || b = 11 || b = 12 || b = 13

(* Start of the line that holds position p: the first q <= p with q = 0
   or a newline at q - 1. *)
fun line_start {l:agz}{n:pos}{p:nat | p <= n} .<p>.
  (src: !$A.borrow(byte, l, n), p: int p): [q:nat | q <= p] int q =
  if p <= 0 then 0
  else if byte2int0($A.read<byte>(src, p - 1)) = 10 then p
  else line_start(src, p - 1)

fun skip_blanks {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else if is_blank(byte2int0($A.read<byte>(src, p))) then skip_blanks(src, p + 1, e)
  else p

(* Where the text of the doc line [ls, le) starts, or ~1 when it is not
   a doc line: after leading blanks it starts with /// but not ////, and
   the text follows the /// and one optional space. *)
fn doc_body {l:agz}{n:pos}{ls,le:nat | ls <= le; le <= n}
  (src: !$A.borrow(byte, l, n), ls: int ls, le: int le): [b:int | b <= le] int b = let
  val t = skip_blanks(src, ls, le)
in
  if t + 3 > le then ~1
  else if byte2int0($A.read<byte>(src, t)) <> 47 then ~1
  else if byte2int0($A.read<byte>(src, t + 1)) <> 47 then ~1
  else if byte2int0($A.read<byte>(src, t + 2)) <> 47 then ~1
  else if t + 3 >= le then t + 3
  else let
    val c = byte2int0($A.read<byte>(src, t + 3))
  in if c = 47 then ~1 else if c = 32 then t + 4 else t + 3 end
end

(* The first line of the run of doc lines that ends with the newline at
   le, or le + 1 when the line ending at le is not a doc line. *)
fun doc_top {l:agz}{n:pos}{le:nat | le < n} .<le>.
  (src: !$A.borrow(byte, l, n), le: int le): [r:nat | r <= le + 1] int r = let
  val ls = line_start(src, le)
in
  if doc_body(src, ls, le) < 0 then le + 1
  else if ls <= 0 then 0
  else doc_top(src, ls - 1)
end

fun find_newline {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n): [q:nat | p <= q; q <= n] int q =
  if p >= max then p
  else if byte2int0($A.read<byte>(src, p)) = 10 then p
  else find_newline(src, p + 1, max)

(* The text of the doc line starting at p; returns the position after it *)
fn put_doc_line {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), p: int p, max: int n,
   out: !$B.builder_v >> $B.builder_v): [r:int | p < r; r <= n + 1] int r = let
  val le = find_newline(src, p, max)
  val b = doc_body(src, p, le)
  val () = (if b >= 0 then copy_to_builder_v(src, b, le, max, out)
            else copy_to_builder_v(src, le, le, max, out))
in le + 1 end

(* A newline and the text of each doc line in [p, stop) *)
fun put_doc_rest {l:agz}{n:pos}{p:nat | p <= n + 1}{s:nat | s <= n} .<n + 1 - p>.
  (src: !$A.borrow(byte, l, n), p: int p, stop: int s, max: int n,
   out: !$B.builder_v >> $B.builder_v): void =
  if p >= stop then ()
  else let
    val () = put_char_v(out, 10)
    val np = put_doc_line(src, p, max, out)
  in put_doc_rest(src, np, stop, max, out) end

(* "\n<doc>\n" for the #pub at ss, when doc lines end right above it:
   the texts of the lines joined with newlines, as in the Rust bats *)
fn put_doc_comment {l:agz}{n:pos}{s:nat | s <= n}
  (src: !$A.borrow(byte, l, n), ss: int s, max: int n,
   out: !$B.builder_v >> $B.builder_v): void =
  if ss <= 0 then ()
  else if byte2int0($A.read<byte>(src, ss - 1)) <> 10 then ()
  else let
    val top = doc_top(src, ss - 1)
  in
    if top >= ss then ()
    else let
      val () = put_char_v(out, 10)
      val np = put_doc_line(src, top, max, out)
      val () = put_doc_rest(src, np, ss, max, out)
    in put_char_v(out, 10) end
  end

(* ============================================================
   Module pages
   ============================================================ *)

(* Past the whitespace at the start of src[p, e) *)
fun trim_start {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int e): [q:int | p <= q; q <= e] int q =
  if p >= e then p
  else if is_trim_ws(byte2int0($A.read<byte>(src, p))) then trim_start(src, p + 1, e)
  else p

(* Before the whitespace at the end of src[s, e) *)
fun trim_end {l:agz}{n:pos}{s,e:nat | s <= e; e <= n} .<e - s>.
  (src: !$A.borrow(byte, l, n), s: int s, e: int e): [q:int | s <= q; q <= e] int q =
  if e <= s then e
  else if is_trim_ws(byte2int0($A.read<byte>(src, e - 1))) then trim_end(src, s, e - 1)
  else e

(* "\n### `<signature>`\n" and its doc comment for each #pub declaration
   of xs (not in a $UNITTEST block: ut is the depth of those); returns
   count plus the number of them. *)
fun put_entries {ls:agz}{ns:pos}{k:nat} .<k>.
  (src: !$A.borrow(byte, ls, ns), max: int ns, xs: !spans(ns, k),
   out: !$B.builder_v >> $B.builder_v, count: int, ut: int): int =
  case+ xs of
  | spans_nil() => count
  | spans_cons(sp, tl) =>
    (case+ sp of
     | SUnittestBegin(_, _, _, _) => put_entries(src, max, tl, out, count, ut + 1)
     | SUnittestEnd(_, _) => put_entries(src, max, tl, out, count, (if ut > 0 then ut - 1 else 0))
     | SPub(ss, se, rejected, cs) =>
       if ut > 0 then put_entries(src, max, tl, out, count, ut)
       else if rejected then put_entries(src, max, tl, out, count, ut)
       else let
         val ts = trim_start(src, cs, se)
         val te = trim_end(src, ts, se)
         val () = bput_v(out, "\n### `")
         val () = copy_to_builder_v(src, ts, te, max, out)
         val () = bput_v(out, "`\n")
         val () = put_doc_comment(src, ss, max, out)
       in put_entries(src, max, tl, out, count + 1, ut) end
     | _ => put_entries(src, max, tl, out, count, ut))

(* The entries of the .bats file at path, appended to out; the number of
   them, or ~1 when the file cannot be read. *)
fn put_file_entries {lp:agz}
  (path: !$A.borrow(byte, lp, 524288), out: !$B.builder_v >> $B.builder_v): int =
  case+ read_whole(path, 524288) of
  | ~whole_ok(ar, piece, m, nbytes) => let
      val @(fz_src, bv_src) = $A.freeze<byte>(piece)
      val xs = lex_spans(bv_src, nbytes, m)
      val n = put_entries(bv_src, m, xs, out, 0, 0)
      val () = spans_free(xs)
      val () = $A.drop<byte>(fz_src, bv_src)
      val () = whole_free(ar, $A.thaw<byte>(fz_src))
    in n end
  | ~whole_err(_) => ~1

(* ============================================================
   Finding the src .bats files, in the Rust bats's order
   ============================================================ *)

(* The path at off in a NUL-separated list, as a NUL-terminated array *)
fn path_at {l:agz} (lst: !$A.borrow(byte, l, 524288), off: pos_t): [lo:agz] $A.arr(byte, lo, 524288) = let
  var pb : $B.builder_v = $B.create()
  val e = find_null_bv_from(lst, off, 524288)
  val () = copy_to_builder_v(lst, off, e, 524288, pb)
  val () = put_char_v(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
in pa end

(* Appends dir/<name> for each entry of dir, NUL-terminated: directories
   to dirs, .bats files to files. dir is NUL-terminated at dlen. *)
fn list_dir {ld:agz}
  (dir: !$A.borrow(byte, ld, 524288), dlen: pos_t,
   dirs: !$B.builder_v >> $B.builder_v, files: !$B.builder_v >> $B.builder_v): void = let
  val dr = $F.dir_read(dir, 524288)
in case+ dr of
  | ~$R.ok(d) => let
      fun loop {n,i:nat | i <= n} .<n - i>.
        (d: !$F.entries(n), i: int i, n: int n, dir: !$A.borrow(byte, ld, 524288), dlen: pos_t,
         dirs: !$B.builder_v >> $B.builder_v, files: !$B.builder_v >> $B.builder_v): void =
        if i >= n then ()
        else let
          val e = $A.alloc<byte>(1024)
          val el = $F.entries_name(d, i, e, 1024)
          val c0 = peek_arr(e, 0, 1024)
          val c1 = peek_arr(e, 1, 1024)
        in
          if el = 0 then let val () = $A.free<byte>(e)
            in loop(d, i + 1, n, dir, dlen, dirs, files) end
          else if el <= 2 && c0 = 46 && (el = 1 || c1 = 46) then let
            val () = $A.free<byte>(e)
          in loop(d, i + 1, n, dir, dlen, dirs, files) end
          else let
            val is_bats = has_bats_ext(e, el, 1024)
            val @(fz_e, bv_e) = $A.freeze<byte>(e)
            var cb : $B.builder_v = $B.create()
            val () = copy_to_builder_v(dir, 0, dlen, 524288, cb)
            val () = put_char_v(cb, 47)
            val () = copy_to_builder_v(bv_e, 0, el, 1024, cb)
            val () = $A.drop<byte>(fz_e, bv_e)
            val () = $A.free<byte>($A.thaw<byte>(fz_e))
            val clen = $B.length(cb)
            val () = put_char_v(cb, 0)
            val @(ca, _) = $B.to_arr(cb)
            val @(fz_c, bv_c) = $A.freeze<byte>(ca)
            val cr = $F.dir_open(bv_c, 524288)
            val is_dir = (case+ cr of
              | ~$R.ok(cd) => let val () = $R.discard<int><int>($F.dir_close(cd)) in true end
              | ~$R.err(_) => false): bool
            val () = (if is_dir then copy_to_builder_v(bv_c, 0, clen + 1, 524288, dirs)
                      else if is_bats then copy_to_builder_v(bv_c, 0, clen + 1, 524288, files)
                      else ())
            val () = $A.drop<byte>(fz_c, bv_c)
            val () = $A.free<byte>($A.thaw<byte>(fz_c))
          in loop(d, i + 1, n, dir, dlen, dirs, files) end
        end
      val () = loop(d, 0, $F.entries_count(d), dir, dlen, dirs, files)
    in $F.entries_free(d) end
  | ~$R.err(_) => ()
end

(* Lists every directory in the NUL-separated list lvl[off, len): their
   subdirectories to next, their .bats files to files *)
fun walk_level {l:agz}{off:nat | off <= 524288} .<524288 - off>.
  (lvl: !$A.borrow(byte, l, 524288), off: int off, len: int,
   next: !$B.builder_v >> $B.builder_v, files: !$B.builder_v >> $B.builder_v): void =
  if off >= len then ()
  else let
    val e = $S.find_null_bv_at(lvl, off, 524288)
    val da = path_at(lvl, off)
    val @(fz_d, bv_d) = $A.freeze<byte>(da)
    val () = list_dir(bv_d, e - off, next, files)
    val () = $A.drop<byte>(fz_d, bv_d)
    val () = $A.free<byte>($A.thaw<byte>(fz_d))
  in if e >= 524288 then () else walk_level(lvl, e + 1, len, next, files) end

(* The directories lvl, then the next level down, until no directories
   are left, at most depth levels (Rust's find_bats_files has no limit,
   and recursed until its stack overflowed on a directory cycle); deeper
   directories are an error *)
fun walk_levels {d:nat} .<d>.
  (lvl: $B.builder_v, files: !$B.builder_v >> $B.builder_v, depth: int d): void = let
  val @(la, llen) = $B.to_arr(lvl)
in
  if llen <= 0 then $A.free<byte>(la)
  else if depth <= 0 then let
    val () = $A.free<byte>(la)
    val () = prerr! ("error: directories nested more than 64 levels deep\n")
  in set_build_err() end
  else let
    val @(fz_l, bv_l) = $A.freeze<byte>(la)
    var next : $B.builder_v = $B.create()
    val () = walk_level(bv_l, 0, llen, next, files)
    val () = $A.drop<byte>(fz_l, bv_l)
    val () = $A.free<byte>($A.thaw<byte>(fz_l))
  in walk_levels(next, files, depth - 1) end
end

(* The paths of a NUL-separated list, each by its range [s, e) *)
datavtype plist(int) =
  | plist_nil(0) of ()
  | {k:nat}{s,e:nat | s <= e; e <= 524288} plist_cons(k + 1) of (int s, int e, plist(k))

fun plist_free {k:nat} .<k>. (xs: plist(k)): void =
  case+ xs of
  | ~plist_nil() => ()
  | ~plist_cons(_, _, tl) => plist_free(tl)

(* The paths of lst[off, len), onto acc *)
fun parse_paths {l:agz}{off:nat | off <= 524288}{k:nat} .<524288 - off>.
  (lst: !$A.borrow(byte, l, 524288), off: int off, len: int, acc: plist(k)): [k2:nat] plist(k2) =
  if off >= len then acc
  else let
    val e = $S.find_null_bv_at(lst, off, 524288)
  in
    if e >= 524288 then plist_cons(off, e, acc)
    else parse_paths(lst, e + 1, len, plist_cons(off, e, acc))
  end

(* Byte i of the path [x, xe), for ordering: ~1 past its end and 0 for
   '/', so that paths order component by component, as Rust's PathBuf
   does *)
fn path_key {l:agz}{x,xe,i:nat | x <= xe; xe <= 524288}
  (lst: !$A.borrow(byte, l, 524288), x: int x, xe: int xe, i: int i): int =
  if x + i >= xe then ~1
  else let
    val b = byte2int0($A.read<byte>(lst, x + i))
  in if b = 47 then 0 else b end

(* Whether the path [a, ae) orders before the path [b, be) *)
fun path_less {l:agz}{a,ae,b,be,i:nat | a <= ae; ae <= 524288; b <= be; be <= 524288; i <= ae - a} .<ae - a - i>.
  (lst: !$A.borrow(byte, l, 524288), a: int a, ae: int ae, b: int b, be: int be, i: int i): bool = let
  val ka = path_key(lst, a, ae, i)
  val kb = path_key(lst, b, be, i)
in
  if ka < kb then true
  else if ka > kb then false
  else if a + i >= ae then false
  else path_less(lst, a, ae, b, be, i + 1)
end

(* The path [s, e) inserted into the sorted xs *)
fun path_insert {l:agz}{s,e:nat | s <= e; e <= 524288}{k:nat} .<k>.
  (lst: !$A.borrow(byte, l, 524288), s: int s, e: int e, xs: plist(k)): plist(k + 1) =
  case+ xs of
  | ~plist_nil() => plist_cons(s, e, plist_nil())
  | ~plist_cons(s2, e2, tl) =>
    if path_less(lst, s, e, s2, e2, 0) then plist_cons(s, e, plist_cons(s2, e2, tl))
    else plist_cons(s2, e2, path_insert(lst, s, e, tl))

fun path_sort {l:agz}{k,j:nat} .<k>.
  (lst: !$A.borrow(byte, l, 524288), xs: plist(k), acc: plist(j)): plist(k + j) =
  case+ xs of
  | ~plist_nil() => acc
  | ~plist_cons(s, e, tl) => path_sort(lst, tl, path_insert(lst, s, e, acc))

(* The paths of files[0, len), sorted *)
fn sorted_paths {l:agz} (files: !$A.borrow(byte, l, 524288), len: int): [k:nat] plist(k) =
  path_sort(files, parse_paths(files, 0, len, plist_nil()), plist_nil())

(* The paths xs of files, each NUL-terminated, appended to out *)
fun put_paths {l:agz}{k:nat} .<k>.
  (files: !$A.borrow(byte, l, 524288), xs: !plist(k), out: !$B.builder_v >> $B.builder_v): void =
  case+ xs of
  | plist_nil() => ()
  | plist_cons(s, e, tl) => let
      val () = copy_to_builder_v(files, s, e, 524288, out)
      val () = put_char_v(out, 0)
    in put_paths(files, tl, out) end

(* The .bats files under dir, recursively, NUL-separated and sorted as
   Rust's PathBuf sorts them (project::find_bats_files) *)
#pub fn sorted_bats_files (dir: $B.builder_v): @([l:agz] $A.arr(byte, l, 524288), int)

implement sorted_bats_files (dir) = let
  var root = dir
  val () = put_char_v(root, 0)
  var files : $B.builder_v = $B.create()
  val () = walk_levels(root, files, 64)
  val @(fa, flen) = $B.to_arr(files)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val xs = sorted_paths(bv_f, flen)
  var out : $B.builder_v = $B.create()
  val () = put_paths(bv_f, xs, out)
  val () = plist_free(xs)
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in $B.to_arr(out) end

(* ============================================================
   Writing docs/
   ============================================================ *)

fun prerr_path {l:agz}{p,e:nat | p <= e; e <= 524288} .<e - p>.
  (lst: !$A.borrow(byte, l, 524288), p: int p, e: int e): void =
  if p >= e then ()
  else let
    val () = prerr_char(int2char0(byte2int0($A.read<byte>(lst, p))))
  in prerr_path(lst, p + 1, e) end

(* Writes page to docs/<module>.md when it has entries (n > 0), the
   module name being files[ns, ne); consumes page. 1 when written, 0
   when there was nothing to write, ~1 on an error (n < 0: the file at
   files[off, e) could not be read). *)
fn write_page {l:agz}{off,e:nat | off <= e; e <= 524288}
  (page: $B.builder_v, n: int, files: !$A.borrow(byte, l, 524288),
   off: int off, e: int e, ns: pos_t, ne: pos_t): int =
  if n < 0 then let
    val () = $B.builder_free(page)
    val () = prerr! ("error: cannot read '")
    val () = prerr_path(files, off, e)
    val () = prerr! ("'\n")
  in ~1 end
  else if n = 0 then let
    val () = $B.builder_free(page)
  in 0 end
  else let
    var mp : $B.builder_v = $B.create()
    val () = bput_v(mp, "docs")
    val () = put_char_v(mp, 0)
    val @(ma, _) = $B.to_arr(mp)
    val @(fz_m, bv_m) = $A.freeze<byte>(ma)
    val () = $R.discard<int><int>($F.file_mkdir(bv_m, 524288, 493))
    val () = $A.drop<byte>(fz_m, bv_m)
    val () = $A.free<byte>($A.thaw<byte>(fz_m))
    var outp : $B.builder_v = $B.create()
    val () = bput_v(outp, "docs/")
    val () = copy_to_builder_v(files, ns, ne, 524288, outp)
    val () = bput_v(outp, ".md")
    val () = put_char_v(outp, 0)
    val @(oa, _) = $B.to_arr(outp)
    val @(fz_o, bv_o) = $A.freeze<byte>(oa)
    val rc = write_file_from_builder(bv_o, 524288, page)
    val () = $A.drop<byte>(fz_o, bv_o)
    val () = $A.free<byte>($A.thaw<byte>(fz_o))
  in
    if rc <> 0 then let
      val () = prerr! ("error: cannot write docs\n")
    in ~1 end
    else 1
  end

(* Writes docs/<module>.md for each file of xs (paths in files), in
   order, adding each written module to idx. Returns count plus the
   modules written, or ~1 on an error. *)
fun write_modules {l:agz}{k:nat} .<k>.
  (files: !$A.borrow(byte, l, 524288), xs: !plist(k),
   idx: !$B.builder_v >> $B.builder_v, count: int): int =
  case+ xs of
  | plist_nil() => count
  | plist_cons(off, e, tl) => let
      val ns = find_basename_start(files, off, 524288, off - 1)
      val ne = e - 5
      val pa = path_at(files, off)
      val @(fz_p, bv_p) = $A.freeze<byte>(pa)
      var page : $B.builder_v = $B.create()
      val () = bput_v(page, "# ")
      val () = copy_to_builder_v(files, ns, ne, 524288, page)
      val () = put_char_v(page, 10)
      val n = put_file_entries(bv_p, page)
      val () = $A.drop<byte>(fz_p, bv_p)
      val () = $A.free<byte>($A.thaw<byte>(fz_p))
      val r = write_page(page, n, files, off, e, ns, ne)
    in
      if r < 0 then ~1
      else if r = 0 then write_modules(files, tl, idx, count)
      else let
        val () = bput_v(idx, "- [")
        val () = copy_to_builder_v(files, ns, ne, 524288, idx)
        val () = bput_v(idx, "](")
        val () = copy_to_builder_v(files, ns, ne, 524288, idx)
        val () = bput_v(idx, ".md)\n")
      in write_modules(files, tl, idx, count + 1) end
    end

(* Writes docs/index.md for the modules listed in idx, the package being
   name[0, nlen); consumes idx. 0, or ~1 on an error. *)
fn write_index {l:agz}{n:pos}
  (idx: $B.builder_v, count: int, name: !$A.borrow(byte, l, n), nlen: int, max: int n): int =
  if count <= 0 then let
    val () = $B.builder_free(idx)
  in (if count < 0 then ~1 else 0) end
  else let
    var ib : $B.builder_v = $B.create()
    val () = bput_v(ib, "# ")
    val () = copy_to_builder_v(name, 0, nlen, max, ib)
    val () = bput_v(ib, "\n\n## Modules\n\n")
    val @(ia, ilen) = $B.to_arr(idx)
    val @(fz_i, bv_i) = $A.freeze<byte>(ia)
    val () = copy_to_builder_v(bv_i, 0, ilen, 524288, ib)
    val () = $A.drop<byte>(fz_i, bv_i)
    val () = $A.free<byte>($A.thaw<byte>(fz_i))
    val ip = str_to_path_arr("docs/index.md")
    val @(fz_ip, bv_ip) = $A.freeze<byte>(ip)
    val rc = write_file_from_builder(bv_ip, 524288, ib)
    val () = $A.drop<byte>(fz_ip, bv_ip)
    val () = $A.free<byte>($A.thaw<byte>(fz_ip))
  in
    if rc <> 0 then let
      val () = prerr! ("error: cannot write docs/index.md\n")
    in ~1 end
    else let
      val () = if is_quiet() then () else prerr! ("generated docs (", count, " module(s))\n")
    in 0 end
  end

(* ============================================================
   Entry point
   ============================================================ *)

(* Writes docs/ for the library whose name is name[0, nlen), from the
   .bats files under src/. Returns 0, or ~1 on an error. *)
#pub fn generate_docs {l:agz}{n:pos}
  (name: !$A.borrow(byte, l, n), nlen: int, max: int n): int

implement generate_docs(name, nlen, max) = let
  var root : $B.builder_v = $B.create()
  val () = bput_v(root, "src")
  val () = put_char_v(root, 0)
  var files : $B.builder_v = $B.create()
  val () = walk_levels(root, files, 64)
  val @(fa, flen) = $B.to_arr(files)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  var idx : $B.builder_v = $B.create()
  val xs = sorted_paths(bv_f, flen)
  val count = write_modules(bv_f, xs, idx, 0)
  val () = plist_free(xs)
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in write_index(idx, count, name, nlen, max) end

(* Whether kbuf[0, klen) is "lib" *)
fn is_lib_kind {l:agz} (kbuf: !$A.arr(byte, l, 32), klen: int): bool =
  klen = 3 && peek_arr(kbuf, 0, 32) = 108 && peek_arr(kbuf, 1, 32) = 105
    && peek_arr(kbuf, 2, 32) = 98

(* Writes docs/ when bats.toml has kind = "lib", as the Rust bats's check
   does. Returns 1 for a library whose docs were written, 0 for any other
   package, ~1 on an error. *)
(* Whether the kind kbuf[0, klen) is lib; no kind is lib too, as in Rust's
   config::load *)
fn kind_is_lib {l:agz} (kbuf: !$A.arr(byte, l, 32), klen: int): bool =
  if klen = 0 then true else is_lib_kind(kbuf, klen)

#pub fn generate_lib_docs(): int

implement generate_lib_docs() = let
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val tor = $F.file_open(bv_tp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
in
  case+ tor of
  | ~$R.ok(tfd) => let
      val tbuf = $A.alloc<byte>(8192)
      val trr = $F.file_read(tfd, tbuf, 8192)
      val tn = (case+ trr of | ~$R.ok(n) => n | ~$R.err(_) => 0): [k:nat | k <= 8192] int k
      val () = $R.discard<int><int>($F.file_close(tfd))
      val @(fz_tb, bv_tb) = $A.freeze<byte>(tbuf)
      val pr = $T.parse(bv_tb, tn)
      val () = $A.drop<byte>(fz_tb, bv_tb)
      val () = $A.free<byte>($A.thaw<byte>(fz_tb))
    in
      case+ pr of
      | ~$R.ok(doc) => let
          val sec = $A.alloc<byte>(7)
          val () = make_package(sec)
          val @(fz_s, bv_s) = $A.freeze<byte>(sec)
          val kn = $A.alloc<byte>(4)
          val () = make_name(kn)
          val @(fz_kn, bv_kn) = $A.freeze<byte>(kn)
          val nbuf = $A.alloc<byte>(256)
          val nr = $T.get(doc, bv_s, 7, bv_kn, 4, nbuf, 256)
          val () = $A.drop<byte>(fz_kn, bv_kn)
          val () = $A.free<byte>($A.thaw<byte>(fz_kn))
          val kk = $A.alloc<byte>(4)
          val () = make_kind(kk)
          val @(fz_kk, bv_kk) = $A.freeze<byte>(kk)
          val kbuf = $A.alloc<byte>(32)
          val kr = $T.get(doc, bv_s, 7, bv_kk, 4, kbuf, 32)
          val () = $A.drop<byte>(fz_kk, bv_kk)
          val () = $A.free<byte>($A.thaw<byte>(fz_kk))
          val () = $A.drop<byte>(fz_s, bv_s)
          val () = $A.free<byte>($A.thaw<byte>(fz_s))
          val () = $T.toml_free(doc)
          val klen = (case+ kr of | ~$R.some(k) => k | ~$R.none() => 0): int
          (* No kind is a library, as in Rust's config::load *)
          val is_lib = kind_is_lib(kbuf, klen)
          val () = $A.free<byte>(kbuf)
          val nlen = (case+ nr of | ~$R.some(k) => k | ~$R.none() => 0): int
          val @(fz_nb, bv_nb) = $A.freeze<byte>(nbuf)
          val rc = (if ~is_lib then 0
                    else if generate_docs(bv_nb, nlen, 256) < 0 then ~1
                    else 1): int
          val () = $A.drop<byte>(fz_nb, bv_nb)
          val () = $A.free<byte>($A.thaw<byte>(fz_nb))
        in rc end
      | ~$R.err(_) => 0
    end
  | ~$R.err(_) => 0
end
