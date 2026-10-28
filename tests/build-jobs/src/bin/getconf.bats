(* build-jobs -- the stand-in getconf of tests/build-jobs: prints GETCONF_ANSWER and exits 0, else exits 1 with no output (keyword: build-jobs) *)
#target native
#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use result as R

implement main0 () = let
  val name = $A.alloc<byte>(15)
  val () = $A.set<byte>(name, 0, $A.int2byte(71))
  val () = $A.set<byte>(name, 1, $A.int2byte(69))
  val () = $A.set<byte>(name, 2, $A.int2byte(84))
  val () = $A.set<byte>(name, 3, $A.int2byte(67))
  val () = $A.set<byte>(name, 4, $A.int2byte(79))
  val () = $A.set<byte>(name, 5, $A.int2byte(78))
  val () = $A.set<byte>(name, 6, $A.int2byte(70))
  val () = $A.set<byte>(name, 7, $A.int2byte(95))
  val () = $A.set<byte>(name, 8, $A.int2byte(65))
  val () = $A.set<byte>(name, 9, $A.int2byte(78))
  val () = $A.set<byte>(name, 10, $A.int2byte(83))
  val () = $A.set<byte>(name, 11, $A.int2byte(87))
  val () = $A.set<byte>(name, 12, $A.int2byte(69))
  val () = $A.set<byte>(name, 13, $A.int2byte(82))
  val () = $A.set<byte>(name, 14, $A.int2byte(0))
  val buf = $A.alloc<byte>(4096)
  val got = $E.get_cstr(name, 15, buf, 4096)
  val () = $A.free<byte>(name)
in
  case+ got of
  | ~$R.none() => let val () = $A.free<byte>(buf) in exit_void(1) end
  | ~$R.some(k) => let
      fun put {l:agz}{k:nat | k <= 4096}{j:nat | j <= k} .<k - j>.
        (buf: !$A.arr(byte, l, 4096), k: int k, j: int j): void =
        if j >= k then ()
        else let
          val () = print_char(int2char0(byte2int0($A.get<byte>(buf, j))))
        in put(buf, k, j + 1) end
      val () = put(buf, k, 0)
      val () = print_newline()
      val () = $A.free<byte>(buf)
    in () end
end
