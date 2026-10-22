staload "./lib.sats"
(* array -- linear memory safety library for bats *)
(* Typed arrays with linear ownership -- no raw pointers. *)
(* Typed arrays with linear ownership. *)

#include "share/atspre_staload.hats"

(* ============================================================
   Types
   ============================================================ *)

(* An array of n elements of a at l, owned by o: null for an array from
   alloc (free releases it), an arena's address for a piece of that
   arena (only arena_return takes it back). Everything that reads or
   writes an array works for any owner. *)










(* ============================================================
   Allocate / free
   ============================================================ *)

(* n elements, all zero bytes. Only element types for which zero bytes
   are a valid value have an instance: byte, char, bool, int, uint and
   Int ([i:int] int i).
   For any other type (a pointer, say, which would be null) there is no
   instance, so alloc<T> does not compile. *)












(* ============================================================
   Element access (bounds-checked)
   ============================================================ *)













(* ============================================================
   Freeze / thaw borrow protocol
   ============================================================ *)



























(* ============================================================
   Read from borrow (bounds-checked)
   ============================================================ *)







(* ============================================================
   Borrow split / join
   ============================================================ *)















(* ============================================================
   Borrow single element
   ============================================================ *)















(* ============================================================
   Safe text -- compile-time character verification
   ============================================================ *)




























(* The text of a string's n bytes, not a copy: a string is never freed
   or changed, so its bytes stay as they are. A string literal's text
   costs no allocation, where text_build (and every text built from
   bytes) allocates one that is never freed. The empty literal's text,
   text(0), has no byte to read (text_get needs i < n). *)






(* ============================================================
   Text from bytes -- runtime SAFE_CHAR validation
   ============================================================ *)









(* ============================================================
   Utility -- int to byte conversion
   ============================================================ *)



(* ============================================================
   Write operations (byte-level)
   ============================================================ *)









(* v as 4 little-endian bytes at i (two's complement), on any host and
   at any offset. *)














(* ============================================================
   Content text -- wider character set for attribute values
   ============================================================ *)















































(* ============================================================
   Arena -- one large region, handed out in pieces
   ============================================================ *)

(* alloc takes at most 1048576 elements, a bound kept on purpose to limit
   fragmentation (allocation size). Code that needs more takes pieces of an arena: a region
   of max elements of a, of which used are handed out, with k pieces
   outstanding. A piece is an arrx owned by the arena (o = la): it reads
   and writes like any array, free does not take it, and only
   arena_return gives it back. An arena is destroyed when no piece is
   outstanding. Pieces are never reused, so every piece is zero bytes;
   as with alloc, arena_create has instances only for element types
   where zero bytes are a valid value. *)


(* The region could not be had: arena_none, never a null arena. *)










(* A piece of n elements; one that does not fit does not type-check. *)




















(* ============================================================
   What an array holds
   ============================================================ *)

(* The cells of an array, first to last *)




(* CLEN(cs, n): cs has n cells *)




(* NTH(cs, i, v): cell i of cs is v *)




(* SETC(cs, i, v, cs2): cs2 is cs with its cell i set to v *)




(* ============================================================
   What the cells of an array are, proved
   ============================================================ *)

(* Setting a cell leaves the number of cells *)


prfun _setc_len {cs,cs2:cells}{i:nat}{v:int}{n:nat} .<n>. (s: SETC(cs, i, v, cs2), l: CLEN(cs, n)): CLEN(cs2, n) =
  case+ s of
  | SETC_here() => (case+ l of CLEN_cons(l1) => CLEN_cons(l1))
  | SETC_there(s1) => (case+ l of CLEN_cons(l1) => CLEN_cons(_setc_len(s1, l1)))

primplement setc_len {cs,cs2}{i}{v}{n} (s, l) = _setc_len(s, l)

(* The cell that was set is the value *)


prfun _setc_nth_same {cs,cs2:cells}{i:nat}{v:int} .<i>. (s: SETC(cs, i, v, cs2)): NTH(cs2, i, v) =
  case+ s of
  | SETC_here() => NTH_here()
  | SETC_there(s1) => NTH_there(_setc_nth_same(s1))

primplement setc_nth_same {cs,cs2}{i}{v} (s) = _setc_nth_same(s)

(* The others are as they were *)


prfun _setc_nth_other {cs,cs2:cells}{i,j:nat | i != j}{v,w:int} .<i>. (s: SETC(cs, i, v, cs2), p: NTH(cs, j, w)): NTH(cs2, j, w) =
  case+ s of
  | SETC_here() => (case+ p of NTH_there(p1) => NTH_there(p1))
  | SETC_there(s1) =>
    (case+ p of
     | NTH_here() => NTH_here()
     | NTH_there(p1) => NTH_there(_setc_nth_other(s1, p1)))

primplement setc_nth_other {cs,cs2}{i,j}{v,w} (s, p) = _setc_nth_other(s, p)

(* A cell is within the cells *)


prfun _nth_in_len {cs:cells}{i:nat}{v:int}{n:nat} .<i>. (p: NTH(cs, i, v), l: CLEN(cs, n)): [i < n] void =
  case+ p of
  | NTH_here() => (case+ l of CLEN_cons(_) => ())
  | NTH_there(p1) => (case+ l of CLEN_cons(l1) => _nth_in_len(p1, l1))

primplement nth_in_len {cs}{i}{v}{n} (p, l) = _nth_in_len(p, l)

(* A cell has one value *)


prfun _nth_functional {cs:cells}{i:nat}{v,w:int} .<i>. (p: NTH(cs, i, v), q: NTH(cs, i, w)): [v == w] void =
  case+ p of
  | NTH_here() => (case+ q of NTH_here() => ())
  | NTH_there(p1) => (case+ q of NTH_there(q1) => _nth_functional(p1, q1))

primplement nth_functional {cs}{i}{v,w} (p, q) = _nth_functional(p, q)

(* ============================================================
   The array
   ============================================================ *)

(* n bytes at l holding the cells cs *)



(* n bytes, all zero, which the types know nothing more of *)




(* Cell i, with the proof that it is cell i of the cells *)



(* Cells i to i + 3, the bytes of a big-endian word most significant first, with the proof of each *)





(* Cell i set to v: the cells that are left, with the proof that they are *)



(* The same three accessors as templates with no template arguments
   (bats-lang/sha256#59): a dependent instantiates a template in its own
   translation unit, so the C compiler inlines the read or the write into
   the dependent's loop, which a call of the functions above (external
   symbols compiled alone) cannot be. Same types, same bodies: barr_get,
   barr_get_be32 and barr_set are these. Use as barr_get_inline(a, i). *)











(* The array that alloc gives, taken to hold cells nothing is known of; it
   is not an array of alloc any more *)


(* The array without its cells, to be written by what knows nothing of them *)


(* A piece of an arena (or any arrx) lent as a barr. The lend keeps the
   owner: barr_of_arrx consumes the piece and gives the barr and the proof
   arrx_lent(l, n, o) that the memory at l belongs to o; the proof is a
   linear view, made only here and consumed only by barr_to_arrx, which
   takes the barr back and gives the piece of o again. While it is lent the
   piece has not been returned (the arena's count k is unchanged, so
   arena_destroy cannot be called), and the proof is of this l and n, so
   the piece cannot be given back as another, or to another owner. The
   cells are as for barr_of_arr: nothing is known of them. *)








(* Another array holding the same cells *)


(* ============================================================
   Borrowing an array whose cells are known
   ============================================================ *)

(* The freeze / thaw / borrow protocol of arrx and borrow above, for a
   barr: the borrow is indexed by the same cells, so a read through it
   gives NTH(cs, i, v) as barr_get does, and thawing gives back the barr
   with those very cells. k borrows are out; barr_thaw needs k = 0, so
   no cell is set while a borrow is out. *)
















(* The same bytes as a plain borrow(byte, l, n), for what reads through
   that type (read, write_borrow, ...), counted like a cborrow: it is one
   more borrow out, so barr_thaw (k = 0) is refused until the view is
   given back to cborrow_view_drop. Both borrows are held at once and no
   cell is settable meanwhile. The view is indexed by l and n only, so what
   is read through it is not known (use cborrow_get for the cells' proof). *)







(* Cell i, with the proof that it is cell i of the cells *)



(* ============================================================
   C runtime helpers
   ============================================================ *)


%{#
#ifndef _ARR_RUNTIME_DEFINED
#define _ARR_RUNTIME_DEFINED
static inline void
_arr_set_byte(void *p, int off, int v) {
  ((unsigned char *)p)[off] = (unsigned char)v;
}
static inline void
_arr_set_i32(void *p, int off, int v) {
  unsigned char *d = ((unsigned char *)p) + off;
  unsigned int u = (unsigned int)v;
  d[0] = (unsigned char)u;
  d[1] = (unsigned char)(u >> 8);
  d[2] = (unsigned char)(u >> 16);
  d[3] = (unsigned char)(u >> 24);
}
static inline void
_arr_copy_at(void *dst, int off, void *src, int len) {
  unsigned char *d = ((unsigned char *)dst) + off;
  unsigned char *s = (unsigned char *)src;
  int i;
  for (i = 0; i < len; i++) d[i] = s[i];
}
/* An arena: a zeroed region of max elements of size sz, of which used
   are handed out. Pieces are taken in order and never reused. int
   arithmetic (the wasm runtime has no size_t): max <= 2^28 and sz <= 4
   keep max * sz within int. */
typedef struct { char *base; int used; int sz; } _arr_arena_t;

static inline void *
_arr_arena_create(int max, int sz) {
  _arr_arena_t *a = (_arr_arena_t *)malloc(sizeof(_arr_arena_t));
  if (!a) return (void *)0;
  a->base = (char *)calloc(max, sz);
  if (!a->base) { free(a); return (void *)0; }
  a->used = 0;
  a->sz = sz;
  return (void *)a;
}
static inline void *
_arr_arena_alloc(void *arena, int n) {
  _arr_arena_t *a = (_arr_arena_t *)arena;
  void *p = (void *)(a->base + a->used * a->sz);
  a->used += n;
  return p;
}
static inline void
_arr_arena_destroy(void *arena) {
  _arr_arena_t *a = (_arr_arena_t *)arena;
  free(a->base);
  free((void *)a);
}
#endif /* _ARR_RUNTIME_DEFINED */
%}


(* ============================================================
   Implementation -- main local block (trusted unsafe core)
   ============================================================ *)

local


  assume arrx(a, l, n, o) = ptr l
  assume barr(l, n, cs) = ptr l
  assume frozenx(a, l, n, k, o) = ptr l
  assume arena(a, l, max, used, k) = ptr l
  assume borrow(a, l, n) = ptr l
  assume cfrozen(l, n, k, cs) = ptr l
  assume cborrow(l, n, cs) = ptr l
  assume arrx_lent(l, n, o) = unit_v
  assume text(n) = ptr
  assume text_builder(n, i) = ptr


in

fn _proven_int2byte{i:nat | i < 256}(i: int i): byte =
   $UNSAFE.cast{byte}(i) 

 extern fun _malloc_bytes (n: int): [l:agz] ptr l = "mac#malloc" 

(* -- Allocate / free -- *)

 extern fun _calloc (n: int, size: size_t): [l:agz] ptr l = "mac#calloc" 

(* n zeroed elements of a. calloc does the multiplication, so the
   template needs no arithmetic instance from the caller's prelude. *)
fn{a:t@ype} _alloc_zeroed {n:pos} (n: int n): [l:agz] ptr l =
  _calloc(n, sizeof<a>)

implement alloc<byte>(n) = _alloc_zeroed<byte>(n)
implement alloc<char>(n) = _alloc_zeroed<char>(n)
implement alloc<bool>(n) = _alloc_zeroed<bool>(n)
implement alloc<int>(n) = _alloc_zeroed<int>(n)
implement alloc<uint>(n) = _alloc_zeroed<uint>(n)
implement alloc<Int>(n) = _alloc_zeroed<Int>(n)

implement{a}
free{l}{n}(arr) =
   $extfcall(void, "free", arr) 

(* -- Byte arrays that know their contents -- *)

implement barr_alloc {n} (n) =
  
    $UNSAFE.castvwtp0{[l:agz][cs:cells] (CLEN(cs, n) | barr(l, n, cs))}(_calloc(n, sizeof<byte>))
  

implement barr_free {l}{n}{cs} (a) =
   $extfcall(void, "free", a) 

implement{} barr_get_inline {l}{n,i}{cs} (a, i) =
  
    $UNSAFE.cast{[v:int | 0 <= v; v < 256] (NTH(cs, i, v) | int v)}(byte2int0($UNSAFE.ptr0_get<byte>(ptr_add<byte>(a, i))))
  

implement barr_get {l}{n,i}{cs} (a, i) = barr_get_inline{l}{n,i}{cs}(a, i)

(* Not trusted: four barr_get *)
implement{} barr_get_be32_inline {l}{n,i}{cs} (a, i) = let
  val (p0 | b0) = barr_get_inline{l}{n,i}{cs}(a, i)
  val (p1 | b1) = barr_get_inline{l}{n,i+1}{cs}(a, i + 1)
  val (p2 | b2) = barr_get_inline{l}{n,i+2}{cs}(a, i + 2)
  val (p3 | b3) = barr_get_inline{l}{n,i+3}{cs}(a, i + 3)
in (p0, p1, p2, p3 | @(b0, b1, b2, b3)) end

implement barr_get_be32 {l}{n,i}{cs} (a, i) = barr_get_be32_inline{l}{n,i}{cs}(a, i)

implement{} barr_set_inline {l}{n,i}{cs}{v} (a, i, v) = let
  val () =  $UNSAFE.ptr0_set<byte>(ptr_add<byte>(a, i), $UNSAFE.cast{byte}(v)) 
in
   $UNSAFE.castvwtp0{[cs2:cells] (SETC(cs, i, v, cs2) | barr(l, n, cs2))}(a) 
end

implement barr_set {l}{n,i}{cs}{v} (a, i, v) = barr_set_inline{l}{n,i}{cs}{v}(a, i, v)

implement barr_of_arr {l}{n} (a) =
   $UNSAFE.castvwtp0{[cs:cells] (CLEN(cs, n) | barr(l, n, cs))}(a) 

implement barr_to_arr {l}{n}{cs} (a) =
   $UNSAFE.castvwtp0{arr(byte, l, n)}(a) 

implement barr_of_arrx {l}{n}{o} (a) =
   $UNSAFE.castvwtp0{[cs:cells] (CLEN(cs, n), arrx_lent(l, n, o) | barr(l, n, cs))}(a) 

implement barr_to_arrx {l}{n}{o}{cs} (pf | a) = let
  prval unit_v() = pf
in
   $UNSAFE.castvwtp0{arrx(byte, l, n, o)}(a) 
end

implement barr_copy {l}{n}{cs} (a, n) = let
  val copy =  _calloc(n, sizeof<byte>) 
  fun go {i:nat | i <= n} .<n - i>. (i: int i): void =
    if i >= n then ()
    else let
      val () = 
        $UNSAFE.ptr0_set<byte>(ptr_add<byte>(copy, i), $UNSAFE.ptr0_get<byte>(ptr_add<byte>(a, i)))
      
    in go(i + 1) end
  val () = go(0)
in
   $UNSAFE.castvwtp0{[m:agz] barr(m, n, cs)}(copy) 
end

implement barr_freeze {l}{n}{cs} (a) = @(a, a)

implement barr_thaw {l}{n}{cs} (f) = f

implement cborrow_dup {l}{n}{cs}{k} (f, b) = b

implement cborrow_drop {l}{n}{cs}{k} (f, b) = ()

implement cborrow_view {l}{n}{cs}{k} (f, b) = b

implement cborrow_view_drop {l}{n}{cs}{k} (f, b) = ()

implement cborrow_get {l}{n,i}{cs} (b, i) =
  
    $UNSAFE.cast{[v:int | 0 <= v; v < 256] (NTH(cs, i, v) | int v)}(byte2int0($UNSAFE.ptr0_get<byte>(ptr_add<byte>(b, i))))
  

(* -- Element access -- *)

implement{a}
get{l}{o}{n,i}(arr, i) =
   $UNSAFE.ptr0_get<a>(ptr_add<a>(arr, i)) 

implement{a}
set{l}{o}{n,i}(arr, i, v) =
   $UNSAFE.ptr0_set<a>(ptr_add<a>(arr, i), v) 

(* -- Freeze / thaw -- *)

implement{a}
freeze{l}{o}{n}(arr) = @(arr, arr)

implement{a}
thaw{l}{o}{n}(f) = f

implement{a}
dup{l}{o}{n}{k}(f, b) = b

implement{a}
drop{l}{o}{n}{k}(f, b) = ()

(* -- Read from borrow -- *)

implement{a}
read{l}{n,i}(b, i) =
   $UNSAFE.ptr0_get<a>(ptr_add<a>(b, i)) 

(* -- Borrow split / join -- *)

implement{a}
borrow_split{l}{o}{n,m}{k}(f, b, m) = let
  val tail =  $UNSAFE.cast{ptr(l+m)}(ptr_add<a>(b, m)) 
in
  @(b, tail)
end

implement{a}
borrow_join{l}{o}{n,m}{k}(f, left, right) = left

(* -- Borrow at -- *)

implement{a}
borrow_at{l}{o}{n}{i}{k}(f, b, i) =
   $UNSAFE.cast{ptr(l+i)}(ptr_add<a>(b, i)) 

implement{a}
drop_borrow_at{l}{o}{n}{i}{k}(f, b) = ()

(* -- Text -- *)

implement
text_build{n}(n) = _malloc_bytes(n)

implement
text_putc{c}{n}{i}(b, i, c) = let
  val () =  $UNSAFE.ptr0_set<byte>(ptr_add<byte>(b, i), _proven_int2byte(c)) 
in b end

implement
text_done{n}(b) = b

implement
text_lit{n}(s) =
   $UNSAFE.cast{text(n)}(string2ptr(s)) 

implement
text_get{n,i}(t, i) =
   $UNSAFE.ptr0_get<byte>(ptr_add<byte>(t, i)) 

implement
text_from_bytes{lb}{n}(src, len) = let
  fun loop {i:nat | i <= n} .<n - i>.
    (src: ptr, i: int i, len: int n): bool =
    if i >= len then true
    else let
      val b = byte2int0( $UNSAFE.ptr0_get<byte>(ptr_add<byte>(src, i)) )
    in
      if (b >= 97 andalso b <= 122)
         orelse (b >= 65 andalso b <= 90)
         orelse (b >= 48 andalso b <= 57)
         orelse b = 45
      then loop(src, i + 1, len)
      else false
    end
  val all_safe = loop(src, 0, len)
in
  if all_safe then let
    val p = _malloc_bytes(len)
    val () =  $extfcall(void, "memcpy", p, src, len) 
    val t =  $UNSAFE.cast{text(n)}(p) 
  in text_ok(t) end
  else text_fail()
end

implement
int2byte{i}(i) = _proven_int2byte(i)

(* -- Write operations -- *)

implement
write_byte{l}{o}{n}{i}{v}(arr, i, v) =
   $extfcall(void, "_arr_set_byte", arr, i, v) 

implement
write_i32{l}{o}{n}{i}(arr, i, v) =
   $extfcall(void, "_arr_set_i32", arr, i, v) 

implement
write_borrow{ld}{o}{ls}{m}{n}{off}(dst, off_val, src, len) =
   $extfcall(void, "_arr_copy_at", dst, off_val, src, len) 

implement
write_text{l}{o}{m}{n}{off}(dst, off_val, src, len) =
   $extfcall(void, "_arr_copy_at", dst, off_val, src, len) 

implement
write_u16le{l}{o}{n}{i}{v}(arr, i, v) = let
  val v0 : int = v
  val () =  $extfcall(void, "_arr_set_byte", arr, i, v0) 
  val () =  $extfcall(void, "_arr_set_byte", arr, i + 1, v0 / 256) 
in () end

(* -- Arena -- *)


extern fun _arena_create_impl
  (max: int, sz: int): [l:addr] ptr l = "mac#_arr_arena_create"
extern fun _arena_alloc_impl
  (arena: ptr, n: int): [l:agz] ptr l = "mac#_arr_arena_alloc"
extern fun _arena_destroy_impl
  (arena: ptr): void = "mac#_arr_arena_destroy"


fn{a:t@ype} _arena_create_zeroed {max:pos} (max: int max): arena_made(a, max) = let
  val p = _arena_create_impl(max, sz2i(sizeof<a>))
in
  if ptr_isnot_null(p) then arena_some(p)
  else arena_none()
end

implement arena_create<byte>(max) = _arena_create_zeroed<byte>(max)
implement arena_create<char>(max) = _arena_create_zeroed<char>(max)
implement arena_create<bool>(max) = _arena_create_zeroed<bool>(max)
implement arena_create<int>(max) = _arena_create_zeroed<int>(max)
implement arena_create<uint>(max) = _arena_create_zeroed<uint>(max)
implement arena_create<Int>(max) = _arena_create_zeroed<Int>(max)

implement{a}
arena_alloc{la}{max,used,k}{n}(ar, n) = _arena_alloc_impl(ar, n)

implement{a}
arena_return{la}{max,used}{k}{l}{n}(ar, p) = ()

implement{a}
arena_destroy{la}{max,used}(ar) = _arena_destroy_impl(ar)

end (* local -- main implementation block *)

(* ============================================================
   Content text -- separate local block
   ============================================================ *)

local


  assume content_text(l, n) = arr(byte, l, n)
  assume content_text_builder(l, n, i) = arr(byte, l, n)


in

implement
content_text_build{n}(n) = alloc<byte>(n)

implement
content_text_putc{c}{l}{n}{i}(b, i, c) = let
  val () = set<byte>(b, i, int2byte(c))
in b end

implement
content_text_done{l}{n}(b) = b

implement
content_text_get{l}{n,i}(t, i) =
  get<byte>(t, i)

implement
content_text_free{l}{n}(t) =
  free<byte>(t)

implement
text_to_content{n}(t, len) = let
  val ar = alloc<byte>(len)
  val () = write_text(ar, 0, t, len)
in ar end

implement
write_content_text{ld}{o}{ls}{m}{n}{off}(dst, off_val, src, len) = let
  fun loop{i:nat | i <= n} .<n - i>.
    (dst: !arrx(byte, ld, m, o), src: !content_text(ls, n),
     off_val: int off, i: int i, len: int n): void =
    if i < len then let
      val b = content_text_get(src, i)
      val () = set<byte>(dst, off_val + i, b)
    in loop(dst, src, off_val, i + 1, len) end
in loop(dst, src, off_val, 0, len) end

end (* local -- content text *)
