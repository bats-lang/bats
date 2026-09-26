(* commands -- subcommand implementations for the bats compiler *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use list as L
#use str as S
#use process as P
#use result as R
#use toml as T

staload "helpers.sats"
staload "build.sats"
staload "lexer.sats"
staload "emitter.sats"
staload "docs.sats"

(* ============================================================
   do_test: build and run tests
   ============================================================ *)

#pub fn do_test(): void

implement do_test() = let
  (* Enable test mode so emit includes unittest blocks *)
  val () = set_test_mode(true)
  val () = do_build_plain(0, 0)
  val () = set_test_mode(false)
  (* Scan source for test function names in $UNITTEST.run blocks *)
  (* Use C helper to scan the source file *)
  val src_arr = str_to_path_arr("src/bin")
  val @(fz_sa, bv_sa) = $A.freeze<byte>(src_arr)
  val dir_r = $F.dir_open(bv_sa, 524288)
  val () = $A.drop<byte>(fz_sa, bv_sa)
  val () = $A.free<byte>($A.thaw<byte>(fz_sa))
  val found_tests = $A.alloc<byte>(1)
  val () = $A.write_byte(found_tests, 0, 0)
in
  case+ dir_r of
  | ~$R.ok(sd) => let
      fun scan_test_dir {lft:agz}{fuel:nat} .<fuel>.
        (sd: !$F.dir, ft: !$A.arr(byte, lft, 1), fuel: int fuel): void =
        if fuel <= 0 then ()
        else let
          val ent = $A.alloc<byte>(256)
          val nr = $F.dir_next(sd, ent, 256)
          val elen = dir_name_len(nr)
        in
          if elen < 0 then $A.free<byte>(ent)
          else let
            val ddd = is_dot_or_dotdot(ent, elen, 256)
            val bb = has_bats_ext(ent, elen, 256)
          in
            if ddd then let val () = $A.free<byte>(ent) in scan_test_dir(sd, ft, fuel - 1) end
            else if bb then let
              (* Read source file *)
              var spath = $B.create()
              val @(fz_e, bv_e) = $A.freeze<byte>(ent)
              val () = $B.bput(spath, "src/bin/")
              val () = copy_to_builder(bv_e, 0, elen, 256, spath, 256)
              val () = $B.put_char(spath, 0)
              val () = $A.drop<byte>(fz_e, bv_e)
              val () = $A.free<byte>($A.thaw<byte>(fz_e))
              val @(spa, _) = $B.to_arr(spath)
              val @(fz_sp, bv_sp) = $A.freeze<byte>(spa)
              val sfd = $F.file_open(bv_sp, 524288, 0, 0)
              val () = $A.drop<byte>(fz_sp, bv_sp)
              val () = $A.free<byte>($A.thaw<byte>(fz_sp))
              val () = (case+ sfd of
                | ~$R.ok(fd) => let
                    val sbuf = $A.alloc<byte>(524288)
                    val rr = $F.file_read(fd, sbuf, 524288)
                    val slen = (case+ rr of | ~$R.ok(n) => n | ~$R.err(_) => 0): int
                    val cr = $F.file_close(fd)
                    val () = $R.discard<int><int>(cr)
                    (* Scan for test functions *)
                    val names_buf = $A.alloc<byte>(12800) (* 100 * 128 bytes *)
                    val nfns = 0
                    val () = $A.free<byte>(sbuf)
                  in
                    if nfns > 0 then let
                      val () = $A.write_byte(ft, 0, 1)
                      val () = println! ("running ", nfns, " test(s)")
                      val () = $A.free<byte>(names_buf)
                    in () end
                    else let
                      val () = $A.free<byte>(names_buf)
                    in () end
                  end
                | ~$R.err(_) => ())
            in scan_test_dir(sd, ft, fuel - 1) end
            else let val () = $A.free<byte>(ent) in scan_test_dir(sd, ft, fuel - 1) end
          end
        end
      val () = scan_test_dir(sd, found_tests, 200)
      val dcr = $F.dir_close(sd)
      val () = $R.discard<int><int>(dcr)
      val ft0 = byte2int0($A.get<byte>(found_tests, 0))
      val () = $A.free<byte>(found_tests)
    in
      if ft0 = 0 then println! ("no tests found") else ()
    end
  | ~$R.err(_) => let
      val () = $A.free<byte>(found_tests)
    in
      println! ("no tests found")
    end
end

(* ============================================================
   upload: package library for repository
   ============================================================ *)

(* b[i, len) to stderr. *)
fun prerr_seg {l:agz}{m:pos}{fuel:nat} .<fuel>.
  (b: !$A.borrow(byte, l, m), i: pos_t, len: int, m: int m, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if i >= len then ()
  else let
    val () = prerr_char(int2char0(peek(b, i, m)))
  in prerr_seg(b, i + 1, len, m, fuel - 1) end

(* The sidecar line in sc (the hash so far) completed and written to
   zp + ".sha256", or the error when the archive could not be hashed *)
fn finish_sidecar {lz:agz}
  (ok: bool, sc: $B.builder_v, zp: !$A.borrow(byte, lz, 524288), zlen: int): void =
  if ~ok then let
    val () = $B.builder_free(sc)
    val () = set_build_err()
  in prerr! ("error: cannot read archive for checksum\n") end
  else let
    var line = sc
    val () = bput_v(line, "  ")
    val base = find_basename_start(zp, 0, 524288, ~1, 524288)
    val () = copy_to_builder_v(zp, base, zlen, 524288, line)
    val () = bput_v(line, "\n")
    var sp: $B.builder_v = $B.create()
    val () = copy_to_builder_v(zp, 0, zlen, 524288, sp)
    val () = bput_v(sp, ".sha256")
    val () = put_char_v(sp, 0)
    val @(spa, _) = $B.to_arr(sp)
    val @(fz_sp, bv_sp) = $A.freeze<byte>(spa)
    val _ = write_file_from_builder(bv_sp, 524288, line)
    val () = $A.drop<byte>(fz_sp, bv_sp)
    val () = $A.free<byte>($A.thaw<byte>(fz_sp))
  in end

(* Writes "<sha256 of the archive>  <archive filename>\n" to the sidecar
   of the archive at zp[0, zlen) (NUL-terminated), as the Rust bats did *)
fn write_sidecar {lz:agz} (zp: !$A.borrow(byte, lz, 524288), zlen: int): void = let
  var sc: $B.builder_v = $B.create()
  val ok = put_file_sha256(zp, sc)
in finish_sidecar(ok, sc, zp, zlen) end

(* The end of the line starting at i: the next '\n', or len *)
fun line_end {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, len: int, n: int n, f: int f): pos_t =
  if f <= 0 then i
  else if i >= len then i
  else if $AR.eq_int_int(peek(b, i, n), 10) then i
  else line_end(b, i + 1, len, n, f - 1)

(* Whether c is whitespace as Rust's str::trim sees it (ASCII) *)
fn is_ws (c: int): bool =
  $AR.eq_int_int(c, 32) || $AR.eq_int_int(c, 9) || $AR.eq_int_int(c, 10) ||
  $AR.eq_int_int(c, 11) || $AR.eq_int_int(c, 12) || $AR.eq_int_int(c, 13)

(* The first non-whitespace position in [i, e), or e *)
fun skip_ws {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n, f: int f): pos_t =
  if f <= 0 then i
  else if i >= e then e
  else if is_ws(peek(b, i, n)) then skip_ws(b, i + 1, e, n, f - 1)
  else i

(* The end of [s, e) with trailing whitespace dropped *)
fun trim_end {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, n: int n, f: int f): pos_t =
  if f <= 0 then e
  else if e <= s then s
  else if is_ws(peek(b, e - 1, n)) then trim_end(b, s, e - 1, n, f - 1)
  else e

(* Whether [i, e) holds a '=' *)
fun has_eq {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n, f: int f): bool =
  if f <= 0 then false
  else if i >= e then false
  else if $AR.eq_int_int(peek(b, i, n), 61) then true
  else has_eq(b, i + 1, e, n, f - 1)

(* Rust's inject_version: a line whose trim starts with "version" and
   holds '=' *)
fn is_version_line {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, n: int n): bool = let
  var c = @[char][7]('v', 'e', 'r', 's', 'i', 'o', 'n')
  val t = skip_ws(b, s, e, n, 8192)
in
  if t + 7 > e then false
  else if lit_at(b, t, n, c, 7) then has_eq(b, s, e, n, 8192)
  else false
end

(* Whether the trimmed line is "[package]" *)
fn is_package_line {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, n: int n): bool = let
  var c = @[char][9]('\[', 'p', 'a', 'c', 'k', 'a', 'g', 'e', ']')
  val t = skip_ws(b, s, e, n, 8192)
  val te = trim_end(b, t, e, n, 8192)
in
  if te - t <> 9 then false else lit_at(b, t, n, c, 9)
end

(* Whether any line of b[i, len) is a version line *)
fun any_version_line {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, len: int, n: int n, f: int f): bool =
  if f <= 0 then false
  else if i >= len then false
  else let
    val e = line_end(b, i, len, n, 8192)
  in
    if is_version_line(b, i, e, n) then true
    else any_version_line(b, e + 1, len, n, f - 1)
  end

(* version = "<v>" and a newline *)
fn put_version_line {lv:agz}{nv:pos}
  (out: !$B.builder_v >> $B.builder_v,
   v: !$A.borrow(byte, lv, nv), vlen: int, nv: int nv): void = let
  val () = bput_v(out, "version = \"")
  val () = copy_to_builder_v(v, 0, vlen, nv, out)
in bput_v(out, "\"\n") end

(* One line b[i, ce) of inject_lines *)
fn inject_line {l:agz}{n:pos}{lv:agz}{nv:pos}
  (b: !$A.borrow(byte, l, n), i: pos_t, ce: pos_t, n: int n,
   replace: bool, ver_line: bool, pkg_line: bool,
   v: !$A.borrow(byte, lv, nv), vlen: int, nv: int nv,
   out: !$B.builder_v >> $B.builder_v): void =
  if replace && ver_line then put_version_line(out, v, vlen, nv)
  else let
    val () = copy_to_builder_v(b, i, ce, n, out)
    val () = put_char_v(out, 10)
  in
    if replace then ()
    else if pkg_line then put_version_line(out, v, vlen, nv)
    else ()
  end

(* Rust's inject_version over the lines of b[i, len): with a version
   line present (replace), each one becomes the new version line;
   otherwise the version line goes after "[package]". Every line ends
   with '\n' and loses a trailing '\r', as str::lines does. *)
fun inject_lines {l:agz}{n:pos}{lv:agz}{nv:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, len: int, n: int n, replace: bool,
   v: !$A.borrow(byte, lv, nv), vlen: int, nv: int nv,
   out: !$B.builder_v >> $B.builder_v, f: int f): void =
  if f <= 0 then ()
  else if i >= len then ()
  else let
    val e = line_end(b, i, len, n, 8192)
    val ce = (if e > i then
      (if $AR.eq_int_int(peek(b, e - 1, n), 13) then e - 1 else e) else e): pos_t
    val ver_line = is_version_line(b, i, ce, n)
    val pkg_line = is_package_line(b, i, ce, n)
    val () = inject_line(b, i, ce, n, replace, ver_line, pkg_line, v, vlen, nv, out)
  in inject_lines(b, e + 1, len, n, replace, v, vlen, nv, out, f - 1) end

(* Frees an argument list that will not be run *)
fun free_args {n:nat} .<n>. (xs: $L.list_vt($P.arg_entry, n)): void =
  case+ xs of
  | ~$L.list_vt_cons(a, rest) => let
      val @(arr, _) = a
      val () = $A.free<byte>(arr)
    in free_args(rest) end
  | ~$L.list_vt_nil() => ()

(* Writes bats.toml with the version injected (Rust: write_with_version)
   to build/upload/bats.toml; 0 on success *)
fn write_with_version {lv:agz}{nv:pos}
  (v: !$A.borrow(byte, lv, nv), vlen: int, nv: int nv): int = let
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val tor = $F.file_open(bv_tp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
in
  case+ tor of
  | ~$R.ok(tfd) => let
      val tbuf = $A.alloc<byte>(8192)
      val trr = $F.file_read(tfd, tbuf, 8192)
      val tlen = (case+ trr of | ~$R.ok(k) => k | ~$R.err(_) => 0): int
      val () = $R.discard<int><int>($F.file_close(tfd))
      val @(fz_tb, bv_tb) = $A.freeze<byte>(tbuf)
      val replace = any_version_line(bv_tb, 0, tlen, 8192, 8192)
      var out: $B.builder_v = $B.create()
      val () = inject_lines(bv_tb, 0, tlen, 8192, replace, v, vlen, nv, out, 8192)
      val () = $A.drop<byte>(fz_tb, bv_tb)
      val () = $A.free<byte>($A.thaw<byte>(fz_tb))
      var dir: $B.builder_v = $B.create()
      val () = bput_v(dir, "build/upload")
      val _ = run_mkdir(dir)
      val upath = str_to_path_arr("build/upload/bats.toml")
      val @(fz_op, bv_op) = $A.freeze<byte>(upath)
      val rc = write_file_from_builder(bv_op, 524288, out)
      val () = $A.drop<byte>(fz_op, bv_op)
      val () = $A.free<byte>($A.thaw<byte>(fz_op))
    in rc end
  | ~$R.err(_) => 1
end

(* repo: the --repository path in repo[0, rplen); rplen is 0 when it
   was not given. *)
(* git rev-parse --git-dir's exit code: 0 in a repository, > 0 outside
   one, -errno when git could not be run (Rust: resolve_version) *)
fn git_dir_rc (): int = let
  val git_exec = str_to_path_arr("git")
  val @(fz_ge, bv_ge) = $A.freeze<byte>(git_exec)
  var b1 = $B.create()
  val () = bput_v(b1, "git")
  var b2 = $B.create()
  val () = bput_v(b2, "rev-parse")
  var b3 = $B.create()
  val () = bput_v(b3, "--git-dir")
  val argv = $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil())))
  val out = $A.alloc<byte>(4096)
  val @(rc, _) = run_cmd_capture(bv_ge, argv, out)
  val () = $A.free<byte>(out)
  val () = $A.drop<byte>(fz_ge, bv_ge)
  val () = $A.free<byte>($A.thaw<byte>(fz_ge))
in rc end

(* Whether git status --porcelain lists anything (Rust: resolve_version) *)
fn git_tree_dirty (): bool = let
  val git_exec = str_to_path_arr("git")
  val @(fz_ge, bv_ge) = $A.freeze<byte>(git_exec)
  var b1 = $B.create()
  val () = bput_v(b1, "git")
  var b2 = $B.create()
  val () = bput_v(b2, "status")
  var b3 = $B.create()
  val () = bput_v(b3, "--porcelain")
  val argv = $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil())))
  val out = $A.alloc<byte>(4096)
  val @(_, olen) = run_cmd_capture(bv_ge, argv, out)
  val () = $A.free<byte>(out)
  val () = $A.drop<byte>(fz_ge, bv_ge)
  val () = $A.free<byte>($A.thaw<byte>(fz_ge))
in olen > 0 end

(* Whether a[0, t) and b[0, t) hold the same bytes *)
fun same_bytes {la,lb:agz}{na,nb:pos}{t:nat | t <= na; t <= nb}{i:nat | i <= t} .<t - i>.
  (a: !$A.arr(byte, la, na), b: !$A.arr(byte, lb, nb), t: int t, i: int i): bool =
  if i >= t then true
  else if $AR.eq_int_int(byte2int0($A.get<byte>(a, i)), byte2int0($A.get<byte>(b, i)))
  then same_bytes(a, b, t, i + 1)
  else false

(* A byte array with its size and the length of its contents *)
vtypedef filled_arr = [l:agz][n:pos][t:nat | t <= n] @($A.arr(byte, l, n), int n, int t)

(* The trunk when bats.toml sets none (Rust: config::load) *)
fn default_trunk (): filled_arr = let
  var main_c = @[char][4]('m', 'a', 'i', 'n')
  val a = $S.from_char_array(main_c, 4)
in @(a, 4, 4) end

(* The [package] value of key in bats.toml with its length, when set
   (Rust: config::load) *)
fn package_value {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), klen: int nk): $R.option(filled_arr) = let
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val tor = $F.file_open(bv_tp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
in
  (case+ tor of
  | ~$R.ok(tfd) => let
      val tbuf = $A.alloc<byte>(8192)
      val trr = $F.file_read(tfd, tbuf, 8192)
      val tcr = $F.file_close(tfd)
      val () = $R.discard<int><int>(tcr)
      val () = (case+ trr of | ~$R.ok(_) => () | ~$R.err(_) => ())
      val @(fz_tb, bv_tb) = $A.freeze<byte>(tbuf)
      val pr = $T.parse(bv_tb, 8192)
      val () = $A.drop<byte>(fz_tb, bv_tb)
      val () = $A.free<byte>($A.thaw<byte>(fz_tb))
    in
      (case+ pr of
      | ~$R.ok(doc) => let
          var sec_c = @[char][7]('p', 'a', 'c', 'k', 'a', 'g', 'e')
          val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
          val vbuf = $A.alloc<byte>(256)
          val vr = $T.get(doc, bv_s, 7, key, klen, vbuf, 256)
          val () = $A.drop<byte>(fz_s, bv_s)
          val () = $A.free<byte>($A.thaw<byte>(fz_s))
          val () = $T.toml_free(doc)
        in
          (case+ vr of
          | ~$R.some(k) => $R.some(@(vbuf, 256, k))
          | ~$R.none() => let
              val () = $A.free<byte>(vbuf)
            in $R.none() end): $R.option(filled_arr)
        end
      | ~$R.err(_) => $R.none()): $R.option(filled_arr)
    end
  | ~$R.err(_) => $R.none()): $R.option(filled_arr)
end

(* [package] trunk from bats.toml with its length *)
fn read_trunk (): filled_arr = let
  var key_c = @[char][5]('t', 'r', 'u', 'n', 'k')
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 5))
  val v = package_value(bv_k, 5)
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
in
  case+ v of
  | ~$R.some(a) => a
  | ~$R.none() => default_trunk()
end

(* Whether git rev-parse --abbrev-ref HEAD's output out[0, olen) names
   the trunk: the name and a newline. Detached HEAD never does.
   (Rust: resolve_version) *)
fn on_trunk {lo:agz}{b:nat | b <= 4096}{lt:agz}{n:pos}{t:nat | t <= n}
  (out: !$A.arr(byte, lo, 4096), olen: int b,
   trunk: !$A.arr(byte, lt, n), t: int t): bool = let
  var head_c = @[char][4]('H', 'E', 'A', 'D')
  val head = $S.from_char_array(head_c, 4)
  val head_match = same_bytes(out, head, 4, 0)
  val () = $A.free<byte>(head)
  val detached = (if t = 4 then head_match else false): bool
in
  if detached then false
  else if olen <> t + 1 then false
  else if $AR.eq_int_int(byte2int0($A.get<byte>(out, t)), 10) (* \n *)
  then same_bytes(out, trunk, t, 0)
  else false
end

(* A version: bytes with the array's size, the length, and whether it
   came from [package] version (true) or from git (false) *)
vtypedef version_arr = [l:agz][n:pos] @($A.arr(byte, l, n), int n, int, bool)

(* The version from git: the last commit's date and seconds since
   midnight, with dev1 off the trunk (Rust: resolve_version) *)
fn git_version (): version_arr = let
  (* Get version from git commit timestamp *)
  val git_exec = str_to_path_arr("git")
  val @(fz_ge, bv_ge) = $A.freeze<byte>(git_exec)
  (* Get commit timestamp *)
  var ts_b1 = $B.create()
  val () = bput_v(ts_b1, "git")
  var ts_b2 = $B.create()
  val () = bput_v(ts_b2, "log")
  var ts_b3 = $B.create()
  val () = bput_v(ts_b3, "-1")
  var ts_b4 = $B.create()
  val () = bput_v(ts_b4, "--format=%ct")
  val ts_argv = $L.list_vt_cons(mk_arg(ts_b1),
    $L.list_vt_cons(mk_arg(ts_b2), $L.list_vt_cons(mk_arg(ts_b3),
    $L.list_vt_cons(mk_arg(ts_b4), $L.list_vt_nil()))))
  val ts_out = $A.alloc<byte>(4096)
  val @(ts_rc, ts_len) = run_cmd_capture(bv_ge, ts_argv, ts_out)
  val ts = parse_decimal(ts_out, ts_len, 4096)
  val () = $A.free<byte>(ts_out)
  val @(yr, mo, dy, secs) = timestamp_to_calver(ts)
  (* Check if on main branch *)
  var br_b1 = $B.create()
  val () = bput_v(br_b1, "git")
  var br_b2 = $B.create()
  val () = bput_v(br_b2, "rev-parse")
  var br_b3 = $B.create()
  val () = bput_v(br_b3, "--abbrev-ref")
  var br_b4 = $B.create()
  val () = bput_v(br_b4, "HEAD")
  val br_argv = $L.list_vt_cons(mk_arg(br_b1),
    $L.list_vt_cons(mk_arg(br_b2), $L.list_vt_cons(mk_arg(br_b3),
    $L.list_vt_cons(mk_arg(br_b4), $L.list_vt_nil()))))
  val br_out = $A.alloc<byte>(4096)
  val @(br_rc, br_len) = run_cmd_capture(bv_ge, br_argv, br_out)
  val @(trunk, _, tlen) = read_trunk()
  val is_main = on_trunk(br_out, br_len, trunk, tlen)
  val () = $A.free<byte>(trunk)
  val () = $A.free<byte>(br_out)
  val () = $A.drop<byte>(fz_ge, bv_ge)
  val () = $A.free<byte>($A.thaw<byte>(fz_ge))
  (* Build version string *)
  var vb_b: $B.builder_v = $B.create()
  val () = bput_int_v(vb_b, yr)
  val () = put_char_v(vb_b, 46) (* . *)
  val () = bput_int_v(vb_b, mo)
  val () = put_char_v(vb_b, 46)
  val () = bput_int_v(vb_b, dy)
  val () = put_char_v(vb_b, 46)
  val () = bput_int_v(vb_b, secs)
  val () = (if ~is_main then bput_v(vb_b, "dev1") else bput_v(vb_b, ""))
  val @(va, vl) = $B.to_arr(vb_b)
in @(va, 524288, vl, false) end

(* Prints Rust's "invalid version part '<part>' in '<version>'" *)
fn invalid_version_part {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), ps: pos_t, pe: pos_t, t: int, n: int n): void = let
  val () = prerr! ("error: invalid version part '")
  val () = prerr_seg(b, ps, pe, n, 8192)
  val () = prerr! ("' in '")
  val () = prerr_seg(b, 0, t, n, 8192)
in prerr! ("'\n") end

(* The upload version (Rust: resolve_version): [package] version when
   set; otherwise from git, which fails with 1 outside a git repository
   and 2 on a dirty working tree *)
fn resolve_version (): $R.result(version_arr, int) = let
  var key_c = @[char][7]('v', 'e', 'r', 's', 'i', 'o', 'n')
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 7))
  val v = package_value(bv_k, 7)
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
in
  case+ v of
  | ~$R.some(a) => let
      (* Rust: Version::parse, then its rendering: dev1 split off, each
         part a u32 printed without '+' or leading zeros *)
      val @(arr, n, t) = a
      val @(fz_a, bv_a) = $A.freeze<byte>(arr)
      var d_c = @[char][4]('d', 'e', 'v', '1')
      val dev = (if t >= 4 then lit_at(bv_a, t - 4, n, d_c, 4) else false): bool
      val be = (if dev then t - 4 else t): pos_t
      var out: $B.builder_v = $B.create()
      val @(bad_s, bad_e) = parse_version_parts(bv_a, 0, be, n, out)
      val () = put_dev1(out, dev)
      val @(va, vl) = $B.to_arr(out)
      val () = (if bad_s >= 0 then invalid_version_part(bv_a, bad_s, bad_e, t, n) else ())
      val () = $A.drop<byte>(fz_a, bv_a)
      val () = $A.free<byte>($A.thaw<byte>(fz_a))
    in
      if bad_s >= 0 then let
        val () = $A.free<byte>(va)
      in $R.err(3) end
      else $R.ok(@(va, 524288, vl, true))
    end
  | ~$R.none() =>
    let
      val rc = git_dir_rc()
    in
      if rc < 0 then $R.err(rc)
      else if rc > 0 then $R.err(1)
      else if git_tree_dirty() then $R.err(2)
      else $R.ok(git_version())
    end
end

(* Rust's "git not found: <OS error text> (os error <e>)" *)
fn git_not_found (e: int): void = let
  val buf = $A.alloc<byte>(256)
  val k = $P.os_error_text(e, buf, 256)
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val () = prerr! ("error: git not found: ")
  val () = prerr_seg(bv_b, 0, k, 256, 256)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in prerr! (" (os error ", e, ")\n") end

(* Prints resolve_version's error: -errno when git could not be run,
   1 outside a git repository, 2 on a dirty tree; an invalid version (3)
   was printed where it was found *)
fn version_error (code: int): void =
  if code < 0 then git_not_found(0 - code)
  else if code = 1 then prerr! ("error: not a git repository (required for auto-versioning)\n")
  else if code = 2 then prerr! ("error: working tree is dirty (commit or stash changes before upload)\n")
  else ()

#pub fn do_upload {lr:agz} (repo: !$A.borrow(byte, lr, 4096), rplen: int): void

implement do_upload {lr} (repo, rplen) = let
  (* Read bats.toml for package name and verify kind = "lib" *)
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val tor = $F.file_open(bv_tp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
in
  case+ tor of
  | ~$R.ok(tfd) => let
      val tbuf = $A.alloc<byte>(8192)
      val trr = $F.file_read(tfd, tbuf, 8192)
      val tlen = (case+ trr of | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val tcr = $F.file_close(tfd)
      val () = $R.discard<int><int>(tcr)
      val @(fz_tb, bv_tb) = $A.freeze<byte>(tbuf)
      val pr = $T.parse(bv_tb, 8192)
      val () = $A.drop<byte>(fz_tb, bv_tb)
      val () = $A.free<byte>($A.thaw<byte>(fz_tb))
    in
      case+ pr of
      | ~$R.ok(doc) => let
          val sec = $A.alloc<byte>(7)
          val () = make_package(sec)
          val @(fz_s, bv_s) = $A.freeze<byte>(sec)
          (* Get package name *)
          val kn = $A.alloc<byte>(4)
          val () = make_name(kn)
          val @(fz_kn, bv_kn) = $A.freeze<byte>(kn)
          val nbuf = $A.alloc<byte>(256)
          val nr = $T.get(doc, bv_s, 7, bv_kn, 4, nbuf, 256)
          val () = $A.drop<byte>(fz_kn, bv_kn)
          val () = $A.free<byte>($A.thaw<byte>(fz_kn))
          (* Get package kind *)
          val kk = $A.alloc<byte>(4)
          val () = $A.set<byte>(kk, 0, int2byte0(107)) (* k *)
          val () = $A.set<byte>(kk, 1, int2byte0(105)) (* i *)
          val () = $A.set<byte>(kk, 2, int2byte0(110)) (* n *)
          val () = $A.set<byte>(kk, 3, int2byte0(100)) (* d *)
          val @(fz_kk, bv_kk) = $A.freeze<byte>(kk)
          val kbuf = $A.alloc<byte>(32)
          val kr = $T.get(doc, bv_s, 7, bv_kk, 4, kbuf, 32)
          val () = $A.drop<byte>(fz_kk, bv_kk)
          val () = $A.free<byte>($A.thaw<byte>(fz_kk))
          val () = $A.drop<byte>(fz_s, bv_s)
          val () = $A.free<byte>($A.thaw<byte>(fz_s))
          val () = $T.toml_free(doc)
          (* Check kind is "lib" (3 chars, l=108, i=105, b=98) *)
          val is_lib = (case+ kr of
            | ~$R.some(klen) => (if klen = 3 then let
                val @(fz_kb, bv_kb) = $A.freeze<byte>(kbuf)
                val k0 = byte2int0($A.read<byte>(bv_kb, 0))
                val () = $A.drop<byte>(fz_kb, bv_kb)
                val () = $A.free<byte>($A.thaw<byte>(fz_kb))
              in $AR.eq_int_int(k0, 108) end
              else let val () = $A.free<byte>(kbuf) in false end): bool
            | ~$R.none() => let val () = $A.free<byte>(kbuf) in false end): bool
        in
          case+ nr of
          | ~$R.some(nlen) =>
            if is_lib then
              if rplen > 0 then let
                (* Docs first, so the archive carries them (Rust: build::upload) *)
                val @(fz_dn, bv_dn) = $A.freeze<byte>(nbuf)
                val drc = generate_docs(bv_dn, nlen, 256)
                val () = $A.drop<byte>(fz_dn, bv_dn)
                val nbuf = $A.thaw<byte>(fz_dn)
              in
                if drc < 0 then let
                  val () = $A.free<byte>(nbuf)
                  val () = set_build_err()
                in prerr! ("error: upload failed\n") end
                else let
                val vr = resolve_version()
              in
                case+ vr of
                | ~$R.err(code) => let
                    val () = $A.free<byte>(nbuf)
                    val () = set_build_err()
                  in version_error(code) end
                | ~$R.ok(ver) => let
                val @(verbuf, vmax, verlen, explicit) = ver
                val @(fz_vb, bv_vb) = $A.freeze<byte>(verbuf)
                (* Build output zip path: repo/pkg/prefix_ver.bats *)
                var zip_path: $B.builder_v = $B.create()
                val () = copy_to_builder_v(repo, 0, rplen, 4096, zip_path)
                val () = bput_v(zip_path, "/")
                val @(fz_nb, bv_nb) = $A.freeze<byte>(nbuf)
                val () = copy_to_builder_v(bv_nb, 0, nlen, 256, zip_path)
                val () = bput_v(zip_path, "/")
                (* Build prefix: replace '/' with '_' in name *)
                var pfx: $B.builder_v = $B.create()
                fun copy_replace_slash {l:agz}{fuel:nat} .<fuel>.
                  (bv: !$A.borrow(byte, l, 256), i: pos_t, len: int,
                   b: !$B.builder_v >> $B.builder_v, fuel: int fuel): void =
                  if fuel <= 0 then () else if i >= len then ()
                  else let
                    val byte_val = peek(bv, i, 256)
                    val () = put_char_v(b, (if $AR.eq_int_int(byte_val, 47) then 95 else byte_val): int)
                  in copy_replace_slash(bv, i + 1, len, b, fuel - 1) end
                val () = copy_replace_slash(bv_nb, 0, nlen, pfx, 256)
                val @(pfx_arr, pfx_len) = $B.to_arr(pfx)
                val @(fz_px, bv_px) = $A.freeze<byte>(pfx_arr)
                val () = copy_to_builder_v(bv_px, 0, pfx_len, 524288, zip_path)
                val () = bput_v(zip_path, "_")
                val () = copy_to_builder_v(bv_vb, 0, verlen, vmax, zip_path)
                val () = bput_v(zip_path, ".bats")
                val () = put_char_v(zip_path, 0)
                val @(zpa, zpa_len) = $B.to_arr(zip_path)
                val @(fz_zp, bv_zp) = $A.freeze<byte>(zpa)
                (* mkdir + zip *)
                var mkd: $B.builder_v = $B.create()
                val () = copy_to_builder_v(repo, 0, rplen, 4096, mkd)
                val () = bput_v(mkd, "/")
                val () = copy_to_builder_v(bv_nb, 0, nlen, 256, mkd)
                val _ = run_mkdir(mkd)
                val zip_exec = str_to_path_arr("zip")
                val @(fz_ze, bv_ze) = $A.freeze<byte>(zip_exec)
                var za1 = $B.create()
                val () = bput_v(za1, "zip")
                var za2 = $B.create()
                val () = bput_v(za2, "-r")
                var za3 = $B.create()
                val () = copy_to_builder_v(bv_zp, 0, zpa_len - 1, 524288, za3)
                var za5 = $B.create()
                val () = bput_v(za5, "src/")
                (* Rust: "uploaded <name> v<version> to <repository>" *)
                var um: $B.builder_v = $B.create()
                val () = bput_v(um, "uploaded ")
                val () = copy_to_builder_v(bv_nb, 0, nlen, 256, um)
                val () = bput_v(um, " v")
                val () = copy_to_builder_v(bv_vb, 0, verlen, vmax, um)
                val () = bput_v(um, " to ")
                val () = copy_to_builder_v(repo, 0, rplen, 4096, um)
                val @(uma, umlen) = $B.to_arr(um)
                val @(fz_um, bv_um) = $A.freeze<byte>(uma)
                val () = $A.drop<byte>(fz_nb, bv_nb)
                val () = $A.free<byte>($A.thaw<byte>(fz_nb))
                val () = $A.drop<byte>(fz_px, bv_px)
                val () = $A.free<byte>($A.thaw<byte>(fz_px))
                val dp = str_to_path_arr("docs")
                val @(fz_dp, bv_dp) = $A.freeze<byte>(dp)
                val has_docs = $F.file_exists(bv_dp, 524288)
                val () = $A.drop<byte>(fz_dp, bv_dp)
                val () = $A.free<byte>($A.thaw<byte>(fz_dp))
                val zip_docs = (if has_docs then let
                    var za6 = $B.create()
                    val () = bput_v(za6, "docs/")
                  in $L.list_vt_cons(mk_arg(za6), $L.list_vt_nil()) end
                  else $L.list_vt_nil()): $L.listv($P.arg_entry)
                val src_docs = $L.list_vt_cons(mk_arg(za5), zip_docs)
                (* An explicit version packages bats.toml as it is; one from
                   git goes into a copy with the version injected, added
                   first under the name bats.toml (Rust: build::upload) *)
                val toml_rc = (if explicit then 0 else let
                    val wrc = write_with_version(bv_vb, verlen, vmax)
                  in
                    if wrc <> 0 then wrc else let
                      var zj1 = $B.create()
                      val () = bput_v(zj1, "zip")
                      var zj2 = $B.create()
                      val () = bput_v(zj2, "-j")
                      var zj3 = $B.create()
                      val () = copy_to_builder_v(bv_zp, 0, zpa_len - 1, 524288, zj3)
                      var zj4 = $B.create()
                      val () = bput_v(zj4, "build/upload/bats.toml")
                    in run_cmd(bv_ze, $L.list_vt_cons(mk_arg(zj1),
                         $L.list_vt_cons(mk_arg(zj2), $L.list_vt_cons(mk_arg(zj3),
                         $L.list_vt_cons(mk_arg(zj4), $L.list_vt_nil()))))) end
                  end): int
                val zip_files = (if explicit then let
                    var za4 = $B.create()
                    val () = bput_v(za4, "bats.toml")
                  in $L.list_vt_cons(mk_arg(za4), src_docs) end
                  else src_docs): $L.listv($P.arg_entry)
                val zip_argv = $L.list_vt_cons(mk_arg(za1),
                  $L.list_vt_cons(mk_arg(za2), $L.list_vt_cons(mk_arg(za3),
                  zip_files)))
                val rc = (if toml_rc <> 0 then let
                    val () = free_args(zip_argv)
                  in toml_rc end
                  else run_cmd(bv_ze, zip_argv)): int
                val () = $A.drop<byte>(fz_ze, bv_ze)
                val () = $A.free<byte>($A.thaw<byte>(fz_ze))
              in
                if rc <> 0 then let
                  val () = $A.drop<byte>(fz_zp, bv_zp)
                  val () = $A.free<byte>($A.thaw<byte>(fz_zp))
                  val () = $A.drop<byte>(fz_vb, bv_vb)
                  val () = $A.free<byte>($A.thaw<byte>(fz_vb))
                  val () = $A.drop<byte>(fz_um, bv_um)
                  val () = $A.free<byte>($A.thaw<byte>(fz_um))
                  val () = set_build_err()
                in prerr! ("error: upload failed\n") end
                else let
                  (* The sidecar zip_path + ".sha256" *)
                  val () = write_sidecar(bv_zp, zpa_len - 1)
                  val () = $A.drop<byte>(fz_zp, bv_zp)
                  val () = $A.free<byte>($A.thaw<byte>(fz_zp))
                  val () = $A.drop<byte>(fz_vb, bv_vb)
                  val () = $A.free<byte>($A.thaw<byte>(fz_vb))
                  val () = (if is_quiet() then () else let
                      val () = prerr_seg(bv_um, 0, umlen, 524288, 524288)
                    in prerr_newline() end)
                  val () = $A.drop<byte>(fz_um, bv_um)
                  val () = $A.free<byte>($A.thaw<byte>(fz_um))
                in () end
              end
              end
              end
              else let
                val () = $A.free<byte>(nbuf)
                val () = set_build_err()
              in prerr! ("error: 'bats upload' requires --repository <dir>\n") end
            else let
              val () = $A.free<byte>(nbuf)
              val () = set_build_err()
            in prerr! ("error: 'bats upload' is only for library packages (kind = \"lib\")\n") end
          | ~$R.none() => let
              val () = $A.free<byte>(nbuf)
              val () = set_build_err()
            in prerr! ("error: package.name not found in bats.toml\n") end
        end
      | ~$R.err(_) => let
          val () = set_build_err()
        in prerr! ("error: parse error in './bats.toml'\n") end
    end
  | ~$R.err(_) => let
      val () = set_build_err()
    in prerr! ("error: cannot read './bats.toml'\n") end
end

(* ============================================================
   completions: generate shell completion scripts
   ============================================================ *)

#pub fn do_completions(shell: int): void

implement do_completions(shell) =
  if shell = 0 then
    print_string "# bash completions\ncomplete -W 'build check clean lock run test tree add remove upload init completions' bats\n"
  else if shell = 1 then
    print_string "#compdef bats\n_bats_cmds=(build check clean lock run test tree add remove upload init completions)\ncompadd $_bats_cmds\n"
  else if shell = 2 then
    print_string "# fish completions\nfor c in build check clean lock run test tree add remove upload init completions; complete -c bats -n __fish_use_subcommand -a $c; end\n"
  else println! ("error: specify a shell (bash, zsh, fish)")

(* Check if a file exists by trying to open it *)

#pub fn file_exists {sn:nat | sn < $B.BUILDER_CAP} (path: string sn): bool

implement file_exists(path) = let
  val pa = str_to_path_arr(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val fex_or = $F.file_open(bv, 524288, 0, 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in case+ fex_or of
  | ~$R.ok(fd) => let
      val cr = $F.file_close(fd)
      val () = $R.discard<int><int>(cr)
    in true end
  | ~$R.err(_) => false
end

(* ============================================================
   write_claude_rules: create .claude/rules/bats.md
   ============================================================ *)

#pub fn write_claude_rules(): void

implement write_claude_rules() = let
  var cmd = $B.create()
  val () = $B.bput(cmd, ".claude/rules")
  val _ = run_mkdir(cmd)
  var rb = $B.create()
  val () = $B.bput(rb, "# Writing Bats\n\n")
  val () = $B.bput(rb, "Bats is a language that compiles to ATS2.\n\n")
  val () = $B.bput(rb, "## Build commands\n\n")
  val () = $B.bput(rb, "```bash\n")
  val () = $B.bput(rb, "bats build    # Build binary project\n")
  val () = $B.bput(rb, "bats check    # Type-check without linking\n")
  val () = $B.bput(rb, "bats clean    # Remove generated artifacts\n")
  val () = $B.bput(rb, "```\n\n")
  val () = $B.bput(rb, "## Project layout\n\n")
  val () = $B.bput(rb, "- `bats.toml` -- package config\n")
  val () = $B.bput(rb, "- `src/lib.bats` -- library entry point (kind = \"lib\")\n")
  val () = $B.bput(rb, "- `src/bin/<name>.bats` -- binary entry points (kind = \"bin\")\n\n")
  val () = $B.bput(rb, "## Bats-specific syntax\n\n")
  val () = $B.bput(rb, "### `#pub` -- public declarations\n\n")
  val () = $B.bput(rb, "```bats\n")
  val () = $B.bput(rb, "#pub fun greet (name: string): void\n")
  val () = $B.bput(rb, "implement greet (name) = println! (\"hello \", name)\n")
  val () = $B.bput(rb, "```\n\n")
  val () = $B.bput(rb, "### `#use` -- package imports\n\n")
  val () = $B.bput(rb, "```bats\n")
  val () = $B.bput(rb, "#use mylib as M\n")
  val () = $B.bput(rb, "val x = $M.greeting ()\n")
  val () = $B.bput(rb, "```\n\n")
  val () = $B.bput(rb, "## ATS2 essentials\n\n")
  val () = $B.bput(rb, "- `println!` has a bang\n")
  val () = $B.bput(rb, "- `fun` declares functions, `val` binds values\n")
  val () = $B.bput(rb, "- Pattern matching: `case+ x of | 0 => ... | n => ...`\n")
  val () = $B.bput(rb, "- Types: `int`, `string`, `bool`, `void`\n")
  val () = $B.bput(rb, "- No semicolons at end of expressions\n")
  val rp = str_to_path_arr(".claude/rules/bats.md")
  val @(fz_rp, bv_rp) = $A.freeze<byte>(rp)
  val _ = write_file_from_builder(bv_rp, 524288, rb)
  val () = $A.drop<byte>(fz_rp, bv_rp)
  val () = $A.free<byte>($A.thaw<byte>(fz_rp))
in end

(* ============================================================
   init: create a new bats project
   ============================================================ *)

(* a[0, alen) = w[0, n) *)
fun arg_is {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (a: !$A.borrow(byte, l, 4096), alen: int, w: &(@[char][n]), n: int n, i: int i): bool =
  if alen <> n then false
  else if i >= n then true
  else if peek(a, i, 4096) <> char2int0(w.[i]) then false
  else arg_is(a, alen, w, n, i + 1)

(* The project kind named by bats init's argument, as the Rust bats
   accepted it: 0 for binary/bin, 1 for library/lib, ~1 otherwise. *)
fn init_kind {l:agz} (a: !$A.borrow(byte, l, 4096), alen: int): int = let
  var w1 = @[char][6]('b', 'i', 'n', 'a', 'r', 'y')
  var w2 = @[char][3]('b', 'i', 'n')
  var w3 = @[char][7]('l', 'i', 'b', 'r', 'a', 'r', 'y')
  var w4 = @[char][3]('l', 'i', 'b')
in
  if arg_is(a, alen, w1, 6, 0) then 0
  else if arg_is(a, alen, w2, 3, 0) then 0
  else if arg_is(a, alen, w3, 7, 0) then 1
  else if arg_is(a, alen, w4, 3, 0) then 1
  else ~1
end

(* Whether the NUL-terminated path in p exists. *)
fn path_exists {l:agz} (p: !$A.borrow(byte, l, 524288)): bool =
  case+ $F.file_open(p, 524288, 0, 0) of
  | ~$R.ok(fd) => let val () = $R.discard<int><int>($F.file_close(fd)) in true end
  | ~$R.err(_) => false

(* The project name, as the Rust bats chose it: the current directory's
   last component, or "myproject". Appended to b. *)
fn add_project_name (b: !$B.builder_v >> $B.builder_v): void = let
  val cwd = $A.alloc<byte>(4096)
  val k = (case+ $E.cwd_read(cwd, 4096) of | ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= 4096] int k
  val @(fz_c, bv_c) = $A.freeze<byte>(cwd)
  val start = find_basename_start(bv_c, 0, 4096, ~1, 4096)
  val () = (if start < k then copy_to_builder_v(bv_c, start, k, 4096, b)
    else bput_v(b, "myproject"))
  val () = $A.drop<byte>(fz_c, bv_c)
in $A.free<byte>($A.thaw<byte>(fz_c)) end

(* The NUL-terminated path "src/bin/<name>.bats" or "src/lib.bats". *)
fn init_source_path {ln:agz}
  (kind: int, name: !$A.borrow(byte, ln, 524288), nlen: int): $B.builder_v = let
  var p: $B.builder_v = $B.create()
  val () = (if kind = 0 then let
      val () = bput_v(p, "src/bin/")
      val () = copy_to_builder_v(name, 0, nlen, 524288, p)
    in bput_v(p, ".bats") end
    else bput_v(p, "src/lib.bats"))
  val () = put_char_v(p, 0)
in p end

(* Writes b to the NUL-terminated path in p; 0 on success. *)
fn write_to {lp:agz} (p: !$A.borrow(byte, lp, 524288), b: $B.builder_v): int =
  write_file_from_builder(p, 524288, b)

(* bats init <kind>: as the Rust bats's cmd_init. arg: the kind argument
   in arg[0, alen). *)
#pub fn do_init {la:agz} (arg: !$A.borrow(byte, la, 4096), alen: int, claude: int): void

implement do_init {la} (arg, alen, claude) = let
  val kind = init_kind(arg, alen)
in
  if kind < 0 then let
    val () = prerr! ("error: unknown project kind '")
    val () = prerr_seg(arg, 0, alen, 4096, 4096)
    val () = prerr! ("', use 'binary' or 'library'")
    val () = prerr_newline()
  in set_build_err() end
  else let
    var nb: $B.builder_v = $B.create()
    val () = add_project_name(nb)
    val @(na, nlen) = $B.to_arr(nb)
    val @(fz_n, bv_n) = $A.freeze<byte>(na)
    val sp = init_source_path(kind, bv_n, nlen)
    val @(spa, splen) = $B.to_arr(sp)
    val @(fz_sp, bv_sp) = $A.freeze<byte>(spa)
    val tp = str_to_path_arr("bats.toml")
    val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
    val gp = str_to_path_arr(".gitignore")
    val @(fz_gp, bv_gp) = $A.freeze<byte>(gp)
    val c_toml = path_exists(bv_tp)
    val c_src = path_exists(bv_sp)
    val c_gi = path_exists(bv_gp)
    val () = (if c_toml || c_src || c_gi then let
        val () = prerr! ("error: refusing to overwrite existing files:")
        val () = prerr_newline()
        val () = (if c_toml then let val () = prerr! ("  bats.toml") in prerr_newline() end else ())
        val () = (if c_src then let
            val () = prerr! ("  ")
            val () = prerr_seg(bv_sp, 0, splen - 1, 524288, 524288)
          in prerr_newline() end else ())
        val () = (if c_gi then let val () = prerr! ("  .gitignore") in prerr_newline() end else ())
      in set_build_err() end
      else let
        var toml: $B.builder_v = $B.create()
        val () = bput_v(toml, "[package]\nname = \"")
        val () = copy_to_builder_v(bv_n, 0, nlen, 524288, toml)
        val () = (if kind = 0 then bput_v(toml, "\"\nkind = \"bin\"\n")
          else bput_v(toml, "\"\nkind = \"lib\"\n"))
        val r1 = write_to(bv_tp, toml)
        var dir: $B.builder_v = $B.create()
        val () = (if kind = 0 then bput_v(dir, "src/bin") else bput_v(dir, "src"))
        val _ = run_mkdir(dir)
        var src: $B.builder_v = $B.create()
        (* split so the emitter does not take the text for this file's main0 *)
        val () = (if kind = 0 then let
            val () = bput_v(src, "implement ")
          in bput_v(src, "main0 () = println! (\"hello, world!\")\n") end
          else bput_v(src, "#pub fun hello(): void\n\nimplement hello () = println! (\"hello from library\")\n"))
        val r2 = write_to(bv_sp, src)
        var gi: $B.builder_v = $B.create()
        val () = bput_v(gi, "build/\ndist/\ndocs/\nbats_modules/\n")
        val r3 = write_to(bv_gp, gi)
      in
        if r1 <> 0 then let
          val () = prerr! ("error: cannot write bats.toml")
          val () = prerr_newline()
        in set_build_err() end
        else if r2 <> 0 then let
          val () = prerr! ("error: cannot write ")
          val () = prerr_seg(bv_sp, 0, splen - 1, 524288, 524288)
          val () = prerr_newline()
        in set_build_err() end
        else if r3 <> 0 then let
          val () = prerr! ("error: cannot write .gitignore")
          val () = prerr_newline()
        in set_build_err() end
        else let
          val () = (if claude > 0 then write_claude_rules() else ())
        in
          if is_quiet() then ()
          else let
            val () = prerr! ("created ")
            val () = prerr_seg(arg, 0, alen, 4096, 4096)
            val () = prerr! (" project '")
            val () = prerr_seg(bv_n, 0, nlen, 524288, 524288)
            val () = prerr! ("'")
          in prerr_newline() end
        end
      end)
    val () = $A.drop<byte>(fz_gp, bv_gp)
    val () = $A.free<byte>($A.thaw<byte>(fz_gp))
    val () = $A.drop<byte>(fz_tp, bv_tp)
    val () = $A.free<byte>($A.thaw<byte>(fz_tp))
    val () = $A.drop<byte>(fz_sp, bv_sp)
    val () = $A.free<byte>($A.thaw<byte>(fz_sp))
    val () = $A.drop<byte>(fz_n, bv_n)
  in $A.free<byte>($A.thaw<byte>(fz_n)) end
end

(* ============================================================
   tree: display dependency tree from bats.lock
   ============================================================ *)

#pub fn do_tree(): void

implement do_tree() = let
  val la = str_to_path_arr("bats.lock")
  val @(fz_la, bv_la) = $A.freeze<byte>(la)
  val lock_or = $F.file_open(bv_la, 524288, 0, 0)
  val () = $A.drop<byte>(fz_la, bv_la)
  val () = $A.free<byte>($A.thaw<byte>(fz_la))
in
  case+ lock_or of
  | ~$R.ok(lfd) => let
      val lock_buf = $A.alloc<byte>(524288)
      val lr = $F.file_read(lfd, lock_buf, 524288)
      val lock_len = (case+ lr of | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val lcr = $F.file_close(lfd)
      val () = $R.discard<int><int>(lcr)
    in
      if lock_len > 0 then let
        (* Use C helper to print Unicode tree *)
        val @(fz_lb, bv_lb) = $A.freeze<byte>(lock_buf)
        val () = print_borrow(bv_lb, 0, lock_len, 524288, 524288)
        val () = $A.drop<byte>(fz_lb, bv_lb)
        val () = $A.free<byte>($A.thaw<byte>(fz_lb))
      in end
      else let
        val () = $A.free<byte>(lock_buf)
      in println! ("no dependencies") end
    end
  | ~$R.err(_) => println! ("error: no bats.lock found (run lock first)")
end

(* ============================================================
   add: add a dependency to bats.toml
   ============================================================ *)

#pub fn do_add {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), pkg_start: pos_t, pkg_len: int,
   max: int n): void

implement do_add(bv, pkg_start, pkg_len, max) = let
  (* Read bats.toml *)
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val tor = $F.file_open(bv_tp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
in
  case+ tor of
  | ~$R.ok(tfd) => let
      val tbuf = $A.alloc<byte>(4096)
      val trr = $F.file_read(tfd, tbuf, 4096)
      val tlen = (case+ trr of | ~$R.ok(nn) => nn | ~$R.err(_) => 0): int
      val tcr = $F.file_close(tfd)
      val () = $R.discard<int><int>(tcr)
      val @(fz_tb2, bv_tb2) = $A.freeze<byte>(tbuf)
      var out_b: $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_tb2, 0, tlen, 4096, out_b)
      val () = $A.drop<byte>(fz_tb2, bv_tb2)
      val () = $A.free<byte>($A.thaw<byte>(fz_tb2))
      val () = bput_v(out_b, "\"")
      val () = copy_to_builder_v(bv, pkg_start, pkg_start + pkg_len, max, out_b)
      val () = bput_v(out_b, "\" = \"\"\n")
      val tp3 = str_to_path_arr("bats.toml")
      val @(fz_tp3, bv_tp3) = $A.freeze<byte>(tp3)
      val rc = write_file_from_builder(bv_tp3, 524288, out_b)
      val () = $A.drop<byte>(fz_tp3, bv_tp3)
      val () = $A.free<byte>($A.thaw<byte>(fz_tp3))
    in
      if rc = 0 then let
          val () = print! ("added '")
          val () = print_borrow(bv, pkg_start, pkg_start + pkg_len, max, 524288)
        in println! ("' to [dependencies]") end
      else println! ("error: cannot write bats.toml")
    end
  | ~$R.err(_) => println! ("error: cannot open bats.toml")
end

(* ============================================================
   remove: remove a dependency from bats.toml
   ============================================================ *)

#pub fn do_remove {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), pkg_start: pos_t, pkg_len: int,
   max: int n): void

implement do_remove(bv, pkg_start, pkg_len, max) = let
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val tor = $F.file_open(bv_tp, 524288, 0, 0)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
in
  case+ tor of
  | ~$R.ok(tfd) => let
      val tbuf = $A.alloc<byte>(4096)
      val trr = $F.file_read(tfd, tbuf, 4096)
      val tlen = (case+ trr of | ~$R.ok(nn) => nn | ~$R.err(_) => 0): int
      val tcr = $F.file_close(tfd)
      val () = $R.discard<int><int>(tcr)
      val () = $A.free<byte>(tbuf)
      val sed_exec = str_to_path_arr("sed")
      val @(fz_se, bv_se) = $A.freeze<byte>(sed_exec)
      var sb1 = $B.create()
      val () = bput_v(sb1, "sed")
      var sb2 = $B.create()
      val () = bput_v(sb2, "-i")
      (* Build pattern: /^"<pkg>"/d *)
      var pat_b: $B.builder_v = $B.create()
      val () = bput_v(pat_b, "/^\"")
      val () = copy_to_builder_v(bv, pkg_start, pkg_start + pkg_len, max, pat_b)
      val () = bput_v(pat_b, "\"/d")
      var sb4 = $B.create()
      val () = bput_v(sb4, "bats.toml")
      val sed_argv = $L.list_vt_cons(mk_arg(sb1), $L.list_vt_cons(mk_arg(sb2),
        $L.list_vt_cons(mk_arg(pat_b), $L.list_vt_cons(mk_arg(sb4),
        $L.list_vt_nil()))))
      val rc = run_cmd(bv_se, sed_argv)
      val () = $A.drop<byte>(fz_se, bv_se)
      val () = $A.free<byte>($A.thaw<byte>(fz_se))
    in
      if rc = 0 then let
          val () = print! ("removed '")
          val () = print_borrow(bv, pkg_start, pkg_start + pkg_len, max, 524288)
        in println! ("' from [dependencies]") end
      else let
        val () = print! ("error: package '")
        val () = print_borrow(bv, pkg_start, pkg_start + pkg_len, max, 524288)
      in println! ("' not found in [dependencies]") end
    end
  | ~$R.err(_) => println! ("error: cannot open bats.toml")
end

(* ============================================================
   Process spawning
   ============================================================ *)

#pub fn run_process_demo(): void

implement run_process_demo() = let
  val exec = str_to_path_arr("echo")
  val @(fz_exec, bv_exec) = $A.freeze<byte>(exec)
  var ba1 = $B.create()
  val () = bput_v(ba1, "echo")
  var ba2 = $B.create()
  val () = bput_v(ba2, "check passed")
  val argv = $L.list_vt_cons(mk_arg(ba1),
    $L.list_vt_cons(mk_arg(ba2), $L.list_vt_nil()))
  val spawn_r = $P.spawn_inherit_env(bv_exec, argv,
    $P.dev_null(), $P.pipe_new(), $P.dev_null())
  val () = $A.drop<byte>(fz_exec, bv_exec)
  val () = $A.free<byte>($A.thaw<byte>(fz_exec))
in
  case+ spawn_r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val () = $P.pipe_end_close(serr_p)
      val+ ~$P.pipe_fd(stdout_fd) = sout_p
      val out_buf = $A.alloc<byte>(256)
      val read_r = $F.file_read(stdout_fd, out_buf, 256)
      val out_len = (case+ read_r of
        | ~$R.ok(n) => n
        | ~$R.err(_) => 0): int
      val fcr = $F.file_close(stdout_fd)
      val () = $R.discard<int><int>(fcr)
      val wait_r = $P.child_wait(child)
      val exit_code = (case+ wait_r of
        | ~$R.ok(n) => n
        | ~$R.err(_) => ~1): int
      val () = print! ("  process: ")
      val () = print_arr(out_buf, 0, out_len, 256, 256)
      val () = println! ("  exit code: ", exit_code)
      val () = $A.free<byte>(out_buf)
    in end
  | ~$R.err(e) =>
      println! ("  spawn failed: ", e)
end


(* ============================================================
   run: build then execute the binary
   ============================================================ *)

(* The NUL-terminated strings in bv[start, total) as argv entries,
   empty ones included, reversed onto acc. *)
fun extra_arg_list {l:agz}{fuel:nat} .<fuel>.
  (bv: !$A.borrow(byte, l, 4096), start: pos_t, total: int,
   acc: $L.listv($P.arg_entry), fuel: int fuel): $L.listv($P.arg_entry) =
  if fuel <= 0 then acc
  else if start >= total then acc
  else let
    val np = find_null_bv_from(bv, start, 4096)
    val e = (if np < total then np else total): int
    var wb = $B.create()
    val () = copy_to_builder_v(bv, start, e, 4096, wb)
  in extra_arg_list(bv, np + 1, total, $L.list_vt_cons(mk_arg(wb), acc), fuel - 1) end

(* Appends to names, each NUL-terminated and in name order, every NAME
   of src/bin/NAME.bats for which the build produced dist/<mode>/NAME;
   returns how many. *)
fun collect_built {lq:agz}{fuel:nat} .<fuel>.
  (names: !$B.builder_v >> $B.builder_v, prev: $A.arr(byte, lq, 256), prev_len: int,
   release: int, count: int, fuel: int fuel): int =
  if fuel <= 0 then let
    val () = $A.free<byte>(prev)
  in count end
  else let
    val sb = str_to_path_arr("src/bin")
    val @(fz_sb, bv_sb) = $A.freeze<byte>(sb)
    val @(fz_pv, bv_pv) = $A.freeze<byte>(prev)
    val @(ent, el) = dir_next_sorted(bv_sb, 524288, bv_pv, prev_len)
    val () = $A.drop<byte>(fz_pv, bv_pv)
    val () = $A.free<byte>($A.thaw<byte>(fz_pv))
    val () = $A.drop<byte>(fz_sb, bv_sb)
    val () = $A.free<byte>($A.thaw<byte>(fz_sb))
  in
    if el < 0 then let
      val () = $A.free<byte>(ent)
    in count end
    else if ~has_bats_ext(ent, el, 256) then
      collect_built(names, ent, el, release, count, fuel - 1)
    else let
      val @(fz_e, bv_e) = $A.freeze<byte>(ent)
      val built = is_built(bv_e, el - 5, release)
      val () = (if built then add_name(names, bv_e, el - 5) else ())
      val () = $A.drop<byte>(fz_e, bv_e)
      val ent = $A.thaw<byte>(fz_e)
      val inc = (if built then 1 else 0): int
    in collect_built(names, ent, el, release, count + inc, fuel - 1) end
  end

(* Whether dist/<mode>/NAME exists, for NAME = ent[0, len). *)
and is_built {le:agz} (ent: !$A.borrow(byte, le, 256), len: int, release: int): bool = let
  var pb: $B.builder_v = $B.create()
  val () = (if release > 0 then bput_v(pb, "dist/release/") else bput_v(pb, "dist/debug/"))
  val () = copy_to_builder_v(ent, 0, len, 256, pb)
  val () = put_char_v(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val built = (case+ $F.file_open(bv_p, 524288, 0, 0) of
    | ~$R.ok(fd) => let val () = $R.discard<int><int>($F.file_close(fd)) in true end
    | ~$R.err(_) => false): bool
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in built end

and add_name {le:agz}
  (names: !$B.builder_v >> $B.builder_v, ent: !$A.borrow(byte, le, 256), len: int): void = let
  val () = copy_to_builder_v(ent, 0, len, 256, names)
in put_char_v(names, 0) end

(* Appends the chosen binary's name: bin[0, blen) for 0, the first
   entry of n for 1, nothing otherwise. *)
fn add_choice {lb,ln:agz}
  (cmd: !$B.builder_v >> $B.builder_v, choice: int,
   bin: !$A.borrow(byte, lb, 256), blen: int, n: !$A.borrow(byte, ln, 524288)): void =
  if choice = 0 then copy_to_builder_v(bin, 0, blen, 256, cmd)
  else if choice = 1 then copy_to_builder_v(n, 0, find_null_bv_from(n, 0, 524288), 524288, cmd)
  else bput_v(cmd, "")

(* Whether the entry at n[i, NUL) equals b[0, blen). *)
fun entry_eq {ln,lb:agz}{fuel:nat} .<fuel>.
  (n: !$A.borrow(byte, ln, 524288), s: pos_t,
   b: !$A.borrow(byte, lb, 256), blen: int, i: pos_t, fuel: int fuel): bool =
  if fuel <= 0 then false
  else if i >= blen then peek(n, s + i, 524288) = 0
  else if peek(n, s + i, 524288) <> peek(b, i, 256) then false
  else entry_eq(n, s, b, blen, i + 1, fuel - 1)

(* Whether some entry of the NUL-terminated list n[s, nlen) is b[0, blen). *)
fun list_has {ln,lb:agz}{fuel:nat} .<fuel>.
  (n: !$A.borrow(byte, ln, 524288), nlen: int, s: pos_t,
   b: !$A.borrow(byte, lb, 256), blen: int, fuel: int fuel): bool =
  if fuel <= 0 then false
  else if s >= nlen then false
  else if entry_eq(n, s, b, blen, 0, 257) then true
  else list_has(n, nlen, find_null_bv_from(n, s, 524288) + 1, b, blen, fuel - 1)


(* The NUL-terminated entries of n[s, nlen) to stderr, ", "-separated. *)
fun prerr_names {ln:agz}{fuel:nat} .<fuel>.
  (n: !$A.borrow(byte, ln, 524288), nlen: int, s: pos_t, first: bool, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if s >= nlen then ()
  else let
    val e = find_null_bv_from(n, s, 524288)
    val () = (if first then () else prerr! (", "))
    val () = prerr_seg(n, s, e, 524288, 524288)
  in prerr_names(n, nlen, e + 1, false, fuel - 1) end

(* bin: the --bin name in bin[0, blen); blen is 0 when it was not
   given. extra: the arguments
   after "--", NUL-terminated, in extra[0, elen). *)
#pub fn do_run {lb,le:agz}
  (release: int, bin: !$A.borrow(byte, lb, 256), blen: int,
   extra: !$A.borrow(byte, le, 4096), elen: int): void

implement do_run {lb,le} (release, bin, blen, extra, elen) = let
  val () = do_build_plain(release, 0)
  (* The binaries the build produced, NUL-terminated, in name order *)
  var names: $B.builder_v = $B.create()
  val count = collect_built(names, $A.alloc<byte>(256), 0, release, 0, 4096)
  val @(na, nlen) = $B.to_arr(names)
  val @(fz_n, bv_n) = $A.freeze<byte>(na)
  (* As the Rust bats: --bin names one of them; without it there must be
     exactly one. 0: run --bin's; 1: run the only one; ~1: error. *)
  val choice = (if blen > 0 then
      if list_has(bv_n, nlen, 0, bin, blen, 4096) then 0
      else let
        val () = prerr! ("error: binary '")
        val () = prerr_seg(bin, 0, blen, 256, 256)
        val () = prerr! ("' not found. Available: ")
        val () = prerr_names(bv_n, nlen, 0, true, 4096)
        val () = prerr_newline()
      in ~1 end
    else if count = 1 then 1
    else let
      val () = prerr! ("error: multiple binaries available, specify one with --bin <name>: ")
      val () = prerr_names(bv_n, nlen, 0, true, 4096)
      val () = prerr_newline()
    in ~1 end): int
  var cmd: $B.builder_v = $B.create()
  val () = (if release > 0 then bput_v(cmd, "./dist/release/")
    else bput_v(cmd, "./dist/debug/"))
  val () = add_choice(cmd, choice, bin, blen, bv_n)
  val chosen = choice >= 0
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
  val () = put_char_v(cmd, 0)
  val @(exec_a, exec_len) = $B.to_arr(cmd)
  val @(fz_ea, bv_ea) = $A.freeze<byte>(exec_a)
in
  if ~chosen then let
    val () = $A.drop<byte>(fz_ea, bv_ea)
    val () = $A.free<byte>($A.thaw<byte>(fz_ea))
  in set_exit_code(1) end
  else let
    var run_b1 = $B.create()
    val () = copy_to_builder_v(bv_ea, 0, exec_len - 1, 524288, run_b1)
    val extras = rev_arg_list(extra_arg_list(extra, 0, elen, $L.list_vt_nil(), 4096), $L.list_vt_nil())
    val run_argv = $L.list_vt_cons(mk_arg(run_b1), extras)
    val rc = run_program(bv_ea, run_argv)
    val () = (if rc < 0 then let
      val () = prerr! ("error: cannot run '")
      val () = prerr_seg(bv_ea, 0, exec_len - 1, 524288, 524288)
      val () = prerr! ("'")
      val () = prerr_newline()
    in set_exit_code(1) end
    else set_exit_code(rc))
    val () = $A.drop<byte>(fz_ea, bv_ea)
  in $A.free<byte>($A.thaw<byte>(fz_ea)) end
end

(* ============================================================
   do_check: preprocess + patsopt, no cc/link
   ============================================================ *)

#pub fn do_check(): void

implement do_check() = let
  val () = clear_build_err()
  val () = do_build_plain(0, 0)
  val () = do_build_plain(0, 1)
in
  if has_build_err() then
    println! ("check failed")
  else let
    val kind = generate_lib_docs()
  in
    if kind < 0 then let
      val () = set_build_err()
    in println! ("check failed") end
    (* As the Rust bats's build::check *)
    else if is_quiet() then ()
    else if kind > 0 then prerr! ("check passed (library)\n")
    else prerr! ("check passed (binary)\n")
  end
end
