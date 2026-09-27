staload AP = "argparse/src/lib.sats"
staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload PA = "path/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"
staload S = "str/src/lib.sats"
staload SHA = "sha256/src/lib.sats"























typedef pos_t = [p:int] int p


fn peek {l:agz}{n:pos}{p:int}
  (src: !$A.borrow(byte, l, n), p: int p, n: int n): int







fn peek_arr {l:agz}{n:pos}{p:int}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n): int







fn poke_arr {l:agz}{n:pos}{p:int}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n, v: int): void







fn find_null_from {l:agz}{n:pos}{p:int}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n): pos_t






fn find_null_bv_from {l:agz}{n:pos}{p:int}
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n): pos_t






















fn is_verbose(): bool

fn is_quiet(): bool

fn is_test_mode(): bool

fn is_to_c(): bool

fn set_verbose(v: bool): void

fn set_quiet(v: bool): void

fn set_test_mode(v: bool): void

fn set_lock_dev(v: bool): void

fn is_lock_dev(): bool

fn set_repo {sn:nat} (s: string sn): void

fn get_repo(): string

fn set_bin {sn:nat} (s: string sn): void

fn get_bin(): string

fn set_to_c(v: int): void

fn get_to_c(): int

fn set_to_c_done(v: int): void

fn get_to_c_done(): int

fn set_self_path {sn:nat} (s: string sn): void

fn get_self_path(): string

fn set_build_err(): void

fn has_build_err(): bool

fn clear_build_err(): void



fn set_exit_code(v: int): void

fn get_exit_code(): int































fn print_arr {l:agz}{n:pos}  (buf: !$A.arr(byte, l, n), i: pos_t, len: int, max: int n): void















fn is_dot_or_dotdot {l:agz}{n:pos}
  (ent: !$A.arr(byte, l, n), len: int, max: int n): bool














fn ent_has_suffix {l:agz}{n:pos}{k:nat | k <= n}{m:pos | m <= 1048576}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n, sfx: &(@[char][m]), m: int m): bool









fn ent_name_eq {l:agz}{n:pos}{k:nat | k <= n}{m:pos | m <= 1048576}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n, s: &(@[char][m]), m: int m): bool









fn is_ident_byte(b: int): bool








fn lit_at {l:agz}{n:pos}{m:pos | m <= 1048576}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n, lit: &(@[char][m]), m: int m): bool











fn has_bats_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn has_dats_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn has_dats_c_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn has_dats_o_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn has_sha256_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn has_lib_dats_c_sfx {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn has_lib_dats_o_sfx {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn is_lib_bats {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn is_lib_dats {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn is_lib_dats_c {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool





fn is_lib_dats_o {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool







fn lit_as {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_begin {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_binary {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_dollar_UNITTEST {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_dollar_UNSAFE {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_dot_slash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_end {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_exthash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_fun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_hash_pub {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_hash_target {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_hash_use {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_let {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_local {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_machash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_no_mangle {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_prfn {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_prfun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_primplement {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_slash_srcslash_libdot_dats {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_staload_dq {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool





fn lit_while {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool




























fn prerr_seg {l:agz}{m:pos}
  (b: !$A.borrow(byte, l, m), i: pos_t, len: int, m: int m): void




fn print_borrow {l:agz}{n:pos}  (buf: !$A.borrow(byte, l, n), i: pos_t, len: int, max: int n): void








fn copy_to_builder {l:agz}{n:pos}{bn:nat | bn + n <= $B.BUILDER_CAP}  (src: !$A.borrow(byte, l, n), start: pos_t, stop: int, max: int n,
   dst: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + n] $B.builder(m)): void



















fn put_char_v(out: !$B.builder_v >> $B.builder_v, v: int): void




fn bput_v {sn:nat}
  (out: !$B.builder_v >> $B.builder_v, s: string sn): void













fn put_int_v(out: !$B.builder_v >> $B.builder_v, v: int): void

fn put_newline_v(out: !$B.builder_v >> $B.builder_v): void





fn copy_to_builder_v {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), start: pos_t, stop: int, max: int n,
   dst: !$B.builder_v >> $B.builder_v): void




















fn append_builder (out: !$B.builder_v >> $B.builder_v, b: $B.builder_v): void















fn find_basename_start {l:agz}{n:pos}  (bv: !$A.borrow(byte, l, n), pos: pos_t, max: int n,
   last: pos_t): pos_t



















fn wbw_loop {l:agz}  (bw: !$F.buf_writer, bv: !$A.borrow(byte, l, 524288),
   i: pos_t, lim: int): void
















fn is_newer {l1:agz}{l2:agz}
  (p1: !$A.borrow(byte, l1, 524288), p2: !$A.borrow(byte, l2, 524288)): bool








fn freshness_check_bv
  (out_b: $B.builder_v, in_b: $B.builder_v): bool






















fn touch_sats_stamp (): void











fn c_fresh_bv
  (out_b: $B.builder_v, in_b: $B.builder_v): bool


















fn file_has_bytes {lp:agz}{lb:agz}
  (path_bv: !$A.borrow(byte, lp, 524288), bv: !$A.borrow(byte, lb, 524288), len: int): bool
























fn arr_range_to_builder_v {l:agz}
  (src: !$A.arr(byte, l, 4096), i: pos_t, lim: int,
   dst: !$B.builder_v >> $B.builder_v): void


















fn str_to_arr4096 {sn:nat} (s: string sn): [ls:agz] $A.arr(byte, ls, 4096)



















fn mk_arg(b: $B.builder_v): $P.arg_entry












fn rev_arg_list
  (xs: $L.listv($P.arg_entry), acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry)




fn split_null_to_list(b: $B.builder_v): $L.listv($P.arg_entry)










































fn split_spaces_to_list(b: $B.builder_v): $L.listv($P.arg_entry)










fn run_mkdir
  (path_b: $B.builder_v): int






















fn run_program {le:agz}
  (exec_bv: !$A.borrow(byte, le, 524288), argv: $L.listv($P.arg_entry)): int













fn run_cmd {le:agz}
  (exec_bv: !$A.borrow(byte, le, 524288),
   argv: $L.listv($P.arg_entry)): int



































fn parse_decimal {l:agz}{n:pos}
  (buf: !$A.arr(byte, l, n), len: int, max: int n): int


















fn timestamp_to_calver(ts: int): @(int, int, int, int)





















fn run_cmd_capture {le:agz}{lo:agz}
  (exec_bv: !$A.borrow(byte, le, 524288),
   argv: $L.listv($P.arg_entry),
   outbuf: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k)






























fn prerr_builder (b: $B.builder_v): void



















































































































































































fn run_patsopt {lph:agz}{lo:agz}{li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int): int
































































































fn run_cc {lph:agz}{lo:agz}{li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int,
   rel: int): int





























































































fn write_file_from_builder {lp:agz}{np:pos | np < 1048576}
  (path_bv: !$A.borrow(byte, lp, np), path_len: int np,
   content_b: $B.builder_v): int



































fn rput(r: !$B.rope, v: int): void



fn rbput {sn:nat} (r: !$B.rope, s: string sn): void




fn rput_int(r: !$B.rope, v: int): void







































fn file_has_rope {lp:agz}{k:nat}
  (path_bv: !$A.borrow(byte, lp, 524288), cs: !$B.rope_list(k)): bool

































fn write_file_from_rope {lp:agz}{k:nat}
  (path_bv: !$A.borrow(byte, lp, 524288), cs: !$B.rope_list(k)): int















datavtype whole_file =
  | {la,l:agz}{m:pos}{n:nat | n < m}
    whole_ok of ($A.arena(byte, la, m, m, 1), $A.arrx(byte, l, m, la), int m, int n)
  | whole_err of int




fn read_whole {lp:agz}{np:pos | np < 1048576}
  (path: !$A.borrow(byte, lp, np), plen: int np): whole_file































fn whole_free {la,l:agz}{m:pos}
  (ar: $A.arena(byte, la, m, m, 1), p: $A.arrx(byte, l, m, la)): void





fn str_to_path_arr {sn:nat | sn < $B.BUILDER_CAP} (s: string sn): [l:agz] $A.arr(byte, l, 524288)












fn make_bats_toml {l:agz}{n:pos | n >= 9}
  (buf: !$A.arr(byte, l, n)): void














fn make_src_bin {l:agz}{n:pos | n >= 7}
  (buf: !$A.arr(byte, l, n)): void












fn make_package {l:agz}{n:pos | n >= 7}
  (buf: !$A.arr(byte, l, n)): void












fn make_name {l:agz}{n:pos | n >= 4}
  (buf: !$A.arr(byte, l, n)): void









fn make_kind {l:agz}{n:pos | n >= 4}
  (buf: !$A.arr(byte, l, n)): void














fn count_argc {l:agz}
  (buf: !$A.arr(byte, l, 4096), len: int): int











fn ap_flag {tp:nat}{ac:nat | ac < 64}{nn,nh:pos | tp + nn + nh <= 8192; nn <= 1048576; nh <= 1048576}
  (p: $AP.parser(tp, ac), name: &(@[char][nn]), nn: int nn, sc: int, help: &(@[char][nh]), nh: int nh
  ): @($AP.parser(tp + nn + nh, ac + 1), $AP.arg($AP.bool_val))











fn ap_string_opt {tp:nat}{ac:nat | ac < 64}{nn,nh:pos | tp + nn + nh <= 8192; nn <= 1048576; nh <= 1048576}
  (p: $AP.parser(tp, ac), name: &(@[char][nn]), nn: int nn, sc: int, help: &(@[char][nh]), nh: int nh
  ): @($AP.parser(tp + nn + nh, ac + 1), $AP.arg($AP.string_val))











fn ap_string_pos {tp:nat}{ac:nat | ac < 64}{nn,nh:pos | tp + nn + nh <= 8192; nn <= 1048576; nh <= 1048576}
  (p: $AP.parser(tp, ac), name: &(@[char][nn]), nn: int nn, help: &(@[char][nh]), nh: int nh
  ): @($AP.parser(tp + nn + nh, ac + 1), $AP.arg($AP.string_val))

























fn put_file_sha256 {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), out: !$B.builder_v >> $B.builder_v): bool






































































































fn put_dev1 (out: !$B.builder_v >> $B.builder_v, dev: bool): void








fn parse_version_parts {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), i: pos_t, be: pos_t, n: int n,
   out: !$B.builder_v >> $B.builder_v): @(pos_t, pos_t)




fn next_dot {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n): pos_t


