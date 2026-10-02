staload "./emitter.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "str/src/lib.dats"
(* emitter -- emit .sats/.dats from source + spans *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload S = "str/src/lib.sats"

staload "helpers.sats"
staload "lexer.sats"

(* The line of position pos: 1 plus the newlines of src[i, pos) *)
fun _byte_to_line {l:agz}{n:pos}{i,p:nat | i <= p; p <= n} .<p - i>.
  (src: !$A.borrow(byte, l, n), i: int i, pos: int p, line: int): int =
  if i >= pos then line
  else if byte2int0($A.read<byte>(src, i)) = 10 then _byte_to_line(src, i + 1, pos, line + 1)
  else _byte_to_line(src, i + 1, pos, line)

(* The column of position pos, looking back from i (< pos) for the
   newline before it *)
fun _byte_to_col {l:agz}{n:pos}{i:int | i >= ~1}{p:nat | i < p; p <= n} .<i + 1>.
  (src: !$A.borrow(byte, l, n), i: int i, pos: int p): int =
  if i < 0 then pos + 1
  else if byte2int0($A.read<byte>(src, i)) = 10 then pos - i
  else _byte_to_col(src, i - 1, pos)

(* ============================================================
   Emitter: read span records
   ============================================================ *)

(* ============================================================
   Emitter: copy source range to a rope, count newlines
   ============================================================ *)

(* Copy bytes from source borrow to a rope (text of any length) *)
fun emit_range {ls:agz}{ns:pos}{s,e:int} .<max(e - s, 0)>.
  (src: !$A.borrow(byte, ls, ns), start: int s, end_pos: int e,
   max: int ns, out: !$B.rope): void =
  if start >= end_pos then ()
  else let
    val () = rput(out, peek(src, start, max))
  in emit_range(src, start + 1, end_pos, max, out) end

(* Copy bytes, transforming .bats" → .sats" for staload paths. *)
fun emit_range_stald {ls:agz}{ns:pos}{s,e:int} .<max(e - s, 0)>.
  (src: !$A.borrow(byte, ls, ns), start: int s, end_pos: int e,
   max: int ns, out: !$B.rope): void =
  if start >= end_pos then ()
  else let
    val b = peek(src, start, max)
    (* Check for .bats" pattern: 46,98,97,116,115,34 → replace b(98) with s(115) *)
    val b_out = (if $AR.eq_int_int(b, 98) &&
      $AR.eq_int_int(peek(src, start - 1, max), 46) &&
      $AR.eq_int_int(peek(src, start + 1, max), 97) &&
      $AR.eq_int_int(peek(src, start + 2, max), 116) &&
      $AR.eq_int_int(peek(src, start + 3, max), 115) &&
      $AR.eq_int_int(peek(src, start + 4, max), 34)
    then 115 else b): int
    val () = rput(out, b_out)
  in emit_range_stald(src, start + 1, end_pos, max, out) end

(* The newlines of src[start, end_pos), so line numbers stay put *)
fun emit_blanks {ls:agz}{ns:pos}{s,e:int} .<max(e - s, 0)>.
  (src: !$A.borrow(byte, ls, ns), start: int s, end_pos: int e,
   max: int ns, out: !$B.rope): void =
  if start >= end_pos then ()
  else let
    val b = peek(src, start, max)
    val () = (if $AR.eq_int_int(b, 10) then rput(out, 10) else ())
  in emit_blanks(src, start + 1, end_pos, max, out) end

(* Whether this file's "implement main0" has been renamed; set by
   emit_code_v, read by do_emit *)
val g_main0_renamed = ref<bool>(false)

(* The first "implement main0" in src[p, e) that is code on its own:
   no identifier byte right before or after it. ~1 when there is none. *)
fun find_main0 {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int e, max: int n): pos_t =
  if p + 15 > e then ~1
  else let
    var c = @[char][15]('i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't', ' ', 'm', 'a', 'i', 'n', '0')
    val hit = lit_at(src, p, max, c, 15)
    val before_ok = (if p = 0 then true else ~is_ident_byte(byte2int0($A.read<byte>(src, p - 1)))): bool
    val after_ok = (if p + 15 >= max then true else ~is_ident_byte(byte2int0($A.read<byte>(src, p + 15)))): bool
  in
    if hit && before_ok && after_ok then p
    else find_main0(src, p + 1, e, max)
  end

fn emit_range_v {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), start: pos_t, end_pos: pos_t,
   max: int ns, out: !$B.rope): void =
  emit_range(src, start, end_pos, max, out)

(* The sats declaration of the renamed entry point, when there is one *)
fn put_main0_decl(out: !$B.rope): void =
  if !g_main0_renamed then rbput(out, "\nfun __BATS_main0 (): void\n")
  else ()

(* Code in [ss, se) to the dats, with the file's first "implement main0"
   renamed to "implement __BATS_main0". Comment and literal spans (aux1 = 1)
   never come here, so their text is never renamed. *)
fn emit_code_v {ls:agz}{ns:pos}{ss,se:nat | ss <= se; se <= ns}
  (src: !$A.borrow(byte, ls, ns), ss: int ss, se: int se,
   max: int ns, out: !$B.rope): void =
  if !g_main0_renamed then emit_range_v(src, ss, se, max, out)
  else let
    val p = find_main0(src, ss, se, max)
  in
    if p < 0 then emit_range_v(src, ss, se, max, out)
    else let
      val () = emit_range_v(src, ss, p, max, out)
      val () = rbput(out, "implement __BATS_main0")
      val () = emit_range_v(src, p + 15, se, max, out)
    in !g_main0_renamed := true end
  end

fn emit_range_stald_v {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), start: pos_t, end_pos: pos_t,
   max: int ns, out: !$B.rope): void =
  emit_range_stald(src, start, end_pos, max, out)

fn emit_blanks_v {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), start: pos_t, end_pos: pos_t,
   max: int ns, out: !$B.rope): void =
  emit_blanks(src, start, end_pos, max, out)

(* ============================================================
   Emitter: name mangling (__BATS__<mangled_pkg>_<member>)
   ============================================================ *)

(* $alias.member, as written: src[as0, ae) and src[ms, me) *)
fn emit_qualified {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns,
   as0: spos(ns), ae: spos(ns), ms: spos(ns), me: spos(ns),
   out: !$B.rope): void = let
  val () = rput(out, 36)  (* $ *)
  val () = emit_range_v(src, as0, ae, src_max, out)
  val () = rput(out, 46)  (* . *)
in emit_range_v(src, ms, me, src_max, out) end

(* ============================================================
   Emitter: generate dats prelude (staload self + dependencies)
   ============================================================ *)

(* Emit one staload line for a #use dependency: staload "pkg/src/lib.dats" (no alias) *)
fn emit_dep_stld {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns,
   pkg_s: spos(ns), pkg_e: spos(ns),
   out: !$B.rope): void = let
  (* staload " *)
  val () = rput(out, 115)
  val () = rput(out, 116)
  val () = rput(out, 97)
  val () = rput(out, 108)
  val () = rput(out, 111)
  val () = rput(out, 97)
  val () = rput(out, 100)
  val () = rput(out, 32)
  val () = rput(out, 34)
  (* package path *)
  val () = emit_range_v(src, pkg_s, pkg_e, src_max, out)
  (* /src/lib.dats"\n *)
  val () = rput(out, 47)   (* / *)
  val () = rput(out, 115)  (* s *)
  val () = rput(out, 114)  (* r *)
  val () = rput(out, 99)   (* c *)
  val () = rput(out, 47)   (* / *)
  val () = rput(out, 108)  (* l *)
  val () = rput(out, 105)  (* i *)
  val () = rput(out, 98)   (* b *)
  val () = rput(out, 46)   (* . *)
  val () = rput(out, 100)  (* d *)
  val () = rput(out, 97)   (* a *)
  val () = rput(out, 116)  (* t *)
  val () = rput(out, 115)  (* s *)
  val () = rput(out, 34)   (* " *)
  val () = rput(out, 10)   (* \n *)
in end

(* Emit one staload line for .sats: staload ALIAS = "pkg/src/lib.sats" *)
fn emit_dep_stld_sats {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns,
   pkg_s: spos(ns), pkg_e: spos(ns), alias_s: spos(ns), alias_e: spos(ns),
   out: !$B.rope): void = let
  (* staload  *)
  val () = rput(out, 115)
  val () = rput(out, 116)
  val () = rput(out, 97)
  val () = rput(out, 108)
  val () = rput(out, 111)
  val () = rput(out, 97)
  val () = rput(out, 100)
  val () = rput(out, 32)
  (* ALIAS = " *)
  val () = emit_range_v(src, alias_s, alias_e, src_max, out)
  val () = rput(out, 32)   (* space *)
  val () = rput(out, 61)   (* = *)
  val () = rput(out, 32)   (* space *)
  val () = rput(out, 34)   (* " *)
  (* package path *)
  val () = emit_range_v(src, pkg_s, pkg_e, src_max, out)
  (* /src/lib.sats"\n *)
  val () = rput(out, 47)   (* / *)
  val () = rput(out, 115)  (* s *)
  val () = rput(out, 114)  (* r *)
  val () = rput(out, 99)   (* c *)
  val () = rput(out, 47)   (* / *)
  val () = rput(out, 108)  (* l *)
  val () = rput(out, 105)  (* i *)
  val () = rput(out, 98)   (* b *)
  val () = rput(out, 46)   (* . *)
  val () = rput(out, 115)  (* s *)
  val () = rput(out, 97)   (* a *)
  val () = rput(out, 116)  (* t *)
  val () = rput(out, 115)  (* s *)
  val () = rput(out, 34)   (* " *)
  val () = rput(out, 10)   (* \n *)
in end

(* The target state inside a $UNITTEST block entered at target_state:
   its contents are code in check and test mode, and blanked otherwise
   (as in a non-matching #target block) *)
fn unittest_enter (target_state: int): int =
  if target_state > 0 then target_state + 1
  else if is_test_mode() then 0
  else 1

(* ============================================================
   Emitter: main emit loop
   ============================================================ *)

(* The range of sp *)
fn span_range {n:int} (sp: !span(n)): @(spos(n), spos(n)) =
  case+ sp of
  | SPass(s, e, _) => @(s, e) | SUse(s, e, _, _, _, _, _) => @(s, e)
  | SPub(s, e, _, _) => @(s, e) | SQual(s, e, _, _, _, _) => @(s, e)
  | SUnsafeBlock(s, e, _, _) => @(s, e) | SConstruct(s, e) => @(s, e)
  | SExtcode(s, e, _, _, _) => @(s, e) | STarget(s, e, _) => @(s, e)
  | SStaload(s, e) => @(s, e) | STargetBegin(s, e, _) => @(s, e)
  | STargetEnd(s, e) => @(s, e) | SUnittestBegin(s, e, _, _) => @(s, e)
  | SUnittestEnd(s, e) => @(s, e) | SLexError(a, _, _, _, _) => @(a, a)

(* An unsafe construct outside $UNSAFE at ss: reported, blanked *)
fn emit_rejected {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, ss: spos(ns), se: spos(ns),
   sats: !$B.rope, dats: !$B.rope): void = let
  val () = println! ("error: unsafe construct at line ", _byte_to_line(src, 0, ss, 1), " column ", _byte_to_col(src, ss - 1, ss), " outside $UNSAFE block")
  val () = emit_blanks_v(src, ss, se, src_max, dats)
in emit_blanks_v(src, ss, se, src_max, sats) end

(* sp, outside a blanked block, to sats and dats; the number of errors
   it adds *)
fn emit_code_span {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, sp: !span(ns),
   sats: !$B.rope, dats: !$B.rope,
   is_unsafe: int): int =
  case+ sp of
  | SPass(ss, se, verbatim) => let
      val () = (if verbatim then emit_range_v(src, ss, se, src_max, dats)
                else emit_code_v(src, ss, se, src_max, dats))
      val () = emit_blanks_v(src, ss, se, src_max, sats)
    in 0 end
  (* #use: its staload in the dats, blank in the sats *)
  | SUse(ss, se, _, ps, pe, as0, ae) => let
      val () = emit_blanks_v(src, ss, se, src_max, sats)
      val () = emit_dep_stld_sats(src, src_max, ps, pe, as0, ae, dats)
    in 0 end
  (* #pub: the declaration to the sats, blank in the dats *)
  | SPub(ss, se, rejected, cs) =>
    if rejected then let
      val () = emit_rejected(src, src_max, ss, se, sats, dats)
    in 1 end
    else let
      val () = emit_blanks_v(src, ss, cs, src_max, sats)
      val () = emit_range_v(src, cs, se, src_max, sats)
      val () = emit_blanks_v(src, ss, se, src_max, dats)
    in 0 end
  | SQual(_, _, as0, ae, ms, me) => let
      val () = emit_qualified(src, src_max, as0, ae, ms, me, dats)
    in 0 end
  (* $UNSAFE begin...end: its contents in an unsafe package, an error in
     a safe one *)
  | SUnsafeBlock(ss, se, cs, ce) =>
    if is_unsafe > 0 then let
      val () = emit_blanks_v(src, ss, cs, src_max, dats)
      val () = emit_blanks_v(src, ss, cs, src_max, sats)
      val () = emit_range_v(src, cs, ce, src_max, dats)
      val () = emit_blanks_v(src, ce, se, src_max, dats)
      val () = emit_blanks_v(src, ce, se, src_max, sats)
    in 0 end
    else let
      val () = println! ("error: $UNSAFE block at line ", _byte_to_line(src, 0, ss, 1), " column ", _byte_to_col(src, ss - 1, ss), " not allowed in safe package")
      val () = emit_blanks_v(src, ss, se, src_max, dats)
      val () = emit_blanks_v(src, ss, se, src_max, sats)
    in 1 end
  | SConstruct(ss, se) => let
      val () = emit_rejected(src, src_max, ss, se, sats, dats)
    in 1 end
  (* %{ ... %}: as is to the dats *)
  | SExtcode(ss, se, _, _, _) => let
      val () = emit_range_v(src, ss, se, src_max, dats)
      val () = emit_blanks_v(src, ss, se, src_max, sats)
    in 0 end
  | SStaload(ss, se) => let
      val () = emit_range_stald_v(src, ss, se, src_max, dats)
      val () = emit_range_stald_v(src, ss, se, src_max, sats)
    in 0 end
  (* #target lines, block markers: blank *)
  | _ => let
      val @(ss, se) = span_range(sp)
      val () = emit_blanks_v(src, ss, se, src_max, sats)
      val () = emit_blanks_v(src, ss, se, src_max, dats)
    in 0 end

(* The target state after sp: entering a #target block for another
   target, or a $UNITTEST block outside check and test mode, blanks
   what is in it *)
fn next_state {n:int} (sp: !span(n), ts: int, build_target: target): int =
  case+ sp of
  | STargetBegin(_, _, t) =>
    if ts > 0 then ts + 1 else if same_target(t, build_target) then 0 else 1
  | SUnittestBegin(_, _, _, _) => unittest_enter(ts)
  | STargetEnd(_, _) => (if ts > 0 then ts - 1 else 0)
  | SUnittestEnd(_, _) => (if ts > 0 then ts - 1 else 0)
  | _ => ts

(* Whether sp opens or closes a block *)
fn is_marker {n:int} (sp: !span(n)): bool =
  case+ sp of
  | STargetBegin(_, _, _) => true | SUnittestBegin(_, _, _, _) => true
  | STargetEnd(_, _) => true | SUnittestEnd(_, _) => true
  | _ => false

(* sp blanked in sats and dats *)
fn emit_blank_span {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, sp: !span(ns),
   sats: !$B.rope, dats: !$B.rope): void = let
  val @(ss, se) = span_range(sp)
  val () = emit_blanks_v(src, ss, se, src_max, sats)
in emit_blanks_v(src, ss, se, src_max, dats) end

(* sp to sats and dats: blanked in a blanked block (ts > 0) or when it
   is a block marker; the number of errors it adds *)
fn emit_one {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, sp: !span(ns),
   sats: !$B.rope, dats: !$B.rope,
   is_unsafe: int, ts: int): int =
  if ts > 0 then let
    val () = emit_blank_span(src, src_max, sp, sats, dats)
  in 0 end
  else if is_marker(sp) then let
    val () = emit_blank_span(src, src_max, sp, sats, dats)
  in 0 end
  else emit_code_span(src, src_max, sp, sats, dats, is_unsafe)

(* The staload of a #use not in a blanked block (ts = 0), to prelude:
   for the sats (with its alias) or the dats; 1 when there was one *)
fn prelude_line {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, sp: !span(ns),
   prelude: !$B.rope, ts: int, for_sats: bool): int =
  if ts > 0 then 0
  else case+ sp of
    | SUse(_, _, _, ps, pe, as0, ae) =>
      if for_sats then let
        val () = emit_dep_stld_sats(src, src_max, ps, pe, as0, ae, prelude)
      in 1 end
      else let
        val () = emit_dep_stld(src, src_max, ps, pe, prelude)
      in 1 end
    | _ => 0

(* xs to sats and dats; ts > 0 inside a blanked block. The number of
   errors, added to errors. *)
fun emit_spans {ls:agz}{ns:pos}{k:nat} .<k>.
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, xs: !spans(ns, k),
   sats: !$B.rope, dats: !$B.rope,
   build_target: target, is_unsafe: int, errors: int, ts: int): int =
  case+ xs of
  | spans_nil() => errors
  | spans_cons(sp, tl) => let
      val e1 = emit_one(src, src_max, sp, sats, dats, is_unsafe, ts)
    in emit_spans(src, src_max, tl, sats, dats, build_target, is_unsafe, errors + e1,
                  next_state(sp, ts, build_target)) end

(* Build dats prelude: a staload of each #use dependency, not in a
   blanked block; the number of them *)
fun build_prelude {ls:agz}{ns:pos}{k:nat} .<k>.
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, xs: !spans(ns, k),
   prelude: !$B.rope, build_target: target, ts: int): int =
  case+ xs of
  | spans_nil() => 0
  | spans_cons(sp, tl) => let
      val c = prelude_line(src, src_max, sp, prelude, ts, false)
    in c + build_prelude(src, src_max, tl, prelude, build_target, next_state(sp, ts, build_target)) end

(* Build sats prelude: staload ALIAS = "pkg/src/lib.sats" for each #use
   not in a blanked block *)
fun build_prelude_sats {ls:agz}{ns:pos}{k:nat} .<k>.
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, xs: !spans(ns, k),
   prelude: !$B.rope, build_target: target, ts: int): void =
  case+ xs of
  | spans_nil() => ()
  | spans_cons(sp, tl) => let
      val _ = prelude_line(src, src_max, sp, prelude, ts, true)
    in build_prelude_sats(src, src_max, tl, prelude, build_target, next_state(sp, ts, build_target)) end

(* ============================================================
   Test functions: each "fn <name> ()" of a $UNITTEST.run block
   ============================================================ *)

(* Past the space, tabs and newlines at p, before e *)
fun skip_blank {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int, max: int n): [q:int | p <= q; q <= n] int q =
  if p >= e then p
  else if p >= max then p
  else let val b = byte2int0($A.read<byte>(src, p)) in
    if b = 32 || b = 9 || b = 10 || b = 13 then skip_blank(src, p + 1, e, max) else p
  end

(* Past the identifier at p, before e *)
fun skip_name {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int, max: int n): [q:int | p <= q; q <= n] int q =
  if p >= e then p
  else if p >= max then p
  else if is_ident_byte(byte2int0($A.read<byte>(src, p))) then skip_name(src, p + 1, e, max)
  else p

(* The byte at p, or ~1 at or past e *)
fn byte_before {l:agz}{n:pos}{p:nat}
  (src: !$A.borrow(byte, l, n), p: int p, e: int, max: int n): int =
  if p >= e then ~1 else if p >= max then ~1 else byte2int0($A.read<byte>(src, p))

(* Each test in the code src[p, e): "fn", a name, "()", appended to out
   as <targets><name>NUL (targets_byte); the number of them *)
fun scan_tests {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int, max: int n, targets: test_targets,
   out: !$B.builder_v >> $B.builder_v, k: int): int =
  if p >= e then k
  else if p >= max then k
  else let
    val prev = (if p > 0 then byte_before(src, p - 1, e, max) else ~1): int
    val at_fn = (if is_ident_byte(prev) then false
                 else if byte_before(src, p, e, max) <> 102 then false
                 else byte_before(src, p + 1, e, max) = 110): bool
  in
    if ~at_fn then scan_tests(src, p + 1, e, max, targets, out, k)
    else let
      val q0 = (if p + 2 <= max then p + 2 else max): [q:int | p < q; q <= n] int q
      val ns = skip_blank(src, q0, e, max)
      val ne = skip_name(src, ns, e, max)
      val q1 = skip_blank(src, ne, e, max)
      val q2 = (if q1 >= max then q1
                else if byte_before(src, q1, e, max) = 40 then skip_blank(src, q1 + 1, e, max)
                else q1): [q:nat | q <= n] int q
      val is_test = (if ns = q0 then false
                     else if ne = ns then false
                     else if q2 = q1 then false
                     else byte_before(src, q2, e, max) = 41): bool
    in
      if is_test then let
        val () = put_char_v(out, targets_byte(targets))
        val () = copy_to_builder_v(src, ns, ne, max, out)
        val () = put_char_v(out, 0)
      in scan_tests(src, ne, e, max, targets, out, k + 1) end
      else scan_tests(src, q0, e, max, targets, out, k)
    end
  end

(* scan_tests over the code span src[ss, se) *)
fn scan_span {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), ss: pos_t, se: int, max: int n, targets: test_targets,
   out: !$B.builder_v >> $B.builder_v, k: int): int =
  if ss < 0 then k
  else if ss > max then k
  else scan_tests(src, ss, se, max, targets, out, k)

(* The run a span leaves: a $UNITTEST.run block's targets from its
   begin to its end, else none *)
fn next_run {ns:int} (sp: !span(ns), run: test_targets): test_targets =
  case+ sp of
  | SUnittestBegin(_, _, r, targets) => (if r then targets else NoTestTargets())
  | SUnittestEnd(_, _) => NoTestTargets()
  | _ => run

(* The tests sp holds when it is code in a $UNITTEST.run block of the
   targets run (some), appended to out; k plus their number *)
fn span_tests {ls:agz}{ns:pos}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, sp: !span(ns), run: test_targets,
   out: !$B.builder_v >> $B.builder_v, k: int): int =
  case+ run of
  | NoTestTargets() => k
  | _ => (case+ sp of
    | SPass(ss, se, v) => (if v then k else scan_tests(src, ss, se, src_max, run, out, k))
    | _ => k)

(* The tests of the $UNITTEST.run blocks among xs, in order, appended
   to out as <targets><name>NUL (targets_byte); run: the targets of the
   block xs starts in, or none *)
fun collect_spans {ls:agz}{ns:pos}{k:nat} .<k>.
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, xs: !spans(ns, k),
   run: test_targets, out: !$B.builder_v >> $B.builder_v, n: int): int =
  case+ xs of
  | spans_nil() => n
  | spans_cons(sp, tl) => let
      val n2 = span_tests(src, src_max, sp, run, out, n)
    in collect_spans(src, src_max, tl, next_run(sp, run), out, n2) end

(* The test functions of the $UNITTEST.run blocks of src, in order, as
   <targets><name>NUL entries (targets_byte: the block's targets); the
   number of them. A test is "fn <name> (): bool" in a
   block's code. *)




implement collect_tests (src, src_max, xs, out) =
  collect_spans(src, src_max, xs, NoTestTargets(), out, 0)

(* "  if i = <k> then <name> ()\n  else " for each entry of t[p, e) *)
fun put_dispatch {l:agz}{p:nat | p <= 524288} .<524288 - p>.
  (t: !$A.borrow(byte, l, 524288), p: int p, e: int, k: int,
   dats: !$B.rope): void =
  if p >= e then ()
  else if p >= 524288 then ()
  else let
    val ne = $S.find_null_bv_at(t, p + 1, 524288)
    val () = rbput(dats, "if i = ")
    val () = rput_int(dats, k)
    val () = rbput(dats, " then ")
    val () = $B.rope_copy(dats, t, p + 1, ne)
    val () = rbput(dats, " ()\n  else ")
  in
    if ne >= 524288 then ()
    else put_dispatch(t, ne + 1, e, k + 1, dats)
  end

(* When there are k > 0 tests t[0, tlen): the declaration of
   __bats_test to sats, its implementation to dats *)
fn put_dispatch_decl {l:agz}
  (k: int, t: !$A.borrow(byte, l, 524288), tlen: int,
   sats: !$B.rope, dats: !$B.rope): void =
  if k <= 0 then ()
  else let
    val () = rbput(sats, "\nfun __bats_test (i: int): bool\n")
    val () = rbput(dats, "\n(* bats test: the i-th test of this module *)\nimplement __bats_test (i) =\n  ")
    val () = put_dispatch(t, 0, tlen, 0, dats)
  in rbput(dats, "false\n") end

(* In check and test mode, a module with tests declares
   __bats_test (i: int): bool, which runs its i-th test (in source
   order), for bats test's runner to call *)
fn put_test_dispatch {ls:agz}{ns:pos}{k:nat}
  (src: !$A.borrow(byte, ls, ns), src_max: int ns, xs: !spans(ns, k),
   sats: !$B.rope, dats: !$B.rope): void =
  if ~is_test_mode() then () else let
  var tb : $B.builder_v = $B.create()
  val k = collect_tests(src, src_max, xs, tb)
  val @(ta, tlen) = $B.to_arr(tb)
  val @(fz_t, bv_t) = $A.freeze<byte>(ta)
  val () = put_dispatch_decl(k, bv_t, tlen, sats, dats)
  val () = $A.drop<byte>(fz_t, bv_t)
in $A.free<byte>($A.thaw<byte>(fz_t)) end

(* Top-level emit: the module's .sats text appended to sats, its .dats
   text to dats (which holds its self-staload line); @(the lines of the
   dats prelude, self-staload included, the number of errors) *)





implement do_emit (src, src_max, xs, build_target, is_unsafe, sats, dats) = let
  (* The staload of each dependency, to the dats (after its self-staload
     line) and, with its alias, to the sats *)
  val dep_count = build_prelude(src, src_max, xs, dats, build_target, 0)
  val () = build_prelude_sats(src, src_max, xs, sats, build_target, 0)
  val () = !g_main0_renamed := false
  val emit_errors = emit_spans(src, src_max, xs, sats, dats, build_target, is_unsafe, 0, 0)
  (* The entry point was renamed in the dats (emit_code_v); declare it *)
  val () = put_main0_decl(sats)
  val () = put_test_dispatch(src, src_max, xs, sats, dats)
in @(dep_count + 1, emit_errors) end
