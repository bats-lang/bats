(* capture-outcome -- plays run_cmd_capture_outcome against real children (bats#444) *)
#target native
#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use list as L
#use process as P

staload "helpers.sats"

(* One child: sh -c <script>, its outcome printed as one line *)
fn play {sn:nat} (name: string, script: string sn): void = let
  val (nul_x | exec) = $P.path_of_string_proved("sh")
  val @(fz_x, bv_x) = $A.barr_freeze(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, script)
  val out = $A.alloc<byte>(4096)
  val outcome = run_cmd_capture_outcome(nul_x | bv_x, $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))), out)
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
  val () = $A.free<byte>(out)
in
  case+ outcome of
  | ~CaptureFits(n) => println! (name, ": fits ", n)
  | ~CaptureFailed(status, n) => println! (name, ": failed status=", status, " kept=", n)
  | ~CaptureLonger(status, mebi, rest) => println! (name, ": longer status=", status, " written=", mebi, "*1048576+", rest)
  | ~CaptureReadFailed(n, _) => println! (name, ": read-failed kept=", n)
  | ~CaptureWaitFailed(n, mebi, rest) => println! (name, ": wait-failed kept=", n, " written=", mebi, "*1048576+", rest)
  | ~CaptureNotRun(errno) => println! (name, ": not-run")
end

(* The old form, kept beside the new one for a version (repository-prototype#381) *)
fn play_old (): void = let
  val (nul_x | exec) = $P.path_of_string_proved("sh")
  val @(fz_x, bv_x) = $A.barr_freeze(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, "printf abc; exit 3")
  val out = $A.alloc<byte>(4096)
  val @(status, n) = run_cmd_capture(nul_x | bv_x, $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))), out)
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
  val () = $A.free<byte>(out)
in println! ("old-form: status=", status, " len=", n) end

implement main0 () = let
  val () = play_old()
  val () = play("small", "printf abc")
  val () = play("empty", "true")
  val () = play("paused", "printf aaaa; sleep 0.3; printf bbbb")
  val () = play("failed", "printf abc; exit 3")
  val () = play("exact", "head -c 4096 /dev/zero")
  val () = play("one-over", "head -c 4097 /dev/zero")
  val () = play("pieces", "i=0; while [ $i -lt 20 ]; do head -c 500 /dev/zero; sleep 0.05; i=$((i+1)); done")
  val () = play("longer-failed", "head -c 10000 /dev/zero; exit 5")
  val () = play("pipe-full", "head -c 300000 /dev/zero; sleep 0.2; exit 0")
  val () = play("stderr-heavy", "head -c 300000 /dev/zero >&2; printf ok")
  val () = play("killed", "printf abc; kill -9 $$")
  val () = play("killed-longer", "head -c 5000 /dev/zero; kill -9 $$")
  val () = play("past-1gib", "head -c 1073746824 /dev/zero")
in end
