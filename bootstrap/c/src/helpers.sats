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









fn span_i32 {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), off: pos_t, max: int n): pos_t

























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






























fun print_arr {l:agz}{n:pos}{fuel:nat}  (buf: !$A.arr(byte, l, n), i: pos_t, len: int, max: int n,
   fuel: int fuel): void









fn is_dot_or_dotdot {l:agz}{n:pos}
  (ent: !$A.arr(byte, l, n), len: int, max: int n): bool















fn dir_name_len (o: $R.option([k:nat | k <= 256] int k)): [k:int | ~1 <= k; k <= 256] int k







fn ent_has_suffix {l:agz}{n:pos}{k:nat | k <= n}{m:pos | m <= 1048576}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n, sfx: &(@[char][m]), m: int m): bool









fn ent_name_eq {l:agz}{n:pos}{k:nat | k <= n}{m:pos | m <= 1048576}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n, s: &(@[char][m]), m: int m): bool









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





fn lit_target_wasm_binary {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool










fun print_borrow {l:agz}{n:pos}{fuel:nat}  (buf: !$A.borrow(byte, l, n), i: pos_t, len: int, max: int n,
   fuel: int fuel): void













fun copy_to_builder {l:agz}{n:pos}{bn:nat}{fuel:nat | bn + fuel <= $B.BUILDER_CAP}  (src: !$A.borrow(byte, l, n), start: pos_t, len: int, max: int n,
   dst: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + fuel] $B.builder(m), fuel: int fuel): void











fn put_char_v(out: !$B.builder_v >> $B.builder_v, v: int): void









fn bput_v {sn:nat}
  (out: !$B.builder_v >> $B.builder_v, s: string sn): void















fn bput_int_v(out: !$B.builder_v >> $B.builder_v, v: int): void





















fn put_int_v(out: !$B.builder_v >> $B.builder_v, v: int): void



fn put_newline_v(out: !$B.builder_v >> $B.builder_v): void



fn copy_to_builder_v {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), start: pos_t, len: int, max: int n,
   dst: !$B.builder_v >> $B.builder_v): void




fun find_basename_start {l:agz}{n:pos}{fuel:nat}  (bv: !$A.borrow(byte, l, n), pos: pos_t, max: int n,
   last: pos_t, fuel: int fuel): pos_t












fun wbw_loop {l:agz}{fuel:nat}  (bw: !$F.buf_writer, bv: !$A.borrow(byte, l, 524288),
   i: pos_t, lim: int, fuel: int fuel): void










fn is_newer {l1:agz}{l2:agz}
  (p1: !$A.borrow(byte, l1, 524288), p2: !$A.borrow(byte, l2, 524288)): bool








fn freshness_check_bv
  (out_b: $B.builder_v, in_b: $B.builder_v): bool













fun token_eq_arr {l:agz}{ls:agz}{fuel:nat}  (buf: !$A.arr(byte, l, 4096), tstart: pos_t, tend: int,
   sarr: !$A.arr(byte, ls, 4096), si: pos_t, fuel: int fuel): bool





















fun arr_range_to_builder {l:agz}{bn:nat}{fuel:nat | bn + fuel <= $B.BUILDER_CAP}  (src: !$A.arr(byte, l, 4096), i: pos_t, lim: int,
   dst: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + fuel] $B.builder(m), fuel: int fuel): void











fn arr_range_to_builder_v {l:agz}
  (src: !$A.arr(byte, l, 4096), i: pos_t, lim: int,
   dst: !$B.builder_v >> $B.builder_v): void




fun str_fill_loop {lb:agz}{sn:nat}{i:nat | i <= sn}{fuel:nat}  (b: !$A.arr(byte, lb, 4096), s: string sn, slen: int sn, i: int i, fuel: int fuel): void










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
   outbuf: !$A.arr(byte, lo, 4096)): @(int, int)





























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






















fn dedupe_lock {l:agz}
  (a: !$A.arr(byte, l, 524288), len: int,
   out: !$B.builder_v >> $B.builder_v): void































































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













fun count_argc_loop {l:agz}{n:pos}{fuel:nat}  (buf: !$A.arr(byte, l, n), pos: pos_t, len: int, max: int n,
   count: int, fuel: int fuel): int














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





































fn dir_next_sorted {lp:agz}{np:pos | np < 1048576}{lq:agz}
  (path: !$A.borrow(byte, lp, np), path_len: int np,
   prev: !$A.borrow(byte, lq, 256), prev_len: int)
  : [lo:agz] @($A.arr(byte, lo, 256), [k:int | ~1 <= k; k <= 256] int k)

















































