staload "./recursion.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "file/src/lib.dats"
staload "result/src/lib.dats"
staload "str/src/lib.dats"
(* recursion -- no call cycle through an implement

   A metric cannot be given to a function declared in a .sats, so the
   body of an implement is never checked for termination: an implement
   that calls itself, directly or through other functions, recurses
   with no proof that it stops. This finds those implements. The call
   graph of a package's top-level definitions (implement, fn, fun, fnx
   and the and of a fun group) is read from its sources: a definition
   calls every definition whose name its body mentions (unqualified),
   an implement's name being visible in every file and another
   definition's only in its own. The calls within a fun group, which
   the group's metric checks, are left out. An implement on a cycle of
   what remains is reported. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload F = "file/src/lib.sats"
staload R = "result/src/lib.sats"
staload S = "str/src/lib.sats"

staload "helpers.sats"
staload "lexer.sats"

#define RMAX 524288

(* ============================================================
   Definitions
   ============================================================ *)

(* The identifiers a body mentions: src[s, e) each *)
datavtype occs(int) =
  | occs_nil(0) of ()
  | {k:nat}{s,e:nat | s <= e; e <= RMAX} occs_cons(k + 1) of (int s, int e, occs(k))

fun occs_free {k:nat} .<k>. (xs: occs(k)): void =
  case+ xs of
  | ~occs_nil() => ()
  | ~occs_cons(_, _, tl) => occs_free(tl)

(* A top-level definition: whether it is an implement, its group (0 for
   an implement; a fn has one of its own, a fun group one for all its
   members), its keyword's start, its name src[ns, ne) and its body's
   identifiers *)
datavtype def =
  | {k:nat} Def of (bool, int, spos(RMAX), spos(RMAX), spos(RMAX), occs(k))

datavtype defs(int) =
  | defs_nil(0) of ()
  | {k:nat} defs_cons(k + 1) of (def, defs(k))

fun defs_free {k:nat} .<k>. (xs: defs(k)): void =
  case+ xs of
  | ~defs_nil() => ()
  | ~defs_cons(d, tl) => let
      val+ ~Def(_, _, _, _, _, oc) = d
      val () = occs_free(oc)
    in defs_free(tl) end

(* A definition's name, name[0, k) (its first 256 bytes: two names that
   share them are taken as one, which can only add calls), whether it is
   visible in every file (an implement), its file and its group *)
datavtype dname =
  | {l:agz}{k:nat | k <= 256} DName of ($A.arr(byte, l, 256), int k, bool, int, int)

datavtype dnames(int) =
  | dnames_nil(0) of ()
  | {m:nat} dnames_cons(m + 1) of (dname, dnames(m))

fun dnames_free {m:nat} .<m>. (xs: dnames(m)): void =
  case+ xs of
  | ~dnames_nil() => ()
  | ~dnames_cons(d, tl) => let
      val+ ~DName(a, _, _, _, _) = d
      val () = $A.free<byte>(a)
    in dnames_free(tl) end

(* The definition being read, if any: its name, whether it is an
   implement, its group, its keyword's start, its name's range and the
   identifiers of its body so far *)
datavtype cur =
  | cur_none of ()
  | {l:agz}{k:nat | k <= 256}{j:nat}
    cur_def of ($A.arr(byte, l, 256), int k, bool, int, spos(RMAX), spos(RMAX), spos(RMAX), occs(j))

(* What the scan has found: the current file's definitions (k), the
   names of every definition so far (m; m - k of them in earlier
   files), the definition being read, and the last group *)
datavtype found(int, int) =
  | {k,m:nat} Found(k, m) of (defs(k), int k, dnames(m), int m, cur, int)

(* The package's files: each one's path (its offset in the file list),
   its source and its definitions; t of them in all *)
datavtype pfiles(int, int) =
  | pfiles_nil(0, 0) of ()
  | {l:agz}{k,t,f:nat} pfiles_cons(t + k, f + 1) of (spos(RMAX), $A.arr(byte, l, RMAX), int k, defs(k), pfiles(t, f))

fun pfiles_free {t,f:nat} .<f>. (xs: pfiles(t, f)): void =
  case+ xs of
  | ~pfiles_nil() => ()
  | ~pfiles_cons(_, a, _, ds, tl) => let
      val () = $A.free<byte>(a)
      val () = defs_free(ds)
    in pfiles_free(tl) end

(* ============================================================
   Reading definitions from the spans
   ============================================================ *)

fn is_ident_start (b: int): bool =
  (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b = 95

(* The byte at p *)
fn rb {l:agz}{p:nat | p < RMAX} (bv: !$A.borrow(byte, l, RMAX), p: int p): int =
  byte2int0($A.read<byte>(bv, p))

(* The end of the identifier that starts at p, within [p, e) *)
fun ident_end {l:agz}{p,e:nat | p <= e; e <= RMAX} .<e - p>.
  (bv: !$A.borrow(byte, l, RMAX), p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val c = rb(bv, p)
  in
    if is_ident_byte(c) then ident_end(bv, p + 1, e)
    else if c = 39 then ident_end(bv, p + 1, e)
    else p
  end

(* The first position of [p, e) past blanks and {...} groups *)
fun skip_head {l:agz}{p,e:nat | p <= e; e <= RMAX} .<e - p>.
  (bv: !$A.borrow(byte, l, RMAX), p: int p, e: int e, depth: int): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val c = rb(bv, p)
  in
    if c = 123 then skip_head(bv, p + 1, e, depth + 1)
    else if c = 125 then skip_head(bv, p + 1, e, (if depth > 0 then depth - 1 else 0))
    else if depth > 0 then skip_head(bv, p + 1, e, depth)
    else if c = 32 || c = 9 || c = 10 || c = 13 then skip_head(bv, p + 1, e, depth)
    else p
  end

(* src[p, q) is the keyword kw[0, m) *)
fn word_is {l:agz}{p,q:nat | p <= q; q <= RMAX}{m:pos | m <= 16}
  (bv: !$A.borrow(byte, l, RMAX), p: int p, q: int q, kw: &(@[char][m]), m: int m): bool =
  if q - p <> m then false else lit_at(bv, p, RMAX, kw, m)

(* What the word src[p, q) at the start of a line begins: 1 an
   implement, 2 a fn, 3 a fun or fnx (a new group), 4 an and (the
   group goes on), 0 none *)
fn def_kind {l:agz}{p,q:nat | p <= q; q <= RMAX}
  (bv: !$A.borrow(byte, l, RMAX), p: int p, q: int q): int = let
  var impl_c = @[char][9]('i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
  var fn_c = @[char][2]('f', 'n')
  var fun_c = @[char][3]('f', 'u', 'n')
  var fnx_c = @[char][3]('f', 'n', 'x')
  var and_c = @[char][3]('a', 'n', 'd')
in
  if word_is(bv, p, q, impl_c, 9) then 1
  else if word_is(bv, p, q, fn_c, 2) then 2
  else if word_is(bv, p, q, fun_c, 3) then 3
  else if word_is(bv, p, q, fnx_c, 3) then 3
  else if word_is(bv, p, q, and_c, 3) then 4
  else 0
end

(* src[s, e) (its first 256 bytes) into a name array *)
fun copy_name {l,la:agz}{s,e:nat | s <= e; e <= RMAX}{i:nat | i <= 256} .<256 - i>.
  (bv: !$A.borrow(byte, l, RMAX), s: int s, e: int e, a: !$A.arr(byte, la, 256), i: int i)
  : [k:nat | k <= 256] int k =
  if i >= 256 then i
  else if s + i >= e then i
  else let
    val () = $A.set<byte>(a, i, $A.read<byte>(bv, s + i))
  in copy_name(bv, s, e, a, i + 1) end

(* The definition being read, if any, added to the found ones *)
fn end_def {k,m:nat} (st: found(k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(k2, m2) = let
  val+ ~Found(ds, kd, nm, km, c, g) = st
in
  case+ c of
  | ~cur_none() => Found(ds, kd, nm, km, cur_none(), g)
  | ~cur_def(a, nk, impl, grp, kw, ns, ne, oc) =>
    Found(defs_cons(Def(impl, grp, kw, ns, ne, oc), ds), kd + 1,
          dnames_cons(DName(a, nk, impl, fi, grp), nm), km + 1, cur_none(), g)
end

(* The end of the name that starts at p (p itself when none does) *)
fn name_end {l:agz}{p,e:nat | p <= e; e <= RMAX}
  (bv: !$A.borrow(byte, l, RMAX), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_ident_start(rb(bv, p)) then ident_end(bv, p, e)
  else p

(* A new definition of kind kd (def_kind) whose keyword is src[kw, q),
   its name after it within [q, e); the position after the name *)
fn start_def {l:agz}{k,m:nat}{kw,q,e:nat | kw <= q; q <= e; e <= RMAX}
  (bv: !$A.borrow(byte, l, RMAX), st: found(k, m), kind: int, kw: int kw, q: int q, e: int e, fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] @(found(k2, m2), [r:nat | q <= r; r <= e] int r) = let
  val st1 = end_def(st, fi)
  val+ ~Found(ds, kd, nm, km, c, g) = st1
  val () = (case+ c of
    | ~cur_none() => ()
    | ~cur_def(a, _, _, _, _, _, _, oc) => let
        val () = $A.free<byte>(a)
      in occs_free(oc) end): void
  val ns = skip_head(bv, q, e, 0)
  val ne = name_end(bv, ns, e)
  val a = $A.alloc<byte>(256)
  val nk = copy_name(bv, ns, ne, a, 0)
  val g2 = (if kind = 4 then (if g > 0 then g else 1) else if kind = 1 then g else g + 1): int
  val grp = (if kind = 1 then 0 else g2): int
in
  @(Found(ds, kd, nm, km, cur_def(a, nk, kind = 1, grp, kw, ns, ne, occs_nil()), g2), ne)
end

(* The identifier src[s, e) added to the body being read *)
fn add_occ {k,m:nat}{s,e:nat | s <= e; e <= RMAX} (st: found(k, m), s: int s, e: int e): found(k, m) = let
  val+ ~Found(ds, kd, nm, km, c, g) = st
in
  case+ c of
  | ~cur_none() => Found(ds, kd, nm, km, cur_none(), g)
  | ~cur_def(a, nk, impl, grp, kw, ns, ne, oc) =>
    Found(ds, kd, nm, km, cur_def(a, nk, impl, grp, kw, ns, ne, occs_cons(s, e, oc)), g)
end

(* Whether p starts a line *)
fn line_start {l:agz}{p:nat | p < RMAX} (bv: !$A.borrow(byte, l, RMAX), p: int p): bool =
  if p = 0 then true else rb(bv, p - 1) = 10

(* Whether the byte before p makes an identifier at p part of something
   else: an identifier, a number, a field (.x) or a qualified name ($X) *)
fn joined {l:agz}{p:nat | p < RMAX} (bv: !$A.borrow(byte, l, RMAX), p: int p): bool =
  if p = 0 then false
  else let
    val c = rb(bv, p - 1)
  in is_ident_byte(c) || c = 39 || c = 46 || c = 36 end

(* The definitions and identifiers of the code src[p, e) *)
fun scan_code {l:agz}{k,m:nat}{p,e:nat | p <= e; e <= RMAX} .<e - p>.
  (bv: !$A.borrow(byte, l, RMAX), p: int p, e: int e, st: found(k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(k2, m2) =
  if p >= e then st
  else if ~is_ident_start(rb(bv, p)) then scan_code(bv, p + 1, e, st, fi)
  else if joined(bv, p) then scan_code(bv, ident_end(bv, p + 1, e), e, st, fi)
  else let
    val q = ident_end(bv, p + 1, e)
    val kind = (if line_start(bv, p) then def_kind(bv, p, q) else 0): int
  in
    if kind > 0 then let
      val @(st2, r) = start_def(bv, st, kind, p, q, e, fi)
    in scan_code(bv, r, e, st2, fi) end
    else scan_code(bv, q, e, add_occ(st, p, q), fi)
  end

(* The definitions and identifiers of the span sp: code is read, a
   comment, string, qualified name or construct is not, and anything
   else (a #pub declaration, a #use, a $UNSAFE block, a block's begin or
   end) ends the definition being read *)
fn scan_span {l:agz}{k,m:nat}
  (bv: !$A.borrow(byte, l, RMAX), sp: !span(RMAX), st: found(k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(k2, m2) =
  case+ sp of
  | SPass(s, e, verbatim) =>
    if verbatim then st else scan_code(bv, s, e, st, fi)
  | SQual(_, _, _, _, _, _) => st
  | SConstruct(_, _) => st
  | SLexError(_, _, _, _, _) => st
  | _ => end_def(st, fi)

fun scan_spans {l:agz}{k,m:nat}{j:nat} .<j>.
  (bv: !$A.borrow(byte, l, RMAX), xs: !spans(RMAX, j), st: found(k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(k2, m2) =
  case+ xs of
  | spans_nil() => st
  | spans_cons(sp, tl) => scan_spans(bv, tl, scan_span(bv, sp, st, fi), fi)

(* ============================================================
   The package's files
   ============================================================ *)

(* What the files read so far hold: t definitions in all, their files
   and names, and the last group *)
datavtype pkg =
  | {t,f:nat} Pkg of (pfiles(t, f), dnames(t), int t, int)

(* pk with the file at the NUL-terminated path p (at fi in the file
   list) *)
fn add_file {lp:agz} (p: !$A.borrow(byte, lp, RMAX), fi: spos(RMAX), pk: pkg): pkg =
  case+ $F.file_open(p, RMAX, 0, 0) of
  | ~$R.err(_) => pk
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(RMAX)
      val n = (case+ $F.file_read(fd, buf, RMAX) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= RMAX] int k
      val () = $R.discard<int><int>($F.file_close(fd))
      val+ ~Pkg(pf, nm, t, g) = pk
      val @(fz, bv) = $A.freeze<byte>(buf)
      val xs = lex_spans(bv, n, RMAX)
      val st = scan_spans(bv, xs, Found(defs_nil(), 0, nm, t, cur_none(), g), fi)
      val st2 = end_def(st, fi)
      val () = spans_free(xs)
      val () = $A.drop<byte>(fz, bv)
      val+ ~Found(ds, kd, nm2, t2, c, g2) = st2
      val () = (case+ c of
        | ~cur_none() => ()
        | ~cur_def(a, _, _, _, _, _, _, oc) => let
            val () = $A.free<byte>(a)
          in occs_free(oc) end): void
    in Pkg(pfiles_cons(fi, $A.thaw<byte>(fz), kd, ds, pf), nm2, t2, g2) end

(* pk with each file of the NUL-separated list files[off, len) *)
fun add_files {lf:agz}{off:nat | off <= RMAX} .<RMAX - off>.
  (files: !$A.borrow(byte, lf, RMAX), off: int off, len: int, pk: pkg): pkg =
  if off >= len then pk
  else let
    val e = $S.find_null_bv_at(files, off, RMAX)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, RMAX, pb)
    val @(pa, _) = $B.to_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val pk2 = add_file(bv_p, off, pk)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in
    if e >= RMAX then pk2 else add_files(files, e + 1, len, pk2)
  end

(* ============================================================
   The call graph
   ============================================================ *)

(* The definitions a definition calls, each by its id j < N *)
datavtype elist(N:int, int) =
  | elist_nil(N, 0) of ()
  | {c:nat}{j:nat | j < N} elist_cons(N, c + 1) of (int j, elist(N, c))

fun elist_free {N:int}{c:nat} .<c>. (xs: elist(N, c)): void =
  case+ xs of
  | ~elist_nil() => ()
  | ~elist_cons(_, tl) => elist_free(tl)

(* A definition of the graph: its id, whether it is an implement, and
   what it calls *)
datavtype node(N:int) =
  | {i:nat | i < N}{c:nat} Node(N) of (int i, bool, elist(N, c))

datavtype nodes(N:int, int) =
  | nodes_nil(N, 0) of ()
  | {c:nat} nodes_cons(N, c + 1) of (node(N), nodes(N, c))

fun nodes_free {N:int}{c:nat} .<c>. (xs: nodes(N, c)): void =
  case+ xs of
  | ~nodes_nil() => ()
  | ~nodes_cons(nd, tl) => let
      val+ ~Node(_, _, es) = nd
      val () = elist_free(es)
    in nodes_free(tl) end

(* Whether a[0, k) and src[s, s + k) hold the same bytes *)
fun same_bytes {la,l:agz}{k:nat | k <= 256}{s:nat | s + k <= RMAX}{i:nat | i <= k} .<k - i>.
  (a: !$A.arr(byte, la, 256), k: int k, src: !$A.arr(byte, l, RMAX), s: int s, i: int i): bool =
  if i >= k then true
  else if byte2int0($A.get<byte>(a, i)) = byte2int0($A.get<byte>(src, s + i)) then
    same_bytes(a, k, src, s, i + 1)
  else false

(* Whether the identifier src[s, e) of file fi, in a body of group grp,
   calls the definition d *)
fn calls {l:agz}{s,e:nat | s <= e; e <= RMAX}
  (d: !dname, src: !$A.arr(byte, l, RMAX), s: int s, e: int e, fi: spos(RMAX), grp: int): bool = let
  val+ @DName(a, k, global, dfi, dgrp) = d
  val len = (if e - s > 256 then 256 else e - s): [n:nat | n <= 256; n <= e - s] int n
  val r = (if ~global && dfi <> fi then false
           else if grp > 0 && grp = dgrp then false
           else if len <> k then false
           else same_bytes(a, k, src, s, 0)): bool
  prval () = fold@(d)
in r end

(* The definitions of nm (ids i, i + 1, ...) that src[s, e) calls,
   added to acc *)
fun calls_of {N:int}{m,i:nat | i + m == N}{l:agz}{s,e:nat | s <= e; e <= RMAX}{c:nat} .<m>.
  (nm: !dnames(m), i: int i, src: !$A.arr(byte, l, RMAX), s: int s, e: int e,
   fi: spos(RMAX), grp: int, acc: elist(N, c)): [c2:nat] elist(N, c2) =
  case+ nm of
  | dnames_nil() => acc
  | dnames_cons(d, tl) =>
    if calls(d, src, s, e, fi, grp) then calls_of(tl, i + 1, src, s, e, fi, grp, elist_cons(i, acc))
    else calls_of(tl, i + 1, src, s, e, fi, grp, acc)

(* What the identifiers oc of a body in file fi, group grp, call *)
fun occs_calls {N:nat}{l:agz}{j:nat}{c:nat} .<j>.
  (oc: !occs(j), nm: !dnames(N), src: !$A.arr(byte, l, RMAX), fi: spos(RMAX), grp: int, acc: elist(N, c))
  : [c2:nat] elist(N, c2) =
  case+ oc of
  | occs_nil() => acc
  | occs_cons(s, e, tl) =>
    occs_calls(tl, nm, src, fi, grp, calls_of(nm, 0, src, s, e, fi, grp, acc))

(* The nodes of the definitions ds of file fi (ids i, i + 1, ...),
   added to acc *)
fun def_nodes {N:nat}{k,i:nat | i + k <= N}{l:agz}{c:nat} .<k>.
  (ds: !defs(k), i: int i, nm: !dnames(N), src: !$A.arr(byte, l, RMAX), fi: spos(RMAX), acc: nodes(N, c))
  : [c2:nat] nodes(N, c2) =
  case+ ds of
  | defs_nil() => acc
  | defs_cons(d, tl) => let
      val+ @Def(impl, grp, _, _, _, oc) = d
      val es = occs_calls(oc, nm, src, fi, grp, elist_nil())
      val nd = Node(i, impl, es)
      prval () = fold@(d)
    in def_nodes(tl, i + 1, nm, src, fi, nodes_cons(nd, acc)) end

(* The nodes of the files pf, whose definitions have ids i, i + 1, ... *)
fun file_nodes {N:nat}{t,f,i:nat | i + t == N}{c:nat} .<f>.
  (pf: !pfiles(t, f), i: int i, nm: !dnames(N), acc: nodes(N, c)): [c2:nat] nodes(N, c2) =
  case+ pf of
  | pfiles_nil() => acc
  | pfiles_cons(fi, src, k, ds, tl) => let
      val acc2 = def_nodes(ds, i, nm, src, fi, acc)
    in file_nodes(tl, i + k, nm, acc2) end

(* ============================================================
   Cycles
   ============================================================ *)

datavtype nodes_n(N:int) =
  | {c:nat} NodesN(N) of (nodes(N, c), int c)

(* Whether es holds j with mark[j] *)
fun any_marked {N:nat}{lm:agz}{c:nat} .<c>. (es: !elist(N, c), mark: !$A.arr(bool, lm, N)): bool =
  case+ es of
  | elist_nil() => false
  | elist_cons(j, tl) => if $A.get<bool>(mark, j) then true else any_marked(tl, mark)

(* Whether es holds x or some j with mark[j] *)
fun calls_into {N:nat}{lm:agz}{c:nat} .<c>.
  (es: !elist(N, c), x: int, mark: !$A.arr(bool, lm, N)): bool =
  case+ es of
  | elist_nil() => false
  | elist_cons(j, tl) =>
    if j = x then true
    else if $A.get<bool>(mark, j) then true
    else calls_into(tl, x, mark)

(* Whether es holds a j that is not dead *)
fun has_live {N:nat}{lm:agz}{c:nat} .<c>. (es: !elist(N, c), dead: !$A.arr(bool, lm, N)): bool =
  case+ es of
  | elist_nil() => false
  | elist_cons(j, tl) => if $A.get<bool>(dead, j) then has_live(tl, dead) else true

(* One round of taking out the nodes of xs that call no live node (dead
   marks the others): the kept ones added to kept (a of them) *)
fun prune_round {N:nat}{lm:agz}{c,a:nat} .<c>.
  (xs: nodes(N, c), dead: !$A.arr(bool, lm, N), kept: nodes(N, a), ka: int a)
  : [a2:nat | a2 <= a + c] @(nodes(N, a2), int a2) =
  case+ xs of
  | ~nodes_nil() => @(kept, ka)
  | ~nodes_cons(nd, tl) => let
      val+ @Node(i, _, es) = nd
      val live = has_live(es, dead)
      val () = (if live then () else $A.set<bool>(dead, i, true))
      prval () = fold@(nd)
    in
      if live then prune_round(tl, dead, nodes_cons(nd, kept), ka + 1)
      else let
        val+ ~Node(_, _, es2) = nd
        val () = elist_free(es2)
      in prune_round(tl, dead, kept, ka) end
    end

(* The nodes of xs that reach a cycle: those left when the nodes that
   call no live node are taken out until none is *)
fun prune {N:nat}{lm:agz}{c:nat} .<c>.
  (xs: nodes(N, c), c: int c, dead: !$A.arr(bool, lm, N)): nodes_n(N) = let
  val @(kept, a) = prune_round(xs, dead, nodes_nil(), 0)
in
  if a >= c then NodesN(kept, a) else prune(kept, a, dead)
end

(* One round of marking the nodes of xs that call x or a marked node
   (moved to done); the others added to rest (a of them) *)
fun reach_round {N:nat}{lm:agz}{c,a,d:nat} .<c>.
  (xs: nodes(N, c), x: int, mark: !$A.arr(bool, lm, N),
   rest: nodes(N, a), ka: int a, done: nodes(N, d))
  : [a2,d2:nat | a2 <= a + c] @(nodes(N, a2), int a2, nodes(N, d2)) =
  case+ xs of
  | ~nodes_nil() => @(rest, ka, done)
  | ~nodes_cons(nd, tl) => let
      val+ @Node(i, _, es) = nd
      val hit = calls_into(es, x, mark)
      val () = (if hit then $A.set<bool>(mark, i, true) else ())
      prval () = fold@(nd)
    in
      if hit then reach_round(tl, x, mark, rest, ka, nodes_cons(nd, done))
      else reach_round(tl, x, mark, nodes_cons(nd, rest), ka + 1, done)
    end

fun nodes_len {N:int}{c:nat}{i:nat} .<c>. (xs: !nodes(N, c), i: int i): int (c + i) =
  case+ xs of
  | nodes_nil() => i
  | nodes_cons(_, tl) => nodes_len(tl, i + 1)

fun nodes_append {N:int}{a,d:nat} .<a>. (xs: nodes(N, a), ys: nodes(N, d)): nodes(N, a + d) =
  case+ xs of
  | ~nodes_nil() => ys
  | ~nodes_cons(nd, tl) => nodes_cons(nd, nodes_append(tl, ys))

(* mark set on each node of xs that calls x, directly or through the
   others; xs given back, as a whole *)
fun reach {N:nat}{lm:agz}{c,d:nat} .<c>.
  (xs: nodes(N, c), c: int c, x: int, mark: !$A.arr(bool, lm, N), done: nodes(N, d)): nodes_n(N) = let
  val @(rest, a, done2) = reach_round(xs, x, mark, nodes_nil(), 0, done)
in
  if a >= c then let
    val all = nodes_append(rest, done2)
    val n = nodes_len(all, 0)
  in NodesN(all, n) end
  else reach(rest, a, x, mark, done2)
end

(* mark cleared for each node of xs *)
fun clear_marks {N:nat}{lm:agz}{c:nat} .<c>. (xs: !nodes(N, c), mark: !$A.arr(bool, lm, N)): void =
  case+ xs of
  | nodes_nil() => ()
  | nodes_cons(nd, tl) => let
      val+ @Node(i, _, _) = nd
      val () = $A.set<bool>(mark, i, false)
      prval () = fold@(nd)
    in clear_marks(tl, mark) end

(* The ids of the implements of xs *)
datavtype ids(N:int, int) =
  | ids_nil(N, 0) of ()
  | {c:nat}{j:nat | j < N} ids_cons(N, c + 1) of (int j, ids(N, c))

fun impl_ids {N:int}{c,a:nat} .<c>. (xs: !nodes(N, c), acc: ids(N, a)): [a2:nat] ids(N, a2) =
  case+ xs of
  | nodes_nil() => acc
  | nodes_cons(nd, tl) => let
      val+ @Node(i, impl, _) = nd
      val acc2 = (if impl then ids_cons(i, acc) else acc): [a2:nat] ids(N, a2)
      prval () = fold@(nd)
    in impl_ids(tl, acc2) end

(* cyc set for each implement of cs that is on a cycle of the nodes rs *)
fun mark_cycles {N:nat}{lm,lc:agz}{a:nat} .<a>.
  (cs: ids(N, a), rs: nodes_n(N), mark: !$A.arr(bool, lm, N), cyc: !$A.arr(bool, lc, N)): nodes_n(N) =
  case+ cs of
  | ~ids_nil() => rs
  | ~ids_cons(x, tl) => let
      val+ ~NodesN(xs, c) = rs
      val rs2 = reach(xs, c, x, mark, nodes_nil())
      val () = (if $A.get<bool>(mark, x) then $A.set<bool>(cyc, x, true) else ())
      val+ @NodesN(ys, _) = rs2
      val () = clear_marks(ys, mark)
      prval () = fold@(rs2)
    in mark_cycles(tl, rs2, mark, cyc) end

(* ============================================================
   The implements on a cycle
   ============================================================ *)

(* The implements on a cycle: each one's file (its path's offset in
   the file list), keyword and name *)






implement cycle_hits_free {k} (xs) = let
  fun loop {k:nat} .<k>. (xs: cycle_hits(k)): void =
    case+ xs of
    | ~cycle_hits_nil() => ()
    | ~cycle_hits_cons(_, _, _, _, tl) => loop(tl)
in loop(xs) end

(* The hits among the definitions ds of file fi (ids i, i + 1, ...) *)
fun def_hits {N:nat}{k,i:nat | i + k <= N}{lc:agz}{h:nat} .<k>.
  (ds: !defs(k), i: int i, fi: spos(RMAX), cyc: !$A.arr(bool, lc, N), acc: cycle_hits(h))
  : [h2:nat] cycle_hits(h2) =
  case+ ds of
  | defs_nil() => acc
  | defs_cons(d, tl) => let
      val+ @Def(_, _, kw, ns, ne, _) = d
      val acc2 = (if $A.get<bool>(cyc, i) then cycle_hits_cons(fi, kw, ns, ne, acc) else acc)
        : [h2:nat] cycle_hits(h2)
      prval () = fold@(d)
    in def_hits(tl, i + 1, fi, cyc, acc2) end

fun file_hits {N:nat}{t,f,i:nat | i + t == N}{lc:agz}{h:nat} .<f>.
  (pf: !pfiles(t, f), i: int i, cyc: !$A.arr(bool, lc, N), acc: cycle_hits(h)): [h2:nat] cycle_hits(h2) =
  case+ pf of
  | pfiles_nil() => acc
  | pfiles_cons(fi, _, k, ds, tl) => file_hits(tl, i + k, cyc, def_hits(ds, i, fi, cyc, acc))

(* The hits of the N definitions of pf, whose names are nm *)
fn graph_hits {N:pos | N <= 1048576}{f:nat}
  (pf: !pfiles(N, f), nm: !dnames(N), n: int N): [h:nat] cycle_hits(h) = let
  val ns = file_nodes(pf, 0, nm, nodes_nil())
  val dead = $A.alloc<bool>(n)
  val c = nodes_len(ns, 0)
  val rs = prune(ns, c, dead)
  val () = $A.free<bool>(dead)
  val+ @NodesN(rxs, _) = rs
  val cs = impl_ids(rxs, ids_nil())
  prval () = fold@(rs)
  val mark = $A.alloc<bool>(n)
  val cyc = $A.alloc<bool>(n)
  val rs2 = mark_cycles(cs, rs, mark, cyc)
  val+ ~NodesN(all, _) = rs2
  val () = nodes_free(all)
  val () = $A.free<bool>(mark)
  val hs = file_hits(pf, 0, cyc, cycle_hits_nil())
  val () = $A.free<bool>(cyc)
in hs end

(* The implements on a cycle, and whether there were more than 1048576
   definitions (then none is looked at) *)



(* The implements on a call cycle among the definitions of the .bats
   files in the NUL-separated list files[off, len) *)



implement implement_cycles (files, off, len) = let
  val pk = add_files(files, off, len, Pkg(pfiles_nil(), dnames_nil(), 0, 0))
  val+ ~Pkg(pf, nm, t, _) = pk
in
  if t <= 0 then let
    val () = pfiles_free(pf)
    val () = dnames_free(nm)
  in Cycles(cycle_hits_nil(), false) end
  else if t > 1048576 then let
    val () = pfiles_free(pf)
    val () = dnames_free(nm)
  in Cycles(cycle_hits_nil(), true) end
  else let
    val hs = graph_hits(pf, nm, t)
    val () = pfiles_free(pf)
    val () = dnames_free(nm)
  in Cycles(hs, false) end
end
