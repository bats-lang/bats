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

(* alloc takes at most 1048576 elements, to limit fragmentation (see
   CLAUDE.md). Code that needs more takes pieces of an arena: a region
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
  assume frozenx(a, l, n, k, o) = ptr l
  assume arena(a, l, max, used, k) = ptr l
  assume borrow(a, l, n) = ptr l
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
