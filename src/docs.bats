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
fun line_start {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), p: pos_t, max: int n, fuel: int fuel): pos_t =
  if fuel <= 0 then p
  else if p <= 0 then 0
  else if peek(src, p - 1, max) = 10 then p
  else line_start(src, p - 1, max, fuel - 1)

fun skip_blanks {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), p: pos_t, e: pos_t, max: int n, fuel: int fuel): pos_t =
  if fuel <= 0 then p
  else if p >= e then p
  else if is_blank(peek(src, p, max)) then skip_blanks(src, p + 1, e, max, fuel - 1)
  else p

(* Where the text of the doc line [ls, le) starts, or ~1 when it is not
   a doc line: after leading blanks it starts with /// but not ////, and
   the text follows the /// and one optional space. *)
fn doc_body {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), ls: pos_t, le: pos_t, max: int n): pos_t = let
  val t = skip_blanks(src, ls, le, max, max)
in
  if t + 3 > le then ~1
  else if peek(src, t, max) <> 47 then ~1
  else if peek(src, t + 1, max) <> 47 then ~1
  else if peek(src, t + 2, max) <> 47 then ~1
  else if t + 3 < le && peek(src, t + 3, max) = 47 then ~1
  else if t + 3 < le && peek(src, t + 3, max) = 32 then t + 4
  else t + 3
end

(* The first line of the run of doc lines that ends with the newline at
   le, or le + 1 when the line ending at le is not a doc line. *)
fun doc_top {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), le: pos_t, max: int n, fuel: int fuel): pos_t =
  if fuel <= 0 then le + 1
  else let
    val ls = line_start(src, le, max, max)
  in
    if doc_body(src, ls, le, max) < 0 then le + 1
    else if ls <= 0 then 0
    else doc_top(src, ls - 1, max, fuel - 1)
  end

fun find_newline {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), p: pos_t, max: int n, fuel: int fuel): pos_t =
  if fuel <= 0 then p
  else if p >= max then p
  else if peek(src, p, max) = 10 then p
  else find_newline(src, p + 1, max, fuel - 1)

(* The text of the doc line starting at p; returns the position after it *)
fn put_doc_line {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), p: pos_t, max: int n,
   out: !$B.builder_v >> $B.builder_v): pos_t = let
  val le = find_newline(src, p, max, max)
  val b = doc_body(src, p, le, max)
  val bs = (if b >= 0 then b else le): pos_t
  val () = copy_to_builder_v(src, bs, le, max, out)
in le + 1 end

(* A newline and the text of each doc line in [p, stop) *)
fun put_doc_rest {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), p: pos_t, stop: pos_t, max: int n,
   out: !$B.builder_v >> $B.builder_v, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if p >= stop then ()
  else let
    val () = put_char_v(out, 10)
    val np = put_doc_line(src, p, max, out)
  in put_doc_rest(src, np, stop, max, out, fuel - 1) end

(* "\n<doc>\n" for the #pub at ss, when doc lines end right above it:
   the texts of the lines joined with newlines, as in the Rust bats *)
fn put_doc_comment {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), ss: pos_t, max: int n,
   out: !$B.builder_v >> $B.builder_v): void =
  if ss <= 0 then ()
  else if peek(src, ss - 1, max) <> 10 then ()
  else let
    val top = doc_top(src, ss - 1, max, max)
  in
    if top >= ss then ()
    else let
      val () = put_char_v(out, 10)
      val np = put_doc_line(src, top, max, out)
      val () = put_doc_rest(src, np, ss, max, out, max)
    in put_char_v(out, 10) end
  end

(* ============================================================
   Module pages
   ============================================================ *)

fun trim_start {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), p: pos_t, e: pos_t, max: int n, fuel: int fuel): pos_t =
  if fuel <= 0 then p
  else if p >= e then p
  else if is_trim_ws(peek(src, p, max)) then trim_start(src, p + 1, e, max, fuel - 1)
  else p

fun trim_end {l:agz}{n:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, max: int n, fuel: int fuel): pos_t =
  if fuel <= 0 then e
  else if e <= s then e
  else if is_trim_ws(peek(src, e - 1, max)) then trim_end(src, s, e - 1, max, fuel - 1)
  else e

(* "\n### `<signature>`\n" and its doc comment for each #pub span from
   idx on (kind 2, dest 1: contents in [aux1, aux2)); returns count plus
   the number of them. *)
fun put_entries {ls:agz}{ns:pos}{lp:agz}{np:pos}{fuel:nat} .<fuel>.
  (src: !$A.borrow(byte, ls, ns), max: int ns,
   spans: !$A.borrow(byte, lp, np), span_max: int np,
   span_count: int, idx: pos_t,
   out: !$B.builder_v >> $B.builder_v, count: int, fuel: int fuel): int =
  if fuel <= 0 then count
  else if idx >= span_count then count
  else let
    val base = idx * 28
  in
    if peek(spans, base, span_max) = 2 && peek(spans, base + 1, span_max) = 1 then let
      val ss = span_i32(spans, base + 2, span_max)
      val ts = trim_start(src, span_i32(spans, base + 10, span_max),
                          span_i32(spans, base + 14, span_max), max, max)
      val te = trim_end(src, ts, span_i32(spans, base + 14, span_max), max, max)
      val () = bput_v(out, "\n### `")
      val () = copy_to_builder_v(src, ts, te, max, out)
      val () = bput_v(out, "`\n")
      val () = put_doc_comment(src, ss, max, out)
    in put_entries(src, max, spans, span_max, span_count, idx + 1, out, count + 1, fuel - 1) end
    else put_entries(src, max, spans, span_max, span_count, idx + 1, out, count, fuel - 1)
  end

(* The entries of the .bats file at path, appended to out; the number of
   them, or ~1 when the file cannot be read. *)
fn put_file_entries {lp:agz}
  (path: !$A.borrow(byte, lp, 524288), out: !$B.builder_v >> $B.builder_v): int = let
  val or = $F.file_open(path, 524288, 0, 0)
in
  case+ or of
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(524288)
      val rr = $F.file_read(fd, buf, 524288)
      val @(nbytes, ok) = (case+ rr of
        | ~$R.ok(n) => @(n, true) | ~$R.err(_) => @(0, false)): @([k:nat | k <= 524288] int k, bool)
      val () = $R.discard<int><int>($F.file_close(fd))
      val @(fz_src, bv_src) = $A.freeze<byte>(buf)
      val @(span_arr, _, span_count) = do_lex(bv_src, nbytes, 524288)
      val @(fz_sp, bv_sp) = $A.freeze<byte>(span_arr)
      val n = put_entries(bv_src, 524288, bv_sp, 524288, span_count, 0, out, 0, 524288)
      val () = $A.drop<byte>(fz_sp, bv_sp)
      val () = $A.free<byte>($A.thaw<byte>(fz_sp))
      val () = $A.drop<byte>(fz_src, bv_src)
      val () = $A.free<byte>($A.thaw<byte>(fz_src))
    in if ok then n else ~1 end
  | ~$R.err(_) => ~1
end

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
  val dr = $F.dir_open(dir, 524288)
in case+ dr of
  | ~$R.ok(d) => let
      fun loop {fuel:nat} .<fuel>.
        (d: !$F.dir, dir: !$A.borrow(byte, ld, 524288), dlen: pos_t,
         dirs: !$B.builder_v >> $B.builder_v, files: !$B.builder_v >> $B.builder_v,
         fuel: int fuel): void =
        if fuel <= 0 then ()
        else let
          val e = $A.alloc<byte>(256)
          val el = dir_name_len($F.dir_next(d, e, 256))
          val c0 = peek_arr(e, 0, 256)
          val c1 = peek_arr(e, 1, 256)
        in
          if el < 0 then $A.free<byte>(e)
          else if el = 0 then let val () = $A.free<byte>(e)
            in loop(d, dir, dlen, dirs, files, fuel - 1) end
          else if el <= 2 && c0 = 46 && (el = 1 || c1 = 46) then let
            val () = $A.free<byte>(e)
          in loop(d, dir, dlen, dirs, files, fuel - 1) end
          else let
            val is_bats = has_bats_ext(e, el, 256)
            val @(fz_e, bv_e) = $A.freeze<byte>(e)
            var cb : $B.builder_v = $B.create()
            val () = copy_to_builder_v(dir, 0, dlen, 524288, cb)
            val () = put_char_v(cb, 47)
            val () = copy_to_builder_v(bv_e, 0, el, 256, cb)
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
          in loop(d, dir, dlen, dirs, files, fuel - 1) end
        end
      val () = loop(d, dir, dlen, dirs, files, 65536)
    in $R.discard<int><int>($F.dir_close(d)) end
  | ~$R.err(_) => ()
end

(* Lists every directory in the NUL-separated list lvl[off, len), then
   the next level down, until no directories are left. *)
fun walk_level {l:agz}{fuel:nat} .<fuel>.
  (lvl: !$A.borrow(byte, l, 524288), off: pos_t, len: int,
   next: !$B.builder_v >> $B.builder_v, files: !$B.builder_v >> $B.builder_v,
   fuel: int fuel): void =
  if fuel <= 0 then ()
  else if off >= len then ()
  else let
    val e = find_null_bv_from(lvl, off, 524288)
    val da = path_at(lvl, off)
    val @(fz_d, bv_d) = $A.freeze<byte>(da)
    val () = list_dir(bv_d, e - off, next, files)
    val () = $A.drop<byte>(fz_d, bv_d)
    val () = $A.free<byte>($A.thaw<byte>(fz_d))
  in walk_level(lvl, e + 1, len, next, files, fuel - 1) end

fun walk_levels {fuel:nat} .<fuel>.
  (lvl: $B.builder_v, files: !$B.builder_v >> $B.builder_v, fuel: int fuel): void = let
  val @(la, llen) = $B.to_arr(lvl)
in
  if fuel <= 0 then $A.free<byte>(la)
  else if llen <= 0 then $A.free<byte>(la)
  else let
    val @(fz_l, bv_l) = $A.freeze<byte>(la)
    var next : $B.builder_v = $B.create()
    val () = walk_level(bv_l, 0, llen, next, files, 65536)
    val () = $A.drop<byte>(fz_l, bv_l)
    val () = $A.free<byte>($A.thaw<byte>(fz_l))
  in walk_levels(next, files, fuel - 1) end
end

(* Byte i of the path at a, for ordering: ~1 past its end and 0 for '/',
   so that paths order component by component, as Rust's PathBuf does. *)
fn path_key {l:agz} (lst: !$A.borrow(byte, l, 524288), a: pos_t, i: pos_t): int = let
  val b = peek(lst, a + i, 524288)
in if b = 0 then ~1 else if b = 47 then 0 else b end

(* Whether the path at a orders before the path at b *)
fun path_less {l:agz}{fuel:nat} .<fuel>.
  (lst: !$A.borrow(byte, l, 524288), a: pos_t, b: pos_t, i: pos_t, fuel: int fuel): bool =
  if fuel <= 0 then false
  else let
    val ka = path_key(lst, a, i)
    val kb = path_key(lst, b, i)
  in
    if ka < kb then true
    else if ka > kb then false
    else if ka < 0 then false
    else path_less(lst, a, b, i + 1, fuel - 1)
  end

(* The first path in lst[off, len) after prev (any, when prev < 0), or
   ~1 when there is none. best: the smallest found so far, or ~1. *)
fun next_path {l:agz}{fuel:nat} .<fuel>.
  (lst: !$A.borrow(byte, l, 524288), off: pos_t, len: int,
   prev: pos_t, best: pos_t, fuel: int fuel): pos_t =
  if fuel <= 0 then best
  else if off >= len then best
  else let
    val after = (if prev < 0 then true else path_less(lst, prev, off, 0, 4096)): bool
    val better = (if best < 0 then true else path_less(lst, off, best, 0, 4096)): bool
    val best1 = (if after && better then off else best): pos_t
  in next_path(lst, find_null_bv_from(lst, off, 524288) + 1, len, prev, best1, fuel - 1) end

(* ============================================================
   Writing docs/
   ============================================================ *)

fun prerr_path {l:agz}{fuel:nat} .<fuel>.
  (lst: !$A.borrow(byte, l, 524288), p: pos_t, e: pos_t, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if p >= e then ()
  else let
    val () = prerr_char(int2char0(peek(lst, p, 524288)))
  in prerr_path(lst, p + 1, e, fuel - 1) end

(* Writes page to docs/<module>.md when it has entries (n > 0), the
   module name being files[ns, ne); consumes page. 1 when written, 0
   when there was nothing to write, ~1 on an error (n < 0: the file at
   files[off, e) could not be read). *)
fn write_page {l:agz}
  (page: $B.builder_v, n: int, files: !$A.borrow(byte, l, 524288),
   off: pos_t, e: pos_t, ns: pos_t, ne: pos_t): int =
  if n < 0 then let
    val () = $B.builder_free(page)
    val () = prerr! ("error: cannot read '")
    val () = prerr_path(files, off, e, 4096)
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

(* Writes docs/<module>.md for each file in files[0, len) after prev, in
   order, adding each written module to idx. Returns count plus the
   modules written, or ~1 on an error. *)
fun write_modules {l:agz}{fuel:nat} .<fuel>.
  (files: !$A.borrow(byte, l, 524288), len: int, prev: pos_t,
   idx: !$B.builder_v >> $B.builder_v, count: int, fuel: int fuel): int =
  if fuel <= 0 then count
  else let
    val off = next_path(files, 0, len, prev, ~1, 65536)
  in
    if off < 0 then count
    else let
      val e = find_null_bv_from(files, off, 524288)
      val ns = find_basename_start(files, off, 524288, off - 1, 4096)
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
      else if r = 0 then write_modules(files, len, off, idx, count, fuel - 1)
      else let
        val () = bput_v(idx, "- [")
        val () = copy_to_builder_v(files, ns, ne, 524288, idx)
        val () = bput_v(idx, "](")
        val () = copy_to_builder_v(files, ns, ne, 524288, idx)
        val () = bput_v(idx, ".md)\n")
      in write_modules(files, len, off, idx, count + 1, fuel - 1) end
    end
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
  val count = write_modules(bv_f, flen, ~1, idx, 0, 65536)
  val () = $A.drop<byte>(fz_f, bv_f)
  val () = $A.free<byte>($A.thaw<byte>(fz_f))
in write_index(idx, count, name, nlen, max) end

(* Whether kbuf[0, klen) is "lib" *)
fn is_lib_kind {l:agz} (kbuf: !$A.arr(byte, l, 32), klen: int): bool =
  klen = 3 && peek_arr(kbuf, 0, 32) = 108 && peek_arr(kbuf, 1, 32) = 105
    && peek_arr(kbuf, 2, 32) = 98

(* Writes docs/ when bats.toml has kind = "lib", as the Rust bats's check
   does. Returns 0, or ~1 on an error. *)
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
      val () = (case+ trr of | ~$R.ok(_) => () | ~$R.err(_) => ())
      val () = $R.discard<int><int>($F.file_close(tfd))
      val @(fz_tb, bv_tb) = $A.freeze<byte>(tbuf)
      val pr = $T.parse(bv_tb, 8192)
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
          val is_lib = is_lib_kind(kbuf, klen)
          val () = $A.free<byte>(kbuf)
          val nlen = (case+ nr of | ~$R.some(k) => k | ~$R.none() => 0): int
          val @(fz_nb, bv_nb) = $A.freeze<byte>(nbuf)
          val rc = (if is_lib then generate_docs(bv_nb, nlen, 256) else 0): int
          val () = $A.drop<byte>(fz_nb, bv_nb)
          val () = $A.free<byte>($A.thaw<byte>(fz_nb))
        in rc end
      | ~$R.err(_) => 0
    end
  | ~$R.err(_) => 0
end
