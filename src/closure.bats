(* closure -- the dependencies a binary's code reaches through staloads

   A binary dynloads and links every dependency its entry and the
   package's modules staload, and every dependency those staload, and so
   on. The dependencies that can appear are the packages under
   bats_modules/, so the closure is taken over that list: each name found
   in a staload moves from the unseen packages to the queue, and each
   queued package's lib.dats is read in turn. Each step either takes a
   package out of the unseen ones or one out of the queue, which is the
   metric: no count of lines or entries bounds the search. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "docs.sats"

#define CMAX 524288

(* A package name, name[0, k) *)
#pub datavtype dep =
  | {l:agz}{k:nat | k <= 256} Dep of ($A.arr(byte, l, 256), int k)

(* Package names, in order *)
#pub datavtype deps(int) =
  | deps_nil(0) of ()
  | {n:nat} deps_cons(n + 1) of (dep, deps(n))

#pub fun deps_free {n:nat} (xs: deps(n)): void

implement deps_free {n} (xs) = let
  fun loop {n:nat} .<n>. (xs: deps(n)): void =
    case+ xs of
    | ~deps_nil() => ()
    | ~deps_cons(d, tl) => let
        val+ ~Dep(a, _) = d
        val () = $A.free<byte>(a)
      in loop(tl) end
in loop(xs) end

(* The name of d appended to out *)
#pub fn put_dep (out: !$B.builder_v >> $B.builder_v, d: !dep): void

implement put_dep (out, d) = let
  val+ @Dep(a, k) = d
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = copy_to_builder_v(bv, 0, k, 256, out)
  val () = $A.drop<byte>(fz, bv)
  val () = a := $A.thaw<byte>(fz)
  prval () = fold@(d)
in end

(* xs with ys after them *)
fun deps_append {n,m:nat} .<n>. (xs: deps(n), ys: deps(m)): deps(n + m) =
  case+ xs of
  | ~deps_nil() => ys
  | ~deps_cons(d, tl) => deps_cons(d, deps_append(tl, ys))

fun deps_rev {n,m:nat} .<n>. (xs: deps(n), acc: deps(m)): deps(n + m) =
  case+ xs of
  | ~deps_nil() => acc
  | ~deps_cons(d, tl) => deps_rev(tl, deps_cons(d, acc))

(* src[s, e) (its first 256 bytes) into a name array *)
fun copy_name {l,la:agz}{n:pos}{s,e:nat | s <= e; e <= n}{i:nat | i <= 256} .<256 - i>.
  (src: !$A.borrow(byte, l, n), s: int s, e: int e, a: !$A.arr(byte, la, 256), i: int i)
  : [k:nat | k <= 256] int k =
  if i >= 256 then i
  else if s + i >= e then i
  else let
    val () = $A.set<byte>(a, i, $A.read<byte>(src, s + i))
  in copy_name(src, s, e, a, i + 1) end

(* Whether a[0, k) is src[s, e) *)
fun name_is {l,la:agz}{n:pos}{k:nat | k <= 256}{s,e:nat | s <= e; e <= n}{i:nat | i <= k} .<k - i>.
  (a: !$A.arr(byte, la, 256), k: int k, src: !$A.borrow(byte, l, n), s: int s, e: int e, i: int i): bool =
  if e - s <> k then false
  else if i >= k then true
  else if byte2int0($A.get<byte>(a, i)) <> byte2int0($A.read<byte>(src, s + i)) then false
  else name_is(a, k, src, s, e, i + 1)

(* ============================================================
   The universe: the packages under bats_modules/
   ============================================================ *)

(* The package of the path lst[s, e) when it is
   bats_modules/<name>/src/lib.bats, onto acc *)
fn add_package {l:agz}{s,e:nat | s <= e; e <= CMAX}{m:nat}
  (lst: !$A.borrow(byte, l, CMAX), s: int s, e: int e, acc: deps(m)): [m2:nat] deps(m2) = let
  var lib_c = @[char][13]('/', 's', 'r', 'c', '/', 'l', 'i', 'b', '.', 'b', 'a', 't', 's')
in
  (* bats_modules/<name>/src/lib.bats: "bats_modules/" is 13 bytes *)
  if e - s < 27 then acc
  else if ~lit_at(lst, e - 13, CMAX, lib_c, 13) then acc
  else let
    val a = $A.alloc<byte>(256)
    val k = copy_name(lst, s + 13, e - 13, a, 0)
  in deps_cons(Dep(a, k), acc) end
end

fun packages_of {l:agz}{off:nat | off <= CMAX}{m:nat} .<CMAX - off>.
  (lst: !$A.borrow(byte, l, CMAX), off: int off, len: int, acc: deps(m)): [m2:nat] deps(m2) =
  if off >= len then acc
  else let
    val e = $S.find_null_bv_at(lst, off, CMAX)
    val acc2 = add_package(lst, off, e, acc)
  in if e >= CMAX then acc2 else packages_of(lst, e + 1, len, acc2) end

(* The packages under bats_modules/ *)
fn packages (): [u:nat] deps(u) = let
  var d : $B.builder_v = $B.create()
  val () = bput_v(d, "bats_modules")
  val @(fa, flen) = sorted_bats_files(d)
  val @(fz, bv) = $A.freeze<byte>(fa)
  val xs = packages_of(bv, 0, flen, deps_nil())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in xs end

(* ============================================================
   Moving what a file staloads from the unseen packages to the queue
   ============================================================ *)

(* unseen without the package named src[s, e), and it, when it is
   there *)
datavtype taken(int) =
  | {u:nat} Taken(u + 1) of (deps(u), dep)
  | {u:nat} NotTaken(u) of deps(u)

fun take {l:agz}{n:pos}{s,e:nat | s <= e; e <= n}{u:nat} .<u>.
  (src: !$A.borrow(byte, l, n), s: int s, e: int e, unseen: deps(u)): taken(u) =
  case+ unseen of
  | ~deps_nil() => NotTaken(deps_nil())
  | ~deps_cons(d, tl) => let
      val+ @Dep(a, k) = d
      val hit = name_is(a, k, src, s, e, 0)
      prval () = fold@(d)
    in
      if hit then Taken(tl, d)
      else (case+ take(src, s, e, tl) of
        | ~Taken(rest, x) => Taken(deps_cons(d, rest), x)
        | ~NotTaken(rest) => NotTaken(deps_cons(d, rest)))
    end

(* What a scan leaves: the unseen packages and those it found, in the
   order found (reversed), m of them *)
datavtype scanned(int) =
  | {u,m:nat} Scanned(u + m) of (deps(u), deps(m), int m)

(* The end of the line at p *)
fun line_end {l:agz}{n:pos}{p,nb:nat | p <= nb; nb <= n} .<nb - p>.
  (src: !$A.borrow(byte, l, n), p: int p, nb: int nb): [q:nat | p <= q; q <= nb] int q =
  if p >= nb then p
  else if byte2int0($A.read<byte>(src, p)) = 10 then p
  else line_end(src, p + 1, nb)

(* The first '"' of src[p, e), or e *)
fun find_quote {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (src: !$A.borrow(byte, l, n), p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else if byte2int0($A.read<byte>(src, p)) = 34 then p
  else find_quote(src, p + 1, e)

(* The line src[p, le): when it is staload "<name>/src/lib.dats", the
   package name moves from unseen to found *)
fn scan_line {l:agz}{n:pos}{p,le:nat | p <= le; le <= n}{u,m:nat}
  (src: !$A.borrow(byte, l, n), max: int n, p: int p, le: int le, unseen: deps(u), found: deps(m), fm: int m)
  : scanned(u + m) =
  if p + 9 > le then Scanned(unseen, found, fm)
  else if ~lit_staload_dq(src, p, max) then Scanned(unseen, found, fm)
  else let
    val q = find_quote(src, p + 9, le)
  in
    if q - (p + 9) <= 13 then Scanned(unseen, found, fm)
    else if lit_dot_slash(src, p + 9, max) then Scanned(unseen, found, fm)
    else if ~lit_slash_srcslash_libdot_dats(src, q - 13, max) then Scanned(unseen, found, fm)
    else (case+ take(src, p + 9, q - 13, unseen) of
      | ~Taken(rest, d) => Scanned(rest, deps_cons(d, found), fm + 1)
      | ~NotTaken(rest) => Scanned(rest, found, fm))
  end

(* The staloads of the lines of src[p, nb) *)
fun scan_lines {l:agz}{n:pos}{p,nb:nat | p <= nb; nb <= n}{u,m:nat} .<nb - p>.
  (src: !$A.borrow(byte, l, n), max: int n, p: int p, nb: int nb, unseen: deps(u), found: deps(m), fm: int m)
  : scanned(u + m) =
  if p >= nb then Scanned(unseen, found, fm)
  else let
    val le = line_end(src, p, nb)
    val+ ~Scanned(un2, f2, m2) = scan_line(src, max, p, le, unseen, found, fm)
  in
    if le >= nb then Scanned(un2, f2, m2)
    else scan_lines(src, max, le + 1, nb, un2, f2, m2)
  end

(* The staloads of the file at the NUL-terminated path p *)
fn scan_file {lp:agz}{u:nat}
  (p: !$A.borrow(byte, lp, CMAX), unseen: deps(u)): scanned(u) =
  case+ read_whole(p, CMAX) of
  | ~whole_err(_) => Scanned(unseen, deps_nil(), 0)
  | ~whole_ok(ar, piece, m, nb) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val r = scan_lines(bv, m, 0, nb, unseen, deps_nil(), 0)
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in r end

(* The staloads of the file whose path is b, NUL-terminated *)
fn scan_path {u:nat} (b: $B.builder_v, unseen: deps(u)): scanned(u) = let
  val () = put_char_v(b, 0)
  val @(pa, _) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = scan_file(bv, unseen)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* The staloads of dependency x's modules other than its lib: each
   .dats in build/bats_modules/<x>/src but lib.dats, entries i to n *)
fun scan_extras {n,i:nat | i <= n}{u,m:nat} .<n - i>.
  (es: !$F.entries(n), i: int i, n: int n, x: !dep, unseen: deps(u), found: deps(m), fm: int m)
  : scanned(u + m) =
  if i >= n then Scanned(unseen, found, fm)
  else let
    val e = $A.alloc<byte>(1024)
    val el = $F.entries_name(es, i, e, 1024)
    val dats = has_dats_ext(e, el, 1024)
    val lib = is_lib_dats(e, el, 1024)
    val extra = dats && ~lib
    val @(fz, bv) = $A.freeze<byte>(e)
    val+ ~Scanned(un3, f3, m3) = (if extra then let
        var pb : $B.builder_v = $B.create()
        val () = bput_v(pb, "build/bats_modules/")
        val () = put_dep(pb, x)
        val () = bput_v(pb, "/src/")
        val () = copy_to_builder_v(bv, 0, el, 1024, pb)
        val+ ~Scanned(un2, f2, m2) = scan_path(pb, unseen)
      in Scanned(un2, deps_append(f2, found), m2 + fm) end
      else Scanned(unseen, found, fm)): scanned(u + m)
    val () = $A.drop<byte>(fz, bv)
    val () = $A.free<byte>($A.thaw<byte>(fz))
  in scan_extras(es, i + 1, n, x, un3, f3, m3) end

(* The staloads of all of dependency x's modules: its lib.dats first,
   then the others (a #use in any of them names a dependency the binary
   links, as the others are linked and dynloaded too) *)
fn scan_dep {u:nat} (x: !dep, unseen: deps(u)): scanned(u) = let
  var pb : $B.builder_v = $B.create()
  val () = bput_v(pb, "build/bats_modules/")
  val () = put_dep(pb, x)
  val () = bput_v(pb, "/src/lib.dats")
  val+ ~Scanned(un1, f1, m1) = scan_path(pb, unseen)
  var db : $B.builder_v = $B.create()
  val () = bput_v(db, "build/bats_modules/")
  val () = put_dep(db, x)
  val () = bput_v(db, "/src")
  val () = put_char_v(db, 0)
  val @(da, _) = $B.to_arr(db)
  val @(fz, bv) = $A.freeze<byte>(da)
  val dr = $F.dir_read(bv, 524288)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ dr of
  | ~$R.ok(es) => let
      val r = scan_extras(es, 0, $F.entries_count(es), x, un1, f1, m1)
      val () = $F.entries_free(es)
    in r end
  | ~$R.err(_) => Scanned(un1, f1, m1)
end

(* ============================================================
   The closure
   ============================================================ *)

(* The packages the queue reaches: done (reversed) with the queue and
   what its packages' modules staload, in the order found *)
fun close {u,q:nat}{d:nat} .<u, q>.
  (unseen: deps(u), queue: deps(q), done: deps(d)): [r:nat] deps(r) =
  case+ queue of
  | ~deps_nil() => let
      val () = deps_free(unseen)
    in deps_rev(done, deps_nil()) end
  | ~deps_cons(x, rest) => let
      val+ ~Scanned(un2, found, m) = scan_dep(x, unseen)
      val q2 = deps_append(rest, deps_rev(found, deps_nil()))
    in
      if m > 0 then close(un2, q2, deps_cons(x, done))
      else close(un2, q2, deps_cons(x, done))
    end

(* Whether fl[p, e) holds a '/' *)
fun has_slash {l:agz}{p,e:nat | p <= e; e <= CMAX} .<e - p>.
  (fl: !$A.borrow(byte, l, CMAX), p: int p, e: int e): bool =
  if p >= e then false
  else if byte2int0($A.read<byte>(fl, p)) = 47 then true
  else has_slash(fl, p + 1, e)

(* The staloads of each build/src/<module>.dats in the NUL-separated
   list fl[off, len) of .bats modules, in order *)
fun scan_modules {l:agz}{off:nat | off <= CMAX}{u,m:nat} .<CMAX - off>.
  (fl: !$A.borrow(byte, l, CMAX), off: int off, len: int, unseen: deps(u), found: deps(m), fm: int m)
  : scanned(u + m) =
  if off >= len then Scanned(unseen, found, fm)
  else let
    val e = $S.find_null_bv_at(fl, off, CMAX)
  in
    (* src/<name>.bats, a shared module; src/bin/ and deeper are not *)
    if e - off < 9 then (if e >= CMAX then Scanned(unseen, found, fm) else scan_modules(fl, e + 1, len, unseen, found, fm))
    else if has_slash(fl, off + 4, e) then (if e >= CMAX then Scanned(unseen, found, fm) else scan_modules(fl, e + 1, len, unseen, found, fm))
    else let
      var pb : $B.builder_v = $B.create()
      val () = bput_v(pb, "build/")
      val () = copy_to_builder_v(fl, off, e - 5, CMAX, pb)
      val () = bput_v(pb, ".dats")
      val+ ~Scanned(un2, f2, m2) = scan_path(pb, unseen)
      val+ ~Scanned(un3, f3, m3) = Scanned(un2, deps_append(f2, found), m2 + fm)
    in if e >= CMAX then Scanned(un3, f3, m3) else scan_modules(fl, e + 1, len, un3, f3, m3) end
  end

(* The dependencies of the binary whose entry .dats is at the
   NUL-terminated path entry, in the order found: what it staloads, then
   what the package's shared modules (src/, not src/bin/) staload, then
   what those staload, and so on *)
#pub fn dep_closure {le:agz} (entry: !$A.borrow(byte, le, 524288)): [r:nat] deps(r)

implement dep_closure {le} (entry) = let
  val un0 = packages()
  val+ ~Scanned(un1, f1, _) = scan_file(entry, un0)
  var sd : $B.builder_v = $B.create()
  val () = bput_v(sd, "src")
  val @(fa, flen) = sorted_bats_files(sd)
  val @(fz, bv) = $A.freeze<byte>(fa)
  val+ ~Scanned(un2, f2, _) = scan_modules(bv, 0, flen, un1, deps_nil(), 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  (* f1 and f2 are reversed; the entry's first *)
  val queue = deps_rev(deps_append(f2, f1), deps_nil())
in close(un2, queue, deps_nil()) end
