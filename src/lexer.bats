(* lexer -- tokenizer for the bats compiler *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use str as S

staload "helpers.sats"

fn is_ident_start(b: int): bool =
  (b >= 97 && b <= 122) ||
  (b >= 65 && b <= 90) ||
  $AR.eq_int_int(b, 95)

(* ============================================================
   Lexer: span storage
   Each span = 28 bytes in a builder:
     [0] kind  [1] dest
     [2..5] start  [6..9] end
     [10..13] aux1  [14..17] aux2
     [18..21] aux3  [22..25] aux4
     [26..27] padding
   Kinds: 0=passthrough 1=hash_use 2=pub_decl 3=qualified
          4=unsafe_block 5=unsafe_construct 6=extcode
          7=target 8=unittest 9=restricted 10=unittest_run
          11=target_block (opaque, expanded by post-lex pass)
          13=target_begin 14=target_end
   Passthrough (kind 0) spans of comments, string and char literals
   have aux1 = 1: they are copied verbatim, never read as code.
   Dests: 0=dats 1=sats 2=both
   ============================================================ *)

fn put_i32(b: !$B.builder_v >> $B.builder_v, v: int): void = let
  val () = put_char_v(b, v mod 256)
  val v1 = v / 256
  val () = put_char_v(b, v1 mod 256)
  val v2 = v1 / 256
  val () = put_char_v(b, v2 mod 256)
  val () = put_char_v(b, v2 / 256)
in end

fn put_span(b: !$B.builder_v >> $B.builder_v, kind: int, dest: int,
            sp_start: pos_t, sp_end: pos_t,
            a1: int, a2: int, a3: int, a4: int): void = let
  val () = put_char_v(b, kind)
  val () = put_char_v(b, dest)
  val () = put_i32(b, sp_start)
  val () = put_i32(b, sp_end)
  val () = put_i32(b, a1)
  val () = put_i32(b, a2)
  val () = put_i32(b, a3)
  val () = put_i32(b, a4)
  val () = put_char_v(b, 0)
  val () = put_char_v(b, 0)
in end

(* ============================================================
   Lexer: keyword detection helpers
   ============================================================ *)

fn looking_at_2 {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n,
   c0: int, c1: int): bool =
  $AR.eq_int_int(peek(src, pos, max), c0) &&
  $AR.eq_int_int(peek(src, pos + 1, max), c1)

fn is_kw_boundary {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  if pos >= max then true
  else ~(is_ident_byte(peek(src, pos, max)))

fn is_kw_boundary_before {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  if pos <= 0 then true
  else ~(is_ident_byte(peek(src, pos - 1, max)))

fn looking_at_pub {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_hash_pub(src, pos, max) &&
  is_kw_boundary(src, pos + 4, max)

fn looking_at_use {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_hash_use(src, pos, max) &&
  is_kw_boundary(src, pos + 4, max)

fn looking_at_target {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_hash_target(src, pos, max) &&
  is_kw_boundary(src, pos + 7, max)

fn looking_at_unsafe {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_dollar_UNSAFE(src, pos, max)

fn looking_at_unittest {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_dollar_UNITTEST(src, pos, max)

fn looking_at_binary {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_binary(src, pos, max) &&
  is_kw_boundary(src, pos + 6, max)

fn looking_at_begin {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_begin(src, pos, max) &&
  is_kw_boundary(src, pos + 5, max)

fn looking_at_end {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_end(src, pos, max) &&
  is_kw_boundary(src, pos + 3, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_as {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_as(src, pos, max) &&
  is_kw_boundary(src, pos + 2, max)

(* Unsafe construct detectors use manual byte comparisons to avoid
   the preprocessor's textual keyword scanner triggering on string literals *)
fn looking_at_cast_fn {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 99) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 115) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 102) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 110) &&
  is_kw_boundary(src, pos + 6, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_prax_i {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 112) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 114) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 120) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 105) &&
  is_kw_boundary(src, pos + 5, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_ext_ern {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 101) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 120) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 101) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 114) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 110) &&
  is_kw_boundary(src, pos + 6, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_assu_me {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 115) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 115) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 117) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 109) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 101) &&
  is_kw_boundary(src, pos + 6, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_stld {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  is_kw_boundary_before(src, pos, max) &&
  $AR.eq_int_int(peek(src, pos, max), 115) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 108) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 111) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 6, max), 100) &&
  is_kw_boundary(src, pos + 7, max)

fn looking_at_extval {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 36) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 101) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 120) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 118) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 6, max), 108) &&
  is_kw_boundary(src, pos + 7, max)

fn looking_at_extfcall {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 36) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 101) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 120) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 102) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 99) &&
  $AR.eq_int_int(peek(src, pos + 6, max), 97) &&
  $AR.eq_int_int(peek(src, pos + 7, max), 108) &&
  $AR.eq_int_int(peek(src, pos + 8, max), 108) &&
  is_kw_boundary(src, pos + 9, max)

fn looking_at_extype {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 36) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 101) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 120) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 121) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 112) &&
  $AR.eq_int_int(peek(src, pos + 6, max), 101) &&
  is_kw_boundary(src, pos + 7, max)

fn looking_at_extkind {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  $AR.eq_int_int(peek(src, pos, max), 36) &&
  $AR.eq_int_int(peek(src, pos + 1, max), 101) &&
  $AR.eq_int_int(peek(src, pos + 2, max), 120) &&
  $AR.eq_int_int(peek(src, pos + 3, max), 116) &&
  $AR.eq_int_int(peek(src, pos + 4, max), 107) &&
  $AR.eq_int_int(peek(src, pos + 5, max), 105) &&
  $AR.eq_int_int(peek(src, pos + 6, max), 110) &&
  $AR.eq_int_int(peek(src, pos + 7, max), 100) &&
  is_kw_boundary(src, pos + 8, max)

fn looking_at_mac_hash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_machash(src, pos, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_ext_hash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_exthash(src, pos, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_fun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_fun(src, pos, max) &&
  is_kw_boundary(src, pos + 3, max) &&
  is_kw_boundary_before(src, pos, max)

(* ============================================================
   Lexer: typed positions
   A position p is a nat at most n, the source buffer's size; the source
   is src[0, m), m <= n. Every scanner recurses on n - p, so it ends,
   and reads a byte at p only when p < n.
   ============================================================ *)

(* The byte at p, or 0 at or past n (the source reads as NULs after it) *)
fn at {l:agz}{n:pos}{p:nat}
  (src: !$A.borrow(byte, l, n), p: int p, n: int n): int =
  if p < n then byte2int0($A.read<byte>(src, p)) else 0

(* p + k, or n when that is past it *)
fn adv {p,k:nat}{n:nat | p <= n}
  (p: int p, k: int k, n: int n): [q:int | p <= q; q <= n; q == p + k || q == n] int q =
  if p + k <= n then p + k else n

(* Scan forward from pos looking for ".<" before "=" to detect a
   termination metric. True if .<...>. is found: the fun is safe. *)
fun _has_metric {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if pos >= max then false
  else let
    val b = at(src, pos, max)
  in
    (* Found ".<" — has metric *)
    if $AR.eq_int_int(b, 46) then
      if $AR.eq_int_int(at(src, pos + 1, max), 60) then true
      else _has_metric(src, pos + 1, max)
    (* Found standalone "=" — end of signature, no metric *)
    (* Skip <= >= == != by checking the neighbouring bytes: the first
       "=" of "==" is recognised by the next byte, the rest by the
       previous one. *)
    else if $AR.eq_int_int(b, 61) then let
      val prev = (if pos > 0 then at(src, pos - 1, max) else 32): int
      val next = at(src, pos + 1, max)
    in
      if $AR.eq_int_int(next, 61) then _has_metric(src, pos + 1, max)
      else if $AR.eq_int_int(prev, 60) then _has_metric(src, pos + 1, max)
      else if $AR.eq_int_int(prev, 62) then _has_metric(src, pos + 1, max)
      else if $AR.eq_int_int(prev, 61) then _has_metric(src, pos + 1, max)
      else if $AR.eq_int_int(prev, 33) then _has_metric(src, pos + 1, max)
      else false
    end
    (* Found newline followed by non-whitespace — end of declaration *)
    else if $AR.eq_int_int(b, 10) then let
      val nb = at(src, pos + 1, max)
    in
      if $AR.eq_int_int(nb, 32) || $AR.eq_int_int(nb, 9) then
        _has_metric(src, pos + 1, max)
      else false
    end
    else _has_metric(src, pos + 1, max)
  end

fn _content_starts_prfun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_prfun(src, pos, max) &&
  is_kw_boundary(src, pos + 5, max)

(* #pub castfn, praxi, extern or assume: unsafe as a declaration too *)
fn _content_starts_restricted {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  looking_at_cast_fn(src, pos, max) || looking_at_prax_i(src, pos, max) ||
  looking_at_ext_ern(src, pos, max) || looking_at_assu_me(src, pos, max)

fn _content_starts_prfn {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_prfn(src, pos, max) &&
  is_kw_boundary(src, pos + 4, max)

fn _looking_at_primplement {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_primplement(src, pos, max)

fn looking_at_no_mangle {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_no_mangle(src, pos, max) &&
  is_kw_boundary(src, pos + 9, max)

(* ============================================================
   Lexer: sub-lexers
   ============================================================ *)

(* Skip whitespace (space/tab only, not newlines) *)
fun skip_ws {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if pos >= max then pos
  else let val b = at(src, pos, max) in
    if $AR.eq_int_int(b, 32) || $AR.eq_int_int(b, 9) then skip_ws(src, pos + 1, max)
    else pos
  end

(* while is unsafe (no termination proof); while* carries a metric *)
fn looking_at_while {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  lit_while(src, pos, max) &&
  is_kw_boundary(src, pos + 5, max) &&
  is_kw_boundary_before(src, pos, max) &&
  ~($AR.eq_int_int(at(src, skip_ws(src, adv(pos, 5, max), max), max), 42))

(* Skip to end of line, including the newline; past pos when pos < m *)
fun skip_to_eol {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : [q:int | p <= q; q <= n; p < q || m <= p] int q =
  if pos >= src_len then pos
  else if $AR.eq_int_int(at(src, pos, max), 10) then pos + 1
  else skip_to_eol(src, pos + 1, src_len, max)

(* Skip ident chars *)
fun skip_ident {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if pos >= max then pos
  else if is_ident_byte(at(src, pos, max)) then skip_ident(src, pos + 1, max)
  else pos

(* Past a {quantifier} group opened before p: after its "}" *)
fun _skip_brace {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if p >= max then p
  else if $AR.eq_int_int(at(src, p, max), 125) then p + 1
  else _skip_brace(src, p + 1, max)

(* The declaration name's start after a prfun/prfn keyword: past blanks
   and {quantifier} groups *)
fun _skip_to_name {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if pos >= max then pos
  else let val b = at(src, pos, max) in
    if $AR.eq_int_int(b, 32) || $AR.eq_int_int(b, 9) || $AR.eq_int_int(b, 10) then
      _skip_to_name(src, pos + 1, max)
    else if $AR.eq_int_int(b, 123) then
      _skip_to_name(src, _skip_brace(src, pos + 1, max), max)
    else pos
  end

(* Whether src[a, a + k) and src[b, b + k) hold the same bytes *)
fun _names_match {l:agz}{n:pos}{a,b,k:nat} .<k>.
  (src: !$A.borrow(byte, l, n), a: int a, b: int b, len: int k, max: int n): bool =
  if len <= 0 then true
  else if $AR.eq_int_int(at(src, a, max), at(src, b, max)) then
    _names_match(src, a + 1, b + 1, len - 1, max)
  else false

(* Whether a primplement of the name src[name_start, name_start + name_len)
   appears in src[scan_pos, m) *)
fun _has_primplement {l:agz}{n:pos}{m:nat | m <= n}{a,k:nat}{s:nat | s <= n} .<n - s>.
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   name_start: int a, name_len: int k, scan_pos: int s): bool =
  if scan_pos >= src_len then false
  else if _looking_at_primplement(src, scan_pos, max) then let
    val p = _skip_to_name(src, adv(scan_pos, 11, max), max)
    val nend = skip_ident(src, p, max)
  in
    if $AR.eq_int_int(nend - p, name_len) &&
       _names_match(src, name_start, p, name_len, max) then true
    else _has_primplement(src, src_len, max, name_start, name_len, scan_pos + 1)
  end
  else _has_primplement(src, src_len, max, name_start, name_len, scan_pos + 1)

(* Skip non-whitespace *)
fun skip_nonws {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if pos >= max then pos
  else let val b = at(src, pos, max) in
    if $AR.eq_int_int(b, 32) || $AR.eq_int_int(b, 9) ||
       $AR.eq_int_int(b, 10) || $AR.eq_int_int(b, 0)
    then pos
    else skip_nonws(src, pos + 1, max)
  end

(* A sub-lexer's result: the end of what it lexed, past its start s, and
   the span count *)
typedef lexed(s:int, n:int) = @([q:int | s < q; q <= n] int q, int)

(* Lex // line comment. //// = rest-of-file *)
fn lex_line_comment {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) =
  if $AR.eq_int_int(at(src, start + 2, max), 47) &&
     $AR.eq_int_int(at(src, start + 3, max), 47) then let
    val () = put_span(spans, 0, 0, start, src_len, 1, 0, 0, 0)
  in @(src_len, count + 1) end
  else let
    val ep = skip_to_eol(src, adv(start, 2, max), src_len, max)
    val () = put_span(spans, 0, 0, start, ep, 1, 0, 0, 0)
  in @(ep, count + 1) end

(* The end of a /* ... */ comment whose body starts at pos: after its
   close, or m *)
fun lex_c_comment_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : [q:int | q <= n; p <= q || q == m] int q =
  if pos + 1 >= src_len then src_len
  else if $AR.eq_int_int(at(src, pos, max), 42) &&
          $AR.eq_int_int(at(src, pos + 1, max), 47) then pos + 2
  else lex_c_comment_inner(src, pos + 1, src_len, max)

fn lex_c_comment {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) = let
  val ep = lex_c_comment_inner(src, adv(start, 2, max), src_len, max)
  val () = put_span(spans, 0, 0, start, ep, 1, 0, 0, 0)
in @(ep, count + 1) end

(* The end of a nested (* ... *) comment at depth whose body starts at
   pos: after the close that brings depth to 0, or m *)
fun lex_ml_comment_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n,
   depth: int): [q:int | q <= n; p <= q || q == m] int q =
  if depth <= 0 then pos
  else if pos + 1 >= src_len then src_len
  else let
    val b0 = at(src, pos, max)
    val b1 = at(src, pos + 1, max)
  in
    if $AR.eq_int_int(b0, 40) && $AR.eq_int_int(b1, 42) then
      lex_ml_comment_inner(src, pos + 2, src_len, max, depth + 1)
    else if $AR.eq_int_int(b0, 42) && $AR.eq_int_int(b1, 41) then
      lex_ml_comment_inner(src, pos + 2, src_len, max, depth - 1)
    else
      lex_ml_comment_inner(src, pos + 1, src_len, max, depth)
  end

fn lex_ml_comment {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) = let
  val ep = lex_ml_comment_inner(src, adv(start, 2, max), src_len, max, 1)
  val () = put_span(spans, 0, 0, start, ep, 1, 0, 0, 0)
in @(ep, count + 1) end

(* The end of a string literal whose body starts at pos, with \" escapes *)
fun lex_string_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : [q:int | p <= q; q <= n] int q =
  if pos >= src_len then pos
  else let val b = at(src, pos, max) in
    if $AR.eq_int_int(b, 92) then lex_string_inner(src, adv(pos, 2, max), src_len, max)
    else if $AR.eq_int_int(b, 34) then pos + 1
    else lex_string_inner(src, pos + 1, src_len, max)
  end

fn lex_string {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) = let
  val ep = lex_string_inner(src, start + 1, src_len, max)
  val () = put_span(spans, 0, 0, start, ep, 1, 0, 0, 0)
in @(ep, count + 1) end

(* Lex char literal '...' *)
fn lex_char_lit {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) = let
  val p1 = start + 1
  val p2 = (if $AR.eq_int_int(at(src, p1, max), 92) then adv(p1, 2, max)
            else adv(p1, 1, max)): [q:int | s < q; q <= n] int q
  val p3 = (if $AR.eq_int_int(at(src, p2, max), 39) then adv(p2, 1, max)
            else p2): [q:int | s < q; q <= n] int q
  val () = put_span(spans, 0, 0, start, p3, 1, 0, 0, 0)
in @(p3, count + 1) end

(* The end of %{ ... %} C code whose body starts at pos: after the %},
   or m *)
fun lex_extcode_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : [q:int | q <= n; p <= q || q == m] int q =
  if pos + 1 >= src_len then src_len
  else if $AR.eq_int_int(at(src, pos, max), 37) &&
          $AR.eq_int_int(at(src, pos + 1, max), 125) then pos + 2
  else lex_extcode_inner(src, pos + 1, src_len, max)

fn lex_extcode {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) = let
  val after_open = adv(start, 2, max)
  val bk = at(src, after_open, max)
  val kind = (if $AR.eq_int_int(bk, 94) then 1
              else if $AR.eq_int_int(bk, 36) then 2
              else if $AR.eq_int_int(bk, 35) then 3
              else 0): int
  val cstart = (if kind > 0 then adv(after_open, 1, max)
                else after_open): [q:int | s < q; q <= n] int q
  val ep = lex_extcode_inner(src, cstart, src_len, max)
  val cend = (if ep >= 2 then ep - 2 else ep): int
  val () = put_span(spans, 6, 0, start, ep, cstart, cend, kind, 0)
in @(ep, count + 1) end

(* Lex #use pkg as Alias [no_mangle] *)
fn lex_hash_use {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int): lexed(s, n) = let
  val p0 = skip_ws(src, adv(start, 4, max), max)
  val pkg_start = p0
  val pkg_end = skip_nonws(src, p0, max)
  val p1 = skip_ws(src, pkg_end, max)
  val p2 = (if looking_at_as(src, p1, max) then adv(p1, 2, max)
            else p1): [q:int | s < q; q <= n] int q
  val p3 = skip_ws(src, p2, max)
  val alias_start = p3
  val alias_end = skip_ident(src, p3, max)
  val p4 = skip_ws(src, alias_end, max)
  val mangle = (if looking_at_no_mangle(src, p4, max) then 0 else 1): int
  val ep = skip_to_eol(src, p4, src_len, max)
  val () = put_span(spans, 1, mangle + 1, start, ep,
                    pkg_start, pkg_end, alias_start, alias_end)
in @(ep, count + 1) end

(* Lex $Alias.member qualified access: past start when it is one, else
   start itself *)
fn lex_qualified {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int)
  : @([q:int | s <= q; q <= n] int q, int) = let
  val alias_start = start + 1
  val alias_end = skip_ident(src, alias_start, max)
in
  if $AR.eq_int_int(at(src, alias_end, max), 46) then let
    val member_start = adv(alias_end, 1, max)
    val member_end = skip_ident(src, member_start, max)
  in
    if member_end > member_start then let
      val () = put_span(spans, 3, 0, start, member_end,
                        alias_start, alias_end, member_start, member_end)
    in @(member_end, count + 1) end
    else @(start, count)
  end
  else @(start, count)
end

(* Check if line at pos is blank *)
fun is_blank_line {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n): bool =
  if pos >= src_len then true
  else let val b = at(src, pos, max) in
    if $AR.eq_int_int(b, 10) then true
    else if $AR.eq_int_int(b, 32) || $AR.eq_int_int(b, 9) then
      is_blank_line(src, pos + 1, src_len, max)
    else false
  end

(* Past the blank lines at p *)
fun skip_blanks {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, src_len: int m, max: int n)
  : [q:int | p <= q; q <= n] int q =
  if p >= src_len then p
  else if is_blank_line(src, p, src_len, max) then
    skip_blanks(src, skip_to_eol(src, p, src_len, max), src_len, max)
  else p

(* Lex #pub declaration - find end of block *)
fun lex_pub_lines {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : [q:int | p <= q; q <= n] int q =
  if pos >= src_len then pos
  else let
    val eol = skip_to_eol(src, pos, src_len, max)
  in
    if eol >= src_len then eol
    else if is_blank_line(src, eol, src_len, max) then let
      (* Past blank lines: if the next non-blank starts with 'and', continue *)
      val next = skip_blanks(src, eol, src_len, max)
    in
      if next < src_len &&
         $AR.eq_int_int(at(src, next, max), 97) &&
         $AR.eq_int_int(at(src, next + 1, max), 110) &&
         $AR.eq_int_int(at(src, next + 2, max), 100) &&
         is_kw_boundary(src, next + 3, max)
      then lex_pub_lines(src, eol, src_len, max)
      else eol
    end
    else if looking_at_pub(src, eol, max) then eol
    else if looking_at_use(src, eol, max) then eol
    else if looking_at_target(src, eol, max) then eol
    else if looking_at_unsafe(src, eol, max) then eol
    else if looking_at_unittest(src, eol, max) then eol
    else let val b = at(src, eol, max) in
      if $AR.eq_int_int(b, 102) &&
         ($AR.eq_int_int(at(src, eol + 1, max), 117) &&
          $AR.eq_int_int(at(src, eol + 2, max), 110) &&
          is_kw_boundary(src, eol + 3, max)) then eol
      else if $AR.eq_int_int(b, 102) &&
              $AR.eq_int_int(at(src, eol + 1, max), 110) &&
              is_kw_boundary(src, eol + 2, max) then eol
      else if $AR.eq_int_int(b, 118) &&
              $AR.eq_int_int(at(src, eol + 1, max), 97) &&
              $AR.eq_int_int(at(src, eol + 2, max), 108) &&
              is_kw_boundary(src, eol + 3, max) then eol
      else if $AR.eq_int_int(b, 105) &&
              $AR.eq_int_int(at(src, eol + 1, max), 109) &&
              $AR.eq_int_int(at(src, eol + 2, max), 112) &&
              $AR.eq_int_int(at(src, eol + 3, max), 108) &&
              $AR.eq_int_int(at(src, eol + 4, max), 101) &&
              $AR.eq_int_int(at(src, eol + 5, max), 109) &&
              $AR.eq_int_int(at(src, eol + 6, max), 101) &&
              $AR.eq_int_int(at(src, eol + 7, max), 110) &&
              $AR.eq_int_int(at(src, eol + 8, max), 116) &&
              is_kw_boundary(src, eol + 9, max) then eol
      else if $AR.eq_int_int(b, 37) &&
              $AR.eq_int_int(at(src, eol + 1, max), 123) then eol
      else lex_pub_lines(src, eol, src_len, max)
    end
  end

(* Check for "let" *)
fn looking_at_let {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  is_kw_boundary_before(src, pos, max) &&
  lit_let(src, pos, max) &&
  is_kw_boundary(src, pos + 3, max)

fn looking_at_local {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  is_kw_boundary_before(src, pos, max) &&
  lit_local(src, pos, max) &&
  is_kw_boundary(src, pos + 5, max)

(* The end that closes a block opened before pos at depth, or src_len.
   C code in %{ ... %} is skipped: a word "end" there (in a comment,
   say) is not the keyword. *)
fun find_end_kw {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n,
   depth: int): [q:int | q <= n; p <= q || q == m] int q =
  if pos >= src_len then src_len
  else if $AR.eq_int_int(at(src, pos, max), 37) &&
          $AR.eq_int_int(at(src, pos + 1, max), 123) then
    find_end_kw(src, lex_extcode_inner(src, adv(pos, 2, max), src_len, max),
                src_len, max, depth)
  else if looking_at_end(src, pos, max) then
    (if depth <= 1 then pos
     else find_end_kw(src, adv(pos, 3, max), src_len, max, depth - 1))
  else if looking_at_begin(src, pos, max) then
    find_end_kw(src, adv(pos, 5, max), src_len, max, depth + 1)
  else if looking_at_let(src, pos, max) then
    find_end_kw(src, adv(pos, 3, max), src_len, max, depth + 1)
  else if looking_at_local(src, pos, max) then
    find_end_kw(src, adv(pos, 5, max), src_len, max, depth + 1)
  else find_end_kw(src, pos + 1, src_len, max, depth)

(* After a block whose contents end at ce: past its "end", or m *)
fn block_end {n:nat}{m:nat | m <= n}{c:nat | c <= n}
  (ce: int c, src_len: int m, max: int n): [q:int | c <= q; q <= n] int q =
  if ce < src_len then adv(ce, 3, max) else ce

(* $UNSAFE: past start when it is $UNSAFE.x or $UNSAFE begin...end,
   else start itself *)
fn lex_unsafe_dispatch {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int)
  : @([q:int | s <= q; q <= n] int q, int) = let
  val after = adv(start, 7, max)
in
  if $AR.eq_int_int(at(src, after, max), 46) then let
    val ident_end = skip_ident(src, adv(after, 1, max), max)
    val () = put_span(spans, 5, 0, start, ident_end, 0, 0, 0, 0)
  in @(ident_end, count + 1) end
  else let
    val p0 = skip_ws(src, after, max)
  in
    if looking_at_begin(src, p0, max) then let
      val contents_start = adv(p0, 5, max)
      val end_pos = find_end_kw(src, contents_start, src_len, max, 1)
      val ep = block_end(end_pos, src_len, max)
      val () = put_span(spans, 4, 0, start, ep, contents_start, end_pos, 0, 0)
    in @(ep, count + 1) end
    else @(start, count)
  end
end

(* $UNITTEST: past start when it is $UNITTEST.run begin...end or
   $UNITTEST begin...end, else start itself *)
fn lex_unittest_dispatch {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, start: int s, count: int)
  : @([q:int | s <= q; q <= n] int q, int) = let
  val p0 = skip_ws(src, adv(start, 9, max), max)
  val is_run = $AR.eq_int_int(at(src, p0, max), 46) &&
    $AR.eq_int_int(at(src, p0 + 1, max), 114) &&
    $AR.eq_int_int(at(src, p0 + 2, max), 117) &&
    $AR.eq_int_int(at(src, p0 + 3, max), 110)
in
  if is_run then let
    val p1 = skip_ws(src, adv(p0, 4, max), max)
  in
    if looking_at_begin(src, p1, max) then let
      val contents_start = adv(p1, 5, max)
      val end_pos = find_end_kw(src, contents_start, src_len, max, 1)
      val ep = block_end(end_pos, src_len, max)
      val () = put_span(spans, 10, 0, start, ep, contents_start, end_pos, 0, 0)
    in @(ep, count + 1) end
    else @(start, count)
  end
  else if looking_at_begin(src, p0, max) then let
    val contents_start = adv(p0, 5, max)
    val end_pos = find_end_kw(src, contents_start, src_len, max, 0)
    val ep = block_end(end_pos, src_len, max)
    val () = put_span(spans, 8, 0, start, ep, contents_start, end_pos, 0, 0)
  in @(ep, count + 1) end
  else @(start, count)
end

(* ============================================================
   Lexer: passthrough scanner
   ============================================================ *)

fun lex_passthrough_scan {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : [q:int | p <= q; q <= n] int q =
  if pos >= src_len then pos
  else let
    val b = at(src, pos, max)
    val b1 = at(src, pos + 1, max)
  in
    if $AR.eq_int_int(b, 47) && ($AR.eq_int_int(b1, 47) || $AR.eq_int_int(b1, 42))
    then pos
    else if $AR.eq_int_int(b, 40) && $AR.eq_int_int(b1, 42) then pos
    else if $AR.eq_int_int(b, 34) then pos
    else if $AR.eq_int_int(b, 39) then pos
    else if $AR.eq_int_int(b, 37) && $AR.eq_int_int(b1, 123) then pos
    else if $AR.eq_int_int(b, 35) &&
      (looking_at_pub(src, pos, max) || looking_at_use(src, pos, max) ||
       looking_at_target(src, pos, max)) then pos
    else if $AR.eq_int_int(b, 36) && is_ident_start(b1) then pos
    (* Stop at unsafe keywords so lex_main can detect them *)
    else if looking_at_cast_fn(src, pos, max) then pos
    else if looking_at_prax_i(src, pos, max) then pos
    else if looking_at_ext_ern(src, pos, max) then pos
    else if looking_at_assu_me(src, pos, max) then pos
    else if looking_at_mac_hash(src, pos, max) then pos
    else if looking_at_ext_hash(src, pos, max) then pos
    else if looking_at_while(src, pos, max) then pos
    else if looking_at_fun(src, pos, max) then pos
    else if looking_at_stld(src, pos, max) then pos
    else lex_passthrough_scan(src, pos + 1, src_len, max)
  end

(* ============================================================
   Lexer: main loop
   ============================================================ *)

(* A span of the unsafe construct src[pos, pos + k) *)
fn unsafe_kw {n:nat}{p:nat | p < n}{k:pos}
  (spans: !$B.builder_v >> $B.builder_v, pos: int p, k: int k, max: int n)
  : [q:int | p < q; q <= n] int q = let
  val ep = adv(pos, k, max)
  val () = put_span(spans, 5, 0, pos, ep, 0, 0, 0, 0)
in ep end

(* The #pub declaration's span kind: 5 when it is restricted, or a proof
   function with no primplement in the source; else 2 *)
fn pub_kind {l:agz}{n:pos}{m:nat | m <= n}{c:nat | c <= n}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n, cs: int c): int = let
  val is_prfun = _content_starts_prfun(src, cs, max)
  val is_prfn = (if is_prfun then false else _content_starts_prfn(src, cs, max)): bool
in
  if _content_starts_restricted(src, cs, max) then 5
  else if is_prfun || is_prfn then let
    val kw_len = (if is_prfun then 5 else 4): [k:int | 4 <= k; k <= 5] int k
    val name_pos = _skip_to_name(src, adv(cs, kw_len, max), max)
    val name_end = skip_ident(src, name_pos, max)
  in
    if _has_primplement(src, src_len, max, name_pos, name_end - name_pos, 0) then 2
    else 5
  end
  else 2
end

(* Lexes src[pos, m) into spans; count is the number so far. A
   #target ... begin ... end block is expanded (a target_begin span, its
   contents' spans, a target_end span) when expand; its contents are
   lexed with expand false, as one opaque target_block span per block. *)
fun lex_main {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !$B.builder_v >> $B.builder_v, pos: int p, count: int,
   expand: bool): int =
  if pos >= src_len then count
  else let
    val b0 = at(src, pos, max)
    val b1 = at(src, pos + 1, max)
  in
    (* // line comment *)
    if $AR.eq_int_int(b0, 47) && $AR.eq_int_int(b1, 47) then let
      val @(np, nc) = lex_line_comment(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* /* C comment *)
    else if $AR.eq_int_int(b0, 47) && $AR.eq_int_int(b1, 42) then let
      val @(np, nc) = lex_c_comment(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* paren-star ML comment *)
    else if $AR.eq_int_int(b0, 40) && $AR.eq_int_int(b1, 42) then let
      val @(np, nc) = lex_ml_comment(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* " string *)
    else if $AR.eq_int_int(b0, 34) then let
      val @(np, nc) = lex_string(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* ' char *)
    else if $AR.eq_int_int(b0, 39) then let
      val @(np, nc) = lex_char_lit(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* %{ extcode *)
    else if $AR.eq_int_int(b0, 37) && $AR.eq_int_int(b1, 123) then let
      val @(np, nc) = lex_extcode(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* #pub declaration *)
    else if looking_at_pub(src, pos, max) then let
      val contents_start = skip_ws(src, adv(pos, 4, max), max)
      val ep = lex_pub_lines(src, contents_start, src_len, max)
      val () = put_span(spans, pub_kind(src, src_len, max, contents_start), 1,
                        pos, ep, contents_start, ep, 0, 0)
    in lex_main(src, src_len, max, spans, ep, count + 1, expand) end

    (* #target *)
    else if looking_at_target(src, pos, max) then let
      val p0 = skip_ws(src, adv(pos, 7, max), max)
      val ident_end = skip_ident(src, p0, max)
      val target = (if $AR.eq_int_int(at(src, p0, max), 119) then 1 else 0): int
      val p1 = skip_ws(src, ident_end, max)
    in
      if looking_at_begin(src, p1, max) then let
        (* Block form: #target wasm begin...end *)
        val cs = adv(p1, 5, max)
        val ce = find_end_kw(src, cs, src_len, max, 1)
        val ep = block_end(ce, src_len, max)
      in
        if expand then let
          (* target_begin covers [pos, cs), target_end [ce, ep) *)
          val () = put_span(spans, 13, 0, pos, cs, target, 0, 0, 0)
          val inner = lex_main(src, ce, max, spans, cs, 0, false)
          val () = put_span(spans, 14, 0, ce, ep, 0, 0, 0, 0)
        in lex_main(src, src_len, max, spans, ep, count + inner + 2, expand) end
        else let
          (* kind=11: target_block. aux1=target(0=native,1=wasm), aux2/aux3=content range *)
          val () = put_span(spans, 11, 0, pos, ep, target, cs, ce, 0)
        in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
      end
      else if looking_at_binary(src, p1, max) then let
        (* Binary marker form: #target wasm binary; kind=7, aux1=2 *)
        val ep = skip_to_eol(src, adv(p1, 6, max), src_len, max)
        val () = put_span(spans, 7, 2, pos, ep, 2, 0, 0, 0)
      in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
      else let
        (* Line form: just the directive *)
        val ep = skip_to_eol(src, ident_end, src_len, max)
        val () = put_span(spans, 7, 2, pos, ep, target, 0, 0, 0)
      in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
    end

    (* $extval, $extfcall, $extype, $extkind — unsafe constructs *)
    else if looking_at_extval(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 7, max), count + 1, expand)
    else if looking_at_extfcall(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 9, max), count + 1, expand)
    else if looking_at_extype(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 7, max), count + 1, expand)
    else if looking_at_extkind(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 8, max), count + 1, expand)

    (* $UNSAFE *)
    else if looking_at_unsafe(src, pos, max) then let
      val @(np, nc) = lex_unsafe_dispatch(src, src_len, max, spans, pos, count)
    in
      if np > pos then lex_main(src, src_len, max, spans, np, nc, expand)
      else let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_span(spans, 0, 0, pos, ep, 0, 0, 0, 0)
      in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
    end

    (* $UNITTEST *)
    else if looking_at_unittest(src, pos, max) then let
      val @(np, nc) = lex_unittest_dispatch(src, src_len, max, spans, pos, count)
    in
      if np > pos then lex_main(src, src_len, max, spans, np, nc, expand)
      else let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_span(spans, 0, 0, pos, ep, 0, 0, 0, 0)
      in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
    end

    (* #use *)
    else if looking_at_use(src, pos, max) then let
      val @(np, nc) = lex_hash_use(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc, expand) end

    (* $ident.ident qualified access *)
    else if $AR.eq_int_int(b0, 36) && is_ident_start(b1) then let
      val @(np, nc) = lex_qualified(src, src_len, max, spans, pos, count)
    in
      if np > pos then lex_main(src, src_len, max, spans, np, nc, expand)
      else let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_span(spans, 0, 0, pos, ep, 0, 0, 0, 0)
      in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
    end

    (* fun without termination metric — unsafe (can diverge) *)
    else if looking_at_fun(src, pos, max) then
      if _has_metric(src, adv(pos, 3, max), max) then let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_span(spans, 0, 0, pos, ep, 0, 0, 0, 0)
      in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
      else lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 3, max), count + 1, expand)

    (* unsafe keyword constructs detected here *)
    else if looking_at_cast_fn(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 6, max), count + 1, expand)
    else if looking_at_prax_i(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 5, max), count + 1, expand)
    else if looking_at_ext_ern(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 6, max), count + 1, expand)
    else if looking_at_assu_me(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 6, max), count + 1, expand)
    else if looking_at_mac_hash(src, pos, max) || looking_at_ext_hash(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 4, max), count + 1, expand)
    else if looking_at_while(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 5, max), count + 1, expand)
    (* staload lines: kind=12, go to both .sats and .dats with .bats→.sats rename *)
    else if looking_at_stld(src, pos, max) then let
      val ep = skip_to_eol(src, adv(pos, 7, max), src_len, max)
      val () = put_span(spans, 12, 2, pos, ep, 0, 0, 0, 0)
    in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
    (* Default: passthrough *)
    else let
      val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
      val () = put_span(spans, 0, 0, pos, ep, 0, 0, 0, 0)
    in lex_main(src, src_len, max, spans, ep, count + 1, expand) end
  end

(* Top-level lex function *)
#pub fn do_lex {l:agz}{n:pos}{m:nat | m <= n}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n
  ): @([ls:agz] $A.arr(byte, ls, 524288), int, int)

implement do_lex (src, src_len, max) = let
  var span_builder = $B.create()
  val span_count = lex_main(src, src_len, max, span_builder, 0, 0, true)
  val @(span_arr, span_arr_len) = $B.to_arr(span_builder)
in @(span_arr, span_arr_len, span_count) end
