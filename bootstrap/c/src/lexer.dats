staload "./lexer.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "str/src/lib.dats"
(* lexer -- tokenizer for the bats compiler *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload S = "str/src/lib.sats"

staload "helpers.sats"

fn is_ident_start(b: int): bool =
  (b >= 97 && b <= 122) ||
  (b >= 65 && b <= 90) ||
  $AR.eq_int_int(b, 95)

(* ============================================================
   Typed spans: each position is proven inside the source
   ============================================================ *)

(* A position in a source of n bytes *)


(* A span of a source of n bytes: the construct and its positions (the
   span's own range first) *)























(* The spans of a source of n bytes, k of them *)






implement spans_free {n}{k} (xs) = let
  fun loop {k:nat} .<k>. (xs: spans(n, k)): void =
    case+ xs of
    | ~spans_nil() => ()
    | ~spans_cons(sp, tl) => let
        val () = (case+ sp of
          | ~SPass(_, _, _) => () | ~SUse(_, _, _, _, _, _, _) => ()
          | ~SPub(_, _, _, _) => () | ~SQual(_, _, _, _, _, _) => ()
          | ~SUnsafeBlock(_, _, _, _) => () | ~SConstruct(_, _) => ()
          | ~SExtcode(_, _, _, _, _) => () | ~STarget(_, _, _) => ()
          | ~SStaload(_, _) => () | ~STargetBegin(_, _, _) => ()
          | ~STargetEnd(_, _) => () | ~SUnittestBegin(_, _, _, _) => ()
          | ~SUnittestEnd(_, _) => () | ~SLexError(_, _, _, _, _) => ())
      in loop(tl) end
in loop(xs) end

(* xs reversed onto acc *)
fun spans_rev {n:int}{k,j:nat} .<k>.
  (xs: spans(n, k), acc: spans(n, j)): spans(n, k + j) =
  case+ xs of
  | ~spans_nil() => acc
  | ~spans_cons(sp, tl) => spans_rev(tl, spans_cons(sp, acc))

(* The lexer's output so far: the spans, in reverse *)
datavtype lexout(n:int) =
  | {k:nat} LexOut(n) of spans(n, k)

(* sp added to the output *)
fn put_typed {n:int} (o: !lexout(n) >> lexout(n), sp: span(n)): void = let
  val+ @LexOut(xs) = o
  val () = xs := spans_cons(sp, xs)
  prval () = fold@(o)
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

(* Whether src[s, e) is the word lit[0, k) *)
fn word_is {l:agz}{n:pos}{k:pos | k <= 1048576}{s,e:int}
  (src: !$A.borrow(byte, l, n), s: int s, e: int e, max: int n, lit: &(@[char][k]), k: int k): bool =
  if e - s = k then lit_at(src, s, max, lit, k) else false

(* Whether the keyword kw[0, k) is at pos, whole *)
fn looking_at_kw {l:agz}{n:pos}{p:nat | p <= n}{k:pos | k <= 1048576}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n, kw: &(@[char][k]), k: int k): bool =
  lit_at(src, pos, max, kw, k) && is_kw_boundary(src, pos + k, max) &&
  is_kw_boundary_before(src, pos, max)

fn looking_at_fnx {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if $AR.eq_int_int(at(src, pos, max), 102) then let
    var c = @[char][3]('f', 'n', 'x')
  in looking_at_kw(src, pos, max, c, 3) end
  else false

(* fix, fix@: a recursive lambda *)
fn looking_at_fix {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if $AR.eq_int_int(at(src, pos, max), 102) then let
    var c = @[char][3]('f', 'i', 'x')
  in lit_at(src, pos, max, c, 3) && ~(is_ident_byte(at(src, pos + 3, max))) &&
     is_kw_boundary_before(src, pos, max) end
  else false

fn looking_at_and {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if $AR.eq_int_int(at(src, pos, max), 97) then let
    var c = @[char][3]('a', 'n', 'd')
  in looking_at_kw(src, pos, max, c, 3) end
  else false

(* val rec: a recursive value, with no termination metric; the end of
   "rec" when it is one, else pos *)
fn val_rec_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if $AR.eq_int_int(at(src, pos, max), 118) then let
    var v = @[char][3]('v', 'a', 'l')
    var r = @[char][3]('r', 'e', 'c')
  in
    if looking_at_kw(src, pos, max, v, 3) then let
      val r0 = skip_ws(src, adv(pos, 3, max), max)
    in
      if r0 > pos + 3 && looking_at_kw(src, r0, max, r, 3) then adv(r0, 3, max) else pos
    end
    else pos
  end
  else pos

(* The start of the line holding p *)
fun line_start {l:agz}{n:pos}{p:nat | p <= n} .<p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n): [q:nat | q <= p] int q =
  if p = 0 then 0
  else if $AR.eq_int_int(at(src, p - 1, max), 10) then p
  else line_start(src, p - 1, max)

(* The kind of declaration the word src[s, e) opens: 1 for fun or fnx,
   2 for and, 3 for another declaration keyword, 0 for none *)
fn decl_word {l:agz}{n:pos}{s,e:int}
  (src: !$A.borrow(byte, l, n), s: int s, e: int e, max: int n): int = let
  var c_fun = @[char][3]('f', 'u', 'n')
  var c_fnx = @[char][3]('f', 'n', 'x')
  var c_and = @[char][3]('a', 'n', 'd')
  var c_fn = @[char][2]('f', 'n')
  var c_val = @[char][3]('v', 'a', 'l')
  var c_var = @[char][3]('v', 'a', 'r')
  var c_prfun = @[char][5]('p', 'r', 'f', 'u', 'n')
  var c_prfn = @[char][4]('p', 'r', 'f', 'n')
  var c_impl = @[char][9]('i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
  var c_primpl = @[char][11]('p', 'r', 'i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
  var c_extern = @[char][6]('e', 'x', 't', 'e', 'r', 'n')
  var c_pub = @[char][4]('#', 'p', 'u', 'b')
  var c_local = @[char][5]('l', 'o', 'c', 'a', 'l')
  var c_dt = @[char][8]('d', 'a', 't', 'a', 't', 'y', 'p', 'e')
  var c_dvt = @[char][9]('d', 'a', 't', 'a', 'v', 't', 'y', 'p', 'e')
  var c_dvwt = @[char][12]('d', 'a', 't', 'a', 'v', 'i', 'e', 'w', 't', 'y', 'p', 'e')
  var c_dp = @[char][8]('d', 'a', 't', 'a', 'p', 'r', 'o', 'p')
  var c_dv = @[char][8]('d', 'a', 't', 'a', 'v', 'i', 'e', 'w')
  var c_td = @[char][7]('t', 'y', 'p', 'e', 'd', 'e', 'f')
  var c_vtd = @[char][8]('v', 't', 'y', 'p', 'e', 'd', 'e', 'f')
  var c_vwtd = @[char][11]('v', 'i', 'e', 'w', 't', 'y', 'p', 'e', 'd', 'e', 'f')
  var c_sd = @[char][6]('s', 't', 'a', 'd', 'e', 'f')
in
  if word_is(src, s, e, max, c_fun, 3) then 1
  else if word_is(src, s, e, max, c_fnx, 3) then 1
  else if word_is(src, s, e, max, c_and, 3) then 2
  else if word_is(src, s, e, max, c_fn, 2) then 3
  else if word_is(src, s, e, max, c_val, 3) then 3
  else if word_is(src, s, e, max, c_var, 3) then 3
  else if word_is(src, s, e, max, c_prfun, 5) then 3
  else if word_is(src, s, e, max, c_prfn, 4) then 3
  else if word_is(src, s, e, max, c_impl, 9) then 3
  else if word_is(src, s, e, max, c_primpl, 11) then 3
  else if word_is(src, s, e, max, c_extern, 6) then 3
  else if word_is(src, s, e, max, c_pub, 4) then 3
  else if word_is(src, s, e, max, c_local, 5) then 3
  else if word_is(src, s, e, max, c_dt, 8) then 3
  else if word_is(src, s, e, max, c_dvt, 9) then 3
  else if word_is(src, s, e, max, c_dvwt, 12) then 3
  else if word_is(src, s, e, max, c_dp, 8) then 3
  else if word_is(src, s, e, max, c_dv, 8) then 3
  else if word_is(src, s, e, max, c_td, 7) then 3
  else if word_is(src, s, e, max, c_vtd, 8) then 3
  else if word_is(src, s, e, max, c_vwtd, 11) then 3
  else if word_is(src, s, e, max, c_sd, 6) then 3
  else 0
end

(* The end of the word (ident bytes and #) at s *)
fun word_end_at {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if p >= max then p
  else let val b = at(src, p, max) in
    if is_ident_byte(b) || $AR.eq_int_int(b, 35) then word_end_at(src, p + 1, max)
    else p
  end

(* Whether the and whose line starts at ls continues a fun or fnx group:
   the lines before it are read upward, past those indented deeper than
   ind or opening no declaration, to the first declaration keyword at
   indentation ind or less *)
fun and_in_fun_group {l:agz}{n:pos}{ls:nat | ls <= n} .<ls>.
  (src: !$A.borrow(byte, l, n), ls: int ls, ind: int, max: int n): bool =
  if ls = 0 then false
  else let
    val prev = line_start(src, ls - 1, max)
    val fs = skip_ws(src, prev, max)
    val we = word_end_at(src, fs, max)
    val kind = (if fs - prev <= ind then decl_word(src, fs, we, max) else 0): int
  in
    if kind = 1 then true
    else if kind = 3 then false
    else and_in_fun_group(src, prev, ind, max)
  end

(* Whether the and at pos opens a member of a fun or fnx group *)
fn and_opens_fun {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool = let
  val ls = line_start(src, pos, max)
  val fs = skip_ws(src, ls, max)
in and_in_fun_group(src, ls, fs - ls, max) end

(* A sub-lexer's result: the end of what it lexed, past its start s, and
   the span count *)
typedef lexed(s:int, n:int) = @([q:int | s < q; q <= n] int q, int)

(* Lex // line comment. //// = rest-of-file *)
fn lex_line_comment {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) =
  if $AR.eq_int_int(at(src, start + 2, max), 47) &&
     $AR.eq_int_int(at(src, start + 3, max), 47) then let
    val () = put_typed(spans, SPass(start, src_len, true))
  in @(src_len, count + 1) end
  else let
    val ep = skip_to_eol(src, adv(start, 2, max), src_len, max)
    val () = put_typed(spans, SPass(start, ep, true))
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
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val ep = lex_c_comment_inner(src, adv(start, 2, max), src_len, max)
  val () = put_typed(spans, SPass(start, ep, true))
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
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val ep = lex_ml_comment_inner(src, adv(start, 2, max), src_len, max, 1)
  val () = put_typed(spans, SPass(start, ep, true))
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
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val ep = lex_string_inner(src, start + 1, src_len, max)
  val () = put_typed(spans, SPass(start, ep, true))
in @(ep, count + 1) end

(* Lex char literal '...' *)
fn lex_char_lit {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val p1 = start + 1
  val p2 = (if $AR.eq_int_int(at(src, p1, max), 92) then adv(p1, 2, max)
            else adv(p1, 1, max)): [q:int | s < q; q <= n] int q
  val p3 = (if $AR.eq_int_int(at(src, p2, max), 39) then adv(p2, 1, max)
            else p2): [q:int | s < q; q <= n] int q
  val () = put_typed(spans, SPass(start, p3, true))
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
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val after_open = adv(start, 2, max)
  val bk = at(src, after_open, max)
  val kind = (if $AR.eq_int_int(bk, 94) then 1
              else if $AR.eq_int_int(bk, 36) then 2
              else if $AR.eq_int_int(bk, 35) then 3
              else 0): int
  val cstart = (if kind > 0 then adv(after_open, 1, max)
                else after_open): [q:int | s < q; q <= n] int q
  val ep = lex_extcode_inner(src, cstart, src_len, max)
  val cend = (if ep >= 2 then ep - 2 else ep): spos(n)
  val () = put_typed(spans, SExtcode(start, ep, cstart, cend, kind))
in @(ep, count + 1) end

(* Lex #use pkg as Alias [no_mangle] *)
fn lex_hash_use {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
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
  val () = put_typed(spans, SUse(start, ep, mangle = 1,
                    pkg_start, pkg_end, alias_start, alias_end))
in @(ep, count + 1) end

(* Lex $Alias.member qualified access: past start when it is one, else
   start itself *)
fn lex_qualified {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int)
  : @([q:int | s <= q; q <= n] int q, int) = let
  val alias_start = start + 1
  val alias_end = skip_ident(src, alias_start, max)
in
  if $AR.eq_int_int(at(src, alias_end, max), 46) then let
    val member_start = adv(alias_end, 1, max)
    val member_end = skip_ident(src, member_start, max)
  in
    if member_end > member_start then let
      val () = put_typed(spans, SQual(start, member_end,
                        alias_start, alias_end, member_start, member_end))
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
  (* A keyword in a comment, a string or a char literal is text *)
  else if $AR.eq_int_int(at(src, pos, max), 40) &&
          $AR.eq_int_int(at(src, pos + 1, max), 42) then
    find_end_kw(src, lex_ml_comment_inner(src, adv(pos, 2, max), src_len, max, 1),
                src_len, max, depth)
  else if $AR.eq_int_int(at(src, pos, max), 47) &&
          $AR.eq_int_int(at(src, pos + 1, max), 42) then
    find_end_kw(src, lex_c_comment_inner(src, adv(pos, 2, max), src_len, max),
                src_len, max, depth)
  else if $AR.eq_int_int(at(src, pos, max), 47) &&
          $AR.eq_int_int(at(src, pos + 1, max), 47) then
    find_end_kw(src, skip_to_eol(src, adv(pos, 2, max), src_len, max),
                src_len, max, depth)
  else if $AR.eq_int_int(at(src, pos, max), 34) then
    find_end_kw(src, lex_string_inner(src, pos + 1, src_len, max), src_len, max, depth)
  (* 'x' and '\x' are char literals; any other ' (x', '(, '[) is not *)
  else if $AR.eq_int_int(at(src, pos, max), 39) then
    (if $AR.eq_int_int(at(src, pos + 1, max), 92) &&
        $AR.eq_int_int(at(src, pos + 3, max), 39) then
       find_end_kw(src, adv(pos, 4, max), src_len, max, depth)
     else if $AR.eq_int_int(at(src, pos + 2, max), 39) then
       find_end_kw(src, adv(pos, 3, max), src_len, max, depth)
     else find_end_kw(src, pos + 1, src_len, max, depth))
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
   spans: !lexout(n) >> lexout(n), start: int s, count: int)
  : @([q:int | s <= q; q <= n] int q, int) = let
  val after = adv(start, 7, max)
in
  if $AR.eq_int_int(at(src, after, max), 46) then let
    val ident_end = skip_ident(src, adv(after, 1, max), max)
    val () = put_typed(spans, SConstruct(start, ident_end))
  in @(ident_end, count + 1) end
  else let
    val p0 = skip_ws(src, after, max)
  in
    if looking_at_begin(src, p0, max) then let
      val contents_start = adv(p0, 5, max)
      val end_pos = find_end_kw(src, contents_start, src_len, max, 1)
      val ep = block_end(end_pos, src_len, max)
      val () = put_typed(spans, SUnsafeBlock(start, ep, contents_start, end_pos))
    in @(ep, count + 1) end
    else @(start, count)
  end
end

(* bits (a set of targets: 1 native, 2 wasm) with bit added *)
fn with_bit (bits: int, bit: int): int =
  if bit = 1 then (if bits = 0 then 1 else if bits = 2 then 3 else bits)
  else (if bits = 0 then 2 else if bits = 1 then 3 else bits)

(* The target list of $UNITTEST.run(...), from p inside the parens
   (Rust: lex_unittest): @(status, bits, q, e) with status 0 and the
   targets as bits (1 native, 2 wasm) and q past the list, or status 1
   (an empty list) or 2 (an unknown target, src[q, e)). A list that
   stops at a non-identifier (no ")") ends there, as in Rust. *)
fun ut_targets {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n, bits: int, found: bool)
  : @(int, int, [q:int | p <= q; q <= n] int q, spos(n)) = let
  val p1 = skip_ws(src, p, max)
in
  if $AR.eq_int_int(at(src, p1, max), 41) then
    (if found then @(0, bits, adv(p1, 1, max), p1) else @(1, bits, p1, p1))
  else let
    val ie = skip_ident(src, p1, max)
    var c_native = @[char][6]('n', 'a', 't', 'i', 'v', 'e')
    var c_wasm = @[char][4]('w', 'a', 's', 'm')
  in
    if ie = p1 then @(0, bits, p1, p1)
    else let
      val bit = (if word_is(src, p1, ie, max, c_native, 6) then 1
                 else if word_is(src, p1, ie, max, c_wasm, 4) then 2
                 else 0): int
    in
      if bit = 0 then @(2, bits, p1, ie)
      else let
        val p2 = skip_ws(src, ie, max)
        val c = at(src, p2, max)
      in
        if $AR.eq_int_int(c, 44) then ut_targets(src, adv(p2, 1, max), max, with_bit(bits, bit), true)
        else if $AR.eq_int_int(c, 41) then @(0, with_bit(bits, bit), adv(p2, 1, max), p2)
        else ut_targets(src, p2, max, with_bit(bits, bit), true)
      end
    end
  end
end

(* The header of a $UNITTEST block at s (Rust: lex_unittest):
   @(status, is_run, bits, cs, e1, e2). status 1: $UNITTEST[.run[(targets)]]
   begin, whose contents start at cs; 0: not a unittest block; 2: an
   empty target list, at e1; 3: an unknown target src[e1, e2). bits
   are the targets (1 native, 2 wasm): native when there is no list. *)
fn ut_header {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n, start: int s)
  : @(int, int, int, [q:int | s < q; q <= n] int q, spos(n), spos(n)) = let
  val a = adv(start, 9, max)
  val is_run = $AR.eq_int_int(at(src, a, max), 46) &&
    $AR.eq_int_int(at(src, a + 1, max), 114) &&
    $AR.eq_int_int(at(src, a + 2, max), 117) &&
    $AR.eq_int_int(at(src, a + 3, max), 110)
  val p0 = (if is_run then adv(a, 4, max) else a): [q:int | s < q; q <= n] int q
  val run = (if is_run then 1 else 0): int
in
  if (if is_run then $AR.eq_int_int(at(src, p0, max), 40) else false) then let
    val @(st, bits, q, e) = ut_targets(src, adv(p0, 1, max), max, 0, false)
  in
    if st = 1 then @(2, run, 0, p0, p0, p0)
    else if st = 2 then @(3, run, 0, p0, q, e)
    else let
      val p1 = skip_ws(src, q, max)
    in
      if looking_at_begin(src, p1, max) then @(1, run, bits, adv(p1, 5, max), 0, 0)
      else @(0, run, 0, p0, 0, 0)
    end
  end
  else let
    val p1 = skip_ws(src, p0, max)
  in
    if looking_at_begin(src, p1, max) then @(1, run, 1, adv(p1, 5, max), 0, 0)
    else @(0, run, 0, p0, 0, 0)
  end
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
    else if looking_at_fnx(src, pos, max) then pos
    else if looking_at_fix(src, pos, max) then pos
    else if looking_at_and(src, pos, max) then pos
    else if val_rec_end(src, pos, max) > pos then pos
    else if looking_at_stld(src, pos, max) then pos
    else lex_passthrough_scan(src, pos + 1, src_len, max)
  end

(* ============================================================
   Lexer: main loop
   ============================================================ *)

(* A span of the unsafe construct src[pos, pos + k) *)
fn unsafe_kw {n:nat}{p:nat | p < n}{k:pos}
  (spans: !lexout(n) >> lexout(n), pos: int p, k: int k, max: int n)
  : [q:int | p < q; q <= n] int q = let
  val ep = adv(pos, k, max)
  val () = put_typed(spans, SConstruct(pos, ep))
in ep end

(* Whether the #pub declaration is rejected: restricted, or a proof
   function with no primplement in the source *)
fn pub_rejected {l:agz}{n:pos}{m:nat | m <= n}{c:nat | c <= n}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n, cs: int c): bool = let
  val is_prfun = _content_starts_prfun(src, cs, max)
  val is_prfn = (if is_prfun then false else _content_starts_prfn(src, cs, max)): bool
in
  if _content_starts_restricted(src, cs, max) then true
  else if is_prfun || is_prfn then let
    val kw_len = (if is_prfun then 5 else 4): [k:int | 4 <= k; k <= 5] int k
    val name_pos = _skip_to_name(src, adv(cs, kw_len, max), max)
    val name_end = skip_ident(src, name_pos, max)
  in
    ~_has_primplement(src, src_len, max, name_pos, name_end - name_pos, 0)
  end
  else false
end

(* Lexes src[pos, m) into spans; count is the number so far. A
   #target ... begin ... end block is a target_begin span, its contents'
   spans and a target_end span; a $UNITTEST block likewise (unittest_begin,
   its contents' spans, unittest_end), so what is in either is lexed, and
   checked, as any other code. *)
fun lex_main {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), pos: int p, count: int): int =
  if pos >= src_len then count
  else let
    val b0 = at(src, pos, max)
    val b1 = at(src, pos + 1, max)
    val vr = val_rec_end(src, pos, max)
  in
    (* // line comment *)
    if $AR.eq_int_int(b0, 47) && $AR.eq_int_int(b1, 47) then let
      val @(np, nc) = lex_line_comment(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* /* C comment *)
    else if $AR.eq_int_int(b0, 47) && $AR.eq_int_int(b1, 42) then let
      val @(np, nc) = lex_c_comment(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* paren-star ML comment *)
    else if $AR.eq_int_int(b0, 40) && $AR.eq_int_int(b1, 42) then let
      val @(np, nc) = lex_ml_comment(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* " string *)
    else if $AR.eq_int_int(b0, 34) then let
      val @(np, nc) = lex_string(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* ' char *)
    else if $AR.eq_int_int(b0, 39) then let
      val @(np, nc) = lex_char_lit(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* %{ extcode *)
    else if $AR.eq_int_int(b0, 37) && $AR.eq_int_int(b1, 123) then let
      val @(np, nc) = lex_extcode(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* #pub declaration *)
    else if looking_at_pub(src, pos, max) then let
      val contents_start = skip_ws(src, adv(pos, 4, max), max)
      val ep = lex_pub_lines(src, contents_start, src_len, max)
      val () = put_typed(spans, SPub(pos, ep, pub_rejected(src, src_len, max, contents_start), contents_start))
    in lex_main(src, src_len, max, spans, ep, count + 1) end

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
        (* target_begin covers [pos, cs), target_end [ce, ep) *)
        val () = put_typed(spans, STargetBegin(pos, cs, target))
        val inner = lex_main(src, ce, max, spans, cs, 0)
        val () = put_typed(spans, STargetEnd(ce, ep))
      in lex_main(src, src_len, max, spans, ep, count + inner + 2) end
      else if looking_at_binary(src, p1, max) then let
        (* Binary marker form: #target wasm binary; kind=7, aux1=2 *)
        val ep = skip_to_eol(src, adv(p1, 6, max), src_len, max)
        val () = put_typed(spans, STarget(pos, ep, 2))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
      else let
        (* Line form: just the directive *)
        val ep = skip_to_eol(src, ident_end, src_len, max)
        val () = put_typed(spans, STarget(pos, ep, target))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
    end

    (* $extval, $extfcall, $extype, $extkind — unsafe constructs *)
    else if looking_at_extval(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 7, max), count + 1)
    else if looking_at_extfcall(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 9, max), count + 1)
    else if looking_at_extype(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 7, max), count + 1)
    else if looking_at_extkind(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 8, max), count + 1)

    (* $UNSAFE *)
    else if looking_at_unsafe(src, pos, max) then let
      val @(np, nc) = lex_unsafe_dispatch(src, src_len, max, spans, pos, count)
    in
      if np > pos then lex_main(src, src_len, max, spans, np, nc)
      else let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_typed(spans, SPass(pos, ep, false))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
    end

    (* $UNITTEST *)
    else if looking_at_unittest(src, pos, max) then let
      val @(st, run, bits, cs, e1, e2) = ut_header(src, src_len, max, pos)
    in
      if st = 1 then let
        val ce = find_end_kw(src, cs, src_len, max, 1)
        val ep = block_end(ce, src_len, max)
        (* No "end": Rust's "unterminated ... begin...end block", and the
           block runs to the end of the file *)
        val nerr = (if ce >= src_len then let
            val () = put_typed(spans, SLexError(pos, 3, pos, pos, run = 1))
          in 1 end else 0): int
        (* unittest_begin covers [pos, cs), unittest_end [ce, ep) *)
        val () = put_typed(spans, SUnittestBegin(pos, cs, run = 1, bits))
        val inner = lex_main(src, ce, max, spans, cs, 0)
        val () = put_typed(spans, SUnittestEnd(ce, ep))
      in lex_main(src, src_len, max, spans, ep, count + nerr + inner + 2) end
      else let
        (* A bad target list is a lex error (Rust: "empty target list in
           $UNITTEST.run()", "unknown test target"); the text is then
           ordinary code, as when it is no unittest block at all *)
        val nerr = (if st >= 2 then let
            val () = put_typed(spans, SLexError(pos, st - 1, e1, e2, false))
          in 1 end else 0): int
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_typed(spans, SPass(pos, ep, false))
      in lex_main(src, src_len, max, spans, ep, count + nerr + 1) end
    end

    (* #use *)
    else if looking_at_use(src, pos, max) then let
      val @(np, nc) = lex_hash_use(src, src_len, max, spans, pos, count)
    in lex_main(src, src_len, max, spans, np, nc) end

    (* $ident.ident qualified access *)
    else if $AR.eq_int_int(b0, 36) && is_ident_start(b1) then let
      val @(np, nc) = lex_qualified(src, src_len, max, spans, pos, count)
    in
      if np > pos then lex_main(src, src_len, max, spans, np, nc)
      else let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_typed(spans, SPass(pos, ep, false))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
    end

    (* fun without termination metric — unsafe (can diverge) *)
    else if looking_at_fun(src, pos, max) then
      if _has_metric(src, adv(pos, 3, max), max) then let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_typed(spans, SPass(pos, ep, false))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
      else lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 3, max), count + 1)

    (* fnx, and in a fun group, fix: recursive, so a termination metric
       is needed as for fun *)
    else if looking_at_fnx(src, pos, max) || looking_at_fix(src, pos, max) ||
            (looking_at_and(src, pos, max) && and_opens_fun(src, pos, max)) then
      if _has_metric(src, adv(pos, 3, max), max) then let
        val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
        val () = put_typed(spans, SPass(pos, ep, false))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
      else lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 3, max), count + 1)

    (* val rec: a recursive value, with no termination metric *)
    else if vr > pos then let
      val () = put_typed(spans, SConstruct(pos, vr))
    in lex_main(src, src_len, max, spans, vr, count + 1) end

    (* unsafe keyword constructs detected here *)
    else if looking_at_cast_fn(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 6, max), count + 1)
    else if looking_at_prax_i(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 5, max), count + 1)
    else if looking_at_ext_ern(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 6, max), count + 1)
    else if looking_at_assu_me(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 6, max), count + 1)
    else if looking_at_mac_hash(src, pos, max) || looking_at_ext_hash(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 4, max), count + 1)
    else if looking_at_while(src, pos, max) then
      lex_main(src, src_len, max, spans, unsafe_kw(spans, pos, 5, max), count + 1)
    (* staload lines: kind=12, go to both .sats and .dats with .bats→.sats rename *)
    else if looking_at_stld(src, pos, max) then let
      val ep = skip_to_eol(src, adv(pos, 7, max), src_len, max)
      val () = put_typed(spans, SStaload(pos, ep))
    in lex_main(src, src_len, max, spans, ep, count + 1) end
    (* Default: passthrough *)
    else let
      val ep = lex_passthrough_scan(src, pos + 1, src_len, max)
      val () = put_typed(spans, SPass(pos, ep, false))
    in lex_main(src, src_len, max, spans, ep, count + 1) end
  end

(* Top-level lex function *)
(* The typed spans of src[0, m), in order *)




implement lex_spans (src, src_len, max) = let
  var o = LexOut(spans_nil())
  val _ = lex_main(src, src_len, max, o, 0, 0)
  val+ ~LexOut(xs) = o
in spans_rev(xs, spans_nil()) end
