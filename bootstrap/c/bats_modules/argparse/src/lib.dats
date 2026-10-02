staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "result/src/lib.dats"
(* argparse -- type-safe CLI argument parser *)
(* Phantom-typed handles ensure correct value extraction. *)
(* The parser is indexed by its text position and its argument count,
   so every table access is proven in bounds at compile time. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload R = "result/src/lib.sats"

(* ============================================================
   Value type tags (phantom types)
   ============================================================ *)






(* Which value kind a handle reads; a proof, erased at run time. *)






(* Phantom-typed argument handle: its spec index, below MAX_ARGS by
   construction, with a proof of its value kind. It is flat (one int at
   run time), so it allocates nothing and needs no freeing; handles can
   be kept and passed around freely. *)


(* ============================================================
   Spec constants
   ============================================================ *)

stadef MAX_ARGS = 64
stadef MAX_TEXT = 8192
stadef SPEC_STRIDE = 16

(* ============================================================
   Parser (linear, indexed by text position and argument count)
   ============================================================ *)










(* ============================================================
   Parse result (linear)
   ============================================================ *)














(* ============================================================
   Parse error (linear)
   ============================================================ *)























(* The values an int argument may take: any, or those in [low, high].
   Linear: IntBetween is a cell, freed when add_int stores it *)




(* ============================================================
   API — Construction
   ============================================================ *)

(* Each argument but a positional one or a subcommand may have a short
   name, a character (-c): given as $R.some(c), or $R.none() *)




























(* Registers a subcommand; returns its index (0 for the first one, 1
   for the next, ...), which get_subcmd gives back when it is chosen.
   A subcommand takes one of the 64 argument slots. *)





(* ============================================================
   API — Parsing
   ============================================================ *)






(* ============================================================
   API — Extraction (phantom-typed)
   ============================================================ *)
















(* The index add_subcommand returned for the subcommand argv chose, if
   it chose one. The first positional token that names a subcommand
   chooses it; later tokens are ordinary positionals. *)


(* ============================================================
   API — Cleanup
   ============================================================ *)



















(* ============================================================
   Implementation helpers
   ============================================================ *)

(* x as a value proven below 65536; equal to x when 0 <= x < 65536.
   Text offsets and lengths are below 8192, so decoding a stored one
   gives it back exactly, now usable as an index. *)
fn _u16 (x: int): [v:nat | v < 65536] int v =
  $AR.low_byte(x) + 256 * $AR.low_byte(x / 256)

fn _text_write
  {lt:agz}{lb:agz}{n:pos}{p:nat | p + n <= 8192}
  (tbuf: !$A.arr(byte, lt, 8192), pos: int p,
   src: !$A.borrow(byte, lb, n), len: int n): int(p + n) = let
  fun loop {lt2:agz}{lb2:agz}{nn:pos}{pp:nat | pp + nn <= 8192}{i:nat | i <= nn} .<nn - i>.
    (dst: !$A.arr(byte, lt2, 8192), src: !$A.borrow(byte, lb2, nn),
     p: int pp, si: int i, n: int nn): void =
    if si >= n then ()
    else let
      val () = $A.set<byte>(dst, p + si, $A.read<byte>(src, si))
    in loop(dst, src, p, si + 1, n) end
  val () = loop(tbuf, src, pos, 0, len)
in pos + len end

fn _spec_set {ls:agz}{i:nat | i < 64}{f:nat | f < 16}
  (specs: !$A.arr(int, ls, 1024), i: int i, f: int f, v: int): void =
  $A.set<int>(specs, i * 16 + f, v)

fn _spec_get {ls:agz}{i:nat | i < 64}{f:nat | f < 16}
  (specs: !$A.arr(int, ls, 1024), i: int i, f: int f): int =
  $A.get<int>(specs, i * 16 + f)

(* What a spec is. The table stores it as a number in field 0, written
   by _kind_code and read by _spec_kind: the one place each way *)
datatype spec_kind =
  | PositionalString
  | OptionString
  | OptionInt
  | Flag
  | Count
  | Subcommand

fn _kind_code (kind: spec_kind): int =
  case+ kind of
  | PositionalString() => 0
  | OptionString() => 1
  | OptionInt() => 2
  | Flag() => 3
  | Count() => 4
  | Subcommand() => 5

fn _spec_kind {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i): spec_kind = let
  val code = _spec_get(specs, i, 0)
in
  if code = 0 then PositionalString()
  else if code = 1 then OptionString()
  else if code = 2 then OptionInt()
  else if code = 3 then Flag()
  else if code = 4 then Count()
  else Subcommand()
end

(* Whether a spec of this kind is an option (named --name or -c) *)
fn _is_option (kind: spec_kind): bool =
  case+ kind of
  | PositionalString() => false
  | OptionString() => true
  | OptionInt() => true
  | Flag() => true
  | Count() => true
  | Subcommand() => false

(* A spec's short name: field 9 says whether it has one (1) or not
   (0), field 6 which; written by _short_store, read by _spec_short *)
fn _short_store {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i, short_name: $R.option(int)): void =
  case+ short_name of
  | ~$R.some(c) => let
      val () = _spec_set(specs, i, 9, 1)
    in _spec_set(specs, i, 6, c) end
  | ~$R.none() => _spec_set(specs, i, 9, 0)

fn _spec_short {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i): $R.option(int) =
  if _spec_get(specs, i, 9) = 1 then $R.some(_spec_get(specs, i, 6)) else $R.none()

(* An int spec's range: field 12 says whether it has one (1) or not
   (0), fields 10 and 11 its ends *)
fn _range_store {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i, range: int_range): void =
  case+ range of
  | ~AnyInt() => _spec_set(specs, i, 12, 0)
  | ~IntBetween(low, high) => let
      val () = _spec_set(specs, i, 12, 1)
      val () = _spec_set(specs, i, 10, low)
    in _spec_set(specs, i, 11, high) end

fn _spec_range {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i): int_range =
  if _spec_get(specs, i, 12) = 1 then IntBetween(_spec_get(specs, i, 10), _spec_get(specs, i, 11))
  else AnyInt()

(* A spec's exclusive group: field 13 says whether it is in one (1) or
   not (0), field 15 which *)
fn _group_store {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i, group: int): void = let
  val () = _spec_set(specs, i, 13, 1)
in _spec_set(specs, i, 15, group) end

fn _in_group {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i, group: int): bool =
  _spec_get(specs, i, 13) = 1 && _spec_get(specs, i, 15) = group

(* Sets a[i] = v for every i in [i0, n). *)
fun _fill_int {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(int, l, n), n: int n, i: int i, v: int): void =
  if i >= n then ()
  else let val () = $A.set<int>(a, i, v) in _fill_int(a, n, i + 1, v) end

(* Sets a[j] = v for every j in [j0, e). *)
fun _fill_int_range {l:agz}{n:pos}{j,e:nat | j <= e; e <= n} .<e - j>.
  (a: !$A.arr(int, l, n), j: int j, e: int e, v: int): void =
  if j >= e then ()
  else let val () = $A.set<int>(a, j, v) in _fill_int_range(a, j + 1, e, v) end

(* ============================================================
   Implementations — Construction
   ============================================================ *)

implement parser_new {lp}{np}{lh}{nh} (name, nlen, help, hlen) = let
  val specs = $A.alloc<int>(1024)
  val tbuf = $A.alloc<byte>(8192)
  val tp = _text_write(tbuf, 0, name, nlen)
  val tp2 = _text_write(tbuf, tp, help, hlen)
in parser_mk(specs, tbuf, 0, tp2, 0, 0, 0, nlen, tp, hlen) end

implement parser_free {tp0}{ac0} (p) = let
  val+ ~parser_mk(specs, tbuf, _, _, _, _, _, _, _, _) = p
in $A.free<int>(specs); $A.free<byte>(tbuf) end

fn _add_base
  {tp0:nat | tp0 <= 8192}{ac0:nat | ac0 < 64}{ln:agz}{nn:pos}{lh:agz}{nh:pos | tp0 + nn + nh <= 8192}
  (p: parser(tp0, ac0), kind: spec_kind,
   name: !$A.borrow(byte, ln, nn), nlen: int nn,
   short_name: $R.option(int),
   help: !$A.borrow(byte, lh, nh), hlen: int nh,
   def_int: int): @(parser(tp0 + nn + nh, ac0 + 1), int ac0) = let
  val+ ~parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) = p
  val noff = tp
  val tp2 = _text_write(tbuf, tp, name, nlen)
  val hoff = tp2
  val tp3 = _text_write(tbuf, tp2, help, hlen)
  (* Every field is written (0: no short name, no range, in no group),
     so nothing later reads uninitialized memory. *)
  val () = _fill_int_range(specs, ac * 16, ac * 16 + 16, 0)
  val () = _spec_set(specs, ac, 0, _kind_code(kind))
  val () = _spec_set(specs, ac, 2, noff)
  val () = _spec_set(specs, ac, 3, nlen)
  val () = _spec_set(specs, ac, 4, hoff)
  val () = _spec_set(specs, ac, 5, hlen)
  val () = _short_store(specs, ac, short_name)
  val () = _spec_set(specs, ac, 7, def_int)
in @(parser_mk(specs, tbuf, ac + 1, tp3, gc, sc, pno, pnl, pho, phl), ac) end

(* A positional argument has no short name: one given is dropped *)
implement add_string {tp0}{ac0}{ln}{nn}{lh}{nh} (p, name, nlen, short_name, help, hlen, positional) =
  if positional then let
    val () = $R.option_discard<int>(short_name)
    val @(p2, idx) = _add_base(p, PositionalString(), name, nlen, $R.none(), help, hlen, 0)
  in @(p2, (kind_string() | idx)) end
  else let
    val @(p2, idx) = _add_base(p, OptionString(), name, nlen, short_name, help, hlen, 0)
  in @(p2, (kind_string() | idx)) end

implement add_int {tp0}{ac0}{ln}{nn}{lh}{nh} (p, name, nlen, short_name, help, hlen, def, range) = let
  val @(p2, idx) = _add_base(p, OptionInt(), name, nlen, short_name, help, hlen, def)
  val+ ~parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) = p2
  val () = _range_store(specs, idx, range)
in @(parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl), (kind_int() | idx)) end

implement add_flag {tp0}{ac0}{ln}{nn}{lh}{nh} (p, name, nlen, short_name, help, hlen) = let
  val @(p2, idx) = _add_base(p, Flag(), name, nlen, short_name, help, hlen, 0)
in @(p2, (kind_bool() | idx)) end

implement add_count {tp0}{ac0}{ln}{nn}{lh}{nh} (p, name, nlen, short_name, help, hlen) = let
  val @(p2, idx) = _add_base(p, Count(), name, nlen, short_name, help, hlen, 0)
in @(p2, (kind_count() | idx)) end

(* A subcommand is a spec of its own kind (neither positional nor
   option, so no option or positional search finds it) whose field 8
   holds its subcommand index. *)
implement add_subcommand {tp0}{ac0}{ln}{nn}{lh}{nh} (p, name, nlen, help, hlen) = let
  val @(p2, idx) = _add_base(p, Subcommand(), name, nlen, $R.none(), help, hlen, 0)
  val+ ~parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) = p2
  val () = _spec_set(specs, idx, 8, sc)
in @(parser_mk(specs, tbuf, ac, tp, gc, sc + 1, pno, pnl, pho, phl), sc) end

(* ============================================================
   Implementations — Parse
   ============================================================ *)

(* argv[ao + k] = tbuf[to + k] for every k < n. *)
fn _bytes_eq
  {la:agz}{na:pos}{lt:agz}{ao:nat}{to:nat}{n:nat | ao + n <= na; to + n <= 8192}
  (argv: !$A.borrow(byte, la, na), ao: int ao,
   tbuf: !$A.arr(byte, lt, 8192), to: int to, n: int n): bool = let
  fun loop {i:nat | i <= n} .<n - i>.
    (argv: !$A.borrow(byte, la, na), tbuf: !$A.arr(byte, lt, 8192), i: int i): bool =
    if i >= n then true
    else if byte2int0($A.read<byte>(argv, ao + i)) = byte2int0($A.get<byte>(tbuf, to + i)) then
      loop(argv, tbuf, i + 1)
    else false
in loop(argv, tbuf, 0) end

(* A spec index of a parser of ac specs *)
typedef spec_index(ac:int) = [r:nat | r < ac] int r

(* Index of the option named argv[off, off + len), if there is one *)
fn _find_by_name
  {la:agz}{na:pos}{ls:agz}{lt:agz}{ac:nat | ac <= 64}{o:nat}{n:nat | o + n <= na}
  (argv: !$A.borrow(byte, la, na), off: int o, len: int n,
   specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192), ac: int ac)
  : $R.option(spec_index(ac)) = let
  fun loop {i:nat | i <= ac} .<ac - i>.
    (argv: !$A.borrow(byte, la, na), specs: !$A.arr(int, ls, 1024),
     tbuf: !$A.arr(byte, lt, 8192), i: int i): $R.option(spec_index(ac)) =
    if i >= ac then $R.none()
    else if ~_is_option(_spec_kind(specs, i)) then loop(argv, specs, tbuf, i + 1)
    else let
      val snoff = _u16(_spec_get(specs, i, 2))
      val snlen = _u16(_spec_get(specs, i, 3))
    in
      if snlen != len then loop(argv, specs, tbuf, i + 1)
      else if snoff + snlen > 8192 then loop(argv, specs, tbuf, i + 1)
      else if _bytes_eq(argv, off, tbuf, snoff, len) then $R.some(i)
      else loop(argv, specs, tbuf, i + 1)
    end
in loop(argv, specs, tbuf, 0) end

(* Whether spec i's short name is ch *)
fn _short_is {ls:agz}{i:nat | i < 64} (specs: !$A.arr(int, ls, 1024), i: int i, ch: int): bool =
  case+ _spec_short(specs, i) of
  | ~$R.some(c) => c = ch
  | ~$R.none() => false

(* Index of the option with short name ch, if there is one *)
fn _find_by_short
  {ls:agz}{ac:nat | ac <= 64}
  (specs: !$A.arr(int, ls, 1024), ch: int, ac: int ac): $R.option(spec_index(ac)) = let
  fun loop {i:nat | i <= ac} .<ac - i>.
    (specs: !$A.arr(int, ls, 1024), i: int i): $R.option(spec_index(ac)) =
    if i >= ac then $R.none()
    else if _is_option(_spec_kind(specs, i)) && _short_is(specs, i, ch) then $R.some(i)
    else loop(specs, i + 1)
in loop(specs, 0) end

(* Whether a spec of this kind is a positional argument *)
fn _is_positional (kind: spec_kind): bool =
  case+ kind of
  | PositionalString() => true
  | OptionString() => false
  | OptionInt() => false
  | Flag() => false
  | Count() => false
  | Subcommand() => false

(* Index of the pi-th positional spec, if there is one *)
fn _find_pos_spec
  {ls:agz}{ac:nat | ac <= 64}
  (specs: !$A.arr(int, ls, 1024), ac: int ac, pi: int): $R.option(spec_index(ac)) = let
  fun loop {i:nat | i <= ac} .<ac - i>.
    (specs: !$A.arr(int, ls, 1024), i: int i, pi: int): $R.option(spec_index(ac)) =
    if i >= ac then $R.none()
    else if _is_positional(_spec_kind(specs, i)) then
      if pi = 0 then $R.some(i)
      else loop(specs, i + 1, pi - 1)
    else loop(specs, i + 1, pi)
in loop(specs, 0, pi) end

(* Whether a spec of this kind is a subcommand *)
fn _is_subcommand (kind: spec_kind): bool =
  case+ kind of
  | PositionalString() => false
  | OptionString() => false
  | OptionInt() => false
  | Flag() => false
  | Count() => false
  | Subcommand() => true

(* Subcommand index of the subcommand named argv[off, off + len), if
   there is one *)
fn _find_subcmd
  {la:agz}{na:pos}{ls:agz}{lt:agz}{ac:nat | ac <= 64}{o:nat}{n:nat | o + n <= na}
  (argv: !$A.borrow(byte, la, na), off: int o, len: int n,
   specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192), ac: int ac): $R.option(int) = let
  fun loop {i:nat | i <= ac} .<ac - i>.
    (argv: !$A.borrow(byte, la, na), specs: !$A.arr(int, ls, 1024),
     tbuf: !$A.arr(byte, lt, 8192), i: int i): $R.option(int) =
    if i >= ac then $R.none()
    else if ~_is_subcommand(_spec_kind(specs, i)) then loop(argv, specs, tbuf, i + 1)
    else let
      val snoff = _u16(_spec_get(specs, i, 2))
      val snlen = _u16(_spec_get(specs, i, 3))
    in
      if snlen != len then loop(argv, specs, tbuf, i + 1)
      else if snoff + snlen > 8192 then loop(argv, specs, tbuf, i + 1)
      else if _bytes_eq(argv, off, tbuf, snoff, len) then $R.some(_spec_get(specs, i, 8))
      else loop(argv, specs, tbuf, i + 1)
    end
in loop(argv, specs, tbuf, 0) end

(* argv[off, off + len) as a decimal int with an optional leading '-';
   none for a non-digit, an empty string, or a value that does not fit
   in an int. *)
fn _parse_int
  {la:agz}{na:pos}{o:nat}{n:nat | o + n <= na}
  (argv: !$A.borrow(byte, la, na), off: int o, len: int n): $R.option(int) = let
  fun digits {i:nat | i <= n} .<n - i>.
    (argv: !$A.borrow(byte, la, na), i: int i, acc: int): $R.option(int) =
    if i >= len then $R.some(acc)
    else let
      val b = byte2int0($A.read<byte>(argv, off + i))
    in
      if b < 48 then $R.none()
      else if b > 57 then $R.none()
      else if acc > 214748364 then $R.none()
      else if acc = 214748364 then
        if b > 55 then $R.none()
        else digits(argv, i + 1, acc * 10 + (b - 48))
      else digits(argv, i + 1, acc * 10 + (b - 48))
    end
in
  if len <= 0 then $R.none()
  else if byte2int0($A.read<byte>(argv, off)) = 45 then
    (if len <= 1 then $R.none()
     else case+ digits(argv, 1, 0) of
       | ~$R.some(v) => $R.some(0 - v)
       | ~$R.none() => $R.none())
  else digits(argv, 0, 0)
end

(* Copies argv[off, off + len) into the value buffer at sp and records
   it for spec idx. Returns the next free position, or none when the
   value does not fit. *)
fn _store_str
  {la:agz}{na:pos}{ls:agz}{lm:agz}{o:nat}{n:nat | o + n <= na}{i:nat | i < 64}{sp:nat | sp <= 8192}
  (argv: !$A.borrow(byte, la, na), off: int o, len: int n,
   str_buf: !$A.arr(byte, ls, 8192), str_meta: !$A.arr(int, lm, 128),
   idx: int i, sp: int sp): $R.option([r:nat | r <= 8192] int r) =
  if sp + len > 8192 then $R.none()
  else let
    fun copy {k:nat | k <= n} .<n - k>.
      (argv: !$A.borrow(byte, la, na), dst: !$A.arr(byte, ls, 8192), k: int k): void =
      if k >= len then ()
      else let
        val () = $A.set<byte>(dst, sp + k, $A.read<byte>(argv, off + k))
      in copy(argv, dst, k + 1) end
    val () = copy(argv, str_buf, 0)
    val () = $A.set<int>(str_meta, idx * 2, sp)
    val () = $A.set<int>(str_meta, idx * 2 + 1, len)
  in $R.some(sp + len) end

(* End of the NUL-terminated token starting at p (the NUL, or na). *)
fun _find_tok_end
  {la:agz}{na:pos}{p:nat | p <= na} .<na - p>.
  (argv: !$A.borrow(byte, la, na), p: int p, na: int na): [r:int | p <= r; r <= na] int r =
  if p >= na then p
  else if byte2int0($A.read<byte>(argv, p)) = 0 then p
  else _find_tok_end(argv, p + 1, na)

(* Levenshtein distance between argv[ao, ao + n) and tbuf[to, to + m),
   one DP row at a time. Used for "did you mean?" suggestions. *)
fn _edit_dist
  {la:agz}{na:pos}{lt:agz}{ao:nat}{n:nat | ao + n <= na}{to:nat}{m:nat | to + m <= 8192}
  (argv: !$A.borrow(byte, la, na), ao: int ao, n: int n,
   tbuf: !$A.arr(byte, lt, 8192), to: int to, m: int m): int = let
  val row = $A.alloc<int>(m + 1)
  fun init {lr:agz}{j:nat | j <= m + 1} .<m + 1 - j>.
    (row: !$A.arr(int, lr, m + 1), j: int j): void =
    if j > m then ()
    else let val () = $A.set<int>(row, j, j) in init(row, j + 1) end
  (* Fills row j of the table for a[0, i]; diag is D[i - 1][j - 1]. *)
  fun cols {lr:agz}{i:pos | i <= n}{j:pos | j <= m + 1} .<m + 1 - j>.
    (argv: !$A.borrow(byte, la, na), tbuf: !$A.arr(byte, lt, 8192),
     row: !$A.arr(int, lr, m + 1), i: int i, j: int j, diag: int): void =
    if j > m then ()
    else let
      val up = $A.get<int>(row, j)
      val left = $A.get<int>(row, j - 1)
      val cost =
        (if byte2int0($A.read<byte>(argv, ao + i - 1)) = byte2int0($A.get<byte>(tbuf, to + j - 1))
         then 0 else 1): int
      val a = up + 1
      val b = left + 1
      val c = diag + cost
      val mn = (if a < b then a else b): int
      val () = $A.set<int>(row, j, (if c < mn then c else mn))
    in cols(argv, tbuf, row, i, j + 1, up) end
  fun rows {lr:agz}{i:pos | i <= n + 1} .<n + 1 - i>.
    (argv: !$A.borrow(byte, la, na), tbuf: !$A.arr(byte, lt, 8192),
     row: !$A.arr(int, lr, m + 1), i: int i): void =
    if i > n then ()
    else let
      val diag = $A.get<int>(row, 0)
      val () = $A.set<int>(row, 0, i)
      val () = cols(argv, tbuf, row, i, 1, diag)
    in rows(argv, tbuf, row, i + 1) end
  val () = init(row, 0)
  val () = rows(argv, tbuf, row, 1)
  val d = $A.get<int>(row, m)
  val () = $A.free<int>(row)
in d end

(* Index of the option name closest to argv[off, off + len), if an
   option is within distance 999 *)
fn _find_closest
  {la:agz}{na:pos}{ls:agz}{lt:agz}{ac:nat | ac <= 64}{o:nat}{n:nat | o + n <= na}
  (argv: !$A.borrow(byte, la, na), off: int o, len: int n,
   specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192), ac: int ac): $R.option(int) = let
  fun loop {i:nat | i <= ac} .<ac - i>.
    (argv: !$A.borrow(byte, la, na), specs: !$A.arr(int, ls, 1024),
     tbuf: !$A.arr(byte, lt, 8192), i: int i, best: $R.option(int), best_d: int): $R.option(int) =
    if i >= ac then best
    else if ~_is_option(_spec_kind(specs, i)) then loop(argv, specs, tbuf, i + 1, best, best_d)
    else let
      val snoff = _u16(_spec_get(specs, i, 2))
      val snlen = _u16(_spec_get(specs, i, 3))
    in
      if snoff + snlen > 8192 then loop(argv, specs, tbuf, i + 1, best, best_d)
      else let
        val d = _edit_dist(argv, off, len, tbuf, snoff, snlen)
      in
        if d < best_d then let
          val () = $R.option_discard<int>(best)
        in loop(argv, specs, tbuf, i + 1, $R.some(i), d) end
        else loop(argv, specs, tbuf, i + 1, best, best_d)
      end
    end
in loop(argv, specs, tbuf, 0, $R.none(), 999) end

fn _free_parse_temps
  {ls:agz}{lm:agz}{li:agz}{lb:agz}{lp:agz}{lt:agz}{lsp:agz}
  (str_buf: $A.arr(byte, ls, 8192), str_meta: $A.arr(int, lm, 128),
   int_vals: $A.arr(int, li, 64), bool_vals: $A.arr(int, lb, 64),
   present: $A.arr(int, lp, 64), tbuf: $A.arr(byte, lt, 8192),
   specs: $A.arr(int, lsp, 1024)): void = let
  val () = $A.free<byte>(str_buf)
  val () = $A.free<int>(str_meta)
  val () = $A.free<int>(int_vals)
  val () = $A.free<int>(bool_vals)
  val () = $A.free<int>(present)
  val () = $A.free<byte>(tbuf)
  val () = $A.free<int>(specs)
in end

implement parse {tp0}{ac0}{la}{na} (p, argv, argv_len, argc) = let
  val+ ~parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) = p
  val str_buf = $A.alloc<byte>(8192)
  val str_meta = $A.alloc<int>(128)
  val int_vals = $A.alloc<int>(64)
  val bool_vals = $A.alloc<int>(64)
  val present = $A.alloc<int>(64)
  val () = _fill_int(str_meta, 128, 0, 0)
  val () = _fill_int(int_vals, 64, 0, 0)
  val () = _fill_int(bool_vals, 64, 0, 0)
  val () = _fill_int(present, 64, 0, 0)

  (* Defaults for int arguments. *)
  fun init_defs {ls:agz}{li:agz}{k:nat | k <= ac0} .<ac0 - k>.
    (specs: !$A.arr(int, ls, 1024), ivals: !$A.arr(int, li, 64), i: int k): void =
    if i >= ac then ()
    else let
      val () = $A.set<int>(ivals, i, _spec_get(specs, i, 7))
    in init_defs(specs, ivals, i + 1) end
  val () = init_defs(specs, int_vals, 0)

  (* An option's string value, argv[vs, ve), stored for spec idx *)
  fn store_value
    {lm:agz}{lsb:agz}{i:nat | i < ac0}{sp:nat | sp <= 8192}{vs,ve:nat | vs <= ve; ve <= na}
    (argv: !$A.borrow(byte, la, na),
     str_buf: !$A.arr(byte, lsb, 8192), str_meta: !$A.arr(int, lm, 128),
     idx: int i, str_pos: int sp, vs: int vs, ve: int ve, tok_num: int)
    : @([s:nat | s <= 8192] int s, [q:nat | q == ve + 1] int q, int, $R.option(parse_error)) =
    case+ _store_str(argv, vs, ve - vs, str_buf, str_meta, idx, str_pos) of
    | ~$R.some(sp2) => @(sp2, ve + 1, tok_num + 2, $R.none())
    | ~$R.none() => @(str_pos, ve + 1, tok_num + 2, $R.some(err_too_long(idx + 1)))

  (* Handles the option with spec index idx whose token ended at
     next_pos - 1: a flag or count takes no value, others take the next
     token. Returns (str_pos, next_av_pos, tok_num, the error if one) *)
  fn process_option
    {ls:agz}{lm:agz}{li:agz}{lb:agz}{lp:agz}{lsb:agz}
    {i:nat | i < ac0}{sp:nat | sp <= 8192}{np:nat | np <= na + 1}
    (argv: !$A.borrow(byte, la, na),
     specs: !$A.arr(int, ls, 1024),
     str_buf: !$A.arr(byte, lsb, 8192), str_meta: !$A.arr(int, lm, 128),
     int_vals: !$A.arr(int, li, 64), bool_vals: !$A.arr(int, lb, 64),
     present: !$A.arr(int, lp, 64),
     idx: int i, str_pos: int sp, next_pos: int np, tok_num: int)
    : @([s:nat | s <= 8192] int s, [q:nat | np <= q; q <= na + 1] int q, int, $R.option(parse_error)) = let
    val () = $A.set<int>(present, idx, 1)
    val vs = min(next_pos, argv_len)
    val ve = _find_tok_end(argv, vs, argv_len)
  in
    case+ _spec_kind(specs, idx) of
    | Flag() => let
        val () = $A.set<int>(bool_vals, idx, $A.get<int>(bool_vals, idx) + 1)
      in @(str_pos, next_pos, tok_num + 1, $R.none()) end
    | Count() => let
        val () = $A.set<int>(bool_vals, idx, $A.get<int>(bool_vals, idx) + 1)
      in @(str_pos, next_pos, tok_num + 1, $R.none()) end
    | OptionInt() =>
      (case+ _parse_int(argv, vs, ve - vs) of
       | ~$R.some(iv) => let
           val () = $A.set<int>(int_vals, idx, iv)
         in @(str_pos, ve + 1, tok_num + 2, $R.none()) end
       | ~$R.none() => @(str_pos, ve + 1, tok_num + 2, $R.some(err_not_int(idx + 1))))
    | OptionString() => store_value(argv, str_buf, str_meta, idx, str_pos, vs, ve, tok_num)
    (* not options: the option lookups never give one, and a value is
       taken as a string's would be *)
    | PositionalString() => store_value(argv, str_buf, str_meta, idx, str_pos, vs, ve, tok_num)
    | Subcommand() => @(str_pos, next_pos, tok_num + 1, $R.none())
  end

  (* One token per step; av_pos moves forward every step. Returns the
     string buffer's end, the subcommand chosen if one was, and the
     error if one stopped the scan *)
  fun scan_argv
    {ls:agz}{lt:agz}{li:agz}{lb:agz}{lp:agz}{lm:agz}{lsb:agz}
    {sp:nat | sp <= 8192}{ap:nat | ap <= na + 1} .<na + 1 - ap>.
    (argv: !$A.borrow(byte, la, na),
     specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192),
     str_buf: !$A.arr(byte, lsb, 8192), str_meta: !$A.arr(int, lm, 128),
     int_vals: !$A.arr(int, li, 64), bool_vals: !$A.arr(int, lb, 64),
     present: !$A.arr(int, lp, 64),
     pos_idx: int, str_pos: int sp,
     av_pos: int ap, tok_num: int, chosen: $R.option(int))
    : @(int, $R.option(int), $R.option(parse_error)) =
    if tok_num >= argc then @(str_pos, chosen, $R.none())
    else if av_pos >= argv_len then @(str_pos, chosen, $R.none())
    else let
      val tok_start = av_pos
      val tok_end = _find_tok_end(argv, tok_start, argv_len)
      val tok_len = tok_end - tok_start
      val next_pos = tok_end + 1
    in
      if tok_len <= 0 then
        scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
          pos_idx, str_pos, next_pos, tok_num + 1, chosen)
      else let
        val b0 = byte2int0($A.read<byte>(argv, tok_start))
        val b1 = (if tok_start + 1 < argv_len then byte2int0($A.read<byte>(argv, tok_start + 1)) else 0): int
      in
        if b0 = 45 then
          if b1 = 45 then
            if tok_len < 2 then @(str_pos, chosen, $R.some(err_unknown_long($R.none())))
            else (* long option *)
              (case+ _find_by_name(argv, tok_start + 2, tok_len - 2, specs, tbuf, ac) of
               | ~$R.some(opt) => let
                   val @(sp2, np2, tn2, failed) = process_option(argv, specs,
                     str_buf, str_meta, int_vals, bool_vals, present,
                     opt, str_pos, next_pos, tok_num)
                 in
                   case+ failed of
                   | ~$R.some(e) => @(sp2, chosen, $R.some(e))
                   | ~$R.none() => scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                       pos_idx, sp2, np2, tn2, chosen)
                 end
               | ~$R.none() =>
                 @(str_pos, chosen, $R.some(err_unknown_long(_find_closest(argv, tok_start + 2, tok_len - 2, specs, tbuf, ac)))))
          else (* short option *)
            (case+ _find_by_short(specs, b1, ac) of
             | ~$R.some(opt) => let
                 val @(sp2, np2, tn2, failed) = process_option(argv, specs,
                   str_buf, str_meta, int_vals, bool_vals, present,
                   opt, str_pos, next_pos, tok_num)
               in
                 case+ failed of
                 | ~$R.some(e) => @(sp2, chosen, $R.some(e))
                 | ~$R.none() => scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                     pos_idx, sp2, np2, tn2, chosen)
               end
             | ~$R.none() => @(str_pos, chosen, $R.some(err_unknown_short(b1))))
        else let (* subcommand or positional *)
          val choosing = $R.is_none<int>(chosen)
          val sub = (if choosing then _find_subcmd(argv, tok_start, tok_len, specs, tbuf, ac)
                     else $R.none()): $R.option(int)
        in
          case+ sub of
          | ~$R.some(sub_index) => let
              val () = $R.option_discard<int>(chosen)
            in
              scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                pos_idx, str_pos, next_pos, tok_num + 1, $R.some(sub_index))
            end
          | ~$R.none() =>
            (case+ _find_pos_spec(specs, ac, pos_idx) of
             | ~$R.some(pidx) => let
                 val () = $A.set<int>(present, pidx, 1)
               in
                 case+ _store_str(argv, tok_start, tok_len, str_buf, str_meta, pidx, str_pos) of
                 | ~$R.none() => @(str_pos, chosen, $R.some(err_too_long(pidx + 1)))
                 | ~$R.some(sp2) => scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                     pos_idx + 1, sp2, next_pos, tok_num + 1, chosen)
               end
             | ~$R.none() =>
               if sc > 0 && choosing then @(str_pos, chosen, $R.some(err_choice(tok_num)))
               else (* a positional nothing takes is ignored *)
                 scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                   pos_idx, str_pos, next_pos, tok_num + 1, chosen))
        end
      end
    end

  (* Skip the first token (program name). *)
  val first_end = _find_tok_end(argv, 0, argv_len)

  val @(final_sp, chosen, scan_failure) =
    scan_argv(argv, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
      0, 0, first_end + 1, 1, $R.none())

  (* Int range validation: a present int argument with a range must lie
     in it. The spec index + 1 of the first that does not, if one *)
  fun check_ranges {ls:agz}{li:agz}{lp:agz}{k:nat | k <= ac0} .<ac0 - k>.
    (specs: !$A.arr(int, ls, 1024), int_vals: !$A.arr(int, li, 64),
     present: !$A.arr(int, lp, 64), i: int k): $R.option(int) =
    if i >= ac then $R.none()
    else if $A.get<int>(present, i) <= 0 then check_ranges(specs, int_vals, present, i + 1)
    else
      case+ _spec_kind(specs, i) of
      | OptionInt() => (case+ _spec_range(specs, i) of
        | ~AnyInt() => check_ranges(specs, int_vals, present, i + 1)
        | ~IntBetween(low, high) => let
            val v = $A.get<int>(int_vals, i)
          in
            if v < low then $R.some(i + 1)
            else if v > high then $R.some(i + 1)
            else check_ranges(specs, int_vals, present, i + 1)
          end)
      | PositionalString() => check_ranges(specs, int_vals, present, i + 1)
      | OptionString() => check_ranges(specs, int_vals, present, i + 1)
      | Flag() => check_ranges(specs, int_vals, present, i + 1)
      | Count() => check_ranges(specs, int_vals, present, i + 1)
      | Subcommand() => check_ranges(specs, int_vals, present, i + 1)

  (* Exclusive group validation: at most one present argument per group. *)
  fun count_in_group {ls:agz}{lp:agz}{k:nat | k <= ac0} .<ac0 - k>.
    (specs: !$A.arr(int, ls, 1024), present: !$A.arr(int, lp, 64),
     i: int k, gid: int, count: int): int =
    if i >= ac then count
    else if _in_group(specs, i, gid) then
      if $A.get<int>(present, i) > 0 then count_in_group(specs, present, i + 1, gid, count + 1)
      else count_in_group(specs, present, i + 1, gid, count)
    else count_in_group(specs, present, i + 1, gid, count)

  (* The index + 1 of the first group with more than one present, if
     one *)
  fun check_groups {ls:agz}{lp:agz}{g:nat}{k:nat | k <= g} .<g - k>.
    (specs: !$A.arr(int, ls, 1024), present: !$A.arr(int, lp, 64),
     k: int k, gc: int g): $R.option(int) =
    if k >= gc then $R.none()
    else if count_in_group(specs, present, 0, k, 0) > 1 then $R.some(k + 1)
    else check_groups(specs, present, k + 1, gc)
in
  case+ scan_failure of
  | ~$R.some(e) => let
      val () = $R.option_discard<int>(chosen)
      val () = _free_parse_temps(str_buf, str_meta, int_vals, bool_vals, present, tbuf, specs)
    in $R.err(e) end
  | ~$R.none() =>
    (case+ check_ranges(specs, int_vals, present, 0) of
     | ~$R.some(out_of_range) => let
         val () = $R.option_discard<int>(chosen)
         val () = _free_parse_temps(str_buf, str_meta, int_vals, bool_vals, present, tbuf, specs)
       in $R.err(err_range(out_of_range)) end
     | ~$R.none() =>
       (case+ check_groups(specs, present, 0, gc) of
        | ~$R.some(group) => let
            val () = $R.option_discard<int>(chosen)
            val () = _free_parse_temps(str_buf, str_meta, int_vals, bool_vals, present, tbuf, specs)
          in $R.err(err_exclusive(group)) end
        | ~$R.none() =>
          $R.ok(parse_result_mk(str_buf, str_meta, int_vals, bool_vals, present,
            ac, final_sp, chosen, tbuf, specs))))
end

(* ============================================================
   Implementations — Extraction
   ============================================================ *)

implement get_string_len(r, h) = let
  val+ @parse_result_mk(_, smeta, _, _, _, _, _, _, _, _) = r
  val (_ | idx) = h
  val len = $A.get<int>(smeta, idx * 2 + 1)
  prval () = fold@(r)
in len end

implement get_string_copy {l}{n} (r, h, buf, max_len) = let
  val+ @parse_result_mk(sbuf, smeta, _, _, _, _, _, _, _, _) = r
  val (_ | idx) = h
  val off = _u16($A.get<int>(smeta, idx * 2))
  val len = _u16($A.get<int>(smeta, idx * 2 + 1))
  val cl = min(len, max_len)
  fun loop {lb:agz}{ls2:agz}{o:nat}{c:nat | c <= n; o + c <= 8192}{i:nat | i <= c} .<c - i>.
    (dst: !$A.arr(byte, lb, n), src: !$A.arr(byte, ls2, 8192),
     o: int o, c: int c, i: int i): void =
    if i >= c then ()
    else let
      val () = $A.set<byte>(dst, i, $A.get<byte>(src, o + i))
    in loop(dst, src, o, c, i + 1) end
  val copied = (if off + cl <= 8192 then let
      val () = loop(buf, sbuf, off, cl, 0)
    in cl end else 0): int
  prval () = fold@(r)
in copied end

implement get_int(r, h) = let
  val+ @parse_result_mk(_, _, ivals, _, _, _, _, _, _, _) = r
  val (_ | idx) = h
  val v = $A.get<int>(ivals, idx)
  prval () = fold@(r)
in v end

implement get_bool(r, h) = let
  val+ @parse_result_mk(_, _, _, bvals, _, _, _, _, _, _) = r
  val (_ | idx) = h
  val v = $A.get<int>(bvals, idx)
  prval () = fold@(r)
in v > 0 end

implement get_count(r, h) = let
  val+ @parse_result_mk(_, _, _, bvals, _, _, _, _, _, _) = r
  val (_ | idx) = h
  val v = $A.get<int>(bvals, idx)
  prval () = fold@(r)
in v end

implement is_present {a} (r, h) = let
  val+ @parse_result_mk(_, _, _, _, pres, _, _, _, _, _) = r
  val (_ | idx) = h
  val v = $A.get<int>(pres, idx)
  prval () = fold@(r)
in v > 0 end

implement get_subcmd(r) = let
  val+ @parse_result_mk(_, _, _, _, _, _, _, chosen, _, _) = r
  val copy = (case+ chosen of
    | $R.some(index) => $R.some(index)
    | $R.none() => $R.none()): $R.option(int)
  prval () = fold@(r)
in copy end

(* ============================================================
   Implementations — Exclusive groups
   ============================================================ *)

implement add_exclusive_group {tp0}{ac0} (p) = let
  val+ ~parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) = p
in @(parser_mk(specs, tbuf, ac, tp, gc + 1, sc, pno, pnl, pho, phl), gc) end

implement add_to_group {tp0}{ac0}{a} (p, group_id, handle) = let
  val+ ~parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) = p
  val (_ | idx) = handle
  val () = _group_store(specs, idx, group_id)
in parser_mk(specs, tbuf, ac, tp, gc, sc, pno, pnl, pho, phl) end

(* ============================================================
   Implementations — Help formatting
   ============================================================ *)

(* Writes byte b at p if there is room ('?' if b is not a byte). *)
fn _help_put
  {l:agz}{n:pos}{p:nat | p <= n}
  (buf: !$A.arr(byte, l, n), p: int p, b: int, max_len: int n): [r:nat | p <= r; r <= n] int r =
  if p < max_len then let
    val v = (if b >= 0 then if b < 256 then $AR.low_byte(b) else 63 else 63): [v:nat | v < 256] int v
    val () = $A.set<byte>(buf, p, $A.int2byte(v))
  in p + 1 end
  else p

(* Copies tbuf[off, off + len) to buf at p, as much as fits. *)
fn _help_copy
  {l:agz}{n:pos}{lt:agz}{p:nat | p <= n}
  (buf: !$A.arr(byte, l, n), p: int p,
   tbuf: !$A.arr(byte, lt, 8192), off: int, len: int,
   max_len: int n): [r:nat | p <= r; r <= n] int r = let
  val o = _u16(off)
  val c = _u16(len)
  fun loop {o:nat}{c:nat | o + c <= 8192}{i:nat | i <= c}{q:nat | p <= q; q <= n} .<c - i>.
    (buf: !$A.arr(byte, l, n), tbuf: !$A.arr(byte, lt, 8192),
     o: int o, c: int c, i: int i, q: int q): [r:nat | p <= r; r <= n] int r =
    if i >= c then q
    else if q >= max_len then q
    else let
      val () = $A.set<byte>(buf, q, $A.get<byte>(tbuf, o + i))
    in loop(buf, tbuf, o, c, i + 1, q + 1) end
in
  if o + c <= 8192 then loop(buf, tbuf, o, c, 0, p) else p
end

implement format_help {l}{n} (r, buf, max_len) = let
  val+ @parse_result_mk(_, _, _, _, _, ac, _, _, tbuf, specs) = r
  val pos = _help_put(buf, 0, 85, max_len)
  val pos = _help_put(buf, pos, 115, max_len)
  val pos = _help_put(buf, pos, 97, max_len)
  val pos = _help_put(buf, pos, 103, max_len)
  val pos = _help_put(buf, pos, 101, max_len)
  val pos = _help_put(buf, pos, 58, max_len)
  val pos = _help_put(buf, pos, 10, max_len)
  val pos = _help_put(buf, pos, 10, max_len)

  fun fmt_args {ls:agz}{lt:agz}{a:nat | a <= 64}{k:nat | k <= a}{p:nat | p <= n} .<a - k>.
    (buf: !$A.arr(byte, l, n), tbuf: !$A.arr(byte, lt, 8192),
     specs: !$A.arr(int, ls, 1024), pos: int p, i: int k, ac: int a): [r:nat | r <= n] int r =
    if i >= ac then pos
    else let
      val noff = _spec_get(specs, i, 2)
      val nlen = _spec_get(specs, i, 3)
      val hoff = _spec_get(specs, i, 4)
      val hlen = _spec_get(specs, i, 5)
      val pos = _help_put(buf, pos, 32, max_len)
      val pos = _help_put(buf, pos, 32, max_len)
    in
      if ~_is_option(_spec_kind(specs, i)) then let (* positional or subcommand *)
        val pos = _help_copy(buf, pos, tbuf, noff, nlen, max_len)
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_copy(buf, pos, tbuf, hoff, hlen, max_len)
        val pos = _help_put(buf, pos, 10, max_len)
      in fmt_args(buf, tbuf, specs, pos, i + 1, ac) end
      else let
        val pos =
          (case+ _spec_short(specs, i) of
           | ~$R.some(short_char) => let
             val q = _help_put(buf, pos, 45, max_len)
             val q = _help_put(buf, q, short_char, max_len)
             val q = _help_put(buf, q, 44, max_len)
           in _help_put(buf, q, 32, max_len) end
           | ~$R.none() => let
             val q = _help_put(buf, pos, 32, max_len)
             val q = _help_put(buf, q, 32, max_len)
             val q = _help_put(buf, q, 32, max_len)
           in _help_put(buf, q, 32, max_len) end): [q:nat | q <= n] int q
        val pos = _help_put(buf, pos, 45, max_len)
        val pos = _help_put(buf, pos, 45, max_len)
        val pos = _help_copy(buf, pos, tbuf, noff, nlen, max_len)
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_copy(buf, pos, tbuf, hoff, hlen, max_len)
        val pos = _help_put(buf, pos, 10, max_len)
      in fmt_args(buf, tbuf, specs, pos, i + 1, ac) end
    end

  val final_pos = fmt_args(buf, tbuf, specs, pos, 0, ac)
  prval () = fold@(r)
in final_pos end

(* ============================================================
   Implementations — Cleanup
   ============================================================ *)

implement parse_result_free(r) = let
  val+ ~parse_result_mk(sb, sm, iv, bv, pr, _, _, chosen, tb, sp) = r
  val () = $R.option_discard<int>(chosen)
in
  $A.free<byte>(sb); $A.free<int>(sm);
  $A.free<int>(iv); $A.free<int>(bv); $A.free<int>(pr);
  $A.free<byte>(tb); $A.free<int>(sp)
end

implement parse_error_free(e) =
  case+ e of
  | ~err_unknown_long(closest) => $R.option_discard<int>(closest)
  | ~err_unknown_short(_) => ()
  | ~err_range(_) => ()
  | ~err_not_int(_) => ()
  | ~err_exclusive(_) => ()
  | ~err_choice(_) => ()
  | ~err_too_long(_) => ()
