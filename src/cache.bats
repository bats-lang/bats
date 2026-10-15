(* cache -- patsopt's C made independent of where the project is, and
   kept in a cache that checkouts of a project share (bats-lang/bats#250).

   patsopt is given relative paths but writes absolute ones into the C:
   mangled into symbol names (/a/b/ as _057_a_057_b_057_) and plain in
   location comments. After it succeeds, the project's directory is
   taken out of both, so every path in the C is relative to the project
   (build/src/m.dats), as GCC's -ffile-prefix-map or Rust's
   --remap-path-prefix make them: the same sources give the same C at
   any path.

   With BATS_CACHE_DIR set, that C is kept there under a key made of
   what patsopt reads: the digest of the running bats's own inputs (the
   stamp's `bats` line), the toolchain (patsopt and the files of its
   prelude and libraries, by content), patsopt's arguments, and the
   module's .dats with every file its staloads and includes reach
   (patsopt --depgen, followed to the end), each by path and sha256. A
   module bats would run patsopt on is looked up first; a hit is copied
   into place and checked as patsopt's output is (check_emitted_flaws),
   and only a run that passed is kept, so a hit never lets through what
   a cold build rejects. Entries are written to a temporary file and
   renamed into place, so checkouts and processes share the cache with
   no lock; an entry not used for 7 days is removed. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R
#use sha256 as SHA
#use str as S

staload "helpers.sats"
staload "_bats_inputs.sats"

(* Whether this process has written build/.bats_toolchain, the listing
   the toolchain's part of a key is the hash of: it is made once per
   process, since another run may have had another toolchain *)
val g_toolchain_listed = ref<bool>(false)

(* The directory of the cache's entries under BATS_CACHE_DIR. It is only
   a name: what an entry is valid for is in its key, which begins with the
   digest of the running bats's own inputs (the stamp's `bats` line,
   stamp.bats), so another bats never hits what this one made, with no
   number to bump when the emitter changes. Entries of other bats
   versions stay in this directory until they are not used for 7 days. *)
#define CACHE_DIR_NAME "patsopt-1"

(* ============================================================
   Running sh
   ============================================================ *)

(* The NUL-terminated path p[0, len) (len counts the NUL) as an
   argument, up to its first NUL *)
fn path_arg {lp:agz} (p: !$A.borrow(byte, lp, 524288), len: int): $P.arg_entry = let
  val stop = find_null_bv_from(p, 0, 524288)
  var b = $B.create()
  val () = copy_to_builder_v(p, 0, (if stop < len - 1 then stop else len - 1), 524288, b)
in mk_arg(b) end

(* sh -c script, with args as $1, $2, ...: sh's exit status, -1 when it
   could not be run. What sh wrote to stderr is printed when it fails
   (run_cmd), so a script says nothing on a failure that is expected. *)
fn sh_script {sn:nat} (script: string sn, args: $L.listv($P.arg_entry)): int = let
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
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4), args)))))
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in rc end

(* ============================================================
   The project's directory, taken out of the C
   ============================================================ *)

(* The project's directory as getcwd(3) names it, which is how patsopt
   makes a relative path absolute, appended to root; false when it
   cannot be had *)
fn project_root (root: !$B.builder_v >> $B.builder_v): bool = let
  val exec = str_to_path_arr("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, "pwd -P")
  val cwd = $A.alloc<byte>(4096)
  val @(rc, k) = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))), cwd)
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
  (* without its newline *)
  val @(fz_o, bv_o) = $A.freeze<byte>(cwd)
  val e = (if k > 0 then (if peek(bv_o, k - 1, 4096) = 10 then k - 1 else k) else 0): int
  val ok = (rc = 0 && e > 1)
  val () = (if ok then copy_to_builder_v(bv_o, 0, e, 4096, root) else bput_v(root, ""))
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
in ok end

(* p[0, k) appended to out as patsopt mangles a path into a C name: a
   letter, a digit or '_' as itself, any other byte as '_', its three
   octal digits and '_' (/ is _057_) *)
fun mangle_into {l:agz}{n:pos}{i:nat | i <= n}{bm:nat | bm <= $B.BUILDER_CAP} .<n - i>.
  (p: !$A.borrow(byte, l, n), i: int i, k: int, n: int n, out: !$B.builder(bm) >> $B.builder_v): void =
  if i >= n then ()
  else if i >= k then ()
  else let
    val c = byte2int0($A.read<byte>(p, i))
    val plain = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c = 95
    var esc : $B.builder_v = $B.create()
    val () = put_char_v(esc, (if plain then c else 95))
    val () = (if plain then bput_v(esc, "") else let
        val () = put_char_v(esc, 48 + c / 64)
        val () = put_char_v(esc, 48 + (c / 8 - (c / 64) * 8))
        val () = put_char_v(esc, 48 + (c - (c / 8) * 8))
      in put_char_v(esc, 95) end)
    val () = append_builder(out, esc)
  in mangle_into(p, i + 1, k, n, out) end

(* Whether pat[0, pl) is at c[i], within c[0, n) *)
fun at_pattern {lc,lp:agz}{m,q:pos}{pl:nat | pl <= q}{j:nat | j <= pl} .<pl - j>.
  (c: !$A.borrow(byte, lc, m), i: pos_t, n: pos_t, m: int m,
   pat: !$A.borrow(byte, lp, q), pl: int pl, q: int q, j: int j): bool =
  if j >= pl then true
  else if i + j >= n then false
  else if peek(c, i + j, m) <> peek(pat, j, q) then false
  else at_pattern(c, i, n, m, pat, pl, q, j + 1)

(* c[i, n) written to bw, each <root>/build/ (plain, of length p1) and
   <mangled root>build_057_ (of length p2) with the root left out: s1
   and s2 bytes of them, the root's, are skipped and the rest copied *)
fun put_relative {lc,l1,l2:agz}{m,q:pos}{p1,p2:pos | p1 <= q; p2 <= q}{s1,s2:pos}{i:nat} .<max(m - i, 0)>.
  (c: !$A.borrow(byte, lc, m), i: int i, n: pos_t, m: int m,
   plain: !$A.borrow(byte, l1, q), p1: int p1, s1: int s1,
   mangled: !$A.borrow(byte, l2, q), p2: int p2, s2: int s2, q: int q,
   bw: !$F.buf_writer): void =
  if i >= n then ()
  else if i >= m then ()
  else if at_pattern(c, i, n, m, plain, p1, q, 0) then
    put_relative(c, i + s1, n, m, plain, p1, s1, mangled, p2, s2, q, bw)
  else if at_pattern(c, i, n, m, mangled, p2, q, 0) then
    put_relative(c, i + s2, n, m, plain, p1, s1, mangled, p2, s2, q, bw)
  else let
    val wr = $F.buf_write_byte(bw, byte2int0($A.read<byte>(c, i)))
    val () = $R.discard<int><$F.io_error>(wr)
  in put_relative(c, i + 1, n, m, plain, p1, s1, mangled, p2, s2, q, bw) end

(* The NUL-terminated path p[0, len) with ext after it, NUL-terminated *)
fn path_with {lp:agz}{sn:nat} (p: !$A.borrow(byte, lp, 524288), len: int, ext: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(p, 0, len - 1, 524288, b)
  val () = bput_v(b, ext)
  val () = put_char_v(b, 0)
in b end

(* The C at raw (patsopt's, just written) put at out with the project's
   directory left out of its paths. Every file patsopt reads of the
   project is under build/, so only a path followed by build/ (or, in a
   name, build_057_) is rewritten: a string in the program that merely
   holds the directory's name is left as it is. When the directory
   cannot be had, or is /, the C is put there as patsopt wrote it. It is
   written beside out and renamed into place, so a bats stopped at any
   point leaves out as it was or whole, never half written: out older
   than its .dats is built again, where a C left by patsopt with the
   paths still in it would be taken for fresh. 0 when it is in place. *)
fn relative_c {lr,lo:agz}
  (raw_bv: !$A.borrow(byte, lr, 524288), raw_len: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int): int = let
  var root : $B.builder_v = $B.create()
  val known = project_root(root)
  (* <root>/build/ *)
  var plain : $B.builder_v = $B.create()
  val () = append_builder(plain, root)
  val () = bput_v(plain, "/build/")
  val @(pa, pl) = $B.to_arr(plain)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  (* the same mangled: <root>/ mangled, then build_057_ *)
  var mangled : $B.builder_v = $B.create()
  val () = mangle_into(bv_p, 0, pl - 6, 524288, mangled)
  val () = bput_v(mangled, "build_057_")
  val @(ma, ml) = $B.to_arr(mangled)
  val @(fz_m, bv_m) = $A.freeze<byte>(ma)
  val @(na, _) = $B.to_arr(path_with(out_bv, out_len, ".new"))
  val @(fz_n, bv_n) = $A.freeze<byte>(na)
  val written = (if ~known then false
    else if pl <= 8 then false
    else if ml <= 10 then false
    else (case+ read_whole(raw_bv, 524288) of
      | ~whole_err(_) => false
      | ~whole_ok(ar, piece, m, n) => let
          val @(fz_c, bv_c) = $A.freeze<byte>(piece)
          val ok = (case+ $F.file_open(bv_n, 524288, $F.WriteOnly(), $F.CreateOrTruncate(), 420) of
            | ~$R.ok(fd) => let
                val bw = $F.buf_writer_create(fd)
                val () = put_relative(bv_c, 0, n, m, bv_p, pl, pl - 6, bv_m, ml, ml - 10, 524288, bw)
              in (case+ $F.buf_writer_close(bw) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool end
            | ~$R.err(_) => false): bool
          val () = $A.drop<byte>(fz_c, bv_c)
          val () = whole_free(ar, $A.thaw<byte>(fz_c))
        in ok end)): bool
  (* the rewritten C into place, else patsopt's as it is *)
  val rc = (if written then
      sh_script("mv -f \"$1\" \"$2\" && rm -f \"$3\"",
        $L.list_vt_cons(path_arg(bv_n, 524288), $L.list_vt_cons(path_arg(out_bv, out_len),
        $L.list_vt_cons(path_arg(raw_bv, raw_len), $L.list_vt_nil()))))
    else
      sh_script("rm -f \"$1\"; mv -f \"$2\" \"$3\"",
        $L.list_vt_cons(path_arg(bv_n, 524288), $L.list_vt_cons(path_arg(raw_bv, raw_len),
        $L.list_vt_cons(path_arg(out_bv, out_len), $L.list_vt_nil()))))): int
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
  val () = $A.drop<byte>(fz_m, bv_m)
  val () = $A.free<byte>($A.thaw<byte>(fz_m))
in rc end

(* ============================================================
   The key: what patsopt reads, by content
   ============================================================ *)

(* BATS_CACHE_DIR appended to dir; false when it is not set or empty *)
fn cache_dir (dir: !$B.builder_v >> $B.builder_v): bool = let
  var name_c = @[char][14]('B', 'A', 'T', 'S', '_', 'C', 'A', 'C', 'H', 'E', '_', 'D', 'I', 'R')
  val name = $S.from_char_array(name_c, 14)
  val @(fz_n, bv_n) = $A.freeze<byte>(name)
  val buf = $A.alloc<byte>(4096)
  val got = $E.get(bv_n, 14, buf, 4096)
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
  val k = (case+ got of | ~$R.some(n) => n | ~$R.none() => 0): int
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val () = (if k > 0 then copy_to_builder_v(bv_b, 0, k, 4096, dir) else bput_v(dir, ""))
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in k > 0 end

(* The sha256 of the file at the NUL-terminated b's path, appended to
   out; b is consumed. false when the file cannot be read. *)
fn put_path_sha256 (b: $B.builder_v, out: !$B.builder_v >> $B.builder_v): bool = let
  var p = b
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val ok = put_file_sha256(bv_p, out)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in ok end

(* The toolchain, appended to out as the sha256 of a cksum listing of
   patsopt and of every file of the prelude and libraries it reads
   (which --depgen does not name), made once per process into
   build/.bats_toolchain. By content, not by mtime: a patsopt rebuilt or
   a prelude edited in place is another toolchain. This is the stamp's
   `patsopt` line and the cache key's toolchain. false when the listing
   cannot be made. *)
#pub fn toolchain_digest {lph:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int, out: !$B.builder_v >> $B.builder_v): bool

implement toolchain_digest (ph, phlen, out) = let
  val listing = str_to_path_arr("build/.bats_toolchain")
  val @(fz_l, bv_l) = $A.freeze<byte>(listing)
  val have = (if !g_toolchain_listed then $F.file_exists(bv_l, 524288) else false): bool
  val listed = (if have then true
    else let
      var a1 : $B.builder_v = $B.create()
      val () = copy_to_builder_v(ph, 0, phlen, 512, a1)
      var a2 : $B.builder_v = $B.create()
      val () = bput_v(a2, "build/.bats_toolchain")
      val rc = sh_script("l=\"$(pwd -P)/$2\"; cd \"$1\" && find bin/patsopt prelude libats share ccomp -type f -exec cksum {} + | LC_ALL=C sort > \"$l\"",
        $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2), $L.list_vt_nil())))
      val () = (if rc = 0 then !g_toolchain_listed := true else ())
    in rc = 0 end): bool
  val ok = (if listed then put_file_sha256(bv_l, out) else false): bool
  val () = $A.drop<byte>(fz_l, bv_l)
  val () = $A.free<byte>($A.thaw<byte>(fz_l))
in ok end

(* The toolchain, appended to key *)
fn put_toolchain {lph:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int, key: !$B.builder_v >> $B.builder_v): bool = let
  val () = bput_v(key, "toolchain ")
  val ok = toolchain_digest(ph, phlen, key)
  val () = put_char_v(key, 10)
in ok end

(* Each line of c[i, n), a path, appended to key with the sha256 of its
   file; line holds the bytes of the line read so far. false when a file
   cannot be read. *)
fun put_lines {l:agz}{m:pos}{i:nat} .<max(m - i, 0)>.
  (c: !$A.borrow(byte, l, m), i: int i, n: pos_t, m: int m,
   line: $B.builder_v, key: !$B.builder_v >> $B.builder_v, ok: bool): bool =
  if i >= m then let
    val () = $B.builder_free(line)
  in false end
  else if i >= n then
    (if $B.length(line) > 0 then let
       val () = $B.builder_free(line)
     in false end (* a listing ends with a newline *)
     else let val () = $B.builder_free(line) in ok end)
  else let
    val b = byte2int0($A.read<byte>(c, i))
  in
    if b = 10 then let
      var path : $B.builder_v = $B.create()
      val () = append_builder(path, line)
      val @(pa, pl) = $B.to_arr(path)
      val @(fz_pa, bv_pa) = $A.freeze<byte>(pa)
      val () = copy_to_builder_v(bv_pa, 0, pl, 524288, key)
      val () = put_char_v(key, 32)
      var again : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_pa, 0, pl, 524288, again)
      val () = $A.drop<byte>(fz_pa, bv_pa)
      val () = $A.free<byte>($A.thaw<byte>(fz_pa))
      val hashed = put_path_sha256(again, key)
      val () = put_char_v(key, 10)
    in put_lines(c, i + 1, n, m, $B.create(), key, ok && hashed) end
    else let
      var more = line
      val () = put_char_v(more, b)
    in put_lines(c, i + 1, n, m, more, key, ok) end
  end

(* The files patsopt reads for the .dats at in (NUL-terminated, in_len
   with the NUL), besides the toolchain's: the .dats and every file its
   staloads and includes name, and theirs, to the end, sorted, one per
   line into build/.bats_depgen. patsopt --depgen names each file's own
   (one level), so each level's files are given to one --depgen. *)
fn list_inputs {lph,li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int): bool = let
  var a1 : $B.builder_v = $B.create()
  val () = copy_to_builder_v(ph, 0, phlen, 512, a1)
  val () = bput_v(a1, "/bin/patsopt")
  var a2 : $B.builder_v = $B.create()
  val () = copy_to_builder_v(ph, 0, phlen, 512, a2)
  var a4 : $B.builder_v = $B.create()
  val () = bput_v(a4, "build/.bats_depgen")
  val rc = sh_script("P=$1; PATSHOME=$2; export PATSHOME; out=$4; t=$(mktemp -d) || exit 1; trap 'rm -rf \"$t\"' EXIT; printf '%s\\n' \"$3\" > \"$t/seen\"; cp \"$t/seen\" \"$t/todo\"; while [ -s \"$t/todo\" ]; do set --; while IFS= read -r f; do case $f in *.sats) set -- \"$@\" -s \"$f\" ;; *) set -- \"$@\" -d \"$f\" ;; esac; done < \"$t/todo\"; \"$P\" -IATS build -IATS build/src -IATS build/bats_modules --depgen \"$@\" > \"$t/dep\" 2>/dev/null || exit 1; sed -e 's/^[^:]*:[ ]*//' \"$t/dep\" | tr ' ' '\\n' | sed -e '/^$/d' | LC_ALL=C sort -u > \"$t/found\"; LC_ALL=C sort -u \"$t/seen\" > \"$t/known\"; LC_ALL=C comm -23 \"$t/found\" \"$t/known\" > \"$t/todo\"; cat \"$t/todo\" >> \"$t/seen\"; done; LC_ALL=C sort -u \"$t/seen\" > \"$out\"",
    $L.list_vt_cons(mk_arg(a1), $L.list_vt_cons(mk_arg(a2),
    $L.list_vt_cons(path_arg(in_bv, in_len), $L.list_vt_cons(mk_arg(a4), $L.list_vt_nil())))))
in rc = 0 end

(* The key of patsopt's run on in into out, as 64 hex digits appended to
   hex; false when one of its parts cannot be had, and then the run is
   not cached *)
fn module_key {lph,lo,li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int,
   hex: !$B.builder_v >> $B.builder_v): bool = let
  var key : $B.builder_v = $B.create()
  val () = bput_v(key, "bats ")
  val () = bput_v(key, bats_inputs_sha256())
  val () = put_char_v(key, 10)
  val tool = put_toolchain(ph, phlen, key)
  val () = bput_v(key, "patsopt -IATS build -IATS build/src -IATS build/bats_modules -o ")
  val () = copy_to_builder_v(out_bv, 0, out_len - 1, 524288, key)
  val () = bput_v(key, " -d ")
  val () = copy_to_builder_v(in_bv, 0, in_len - 1, 524288, key)
  val () = put_char_v(key, 10)
  val listed = (if tool then list_inputs(ph, phlen, in_bv, in_len) else false): bool
  val read = (if ~listed then false
    else let
      val lp = str_to_path_arr("build/.bats_depgen")
      val @(fz_lp, bv_lp) = $A.freeze<byte>(lp)
      val r = (case+ read_whole(bv_lp, 524288) of
        | ~whole_err(_) => false
        | ~whole_ok(ar, piece, m, n) => let
            val @(fz_c, bv_c) = $A.freeze<byte>(piece)
            val ok = put_lines(bv_c, 0, n, m, $B.create(), key, n > 0)
            val () = $A.drop<byte>(fz_c, bv_c)
            val () = whole_free(ar, $A.thaw<byte>(fz_c))
          in ok end): bool
      val () = $A.drop<byte>(fz_lp, bv_lp)
      val () = $A.free<byte>($A.thaw<byte>(fz_lp))
    in r end): bool
  (* a key past the builder's size would have lost bytes *)
  val whole = $B.length(key) < 524288
  val @(ka, kl) = $B.to_arr(key)
  val c = $SHA.init()
  val () = $SHA.update(c, ka, kl)
  val () = $A.free<byte>(ka)
  val digest = $A.alloc<byte>(64)
  val () = $SHA.finish(c, digest)
  val @(fz_d, bv_d) = $A.freeze<byte>(digest)
  val () = copy_to_builder_v(bv_d, 0, 64, 64, hex)
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
in read && whole end

(* ============================================================
   patsopt, through the cache
   ============================================================ *)

#pub fn run_patsopt {lph:agz}{lo:agz}{li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int): int

implement run_patsopt (ph, phlen, out_bv, out_len, in_bv, in_len) =
  if has_build_err() then 1 else let
  var dir : $B.builder_v = $B.create()
  val shared = cache_dir(dir)
  var hex : $B.builder_v = $B.create()
  val keyed = (if shared then module_key(ph, phlen, out_bv, out_len, in_bv, in_len, hex) else false): bool
  (* <dir>/<format>, and the entry <dir>/<format>/<2 hex>/<hex>.c *)
  val @(da, dl) = $B.to_arr(dir)
  val @(fz_da, bv_da) = $A.freeze<byte>(da)
  var store : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv_da, 0, dl, 524288, store)
  val () = put_char_v(store, 47)
  val () = bput_v(store, CACHE_DIR_NAME)
  val () = $A.drop<byte>(fz_da, bv_da)
  val () = $A.free<byte>($A.thaw<byte>(fz_da))
  val @(ha, hl) = $B.to_arr(hex)
  val @(fz_ha, bv_ha) = $A.freeze<byte>(ha)
  val @(sa, sl) = $B.to_arr(store)
  val @(fz_sa, bv_sa) = $A.freeze<byte>(sa)
  var entry : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv_sa, 0, sl, 524288, entry)
  val () = put_char_v(entry, 47)
  val () = copy_to_builder_v(bv_ha, 0, 2, 524288, entry)
  val () = put_char_v(entry, 47)
  val () = copy_to_builder_v(bv_ha, 0, hl, 524288, entry)
  val () = bput_v(entry, ".c")
  val @(ea, el) = $B.to_arr(entry)
  val @(fz_ea, bv_ea) = $A.freeze<byte>(ea)
  val () = $A.drop<byte>(fz_ha, bv_ha)
  val () = $A.free<byte>($A.thaw<byte>(fz_ha))
  (* a hit: the entry copied into place, and touched for eviction *)
  val hit = (if ~keyed then false
    else let
      var e1 : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_ea, 0, el, 524288, e1)
      (* copied beside the C and renamed into place, as relative_c does *)
      val rc = sh_script("[ -f \"$1\" ] || exit 3; cp \"$1\" \"$2.new\" && mv -f \"$2.new\" \"$2\" && touch \"$1\"",
        $L.list_vt_cons(mk_arg(e1), $L.list_vt_cons(path_arg(out_bv, out_len), $L.list_vt_nil())))
    in rc = 0 end): bool
  val () = (if hit && is_verbose() then let
      val () = print! ("  + patsopt -o ")
      val () = print_borrow(out_bv, 0, out_len, 524288)
      val () = print! (" -d ")
      val () = print_borrow(in_bv, 0, in_len, 524288)
    in println! (" (cached)") end else ())
  (* patsopt writes <out>.raw, which relative_c puts at out *)
  val @(ra, rl) = $B.to_arr(path_with(out_bv, out_len, ".raw"))
  val @(fz_ra, bv_ra) = $A.freeze<byte>(ra)
  val ran = (if hit then 0 else patsopt_only(ph, phlen, bv_ra, rl, in_bv, in_len)): int
  (* a run that failed leaves no C, as before: the old one goes too *)
  val () = (if ran <> 0 then remove_output(out_bv, out_len) else ())
  val rc = (if hit then 0 else if ran <> 0 then ran
    else (if relative_c(bv_ra, rl, out_bv, out_len) = 0 then 0
      else let
        val () = prerr! ("error: patsopt's output could not be put in place\n")
        val () = set_build_err()
      in 1 end)): int
  val () = $A.drop<byte>(fz_ra, bv_ra)
  val () = $A.free<byte>($A.thaw<byte>(fz_ra))
  val rc2 = (if rc <> 0 then rc
    else let
      val flawed = check_emitted_flaws(out_bv, in_bv, in_len - 1)
      val () = (if flawed <> 0 then remove_output(out_bv, out_len) else ())
    in flawed end): int
  (* kept only when patsopt passed, and what follows it too *)
  val () = (if rc2 <> 0 then ()
    else if hit then ()
    else if ~keyed then ()
    else let
      var e2 : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_ea, 0, el, 524288, e2)
      var s2 : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_sa, 0, sl, 524288, s2)
      val _ = sh_script("set -e; d=$(dirname \"$2\"); mkdir -p \"$d\"; t=$(mktemp \"$d/.tmp.XXXXXX\"); cp \"$1\" \"$t\"; mv -f \"$t\" \"$2\"; cd \"$3\"; if [ -z \"$(find .trimmed -mtime -1 2>/dev/null)\" ]; then touch .trimmed; find . -type f -name '*.c' -mtime +7 -exec rm -f {} +; find . -type f -name '.tmp.*' -mtime +1 -exec rm -f {} +; fi",
        $L.list_vt_cons(path_arg(out_bv, out_len), $L.list_vt_cons(mk_arg(e2),
        $L.list_vt_cons(mk_arg(s2), $L.list_vt_nil()))))
    in end)
  val () = $A.drop<byte>(fz_ea, bv_ea)
  val () = $A.free<byte>($A.thaw<byte>(fz_ea))
  val () = $A.drop<byte>(fz_sa, bv_sa)
  val () = $A.free<byte>($A.thaw<byte>(fz_sa))
in rc2 end
