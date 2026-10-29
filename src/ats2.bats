(* ats2 -- the ATS2 toolchain bats keeps in ~/.bats/ats2 (bats-lang/bats#283, #264).

   patsopt, the compiler from ATS to C, is not part of bats: bats finds it
   at $HOME/.bats/ats2/bin/patsopt, and `bats ats2 install` (and, when it
   is absent, bats build, check, test and run) puts it there. Building
   bats itself from bootstrap/c needs none of this.

   The pin is here and nowhere else: the tarball's name, its URL and its
   SHA-256. It is the GMP build of ATS2 (the -int build's constraint
   solver computes in C int and accepts false statements). The tarball is
   fetched with curl and checked by bats's own SHA-256 against the pin
   before anything is unpacked.

   bats uses only a toolchain it made whole (area: ats2 made whole, in
   .claude/rules/ats2-install.md). An install builds in ~/.bats/ats2-temp,
   writes the marker .bats-ats2 (the pin's name and SHA-256) inside it,
   checks it, and moves the whole directory to ~/.bats/ats2 with one
   rename, so ~/.bats/ats2 is a complete marked toolchain or absent:

     absent                          installed
     marker equal to the pin's       used
     no marker, another pin's marker an error naming what was found, and
                                     nothing is deleted
     bats ats2 install --force       builds in ats2-temp first, then removes
                                     what is at ats2 and renames: the one
                                     way to replace it

   libgmp and its headers are the system's (libgmp-dev on Debian and
   Ubuntu, gmp with Homebrew): bats does not install packages. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use list as L
#use process as P
#use result as R

staload "helpers.sats"

#define ATS2_NAME "ATS2-Postiats-gmp-0.4.2"
#define ATS2_SHA256 "73c64f1480df170d65aef5c7e5648677898855a2fa9ea2f3c0502f1b6d7e1b80"
#define ATS2_URL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-gmp-0.4.2.tgz"

(* Whether to say that nothing needed doing *)
#pub datatype ats2_talk = Say | Quiet

(* The state of ~/.bats/ats2 (ats2 made whole, .claude/rules/ats2-install.md): STATE's exit status, read once by ats2_state_of_status *)
datatype ats2_state = Whole | Absent | NoMarker | OtherPin | NoPatsopt | StateFailed

(* A plain install is for an absent ~/.bats/ats2; a forced one replaces what is there once ats2-temp is whole (ats2 made whole) *)
datatype ats2_install_mode = PlainInstall | ForcedInstall

(* sh -c script with up to three arguments ($1, $2, $3); sh's exit status.
   Its stdout is dropped and its stderr shown when it fails (run_cmd). *)
fn sh_exec {sn:nat}
  (script: string sn, a1: $B.builder_v, a2: $B.builder_v, a3: $B.builder_v): int = let
  val (nul_x | exec) = $P.path_of_string_proved("sh")
  val @(fz_x, bv_x) = $A.barr_freeze(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, script)
  var b4 = $B.create()
  val () = bput_v(b4, "sh")
  val rc = run_cmd(nul_x | bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2),
    $L.list_vt_cons(mk_arg(a3), $L.list_vt_nil()))))))))
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
in rc end

fn empty_arg (): $B.builder_v = $B.create()

(* $HOME/.bats as a builder (empty when HOME is not set) *)
fn base_arg (): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val has = env_value("HOME", b)
  val () = (if has then bput_v(b, "/.bats") else ())
in b end

(* The marker's text: the pin's name and SHA-256 *)
fn marker_arg (): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, ATS2_NAME)
  val () = bput_v(b, " ")
  val () = bput_v(b, ATS2_SHA256)
in b end

fn text_arg {sn:nat} (s: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, s)
in b end

fn home_set (): bool = let
  var t : $B.builder_v = $B.create()
  val has = env_value("HOME", t)
  val () = $B.builder_free(t)
in has end

(* STATE: exits with the status ats2_state_of_status reads; every state but Whole and Absent says its error on stderr and deletes nothing (ats2 made whole, ats2-install.md) *)
#define STATE "p=\"$1/ats2\"\nif [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then exit 2; fi\nuse=\"bats never deletes what is at ~/.bats/ats2 by itself; to replace it with the toolchain this bats needs, run: bats ats2 install --force\"\nif [ -f \"$p/.bats-ats2\" ]; then\n  m=$(cat \"$p/.bats-ats2\" 2>/dev/null)\n  if [ \"$m\" = \"$2\" ]; then\n    if [ -x \"$p/bin/patsopt\" ]; then exit 0; fi\n    echo \"error: ~/.bats/ats2 has the marker of this bats's pin but no bin/patsopt, so it is not a whole toolchain; $use\" >&2\n    exit 5\n  fi\n  echo \"error: ~/.bats/ats2 has the marker '$m' and this bats needs '$2'; $use\" >&2\n  exit 4\nfi\necho \"error: ~/.bats/ats2 has no marker .bats-ats2, so bats did not make it (a toolchain of your own, an -int build, anything else); $use\" >&2\nexit 3\n"

fn ats2_state_of_status (status: int): ats2_state =
  if status = 0 then Whole()
  else if status = 2 then Absent()
  else if status = 3 then NoMarker()
  else if status = 4 then OtherPin()
  else if status = 5 then NoPatsopt()
  else StateFailed()

fn ats2_state_now (): ats2_state =
  ats2_state_of_status(sh_exec(STATE, base_arg(), marker_arg(), empty_arg()))

(* The shell argument of PLACE for a mode, made here and nowhere else *)
fn mode_arg (mode: ats2_install_mode): $B.builder_v =
  case+ mode of
  | PlainInstall() => text_arg("0")
  | ForcedInstall() => text_arg("1")

(* $1 the base. A private directory of this run's own, the download in it
   (fixed timeouts, a few retries); its path on stdout, or on failure what
   curl said *)
#define FETCH "d=$(mktemp -d \"$1/ats2-download.XXXXXX\") || { echo \"error: cannot make a temporary directory in $1\"; exit 1; }\nif out=$(curl -fsSL --connect-timeout 20 --max-time 900 --retry 3 --retry-delay 2 \"$2\" -o \"$d/ats2.tgz\" 2>&1); then printf '%s' \"$d\"; else rm -rf \"$d\"; printf '%s\\n' \"$out\"; exit 1; fi\n"

(* $1 the digest of the download, $2 the pin's, $3 the download's directory,
   which is this run's own and goes when the digest is not the pin's *)
#define VERIFY "if [ \"$1\" = \"$2\" ]; then exit 0; fi\nrm -rf \"$3\"\necho \"error: the ATS2 download has sha256 '$1', not the pinned '$2': nothing was installed\" >&2\nexit 1\n"

(* BUILD: unpack and build patsopt in ats2-temp; the marker is bats's write_marker, and PLACE moves the directory (ats2 made whole, ats2-install.md) *)
#define BUILD "set -e\nn=\"$1/ats2-temp\"\nmkdir \"$n\"\ntar -xzf \"$2/ats2.tgz\" --no-same-owner --strip-components=1 -C \"$n\"\nrm -rf \"$2\"\nmake -j4 -C \"$n/src/CBOOT\" patsopt PATSHOME=\"$n\"\nmkdir -p \"$n/bin\"\ncp \"$n/src/CBOOT/patsopt\" \"$n/bin/patsopt\"\n"

(* PLACE: $1 the base, $2 the pin's marker, $3 mode_arg (1 replaces what is at ats2). ats2-temp must hold the marker and bin/patsopt; then, with --force only, what is at ats2 goes (a link itself, never its target), and one rename puts ats2-temp in place (ats2 made whole, ats2-install.md) *)
#define PLACE "n=\"$1/ats2-temp\"\na=\"$1/ats2\"\nif [ \"$(cat \"$n/.bats-ats2\" 2>/dev/null)\" != \"$2\" ] || [ ! -x \"$n/bin/patsopt\" ]; then echo \"error: the ATS2 built in ~/.bats/ats2-temp has no marker of the pin or no bin/patsopt: nothing was moved\" >&2; exit 1; fi\nif [ \"$3\" = 1 ]; then rm -rf \"$a\" || { echo \"error: cannot remove ~/.bats/ats2: nothing was moved\" >&2; exit 1; }\nelif [ -e \"$a\" ] || [ -L \"$a\" ]; then echo \"error: ~/.bats/ats2 appeared during the install, so it is not replaced: nothing was moved\" >&2; exit 1; fi\nmv \"$n\" \"$a\"\n"

(* CLEAR: this module's own leftovers, ats2-temp (the one directory bats removes by itself) and ats2-download.*; CLEAR_ONE also the run's download directory $2 *)
#define CLEAR "rm -rf \"$1/ats2-temp\" \"$1\"/ats2-download.*\n"
#define CLEAR_ONE "rm -rf \"$1/ats2-temp\" \"$2\"\n"

(* The lock that makes two installs one: $HOME/.bats/ats2.lock, held with
   the file package's flock while ats2 is installed (what is installed is
   judged again under it) *)
fn lock_take (): $R.option($F.fd) = let
  val _ = sh_exec("mkdir -p \"$1\"", base_arg(), empty_arg(), empty_arg())
  var p : $B.builder_v = $B.create()
  val _ = env_value("HOME", p)
  val () = bput_v(p, "/.bats/ats2.lock")
  val () = put_char_v(p, 0)
  val @(pa, pal) = $B.into_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val opened = file_open_m(bv_p, pal, $F.ReadWrite(), $F.CreateOrOpen(), 420)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in
  case+ opened of
  | ~$R.err(_) => $R.none()
  | ~$R.ok(fd) =>
    (case+ $F.fd_lock(fd, $F.LockExclusive(), $F.LockFailsAtOnce()) of
    | ~$R.ok(_) => $R.some(fd)
    | ~$R.err(e) =>
      (case+ e of
      | $F.WouldBlock() => let
          val () = prerr! ("waiting for another bats installing ATS2 (it holds ~/.bats/ats2.lock)\n")
        in
          case+ $F.fd_lock(fd, $F.LockExclusive(), $F.LockWaits()) of
          | ~$R.ok(_) => $R.some(fd)
          | ~$R.err(_) => let
              val () = $R.discard<int><$F.io_error>($F.file_close(fd))
            in $R.none() end
        end
      | _ => let
          val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        in $R.none() end))
end

fn lock_release (lk: $R.option($F.fd)): void =
  case+ lk of
  | ~$R.some(fd) => $R.discard<int><$F.io_error>($F.file_close(fd))
  | ~$R.none() => ()

(* The SHA-256 of ats2.tgz in the directory the n bytes of out name, as
   bats computes it; a file that cannot be read gives no digest, which is
   no match *)
fn download_digest {l:agz} (out: !$A.borrow(byte, l, 4096), n: int): $B.builder_v = let
  var path : $B.builder_v = $B.create()
  val () = copy_to_builder_v(out, 0, n, 4096, path)
  val () = bput_v(path, "/ats2.tgz")
  val () = put_char_v(path, 0)
  val @(pa, pal) = $B.into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  var got : $B.builder_v = $B.create()
  val _ = put_file_sha256_m(bv_p, pal, got)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in got end

fn dir_arg {l:agz} (out: !$A.borrow(byte, l, 4096), n: int): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(out, 0, n, 4096, b)
in b end

(* write_marker: the marker, written by bats through write_settle inside ats2-temp, before the rename (ats2 made whole, ats2-install.md) *)
fn write_marker (): int = let
  var marker_text : $B.builder_v = marker_arg()
  val () = put_char_v(marker_text, 10)
  var marker_path : $B.builder_v = base_arg()
  val () = bput_v(marker_path, "/ats2-temp/.bats-ats2")
  val @(marker_array, marker_length) = $B.into_arr(marker_path)
  val @(marker_frozen, marker_view) = $A.freeze<byte>(marker_array)
  val marker_status = write_settle(marker_view, marker_length, write_file_from_builder_m(marker_view, marker_length, marker_text))
  val () = $A.drop<byte>(marker_frozen, marker_view)
  val () = $A.free<byte>($A.thaw<byte>(marker_frozen))
in marker_status end

(* The install itself, under the lock: false (said) when it fails; ForcedInstall replaces what is at ats2 after ats2-temp is whole *)
fn install_now (mode: ats2_install_mode): bool = let
  val _ = sh_exec(CLEAR, base_arg(), empty_arg(), empty_arg())
  val () = println! ("installing ", ATS2_NAME, " into ~/.bats/ats2 ...")
  val out = $A.alloc<byte>(4096)
  val (nul_fetch | fetch_exec) = $P.path_of_string_proved("sh")
  val @(fexec, fbv) = $A.barr_freeze(fetch_exec)
  var s1 = $B.create()
  val () = bput_v(s1, "sh")
  var s2 = $B.create()
  val () = bput_v(s2, "-c")
  var s3 = $B.create()
  val () = bput_v(s3, FETCH)
  var s4 = $B.create()
  val () = bput_v(s4, "sh")
  val outcome = run_cmd_capture_outcome(nul_fetch | fbv, $L.list_vt_cons(mk_arg(s1), $L.list_vt_cons(mk_arg(s2),
    $L.list_vt_cons(mk_arg(s3), $L.list_vt_cons(mk_arg(s4),
    $L.list_vt_cons(mk_arg(base_arg()), $L.list_vt_cons(mk_arg(text_arg(ATS2_URL)), $L.list_vt_nil())))))), out)
  (* the script prints one directory name on success: a longer output is a failure (its first 4096 bytes said), never a directory (capture area) *)
  val @(rc, k) = (case+ outcome of
    | ~CaptureFits(n) => @(0, n)
    | ~CaptureFailed(status, n) => @(status, n)
    | ~CaptureLonger(status, _, _) => @((if status = 0 then ~1 else status), 4096)
    | ~CaptureReadFailed(n, _) => @(~1, n)
    | ~CaptureWaitFailed(n, _, _) => @(~1, n)
    | ~CaptureNotRun(e) => @(0 - e, 0)): @(int, [k:nat | k <= 4096] int k)
  val () = $A.cborrow_drop(fexec, fbv)
  val () = $A.barr_free($A.barr_thaw(fexec))
  val @(fz_o, bv_o) = $A.freeze<byte>(out)
in
  if rc <> 0 then let
    val () = (if k > 0 then prerr_seg(bv_o, 0, k, 4096) else ())
    val () = $A.drop<byte>(fz_o, bv_o)
    val () = $A.free<byte>($A.thaw<byte>(fz_o))
  in false end
  else let
    val checked = sh_exec(VERIFY, download_digest(bv_o, k), text_arg(ATS2_SHA256), dir_arg(bv_o, k))
  in
    if checked <> 0 then let
      val () = $A.drop<byte>(fz_o, bv_o)
      val () = $A.free<byte>($A.thaw<byte>(fz_o))
    in false end
    else let
      val () = println! ("building patsopt ...")
      val built = sh_exec(BUILD, base_arg(), dir_arg(bv_o, k), empty_arg())
    in
      if built <> 0 then let
        val _ = sh_exec(CLEAR_ONE, base_arg(), dir_arg(bv_o, k), empty_arg())
        val () = $A.drop<byte>(fz_o, bv_o)
        val () = $A.free<byte>($A.thaw<byte>(fz_o))
        val () = println! ("note: the ATS2 build bats installs does its constraint solving in infinite precision (GMP), so it needs libgmp and its headers (libgmp-dev on Debian and Ubuntu, gmp on macOS with Homebrew), and make and a C compiler")
      in false end
      else let
        val () = $A.drop<byte>(fz_o, bv_o)
        val () = $A.free<byte>($A.thaw<byte>(fz_o))
        val marked = write_marker()
      in
        if marked <> 0 then let
          val _ = sh_exec(CLEAR, base_arg(), empty_arg(), empty_arg())
        in false end
        else let
          val placed = sh_exec(PLACE, base_arg(), marker_arg(), mode_arg(mode))
        in
          if placed <> 0 then let
            val _ = sh_exec(CLEAR, base_arg(), empty_arg(), empty_arg())
          in false end
          else let
            val () = println! ("ATS2 installed successfully")
          in true end
        end
      end
    end
  end
end

fn no_home (): bool = let
  val () = set_build_err()
in prerr! ("error: HOME is not set, so bats cannot find or install ATS2 (~/.bats/ats2)\n"); false end

#pub fn ats2_ensure (talk: ats2_talk): bool

implement ats2_ensure (talk) =
  if ~home_set() then no_home()
  else
    case+ ats2_state_now() of
    | Whole() => let
        val () = (case+ talk of
          | Say() => println! ("ATS2 (", ATS2_NAME, ") is already installed in ~/.bats/ats2")
          | Quiet() => ())
      in true end
    | Absent() => let
        val lk = lock_take()
        (* judged again under the lock: another bats may have installed it *)
        val ok = (case+ ats2_state_now() of
          | Absent() => install_now(PlainInstall())
          | Whole() => true
          | NoMarker() => false
          | OtherPin() => false
          | NoPatsopt() => false
          | StateFailed() => false): bool
        val () = lock_release(lk)
      in ok end
    | NoMarker() => false
    | OtherPin() => false
    | NoPatsopt() => false
    | StateFailed() => false

#pub fn ats2_install_force (): bool

(* bats ats2 install --force: the one way to replace what is at ~/.bats/ats2 *)
implement ats2_install_force () =
  if ~home_set() then no_home()
  else let
    val lk = lock_take()
    val ok = install_now(ForcedInstall())
    val () = lock_release(lk)
  in ok end

#pub fn ats2_print_marker (): void

(* bats ats2 marker: the marker text of the pin, the one source the tests write into a toolchain of their own (ats2 made whole) *)
implement ats2_print_marker () = println! (ATS2_NAME, " ", ATS2_SHA256)
