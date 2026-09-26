staload "./bats.sats"
staload "argparse/src/lib.dats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "str/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* bats -- bats compiler entry point *)

#include "share/atspre_staload.hats"

staload AP = "argparse/src/lib.sats"
staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload S = "str/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"
staload "build.sats"
staload "commands.sats"

(* Match command buffer to dispatch code *)
(* 0=build 1=check 2=clean 3=lock 4=run 5=init 6=test 7=tree *)
(* 8=upload 9=add 10=remove 11=completions 12=version -1=unknown *)
fn dispatch_cmd {l:agz}
  (buf: !$A.arr(byte, l, 32), len: int): int = let
  val b0 = byte2int0($A.get<byte>(buf, 0))
  val b1 = byte2int0($A.get<byte>(buf, 1))
in
  if len = 5 then
    (if $AR.eq_int_int(b0, 98) then 0
    else if $AR.eq_int_int(b0, 99) then
      (if $AR.eq_int_int(b1, 104) then 1 else 2)
    else ~1): int
  else if len = 4 then
    (if $AR.eq_int_int(b0, 108) then 3
    else if $AR.eq_int_int(b0, 105) then 5
    else if $AR.eq_int_int(b0, 116) then
      (if $AR.eq_int_int(b1, 101) then 6 else 7)
    else ~1): int
  else if len = 3 then
    (if $AR.eq_int_int(b0, 114) then 4
    else if $AR.eq_int_int(b0, 97) then 9
    else ~1): int
  else if len = 6 then
    (if $AR.eq_int_int(b0, 117) then 8
    else if $AR.eq_int_int(b0, 114) then 10
    else ~1): int
  else if len = 11 then 11
  else if len = 7 then 12
  else ~1
end

(* Print usage matching Rust bats format *)
fn print_usage(): void = let
  val () = println! ("usage: bats [--run-in <dir>] [--quiet] <command>")
  val () = println! ("")
  val () = println! ("commands:")
  val () = println! ("  init binary [--claude]       Create a new binary project (src/bin/<name>.bats)")
  val () = println! ("  init library [--claude]      Create a new library project (src/lib.bats)")
  val () = println! ("  add <package> --repository <dir>")
  val () = println! ("                               Add a dependency")
  val () = println! ("  remove <package> --repository <dir>")
  val () = println! ("                               Remove a dependency")
  val () = println! ("  lock [--dev] [--dry-run] --repository <dir>")
  val () = println! ("                               Generate bats.lock")
  val () = println! ("  build [--only debug|release|native|wasm] [--repository <dir>]")
  val () = println! ("                               Build the project")
  val () = println! ("  run [--only debug|release] [--bin <name>] [--repository <dir>] [-- args...]")
  val () = println! ("                               Build and run a binary")
  val () = println! ("  test [--only native|wasm] [--filter <name>] [--repository <dir>]")
  val () = println! ("                               Run tests")
  val () = println! ("  check [--repository <dir>]   Type-check the project (no linking)")
  val () = println! ("  tree [--repository <dir>]    Show dependency tree")
  val () = println! ("  upload --repository <dir>    Package and upload a library")
  val () = println! ("  clean                        Remove generated artifacts")
  val () = println! ("  completions <shell>          Generate shell completions (bash, zsh, fish)")
in end

(* Copies src[s + i, e) to dst[i..], for bats run's arguments after
   "--"; returns the byte count. *)
fun copy_extra {l1,l2:agz}{i:nat | i <= 4096} .<4096 - i>.
  (src: !$A.arr(byte, l1, 4096), dst: !$A.arr(byte, l2, 4096),
   s: pos_t, e: int, i: int i): int =
  if i >= 4096 then i
  else if s + i >= e then i
  else let
    val () = $A.set<byte>(dst, i, int2byte0(peek_arr(src, s + i, 4096)))
  in copy_extra(src, dst, s, e, i + 1) end

(* Find the position of "--" separator in the argument buffer. *)
fun find_dashdash {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int): pos_t =
  if pos >= len then ~1
  else if pos >= 4096 then ~1
  else if peek_arr(buf, pos, 4096) = 45 && peek_arr(buf, pos + 1, 4096) = 45
          && peek_arr(buf, pos + 2, 4096) = 0 then pos
  else let
    val next = $S.find_null_at(buf, pos, 4096)
  in
    if next >= 4096 then ~1
    else find_dashdash(buf, next + 1, len)
  end

(* Scan --only values: read all repeated --only tokens from cmdline.
   Returns bitmask: bit0=debug bit1=release bit2=native bit3=wasm *)
fun scan_only {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int, mask: int): int =
  if pos >= len then mask
  else if pos >= 4096 then mask
  (* "--only" : 45,45,111,110,108,121 *)
  else if peek_arr(buf, pos, 4096) = 45 && peek_arr(buf, pos + 1, 4096) = 45
          && peek_arr(buf, pos + 2, 4096) = 111 && peek_arr(buf, pos + 3, 4096) = 110
          && peek_arr(buf, pos + 4, 4096) = 108 && peek_arr(buf, pos + 5, 4096) = 121 then let
    val next = $S.find_null_at(buf, min(pos + 6, 4096), 4096)
    val val_start = next + 1
  in
    if val_start >= len then mask
    else if val_start >= 4096 then mask
    else let
      val v0 = peek_arr(buf, val_start, 4096)
      val vend = $S.find_null_at(buf, val_start, 4096)
      val new_mask = (
        if $AR.eq_int_int(v0, 100) then
          (if (mask mod 2) = 0 then mask + 1 else mask)
        else if $AR.eq_int_int(v0, 114) then
          (if ((mask / 2) mod 2) = 0 then mask + 2 else mask)
        else if $AR.eq_int_int(v0, 110) then
          (if ((mask / 4) mod 2) = 0 then mask + 4 else mask)
        else if $AR.eq_int_int(v0, 119) then
          (if ((mask / 8) mod 2) = 0 then mask + 8 else mask)
        else mask): int
    in
      if vend >= 4096 then new_mask
      else scan_only(buf, vend + 1, len, new_mask)
    end
  end
  else let
    val next = $S.find_null_at(buf, pos, 4096)
  in
    if next >= 4096 then mask
    else scan_only(buf, next + 1, len, mask)
  end

(* The value of a string option copied to buf, and its length; 0 when
   the option was not given. *)
fn opt_string_copy {l:agz}{n:pos}
  (r: !$AP.parse_result, h: $AP.arg($AP.string_val), buf: !$A.arr(byte, l, n), n: int n): int =
  if $AP.is_present(r, h) then $AP.get_string_copy(r, h, buf, n) else 0

(* ============================================================
   Main: read argv (args_read: NUL-separated), dispatch
   ============================================================ *)

fn bats_main (): void = let
  val cl_buf = $A.alloc<byte>(4096)
  val cl_read = $E.args_read(cl_buf, 4096)
in
      case+ cl_read of
      | ~$R.some(cl_n) => let
          val dd_pos = find_dashdash(cl_buf, 0, cl_n)
          (* The arguments after "--\0", NUL-terminated, for bats run *)
          val extra_buf = $A.alloc<byte>(4096)
          val extra_end = (if dd_pos >= 0 then cl_n else 0): int
          val extra_len = copy_extra(cl_buf, extra_buf, dd_pos + 3, extra_end, 0)
          val effective_len = (if dd_pos >= 0 then dd_pos else cl_n): int
          val argc = count_argc(cl_buf, effective_len)
          val only_mask = scan_only(cl_buf, 0, effective_len, 0)
          val @(fz_cb, bv_cb) = $A.freeze<byte>(cl_buf)
          var pna_c = @[char][4]('b', 'a', 't', 's')
          val pna = $S.from_char_array(pna_c, 4)
          val pnl = 4
          val @(fzpn, bvpn) = $A.freeze<byte>(pna)
          var pha_c = @[char][15]('b', 'a', 't', 's', ' ', 'b', 'u', 'i', 'l', 'd', ' ', 't', 'o', 'o', 'l')
          val pha = $S.from_char_array(pha_c, 15)
          val phl = 15
          val @(fzph, bvph) = $A.freeze<byte>(pha)
          val p = $AP.parser_new(bvpn, pnl, bvph, phl)
          val () = $A.drop<byte>(fzpn, bvpn)
          val () = $A.free<byte>($A.thaw<byte>(fzpn))
          val () = $A.drop<byte>(fzph, bvph)
          val () = $A.free<byte>($A.thaw<byte>(fzph))
          var apn0 = @[char][7]('v', 'e', 'r', 'b', 'o', 's', 'e')
          var aph0 = @[char][14]('v', 'e', 'r', 'b', 'o', 's', 'e', ' ', 'o', 'u', 't', 'p', 'u', 't')
          val @(p, h_verbose) = ap_flag(p, apn0, 7, 118, aph0, 14)
          var apn1 = @[char][5]('q', 'u', 'i', 'e', 't')
          var aph1 = @[char][12]('q', 'u', 'i', 'e', 't', ' ', 'o', 'u', 't', 'p', 'u', 't')
          val @(p, h_quiet) = ap_flag(p, apn1, 5, 113, aph1, 12)
          var apn2 = @[char][6]('r', 'u', 'n', '-', 'i', 'n')
          var aph2 = @[char][16]('r', 'u', 'n', ' ', 'i', 'n', ' ', 'd', 'i', 'r', 'e', 'c', 't', 'o', 'r', 'y')
          val @(p, h_run_in) = ap_string_opt(p, apn2, 6, 0, aph2, 16)
          var apn3 = @[char][10]('r', 'e', 'p', 'o', 's', 'i', 't', 'o', 'r', 'y')
          var aph3 = @[char][18]('p', 'a', 'c', 'k', 'a', 'g', 'e', ' ', 'r', 'e', 'p', 'o', 's', 'i', 't', 'o', 'r', 'y')
          val @(p, h_repository) = ap_string_opt(p, apn3, 10, 0, aph3, 18)
          var apn4 = @[char][4]('o', 'n', 'l', 'y')
          var aph4 = @[char][12]('b', 'u', 'i', 'l', 'd', ' ', 't', 'a', 'r', 'g', 'e', 't')
          val @(p, h_only) = ap_string_opt(p, apn4, 4, 0, aph4, 12)
          var apn5 = @[char][3]('b', 'i', 'n')
          var aph5 = @[char][11]('b', 'i', 'n', 'a', 'r', 'y', ' ', 'n', 'a', 'm', 'e')
          val @(p, h_bin) = ap_string_opt(p, apn5, 3, 0, aph5, 11)
          var apn6 = @[char][4]('t', 'o', '-', 'c')
          var aph6 = @[char][27]('o', 'u', 't', 'p', 'u', 't', ' ', 'C', ' ', 'f', 'i', 'l', 'e', 's', ' ', 't', 'o', ' ', 'd', 'i', 'r', 'e', 'c', 't', 'o', 'r', 'y')
          val @(p, h_to_c) = ap_string_opt(p, apn6, 4, 0, aph6, 27)
          var apn7 = @[char][6]('c', 'l', 'a', 'u', 'd', 'e')
          var aph7 = @[char][19]('c', 'r', 'e', 'a', 't', 'e', ' ', 'c', 'l', 'a', 'u', 'd', 'e', ' ', 'r', 'u', 'l', 'e', 's')
          val @(p, h_claude) = ap_flag(p, apn7, 6, 0, aph7, 19)
          var apn8 = @[char][3]('d', 'e', 'v')
          var aph8 = @[char][24]('i', 'n', 'c', 'l', 'u', 'd', 'e', ' ', 'd', 'e', 'v', ' ', 'd', 'e', 'p', 'e', 'n', 'd', 'e', 'n', 'c', 'i', 'e', 's')
          val @(p, h_dev) = ap_flag(p, apn8, 3, 0, aph8, 24)
          var apn9 = @[char][7]('d', 'r', 'y', '-', 'r', 'u', 'n')
          var aph9 = @[char][12]('d', 'r', 'y', ' ', 'r', 'u', 'n', ' ', 'm', 'o', 'd', 'e')
          val @(p, h_dry_run) = ap_flag(p, apn9, 7, 0, aph9, 12)
          var apn10 = @[char][4]('h', 'e', 'l', 'p')
          var aph10 = @[char][9]('s', 'h', 'o', 'w', ' ', 'h', 'e', 'l', 'p')
          val @(p, h_help) = ap_flag(p, apn10, 4, 104, aph10, 9)
          var apn11 = @[char][6]('f', 'i', 'l', 't', 'e', 'r')
          var aph11 = @[char][11]('t', 'e', 's', 't', ' ', 'f', 'i', 'l', 't', 'e', 'r')
          val @(p, h_filter) = ap_string_opt(p, apn11, 6, 0, aph11, 11)
          var apn12 = @[char][7]('c', 'o', 'm', 'm', 'a', 'n', 'd')
          var aph12 = @[char][10]('s', 'u', 'b', 'c', 'o', 'm', 'm', 'a', 'n', 'd')
          val @(p, h_cmd) = ap_string_pos(p, apn12, 7, aph12, 10)
          var apn13 = @[char][8]('a', 'r', 'g', 'u', 'm', 'e', 'n', 't')
          var aph13 = @[char][19]('s', 'u', 'b', 'c', 'o', 'm', 'm', 'a', 'n', 'd', ' ', 'a', 'r', 'g', 'u', 'm', 'e', 'n', 't')
          val @(p, h_arg) = ap_string_pos(p, apn13, 8, aph13, 19)
          val result = $AP.parse(p, bv_cb, 4096, argc)
          val () = $A.drop<byte>(fz_cb, bv_cb)
          val () = $A.free<byte>($A.thaw<byte>(fz_cb))
        in
          case+ result of
          | ~$R.ok(r) => let
              val want_help = $AP.get_bool(r, h_help)
            in
              if want_help then let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(extra_buf)
              in print_usage() end
              else let
              val () = (if $AP.get_bool(r, h_verbose) then set_verbose(true) else ())
              val () = (if $AP.get_bool(r, h_quiet) then set_quiet(true) else ())
              (* Handle --run-in *)
              val () = (if $AP.is_present(r, h_run_in) then let
                val ri_buf = $A.alloc<byte>(4096)
                val _ = $AP.get_string_copy(r, h_run_in, ri_buf, 4096)
                val @(fz_ri, bv_ri) = $A.freeze<byte>(ri_buf)
                val chdr = $F.file_chdir(bv_ri, 4096)
                val () = $R.discard<int><int>(chdr)
                val () = $A.drop<byte>(fz_ri, bv_ri)
                val () = $A.free<byte>($A.thaw<byte>(fz_ri))
              in end else ())
              (* --repository: passed to the commands that use it; length 0
                 when absent *)
              val repo_buf = $A.alloc<byte>(4096)
              val repo_len = opt_string_copy(r, h_repository, repo_buf, 4096)
              val @(fz_repo, bv_repo) = $A.freeze<byte>(repo_buf)
              val @(fz_extra, bv_extra) = $A.freeze<byte>(extra_buf)
              (* --to-c: passed to do_build; length 0 when absent *)
              val tc_buf = $A.alloc<byte>(4096)
              val tc_len = opt_string_copy(r, h_to_c, tc_buf, 4096)
              val () = (if tc_len > 0 then set_to_c(1) else ())
              val @(fz_tc, bv_tc) = $A.freeze<byte>(tc_buf)
              (* Get command *)
              val cmd_buf = $A.alloc<byte>(32)
              val cmd_len = $AP.get_string_copy(r, h_cmd, cmd_buf, 32)
              val cmd_code = dispatch_cmd(cmd_buf, cmd_len)
              val () = $A.free<byte>(cmd_buf)
              val arg_buf = $A.alloc<byte>(4096)
              val arg_len = $AP.get_string_copy(r, h_arg, arg_buf, 4096)
            in let val () = (
              if cmd_code = 0 then let (* build *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val has_debug = (only_mask mod 2)
                val has_release = ((only_mask / 2) mod 2)
                val has_wasm = ((only_mask / 8) mod 2)
              in
                if only_mask = 0 then let
                  val () = do_build(0, 0, bv_tc, tc_len)
                  val () = do_build(1, 0, bv_tc, tc_len)
                  val () = do_build(0, 1, bv_tc, tc_len)
                in do_build(1, 1, bv_tc, tc_len) end
                else let
                  val bt = (if has_wasm > 0 then 1 else 0): int
                  val () = (if has_debug > 0 then do_build(0, bt, bv_tc, tc_len) else ())
                  val () = (if has_release > 0 then do_build(1, bt, bv_tc, tc_len) else ())
                  val () = (if has_debug = 0 then
                    if has_release = 0 then do_build(0, bt, bv_tc, tc_len)
                    else ()
                  else ())
                  val () = (if has_wasm > 0 then
                    if is_to_c() then
                      println! ("error: --to-c wasm is not yet implemented without shell")
                    else ()
                  else ())
                in
                  if has_debug = 0 then
                    if has_release = 0 then
                      if has_wasm = 0 then do_build(0, 0, bv_tc, tc_len)
                      else ()
                    else ()
                  else ()
                end
              end
              else if cmd_code = 1 then let (* check *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_check() end
              else if cmd_code = 2 then let (* clean *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_clean() end
              else if cmd_code = 3 then let (* lock *)
                val lk_dev = (if $AP.is_present(r, h_dev) then 1 else 0): int
                val lk_dry = (if $AP.is_present(r, h_dry_run) then 1 else 0): int
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_lock(lk_dev, lk_dry, bv_repo, repo_len) end
              else if cmd_code = 4 then let (* run *)
                val bin_buf = $A.alloc<byte>(256)
                val bin_len = opt_string_copy(r, h_bin, bin_buf, 256)
                fn check_only_release {l2:agz}
                  (buf: !$A.arr(byte, l2, 32), olen: int): int =
                  if olen = 7 then let
                    val b0 = byte2int0($A.get<byte>(buf, 0))
                  in (if $AR.eq_int_int(b0, 114) then 1 else 0): int end
                  else 0
                val run_release = (let
                  val ob2 = $A.alloc<byte>(32)
                  val ol2 = $AP.get_string_copy(r, h_only, ob2, 32)
                  val is_rel = check_only_release(ob2, ol2)
                  val () = $A.free<byte>(ob2)
                in is_rel end): int
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val @(fz_bin, bv_bin) = $A.freeze<byte>(bin_buf)
                val () = do_run(run_release, bv_bin, bin_len, bv_extra, extra_len)
                val () = $A.drop<byte>(fz_bin, bv_bin)
              in $A.free<byte>($A.thaw<byte>(fz_bin)) end
              else if cmd_code = 5 then let (* init *)
                val init_claude = (if $AP.get_bool(r, h_claude) then 1 else 0): int
                val () = $AP.parse_result_free(r)
              in
                if arg_len > 0 then let
                  val @(fz_ia, bv_ia) = $A.freeze<byte>(arg_buf)
                  val () = do_init(bv_ia, arg_len, init_claude)
                  val () = $A.drop<byte>(fz_ia, bv_ia)
                in $A.free<byte>($A.thaw<byte>(fz_ia)) end
                else let
                  val () = $A.free<byte>(arg_buf)
                  val () = prerr! ("error: specify 'binary' or 'library'\nusage: bats init binary [--claude]\n       bats init library [--claude]")
                  val () = prerr_newline()
                in set_build_err() end
              end
              else if cmd_code = 6 then let (* test *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_test() end
              else if cmd_code = 7 then let (* tree *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_tree() end
              else if cmd_code = 8 then let (* upload *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_upload(bv_repo, repo_len) end
              else if cmd_code = 9 then let (* add *)
                val () = $AP.parse_result_free(r)
              in
                if arg_len > 0 then let
                  val @(fz_ab, bv_ab) = $A.freeze<byte>(arg_buf)
                  val () = do_add(bv_ab, 0, arg_len, 4096)
                  val () = $A.drop<byte>(fz_ab, bv_ab)
                  val () = $A.free<byte>($A.thaw<byte>(fz_ab))
                in end
                else let
                  val () = $A.free<byte>(arg_buf)
                in println! ("error: specify a package name\nusage: bats add <package>") end
              end
              else if cmd_code = 10 then let (* remove *)
                val () = $AP.parse_result_free(r)
              in
                if arg_len > 0 then let
                  val @(fz_rb, bv_rb) = $A.freeze<byte>(arg_buf)
                  val () = do_remove(bv_rb, 0, arg_len, 4096)
                  val () = $A.drop<byte>(fz_rb, bv_rb)
                  val () = $A.free<byte>($A.thaw<byte>(fz_rb))
                in end
                else let
                  val () = $A.free<byte>(arg_buf)
                in println! ("error: specify a package name\nusage: bats remove <package>") end
              end
              else if cmd_code = 11 then let (* completions *)
                val () = $AP.parse_result_free(r)
                fn check_shell_arg {l2:agz}
                  (buf: !$A.arr(byte, l2, 4096), alen: int): int =
                  if alen <= 0 then ~1
                  else let val b0 = byte2int0($A.get<byte>(buf, 0)) in
                    if $AR.eq_int_int(b0, 98) then 0
                    else if $AR.eq_int_int(b0, 122) then 1
                    else if $AR.eq_int_int(b0, 102) then 2
                    else ~1
                  end
                val shell = check_shell_arg(arg_buf, arg_len)
                val () = $A.free<byte>(arg_buf)
              in
                if shell >= 0 then do_completions(shell)
                else println! ("error: specify a shell (bash, zsh, fish)\nusage: bats completions bash|zsh|fish")
              end
              else if cmd_code = 12 then let (* version *)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in println! ("bats 0.1.0") end
              else let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in println! ("usage: bats <init|lock|add|remove|build|run|test|check|tree|upload|clean|completions> [--only debug|release]") end)
              val () = $A.drop<byte>(fz_repo, bv_repo)
              val () = $A.free<byte>($A.thaw<byte>(fz_repo))
              val () = $A.drop<byte>(fz_extra, bv_extra)
              val () = $A.free<byte>($A.thaw<byte>(fz_extra))
              val () = $A.drop<byte>(fz_tc, bv_tc)
              val () = $A.free<byte>($A.thaw<byte>(fz_tc))
            in end
            end end
          | ~$R.err(e) => let
              val () = $AP.parse_error_free(e)
              val () = $A.free<byte>(extra_buf)
            in print_usage() end
        end
      | ~$R.none() => let
          val () = $A.free<byte>(cl_buf)
        in println! ("Cannot read the command line") end
end

(* Exit non-zero when any command recorded an error, so CI and scripts
   can rely on the exit status. *)
implement __BATS_main0 () = let
  val () = bats_main ()
in
  if has_build_err () then exit_void (1)
  else if get_exit_code () <> 0 then exit_void (get_exit_code ())
  else ()
end
