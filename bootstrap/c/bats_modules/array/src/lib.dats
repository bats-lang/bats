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
get{l}{n,i}(arr, i) =
   $UNSAFE.ptr0_get<a>(ptr_add<a>(arr, i)) 

implement{a}
set{l}{n,i}(arr, i, v) =
   $UNSAFE.ptr0_set<a>(ptr_add<a>(arr, i), v) 

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
