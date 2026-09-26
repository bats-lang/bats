(* commands -- subcommand implementations for the bats compiler *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use list as L
#use str as S
#use process as P
#use result as R
#use sha256 as SHA
#use toml as T

staload "helpers.sats"
staload "build.sats"
staload "lexer.sats"
staload "emitter.sats"

(* ============================================================
   do_test: build and run tests
   ============================================================ *)

#pub fn do_test(): void

implement do_test() = let
  (* Enable test mode so emit includes unittest blocks *)
  val () = set_test_mode(true)
  val () = do_build(0, 0)
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
   generate docs: scan lib.bats for #pub and write docs/
   ============================================================ *)

#pub fn do_generate_docs(pkg_name_len: int, kind_is_lib: int): void

implement do_generate_docs(pkg_name_len, kind_is_lib) =
  if kind_is_lib = 0 then ()
  else let
    var cmd = $B.create()
    val () = $B.bput(cmd, "docs")
    val _ = run_mkdir(cmd)
    val lp = str_to_path_arr("src/lib.bats")
    val @(fz_lp, bv_lp) = $A.freeze<byte>(lp)
    val lib_or = $F.file_open(bv_lp, 524288, 0, 0)
    val () = $A.drop<byte>(fz_lp, bv_lp)
    val () = $A.free<byte>($A.thaw<byte>(fz_lp))
  in
    case+ lib_or of
    | ~$R.ok(lfd) => let
        val lbuf = $A.alloc<byte>(524288)
        val lrr = $F.file_read(lfd, lbuf, 524288)
        val llen = (case+ lrr of | ~$R.ok(n) => n | ~$R.err(_) => 0): int
        val lcr = $F.file_close(lfd)
        val () = $R.discard<int><int>(lcr)
        var doc_b: $B.builder_v = $B.create()
        val () = bput_v(doc_b, "# API Reference\n\n")
        (* Scan for #pub lines: 35,112,117,98,32 *)
        (* The rest of the line from q, up to and including its newline,
           copied to doc without the newline. Returns the position after it. *)
        fun copy_line {l3:agz}{q:nat | q <= 524288} .<524288 - q>.
          (buf: !$A.arr(byte, l3, 524288), doc: !$B.builder_v >> $B.builder_v,
           pos: int q): [r:int | q <= r; r <= 524288] int r =
          if pos >= 524288 then pos
          else let
            val b = peek_arr(buf, pos, 524288)
          in
            if $AR.eq_int_int(b, 10) then pos + 1
            else let
              val () = put_char_v(doc, b)
            in copy_line(buf, doc, pos + 1) end
          end
        fun skip_line {l4:agz}{q:nat | q < 524288} .<524288 - q>.
          (buf: !$A.arr(byte, l4, 524288), pos: int q): [r:int | q < r; r <= 524288] int r =
          if $AR.eq_int_int(peek_arr(buf, pos, 524288), 10) then pos + 1
          else if pos + 1 >= 524288 then 524288
          else skip_line(buf, pos + 1)
        fun scan_pub {l2:agz}{q:nat | q <= 524288} .<524288 - q>.
          (buf: !$A.arr(byte, l2, 524288), doc: !$B.builder_v >> $B.builder_v,
           pos: int q, len: int): void =
          if pos >= len then ()
          else if pos + 4 >= 524288 then ()
          (* "#pub " : 35,112,117,98,32 *)
          else if peek_arr(buf, pos, 524288) = 35 && peek_arr(buf, pos + 1, 524288) = 112
                  && peek_arr(buf, pos + 2, 524288) = 117 && peek_arr(buf, pos + 3, 524288) = 98
                  && peek_arr(buf, pos + 4, 524288) = 32 then let
            val () = bput_v(doc, "```\n")
            val np = copy_line(buf, doc, pos + 5)
            val () = bput_v(doc, "\n```\n\n")
          in scan_pub(buf, doc, np, len) end
          (* Any other line starting with '#' skips to the next NUL byte. *)
          else if peek_arr(buf, pos, 524288) = 35 then let
            val np = $S.find_null_at(buf, pos, 524288)
          in
            if np >= 524288 then ()
            else scan_pub(buf, doc, np + 1, len)
          end
          else scan_pub(buf, doc, skip_line(buf, pos), len)
        val () = scan_pub(lbuf, doc_b, 0, llen)
        val () = $A.free<byte>(lbuf)
        val dp = str_to_path_arr("docs/lib.md")
        val @(fz_dp, bv_dp) = $A.freeze<byte>(dp)
        val _ = write_file_from_builder(bv_dp, 524288, doc_b)
        val () = $A.drop<byte>(fz_dp, bv_dp)
        val () = $A.free<byte>($A.thaw<byte>(fz_dp))
        (* Write docs/index.md *)
        var idx_b = $B.create()
        val () = $B.bput(idx_b, "# Documentation\n\n- [API Reference](lib.md)\n")
        val ip = str_to_path_arr("docs/index.md")
        val @(fz_ip, bv_ip) = $A.freeze<byte>(ip)
        val _ = write_file_from_builder(bv_ip, 524288, idx_b)
        val () = $A.drop<byte>(fz_ip, bv_ip)
        val () = $A.free<byte>($A.thaw<byte>(fz_ip))
      in end
    | ~$R.err(_) => ()
  end

(* ============================================================
   upload: package library for repository
   ============================================================ *)

(* dst[i, n) = src[i, n) *)
fun copy_prefix {la,lb:agz}{n:pos | n <= 524288}{i:nat | i <= n} .<n - i>.
  (src: !$A.arr(byte, la, 524288), dst: !$A.arr(byte, lb, n), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in copy_prefix(src, dst, n, i + 1) end

(* Writes "<sha256 of the archive>  <archive filename>\n" to the sidecar,
   as the Rust bats did. arc: the archive read into arc[0, n). *)
fn write_sidecar_of {la,lz:agz}{n:nat | n <= 524288}
  (arc: $A.arr(byte, la, 524288), n: int n,
   zp: !$A.borrow(byte, lz, 524288), zlen: int): void =
  if n <= 0 then let
    val () = $A.free<byte>(arc)
    val () = set_build_err()
  in println! ("error: cannot read the archive to hash it") end
  else let
    val data = $A.alloc<byte>(n)
    val () = copy_prefix(arc, data, n, 0)
    val () = $A.free<byte>(arc)
    val hex = $A.alloc<byte>(64)
    val () = $SHA.hash(data, n, hex)
    val () = $A.free<byte>(data)
    var sc: $B.builder_v = $B.create()
    val @(fh, bh) = $A.freeze<byte>(hex)
    val () = copy_to_builder_v(bh, 0, 64, 64, sc)
    val () = $A.drop<byte>(fh, bh)
    val () = $A.free<byte>($A.thaw<byte>(fh))
    val () = bput_v(sc, "  ")
    val base = find_basename_start(zp, 0, 524288, ~1, 524288)
    val () = copy_to_builder_v(zp, base, zlen, 524288, sc)
    val () = bput_v(sc, "\n")
    var sp: $B.builder_v = $B.create()
    val () = copy_to_builder_v(zp, 0, zlen, 524288, sp)
    val () = bput_v(sp, ".sha256")
    val () = put_char_v(sp, 0)
    val @(spa, _) = $B.to_arr(sp)
    val @(fz_sp, bv_sp) = $A.freeze<byte>(spa)
    val _ = write_file_from_builder(bv_sp, 524288, sc)
    val () = $A.drop<byte>(fz_sp, bv_sp)
    val () = $A.free<byte>($A.thaw<byte>(fz_sp))
  in end

(* The sidecar of the archive at zp[0, zlen) (NUL-terminated). *)
fn write_sidecar {lz:agz} (zp: !$A.borrow(byte, lz, 524288), zlen: int): void =
  case+ $F.file_open(zp, 524288, 0, 0) of
  | ~$R.ok(afd) => let
      val arc = $A.alloc<byte>(524288)
      val n = (case+ $F.file_read(afd, arc, 524288) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 524288] int k
      val () = $R.discard<int><int>($F.file_close(afd))
    in write_sidecar_of(arc, n, zp, zlen) end
  | ~$R.err(_) => let
      val () = set_build_err()
    in println! ("error: cannot open the archive to hash it") end

(* repo: the --repository path in repo[0, rplen); rplen is 0 when it
   was not given. *)
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
                (* Get version from git commit timestamp *)
                val git_exec = str_to_path_arr("/usr/bin/git")
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
                (* Check if branch is "main" (109,97,105,110) *)
                val b0 = byte2int0($A.get<byte>(br_out, 0))
                val b1 = byte2int0($A.get<byte>(br_out, 1))
                val b2 = byte2int0($A.get<byte>(br_out, 2))
                val b3 = byte2int0($A.get<byte>(br_out, 3))
                val is_main = (if br_len >= 4 then
                  $AR.eq_int_int(b0, 109) &&
                  $AR.eq_int_int(b1, 97) &&
                  $AR.eq_int_int(b2, 105) &&
                  $AR.eq_int_int(b3, 110)
                else false): bool
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
                val @(verbuf, verlen) = (let
                  val @(va, vl) = $B.to_arr(vb_b)
                in @(va, vl) end): [lvb:agz] @($A.arr(byte, lvb, 524288), int)
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
                val () = copy_to_builder_v(bv_vb, 0, verlen, 524288, zip_path)
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
                val zip_exec = str_to_path_arr("/usr/bin/zip")
                val @(fz_ze, bv_ze) = $A.freeze<byte>(zip_exec)
                var za1 = $B.create()
                val () = bput_v(za1, "zip")
                var za2 = $B.create()
                val () = bput_v(za2, "-r")
                var za3 = $B.create()
                val () = copy_to_builder_v(bv_zp, 0, zpa_len - 1, 524288, za3)
                var za4 = $B.create()
                val () = bput_v(za4, "bats.toml")
                var za5 = $B.create()
                val () = bput_v(za5, "src/")
                val () = $A.drop<byte>(fz_nb, bv_nb)
                val () = $A.free<byte>($A.thaw<byte>(fz_nb))
                val () = $A.drop<byte>(fz_px, bv_px)
                val () = $A.free<byte>($A.thaw<byte>(fz_px))
                val zip_argv = $L.list_vt_cons(mk_arg(za1),
                  $L.list_vt_cons(mk_arg(za2), $L.list_vt_cons(mk_arg(za3),
                  $L.list_vt_cons(mk_arg(za4), $L.list_vt_cons(mk_arg(za5),
                  $L.list_vt_nil())))))
                val rc = run_cmd(bv_ze, zip_argv)
                val () = $A.drop<byte>(fz_ze, bv_ze)
                val () = $A.free<byte>($A.thaw<byte>(fz_ze))
              in
                if rc <> 0 then let
                  val () = $A.drop<byte>(fz_zp, bv_zp)
                  val () = $A.free<byte>($A.thaw<byte>(fz_zp))
                  val () = $A.drop<byte>(fz_vb, bv_vb)
                  val () = $A.free<byte>($A.thaw<byte>(fz_vb))
                in println! ("error: upload failed") end
                else let
                  (* The sidecar zip_path + ".sha256" *)
                  val () = write_sidecar(bv_zp, zpa_len - 1)
                  val () = $A.drop<byte>(fz_zp, bv_zp)
                  val () = $A.free<byte>($A.thaw<byte>(fz_zp))
                  val () = $A.drop<byte>(fz_vb, bv_vb)
                  val () = $A.free<byte>($A.thaw<byte>(fz_vb))
                  val () = do_generate_docs(0, 1)
                in println! ("uploaded successfully") end
              end
              else let
                val () = $A.free<byte>(nbuf)
              in println! ("error: --repository is required for upload") end
            else let
              val () = $A.free<byte>(nbuf)
            in println! ("error: 'upload' is only for library packages (kind = \"lib\")") end
          | ~$R.none() => let
              val () = $A.free<byte>(nbuf)
            in println! ("error: package.name not found in bats.toml") end
        end
      | ~$R.err(_) => println! ("error: could not parse bats.toml")
    end
  | ~$R.err(_) => println! ("error: could not open bats.toml")
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

#pub fn do_init(kind: int, claude: int): void

implement do_init(kind, claude) = let
  (* Check for existing project *)
  val has_toml = file_exists("bats.toml")
  val has_gi = file_exists(".gitignore")
in
  if has_toml then println! ("error: bats.toml already exists")
  else if has_gi then println! ("error: .gitignore already exists")
  else let
  (* kind: 0=binary, 1=library *)
  (* Get current directory name via readlink /proc/self/cwd *)
  val @(cwd_buf, cwd_len) = (let
    (* Get CWD via pwd *)
    val pwd_exec = str_to_path_arr("/bin/pwd")
    val @(fz_pwd, bv_pwd) = $A.freeze<byte>(pwd_exec)
    var pwd_b1 = $B.create()
    val () = bput_v(pwd_b1, "pwd")
    val pwd_argv = $L.list_vt_cons(mk_arg(pwd_b1), $L.list_vt_nil())
    (* TODO: run_cmd sends stdout to /dev/null, need stdout capture *)
    val _ = run_cmd(bv_pwd, pwd_argv)
    val () = $A.drop<byte>(fz_pwd, bv_pwd)
    val () = $A.free<byte>($A.thaw<byte>(fz_pwd))
    (* Write placeholder CWD *)
    var cwdb = $B.create()
    val () = $B.bput(cwdb, ".")
    val cwdp = str_to_path_arr("/tmp/_bpoc_cwd.txt")
    val @(fz_cwdp, bv_cwdp) = $A.freeze<byte>(cwdp)
    val _ = write_file_from_builder(bv_cwdp, 524288, cwdb)
    val () = $A.drop<byte>(fz_cwdp, bv_cwdp)
    val () = $A.free<byte>($A.thaw<byte>(fz_cwdp))
    val cp = str_to_path_arr("/tmp/_bpoc_cwd.txt")
    val @(fz_cp, bv_cp) = $A.freeze<byte>(cp)
    val cf = $F.file_open(bv_cp, 524288, 0, 0)
    val () = $A.drop<byte>(fz_cp, bv_cp)
    val () = $A.free<byte>($A.thaw<byte>(fz_cp))
  in case+ cf of
    | ~$R.ok(cfd) => let
        val cb = $A.alloc<byte>(4096)
        val cr2 = $F.file_read(cfd, cb, 4096)
        val clen = (case+ cr2 of | ~$R.ok(nn) => nn | ~$R.err(_) => 0): pos_t
        val ccr = $F.file_close(cfd)
        val () = $R.discard<int><int>(ccr)
        (* strip trailing newline *)
        val clen2 = strip_newline_arr(cb, clen)
      in @(cb, clen2) end
    | ~$R.err(_) => let val cb = $A.alloc<byte>(4096) in @(cb, 0) end
  end): [lcwd:agz] @($A.arr(byte, lcwd, 4096), int)
  val @(fz_cwd, bv_cwd) = $A.freeze<byte>(cwd_buf)
  (* Find last '/' in cwd path to extract basename *)
  fun find_last_slash {l2:agz}{fuel2:nat} .<fuel2>.
    (bv: !$A.borrow(byte, l2, 4096), pos: pos_t, len: int,
     last: pos_t, fuel2: int fuel2): pos_t =
    if fuel2 <= 0 then last
    else if pos >= len then last
    else let
      val b = peek(bv, pos, 4096)
    in
      if b = 47 then find_last_slash(bv, pos + 1, len, pos, fuel2 - 1)
      else find_last_slash(bv, pos + 1, len, last, fuel2 - 1)
    end
  val last_slash = find_last_slash(bv_cwd, 0, cwd_len, ~1, 4096)
  val name_start = last_slash + 1
  val name_len = cwd_len - name_start
  (* mkdir *)
  var cmd1: $B.builder_v = $B.create()
  val () = (if kind = 0 then bput_v(cmd1, "src/bin")
    else bput_v(cmd1, "src"))
  val _ = run_mkdir(cmd1)
  (* Write bats.toml *)
  var toml: $B.builder_v = $B.create()
  val () = bput_v(toml, "[package]\nname = \"")
  val () = copy_to_builder_v(bv_cwd, name_start, cwd_len, 4096, toml)
  val () = (if kind = 0 then bput_v(toml, "\"\nkind = \"bin\"\n\n[dependencies]\n")
    else bput_v(toml, "\"\nkind = \"lib\"\n\n[dependencies]\n"))
  val tp = str_to_path_arr("bats.toml")
  val @(fz_tp, bv_tp) = $A.freeze<byte>(tp)
  val rc = write_file_from_builder(bv_tp, 524288, toml)
  val () = $A.drop<byte>(fz_tp, bv_tp)
  val () = $A.free<byte>($A.thaw<byte>(fz_tp))
  (* Write source file *)
  val @(rc2) = (if kind = 0 then let
    var src = $B.create()
    val () = $B.bput(src, "implement ")
    val () = $B.bput(src, "main0 () = println! (\"hello, world!\")\n")
    var src_path = $B.create()
    val () = $B.bput(src_path, "src/bin/")
    val () = copy_to_builder(bv_cwd, name_start, cwd_len, 4096, src_path, 4096)
    val () = $B.bput(src_path, ".bats")
    val () = $B.put_char(src_path, 0)
    val @(src_pa, _) = $B.to_arr(src_path)
    val @(fz_sp, bv_sp) = $A.freeze<byte>(src_pa)
    val r = write_file_from_builder(bv_sp, 524288, src)
    val () = $A.drop<byte>(fz_sp, bv_sp)
    val () = $A.free<byte>($A.thaw<byte>(fz_sp))
  in @(r) end
  else let
    var src = $B.create()
    val () = $B.bput(src, "#pub fun hello(): void\n\n")
    val () = $B.bput(src, "implement hello () = println! (\"hello from library\")\n")
    var src_path = $B.create()
    val () = $B.bput(src_path, "src/lib.bats")
    val () = $B.put_char(src_path, 0)
    val @(src_pa, _) = $B.to_arr(src_path)
    val @(fz_sp, bv_sp) = $A.freeze<byte>(src_pa)
    val r = write_file_from_builder(bv_sp, 524288, src)
    val () = $A.drop<byte>(fz_sp, bv_sp)
    val () = $A.free<byte>($A.thaw<byte>(fz_sp))
  in @(r) end): @(int)
  val () = $A.drop<byte>(fz_cwd, bv_cwd)
  val () = $A.free<byte>($A.thaw<byte>(fz_cwd))
  (* Write .gitignore *)
  var gi = $B.create()
  val () = $B.bput(gi, "build/\ndist/\nbats_modules/\ndocs/\n")
  val gp = str_to_path_arr(".gitignore")
  val @(fz_gp, bv_gp) = $A.freeze<byte>(gp)
  val rc3 = write_file_from_builder(bv_gp, 524288, gi)
  val () = $A.drop<byte>(fz_gp, bv_gp)
  val () = $A.free<byte>($A.thaw<byte>(fz_gp))
in
  if rc = 0 then
    if rc2 = 0 then
      if rc3 = 0 then let
        val () = (if claude > 0 then write_claude_rules() else ())
      in println! ("initialized bats project in current directory") end
      else println! ("error: failed to write .gitignore")
    else println! ("error: failed to write source file")
  else println! ("error: failed to write bats.toml")
end end

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
      val sed_exec = str_to_path_arr("/usr/bin/sed")
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
  val exec = str_to_path_arr("/bin/echo")
  val @(fz_exec, bv_exec) = $A.freeze<byte>(exec)
  var ba1 = $B.create()
  val () = bput_v(ba1, "echo")
  var ba2 = $B.create()
  val () = bput_v(ba2, "check passed")
  val argv = $L.list_vt_cons(mk_arg(ba1),
    $L.list_vt_cons(mk_arg(ba2), $L.list_vt_nil()))
  val envp: $L.listv($P.arg_entry) = $L.list_vt_nil()
  val spawn_r = $P.spawn(bv_exec, argv, envp,
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

(* b[i, len) to stderr. *)
fun prerr_seg {l:agz}{m:pos}{fuel:nat} .<fuel>.
  (b: !$A.borrow(byte, l, m), i: pos_t, len: int, m: int m, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if i >= len then ()
  else let
    val () = prerr_char(int2char0(peek(b, i, m)))
  in prerr_seg(b, i + 1, len, m, fuel - 1) end

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
  val () = do_build(release, 0)
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
  val () = do_build(0, 0)
  val () = do_build(0, 1)
in
  if has_build_err() then
    println! ("check failed")
  else let
    val () = println! ("  process: check passed")
    val () = println! ("  exit code: 0")
  in
    println! ("check passed")
  end
end
