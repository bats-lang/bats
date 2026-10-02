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


(* The targets a $UNITTEST.run block's tests run on (NoTestTargets
   when its list named none, as a list that stops at a word that is not
   an identifier can) *)


(* Where the C of an extcode block goes, by the byte after its %{: %{
   where it is, %{^ at the top of the C, %{$ at its end, %{# into the
   static (.sats) code *)


(* What a build makes code for, and what a #target block is for *)


(* What a #target line names: #target native, #target wasm, or
   #target wasm binary *)


(* Whether two targets are the same *)


implement same_target (a, b) =
  case+ (a, b) of
  | (Native(), Native()) => true
  | (Wasm(), Wasm()) => true
  | (_, _) => false

(* A test's targets as the byte that leads its entry in a list of tests
   (collect_tests): 1 native, 2 wasm, 3 both, 0 none *)


implement targets_byte (targets) =
  case+ targets of
  | NoTestTargets() => 0 | NativeTests() => 1 | WasmTests() => 2 | AllTargets() => 3

(* The targets a list entry's leading byte stands for (targets_byte) *)


implement targets_of_byte (b) =
  if b = 1 then NativeTests() else if b = 2 then WasmTests()
  else if b = 3 then AllTargets() else NoTestTargets()

(* Whether a test of targets runs on wasm (when wasm) or native *)


implement runs_on (targets, wasm) =
  case+ targets of
  | NoTestTargets() => false
  | NativeTests() => ~wasm
  | WasmTests() => wasm
  | AllTargets() => true

(* What the lexer found wrong (Rust's lexer errors) *)










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
  is_kw_boundary_before(src, pos, max) &&
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

(* Whether the last byte before pos that is not a blank is '<': the
   "fun" at pos names a function kind in an arrow (=<fun>, -<fun>),
   not a declaration *)
fun _after_angle {l:agz}{n:pos}{i:int} .<max(i, 0)>.
  (src: !$A.borrow(byte, l, n), pos: int i, max: int n): bool =
  if pos <= 0 then false
  else let
    val b = peek(src, pos - 1, max)
  in
    if b = 32 || b = 9 then _after_angle(src, pos - 1, max)
    else b = 60
  end

fn looking_at_fun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool =
  lit_fun(src, pos, max) &&
  is_kw_boundary(src, pos + 3, max) &&
  is_kw_boundary_before(src, pos, max) &&
  ~(_after_angle(src, pos, max))

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

(* ============================================================
   Non-linear heap values: what allocates must be linear, so that its
   consumer frees it (there is no garbage collector). Outside $UNSAFE
   these are rejected: a datatype whose constructor carries data (a
   datavtype is freed by its match), a boxed tuple, record or list
   ('(, '{, '[ and $tup, $rec, $list; the flat @( ) and @{ } and the
   linear $tup_vt, $rec_vt and $list_vt stay), a non-linear closure
   (cloref, cloptr; lincloptr is freed with cloptr_free), a lam whose
   arrow leaves its kind to the context (llam is linear) and a ref made
   inside a function (one made once, at the top level, stays).
   ============================================================ *)

fn looking_at_datatype {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if $AR.eq_int_int(at(src, pos, max), 100) then let
    var c = @[char][8]('d', 'a', 't', 'a', 't', 'y', 'p', 'e')
  in looking_at_kw(src, pos, max, c, 8) end
  else false

fn looking_at_of {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if $AR.eq_int_int(at(src, pos, max), 111) then let
    var c = @[char][2]('o', 'f')
  in looking_at_kw(src, pos, max, c, 2) end
  else false

(* Whether what follows an "of" at pos is "()" (blanks allowed inside) *)
fn of_unit {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool = let
  val p1 = skip_ws(src, pos, max)
in
  if $AR.eq_int_int(at(src, p1, max), 40) then
    $AR.eq_int_int(at(src, skip_ws(src, adv(p1, 1, max), max), max), 41)
  else false
end

(* Whether the datatype declaration whose header starts at pos has a
   constructor that carries data: an "of" at bracket depth 0 before the
   declaration ends, at a line that starts with none of a blank, "|",
   "of" and "and" (an "and" opens the next datatype of the group) *)
fun _datatype_carries {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n, depth: int): bool =
  if pos >= max then false
  else let
    val b = at(src, pos, max)
  in
    if $AR.eq_int_int(b, 40) || $AR.eq_int_int(b, 91) || $AR.eq_int_int(b, 123) then
      _datatype_carries(src, pos + 1, max, depth + 1)
    else if $AR.eq_int_int(b, 41) || $AR.eq_int_int(b, 93) || $AR.eq_int_int(b, 125) then
      _datatype_carries(src, pos + 1, max, depth - 1)
    else if depth > 0 then _datatype_carries(src, pos + 1, max, depth)
    else if $AR.eq_int_int(b, 10) then let
      val nb = at(src, pos + 1, max)
    in
      if $AR.eq_int_int(nb, 32) || $AR.eq_int_int(nb, 9) ||
         $AR.eq_int_int(nb, 124) || $AR.eq_int_int(nb, 10) then
        _datatype_carries(src, pos + 1, max, depth)
      else if looking_at_of(src, pos + 1, max) || looking_at_and(src, pos + 1, max) then
        _datatype_carries(src, pos + 1, max, depth)
      else false
    end
    else if looking_at_of(src, pos, max) then
      (* "of ()" carries nothing: it is a nullary constructor *)
      ~(of_unit(src, adv(pos, 2, max), max))
    else _datatype_carries(src, pos + 1, max, depth)
  end

(* A datatype keyword at pos whose declaration carries data *)
fn datatype_carries {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  looking_at_datatype(src, pos, max) &&
  _datatype_carries(src, adv(pos, 8, max), max, 0)

(* '( '{ '[ : a boxed tuple, record or list (not a char literal) *)
fn boxed_quote {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool = let
  val b1 = at(src, pos + 1, max)
in
  $AR.eq_int_int(at(src, pos, max), 39) &&
  ($AR.eq_int_int(b1, 40) || $AR.eq_int_int(b1, 123) || $AR.eq_int_int(b1, 91)) &&
  ~($AR.eq_int_int(at(src, pos + 2, max), 39))
end

(* $tup $rec $list $tup_t $rec_t $list_t: a boxed tuple, record or
   list; past it when it is one, else pos *)
fn boxed_dollar_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if $AR.eq_int_int(at(src, pos, max), 36) then let
    val ws = adv(pos, 1, max)
    val we = skip_ident(src, ws, max)
    var c_tup = @[char][3]('t', 'u', 'p')
    var c_rec = @[char][3]('r', 'e', 'c')
    var c_list = @[char][4]('l', 'i', 's', 't')
    var c_tup_t = @[char][5]('t', 'u', 'p', '_', 't')
    var c_rec_t = @[char][5]('r', 'e', 'c', '_', 't')
    var c_list_t = @[char][6]('l', 'i', 's', 't', '_', 't')
    var c_delay = @[char][5]('d', 'e', 'l', 'a', 'y')
  in
    if word_is(src, ws, we, max, c_tup, 3) || word_is(src, ws, we, max, c_rec, 3) ||
       word_is(src, ws, we, max, c_list, 4) || word_is(src, ws, we, max, c_tup_t, 5) ||
       word_is(src, ws, we, max, c_rec_t, 5) || word_is(src, ws, we, max, c_list_t, 6) ||
       word_is(src, ws, we, max, c_delay, 5)
    then we else pos
  end
  else pos

(* cloref cloref0 cloref1 cloptr cloptr0 cloptr1: a non-linear closure;
   past it when it is one, else pos (lincloptr is not: the "n" before
   "cloptr" is an identifier byte) *)
fn nonlinear_clo_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if $AR.eq_int_int(at(src, pos, max), 99) && is_kw_boundary_before(src, pos, max) then let
    val we = skip_ident(src, pos, max)
    var c_ref = @[char][6]('c', 'l', 'o', 'r', 'e', 'f')
    var c_ref0 = @[char][7]('c', 'l', 'o', 'r', 'e', 'f', '0')
    var c_ref1 = @[char][7]('c', 'l', 'o', 'r', 'e', 'f', '1')
    var c_ptr = @[char][6]('c', 'l', 'o', 'p', 't', 'r')
    var c_ptr0 = @[char][7]('c', 'l', 'o', 'p', 't', 'r', '0')
    var c_ptr1 = @[char][7]('c', 'l', 'o', 'p', 't', 'r', '1')
  in
    if word_is(src, pos, we, max, c_ref, 6) || word_is(src, pos, we, max, c_ref0, 7) ||
       word_is(src, pos, we, max, c_ref1, 7) || word_is(src, pos, we, max, c_ptr, 6) ||
       word_is(src, pos, we, max, c_ptr0, 7) || word_is(src, pos, we, max, c_ptr1, 7)
    then we else pos
  end
  else pos

(* ref<...>( or ref_make_elt on an indented line: a cell made inside a
   function, never freed; past the word when it is one, else pos *)
fn inner_ref_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if $AR.eq_int_int(at(src, pos, max), 114) && is_kw_boundary_before(src, pos, max) then let
    val we = skip_ident(src, pos, max)
    var c_ref = @[char][3]('r', 'e', 'f')
    var c_make = @[char][12]('r', 'e', 'f', '_', 'm', 'a', 'k', 'e', '_', 'e', 'l', 't')
    val is_make = (if word_is(src, pos, we, max, c_ref, 3)
                   then $AR.eq_int_int(at(src, we, max), 60)
                   else word_is(src, pos, we, max, c_make, 12)): bool
    val ls = line_start(src, pos, max)
    val lb = at(src, ls, max)
  in
    if is_make && ($AR.eq_int_int(lb, 32) || $AR.eq_int_int(lb, 9)) then we else pos
  end
  else pos

(* Whether the arrow of the lambda whose parameters start at pos names
   a plain function or a linear closure: the first "=>" or "=<" at
   bracket depth 0 is "=<" followed by a word that starts with "fun"
   or "lin" (fun, fun0, fun1, lincloptr1). A plain "=>" leaves the kind
   to the context, which makes it a cloref1 closure when it is given to
   a cloref parameter (one of the prelude's, say) *)
fun _lam_arrow_plain {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n, depth: int): bool =
  if pos >= max then false
  else let
    val b = at(src, pos, max)
  in
    if $AR.eq_int_int(b, 40) || $AR.eq_int_int(b, 91) || $AR.eq_int_int(b, 123) then
      _lam_arrow_plain(src, pos + 1, max, depth + 1)
    else if $AR.eq_int_int(b, 41) || $AR.eq_int_int(b, 93) || $AR.eq_int_int(b, 125) then
      _lam_arrow_plain(src, pos + 1, max, depth - 1)
    else if depth > 0 then _lam_arrow_plain(src, pos + 1, max, depth)
    else if $AR.eq_int_int(b, 61) then let
      val next = at(src, pos + 1, max)
    in
      if $AR.eq_int_int(next, 62) then false
      else if $AR.eq_int_int(next, 60) then let
        val word = skip_ws(src, adv(pos, 2, max), max)
        var fun_c = @[char][3]('f', 'u', 'n')
        var lin_c = @[char][3]('l', 'i', 'n')
      in lit_at(src, word, max, fun_c, 3) || lit_at(src, word, max, lin_c, 3) end
      else _lam_arrow_plain(src, pos + 1, max, depth)
    end
    else _lam_arrow_plain(src, pos + 1, max, depth)
  end

(* lam (not lam@, a flat closure on the stack, nor llam): past the word
   when its arrow does not make it a plain function or a linear closure
   (=<fun1>, =<lincloptr1>), else pos *)
fn bare_lam_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q =
  if $AR.eq_int_int(at(src, pos, max), 108) then let
    var c = @[char][3]('l', 'a', 'm')
    val after = adv(pos, 3, max)
  in
    if looking_at_kw(src, pos, max, c, 3) && ~($AR.eq_int_int(at(src, after, max), 64)) &&
       ~(_lam_arrow_plain(src, after, max, 0))
    then after else pos
  end
  else pos

(* Whether src[i, e) holds "libats/ML" or "libats_ML" (a staload of
   one of its SATS files, or an include of its staload .hats) *)
fun names_libats_ml {l:agz}{n:pos}{i:nat}{e:int} .<max(e - i, 0)>.
  (src: !$A.borrow(byte, l, n), i: int i, e: int e, max: int n): bool =
  if i + 9 > e then false
  else let
    var slash_c = @[char][9]('l', 'i', 'b', 'a', 't', 's', '/', 'M', 'L')
    var underscore_c = @[char][9]('l', 'i', 'b', 'a', 't', 's', '_', 'M', 'L')
  in
    if lit_at(src, i, max, slash_c, 9) || lit_at(src, i, max, underscore_c, 9) then true
    else names_libats_ml(src, i + 1, e, max)
  end

(* #include at pos *)
fn looking_at_include {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): bool =
  if $AR.eq_int_int(at(src, pos, max), 35) then let
    var c = @[char][8]('#', 'i', 'n', 'c', 'l', 'u', 'd', 'e')
  in lit_at(src, pos, max, c, 8) && is_kw_boundary(src, pos + 8, max) end
  else false

(* Whether the source declares its own function or type named src[s, e):
   a "fun", "fn", "datavtype", "vtypedef" or "typedef" keyword, then
   blanks and {quantifier} groups, then the name. The list package's nil
   and cons, which build a list_vt, and the compiler's cons, a linear
   list of version constraints, are their own, not the prelude's macros *)
fun _declares_own {l:agz}{n:pos}{p:nat | p <= n}{s,e:nat | s <= e; e <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n, s: int s, e: int e): bool =
  if p >= max then false
  else let
    var fun_c = @[char][3]('f', 'u', 'n')
    var fn_c = @[char][2]('f', 'n')
    var datavtype_c = @[char][9]('d', 'a', 't', 'a', 'v', 't', 'y', 'p', 'e')
    var vtypedef_c = @[char][8]('v', 't', 'y', 'p', 'e', 'd', 'e', 'f')
    var typedef_c = @[char][7]('t', 'y', 'p', 'e', 'd', 'e', 'f')
    val keyword_end = (if looking_at_kw(src, p, max, fun_c, 3) then adv(p, 3, max)
                       else if looking_at_kw(src, p, max, fn_c, 2) then adv(p, 2, max)
                       else if looking_at_kw(src, p, max, datavtype_c, 9) then adv(p, 9, max)
                       else if looking_at_kw(src, p, max, vtypedef_c, 8) then adv(p, 8, max)
                       else if looking_at_kw(src, p, max, typedef_c, 7) then adv(p, 7, max)
                       else p): [q:int | p <= q; q <= n] int q
  in
    if keyword_end > p then let
      val name_start = _skip_to_name(src, keyword_end, max)
      val name_end = skip_ident(src, name_start, max)
    in
      if name_end - name_start = e - s && _names_match(src, name_start, s, e - s, max) then true
      else _declares_own(src, p + 1, max, s, e)
    end
    else _declares_own(src, p + 1, max, s, e)
  end

(* A word of the prelude (or of libats/ML) that builds a non-linear
   list, option or stream (helpers' prelude_build_of), not qualified
   ($X.word names another package's): past it when it is one, else pos.
   nil and cons are the prelude's macros for list_nil and list_cons
   unless the source declares its own *)
fn prelude_word_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q = let
  val b0 = at(src, pos, max)
  val qualified = (if pos > 0 then $AR.eq_int_int(at(src, pos - 1, max), 46) else false): bool
in
  if ~(is_ident_byte(b0)) || (b0 >= 48 && b0 <= 57) || qualified ||
     ~(is_kw_boundary_before(src, pos, max)) then pos
  else let
    val we = skip_ident(src, pos, max)
    var nil_c = @[char][3]('n', 'i', 'l')
    var cons_c = @[char][4]('c', 'o', 'n', 's')
    val is_macro = word_is(src, pos, we, max, nil_c, 3) || word_is(src, pos, we, max, cons_c, 4)
  in
    case+ prelude_build_of(src, pos, we, max) of
    | NoPreludeBuild() => pos
    | _ => if is_macro && _declares_own(src, 0, max, pos, we) then pos else we
  end
end

(* Past the non-linear heap construct at pos when there is one (the
   datatype keyword, a '( '{ '[, a $tup $rec $list, a cloref or cloptr,
   a bare lam, a ref made inside a function, a word of the prelude that
   builds a non-linear list, option or stream, a "::"), else pos *)
fn nonlinear_end {l:agz}{n:pos}{p:nat | p <= n}
  (src: !$A.borrow(byte, l, n), pos: int p, max: int n): [q:int | p <= q; q <= n] int q = let
  val b0 = at(src, pos, max)
in
  if $AR.eq_int_int(b0, 100) then (if datatype_carries(src, pos, max) then adv(pos, 8, max) else pos)
  else if $AR.eq_int_int(b0, 39) then (if boxed_quote(src, pos, max) then adv(pos, 2, max) else pos)
  else if $AR.eq_int_int(b0, 36) then boxed_dollar_end(src, pos, max)
  else if $AR.eq_int_int(b0, 99) && nonlinear_clo_end(src, pos, max) > pos then nonlinear_clo_end(src, pos, max)
  else if $AR.eq_int_int(b0, 114) then inner_ref_end(src, pos, max)
  else if $AR.eq_int_int(b0, 108) && bare_lam_end(src, pos, max) > pos then bare_lam_end(src, pos, max)
  else if $AR.eq_int_int(b0, 58) && $AR.eq_int_int(at(src, pos + 1, max), 58) then adv(pos, 2, max)
  else prelude_word_end(src, pos, max)
end

(* What the word src[s, e) opens: a fun or fnx (a recursive group), an
   and (a member of one), another declaration, or no declaration *)
datatype declaration = RecursiveFun | AndClause | OtherDeclaration | NotDeclaration

(* The declaration the word src[s, e) opens *)
fn decl_word {l:agz}{n:pos}{s,e:int}
  (src: !$A.borrow(byte, l, n), s: int s, e: int e, max: int n): declaration = let
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
  if word_is(src, s, e, max, c_fun, 3) then RecursiveFun()
  else if word_is(src, s, e, max, c_fnx, 3) then RecursiveFun()
  else if word_is(src, s, e, max, c_and, 3) then AndClause()
  else if word_is(src, s, e, max, c_fn, 2) then OtherDeclaration()
  else if word_is(src, s, e, max, c_val, 3) then OtherDeclaration()
  else if word_is(src, s, e, max, c_var, 3) then OtherDeclaration()
  else if word_is(src, s, e, max, c_prfun, 5) then OtherDeclaration()
  else if word_is(src, s, e, max, c_prfn, 4) then OtherDeclaration()
  else if word_is(src, s, e, max, c_impl, 9) then OtherDeclaration()
  else if word_is(src, s, e, max, c_primpl, 11) then OtherDeclaration()
  else if word_is(src, s, e, max, c_extern, 6) then OtherDeclaration()
  else if word_is(src, s, e, max, c_pub, 4) then OtherDeclaration()
  else if word_is(src, s, e, max, c_local, 5) then OtherDeclaration()
  else if word_is(src, s, e, max, c_dt, 8) then OtherDeclaration()
  else if word_is(src, s, e, max, c_dvt, 9) then OtherDeclaration()
  else if word_is(src, s, e, max, c_dvwt, 12) then OtherDeclaration()
  else if word_is(src, s, e, max, c_dp, 8) then OtherDeclaration()
  else if word_is(src, s, e, max, c_dv, 8) then OtherDeclaration()
  else if word_is(src, s, e, max, c_td, 7) then OtherDeclaration()
  else if word_is(src, s, e, max, c_vtd, 8) then OtherDeclaration()
  else if word_is(src, s, e, max, c_vwtd, 11) then OtherDeclaration()
  else if word_is(src, s, e, max, c_sd, 6) then OtherDeclaration()
  else NotDeclaration()
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
    val kind = (if fs - prev <= ind then decl_word(src, fs, we, max) else NotDeclaration()): declaration
  in
    case+ kind of
    | RecursiveFun() => true
    | OtherDeclaration() => false
    | _ => and_in_fun_group(src, prev, ind, max)
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
   close, or m; and whether it was closed *)
fun lex_c_comment_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : @([q:int | q <= n; p <= q || q == m] int q, bool) =
  if pos + 1 >= src_len then @(src_len, false)
  else if $AR.eq_int_int(at(src, pos, max), 42) &&
          $AR.eq_int_int(at(src, pos + 1, max), 47) then @(pos + 2, true)
  else lex_c_comment_inner(src, pos + 1, src_len, max)

(* An unterminated construct at start: Rust's lexer error, at start;
   the construct still runs to the end of the file *)
fn lex_unterminated {n:pos}{s:nat | s < n}
  (spans: !lexout(n) >> lexout(n), start: int s, what: lex_error): int = let
  val () = put_typed(spans, SLexError(start, what, start, start, false))
in 1 end

fn lex_c_comment {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val @(ep, closed) = lex_c_comment_inner(src, adv(start, 2, max), src_len, max)
  val ne = (if closed then 0 else lex_unterminated(spans, start, UnterminatedCComment())): int
  val () = put_typed(spans, SPass(start, ep, true))
in @(ep, count + ne + 1) end

(* The end of a nested (* ... *) comment at depth whose body starts at
   pos: after the close that brings depth to 0, or m; and whether it was
   closed *)
fun lex_ml_comment_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n,
   depth: int): @([q:int | q <= n; p <= q || q == m] int q, bool) =
  if depth <= 0 then @(pos, true)
  else if pos + 1 >= src_len then @(src_len, false)
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
  val @(ep, closed) = lex_ml_comment_inner(src, adv(start, 2, max), src_len, max, 1)
  val ne = (if closed then 0 else lex_unterminated(spans, start, UnterminatedMlComment())): int
  val () = put_typed(spans, SPass(start, ep, true))
in @(ep, count + ne + 1) end

(* The end of a string literal whose body starts at pos, with \" escapes,
   and whether it was closed *)
fun lex_string_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : @([q:int | p <= q; q <= n] int q, bool) =
  if pos >= src_len then @(pos, false)
  else let val b = at(src, pos, max) in
    if $AR.eq_int_int(b, 92) then lex_string_inner(src, adv(pos, 2, max), src_len, max)
    else if $AR.eq_int_int(b, 34) then @(pos + 1, true)
    else lex_string_inner(src, pos + 1, src_len, max)
  end

fn lex_string {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val @(ep, closed) = lex_string_inner(src, start + 1, src_len, max)
  val ne = (if closed then 0 else lex_unterminated(spans, start, UnterminatedString())): int
  val () = put_typed(spans, SPass(start, ep, true))
in @(ep, count + ne + 1) end

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
   or m; and whether it was closed *)
fun lex_extcode_inner {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), pos: int p, src_len: int m, max: int n)
  : @([q:int | q <= n; p <= q || q == m] int q, bool) =
  if pos + 1 >= src_len then @(src_len, false)
  else if $AR.eq_int_int(at(src, pos, max), 37) &&
          $AR.eq_int_int(at(src, pos + 1, max), 125) then @(pos + 2, true)
  else lex_extcode_inner(src, pos + 1, src_len, max)

fn lex_extcode {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n,
   spans: !lexout(n) >> lexout(n), start: int s, count: int): lexed(s, n) = let
  val after_open = adv(start, 2, max)
  val bk = at(src, after_open, max)
  val kind = (if $AR.eq_int_int(bk, 94) then CodeAtTop()
              else if $AR.eq_int_int(bk, 36) then CodeAtEnd()
              else if $AR.eq_int_int(bk, 35) then CodeInStatic()
              else CodeHere()): extcode_kind
  val marked = (case+ kind of CodeHere() => false | _ => true): bool
  val cstart = (if marked then adv(after_open, 1, max)
                else after_open): [q:int | s < q; q <= n] int q
  val @(ep, closed) = lex_extcode_inner(src, cstart, src_len, max)
  val ne = (if closed then 0 else lex_unterminated(spans, start, UnterminatedExtcode())): int
  val cend = (if closed then (if ep >= 2 then ep - 2 else ep) else ep): spos(n)
  val () = put_typed(spans, SExtcode(start, ep, cstart, cend, kind))
in @(ep, count + ne + 1) end

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
    find_end_kw(src, (lex_extcode_inner(src, adv(pos, 2, max), src_len, max)).0,
                src_len, max, depth)
  (* A keyword in a comment, a string or a char literal is text *)
  else if $AR.eq_int_int(at(src, pos, max), 40) &&
          $AR.eq_int_int(at(src, pos + 1, max), 42) then
    find_end_kw(src, (lex_ml_comment_inner(src, adv(pos, 2, max), src_len, max, 1)).0,
                src_len, max, depth)
  else if $AR.eq_int_int(at(src, pos, max), 47) &&
          $AR.eq_int_int(at(src, pos + 1, max), 42) then
    find_end_kw(src, (lex_c_comment_inner(src, adv(pos, 2, max), src_len, max)).0,
                src_len, max, depth)
  else if $AR.eq_int_int(at(src, pos, max), 47) &&
          $AR.eq_int_int(at(src, pos + 1, max), 47) then
    find_end_kw(src, skip_to_eol(src, adv(pos, 2, max), src_len, max),
                src_len, max, depth)
  else if $AR.eq_int_int(at(src, pos, max), 34) then
    find_end_kw(src, (lex_string_inner(src, pos + 1, src_len, max)).0, src_len, max, depth)
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
      val ne = (if end_pos >= src_len then lex_unterminated(spans, start, UnterminatedUnsafe()) else 0): int
      val () = put_typed(spans, SUnsafeBlock(start, ep, contents_start, end_pos))
    in @(ep, count + ne + 1) end
    else @(start, count)
  end
end

(* targets with the native or the wasm target added *)
fn with_target (targets: test_targets, wasm: bool): test_targets =
  case+ targets of
  | NoTestTargets() => if wasm then WasmTests() else NativeTests()
  | NativeTests() => if wasm then AllTargets() else NativeTests()
  | WasmTests() => if wasm then WasmTests() else AllTargets()
  | AllTargets() => AllTargets()

(* How a $UNITTEST.run target list reads *)
datatype target_list = TargetsRead | TargetListEmpty | TargetNotKnown

(* The target list of $UNITTEST.run(...), from p inside the parens
   (Rust: lex_unittest): @(how, targets, q, e) with the targets read
   and q past the list, or an empty list, or an unknown target src[q,
   e). A list that stops at a non-identifier (no ")") ends there, as in
   Rust. *)
fun ut_targets {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, max: int n, targets: test_targets, found: bool)
  : @(target_list, test_targets, [q:int | p <= q; q <= n] int q, spos(n)) = let
  val p1 = skip_ws(src, p, max)
in
  if $AR.eq_int_int(at(src, p1, max), 41) then
    (if found then @(TargetsRead(), targets, adv(p1, 1, max), p1)
     else @(TargetListEmpty(), targets, p1, p1))
  else let
    val ie = skip_ident(src, p1, max)
    var c_native = @[char][6]('n', 'a', 't', 'i', 'v', 'e')
    var c_wasm = @[char][4]('w', 'a', 's', 'm')
  in
    if ie = p1 then @(TargetsRead(), targets, p1, p1)
    else let
      val is_native = word_is(src, p1, ie, max, c_native, 6)
      val is_wasm = word_is(src, p1, ie, max, c_wasm, 4)
    in
      if ~is_native && ~is_wasm then @(TargetNotKnown(), targets, p1, ie)
      else let
        val p2 = skip_ws(src, ie, max)
        val c = at(src, p2, max)
        val added = with_target(targets, is_wasm)
      in
        if $AR.eq_int_int(c, 44) then ut_targets(src, adv(p2, 1, max), max, added, true)
        else if $AR.eq_int_int(c, 41) then @(TargetsRead(), added, adv(p2, 1, max), p2)
        else ut_targets(src, p2, max, added, true)
      end
    end
  end
end

(* What a $UNITTEST header is *)
datatype unittest_header = NotUnittest | UnittestBlock | HeaderEmptyList | HeaderUnknownTarget

(* The header of a $UNITTEST block at s (Rust: lex_unittest):
   @(header, is_run, targets, cs, e1, e2): a $UNITTEST[.run[(targets)]]
   begin, whose contents start at cs; not a unittest block; an empty
   target list, at e1; an unknown target src[e1, e2). The targets are
   native when there is no list. *)
fn ut_header {l:agz}{n:pos}{m:nat | m <= n}{s:nat | s < m}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n, start: int s)
  : @(unittest_header, bool, test_targets, [q:int | s < q; q <= n] int q, spos(n), spos(n)) = let
  val a = adv(start, 9, max)
  val is_run = $AR.eq_int_int(at(src, a, max), 46) &&
    $AR.eq_int_int(at(src, a + 1, max), 114) &&
    $AR.eq_int_int(at(src, a + 2, max), 117) &&
    $AR.eq_int_int(at(src, a + 3, max), 110)
  val p0 = (if is_run then adv(a, 4, max) else a): [q:int | s < q; q <= n] int q
  val run = is_run
in
  if (if is_run then $AR.eq_int_int(at(src, p0, max), 40) else false) then let
    val @(how, targets, q, e) = ut_targets(src, adv(p0, 1, max), max, NoTestTargets(), false)
  in
    case+ how of
    | TargetListEmpty() => @(HeaderEmptyList(), run, NoTestTargets(), p0, p0, p0)
    | TargetNotKnown() => @(HeaderUnknownTarget(), run, NoTestTargets(), p0, q, e)
    | TargetsRead() => let
        val p1 = skip_ws(src, q, max)
      in
        if looking_at_begin(src, p1, max) then @(UnittestBlock(), run, targets, adv(p1, 5, max), 0, 0)
        else @(NotUnittest(), run, NoTestTargets(), p0, 0, 0)
      end
  end
  else let
    val p1 = skip_ws(src, p0, max)
  in
    if looking_at_begin(src, p1, max) then @(UnittestBlock(), run, NativeTests(), adv(p1, 5, max), 0, 0)
    else @(NotUnittest(), run, NoTestTargets(), p0, 0, 0)
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
    else if looking_at_include(src, pos, max) then pos
    else if nonlinear_end(src, pos, max) > pos then pos
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

(* The first non-linear heap construct in the #pub declaration src[p, e),
   or e when there is none (its comments and strings are skipped) *)
fun pub_nonlinear {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int m, max: int n)
  : [q:int | p <= q; q <= n] int q =
  if p >= e then p
  else let
    val b0 = at(src, p, max)
    val b1 = at(src, p + 1, max)
  in
    if $AR.eq_int_int(b0, 40) && $AR.eq_int_int(b1, 42) then let
      val @(q, _) = lex_ml_comment_inner(src, adv(p, 2, max), e, max, 1)
    in pub_nonlinear(src, q, e, max) end
    else if $AR.eq_int_int(b0, 34) then let
      val @(q, _) = lex_string_inner(src, p + 1, e, max)
    in pub_nonlinear(src, q, e, max) end
    else if nonlinear_end(src, p, max) > p then p
    else pub_nonlinear(src, p + 1, e, max)
  end

(* Whether the #pub declaration is rejected: restricted, or a proof
   function with no primplement in the source *)
fn pub_rejected {l:agz}{n:pos}{m:nat | m <= n}{c:nat | c <= n}
  (src: !$A.borrow(byte, l, n), src_len: int m, max: int n, cs: int c): bool = let
  val is_prfun = _content_starts_prfun(src, cs, max)
  val is_prfn = (if is_prfun then false else _content_starts_prfn(src, cs, max)): bool
in
  if _content_starts_restricted(src, cs, max) then true
  else if datatype_carries(src, cs, max) then true
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
    val nl = nonlinear_end(src, pos, max)
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

    (* A non-linear heap construct: a datatype whose constructor carries
       data, a boxed tuple, record or list, a cloref or cloptr closure,
       a bare lam, a ref made inside a function: allocated, never freed *)
    else if nl > pos then let
      val () = put_typed(spans, SConstruct(pos, nl))
    in lex_main(src, src_len, max, spans, nl, count + 1) end

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
      val restricted = pub_rejected(src, src_len, max, contents_start)
      (* A non-linear heap construct in the declaration rejects it, and
         is where its error points (its contents start otherwise) *)
      val nl = pub_nonlinear(src, contents_start, ep, max)
      val () = (if restricted then put_typed(spans, SPub(pos, ep, true, contents_start))
                else if nl < ep then put_typed(spans, SPub(pos, ep, true, nl))
                else put_typed(spans, SPub(pos, ep, false, contents_start))): void
    in lex_main(src, src_len, max, spans, ep, count + 1) end

    (* #target *)
    else if looking_at_target(src, pos, max) then let
      val p0 = skip_ws(src, adv(pos, 7, max), max)
      val ident_end = skip_ident(src, p0, max)
      val is_wasm = $AR.eq_int_int(at(src, p0, max), 119)
      val p1 = skip_ws(src, ident_end, max)
    in
      if looking_at_begin(src, p1, max) then let
        (* Block form: #target wasm begin...end *)
        val cs = adv(p1, 5, max)
        val ce = find_end_kw(src, cs, src_len, max, 1)
        val ep = block_end(ce, src_len, max)
        (* target_begin covers [pos, cs), target_end [ce, ep) *)
        val () = put_typed(spans, STargetBegin(pos, cs, (if is_wasm then Wasm() else Native()): target))
        val inner = lex_main(src, ce, max, spans, cs, 0)
        val () = put_typed(spans, STargetEnd(ce, ep))
      in lex_main(src, src_len, max, spans, ep, count + inner + 2) end
      else if looking_at_binary(src, p1, max) then let
        (* Binary marker form: #target wasm binary *)
        val ep = skip_to_eol(src, adv(p1, 6, max), src_len, max)
        val () = put_typed(spans, STarget(pos, ep, WasmBinaryLine()))
      in lex_main(src, src_len, max, spans, ep, count + 1) end
      else let
        (* Line form: just the directive *)
        val ep = skip_to_eol(src, ident_end, src_len, max)
        val () = put_typed(spans, STarget(pos, ep, (if is_wasm then WasmLine() else NativeLine()): target_line))
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
      val @(header, run, targets, cs, e1, e2) = ut_header(src, src_len, max, pos)
    in
      case+ header of
      | UnittestBlock() => let
        val ce = find_end_kw(src, cs, src_len, max, 1)
        val ep = block_end(ce, src_len, max)
        (* No "end": Rust's "unterminated ... begin...end block", and the
           block runs to the end of the file *)
        val nerr = (if ce >= src_len then let
            val () = put_typed(spans, SLexError(pos, UnterminatedUnittest(), pos, pos, run))
          in 1 end else 0): int
        (* unittest_begin covers [pos, cs), unittest_end [ce, ep) *)
        val () = put_typed(spans, SUnittestBegin(pos, cs, run, targets))
        val inner = lex_main(src, ce, max, spans, cs, 0)
        val () = put_typed(spans, SUnittestEnd(ce, ep))
      in lex_main(src, src_len, max, spans, ep, count + nerr + inner + 2) end
      | _ => let
        (* A bad target list is a lex error (Rust: "empty target list in
           $UNITTEST.run()", "unknown test target"); the text is then
           ordinary code, as when it is no unittest block at all *)
        val nerr = (case+ header of
          | HeaderEmptyList() => let
              val () = put_typed(spans, SLexError(pos, EmptyTargetList(), e1, e2, false))
            in 1 end
          | HeaderUnknownTarget() => let
              val () = put_typed(spans, SLexError(pos, UnknownTarget(), e1, e2, false))
            in 1 end
          | _ => 0): int
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
      (* libats/ML is ATS's garbage-collected library: its lists, options,
         arrays and maps are never freed *)
      val () = (if names_libats_ml(src, pos, ep, max) then put_typed(spans, SConstruct(pos, ep))
                else put_typed(spans, SStaload(pos, ep))): void
    in lex_main(src, src_len, max, spans, ep, count + 1) end
    else if looking_at_include(src, pos, max) &&
            names_libats_ml(src, pos, skip_to_eol(src, pos, src_len, max), max) then let
      val ep = skip_to_eol(src, pos, src_len, max)
      val () = put_typed(spans, SConstruct(pos, ep))
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
