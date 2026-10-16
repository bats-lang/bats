(* ats2 -- the ATS2 toolchain bats keeps in ~/.bats/ats2 (bats-lang/bats#283).

   patsopt, the compiler from ATS to C, is not part of bats: bats finds it
   at $HOME/.bats/ats2/bin/patsopt, and `bats ats2 install` (and, when it
   is missing, bats build, check, test and run) puts it there. Building
   bats itself from bootstrap/c needs none of this: the C and its Makefile
   carry the ATS2 headers they compile against (bootstrap/c/ats2).

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
     nothing                     installed

   An install goes through ats2.tgz.part and ats2.new beside ats2 and is
   moved into place whole, so a run that is killed leaves no half-made
   toolchain where patsopt is looked for, and the next run clears what it
   left. libgmp and its headers are the system's (libgmp-dev on Debian and
   Ubuntu, gmp with Homebrew): bats does not install packages. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

staload "helpers.sats"

#define ATS2_NAME "ATS2-Postiats-gmp-0.4.2"
#define ATS2_SHA256 "73c64f1480df170d65aef5c7e5648677898855a2fa9ea2f3c0502f1b6d7e1b80"
#define ATS2_URL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-gmp-0.4.2.tgz"

(* Whether to say that nothing needed doing *)
#pub datatype ats2_talk = Say | Quiet

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
   is there; 2: nothing usable (nothing, or an older pin's) *)
#define STATE "p=\"$1/ats2\"\nif [ -x \"$p/bin/patsopt\" ]; then\n  if [ \"$(cat \"$p/.bats-ats2\" 2>/dev/null)\" = \"$2\" ]; then exit 0; fi\n  if [ -f \"$p/.bats-ats2\" ]; then exit 2; fi\n  exit 3\nfi\nexit 2\n"

(* what an earlier run left, and the download *)
#define FETCH "set -e\nmkdir -p \"$1\"\nrm -rf \"$1/ats2.new\" \"$1/ats2.tgz.part\"\ncurl -fsSL \"$2\" -o \"$1/ats2.tgz.part\"\n"

(* $1 the digest of the download, $2 the pin's, $3 the base *)
#define VERIFY "if [ \"$1\" = \"$2\" ]; then exit 0; fi\nrm -f \"$3/ats2.tgz.part\"\necho \"error: the ATS2 download has sha256 '$1', not the pinned '$2': nothing was installed\" >&2\nexit 1\n"

(* unpack, build patsopt, mark, and move into place *)
#define BUILD "set -e\nn=\"$1/ats2.new\"\nmkdir \"$n\"\ntar -xzf \"$1/ats2.tgz.part\" --strip-components=1 -C \"$n\"\nrm -f \"$1/ats2.tgz.part\"\nmake -j4 -C \"$n/src/CBOOT\" patsopt PATSHOME=\"$n\"\nmkdir -p \"$n/bin\"\ncp \"$n/src/CBOOT/patsopt\" \"$n/bin/patsopt\"\nprintf '%s\\n' \"$2\" > \"$n/.bats-ats2\"\nrm -rf \"$1/ats2\"\nmv \"$n\" \"$1/ats2\"\n"

#define CLEAR "rm -rf \"$1/ats2.new\" \"$1/ats2.tgz.part\"\n"

(* The SHA-256 of the download, as bats computes it *)
fn download_digest (): $B.builder_v = let
  var path : $B.builder_v = $B.create()
  val _ = env_value("HOME", path)
  val () = bput_v(path, "/.bats/ats2.tgz.part")
  val () = put_char_v(path, 0)
  val @(pa, _) = $B.to_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  var got : $B.builder_v = $B.create()
  (* a download that cannot be read gives no digest, which is no match *)
  val _ = put_file_sha256(bv_p, got)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in got end

#pub fn ats2_ensure (talk: ats2_talk): bool

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
      val () = (case+ talk of
        | Say() => println! ("ATS2 in ~/.bats/ats2 was not installed by bats, so it is used as it is: it is not checked against the pinned ", ATS2_NAME)
        | Quiet() => ())
    in true end
    else if state <> 2 then false
    else let
      val () = println! ("ATS2 not found, installing ", ATS2_NAME, " into ~/.bats/ats2 ...")
      val fetched = sh_exec(FETCH, base_arg(), text_arg(ATS2_URL), empty_arg())
    in
      if fetched <> 0 then let
        val _ = sh_exec(CLEAR, base_arg(), empty_arg(), empty_arg())
      in false end
      else let
        val checked = sh_exec(VERIFY, download_digest(), text_arg(ATS2_SHA256), base_arg())
      in
        if checked <> 0 then false
        else let
          val () = println! ("building patsopt ...")
          val built = sh_exec(BUILD, base_arg(), marker_arg(), empty_arg())
        in
          if built <> 0 then let
            val _ = sh_exec(CLEAR, base_arg(), empty_arg(), empty_arg())
            val () = println! ("note: the ATS2 build bats installs does its constraint solving in infinite precision (GMP), so it needs libgmp and its headers (libgmp-dev on Debian and Ubuntu, gmp on macOS with Homebrew), and make and a C compiler")
          in false end
          else let
            val () = println! ("ATS2 installed successfully")
          in true end
        end
      end
    end
  end
