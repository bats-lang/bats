staload "./ats2.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* ats2 -- the ATS2 toolchain bats keeps in ~/.bats/ats2 (bats-lang/bats#283).

   patsopt, the compiler from ATS to C, is not part of bats: bats finds it
   at $HOME/.bats/ats2/bin/patsopt, and `bats ats2 install` (and, when it
   is missing, bats build, check, test and run) puts it there. Building
   bats itself from bootstrap/c needs none of this: the C and its Makefile
   carry the ATS2 headers they compile against (bootstrap/c/_bats_native_stubs).

   The pin is here and nowhere else: the tarball's name, its URL and its
   SHA-256. It is the GMP build of ATS2 (the -int build's constraint
   solver computes in C int and accepts false statements, bats#264). The
   tarball is fetched with curl (bats runs curl, tar and make through the
   process package, as it runs git), and checked by bats's own SHA-256
   against the pin before anything is unpacked.

   What is installed is judged by <home>/.bats/ats2/.bats-ats2, the pin's
   name and SHA-256 on a line, written last, after patsopt is built:

     marker equal to the pin's, bin/patsopt there   already installed
     a marker of another pin (an older ATS2 of bats's) replaced
     bin/patsopt but no marker   a toolchain somebody else made (a
                                 developer's own, an -int build): used as
                                 it is, never replaced, said so
     an empty directory, or nothing   installed
     anything else (a directory with other files, a link to one)
                                 refused, left as it was: bats replaces
                                 only what it made

   An install goes through a download directory (ats2-download.XXXXXX) and
   ats2.new beside ats2 and is moved into place whole, so a run that is killed leaves no half-made
   toolchain where patsopt is looked for, and the next run clears what it
   left. libgmp and its headers are the system's (libgmp-dev on Debian and
   Ubuntu, gmp with Homebrew): bats does not install packages. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"

#define ATS2_NAME "ATS2-Postiats-gmp-0.4.2"
#define ATS2_SHA256 "73c64f1480df170d65aef5c7e5648677898855a2fa9ea2f3c0502f1b6d7e1b80"
#define ATS2_URL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-gmp-0.4.2.tgz"

(* Whether to say that nothing needed doing *)


(* sh -c script with up to three arguments ($1, $2, $3); sh's exit status.
   Its stdout is dropped and its stderr shown when it fails (run_cmd). *)
fn sh_exec {sn:nat}
  (script: string sn, a1: $B.builder_v, a2: $B.builder_v, a3: $B.builder_v): int = let
  val exec = str_to_path_arr("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, script)
  var b4 = $B.create()
  val () = bput_v(b4, "sh")
  val rc = run_cmd(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2),
    $L.list_vt_cons(mk_arg(a3), $L.list_vt_nil()))))))))
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
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

(* 0: the pinned toolchain is installed; 3: a toolchain bats did not make
   is there; 4: something else bats did not make is there, which is not
   replaced; 2: nothing usable (nothing, an empty directory, or an older
   pin's) *)
#define STATE "p=\"$1/ats2\"\nif [ -x \"$p/bin/patsopt\" ]; then\n  if [ \"$(cat \"$p/.bats-ats2\" 2>/dev/null)\" = \"$2\" ]; then exit 0; fi\n  if [ -f \"$p/.bats-ats2\" ]; then if [ -L \"$p\" ]; then exit 4; fi; exit 2; fi\n  exit 3\nfi\nif [ -f \"$p/.bats-ats2\" ] && [ ! -L \"$p\" ]; then exit 2; fi\nif [ -L \"$p\" ]; then exit 4; fi\nif [ -e \"$p\" ]; then\n  if [ -d \"$p\" ] && [ -z \"$(ls -A \"$p\")\" ]; then exit 2; fi\n  exit 4\nfi\nexit 2\n"

(* $1 the base. A private directory of this run's own, the download in it
   (fixed timeouts, a few retries); its path on stdout, or on failure what
   curl said *)
#define FETCH "d=$(mktemp -d \"$1/ats2-download.XXXXXX\") || { echo \"error: cannot make a temporary directory in $1\"; exit 1; }\nif out=$(curl -fsSL --connect-timeout 20 --max-time 900 --retry 3 --retry-delay 2 \"$2\" -o \"$d/ats2.tgz\" 2>&1); then printf '%s' \"$d\"; else rm -rf \"$d\"; printf '%s\\n' \"$out\"; exit 1; fi\n"

(* $1 the digest of the download, $2 the pin's, $3 the download's directory,
   which is this run's own and goes when the digest is not the pin's *)
#define VERIFY "if [ \"$1\" = \"$2\" ]; then exit 0; fi\nrm -rf \"$3\"\necho \"error: the ATS2 download has sha256 '$1', not the pinned '$2': nothing was installed\" >&2\nexit 1\n"

(* $1 the base, $2 the marker, $3 the download's directory: unpack, build
   patsopt, mark, and move into place *)
#define BUILD "set -e\nn=\"$1/ats2.new\"\nmkdir \"$n\"\ntar -xzf \"$3/ats2.tgz\" --no-same-owner --strip-components=1 -C \"$n\"\nrm -rf \"$3\"\nmake -j4 -C \"$n/src/CBOOT\" patsopt PATSHOME=\"$n\"\nmkdir -p \"$n/bin\"\ncp \"$n/src/CBOOT/patsopt\" \"$n/bin/patsopt\"\nprintf '%s\\n' \"$2\" > \"$n/.bats-ats2\"\na=\"$1/ats2\"\nif [ -e \"$a\" ] || [ -L \"$a\" ]; then\n  if [ -f \"$a/.bats-ats2\" ] && [ ! -L \"$a\" ]; then rm -rf \"$a\"\n  elif [ -d \"$a\" ] && [ ! -L \"$a\" ] && [ -z \"$(ls -A \"$a\")\" ]; then rmdir \"$a\"\n  else echo \"error: $a exists and was not made by bats, so it is not replaced\" >&2; exit 1; fi\nfi\nmv \"$n\" \"$a\"\n"

(* $1 the base, $2 a download's directory (or the base's own, to clear
   only what a run killed before this one left): this module's own files,
   ats2.new and ats2-download.* *)
#define CLEAR "rm -rf \"$1/ats2.new\" \"$1/ats2.tgz.part\" \"$1\"/ats2-download.*\n"
#define CLEAR_ONE "rm -rf \"$1/ats2.new\" \"$2\"\n"

(* The lock that makes two installs one: $HOME/.bats/ats2.lock, held with
   the file package's flock while ats2 is installed (what is installed is
   judged again under it) *)
fn lock_take (): $R.option($F.fd) = let
  val _ = sh_exec("mkdir -p \"$1\"", base_arg(), empty_arg(), empty_arg())
  var p : $B.builder_v = $B.create()
  val _ = env_value("HOME", p)
  val () = bput_v(p, "/.bats/ats2.lock")
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val opened = file_open_path(bv_p, $F.ReadWrite(), $F.CreateOrOpen(), 420)
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
  val @(pa, _) = $B.to_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  var got : $B.builder_v = $B.create()
  val _ = put_file_sha256(bv_p, got)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in got end

fn dir_arg {l:agz} (out: !$A.borrow(byte, l, 4096), n: int): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(out, 0, n, 4096, b)
in b end

(* The install itself, under the lock: false (said) when it fails *)
fn install_now (): bool = let
  val _ = sh_exec(CLEAR, base_arg(), empty_arg(), empty_arg())
  val () = println! ("ATS2 not found, installing ", ATS2_NAME, " into ~/.bats/ats2 ...")
  val out = $A.alloc<byte>(4096)
  val @(fexec, fbv) = let
    val e = str_to_path_arr("sh")
  in $A.freeze<byte>(e) end
  var s1 = $B.create()
  val () = bput_v(s1, "sh")
  var s2 = $B.create()
  val () = bput_v(s2, "-c")
  var s3 = $B.create()
  val () = bput_v(s3, FETCH)
  var s4 = $B.create()
  val () = bput_v(s4, "sh")
  val @(rc, k) = run_cmd_capture(fbv, $L.list_vt_cons(mk_arg(s1), $L.list_vt_cons(mk_arg(s2),
    $L.list_vt_cons(mk_arg(s3), $L.list_vt_cons(mk_arg(s4),
    $L.list_vt_cons(mk_arg(base_arg()), $L.list_vt_cons(mk_arg(text_arg(ATS2_URL)), $L.list_vt_nil())))))), out)
  val () = $A.drop<byte>(fexec, fbv)
  val () = $A.free<byte>($A.thaw<byte>(fexec))
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
      val built = sh_exec(BUILD, base_arg(), marker_arg(), dir_arg(bv_o, k))
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
        val () = println! ("ATS2 installed successfully")
      in true end
    end
  end
end

(* A toolchain bats did not make: used as it is, and said on every run, on
   stderr, because an -int build computes in C int and accepts false
   statements (bats#264) *)
val g_warned = ref<bool>(false)

fn warn_foreign (): void = if !g_warned then () else let
  val () = !g_warned := true
  var b : $B.builder_v = $B.create()
  val _ = env_value("HOME", b)
  val () = bput_v(b, "/.bats/ats2")
  val () = prerr! ("warning: the ATS2 in ")
  val () = prerr_builder(b)
in prerr! (" was not installed by bats and is not checked against the pinned ", ATS2_NAME, " (an -int build accepts false statements, bats#264)\n") end



implement ats2_ensure (talk) =
  if ~home_set() then let
    val () = set_build_err()
  in prerr! ("error: HOME is not set, so bats cannot find or install ATS2 (~/.bats/ats2)\n"); false end
  else let
    val state = sh_exec(STATE, base_arg(), marker_arg(), empty_arg())
  in
    if state = 0 then let
      val () = (case+ talk of
        | Say() => println! ("ATS2 (", ATS2_NAME, ") is already installed in ~/.bats/ats2")
        | Quiet() => ())
    in true end
    else if state = 3 then let
      val () = warn_foreign()
    in true end
    else if state = 4 then let
      val () = prerr! ("error: ~/.bats/ats2 exists, is not a toolchain bats made and is not an empty directory, so bats does not replace it: move it away and run bats ats2 install\n")
    in false end
    else if state <> 2 then false
    else let
      val lk = lock_take()
      (* judged again under the lock: another bats may have installed it *)
      val again = sh_exec(STATE, base_arg(), marker_arg(), empty_arg())
      val ok = (if again = 2 then install_now() else (again = 0 || again = 3)): bool
      val () = lock_release(lk)
    in ok end
  end
