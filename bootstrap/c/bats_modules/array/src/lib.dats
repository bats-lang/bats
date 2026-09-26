staload "./lib.sats"
(* array -- linear memory safety library for bats *)
(* Typed arrays with linear ownership -- no raw pointers. *)
(* Typed arrays with linear ownership. *)

#include "share/atspre_staload.hats"

(* ============================================================
   Types
   ============================================================ *)







(* ============================================================
   Allocate / free
   ============================================================ *)













(* ============================================================
   Element access (bounds-checked)
   ============================================================ *)













(* ============================================================
   Split / join (sub-array with size tracking)
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
































(* ============================================================
   Text from bytes -- runtime SAFE_CHAR validation
   ============================================================ *)









(* ============================================================
   Utility -- int to byte conversion
   ============================================================ *)



(* ============================================================
   Write operations (byte-level)
   ============================================================ *)























(* ============================================================
   Content text -- wider character set for attribute values
   ============================================================ *)















































(* ============================================================
   Arena -- bulk allocation with token-tracked lifecycle
   ============================================================ *)






























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
  *(int *)(((char *)p) + off) = v;
}
static inline void
_arr_copy_at(void *dst, int off, void *src, int len) {
  unsigned char *d = ((unsigned char *)dst) + off;
  unsigned char *s = (unsigned char *)src;
  int i;
  for (i = 0; i < len; i++) d[i] = s[i];
}

typedef struct { char *base; int used; int max_sz; } _arr_arena_t;

static inline void *
_arr_arena_create(int max_sz) {
  _arr_arena_t *a;
  a = (void *)malloc(sizeof(_arr_arena_t));
  a->base = (char *)malloc(max_sz);
  a->used = 0;
  a->max_sz = max_sz;
  memset(a->base, 0, max_sz);
  return (void *)a;
}
static inline void *
_arr_arena_alloc(void *arena, int sz) {
  _arr_arena_t *a = (_arr_arena_t *)arena;
  void *p = (void *)(a->base + a->used);
  a->used += sz;
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


  assume arr(a, l, n) = ptr l
  assume frozen(a, l, n, k) = ptr l
  assume borrow(a, l, n) = ptr l
  assume text(n) = ptr
  assume text_builder(n, i) = ptr
  assume arena(l, max, k) = ptr l
  assume arena_token(la, l, n) = ptr l


in

fn _proven_int2byte{i:nat | i < 256}(i: int i): byte =
   $UNSAFE.cast{byte}(i) 

 extern fun _malloc_bytes (n: int): [l:agz] ptr l = "mac#malloc" 

(* -- Allocate / free -- *)

implement{a}
alloc{n}(n) = let
  val nbytes = n * sz2i(sizeof<a>)
  val p = _malloc_bytes(nbytes)
  val () =  $extfcall(void, "memset", p, 0, nbytes) 
in
  p
end

implement{a}
free{l}{n}(arr) =
   $extfcall(void, "free", arr) 

(* -- Element access -- *)

implement{a}
get{l}{n,i}(arr, i) =
   $UNSAFE.ptr0_get<a>(ptr_add<a>(arr, i)) 

implement{a}
set{l}{n,i}(arr, i, v) =
   $UNSAFE.ptr0_set<a>(ptr_add<a>(arr, i), v) 

(* -- Split / join -- *)

implement{a}
split{l}{n,m}(arr, m) = let
  val tail =  $UNSAFE.cast{ptr(l+m)}(ptr_add<a>(arr, m)) 
in
  @(arr, tail)
end

implement{a}
join{l}{n,m}(left, right) = left

(* -- Freeze / thaw -- *)

implement{a}
freeze{l}{n}(arr) = @(arr, arr)

implement{a}
thaw{l}{n}(f) = f

implement{a}
dup{l}{n}{k}(f, b) = b

implement{a}
drop{l}{n}{k}(f, b) = ()

(* -- Read from borrow -- *)

implement{a}
read{l}{n,i}(b, i) =
   $UNSAFE.ptr0_get<a>(ptr_add<a>(b, i)) 

(* -- Borrow split / join -- *)

implement{a}
borrow_split{l}{n,m}{k}(f, b, m) = let
  val tail =  $UNSAFE.cast{ptr(l+m)}(ptr_add<a>(b, m)) 
in
  @(b, tail)
end

implement{a}
borrow_join{l}{n,m}{k}(f, left, right) = left

(* -- Borrow at -- *)

implement{a}
borrow_at{l}{n}{i}{k}(f, b, i) =
   $UNSAFE.cast{ptr(l+i)}(ptr_add<a>(b, i)) 

implement{a}
drop_borrow_at{l}{n}{i}{k}(f, b) = ()

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
write_byte{l}{n}{i}{v}(arr, i, v) =
   $extfcall(void, "_arr_set_byte", arr, i, v) 

implement
write_i32{l}{n}{i}(arr, i, v) =
   $extfcall(void, "_arr_set_i32", arr, i, v) 

implement
write_borrow{ld}{ls}{m}{n}{off}(dst, off_val, src, len) =
   $extfcall(void, "_arr_copy_at", dst, off_val, src, len) 

implement
write_text{l}{m}{n}{off}(dst, off_val, src, len) =
   $extfcall(void, "_arr_copy_at", dst, off_val, src, len) 

implement
write_u16le{l}{n}{i}{v}(arr, i, v) = let
  val v0 : int = v
  val () =  $extfcall(void, "_arr_set_byte", arr, i, v0) 
  val () =  $extfcall(void, "_arr_set_byte", arr, i + 1, v0 / 256) 
in () end

(* -- Arena -- *)


extern fun _arena_create_impl
  (max: int): [l:agz] ptr l = "mac#_arr_arena_create"
extern fun _arena_alloc_impl
  (arena: ptr, size: int): [l:agz] ptr l = "mac#_arr_arena_alloc"
extern fun _arena_destroy_impl
  (arena: ptr): void = "mac#_arr_arena_destroy"


implement
arena_create{max}(max_size) = _arena_create_impl(max_size)

implement{a}
arena_alloc{la}{max}{k}{n}(ar, n) = let
  val nbytes = n * sz2i(sizeof<a>)
  val p = _arena_alloc_impl(
     $UNSAFE.castvwtp1{ptr}(ar) , nbytes)
in @(p, p) end

implement{a}
arena_return{la}{max}{k}{l}{n}(ar, token, v) = ()

implement
arena_destroy{l}{max}(ar) = _arena_destroy_impl(ar)

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
write_content_text{ld}{ls}{m}{n}{off}(dst, off_val, src, len) = let
  fun loop{i:nat | i <= n} .<n - i>.
    (dst: !arr(byte, ld, m), src: !content_text(ls, n),
     off_val: int off, i: int i, len: int n): void =
    if i < len then let
      val b = content_text_get(src, i)
      val () = set<byte>(dst, off_val + i, b)
    in loop(dst, src, off_val, i + 1, len) end
in loop(dst, src, off_val, 0, len) end

end (* local -- content text *)
