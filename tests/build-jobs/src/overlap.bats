(* build-jobs -- reads the log of the stand-in clang (keyword: build-jobs): a line "S <C file>" is a compile
   that started, "E <C file>" and "F <C file>" a compile that ended (well, failed) *)
#target native
#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R

(* The most compiles running at once in buf[0, k), and the compiles still running at its end *)
fun scan {l:agz}{k:nat | k <= 65536}{p:nat | p <= k} .<k - p>.
  (buf: !$A.arr(byte, l, 65536), k: int k, p: int p, line_start: bool, cur: int, best: int): @(int, int) =
  if p >= k then @(best, cur)
  else let
    val c = byte2int0($A.get<byte>(buf, p))
    val cur2 = (if line_start then (if c = 83 then cur + 1 else if c = 69 then cur - 1 else if c = 70 then cur - 1 else cur) else cur): int
    val best2 = (if cur2 > best then cur2 else best): int
  in scan(buf, k, p + 1, (c = 10), cur2, best2) end

(* The bytes of the NUL-terminated path in a builder's text *)
fn exact_path (b: $B.builder_v): [l:agz][n:pos | n <= 524289] @($A.arr(byte, l, n), int n) = let
  val @(small, len) = $B.into_arr(b)
  val grown = $A.alloc<byte>(len + 1)
  val @(fz, bv) = $A.freeze<byte>(small)
  val @(text, rest) = $A.borrow_split<byte>(fz, bv, len)
  val () = $A.write_borrow(grown, 0, text, len)
  val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, text, rest))
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(grown, len + 1) end

#pub fn log_overlap (path: $B.builder_v): @(int, int)

implement log_overlap (path) = let
  val @(pa, pn) = exact_path(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val opened = $F.file_open(bv, pn, $F.ReadOnly(), $F.OpenExisting(), 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ opened of
  | ~$R.err(_) => @(0, 0)
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(65536)
      val k = (case+ $F.file_read(fd, buf, 65536) of
        | ~$R.ok(n) => n
        | ~$R.err(_) => 0): [n:nat | n <= 65536] int n
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      val result = scan(buf, k, 0, true, 0, 0)
      val () = $A.free<byte>(buf)
    in result end
end
