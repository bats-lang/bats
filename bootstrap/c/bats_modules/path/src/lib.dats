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
   join -- join base and name with / separator
   Returns length of result written to out.
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
  (* Total needed: base_len + 1 (for /) + name_len *)
  val total = $AR.add_int_int($AR.add_int_int(base_len, 1), name_len)

  (* Copy base bytes *)
  fun copy_base {lo:agz}{mo:pos}{la:agz}{na:pos}{i:nat | i <= na} .<na - i>.
    (out: !$A.arr(byte, lo, mo), max: int mo,
     base: !$A.borrow(byte, la, na), base_len: int na,
     i: int i): void =
    if i >= base_len then ()
    else let
      val gi = g1ofg0(i)
    in
      if gi >= 0 then
        if gi < max then let
          val b = $A.read<byte>(base, i)
          val () = $A.set<byte>(out, gi, b)
        in copy_base(out, max, base, base_len, i + 1) end
        else ()
      else ()
    end

  (* Copy name bytes starting at offset *)
  fun copy_name {lo:agz}{mo:pos}{lb:agz}{nb:pos}{i:nat | i <= nb} .<nb - i>.
    (out: !$A.arr(byte, lo, mo), max: int mo,
     name: !$A.borrow(byte, lb, nb), name_len: int nb,
     i: int i, offset: int): void =
    if i >= name_len then ()
    else let
      val dst = g1ofg0(offset + i)
    in
      if dst >= 0 then
        if dst < max then let
          val b = $A.read<byte>(name, i)
          val () = $A.set<byte>(out, dst, b)
        in copy_name(out, max, name, name_len, i + 1, offset) end
        else ()
      else ()
    end
in
  if $AR.gt_int_int(total, max) then 0
  else let
    val () = copy_base(out, max, base, base_len, 0)
    (* Write / separator *)
    val sep_pos = g1ofg0(base_len)
    val () = (if sep_pos >= 0 then
      if sep_pos < max then
        $A.set<byte>(out, sep_pos,
          $A.int2byte($AR.checked_byte(SLASH)))): void
    val () = copy_name(out, max, name, name_len, 0, base_len + 1)
  in total end
end

(* -- parent -- *)

implement parent {la}{na} (path, path_len) = let
  (* Scan backwards for last / *)
  fun loop {la:agz}{na:pos}{k:nat} .<k>.
    (path: !$A.borrow(byte, la, na), path_len: int na,
     i: int, rem: int(k)): int =
    if rem <= 0 then 0
    else if $AR.lte_int_int(i, 0) then 0
    else let
      val idx = i - 1
      val gi = g1ofg0(idx)
    in
      if gi >= 0 then
        if gi < path_len then let
          val c = byte2int0($A.read<byte>(path, gi))
        in
          if $AR.eq_int_int(c, SLASH) then idx
          else loop(path, path_len, idx, rem - 1)
        end
        else 0
      else 0
    end
in loop(path, path_len, path_len, $AR.checked_nat(path_len)) end

(* -- filename -- *)

implement filename {la}{na} (path, path_len) = let
  (* Scan backwards for last / *)
  fun loop {la:agz}{na:pos}{k:nat} .<k>.
    (path: !$A.borrow(byte, la, na), path_len: int na,
     i: int, rem: int(k)): int =
    if rem <= 0 then 0
    else if $AR.lte_int_int(i, 0) then 0
    else let
      val idx = i - 1
      val gi = g1ofg0(idx)
    in
      if gi >= 0 then
        if gi < path_len then let
          val c = byte2int0($A.read<byte>(path, gi))
        in
          if $AR.eq_int_int(c, SLASH) then i
          else loop(path, path_len, idx, rem - 1)
        end
        else 0
      else 0
    end
in loop(path, path_len, path_len, $AR.checked_nat(path_len)) end

(* -- extension -- *)

implement extension {la}{na} (path, path_len) = let
  (* Find filename start first *)
  val fname_start = filename(path, path_len)
  (* Scan backwards from end for last . after filename start *)
  fun loop {la:agz}{na:pos}{k:nat} .<k>.
    (path: !$A.borrow(byte, la, na), path_len: int na,
     i: int, fname_start: int, rem: int(k)): int =
    if rem <= 0 then path_len
    else if $AR.lte_int_int(i, fname_start) then path_len
    else let
      val idx = i - 1
      val gi = g1ofg0(idx)
    in
      if gi >= 0 then
        if gi < path_len then let
          val c = byte2int0($A.read<byte>(path, gi))
        in
          if $AR.eq_int_int(c, DOT) then i
          else loop(path, path_len, idx, fname_start, rem - 1)
        end
        else path_len
      else path_len
    end
in loop(path, path_len, path_len, fname_start, $AR.checked_nat(path_len)) end

(* -- is_absolute -- *)

implement is_absolute {la}{na} (path, path_len) = let
  val c = byte2int0($A.read<byte>(path, 0))
in $AR.eq_int_int(c, SLASH) end

(* ============================================================
   Static tests
   ============================================================ *)

fn _test_parent(): void = let
  (* Test with "/foo/bar" = [47,102,111,111,47,98,97,114] len=8 *)
  val arr = $A.alloc<byte>(8)
  val () = $A.set<byte>(arr, 0, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 1, $A.int2byte($AR.checked_byte(102)))
  val () = $A.set<byte>(arr, 2, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 3, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 4, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 5, $A.int2byte($AR.checked_byte(98)))
  val () = $A.set<byte>(arr, 6, $A.int2byte($AR.checked_byte(97)))
  val () = $A.set<byte>(arr, 7, $A.int2byte($AR.checked_byte(114)))
  val @(fz, bw) = $A.freeze<byte>(arr)
  val p = parent(bw, 8)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

fn _test_filename(): void = let
  val arr = $A.alloc<byte>(8)
  val () = $A.set<byte>(arr, 0, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 1, $A.int2byte($AR.checked_byte(102)))
  val () = $A.set<byte>(arr, 2, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 3, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 4, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 5, $A.int2byte($AR.checked_byte(98)))
  val () = $A.set<byte>(arr, 6, $A.int2byte($AR.checked_byte(97)))
  val () = $A.set<byte>(arr, 7, $A.int2byte($AR.checked_byte(114)))
  val @(fz, bw) = $A.freeze<byte>(arr)
  val f = filename(bw, 8)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

fn _test_is_absolute(): void = let
  val arr = $A.alloc<byte>(4)
  val () = $A.set<byte>(arr, 0, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 1, $A.int2byte($AR.checked_byte(102)))
  val () = $A.set<byte>(arr, 2, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 3, $A.int2byte($AR.checked_byte(111)))
  val @(fz, bw) = $A.freeze<byte>(arr)
  val b = is_absolute(bw, 4)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end

fn _test_join(): void = let
  (* base = "foo" = [102, 111, 111], name = "bar" = [98, 97, 114] *)
  val base = $A.alloc<byte>(3)
  val () = $A.set<byte>(base, 0, $A.int2byte($AR.checked_byte(102)))
  val () = $A.set<byte>(base, 1, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(base, 2, $A.int2byte($AR.checked_byte(111)))
  val name = $A.alloc<byte>(3)
  val () = $A.set<byte>(name, 0, $A.int2byte($AR.checked_byte(98)))
  val () = $A.set<byte>(name, 1, $A.int2byte($AR.checked_byte(97)))
  val () = $A.set<byte>(name, 2, $A.int2byte($AR.checked_byte(114)))
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
  val arr = $A.alloc<byte>(12)
  val () = $A.set<byte>(arr, 0, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 1, $A.int2byte($AR.checked_byte(102)))
  val () = $A.set<byte>(arr, 2, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 3, $A.int2byte($AR.checked_byte(111)))
  val () = $A.set<byte>(arr, 4, $A.int2byte($AR.checked_byte(47)))
  val () = $A.set<byte>(arr, 5, $A.int2byte($AR.checked_byte(98)))
  val () = $A.set<byte>(arr, 6, $A.int2byte($AR.checked_byte(97)))
  val () = $A.set<byte>(arr, 7, $A.int2byte($AR.checked_byte(114)))
  val () = $A.set<byte>(arr, 8, $A.int2byte($AR.checked_byte(46)))
  val () = $A.set<byte>(arr, 9, $A.int2byte($AR.checked_byte(116)))
  val () = $A.set<byte>(arr, 10, $A.int2byte($AR.checked_byte(120)))
  val () = $A.set<byte>(arr, 11, $A.int2byte($AR.checked_byte(116)))
  val @(fz, bw) = $A.freeze<byte>(arr)
  val e = extension(bw, 12)
  val () = $A.drop<byte>(fz, bw)
  val arr2 = $A.thaw<byte>(fz)
  val () = $A.free<byte>(arr2)
in end
