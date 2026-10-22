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
   name and SHA-256 on a line, written by bats through write_settle last,
   after the toolchain is moved into place (bats-lang/bats#372):

     marker equal to the pin's, bin/patsopt there   already installed
     a marker of another pin (an older ATS2 of bats's) replaced
     bin/patsopt but no marker   a toolchain somebody else made (a
                                 developer's own, an -int build): used as
                                 it is, never replaced, said so
     an empty directory, or nothing   installed
     anything else (a directory with other files, a link to one)
                                 refused, left as it was: bats replaces
                                 only what it made
     a directory with other files and no bin/patsopt
                                 refused, naming bin/patsopt, left as it was

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
   replaced; 5: a directory bats did not make, with files and no bin/patsopt
   (a part of a toolchain: named as such, not replaced); 2: nothing usable
   (nothing, an empty directory, or an older pin's) *)
#define STATE "p=\"$1/ats2\"\nif [ -x \"$p/bin/patsopt\" ]; then\n  if [ \"$(cat \"$p/.bats-ats2\" 2>/dev/null)\" = \"$2\" ]; then exit 0; fi\n  if [ -f \"$p/.bats-ats2\" ]; then if [ -L \"$p\" ]; then exit 4; fi; exit 2; fi\n  exit 3\nfi\nif [ -f \"$p/.bats-ats2\" ] && [ ! -L \"$p\" ]; then exit 2; fi\nif [ -L \"$p\" ]; then exit 4; fi\nif [ -e \"$p\" ]; then\n  if [ -d \"$p\" ] && [ -z \"$(ls -A \"$p\")\" ]; then exit 2; fi\n  if [ -d \"$p\" ] && [ ! -L \"$p\" ] && [ ! -e \"$p/bin/patsopt\" ]; then exit 5; fi\n  exit 4\nfi\nexit 2\n"

(* $1 the base. A private directory of this run's own, the download in it
   (fixed timeouts, a few retries); its path on stdout, or on failure what
   curl said *)
#define FETCH "d=$(mktemp -d \"$1/ats2-download.XXXXXX\") || { echo \"error: cannot make a temporary directory in $1\"; exit 1; }\nif out=$(curl -fsSL --connect-timeout 20 --max-time 900 --retry 3 --retry-delay 2 \"$2\" -o \"$d/ats2.tgz\" 2>&1); then printf '%s' \"$d\"; else rm -rf \"$d\"; printf '%s\\n' \"$out\"; exit 1; fi\n"

(* $1 the digest of the download, $2 the pin's, $3 the download's directory,
   which is this run's own and goes when the digest is not the pin's *)
#define VERIFY "if [ \"$1\" = \"$2\" ]; then exit 0; fi\nrm -rf \"$3\"\necho \"error: the ATS2 download has sha256 '$1', not the pinned '$2': nothing was installed\" >&2\nexit 1\n"

(* BUILD: unpack, build and move patsopt into place, the marker is bats's write_marker after the move (bats#372, ats2-install.md) *)
#define BUILD "set -e\nn=\"$1/ats2.new\"\nmkdir \"$n\"\ntar -xzf \"$2/ats2.tgz\" --no-same-owner --strip-components=1 -C \"$n\"\nrm -rf \"$2\"\nmake -j4 -C \"$n/src/CBOOT\" patsopt PATSHOME=\"$n\"\nmkdir -p \"$n/bin\"\ncp \"$n/src/CBOOT/patsopt\" \"$n/bin/patsopt\"\na=\"$1/ats2\"\nif [ -e \"$a\" ] || [ -L \"$a\" ]; then\n  if [ -f \"$a/.bats-ats2\" ] && [ ! -L \"$a\" ]; then rm -rf \"$a\"\n  elif [ -d \"$a\" ] && [ ! -L \"$a\" ] && [ -z \"$(ls -A \"$a\")\" ]; then rmdir \"$a\"\n  else echo \"error: $a exists and was not made by bats, so it is not replaced\" >&2; exit 1; fi\nfi\nmv \"$n\" \"$a\"\n"

(* $1 the base, $2 a download's directory (or the base's own, to clear
   only what a run killed before this one left): this module's own files,
   ats2.new and ats2-download.* *)
#define CLEAR "rm -rf \"$1/ats2.new\" \"$1/ats2.tgz.part\" \"$1\"/ats2-download.*\n"
#define CLEAR_ONE "rm -rf \"$1/ats2.new\" \"$2\"\n"

(* MOVED_CLEAR: a failed marker write removes the moved toolchain, marker first, status 2/3 say which step failed (bats#372, ats2-install.md) *)
#define MOVED_CLEAR "rm -rf \"$1/ats2/.bats-ats2\" || exit 2\nrm -rf \"$1/ats2\" || exit 3\n"

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

(* write_marker: the marker, written by bats through write_settle after the move (bats#372, ats2-install.md) *)
fn write_marker (): int = let
  var marker_text : $B.builder_v = marker_arg()
  val () = put_char_v(marker_text, 10)
  var marker_path : $B.builder_v = base_arg()
  val () = bput_v(marker_path, "/ats2/.bats-ats2")
  val @(marker_array, marker_length) = $B.into_arr(marker_path)
  val @(marker_frozen, marker_view) = $A.freeze<byte>(marker_array)
  val marker_status = write_settle(marker_view, marker_length, write_file_from_builder_m(marker_view, marker_length, marker_text))
  val () = $A.drop<byte>(marker_frozen, marker_view)
  val () = $A.free<byte>($A.thaw<byte>(marker_frozen))
in marker_status end

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
          (* write_marker failed: MOVED_CLEAR removes the moved toolchain, and the message follows its status (bats#372) *)
          val cleared = sh_exec(MOVED_CLEAR, base_arg(), empty_arg(), empty_arg())
          val () = (if cleared = 0
            then prerr! ("error: the ATS2 toolchain bats moved into ~/.bats/ats2 was removed again, so the next bats ats2 install starts from nothing\n")
            else if cleared = 2
            then prerr! ("error: the ATS2 toolchain bats moved into ~/.bats/ats2 could not be removed, and its marker .bats-ats2 may still be there and claim a complete install: remove ~/.bats/ats2 by hand before the next bats ats2 install\n")
            else prerr! ("error: the marker of the ATS2 toolchain bats moved into ~/.bats/ats2 was removed, but the rest of the toolchain could not be: it is still there with no marker, so the next bats ats2 install would use it as it is; move it away before then\n"))
        in false end
        else let
          val () = println! ("ATS2 installed successfully")
        in true end
      end
    end
  end
end

(* What a toolchain bats did not make does with a false statement (bats#264).
   The probe is the statement of the issue: the -int build of the solver
   accepts it (in well under a second here), the GMP build does not, and it
   runs past 100 s on it here, so a cap ends it. A control, a true
   statement, must be accepted first, so a patsopt that checks nothing is
   no answer. The answer is patsopt's exit status, and no name or path
   says it, so renaming a directory does not change it. The cap is 20 s:
   the -int build's answer is far below it, and a slower machine gives
   "cannot tell", never a wrong kind.

   The shell only runs patsopt and says its status. Every file the probe
   writes is bats's, through write_settle (bats-lang/bats#359): the two
   sources, in a directory the shell made with mktemp and removes after the
   run, and the answer kept in ~/.bats/ats2.solver. The run's exit status:
   20 accepted (the -int build); 21 refused; 22 no answer, not kept (the
   control failed, patsopt died without an answer, ended by a signal, or
   exited with a status other than 1); 24 no answer within the cap, kept as
   22. A patsopt that is past the cap is sent TERM at 20 s and KILL at 25 s,
   and a status of 143 or 137 is taken for that; 23: no temporary
   directory. An answer of 20 or 21, and 22 for a probe past the cap, is
   kept in ~/.bats/ats2.solver as "<cksum of bin/patsopt> <20|21|22>" (the
   bytes, not the path, so a toolchain is probed once and a renamed one is
   not). A patsopt that is killed together with its shell gives no status
   and is not kept. No file's time is read. *)
#define PROBE_CONTROL "#include \"share/atspre_staload.hats\"\nprfn bats_probe_true {n:nat | n < 65536} (): [n < 65536] void = ()\n"
#define PROBE_FALSE "#include \"share/atspre_staload.hats\"\nprfn bats_probe_false {h,l:nat | h < 65536; l < 65536;\n  (h/256 + 256*(l%256))/256 + 256*((l/256 + 256*(h%256))%256) == l} (): [1 == 2] void = ()\n"

(* The cksum of bin/patsopt, as cksum prints it, with no newline *)
#define PROBE_SUM "c=$(cksum < \"$1/ats2/bin/patsopt\") || exit 22\nprintf '%s' \"$c\"\n"

(* The kept answer for the cksum $2: its exit status is the answer, 9 when none is kept *)
#define PROBE_KEPT "if [ -f \"$1/ats2.solver\" ]; then\n  case $(cat \"$1/ats2.solver\") in\n    \"$2 20\") exit 20 ;;\n    \"$2 21\") exit 21 ;;\n    \"$2 22\") exit 22 ;;\n  esac\nfi\nexit 9\n"

(* A new directory of the probe's, its name printed *)
#define PROBE_MAKE "d=$(mktemp -d \"$1/ats2-probe.XXXXXX\") || exit 23\nprintf '%s' \"$d\"\n"

(* patsopt on the control, then on the false statement in $2, each capped; its
   status is the answer (see above). Its output is dropped, as a probe's is. *)
#define PROBE_RUN "P=\"$1/ats2/bin/patsopt\"\nexport PATSHOME=\"$1/ats2\"\ncapped() {\n  \"$P\" -tc -d \"$1\" > /dev/null 2>&1 &\n  p=$!\n  ( sleep 20; kill -TERM \"$p\" 2>/dev/null; sleep 5; kill -KILL \"$p\" 2>/dev/null ) 2>&- &\n  w=$!\n  wait \"$p\"\n  r=$?\n  kill \"$w\" 2>/dev/null\n  wait \"$w\" 2>/dev/null\n  case $r in 137|143) return 124 ;; esac\n  return $r\n}\ncapped \"$2/control.dats\"\nif [ $? -ne 0 ]; then exit 22; fi\ncapped \"$2/false.dats\"\nf=$?\nif [ $f -eq 0 ]; then exit 20; fi\nif [ $f -eq 124 ]; then exit 24; fi\nif [ $f -eq 1 ]; then exit 21; fi\nexit 22\n"

#define PROBE_CLEAR "rm -rf \"$1\"\n"

datatype solver_kind = SolverInt | SolverRefusesFalse | SolverNoAnswer

(* sh -c with two arguments, its stdout kept in out (at most 4096 bytes) *)
fn sh_capture {sn:nat}{lo:agz}
  (script: string sn, a1: $B.builder_v, a2: $B.builder_v, out: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k) = let
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
  val r = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2), $L.list_vt_nil())))))), out)
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in r end

(* The status of a script, and what it printed (at most 4096 bytes) *)
fn capture_text {sn:nat} (script: string sn, a1: $B.builder_v): @(int, $B.builder_v) = let
  val out = $A.alloc<byte>(4096)
  val @(rc, k) = sh_capture(script, a1, empty_arg(), out)
  val @(fz_o, bv_o) = $A.freeze<byte>(out)
  val b = dir_arg(bv_o, k)
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
in @(rc, b) end

(* dir/name, written with content: write_settle says why it failed, and the
   result is its 0 or ~1 *)
fn probe_write {l:agz}{sa:nat}{sb:nat}
  (out: !$A.borrow(byte, l, 4096), n: int, name: string sa, content: string sb): int = let
  var p : $B.builder_v = $B.create()
  val () = copy_to_builder_v(out, 0, n, 4096, p)
  val () = bput_v(p, "/")
  val () = bput_v(p, name)
  val @(pa, pal) = $B.into_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  var c : $B.builder_v = $B.create()
  val () = bput_v(c, content)
  val rc = write_settle(bv_p, pal, write_file_from_builder_m(bv_p, pal, c))
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in rc end

(* the two sources are written and patsopt run on them: the code of the run,
   or ~1 when a source could not be written or no directory was made *)
fn probe_answer {l:agz} (rc_m: int, bv_o: !$A.borrow(byte, l, 4096), n: int): int =
  if rc_m <> 0 then ~1
  else if probe_write(bv_o, n, "control.dats", PROBE_CONTROL) <> 0 then ~1
  else if probe_write(bv_o, n, "false.dats", PROBE_FALSE) <> 0 then ~1
  else sh_exec(PROBE_RUN, base_arg(), dir_arg(bv_o, n), empty_arg())

fn kind_of_code (code: int): solver_kind =
  if code = 20 then SolverInt()
  else if code = 21 then SolverRefusesFalse()
  else SolverNoAnswer()

(* the answer a run's code keeps, or ~1 for a code that is not kept *)
fn kept_of_code (code: int): int =
  if code = 20 then 20
  else if code = 21 then 21
  else if code = 24 then 22
  else ~1

(* ~/.bats/ats2.solver: "<cksum> <answer>", written by bats. The write's
   failure fails the build, as every write of bats's does (#359). *)
fn keep_answer (answer: int): int = let
  val @(rc, key) = capture_text(PROBE_SUM, base_arg())
in
  if rc <> 0 then let
    val () = $B.builder_free(key)
  in 0 end
  else let
    val () = bput_v(key, " ")
    val () = (if answer = 20 then bput_v(key, "20")
      else if answer = 21 then bput_v(key, "21")
      else bput_v(key, "22"))
    val () = put_char_v(key, 10)
    var p : $B.builder_v = base_arg()
    val () = bput_v(p, "/ats2.solver")
    val @(pa, pal) = $B.into_arr(p)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val rc2 = write_settle(bv_p, pal, write_file_from_builder_m(bv_p, pal, key))
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in rc2 end
end

(* a probe made now: its directory is removed whatever it found *)
fn probe_fresh (): solver_kind = let
  val out = $A.alloc<byte>(4096)
  val @(rc_m, n) = sh_capture(PROBE_MAKE, base_arg(), empty_arg(), out)
  val @(fz_o, bv_o) = $A.freeze<byte>(out)
  val code = probe_answer(rc_m, bv_o, n)
  val _ = (if rc_m = 0 then sh_exec(PROBE_CLEAR, dir_arg(bv_o, n), empty_arg(), empty_arg()) else 0)
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val kept = kept_of_code(code)
  val _ = (if kept >= 0 then keep_answer(kept) else 0)
in kind_of_code(code) end

fn probe_solver (): solver_kind = let
  val @(rc_s, key) = capture_text(PROBE_SUM, base_arg())
in
  if rc_s <> 0 then let
    val () = $B.builder_free(key)
  in SolverNoAnswer() end
  else let
    val kept = sh_exec(PROBE_KEPT, base_arg(), key, empty_arg())
  in
    if kept = 20 then SolverInt()
    else if kept = 21 then SolverRefusesFalse()
    else if kept = 22 then SolverNoAnswer()
    else probe_fresh()
  end
end

(* ~/.bats/ats2 as a builder (empty when HOME is not set) *)
fn here_arg (): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val has = env_value("HOME", b)
  val () = (if has then bput_v(b, "/.bats/ats2") else ())
in b end

fn say_solver (kind: solver_kind): void =
  case+ kind of
  | SolverInt() => let
      val () = prerr! ("warning: the ATS2 in ")
      val () = prerr_builder(here_arg())
    in prerr! (" was not installed by bats, and its constraint solver accepts a false statement, so it is the -int build, which computes in C int and proves false things (bats#264). A local check can pass what CI refuses: CI uses the pinned ", ATS2_NAME, ". To use that one, move ~/.bats/ats2 away and run bats ats2 install\n") end
  | SolverRefusesFalse() => let
      val () = prerr! ("note: the ATS2 in ")
      val () = prerr_builder(here_arg())
    in prerr! (" was not installed by bats and is not the pinned ", ATS2_NAME, ". Its constraint solver refuses the false statement that the -int build accepts (bats#264)\n") end
  | SolverNoAnswer() => let
      val () = prerr! ("warning: the ATS2 in ")
      val () = prerr_builder(here_arg())
    in prerr! (" was not installed by bats, and bats cannot tell which constraint solver it has: it gave no answer to a false statement within 20 s (the -int build answers in well under a second; bats#264)\n") end

(* A toolchain bats did not make: used as it is, and said on every run, on
   stderr, once, with what the probe found of its solver. An -int build is
   said to be one (CI uses the GMP build, so a local check can pass what CI
   refuses): a warning, not an error, since a user who knowingly uses it
   keeps what they installed, and bats replaces only what it made. *)
val g_warned = ref<bool>(false)

fn warn_foreign (): void = if !g_warned then () else let
  val () = !g_warned := true
  val () = prerr! ("checking the ATS2 in ")
  val () = prerr_builder(here_arg())
  val () = prerr! (" (not installed by bats) with a false statement, up to 20 s ...\n")
  val kind = probe_solver()
in say_solver(kind) end



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
    else if state = 5 then let
      val () = prerr! ("error: the toolchain at ~/.bats/ats2 has no bin/patsopt, and it is not one bats made, so bats does not replace it: move it away and run bats ats2 install\n")
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
