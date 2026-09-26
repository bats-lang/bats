staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "result/src/lib.dats"
staload "env/src/lib.dats"
(* argparse -- type-safe CLI argument parser *)
(* Phantom-typed handles ensure correct value extraction. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload R = "result/src/lib.sats"
staload E = "env/src/lib.sats"

(* ============================================================
   Value type tags (phantom types)
   ============================================================ *)






(* Phantom-typed argument handle *)


(* ============================================================
   Spec constants
   ============================================================ *)

stadef MAX_ARGS = 64
stadef MAX_TEXT = 8192
stadef SPEC_STRIDE = 16

(* ============================================================
   Parser (linear)
   ============================================================ *)











(* ============================================================
   Parse result (linear)
   ============================================================ *)














(* ============================================================
   Parse error (linear)
   ============================================================ *)








(* ============================================================
   API — Construction
   ============================================================ *)

































(* ============================================================
   API — Parsing
   ============================================================ *)






(* ============================================================
   API — Extraction (phantom-typed)
   ============================================================ *)


















(* ============================================================
   API — Cleanup
   ============================================================ *)















(* ============================================================
   Implementation helpers
   ============================================================ *)

fn _text_write
  {lt:agz}{lb:agz}{n:pos}
  (tbuf: !$A.arr(byte, lt, 8192), pos: int,
   src: !$A.borrow(byte, lb, n), len: int n): int = let
  fun loop {ld:agz}{lb:agz}{n:pos}{i:nat | i <= n} .<n - i>.
    (dst: !$A.arr(byte, ld, 8192), src: !$A.borrow(byte, lb, n),
     di: int, si: int i, n: int n): void =
    if si >= n then ()
    else let val di1 = g1ofg0(di) in
      if di1 >= 0 then if di1 < 8192 then let
        val () = $A.set<byte>(dst, di1, $A.read<byte>(src, si))
      in loop(dst, src, di + 1, si + 1, n) end
    end
  val () = loop(tbuf, src, pos, 0, len)
in pos + len end

fn _spec_set {ls:agz}
  (specs: !$A.arr(int, ls, 1024), idx: int, field: int, v: int): void = let
  val off = g1ofg0(idx * 16 + field)
in if off >= 0 then if off < 1024 then $A.set<int>(specs, off, v) end

fn _spec_get {ls:agz}
  (specs: !$A.arr(int, ls, 1024), idx: int, field: int): int = let
  val off = g1ofg0(idx * 16 + field)
in
  if off >= 0 then if off < 1024 then $A.get<int>(specs, off) else 0 else 0
end

(* ============================================================
   Implementations — Construction
   ============================================================ *)

implement parser_new {lp}{np}{lh}{nh} (name, nlen, help, hlen) = let
  val specs = $A.alloc<int>(1024)
  val tbuf = $A.alloc<byte>(8192)
  val subcmds = $A.alloc<int>(64)
  val noff = 0
  val tp = _text_write(tbuf, 0, name, nlen)
  val hoff = tp
  val tp2 = _text_write(tbuf, tp, help, hlen)
in parser_mk(specs, tbuf, subcmds, 0, tp2, 0, 0, 0, noff, nlen, hoff, hlen) end

implement parser_free(p) = let
  val+ ~parser_mk(specs, tbuf, subcmds, _, _, _, _, _, _, _, _, _) = p
in $A.free<int>(specs); $A.free<byte>(tbuf); $A.free<int>(subcmds) end

fn _add_base
  {ln:agz}{nn:pos}{lh:agz}{nh:pos}
  (p: parser, kind: int, vtype: int,
   name: !$A.borrow(byte, ln, nn), nlen: int nn,
   short_ch: int,
   help: !$A.borrow(byte, lh, nh), hlen: int nh,
   def_int: int): @(parser, int) = let
  val+ ~parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) = p
  val idx = ac
  val noff = tp
  val tp2 = _text_write(tbuf, tp, name, nlen)
  val hoff = tp2
  val tp3 = _text_write(tbuf, tp2, help, hlen)
  val () = _spec_set(specs, idx, 0, kind)
  val () = _spec_set(specs, idx, 1, vtype)
  val () = _spec_set(specs, idx, 2, noff)
  val () = _spec_set(specs, idx, 3, nlen)
  val () = _spec_set(specs, idx, 4, hoff)
  val () = _spec_set(specs, idx, 5, hlen)
  val () = _spec_set(specs, idx, 6, short_ch)
  val () = _spec_set(specs, idx, 7, def_int)
  val new_pc = if kind = 0 then pc + 1 else pc
in @(parser_mk(specs, tbuf, subcmds, ac + 1, tp3, new_pc, sc, gc, pno, pnl, pho, phl), idx) end

implement add_string {ln}{nn}{lh}{nh} (p, name, nlen, short_ch, help, hlen, positional) = let
  val kind = if positional then 0 else 1
  val @(p2, idx) = _add_base(p, kind, 0, name, nlen, short_ch, help, hlen, 0)
in @(p2,  $UNSAFE.cast{arg(string_val)}(idx) ) end

implement add_int {ln}{nn}{lh}{nh} (p, name, nlen, short_ch, help, hlen, def, mn, mx) = let
  val @(p2, idx) = _add_base(p, 1, 1, name, nlen, short_ch, help, hlen, def)
  val+ ~parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) = p2
  val () = _spec_set(specs, idx, 10, mn)
  val () = _spec_set(specs, idx, 11, mx)
in @(parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl),
      $UNSAFE.cast{arg(int_val)}(idx) ) end

implement add_flag {ln}{nn}{lh}{nh} (p, name, nlen, short_ch, help, hlen) = let
  val @(p2, idx) = _add_base(p, 2, 2, name, nlen, short_ch, help, hlen, 0)
in @(p2,  $UNSAFE.cast{arg(bool_val)}(idx) ) end

implement add_count {ln}{nn}{lh}{nh} (p, name, nlen, short_ch, help, hlen) = let
  val @(p2, idx) = _add_base(p, 2, 3, name, nlen, short_ch, help, hlen, 0)
in @(p2,  $UNSAFE.cast{arg(count_val)}(idx) ) end

implement add_subcommand {ln}{nn}{lh}{nh} (p, name, nlen, help, hlen) = let
  val+ ~parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) = p
  val si = sc
  val noff = tp
  val tp2 = _text_write(tbuf, tp, name, nlen)
  val hoff = tp2
  val tp3 = _text_write(tbuf, tp2, help, hlen)
  val base = g1ofg0(si * 4)
  val () = if base >= 0 then if base + 3 < 64 then let
    val () = $A.set<int>(subcmds, base, noff)
    val () = $A.set<int>(subcmds, $AR.checked_idx(base + 1, 64), nlen)
    val () = $A.set<int>(subcmds, $AR.checked_idx(base + 2, 64), hoff)
    val () = $A.set<int>(subcmds, $AR.checked_idx(base + 3, 64), hlen)
  in end
in @(parser_mk(specs, tbuf, subcmds, ac, tp3, pc, sc + 1, gc, pno, pnl, pho, phl), si) end

(* ============================================================
   Implementations — Parse
   ============================================================ *)

(* Compare bytes in argv at offset against spec text *)
fun _bytes_eq
  {la:agz}{na:pos}{lt:agz}{fuel:nat} .<fuel>.
  (argv: !$A.borrow(byte, la, na), av_off: int, av_len: int na,
   tbuf: !$A.arr(byte, lt, 8192), tb_off: int, cmp_len: int,
   fuel: int fuel): bool =
  if fuel <= 0 then true
  else if cmp_len <= 0 then true
  else let
    val ai = g1ofg0(av_off)
    val ti = g1ofg0(tb_off)
  in
    if ai >= 0 then
      if ai < av_len then
        if ti >= 0 then
          if ti < 8192 then let
            val ab = byte2int0($A.read<byte>(argv, ai))
            val tb = byte2int0($A.get<byte>(tbuf, ti))
          in
            if $AR.eq_int_int(ab, tb) then
              _bytes_eq(argv, av_off + 1, av_len, tbuf, tb_off + 1, cmp_len - 1, fuel - 1)
            else false
          end
          else false
        else false
      else false
    else false
  end

(* Find arg index matching --name in argv starting at av_off *)
fun _find_by_name
  {la:agz}{na:pos}{ls:agz}{lt:agz}{fuel:nat} .<fuel>.
  (argv: !$A.borrow(byte, la, na), av_off: int, name_len: int, av_len: int na,
   specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192),
   ac: int, i: int, fuel: int fuel): int =
  if fuel <= 0 then ~1
  else if i >= ac then ~1
  else let
    val kind = _spec_get(specs, i, 0)
  in
    if kind > 0 then let
      val snoff = _spec_get(specs, i, 2)
      val snlen = _spec_get(specs, i, 3)
    in
      if $AR.eq_int_int(snlen, name_len) then
        if _bytes_eq(argv, av_off, av_len, tbuf, snoff, name_len, $AR.checked_nat(name_len)) then i
        else _find_by_name(argv, av_off, name_len, av_len, specs, tbuf, ac, i + 1, fuel - 1)
      else _find_by_name(argv, av_off, name_len, av_len, specs, tbuf, ac, i + 1, fuel - 1)
    end
    else _find_by_name(argv, av_off, name_len, av_len, specs, tbuf, ac, i + 1, fuel - 1)
  end

(* Find arg index matching short flag -c *)
fun _find_by_short
  {ls:agz}{fuel:nat} .<fuel>.
  (specs: !$A.arr(int, ls, 1024), ch: int, ac: int, i: int, fuel: int fuel): int =
  if fuel <= 0 then ~1
  else if i >= ac then ~1
  else let
    val kind = _spec_get(specs, i, 0)
    val sc = _spec_get(specs, i, 6)
  in
    if kind > 0 then
      if $AR.eq_int_int(sc, ch) then i
      else _find_by_short(specs, ch, ac, i + 1, fuel - 1)
    else _find_by_short(specs, ch, ac, i + 1, fuel - 1)
  end

(* Parse int from bytes. Returns (value, success). *)
fun _parse_int
  {la:agz}{na:pos}{fuel:nat} .<fuel>.
  (argv: !$A.borrow(byte, la, na), off: int, len: int, av_len: int na,
   fuel: int fuel): @(int, bool) = let
  fun digit_loop
    {la:agz}{na:pos}{fuel:nat} .<fuel>.
    (argv: !$A.borrow(byte, la, na), off: int, len: int, av_len: int na,
     acc: int, i: int, fuel: int fuel): @(int, bool) =
    if fuel <= 0 then @(acc, true)
    else if i >= len then @(acc, true)
    else let
      val p = g1ofg0(off + i)
    in
      if p >= 0 then
        if p < av_len then let
          val b = byte2int0($A.read<byte>(argv, p))
        in
          if b >= 48 then
            if b <= 57 then
              digit_loop(argv, off, len, av_len, acc * 10 + (b - 48), i + 1, fuel - 1)
            else @(0, false)
          else @(0, false)
        end
        else @(0, false)
      else @(0, false)
    end
in
  if len <= 0 then @(0, false)
  else let
    val p0 = g1ofg0(off)
  in
    if p0 >= 0 then
      if p0 < av_len then let
        val first = byte2int0($A.read<byte>(argv, p0))
      in
        if $AR.eq_int_int(first, 45) then let
          val @(v, ok) = digit_loop(argv, off + 1, len - 1, av_len, 0, 0, $AR.checked_nat(len))
        in @(0 - v, ok) end
        else digit_loop(argv, off, len, av_len, 0, 0, $AR.checked_nat(len))
      end
      else @(0, false)
    else @(0, false)
  end
end

(* Store string value: copy from argv to result string buffer *)
fn _store_str
  {la:agz}{na:pos}{ls:agz}{lm:agz}
  (argv: !$A.borrow(byte, la, na), av_off: int, val_len: int, av_len: int na,
   str_buf: !$A.arr(byte, ls, 8192), str_meta: !$A.arr(int, lm, 128),
   idx: int, str_pos: int): int = let
  fun copy {la:agz}{na:pos}{ls:agz}{fuel:nat} .<fuel>.
    (src: !$A.borrow(byte, la, na), dst: !$A.arr(byte, ls, 8192),
     si: int, di: int, count: int, av_len: int na, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if count <= 0 then ()
    else let
      val si1 = g1ofg0(si)
      val di1 = g1ofg0(di)
    in
      if si1 >= 0 then
        if si1 < av_len then
          if di1 >= 0 then
            if di1 < 8192 then let
              val () = $A.set<byte>(dst, di1, $A.read<byte>(src, si1))
            in copy(src, dst, si + 1, di + 1, count - 1, av_len, fuel - 1) end
            else ()
          else ()
        else ()
      else ()
    end
  val () = copy(argv, str_buf, av_off, str_pos, val_len, av_len, $AR.checked_nat(val_len))
  val mi = g1ofg0(idx * 2)
  val () = if mi >= 0 then
    if mi < 128 then $A.set<int>(str_meta, mi, str_pos) else ()
  else ()
  val mi2 = g1ofg0(idx * 2 + 1)
  val () = if mi2 >= 0 then
    if mi2 < 128 then $A.set<int>(str_meta, mi2, val_len) else ()
  else ()
in str_pos + val_len end

(* Find end of a null-terminated token in argv *)
fun _find_tok_end
  {la:agz}{na:pos}{f:nat} .<f>.
  (argv: !$A.borrow(byte, la, na), pos: int, av_len: int na, f: int f): int =
  if f <= 0 then pos
  else if pos >= av_len then pos
  else let
    val p1 = g1ofg0(pos)
  in
    if p1 >= 0 then
      if p1 < av_len then
        if $AR.eq_int_int(byte2int0($A.read<byte>(argv, p1)), 0) then pos
        else _find_tok_end(argv, pos + 1, av_len, f - 1)
      else pos
    else pos
  end

(* Find the nth positional arg spec *)
fun _find_pos_spec
  {ls:agz}{f:nat} .<f>.
  (specs: !$A.arr(int, ls, 1024), ac: int, i: int, pi: int, f: int f): int =
  if f <= 0 then ~1
  else if i >= ac then ~1
  else let
    val kind = _spec_get(specs, i, 0)
  in
    if $AR.eq_int_int(kind, 0) then
      if $AR.eq_int_int(pi, 0) then i
      else _find_pos_spec(specs, ac, i + 1, pi - 1, f - 1)
    else _find_pos_spec(specs, ac, i + 1, pi, f - 1)
  end

(* Mark an arg present in the present array *)
fn _mark_present
  {lp:agz}
  (present: !$A.arr(int, lp, 64), idx: int): void = let
  val pi = g1ofg0(idx)
in
  if pi >= 0 then
    if pi < 64 then $A.set<int>(present, pi, 1)
    else ()
  else ()
end

(* Increment a bool/count value *)
fn _inc_bool
  {lb:agz}
  (bool_vals: !$A.arr(int, lb, 64), idx: int): void = let
  val pi = g1ofg0(idx)
in
  if pi >= 0 then
    if pi < 64 then let
      val cur = $A.get<int>(bool_vals, pi)
    in
      $A.set<int>(bool_vals, pi, cur + 1)
    end
    else ()
  else ()
end

(* Store an int value *)
fn _set_int_val
  {li:agz}
  (int_vals: !$A.arr(int, li, 64), idx: int, v: int): void = let
  val pi = g1ofg0(idx)
in
  if pi >= 0 then
    if pi < 64 then $A.set<int>(int_vals, pi, v)
    else ()
  else ()
end

(* Handle a flag/count option: increment bool_vals, advance one token *)
(* Returns @(pos_idx, str_pos, next_av_pos, next_tok_num, subcmd_idx) *)
fn _handle_flag
  {lb:agz}{lp:agz}
  (bool_vals: !$A.arr(int, lb, 64),
   present: !$A.arr(int, lp, 64),
   idx: int,
   pos_idx: int, str_pos: int, next_pos: int, tok_num: int, subcmd_idx: int
  ): @(int, int, int, int, int) = let
  val () = _mark_present(present, idx)
  val () = _inc_bool(bool_vals, idx)
in
  @(pos_idx, str_pos, next_pos, tok_num + 1, subcmd_idx)
end

(* Handle a value option (int or string): consume next token as value *)
(* Returns @(pos_idx, str_pos, next_av_pos, next_tok_num, subcmd_idx) *)
fn _handle_value_opt
  {la:agz}{na:pos}{ls:agz}{lm:agz}{li:agz}{lb:agz}{lp:agz}
  (argv: !$A.borrow(byte, la, na), av_len: int na,
   str_buf: !$A.arr(byte, ls, 8192), str_meta: !$A.arr(int, lm, 128),
   int_vals: !$A.arr(int, li, 64),
   present: !$A.arr(int, lp, 64),
   idx: int, vtype: int,
   pos_idx: int, str_pos: int, next_pos: int, tok_num: int, subcmd_idx: int
  ): @(int, int, int, int, int) = let
  val () = _mark_present(present, idx)
  val val_start = next_pos
  val val_end = _find_tok_end(argv, val_start, av_len, av_len)
  val val_len = val_end - val_start
  val next2 = val_end + 1
in
  if $AR.eq_int_int(vtype, 1) then let
    val vl = $AR.checked_nat(if val_len > 0 then val_len else 0)
    val @(iv, _) = _parse_int(argv, val_start, val_len, av_len, vl)
    val () = _set_int_val(int_vals, idx, iv)
  in
    @(pos_idx, str_pos, next2, tok_num + 2, subcmd_idx)
  end
  else let
    val vl2 = $AR.checked_nat(if val_len > 0 then val_len else 0)
    val sp2 = _store_str(argv, val_start, val_len, av_len, str_buf, str_meta, idx, str_pos)
  in
    @(pos_idx, sp2, next2, tok_num + 2, subcmd_idx)
  end
end

(* Handle a known option (long or short) given its spec index *)
(* Returns @(pos_idx, str_pos, next_av_pos, next_tok_num, subcmd_idx) *)
fn _handle_known_opt
  {la:agz}{na:pos}{ls:agz}{lt:agz}{lm:agz}{li:agz}{lb:agz}{lp:agz}{ls2:agz}
  (argv: !$A.borrow(byte, la, na), av_len: int na,
   specs: !$A.arr(int, ls, 1024),
   str_buf: !$A.arr(byte, ls2, 8192), str_meta: !$A.arr(int, lm, 128),
   int_vals: !$A.arr(int, li, 64), bool_vals: !$A.arr(int, lb, 64),
   present: !$A.arr(int, lp, 64),
   idx: int,
   pos_idx: int, str_pos: int, next_pos: int, tok_num: int, subcmd_idx: int
  ): @(int, int, int, int, int) = let
  val kind = _spec_get(specs, idx, 0)
  val vtype = _spec_get(specs, idx, 1)
in
  if $AR.eq_int_int(kind, 2) then
    _handle_flag(bool_vals, present, idx, pos_idx, str_pos, next_pos, tok_num, subcmd_idx)
  else let
    val () = _mark_present(present, idx)
    val val_start = next_pos
    val val_end = _find_tok_end(argv, val_start, av_len, av_len)
    val val_len = val_end - val_start
    val next2 = val_end + 1
  in
    if $AR.eq_int_int(vtype, 1) then let
      val vl = $AR.checked_nat(if val_len > 0 then val_len else 0)
      val @(iv, _) = _parse_int(argv, val_start, val_len, av_len, vl)
      val () = _set_int_val(int_vals, idx, iv)
    in @(pos_idx, str_pos, next2, tok_num + 2, subcmd_idx) end
    else let
      val sp2 = _store_str(argv, val_start, val_len, av_len, str_buf, str_meta, idx, str_pos)
    in @(pos_idx, sp2, next2, tok_num + 2, subcmd_idx) end
  end
end

(* Handle a positional token *)
fn _handle_positional
  {la:agz}{na:pos}{ls:agz}{lt:agz}{lm:agz}{lp:agz}{lsb:agz}
  (argv: !$A.borrow(byte, la, na), av_len: int na,
   specs: !$A.arr(int, ls, 1024),
   str_buf: !$A.arr(byte, lsb, 8192), str_meta: !$A.arr(int, lm, 128),
   present: !$A.arr(int, lp, 64),
   ac: int, tok_start: int, tok_len: int,
   pos_idx: int, str_pos: int, next_pos: int, tok_num: int, subcmd_idx: int
  ): @(int, int, int, int, int) = let
  val pidx = _find_pos_spec(specs, ac, 0, pos_idx, $AR.checked_nat(ac))
in
  if pidx >= 0 then let
    val () = _mark_present(present, pidx)
    val sp2 = _store_str(argv, tok_start, tok_len, av_len, str_buf, str_meta, pidx, str_pos)
  in
    @(pos_idx + 1, sp2, next_pos, tok_num + 1, subcmd_idx)
  end
  else
    @(pos_idx, str_pos, next_pos, tok_num + 1, tok_num)
end

(* Classify a token: 0=skip, 1=long option, 2=short option, 3=positional *)
fn _classify_token
  {la:agz}{na:pos}
  (argv: !$A.borrow(byte, la, na), av_len: int na,
   tok_start: int, tok_len: int): int = let
  val t0 = g1ofg0(tok_start)
in
  if t0 < 0 then 0
  else if t0 >= av_len then 0
  else let
    val b0 = byte2int0($A.read<byte>(argv, t0))
  in
    if $AR.eq_int_int(b0, 45) then let
      val t1 = g1ofg0(tok_start + 1)
    in
      if t1 >= 0 then
        if t1 < av_len then let
          val b1 = byte2int0($A.read<byte>(argv, t1))
        in
          if $AR.eq_int_int(b1, 45) then 1
          else 2
        end
        else 0
      else 0
    end
    else 3
  end
end

(* Get the short char byte at tok_start+1 *)
fn _get_short_char
  {la:agz}{na:pos}
  (argv: !$A.borrow(byte, la, na), av_len: int na, tok_start: int): int = let
  val t1 = g1ofg0(tok_start + 1)
in
  if t1 >= 0 then
    if t1 < av_len then byte2int0($A.read<byte>(argv, t1))
    else 0
  else 0
end

(* Simple edit distance between two byte sequences in different buffers.
   Used for "did you mean?" suggestions. O(n*m) but names are short. *)
fun _edit_dist
  {la:agz}{na:pos}{lt:agz}{fuel:nat} .<fuel>.
  (argv: !$A.borrow(byte, la, na), a_off: int, a_len: int, av_len: int na,
   tbuf: !$A.arr(byte, lt, 8192), b_off: int, b_len: int,
   fuel: int fuel): int =
  if fuel <= 0 then 999
  else if a_len <= 0 then b_len
  else if b_len <= 0 then a_len
  else let
    val ai = g1ofg0(a_off)
    val bi = g1ofg0(b_off)
  in
    if ai >= 0 then if ai < av_len then
      if bi >= 0 then if bi < 8192 then let
        val ac = byte2int0($A.read<byte>(argv, ai))
        val bc = byte2int0($A.get<byte>(tbuf, bi))
        val cost = if $AR.eq_int_int(ac, bc) then 0 else 1
        val d1 = $AR.add_int_int(_edit_dist(argv, a_off + 1, a_len - 1, av_len, tbuf, b_off, b_len, fuel - 1), 1)
        val d2 = $AR.add_int_int(_edit_dist(argv, a_off, a_len, av_len, tbuf, b_off + 1, b_len - 1, fuel - 1), 1)
        val d3 = $AR.add_int_int(_edit_dist(argv, a_off + 1, a_len - 1, av_len, tbuf, b_off + 1, b_len - 1, fuel - 1), cost)
        val mn = if $AR.lt_int_int(d1, d2) then d1 else d2
      in if $AR.lt_int_int(d3, mn) then d3 else mn end
      else 999 else 999
    else 999 else 999
  end

(* Find the closest matching option name, return its index or -1 *)
fun _find_closest
  {la:agz}{na:pos}{ls:agz}{lt:agz}{fuel:nat} .<fuel>.
  (argv: !$A.borrow(byte, la, na), name_off: int, name_len: int, av_len: int na,
   specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192),
   ac: int, i: int, best_idx: int, best_dist: int, fuel: int fuel): int =
  if fuel <= 0 then best_idx
  else if i >= ac then best_idx
  else let
    val kind = _spec_get(specs, i, 0)
  in
    if kind > 0 then let
      val snoff = _spec_get(specs, i, 2)
      val snlen = _spec_get(specs, i, 3)
      val d = _edit_dist(argv, name_off, name_len, av_len, tbuf, snoff, snlen,
        $AR.checked_nat((name_len + snlen) * 3))
    in
      if $AR.lt_int_int(d, best_dist) then
        _find_closest(argv, name_off, name_len, av_len, specs, tbuf, ac, i + 1, i, d, fuel - 1)
      else
        _find_closest(argv, name_off, name_len, av_len, specs, tbuf, ac, i + 1, best_idx, best_dist, fuel - 1)
    end
    else _find_closest(argv, name_off, name_len, av_len, specs, tbuf, ac, i + 1, best_idx, best_dist, fuel - 1)
  end

implement parse {la}{na} (p, argv, argv_len, argc) = let
  val+ ~parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) = p
  val str_buf = $A.alloc<byte>(8192)
  val str_meta = $A.alloc<int>(128)
  val int_vals = $A.alloc<int>(64)
  val bool_vals = $A.alloc<int>(64)
  val present = $A.alloc<int>(64)

  (* Initialize defaults *)
  fun init_defs {ls:agz}{li:agz}{lb:agz}{k:nat | k <= 64} .<64 - k>.
    (specs: !$A.arr(int, ls, 1024), ivals: !$A.arr(int, li, 64),
     bvals: !$A.arr(int, lb, 64), i: int k, n: int): void =
    if i >= n then ()
    else if i >= 64 then ()
    else let
      val () = $A.set<int>(ivals, i, _spec_get(specs, i, 7))
      val () = $A.set<int>(bvals, i, 0)
    in init_defs(specs, ivals, bvals, i + 1, n) end
  val () = init_defs(specs, int_vals, bool_vals, 0, ac)

  (* Main scan loop: flat control flow.
     For each token, classify it and dispatch to the appropriate handler. *)
  fun scan_argv
    {la:agz}{na:pos}{ls:agz}{lt:agz}{li:agz}{lb:agz}{lp:agz}{lm:agz}{lsb:agz}{fuel:nat} .<fuel>.
    (argv: !$A.borrow(byte, la, na), av_len: int na,
     specs: !$A.arr(int, ls, 1024), tbuf: !$A.arr(byte, lt, 8192),
     str_buf: !$A.arr(byte, lsb, 8192), str_meta: !$A.arr(int, lm, 128),
     int_vals: !$A.arr(int, li, 64), bool_vals: !$A.arr(int, lb, 64),
     present: !$A.arr(int, lp, 64),
     ac: int, pos_idx: int, str_pos: int,
     av_pos: int, tok_num: int, argc: int, subcmd_idx: int,
     fuel: int fuel): @(int, int, int) =
    if fuel <= 0 then @(str_pos, subcmd_idx, 0)
    else if tok_num >= argc then @(str_pos, subcmd_idx, 0)
    else let
      val tok_start = av_pos
      val tok_end = _find_tok_end(argv, tok_start, av_len, av_len)
      val tok_len = tok_end - tok_start
      val next_pos = tok_end + 1
    in
      if tok_len <= 0 then
        scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
          ac, pos_idx, str_pos, next_pos, tok_num + 1, argc, subcmd_idx, fuel - 1)
      else let
        val cls = _classify_token(argv, av_len, tok_start, tok_len)
      in
        if $AR.eq_int_int(cls, 1) then let (* long option *)
          val name_off = tok_start + 2
          val name_len = tok_len - 2
          val idx = _find_by_name(argv, name_off, name_len, av_len, specs, tbuf, ac, 0, $AR.checked_nat(ac))
        in
          if idx >= 0 then let
            val kind = _spec_get(specs, idx, 0)
            val vtype = _spec_get(specs, idx, 1)
            val () = _mark_present(present, idx)
          in
            if $AR.eq_int_int(kind, 2) then let
              val () = _inc_bool(bool_vals, idx)
            in
              scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                ac, pos_idx, str_pos, next_pos, tok_num + 1, argc, subcmd_idx, fuel - 1)
            end
            else let
              val vs = next_pos
              val ve = _find_tok_end(argv, vs, av_len, av_len)
              val vl = ve - vs
              val np2 = ve + 1
            in
              if $AR.eq_int_int(vtype, 1) then let
                val @(iv, _) = _parse_int(argv, vs, vl, av_len, $AR.checked_nat(if vl > 0 then vl else 0))
                val () = _set_int_val(int_vals, idx, iv)
              in
                scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                  ac, pos_idx, str_pos, np2, tok_num + 2, argc, subcmd_idx, fuel - 1)
              end
              else let
                val sp2 = _store_str(argv, vs, vl, av_len, str_buf, str_meta, idx, str_pos)
              in
                scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                  ac, pos_idx, sp2, np2, tok_num + 2, argc, subcmd_idx, fuel - 1)
              end
            end
          end
          else let
            (* Unknown long option — find closest match for "did you mean?" *)
            val closest = _find_closest(argv, name_off, name_len, av_len,
              specs, tbuf, ac, 0, ~1, 999, $AR.checked_nat(ac))
          in
            if closest >= 0 then @(str_pos, subcmd_idx, 3000 + closest)
            else @(str_pos, subcmd_idx, 3000)
          end
        end
        else if $AR.eq_int_int(cls, 2) then let (* short option *)
          val ch = _get_short_char(argv, av_len, tok_start)
          val idx = _find_by_short(specs, ch, ac, 0, $AR.checked_nat(ac))
        in
          if idx >= 0 then let
            val kind = _spec_get(specs, idx, 0)
            val vtype = _spec_get(specs, idx, 1)
            val () = _mark_present(present, idx)
          in
            if $AR.eq_int_int(kind, 2) then let
              val () = _inc_bool(bool_vals, idx)
            in
              scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                ac, pos_idx, str_pos, next_pos, tok_num + 1, argc, subcmd_idx, fuel - 1)
            end
            else let
              val vs = next_pos
              val ve = _find_tok_end(argv, vs, av_len, av_len)
              val vl = ve - vs
              val np2 = ve + 1
            in
              if $AR.eq_int_int(vtype, 1) then let
                val @(iv, _) = _parse_int(argv, vs, vl, av_len, $AR.checked_nat(if vl > 0 then vl else 0))
                val () = _set_int_val(int_vals, idx, iv)
              in
                scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                  ac, pos_idx, str_pos, np2, tok_num + 2, argc, subcmd_idx, fuel - 1)
              end
              else let
                val sp2 = _store_str(argv, vs, vl, av_len, str_buf, str_meta, idx, str_pos)
              in
                scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
                  ac, pos_idx, sp2, np2, tok_num + 2, argc, subcmd_idx, fuel - 1)
              end
            end
          end
          else (* unknown short option *)
            @(str_pos, subcmd_idx, 4000 + ch)
        end
        else if $AR.eq_int_int(cls, 3) then let (* positional *)
          val pidx = _find_pos_spec(specs, ac, 0, pos_idx, $AR.checked_nat(ac))
        in
          if pidx >= 0 then let
            val () = _mark_present(present, pidx)
            val sp2 = _store_str(argv, tok_start, tok_len, av_len, str_buf, str_meta, pidx, str_pos)
          in
            scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
              ac, pos_idx + 1, sp2, next_pos, tok_num + 1, argc, subcmd_idx, fuel - 1)
          end
          else
            scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
              ac, pos_idx, str_pos, next_pos, tok_num + 1, argc, tok_num, fuel - 1)
        end
        else (* cls=0: skip *)
          scan_argv(argv, av_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
            ac, pos_idx, str_pos, next_pos, tok_num + 1, argc, subcmd_idx, fuel - 1)
      end
    end

  (* Skip first token (program name) *)
  val first_end = _find_tok_end(argv, 0, argv_len, argv_len)
  val start_pos = first_end + 1

  val @(final_sp, final_subcmd, err) =
    scan_argv(argv, argv_len, specs, tbuf, str_buf, str_meta, int_vals, bool_vals, present,
      ac, 0, 0, start_pos, 1, argc, ~1, $AR.checked_nat(argc * 2))

  (* Check for scan errors (unknown options with suggestions) *)
  val scan_err = err

  (* Post-parse validation *)

  (* Int range validation: for each int arg with min != max, check bounds *)
  fun check_ranges {ls:agz}{li:agz}{lp:agz}{k:nat | k <= 64} .<64 - k>.
    (specs: !$A.arr(int, ls, 1024), int_vals: !$A.arr(int, li, 64),
     present: !$A.arr(int, lp, 64), i: int k, ac: int): int =
    if i >= ac then 0
    else if i >= 64 then 0
    else let
      val vtype = _spec_get(specs, i, 1)
      val pi = g1ofg0(i)
    in
      if $AR.eq_int_int(vtype, 1) then let
        val mn = _spec_get(specs, i, 10)
        val mx = _spec_get(specs, i, 11)
      in
        if $AR.eq_int_int(mn, 0) then
          if $AR.eq_int_int(mx, 0) then check_ranges(specs, int_vals, present, i + 1, ac)
          else let
            val pv = if pi >= 0 then if pi < 64 then $A.get<int>(present, pi) else 0 else 0
          in
            if $AR.gt_int_int(pv, 0) then let
              val v = if pi >= 0 then if pi < 64 then $A.get<int>(int_vals, pi) else 0 else 0
            in
              if $AR.lt_int_int(v, mn) then i + 1
              else if $AR.gt_int_int(v, mx) then i + 1
              else check_ranges(specs, int_vals, present, i + 1, ac)
            end
            else check_ranges(specs, int_vals, present, i + 1, ac)
          end
        else check_ranges(specs, int_vals, present, i + 1, ac)
      end
      else check_ranges(specs, int_vals, present, i + 1, ac)
    end

  val range_err = check_ranges(specs, int_vals, present, 0, ac)

  (* Exclusive group validation: for each group, count how many args are present *)
  fun check_exclusive {ls:agz}{lp:agz}{k:nat | k <= 64} .<64 - k>.
    (specs: !$A.arr(int, ls, 1024), present: !$A.arr(int, lp, 64),
     i: int k, ac: int, gid: int, count: int): int =
    if i >= ac then count
    else if i >= 64 then count
    else let
      val g = _spec_get(specs, i, 15)
      val pi = g1ofg0(i)
      val pv = if pi >= 0 then if pi < 64 then $A.get<int>(present, pi) else 0 else 0
      val nc = if $AR.eq_int_int(g, gid) then
        if $AR.gt_int_int(pv, 0) then count + 1 else count
      else count
    in check_exclusive(specs, present, i + 1, ac, gid, nc) end

  (* Check all groups — for now just group 0..gc-1 *)
  fun check_all_groups {ls:agz}{lp:agz}{k:nat | k <= 8} .<8 - k>.
    (specs: !$A.arr(int, ls, 1024), present: !$A.arr(int, lp, 64),
     g: int k, gc: int, ac: int): int =
    if g >= gc then 0
    else if g >= 8 then 0
    else let
      val cnt = check_exclusive(specs, present, 0, ac, g, 0)
    in
      if cnt > 1 then g + 1
      else check_all_groups(specs, present, g + 1, gc, ac)
    end

  val group_err = check_all_groups(specs, present, 0, gc, ac)

  (* Choice validation: for string args with choices, verify value matches *)
  fun _check_str_match
    {ls:agz}{lt:agz}{fuel:nat} .<fuel>.
    (str_buf: !$A.arr(byte, ls, 8192), s_off: int, s_len: int,
     tbuf: !$A.arr(byte, lt, 8192), c_off: int, c_len: int,
     fuel: int fuel): bool =
    if fuel <= 0 then true
    else if s_len <= 0 then true
    else if c_len <= 0 then true
    else let
      val si = g1ofg0(s_off)
      val ci = g1ofg0(c_off)
    in
      if si >= 0 then if si < 8192 then
        if ci >= 0 then if ci < 8192 then let
          val sb = byte2int0($A.get<byte>(str_buf, si))
          val cb = byte2int0($A.get<byte>(tbuf, ci))
        in
          if $AR.eq_int_int(sb, cb) then
            _check_str_match(str_buf, s_off + 1, s_len - 1, tbuf, c_off + 1, c_len - 1, fuel - 1)
          else false
        end else false else false
      else false else false
    end

  (* Check one string value against null-separated choices *)
  fun _check_one_choice
    {ls:agz}{lt:agz}{fuel:nat} .<fuel>.
    (str_buf: !$A.arr(byte, ls, 8192), s_off: int, s_len: int,
     tbuf: !$A.arr(byte, lt, 8192), c_off: int, c_total_len: int,
     choice_count: int, ci: int, fuel: int fuel): bool =
    if fuel <= 0 then false
    else if ci >= choice_count then false
    else let
      (* Find end of current choice (next null byte in tbuf) *)
      fun _find_choice_end {lt:agz}{f:nat} .<f>.
        (tbuf: !$A.arr(byte, lt, 8192), pos: int, limit: int, f: int f): int =
        if f <= 0 then pos
        else if pos >= limit then pos
        else let val p1 = g1ofg0(pos) in
          if p1 >= 0 then if p1 < 8192 then
            if $AR.eq_int_int(byte2int0($A.get<byte>(tbuf, p1)), 0) then pos
            else _find_choice_end(tbuf, pos + 1, limit, f - 1)
          else pos else pos
        end
      val ce = _find_choice_end(tbuf, c_off, c_off + c_total_len, $AR.checked_nat(c_total_len))
      val clen = ce - c_off
    in
      if $AR.eq_int_int(clen, s_len) then
        if _check_str_match(str_buf, s_off, s_len, tbuf, c_off, clen, $AR.checked_nat(clen)) then true
        else _check_one_choice(str_buf, s_off, s_len, tbuf, ce + 1, c_total_len - clen - 1, choice_count, ci + 1, fuel - 1)
      else _check_one_choice(str_buf, s_off, s_len, tbuf, ce + 1, c_total_len - clen - 1, choice_count, ci + 1, fuel - 1)
    end

  fun check_choices
    {ls:agz}{lt:agz}{lm:agz}{lp:agz}{lsp:agz}{k:nat | k <= 64} .<64 - k>.
    (specs: !$A.arr(int, lsp, 1024), str_buf: !$A.arr(byte, ls, 8192),
     str_meta: !$A.arr(int, lm, 128), tbuf: !$A.arr(byte, lt, 8192),
     present: !$A.arr(int, lp, 64), i: int k, ac: int): int =
    if i >= ac then 0
    else if i >= 64 then 0
    else let
      val vtype = _spec_get(specs, i, 1)
      val cc = _spec_get(specs, i, 14)
    in
      if $AR.eq_int_int(vtype, 0) then (* string type *)
        if $AR.gt_int_int(cc, 0) then let (* has choices *)
          val pi = g1ofg0(i)
          val pv = if pi >= 0 then if pi < 64 then $A.get<int>(present, pi) else 0 else 0
        in
          if $AR.gt_int_int(pv, 0) then let
            val mi = g1ofg0(i * 2)
            val s_off = if mi >= 0 then if mi < 128 then $A.get<int>(str_meta, mi) else 0 else 0
            val mi2 = g1ofg0(i * 2 + 1)
            val s_len = if mi2 >= 0 then if mi2 < 128 then $A.get<int>(str_meta, mi2) else 0 else 0
            val c_off = _spec_get(specs, i, 12)
            val c_len = _spec_get(specs, i, 13)
            val ok = _check_one_choice(str_buf, s_off, s_len, tbuf, c_off, c_len, cc, 0, $AR.checked_nat(cc))
          in
            if ok then check_choices(specs, str_buf, str_meta, tbuf, present, i + 1, ac)
            else i + 1
          end
          else check_choices(specs, str_buf, str_meta, tbuf, present, i + 1, ac)
        end
        else check_choices(specs, str_buf, str_meta, tbuf, present, i + 1, ac)
      else check_choices(specs, str_buf, str_meta, tbuf, present, i + 1, ac)
    end

  val choice_err = check_choices(specs, str_buf, str_meta, tbuf, present, 0, ac)

  (* Env var fallback: for unset string options with env var, try getenv *)
  fun check_env_fallback
    {ls:agz}{lt:agz}{lm:agz}{lp:agz}{lsp:agz}{k:nat | k <= 64} .<64 - k>.
    (specs: !$A.arr(int, lsp, 1024), str_buf: !$A.arr(byte, ls, 8192),
     str_meta: !$A.arr(int, lm, 128), tbuf: !$A.arr(byte, lt, 8192),
     present: !$A.arr(int, lp, 64), i: int k, ac: int, str_pos: int): int =
    if i >= ac then str_pos
    else if i >= 64 then str_pos
    else let
      val kind = _spec_get(specs, i, 0)
      val vtype = _spec_get(specs, i, 1)
      val pi = g1ofg0(i)
      val pv = if pi >= 0 then if pi < 64 then $A.get<int>(present, pi) else 1 else 1
    in
      if $AR.eq_int_int(kind, 1) then (* option *)
        if $AR.eq_int_int(vtype, 0) then (* string *)
          if $AR.eq_int_int(pv, 0) then let (* not set *)
            val e_off = _spec_get(specs, i, 12)
            val e_len = _spec_get(specs, i, 13)
            val cc = _spec_get(specs, i, 14)
          in
            if $AR.gt_int_int(e_len, 0) then
              if $AR.eq_int_int(cc, 0) then let
                (* This has env var, not choices — use env package *)
                (* Copy env var name from tbuf to a temp borrow-able array *)
                (* Build null-terminated env var name array *)
                val env_name = $A.alloc<byte>(256)
                fun _copy_ename {lt:agz}{le:agz}{fuel:nat} .<fuel>.
                  (tbuf: !$A.arr(byte, lt, 8192), ebuf: !$A.arr(byte, le, 256),
                   si: int, di: int, len: int, fuel: int fuel): void =
                  if fuel <= 0 then ()
                  else if len <= 0 then ()
                  else let val s = g1ofg0(si) val d = g1ofg0(di) in
                    if s >= 0 then if s < 8192 then
                      if d >= 0 then if d < 256 then let
                        val () = $A.set<byte>(ebuf, d, $A.get<byte>(tbuf, s))
                      in _copy_ename(tbuf, ebuf, si + 1, di + 1, len - 1, fuel - 1) end
                      else () else ()
                    else () else ()
                  end
                val elen2 = if e_len > 255 then 255 else e_len
                val () = _copy_ename(tbuf, env_name, e_off, 0, elen2, $AR.checked_nat(elen2))
                (* Add null terminator *)
                val () = let val nd = $AR.checked_idx(elen2, 256) in
                  $A.set<byte>(env_name, nd, $A.int2byte($AR.checked_byte(0)))
                end
                (* Call env.get_cstr *)
                val env_val = $A.alloc<byte>(4096)
                val env_result = $E.get_cstr(env_name, env_val, 4096)
                val () = $A.free<byte>(env_name)
              in
                case+ env_result of
                | ~$R.some(env_len) => let
                    (* Copy env_val to str_buf at str_pos *)
                    fun copy_val {ls:agz}{le:agz}{fuel:nat} .<fuel>.
                      (dst: !$A.arr(byte, ls, 8192), src: !$A.arr(byte, le, 4096),
                       di: int, si: int, len: int, fuel: int fuel): void =
                      if fuel <= 0 then ()
                      else if len <= 0 then ()
                      else let val d = g1ofg0(di) val s = g1ofg0(si) in
                        if d >= 0 then if d < 8192 then
                          if s >= 0 then if s < 4096 then let
                            val () = $A.set<byte>(dst, d, $A.get<byte>(src, s))
                          in copy_val(dst, src, di + 1, si + 1, len - 1, fuel - 1) end
                          else () else ()
                        else () else ()
                      end
                    val () = copy_val(str_buf, env_val, str_pos, 0, env_len, $AR.checked_nat(env_len))
                    val () = $A.free<byte>(env_val)
                    val mi = g1ofg0(i * 2)
                    val () = if mi >= 0 then if mi < 128 then $A.set<int>(str_meta, mi, str_pos) else () else ()
                    val mi2 = g1ofg0(i * 2 + 1)
                    val () = if mi2 >= 0 then if mi2 < 128 then $A.set<int>(str_meta, mi2, env_len) else () else ()
                    val () = if pi >= 0 then if pi < 64 then $A.set<int>(present, pi, 1) else () else ()
                  in check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos + env_len) end
                | ~$R.none() => let
                    val () = $A.free<byte>(env_val)
                  in check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos) end
              end
              else check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos)
            else check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos)
          end
          else check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos)
        else check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos)
      else check_env_fallback(specs, str_buf, str_meta, tbuf, present, i + 1, ac, str_pos)
    end

  val final_sp2 = check_env_fallback(specs, str_buf, str_meta, tbuf, present, 0, ac, final_sp)

  val () = $A.free<int>(subcmds)
in
  if $AR.gt_int_int(scan_err, 0) then let
    val () = $A.free<byte>(str_buf)
    val () = $A.free<int>(str_meta)
    val () = $A.free<int>(int_vals)
    val () = $A.free<int>(bool_vals)
    val () = $A.free<int>(present)
    val () = $A.free<byte>(tbuf)
    val () = $A.free<int>(specs)
  in
    if scan_err >= 4000 then $R.err(err_unknown_short(scan_err - 4000))
    else $R.err(err_unknown_long(scan_err - 3000))
  end
  else if $AR.gt_int_int(range_err, 0) then let
    val () = $A.free<byte>(str_buf)
    val () = $A.free<int>(str_meta)
    val () = $A.free<int>(int_vals)
    val () = $A.free<int>(bool_vals)
    val () = $A.free<int>(present)
    val () = $A.free<byte>(tbuf)
    val () = $A.free<int>(specs)
  in $R.err(err_range(range_err)) end
  else if $AR.gt_int_int(group_err, 0) then let
    val () = $A.free<byte>(str_buf)
    val () = $A.free<int>(str_meta)
    val () = $A.free<int>(int_vals)
    val () = $A.free<int>(bool_vals)
    val () = $A.free<int>(present)
    val () = $A.free<byte>(tbuf)
    val () = $A.free<int>(specs)
  in $R.err(err_exclusive(group_err)) end
  else if $AR.gt_int_int(choice_err, 0) then let
    val () = $A.free<byte>(str_buf)
    val () = $A.free<int>(str_meta)
    val () = $A.free<int>(int_vals)
    val () = $A.free<int>(bool_vals)
    val () = $A.free<int>(present)
    val () = $A.free<byte>(tbuf)
    val () = $A.free<int>(specs)
  in $R.err(err_choice(choice_err)) end
  else
    $R.ok(parse_result_mk(str_buf, str_meta, int_vals, bool_vals, present,
      ac, final_sp, final_subcmd, tbuf, specs))
end

(* ============================================================
   Implementations — Extraction
   ============================================================ *)

implement get_string_len(r, h) = let
  val+ @parse_result_mk(_, smeta, _, _, _, _, _, _, _, _) = r
  val idx =  $UNSAFE.cast{int}(h) 
  val mi = g1ofg0(idx * 2 + 1)
  val len = if mi >= 0 then if mi < 128 then $A.get<int>(smeta, mi) else 0 else 0
  prval () = fold@(r)
in len end

implement get_string_copy {l}{n} (r, h, buf, max_len) = let
  val+ @parse_result_mk(sbuf, smeta, _, _, _, _, _, _, _, _) = r
  val idx =  $UNSAFE.cast{int}(h) 
  val mi = g1ofg0(idx * 2)
  val off = if mi >= 0 then if mi < 128 then $A.get<int>(smeta, mi) else 0 else 0
  val mi2 = g1ofg0(idx * 2 + 1)
  val len = if mi2 >= 0 then if mi2 < 128 then $A.get<int>(smeta, mi2) else 0 else 0
  val copy_len = (if $AR.gt_int_int(len, max_len) then max_len else len): int
  val () = let
    fun loop {lb:agz}{nd:pos}{ls2:agz}{k:nat | k <= nd} .<nd - k>.
      (dst: !$A.arr(byte, lb, nd), src: !$A.arr(byte, ls2, 8192),
       di: int k, si: int, nd: int nd, lim: int): void =
      if di >= nd then ()
      else if di >= lim then ()
      else let val si1 = g1ofg0(si) in
        if si1 >= 0 then
          if si1 < 8192 then let
            val () = $A.set<byte>(dst, di, $A.get<byte>(src, si1))
          in loop(dst, src, di + 1, si + 1, nd, lim) end
          else ()
        else ()
      end
  in loop(buf, sbuf, 0, off, max_len, copy_len) end
  prval () = fold@(r)
in copy_len end

implement get_int(r, h) = let
  val+ @parse_result_mk(_, _, ivals, _, _, _, _, _, _, _) = r
  val idx = g1ofg0( $UNSAFE.cast{int}(h) )
  val v = if idx >= 0 then if idx < 64 then $A.get<int>(ivals, idx) else 0 else 0
  prval () = fold@(r)
in v end

implement get_bool(r, h) = let
  val+ @parse_result_mk(_, _, _, bvals, _, _, _, _, _, _) = r
  val idx = g1ofg0( $UNSAFE.cast{int}(h) )
  val v = if idx >= 0 then if idx < 64 then $A.get<int>(bvals, idx) else 0 else 0
  prval () = fold@(r)
in $AR.gt_int_int(v, 0) end

implement get_count(r, h) = let
  val+ @parse_result_mk(_, _, _, bvals, _, _, _, _, _, _) = r
  val idx = g1ofg0( $UNSAFE.cast{int}(h) )
  val v = if idx >= 0 then if idx < 64 then $A.get<int>(bvals, idx) else 0 else 0
  prval () = fold@(r)
in v end

implement is_present {a} (r, h) = let
  val+ @parse_result_mk(_, _, _, _, pres, _, _, _, _, _) = r
  val idx = g1ofg0( $UNSAFE.cast{int}(h) )
  val v = if idx >= 0 then if idx < 64 then $A.get<int>(pres, idx) else 0 else 0
  prval () = fold@(r)
in $AR.gt_int_int(v, 0) end

implement get_subcmd(r) = let
  val+ @parse_result_mk(_, _, _, _, _, _, _, si, _, _) = r
  val v = si
  prval () = fold@(r)
in v end

(* ============================================================
   Implementations — Exclusive groups
   ============================================================ *)

implement add_exclusive_group(p) = let
  val+ ~parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) = p
  val gid = gc
in @(parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc + 1, pno, pnl, pho, phl), gid) end

implement add_to_group {a} (p, group_id, handle) = let
  val+ ~parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) = p
  val idx =  $UNSAFE.cast{int}(handle) 
  val () = _spec_set(specs, idx, 15, group_id)
in parser_mk(specs, tbuf, subcmds, ac, tp, pc, sc, gc, pno, pnl, pho, phl) end

(* ============================================================
   Implementations — Help formatting
   ============================================================ *)

fn _help_put
  {l:agz}{n:pos}
  (buf: !$A.arr(byte, l, n), pos: int, b: int, max_len: int n): int = let
  val p = g1ofg0(pos)
in
  if p >= 0 then
    if p < max_len then let
      val () = $A.set<byte>(buf, p, $A.int2byte($AR.checked_byte(
        if b >= 0 then if b < 256 then b else 63 else 63)))
    in pos + 1 end
    else pos
  else pos
end

fun _help_copy
  {l:agz}{n:pos}{lt:agz}{fuel:nat} .<fuel>.
  (buf: !$A.arr(byte, l, n), dst: int,
   tbuf: !$A.arr(byte, lt, 8192), src: int, len: int,
   max_len: int n, fuel: int fuel): int =
  if fuel <= 0 then dst
  else if len <= 0 then dst
  else let
    val si = g1ofg0(src)
    val di = g1ofg0(dst)
  in
    if si >= 0 then if si < 8192 then
      if di >= 0 then if di < max_len then let
        val b = byte2int0($A.get<byte>(tbuf, si))
        val () = $A.set<byte>(buf, di, $A.int2byte($AR.checked_byte(
          if b >= 0 then if b < 256 then b else 0 else 0)))
      in _help_copy(buf, dst + 1, tbuf, src + 1, len - 1, max_len, fuel - 1) end
      else dst else dst
    else dst else dst
  end

implement format_help {l}{n} (r, buf, max_len) = let
  val+ @parse_result_mk(_, _, _, _, _, ac, _, _, tbuf, specs) = r
  (* "Usage:\n\n" *)
  val pos = _help_put(buf, 0, 85, max_len)
  val pos = _help_put(buf, pos, 115, max_len)
  val pos = _help_put(buf, pos, 97, max_len)
  val pos = _help_put(buf, pos, 103, max_len)
  val pos = _help_put(buf, pos, 101, max_len)
  val pos = _help_put(buf, pos, 58, max_len)
  val pos = _help_put(buf, pos, 10, max_len)
  val pos = _help_put(buf, pos, 10, max_len)

  fun fmt_args {l:agz}{n:pos}{ls:agz}{lt:agz}{k:nat | k <= 64} .<64 - k>.
    (buf: !$A.arr(byte, l, n), tbuf: !$A.arr(byte, lt, 8192),
     specs: !$A.arr(int, ls, 1024), pos: int, i: int k, ac: int, max_len: int n): int =
    if i >= ac then pos
    else if i >= 64 then pos
    else let
      val noff = _spec_get(specs, i, 2)
      val nlen = _spec_get(specs, i, 3)
      val hoff = _spec_get(specs, i, 4)
      val hlen = _spec_get(specs, i, 5)
      val sch = _spec_get(specs, i, 6)
      val kind = _spec_get(specs, i, 0)
      val pos = _help_put(buf, pos, 32, max_len)
      val pos = _help_put(buf, pos, 32, max_len)
    in
      if $AR.eq_int_int(kind, 0) then let
        val pos = _help_copy(buf, pos, tbuf, noff, nlen, max_len, $AR.checked_nat(nlen))
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_copy(buf, pos, tbuf, hoff, hlen, max_len, $AR.checked_nat(hlen))
        val pos = _help_put(buf, pos, 10, max_len)
      in fmt_args(buf, tbuf, specs, pos, i + 1, ac, max_len) end
      else let
        val pos = if sch >= 0 then let
          val p = _help_put(buf, pos, 45, max_len)
          val p = _help_put(buf, p, sch, max_len)
          val p = _help_put(buf, p, 44, max_len)
          val p = _help_put(buf, p, 32, max_len)
        in p end
        else let
          val p = _help_put(buf, pos, 32, max_len)
          val p = _help_put(buf, p, 32, max_len)
          val p = _help_put(buf, p, 32, max_len)
          val p = _help_put(buf, p, 32, max_len)
        in p end
        val pos = _help_put(buf, pos, 45, max_len)
        val pos = _help_put(buf, pos, 45, max_len)
        val pos = _help_copy(buf, pos, tbuf, noff, nlen, max_len, $AR.checked_nat(nlen))
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_put(buf, pos, 32, max_len)
        val pos = _help_copy(buf, pos, tbuf, hoff, hlen, max_len, $AR.checked_nat(hlen))
        val pos = _help_put(buf, pos, 10, max_len)
      in fmt_args(buf, tbuf, specs, pos, i + 1, ac, max_len) end
    end

  val final_pos = fmt_args(buf, tbuf, specs, pos, 0, ac, max_len)
  prval () = fold@(r)
in final_pos end

(* ============================================================
   Implementations — Cleanup
   ============================================================ *)

implement parse_result_free(r) = let
  val+ ~parse_result_mk(sb, sm, iv, bv, pr, _, _, _, tb, sp) = r
in
  $A.free<byte>(sb); $A.free<int>(sm);
  $A.free<int>(iv); $A.free<int>(bv); $A.free<int>(pr);
  $A.free<byte>(tb); $A.free<int>(sp)
end

implement parse_error_free(e) =
  case+ e of
  | ~err_unknown_long(_) => ()
  | ~err_unknown_short(_) => ()
  | ~err_range(_) => ()
  | ~err_exclusive(_) => ()
  | ~err_choice(_) => ()
