staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "str/src/lib.dats"
(* path -- file path manipulation *)
(* Pure byte scanning on borrowed byte arrays. No $UNSAFE, no assume. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload S = "str/src/lib.sats"

(* ============================================================
   Constants: ASCII codes
   ============================================================ *)

#define SLASH 47
#define DOT 46

(* ============================================================
   join -- join base and name with / separator into out, which must
   have room for both and the separator: the length written,
   base_len + 1 + name_len.
   ============================================================ *)







(* ============================================================
   parent -- return length of parent (up to last /)
   e.g. "/foo/bar" -> 4 ("/foo")
   ============================================================ *)





(* ============================================================
   filename -- return offset of filename (after last /)
   e.g. "/foo/bar.txt" -> 5
   ============================================================ *)





(* ============================================================
   extension -- return offset of extension (after last .)
   e.g. "/foo/bar.txt" -> 9
   Returns path_len if no extension found.
   ============================================================ *)





(* ============================================================
   is_absolute -- starts with /
   ============================================================ *)





(* ============================================================
   Implementations
   ============================================================ *)

(* -- join -- *)

implement join {la}{na}{lb}{nb}{lo}{mo}
  (base, base_len, name, name_len, out, max) = let
  fun copy_base {lo:agz}{mo:pos}{la:agz}{na:pos | na < mo}{i:nat | i <= na} .<na - i>.
    (out: !$A.arr(byte, lo, mo),
     base: !$A.borrow(byte, la, na), base_len: int na,
     i: int i): void =
    if i >= base_len then ()
    else let
      val b = $A.read<byte>(base, i)
      val () = $A.set<byte>(out, i, b)
    in copy_base(out, base, base_len, $AR.add_g1(i, 1)) end

  fun copy_name {lo:agz}{mo:pos}{lb:agz}{nb:pos}{off:nat | off + nb <= mo}{i:nat | i <= nb} .<nb - i>.
    (out: !$A.arr(byte, lo, mo),
     name: !$A.borrow(byte, lb, nb), name_len: int nb,
     i: int i, offset: int off): void =
    if i >= name_len then ()
    else let
      val b = $A.read<byte>(name, i)
      val di = $AR.add_g1(offset, i)
      val () = $A.set<byte>(out, di, b)
    in copy_name(out, name, name_len, $AR.add_g1(i, 1), offset) end
  val () = copy_base(out, base, base_len, 0)
  val () = $A.set<byte>(out, base_len, $A.int2byte($AR.byte_of_char('/')))
  val offset = $AR.add_g1(base_len, 1)
  val () = copy_name(out, name, name_len, 0, offset)
in $AR.add_g1(offset, name_len) end

(* -- parent -- *)

implement parent {la}{na} (path, path_len) = let
  fun loop {la:agz}{na:pos}{i:nat | i <= na} .<i>.
    (path: !$A.borrow(byte, la, na),
     i: int i): [r:nat | r < na] int r =
    if $AR.lte_g1(i, 0) then 0
    else let
      val idx = $AR.sub_g1(i, 1)
      val c = byte2int0($A.read<byte>(path, idx))
    in
      if $AR.eq_int_int(c, SLASH) then idx
      else loop(path, idx)
    end
in loop(path, path_len) end

(* -- filename -- *)

implement filename {la}{na} (path, path_len) = let
  fun loop {la:agz}{na:pos}{i:nat | i <= na} .<i>.
    (path: !$A.borrow(byte, la, na),
     i: int i): [r:nat | r <= na] int r =
    if $AR.lte_g1(i, 0) then 0
    else let
      val idx = $AR.sub_g1(i, 1)
      val c = byte2int0($A.read<byte>(path, idx))
    in
      if $AR.eq_int_int(c, SLASH) then i
      else loop(path, idx)
    end
in loop(path, path_len) end

(* -- extension -- *)

implement extension {la}{na} (path, path_len) = let
  val fname_start = filename(path, path_len)
  fun loop {la:agz}{na:pos}{i:nat | i <= na}{f:nat} .<i>.
    (path: !$A.borrow(byte, la, na), path_len: int na,
     i: int i, fname_start: int f): [r:nat | r <= na] int r =
    if $AR.lte_g1(i, 0) then path_len
    else if $AR.lte_g1(i, fname_start) then path_len
    else let
      val idx = $AR.sub_g1(i, 1)
      val c = byte2int0($A.read<byte>(path, idx))
    in
      if $AR.eq_int_int(c, DOT) then i
      else loop(path, path_len, idx, fname_start)
    end
in loop(path, path_len, path_len, fname_start) end

(* -- is_absolute -- *)

implement is_absolute {la}{na} (path, path_len) = let
  val c = byte2int0($A.read<byte>(path, 0))
in $AR.eq_int_int(c, SLASH) end

(* ============================================================
   Static tests
   ============================================================ *)

fn _test_parent(): void = let
  (* Test with "/foo/bar" = [47,102,111,111,47,98,97,114] len=8 *)
  var chars = @[char][8]('/', 'f', 'o', 'o', '/', 'b', 'a', 'r')
  val arr = $S.from_char_array(chars, 8)
  val @(fz, bw) = $A.freeze<byte>(arr)
  val p = parent(bw, 8)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

fn _test_filename(): void = let
  var chars = @[char][8]('/', 'f', 'o', 'o', '/', 'b', 'a', 'r')
  val arr = $S.from_char_array(chars, 8)
  val @(fz, bw) = $A.freeze<byte>(arr)
  val f = filename(bw, 8)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

fn _test_is_absolute(): void = let
  var chars = @[char][4]('/', 'f', 'o', 'o')
  val arr = $S.from_char_array(chars, 4)
  val @(fz, bw) = $A.freeze<byte>(arr)
  val b = is_absolute(bw, 4)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

fn _test_join(): void = let
  var bchars = @[char][3]('f', 'o', 'o')
  val base = $S.from_char_array(bchars, 3)
  var nchars = @[char][3]('b', 'a', 'r')
  val name = $S.from_char_array(nchars, 3)
  val out = $A.alloc<byte>(7)
  val @(fzb, bwb) = $A.freeze<byte>(base)
  val @(fzn, bwn) = $A.freeze<byte>(name)
  val len = join(bwb, 3, bwn, 3, out, 7)
  val () = $A.drop<byte>(fzb, bwb)
  val () = $A.drop<byte>(fzn, bwn)
  val base2 = $A.thaw<byte>(fzb)
  val name2 = $A.thaw<byte>(fzn)
  val () = $A.free<byte>(base2)
  val () = $A.free<byte>(name2)
  val () = $A.free<byte>(out)
in end

fn _test_extension(): void = let
  (* "/foo/bar.txt" = [47,102,111,111,47,98,97,114,46,116,120,116] len=12 *)
  var chars = @[char][12]('/', 'f', 'o', 'o', '/', 'b', 'a', 'r', '.', 't', 'x', 't')
  val arr = $S.from_char_array(chars, 12)
  val @(fz, bw) = $A.freeze<byte>(arr)
  val e = extension(bw, 12)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

(* ============================================================
   Tests (bats test)
   ============================================================ *)





















































































