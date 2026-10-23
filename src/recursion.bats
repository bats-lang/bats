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

#use arith as AR
#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "lexer.sats"

#define RMAX 524288

(* ============================================================
   Definitions
   ============================================================ *)

(* The identifiers a body mentions: src[s, e) each *)
datavtype occs(n:int, int) =
  | occs_nil(n, 0) of ()
  | {k:nat}{s,e:nat | s <= e; e <= n} occs_cons(n, k + 1) of (int s, int e, occs(n, k))

fun occs_free {n:int}{k:nat} .<k>. (xs: occs(n, k)): void =
  case+ xs of
  | ~occs_nil() => ()
  | ~occs_cons(_, _, tl) => occs_free(tl)

(* A top-level definition: whether it is an implement, its group (0 for
   an implement; a fn has one of its own, a fun group one for all its
   members), its keyword's start, its name src[ns, ne) and its body's
   identifiers *)
datavtype def(n:int) =
  | {k:nat}{s,e:nat | s <= e; e <= n} Def(n) of (bool, int, spos(n), int s, int e, occs(n, k))

datavtype defs(n:int, int) =
  | defs_nil(n, 0) of ()
  | {k:nat} defs_cons(n, k + 1) of (def(n), defs(n, k))

fun defs_free {n:int}{k:nat} .<k>. (xs: defs(n, k)): void =
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
datavtype cur(n:int) =
  | cur_none(n) of ()
  | {l:agz}{k:nat | k <= 256}{j:nat}{s,e:nat | s <= e; e <= n}
    cur_def(n) of ($A.arr(byte, l, 256), int k, bool, int, spos(n), int s, int e, occs(n, j))

(* What the scan has found: the current file's definitions (k), the
   names of every definition so far (m; m - k of them in earlier
   files), the definition being read, and the last group *)
datavtype found(n:int, int, int) =
  | {k,m:nat} Found(n, k, m) of (defs(n, k), int k, dnames(m), int m, cur(n), int)

(* The package's files: each one's path (its offset in the file list),
   its source (read whole, read_whole) and its definitions; t of them in
   all *)
datavtype pfiles(int, int) =
  | {la,l:agz}{n:pos}{k,t,f:nat} pfiles_cons(t + k, f + 1) of
      (spos(RMAX), $A.arena(byte, la, n, n, 1), $A.arrx(byte, l, n, la), int n, int k, defs(n, k), pfiles(t, f))
  | pfiles_nil(0, 0) of ()

fun pfiles_free {t,f:nat} .<f>. (xs: pfiles(t, f)): void =
  case+ xs of
  | ~pfiles_nil() => ()
  | ~pfiles_cons(_, ar, a, _, _, ds, tl) => let
      val () = whole_free(ar, a)
      val () = defs_free(ds)
    in pfiles_free(tl) end

(* ============================================================
   Reading definitions from the spans
   ============================================================ *)

fn is_ident_start (b: int): bool =
  (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b = 95

(* The byte at p *)
fn rb {n:pos}{l:agz}{p:nat | p < n} (bv: !$A.borrow(byte, l, n), p: int p): int =
  byte2int0($A.read<byte>(bv, p))

(* The end of the identifier that starts at p, within [p, e) *)
fun ident_end {n:pos}{l:agz}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val c = rb(bv, p)
  in
    if is_ident_byte(c) then ident_end(bv, p + 1, e)
    else if c = 39 then ident_end(bv, p + 1, e)
    else p
  end

(* The first position of [p, e) past blanks and {...} groups *)
fun skip_head {n:pos}{l:agz}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, depth: int): [q:nat | p <= q; q <= e] int q =
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
fn word_is {n:pos}{l:agz}{p,q:nat | p <= q; q <= n}{m:pos | m <= 16}
  (bv: !$A.borrow(byte, l, n), sn: int n, p: int p, q: int q, kw: &(@[char][m]), m: int m): bool =
  if q - p <> m then false else lit_at(bv, p, sn, kw, m)

(* What a word at the start of a line begins: an implement, a fn, a fun
   or fnx (a new group), an and (the group goes on), or no definition *)
datatype definition = ImplementDefinition | FnDefinition | FunGroup | AndMember | NoDefinition

(* What the word src[p, q) at the start of a line begins *)
fn def_kind {n:pos}{l:agz}{p,q:nat | p <= q; q <= n}
  (bv: !$A.borrow(byte, l, n), sn: int n, p: int p, q: int q): definition = let
  var impl_c = @[char][9]('i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
  var fn_c = @[char][2]('f', 'n')
  var fun_c = @[char][3]('f', 'u', 'n')
  var fnx_c = @[char][3]('f', 'n', 'x')
  var and_c = @[char][3]('a', 'n', 'd')
in
  if word_is(bv, sn, p, q, impl_c, 9) then ImplementDefinition()
  else if word_is(bv, sn, p, q, fn_c, 2) then FnDefinition()
  else if word_is(bv, sn, p, q, fun_c, 3) then FunGroup()
  else if word_is(bv, sn, p, q, fnx_c, 3) then FunGroup()
  else if word_is(bv, sn, p, q, and_c, 3) then AndMember()
  else NoDefinition()
end

(* src[s, e) (its first 256 bytes) into a name array *)
fun copy_name {n:pos}{l,la:agz}{s,e:nat | s <= e; e <= n}{i:nat | i <= 256} .<256 - i>.
  (bv: !$A.borrow(byte, l, n), s: int s, e: int e, a: !$A.arr(byte, la, 256), i: int i)
  : [k:nat | k <= 256] int k =
  if i >= 256 then i
  else if s + i >= e then i
  else let
    val () = $A.set<byte>(a, i, $A.read<byte>(bv, s + i))
  in copy_name(bv, s, e, a, i + 1) end

(* The definition being read, if any, added to the found ones *)
fn end_def {n:pos}{k,m:nat} (st: found(n, k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(n, k2, m2) = let
  val+ ~Found(ds, kd, nm, km, c, g) = st
in
  case+ c of
  | ~cur_none() => Found(ds, kd, nm, km, cur_none(), g)
  | ~cur_def(a, nk, impl, grp, kw, ns, ne, oc) =>
    Found(defs_cons(Def(impl, grp, kw, ns, ne, oc), ds), kd + 1,
          dnames_cons(DName(a, nk, impl, fi, grp), nm), km + 1, cur_none(), g)
end

(* The end of the name that starts at p (p itself when none does) *)
fn name_end {n:pos}{l:agz}{p,e:nat | p <= e; e <= n}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_ident_start(rb(bv, p)) then ident_end(bv, p, e)
  else p

(* A new definition of kind kd (def_kind) whose keyword is src[kw, q),
   its name after it within [q, e); the position after the name *)
fn start_def {n:pos}{l:agz}{k,m:nat}{kw,q,e:nat | kw <= q; q <= e; e <= n}
  (bv: !$A.borrow(byte, l, n), st: found(n, k, m), kind: definition, kw: int kw, q: int q, e: int e, fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] @(found(n, k2, m2), [r:nat | q <= r; r <= e] int r) = let
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
  val is_implement = (case+ kind of ImplementDefinition() => true | _ => false): bool
  val g2 = (case+ kind of
    | AndMember() => (if g > 0 then g else 1)
    | ImplementDefinition() => g
    | _ => g + 1): int
  val grp = (if is_implement then 0 else g2): int
in
  @(Found(ds, kd, nm, km, cur_def(a, nk, is_implement, grp, kw, ns, ne, occs_nil()), g2), ne)
end

(* The identifier src[s, e) added to the body being read *)
fn add_occ {n:pos}{k,m:nat}{s,e:nat | s <= e; e <= n} (st: found(n, k, m), s: int s, e: int e): found(n, k, m) = let
  val+ ~Found(ds, kd, nm, km, c, g) = st
in
  case+ c of
  | ~cur_none() => Found(ds, kd, nm, km, cur_none(), g)
  | ~cur_def(a, nk, impl, grp, kw, ns, ne, oc) =>
    Found(ds, kd, nm, km, cur_def(a, nk, impl, grp, kw, ns, ne, occs_cons(s, e, oc)), g)
end

(* Whether p starts a line *)
fn line_start {n:pos}{l:agz}{p:nat | p < n} (bv: !$A.borrow(byte, l, n), p: int p): bool =
  if p = 0 then true else rb(bv, p - 1) = 10

(* Whether the byte before p makes an identifier at p part of something
   else: an identifier, a number, a field (.x) or a qualified name ($X) *)
fn joined {n:pos}{l:agz}{p:nat | p < n} (bv: !$A.borrow(byte, l, n), p: int p): bool =
  if p = 0 then false
  else let
    val c = rb(bv, p - 1)
  in is_ident_byte(c) || c = 39 || c = 46 || c = 36 end

(* The definitions and identifiers of the code src[p, e) *)
fun scan_code {n:pos}{l:agz}{k,m:nat}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), sn: int n, p: int p, e: int e, st: found(n, k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(n, k2, m2) =
  if p >= e then st
  else if ~is_ident_start(rb(bv, p)) then scan_code(bv, sn, p + 1, e, st, fi)
  else if joined(bv, p) then scan_code(bv, sn, ident_end(bv, p + 1, e), e, st, fi)
  else let
    val q = ident_end(bv, p + 1, e)
    val kind = (if line_start(bv, p) then def_kind(bv, sn, p, q) else NoDefinition()): definition
  in
    if (case+ kind of NoDefinition() => false | _ => true) then let
      val @(st2, r) = start_def(bv, st, kind, p, q, e, fi)
    in scan_code(bv, sn, r, e, st2, fi) end
    else scan_code(bv, sn, q, e, add_occ(st, p, q), fi)
  end

(* The definitions and identifiers of the span sp: code is read, a
   comment, string, qualified name or construct is not, and anything
   else (a #pub declaration, a #use, a $UNSAFE block, a block's begin or
   end) ends the definition being read *)
fn scan_span {n:pos}{l:agz}{k,m:nat}
  (bv: !$A.borrow(byte, l, n), sn: int n, sp: !span(n), st: found(n, k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(n, k2, m2) =
  case+ sp of
  | SPass(s, e, verbatim) =>
    if verbatim then st else scan_code(bv, sn, s, e, st, fi)
  | SQual(_, _, _, _, _, _) => st
  | SConstruct(_, _) => st
  | SLexError(_, _, _, _, _) => st
  | _ => end_def(st, fi)

fun scan_spans {n:pos}{l:agz}{k,m:nat}{j:nat} .<j>.
  (bv: !$A.borrow(byte, l, n), sn: int n, xs: !spans(n, j), st: found(n, k, m), fi: spos(RMAX))
  : [k2,m2:nat | m2 - m == k2 - k] found(n, k2, m2) =
  case+ xs of
  | spans_nil() => st
  | spans_cons(sp, tl) => scan_spans(bv, sn, tl, scan_span(bv, sn, sp, st, fi), fi)

(* ============================================================
   The package's files
   ============================================================ *)

(* What the files read so far hold: t definitions in all, their files
   and names, and the last group *)
datavtype pkg =
  | {t,f:nat} Pkg of (pfiles(t, f), dnames(t), int t, int)

(* ============================================================
   The files scanned in this process (bats#405)
   ============================================================ *)

(* scan memo (recursion.md): a file's definitions kept while its path and bytes are the same *)

(* xs, copied onto acc, the last first *)
fun occs_copy_rev {n:int}{j,c:nat} .<j>. (xs: !occs(n, j), acc: occs(n, c)): occs(n, c + j) =
  case+ xs of
  | occs_nil() => acc
  | occs_cons(s, e, tl) => occs_copy_rev(tl, occs_cons(s, e, acc))

fun occs_rev {n:int}{a,b:nat} .<a>. (xs: occs(n, a), acc: occs(n, b)): occs(n, a + b) =
  case+ xs of
  | ~occs_nil() => acc
  | ~occs_cons(s, e, tl) => occs_rev(tl, occs_cons(s, e, acc))

fn occs_copy {n:int}{j:nat} (xs: !occs(n, j)): occs(n, j) =
  occs_rev(occs_copy_rev(xs, occs_nil()), occs_nil())

(* ds, copied onto acc, the last first, each group (an implement has none) moved by off *)
fun defs_copy_rev {n:int}{k,m:nat} .<k>.
  (ds: !defs(n, k), off: int, acc: defs(n, m)): defs(n, m + k) =
  case+ ds of
  | defs_nil() => acc
  | defs_cons(d, tl) => let
      val+ @Def(impl, grp, kw, ns, ne, oc) = d
      val copy = Def(impl, (if grp > 0 then grp + off else grp), kw, ns, ne, occs_copy(oc))
      prval () = fold@(d)
    in defs_copy_rev(tl, off, defs_cons(copy, acc)) end

fun defs_rev {n:int}{a,b:nat} .<a>. (xs: defs(n, a), acc: defs(n, b)): defs(n, a + b) =
  case+ xs of
  | ~defs_nil() => acc
  | ~defs_cons(d, tl) => defs_rev(tl, defs_cons(d, acc))

(* The names of ds (file fi, bytes bv), the last first, added to acc *)
fun names_rev {n:pos}{l:agz}{k,m:nat} .<k>.
  (ds: !defs(n, k), bv: !$A.borrow(byte, l, n), fi: spos(RMAX), acc: dnames(m)): dnames(m + k) =
  case+ ds of
  | defs_nil() => acc
  | defs_cons(d, tl) => let
      val+ @Def(impl, grp, _, ns, ne, _) = d
      val a = $A.alloc<byte>(256)
      val name_len = copy_name(bv, ns, ne, a, 0)
      val nd = DName(a, name_len, impl, fi, grp)
      prval () = fold@(d)
    in names_rev(tl, bv, fi, dnames_cons(nd, acc)) end

(* xs, moved onto acc in the opposite order *)
fun dnames_rev {a,b:nat} .<a>. (xs: dnames(a), acc: dnames(b)): dnames(a + b) =
  case+ xs of
  | ~dnames_nil() => acc
  | ~dnames_cons(d, tl) => dnames_rev(tl, dnames_cons(d, acc))

(* One file's scan: path, own copy of the bytes, definitions, groups around it, last use *)
datavtype scanned =
  | {path_loc:agz}{path_cap:pos}{path_len:nat | path_len <= path_cap}
    {arena_loc,source_loc:agz}{size:pos}{def_count:nat}
    Scanned of ($A.arr(byte, path_loc, path_cap), int path_len,
                $A.arena(byte, arena_loc, size, size, 1),
                $A.arrx(byte, source_loc, size, arena_loc), int size, int def_count,
                defs(size, def_count), int, int, int)

datavtype scans(int) =
  | scans_nil(0) of ()
  | {c:nat} scans_cons(c + 1) of (scanned, scans(c))

vtypedef scans_v = [c:nat] scans(c)

val g_scans = ref<scans_v>(scans_nil())
val g_remember = ref<bool>(false)
val g_scan_run = ref<int>(0)

(* A scan is kept for this many calls of implement_cycles after its last use *)
#define SCAN_KEEP 64

fun scans_free {c:nat} .<c>. (xs: scans(c)): void =
  case+ xs of
  | ~scans_nil() => ()
  | ~scans_cons(entry, tl) => let
      val+ ~Scanned(path, _, arena, source, _, _, ds, _, _, _) = entry
      val () = $A.free<byte>(path)
      val () = whole_free(arena, source)
      val () = defs_free(ds)
    in scans_free(tl) end

(* The scans used within SCAN_KEEP calls before run *)
fun scans_trim {c:nat} .<c>. (xs: scans(c), run: int): [c2:nat] scans(c2) =
  case+ xs of
  | ~scans_nil() => scans_nil()
  | ~scans_cons(entry, tl) => let
      val rest = scans_trim(tl, run)
      val+ @Scanned(_, _, _, _, _, _, _, _, _, last_used) = entry
      val keep = (run - last_used <= SCAN_KEEP): bool
    in
      if keep then let
        prval () = fold@(entry)
      in scans_cons(entry, rest) end
      else let
        prval () = fold@(entry)
        val+ ~Scanned(path, _, arena, source, _, _, ds, _, _, _) = entry
        val () = $A.free<byte>(path)
        val () = whole_free(arena, source)
        val () = defs_free(ds)
      in rest end
    end

(* Whether p[0, pm) and path[0, path_len) hold the same bytes *)
fun same_path {lp:agz}{np:pos}{pm:nat | pm <= np}{path_loc:agz}{path_cap:pos}
  {path_len:nat | path_len <= path_cap}{i:nat | i <= pm} .<pm - i>.
  (p: !$A.borrow(byte, lp, np), pm: int pm, path: !$A.arr(byte, path_loc, path_cap),
   path_len: int path_len, i: int i): bool =
  if i >= pm then pm = path_len
  else if i >= path_len then false
  else if byte2int0($A.read<byte>(p, i)) = byte2int0($A.get<byte>(path, i)) then
    same_path(p, pm, path, path_len, i + 1)
  else false

(* Whether bv[i, n) and source[i, n) hold the same bytes *)
fun same_source {l:agz}{n:pos}{ls,o:agz}{i:nat | i <= n} .<n - i>.
  (bv: !$A.borrow(byte, l, n), source: !$A.arrx(byte, ls, n, o), n: int n, i: int i): bool =
  if i >= n then true
  else if byte2int0($A.read<byte>(bv, i)) = byte2int0($A.get<byte>(source, i)) then
    same_source(bv, source, n, i + 1)
  else false

(* dst[i, n) set to the bytes of bv *)
fun copy_source {l:agz}{n:pos}{ld,o:agz}{i:nat | i <= n} .<n - i>.
  (dst: !$A.arrx(byte, ld, n, o), bv: !$A.borrow(byte, l, n), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = $A.set<byte>(dst, i, $A.read<byte>(bv, i))
  in copy_source(dst, bv, n, i + 1) end

(* The kept scan of the file at p[0, pm), bytes bv, after group g: its state and true, else false *)
fun scans_use {c:nat}{lp:agz}{np:pos}{pm:nat | pm <= np}{l:agz}{n:pos}{t:nat} .<c>.
  (xs: !scans(c), p: !$A.borrow(byte, lp, np), pm: int pm, bv: !$A.borrow(byte, l, n), sn: int n,
   run: int, fi: spos(RMAX), nm: dnames(t), t: int t, g: int)
  : [k:nat] @(found(n, k, t + k), bool) =
  case+ xs of
  | scans_nil() => @(Found(defs_nil(), 0, nm, t, cur_none(), g), false)
  | scans_cons(entry, tl) => let
      val+ @Scanned(path, path_len, arena, source, size, def_count, ds,
                    group_before, group_after, last_used) = entry
    in
      if same_path(p, pm, path, path_len, 0)
         && (if g > 0 then group_before > 0 else group_before <= 0) then
        (if size <> sn then let
            prval () = fold@(entry)
          in scans_use(tl, p, pm, bv, sn, run, fi, nm, t, g) end
        else if same_source(bv, source, sn, 0) then let
            val () = last_used := run
            val off = g - group_before
            val fresh = defs_rev(defs_copy_rev(ds, off, defs_nil()), defs_nil())
            val names = dnames_rev(names_rev(fresh, bv, fi, dnames_nil()), nm)
            val after = group_after + off
            val kept = def_count
            prval () = fold@(entry)
          in @(Found(fresh, kept, names, t + kept, cur_none(), after), true) end
        else let
            prval () = fold@(entry)
          in scans_use(tl, p, pm, bv, sn, run, fi, nm, t, g) end)
      else let
        prval () = fold@(entry)
      in scans_use(tl, p, pm, bv, sn, run, fi, nm, t, g) end
    end

(* xs with the scan of the file at p[0, pm) added: definitions ds, groups before and after it *)
fn scans_add {c:nat}{lp:agz}{np:pos}{pm:nat | pm <= np}{l:agz}{n:pos}{def_count:nat}
  (xs: scans(c), p: !$A.borrow(byte, lp, np), pm: int pm, bv: !$A.borrow(byte, l, n), sn: int n,
   ds: !defs(n, def_count), def_count: int def_count, group_before: int, group_after: int,
   run: int): [c2:nat] scans(c2) =
  if sn > 268435456 then xs
  else case+ $A.arena_create<byte>(sn) of
  | ~$A.arena_none() => xs
  | ~$A.arena_some(arena) => let
      val piece = $A.arena_alloc<byte>(arena, sn)
      val () = copy_source(piece, bv, sn, 0)
      var path_builder : $B.builder_v = $B.create()
      val () = copy_to_builder_v(p, 0, pm, pm, path_builder)
      val @(path, path_len) = $B.into_arr(path_builder)
      val copy = defs_rev(defs_copy_rev(ds, 0, defs_nil()), defs_nil())
    in
      scans_cons(Scanned(path, path_len, arena, piece, sn, def_count, copy,
                         group_before, group_after, run), xs)
    end

(* The scans taken out of their place (nothing is in it until they are put back) *)
fn scans_take (): scans_v = let
  var taken : scans_v = scans_nil()
  val () = ref_exch_elt<scans_v>(g_scans, taken)
in taken end

fn scans_put (xs: scans_v): void = let
  var back : scans_v = xs
  val () = ref_exch_elt<scans_v>(g_scans, back)
in scans_free(back) end

(* From now on keep the scans of the files for the next call (bats fixtures) *)
#pub fn remember_scans (): void

implement remember_scans () = !g_remember := true

(* xs with the scan the state st holds (the file at p[0, pm), bytes bv, after group g) added *)
fn scans_add_found {lp:agz}{np:pos}{pm:nat | pm <= np}{l:agz}{n:pos}{k,m:nat}
  (xs: scans_v, p: !$A.borrow(byte, lp, np), pm: int pm, bv: !$A.borrow(byte, l, n), sn: int n,
   st: !found(n, k, m), g: int, run: int): scans_v = let
  val+ @Found(ds, def_count, _, _, _, group_after) = st
  val r = scans_add(xs, p, pm, bv, sn, ds, def_count, g, group_after, run)
  prval () = fold@(st)
in r end

(* xs, with the scan of st added when this process remembers them, unless it came from xs *)
fn scans_keep {lp:agz}{np:pos}{pm:nat | pm <= np}{l:agz}{n:pos}{k,m:nat}
  (xs: scans_v, remember: bool, hit: bool, p: !$A.borrow(byte, lp, np), pm: int pm,
   bv: !$A.borrow(byte, l, n), sn: int n, st: !found(n, k, m), g: int, run: int): scans_v =
  if hit || ~remember then xs else scans_add_found(xs, p, pm, bv, sn, st, g, run)

(* The definitions of the file at p[0, pm), bytes bv[0, len), added to nm (t names) after group g *)
fn scan_file {lp:agz}{np:pos}{pm:nat | pm <= np}{l:agz}{n:pos}{m:nat | m <= n}{t:nat}
  (p: !$A.borrow(byte, lp, np), pm: int pm, bv: !$A.borrow(byte, l, n), sn: int n, len: int m,
   fi: spos(RMAX), nm: dnames(t), t: int t, g: int): [k:nat] found(n, k, t + k) = let
  val remember = !g_remember
  val run = !g_scan_run
  val memo = scans_take()
  val @(st0, hit) = (if remember then scans_use(memo, p, pm, bv, sn, run, fi, nm, t, g)
    else @(Found(defs_nil(), 0, nm, t, cur_none(), g), false)): [k:nat] @(found(n, k, t + k), bool)
  val st2 = (if hit then st0 else let
      val xs = lex_spans(bv, len, sn)
      val st1 = scan_spans(bv, sn, xs, st0, fi)
      val () = spans_free(xs)
    in end_def(st1, fi) end): [k:nat] found(n, k, t + k)
  val memo2 = scans_keep(memo, remember, hit, p, pm, bv, sn, st2, g, run)
  val () = scans_put(memo2)
in st2 end

(* pk with the file at the NUL-terminated path p (at fi in the file
   list) *)
fn add_file {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= RMAX}
  (p: !$A.borrow(byte, lp, np), pm: int pm, fi: spos(RMAX), pk: pkg): pkg =
  case+ read_whole_m(p, pm) of
  | ~whole_err(_) => pk
  | ~whole_ok(ar, piece, sn, n) => let
      val+ ~Pkg(pf, nm, t, g) = pk
      val @(fz, bv) = $A.freeze<byte>(piece)
      val st2 = scan_file(p, pm, bv, sn, n, fi, nm, t, g)
      val () = $A.drop<byte>(fz, bv)
      val+ ~Found(ds, kd, nm2, t2, c, g2) = st2
      val () = (case+ c of
        | ~cur_none() => ()
        | ~cur_def(a, _, _, _, _, _, _, oc) => let
            val () = $A.free<byte>(a)
          in occs_free(oc) end): void
    in Pkg(pfiles_cons(fi, ar, $A.thaw<byte>(fz), sn, kd, ds, pf), nm2, t2, g2) end

(* pk with each file of the NUL-separated list files[off, len) *)
fun add_files {lf:agz}{nf:pos}{fm:nat | fm <= nf; fm <= RMAX}{off:nat | off <= fm} .<fm - off>.
  (files: !$A.borrow(byte, lf, nf), fm: int fm, off: int off, len: int, pk: pkg): pkg =
  if off >= len then pk
  else let
    val e = nul_in(files, off, fm)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, fm, pb)
    val @(pa, pal) = $B.into_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val pk2 = add_file(bv_p, pal, off, pk)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in
    if e >= fm then pk2 else add_files(files, fm, e + 1, len, pk2)
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
fun same_bytes {la,l:agz}{o:addr}{n:int}{k:nat | k <= 256}{s:nat | s + k <= n}{i:nat | i <= k} .<k - i>.
  (a: !$A.arr(byte, la, 256), k: int k, src: !$A.arrx(byte, l, n, o), s: int s, i: int i): bool =
  if i >= k then true
  else if byte2int0($A.get<byte>(a, i)) = byte2int0($A.get<byte>(src, s + i)) then
    same_bytes(a, k, src, s, i + 1)
  else false

(* Whether the identifier src[s, e) of file fi, in a body of group grp,
   calls the definition d *)
fn calls {l:agz}{o:addr}{n:int}{s,e:nat | s <= e; e <= n}
  (d: !dname, src: !$A.arrx(byte, l, n, o), s: int s, e: int e, fi: spos(RMAX), grp: int): bool = let
  val+ @DName(a, k, global, dfi, dgrp) = d
  val len = (if e - s > 256 then 256 else e - s): [n:nat | n <= 256; n <= e - s] int n
  val r = (if ~global && dfi <> fi then false
           else if grp > 0 && grp = dgrp then false
           else if len <> k then false
           else same_bytes(a, k, src, s, 0)): bool
  prval () = fold@(d)
in r end

(* The definitions in BUCKETS lists by the hash of their name (its first 256 bytes), each with its id j < N, so that an identifier is compared with the definitions that hash as it does (bats#368) *)
#define BUCKETS 64

datavtype bnames(N:int, int) =
  | bnames_nil(N, 0) of ()
  | {m:nat}{j:nat | j < N} bnames_cons(N, m + 1) of (int j, int, dname, bnames(N, m))

datavtype buckets(N:int, int) =
  | buckets_nil(N, 0) of ()
  | {b,m:nat} buckets_cons(N, b + 1) of (bnames(N, m), buckets(N, b))

fun bnames_free {N:int}{m:nat} .<m>. (xs: bnames(N, m)): void =
  case+ xs of
  | ~bnames_nil() => ()
  | ~bnames_cons(_, _, d, tl) => let
      val+ ~DName(a, _, _, _, _) = d
      val () = $A.free<byte>(a)
    in bnames_free(tl) end

fun buckets_free {N:int}{b:nat} .<b>. (bs: buckets(N, b)): void =
  case+ bs of
  | ~buckets_nil() => ()
  | ~buckets_cons(bn, tl) => let
      val () = bnames_free(bn)
    in buckets_free(tl) end

fun buckets_make {N:int}{b:nat} .<b>. (b: int b): buckets(N, b) =
  if b <= 0 then buckets_nil()
  else buckets_cons(bnames_nil(), buckets_make(b - 1))

(* name hash (recursion.md): below HASHES, the bucket is the hash modulo BUCKETS *)
#define HASHES 1048576

(* The hash of a[0, k) *)
fun hash_name {la:agz}{k:nat | k <= 256}{i:nat | i <= k}{h:nat | h < HASHES} .<k - i>.
  (a: !$A.arr(byte, la, 256), k: int k, i: int i, h: int h): [r:nat | r < HASHES] int r =
  if i >= k then h
  else hash_name(a, k, i + 1, nmod(h * 31 + $AR.low_byte(byte2int0($A.get<byte>(a, i))), HASHES))

(* The hash of src[s, s + k), the same bytes the same *)
fun hash_source {l:agz}{o:addr}{n:int}{k:nat | k <= 256}{s:nat | s + k <= n}{i:nat | i <= k}
  {h:nat | h < HASHES} .<k - i>.
  (src: !$A.arrx(byte, l, n, o), s: int s, k: int k, i: int i, h: int h)
  : [r:nat | r < HASHES] int r =
  if i >= k then h
  else hash_source(src, s, k, i + 1,
    nmod(h * 31 + $AR.low_byte(byte2int0($A.get<byte>(src, s + i))), HASHES))

(* d added to the bucket h of bs, with its id j. h < b, so the buckets
   run out only after h of them are passed: there is no empty bucket
   list to drop d in *)
fun buckets_add {N:int}{b:pos}{j:nat | j < N}{h:nat | h < b} .<b>.
  (bs: buckets(N, b), h: int h, name_hash: int, j: int j, d: dname): buckets(N, b) =
  case+ bs of
  | ~buckets_cons(bn, tl) =>
    if h <= 0 then buckets_cons(bnames_cons(j, name_hash, d, bn), tl)
    else buckets_cons(bn, buckets_add(tl, h - 1, name_hash, j, d))

(* The names nm (ids i, i + 1, ...) in the buckets bs *)
fun buckets_fill {N:int}{m,i:nat | i + m == N} .<m>.
  (nm: dnames(m), i: int i, bs: buckets(N, BUCKETS)): buckets(N, BUCKETS) =
  case+ nm of
  | ~dnames_nil() => bs
  | ~dnames_cons(d, tl) => let
      val+ @DName(a, k, _, _, _) = d
      val name_hash = hash_name(a, k, 0, 0)
      prval () = fold@(d)
    in buckets_fill(tl, i + 1, buckets_add(bs, nmod(name_hash, BUCKETS), name_hash, i, d)) end

(* The definitions of bn that src[s, e) calls, added to acc *)
fun bucket_calls {N:int}{m:nat}{l:agz}{o:addr}{n:int}{s,e:nat | s <= e; e <= n}{c:nat} .<m>.
  (bn: !bnames(N, m), src: !$A.arrx(byte, l, n, o), s: int s, e: int e, name_hash: int,
   fi: spos(RMAX), grp: int, acc: elist(N, c)): [c2:nat] elist(N, c2) =
  case+ bn of
  | bnames_nil() => acc
  | bnames_cons(j, definition_hash, d, tl) =>
    if definition_hash = name_hash && calls(d, src, s, e, fi, grp) then
      bucket_calls(tl, src, s, e, name_hash, fi, grp, elist_cons(j, acc))
    else bucket_calls(tl, src, s, e, name_hash, fi, grp, acc)

(* The definitions of the bucket h of bs that src[s, e) calls, added to acc *)
fun bucket_of {N:int}{b:pos}{h:nat | h < b}{l:agz}{o:addr}{n:int}{s,e:nat | s <= e; e <= n}{c:nat} .<b>.
  (bs: !buckets(N, b), h: int h, src: !$A.arrx(byte, l, n, o), s: int s, e: int e, name_hash: int,
   fi: spos(RMAX), grp: int, acc: elist(N, c)): [c2:nat] elist(N, c2) =
  case+ bs of
  | buckets_cons(bn, tl) =>
    if h <= 0 then bucket_calls(bn, src, s, e, name_hash, fi, grp, acc)
    else bucket_of(tl, h - 1, src, s, e, name_hash, fi, grp, acc)

(* The definitions of bs that src[s, e) calls, added to acc *)
fn calls_of {N:int}{l:agz}{o:addr}{n:int}{s,e:nat | s <= e; e <= n}{c:nat}
  (bs: !buckets(N, BUCKETS), src: !$A.arrx(byte, l, n, o), s: int s, e: int e,
   fi: spos(RMAX), grp: int, acc: elist(N, c)): [c2:nat] elist(N, c2) = let
  val len = (if e - s > 256 then 256 else e - s): [k:nat | k <= 256; k <= e - s] int k
  val name_hash = hash_source(src, s, len, 0, 0)
in bucket_of(bs, nmod(name_hash, BUCKETS), src, s, e, name_hash, fi, grp, acc) end

(* What the identifiers oc of a body in file fi, group grp, call *)
fun occs_calls {N:nat}{l:agz}{o:addr}{n:int}{j:nat}{c:nat} .<j>.
  (oc: !occs(n, j), bs: !buckets(N, BUCKETS), src: !$A.arrx(byte, l, n, o), fi: spos(RMAX), grp: int, acc: elist(N, c))
  : [c2:nat] elist(N, c2) =
  case+ oc of
  | occs_nil() => acc
  | occs_cons(s, e, tl) =>
    occs_calls(tl, bs, src, fi, grp, calls_of(bs, src, s, e, fi, grp, acc))

(* The nodes of the definitions ds of file fi (ids i, i + 1, ...),
   added to acc *)
fun def_nodes {N:nat}{k,i:nat | i + k <= N}{l:agz}{o:addr}{n:int}{c:nat} .<k>.
  (ds: !defs(n, k), i: int i, bs: !buckets(N, BUCKETS), src: !$A.arrx(byte, l, n, o), fi: spos(RMAX), acc: nodes(N, c))
  : [c2:nat] nodes(N, c2) =
  case+ ds of
  | defs_nil() => acc
  | defs_cons(d, tl) => let
      val+ @Def(impl, grp, _, _, _, oc) = d
      val es = occs_calls(oc, bs, src, fi, grp, elist_nil())
      val nd = Node(i, impl, es)
      prval () = fold@(d)
    in def_nodes(tl, i + 1, bs, src, fi, nodes_cons(nd, acc)) end

(* The nodes of the files pf, whose definitions have ids i, i + 1, ... *)
fun file_nodes {N:nat}{t,f,i:nat | i + t == N}{c:nat} .<f>.
  (pf: !pfiles(t, f), i: int i, bs: !buckets(N, BUCKETS), acc: nodes(N, c)): [c2:nat] nodes(N, c2) =
  case+ pf of
  | pfiles_nil() => acc
  | pfiles_cons(fi, _, src, _, k, ds, tl) => let
      val acc2 = def_nodes(ds, i, bs, src, fi, acc)
    in file_nodes(tl, i + k, bs, acc2) end

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
#pub datavtype cycle_hits(int) =
  | cycle_hits_nil(0) of ()
  | {k:nat} cycle_hits_cons(k + 1) of (spos(524288), pos_t, pos_t, pos_t, cycle_hits(k))

#pub fun cycle_hits_free {k:nat} (xs: cycle_hits(k)): void

implement cycle_hits_free {k} (xs) = let
  fun loop {k:nat} .<k>. (xs: cycle_hits(k)): void =
    case+ xs of
    | ~cycle_hits_nil() => ()
    | ~cycle_hits_cons(_, _, _, _, tl) => loop(tl)
in loop(xs) end

(* The hits among the definitions ds of file fi (ids i, i + 1, ...) *)
fun def_hits {N:nat}{n:int}{k,i:nat | i + k <= N}{lc:agz}{h:nat} .<k>.
  (ds: !defs(n, k), i: int i, fi: spos(RMAX), cyc: !$A.arr(bool, lc, N), acc: cycle_hits(h))
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
  | pfiles_cons(fi, _, _, _, k, ds, tl) => file_hits(tl, i + k, cyc, def_hits(ds, i, fi, cyc, acc))

(* The hits of the N definitions of pf, whose names are nm (taken) *)
fn graph_hits {N:pos | N <= 1048576}{f:nat}
  (pf: !pfiles(N, f), nm: dnames(N), n: int N): [h:nat] cycle_hits(h) = let
  val bs = buckets_fill(nm, 0, buckets_make(BUCKETS))
  val ns = file_nodes(pf, 0, bs, nodes_nil())
  val () = buckets_free(bs)
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
#pub datavtype cycles =
  | {h:nat} Cycles of (cycle_hits(h), bool)

(* The implements on a call cycle among the definitions of the .bats
   files in the NUL-separated list files[off, len) *)
#pub fn implement_cycles {lf:agz}{nf:pos}{fm:nat | fm <= nf; fm <= 524288}{off:nat | off <= fm}
  (files: !$A.borrow(byte, lf, nf), fm: int fm, off: int off, len: int): cycles

implement implement_cycles (files, fm, off, len) = let
  val () = (if !g_remember then !g_scan_run := !g_scan_run + 1 else ())
  val pk = add_files(files, fm, off, len, Pkg(pfiles_nil(), dnames_nil(), 0, 0))
  val () = (if !g_remember then scans_put(scans_trim(scans_take(), !g_scan_run)) else ())
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
  in Cycles(hs, false) end
end
