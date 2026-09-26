(* helpers -- shared utilities for the bats compiler *)

#include "share/atspre_staload.hats"

#use argparse as AP
#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use list as L
#use path as PA
#use process as P
#use result as R
#use str as S
#use sha256 as SHA

(* ============================================================
   Proven byte reads
   ============================================================ *)

(* A position in a buffer. Indexed, so a read at it is proven in bounds
   by the comparisons in peek, with no cast. *)
#pub typedef pos_t = [p:int] int p

(* Byte at p, or 0 outside [0, n). *)
#pub fn peek {l:agz}{n:pos}{p:int}
  (src: !$A.borrow(byte, l, n), p: int p, n: int n): int

implement peek (src, p, n) =
  if p < 0 then 0
  else if p >= n then 0
  else byte2int0($A.read<byte>(src, p))

(* Byte at p of an array, or 0 outside [0, n). *)
#pub fn peek_arr {l:agz}{n:pos}{p:int}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n): int

implement peek_arr (buf, p, n) =
  if p < 0 then 0
  else if p >= n then 0
  else byte2int0($A.get<byte>(buf, p))

(* Writes byte v at p of an array; does nothing outside [0, n). *)
#pub fn poke_arr {l:agz}{n:pos}{p:int}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n, v: int): void

implement poke_arr (buf, p, n, v) =
  if p < 0 then ()
  else if p >= n then ()
  else $A.set<byte>(buf, p, int2byte0(v))

(* First NUL at or after p, or p itself when p is outside [0, n]. *)
#pub fn find_null_from {l:agz}{n:pos}{p:int}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n): pos_t

implement find_null_from (buf, p, n) =
  if p < 0 then p
  else if p > n then p
  else $S.find_null_at(buf, p, n)

#pub fn find_null_bv_from {l:agz}{n:pos}{p:int}
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n): pos_t

implement find_null_bv_from (bv, p, n) =
  if p < 0 then p
  else if p > n then p
  else $S.find_null_bv_at(bv, p, n)

(* The little-endian 32-bit int at off in a span table, as a proven
   int: two's complement computed without overflow (the top byte counts
   as b3 - 256 when its sign bit is set). *)
#pub fn span_i32 {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), off: pos_t, max: int n): pos_t

implement span_i32 (bv, off, max) = let
  val b0 = $AR.low_byte(peek(bv, off, max))
  val b1 = $AR.low_byte(peek(bv, off + 1, max))
  val b2 = $AR.low_byte(peek(bv, off + 2, max))
  val b3 = $AR.low_byte(peek(bv, off + 3, max))
  val hi = (if b3 < 128 then b3 else b3 - 256): [h:int | ~128 <= h; h < 128] int h
in b0 + b1 * 256 + b2 * 65536 + hi * 16777216 end

(* ============================================================
   Global state using ATS2 refs (replaces C statics)
   ============================================================ *)

val g_verbose = ref<bool>(false)
val g_quiet = ref<bool>(false)
val g_test_mode = ref<bool>(false)
val g_lock_dev = ref<bool>(false)
val g_repo: ref(string) = ref("")
val g_bin: ref(string) = ref("")
val g_to_c = ref<int>(0)
val g_to_c_done = ref<int>(0)
val g_self_path: ref(string) = ref("")
val g_build_err = ref<bool>(false)
val g_exit_code = ref<int>(0)

#pub fn is_verbose(): bool

#pub fn is_quiet(): bool

#pub fn is_test_mode(): bool

#pub fn is_to_c(): bool

#pub fn set_verbose(v: bool): void

#pub fn set_quiet(v: bool): void

#pub fn set_test_mode(v: bool): void

#pub fn set_lock_dev(v: bool): void

#pub fn is_lock_dev(): bool

#pub fn set_repo {sn:nat} (s: string sn): void

#pub fn get_repo(): string

#pub fn set_bin {sn:nat} (s: string sn): void

#pub fn get_bin(): string

#pub fn set_to_c(v: int): void

#pub fn get_to_c(): int

#pub fn set_to_c_done(v: int): void

#pub fn get_to_c_done(): int

#pub fn set_self_path {sn:nat} (s: string sn): void

#pub fn get_self_path(): string

#pub fn set_build_err(): void

#pub fn has_build_err(): bool

#pub fn clear_build_err(): void

(* The status bats exits with when no error was recorded (bats run
   passes on its program's). *)
#pub fn set_exit_code(v: int): void

#pub fn get_exit_code(): int

implement is_verbose() = !g_verbose
implement is_quiet() = !g_quiet
implement is_test_mode() = !g_test_mode
implement is_to_c() = !g_to_c > 0
implement set_verbose(v) = !g_verbose := v
implement set_quiet(v) = !g_quiet := v
implement set_test_mode(v) = !g_test_mode := v
implement set_lock_dev(v) = !g_lock_dev := v
implement is_lock_dev() = !g_lock_dev
implement set_repo(s) = !g_repo := s
implement get_repo() = !g_repo
implement set_bin(s) = !g_bin := s
implement get_bin() = !g_bin
implement set_to_c(v) = !g_to_c := v
implement get_to_c() = !g_to_c
implement set_to_c_done(v) = !g_to_c_done := v
implement get_to_c_done() = !g_to_c_done
implement set_self_path(s) = !g_self_path := s
implement get_self_path() = !g_self_path
implement set_build_err() = !g_build_err := true
implement has_build_err() = !g_build_err
implement clear_build_err() = !g_build_err := false
implement set_exit_code(v) = !g_exit_code := v
implement get_exit_code() = !g_exit_code

(* ============================================================
   String builder helpers
   ============================================================ *)

#pub fun print_arr {l:agz}{n:pos}{fuel:nat}  (buf: !$A.arr(byte, l, n), i: pos_t, len: int, max: int n,
   fuel: int fuel): void

implement print_arr(buf, i, len, max, fuel) =
  if fuel <= 0 then ()
  else if i >= len then ()
  else let
    val b = peek_arr(buf, i, max)
    val () = print_char(int2char0(b))
  in print_arr(buf, i + 1, len, max, fuel - 1) end

#pub fn is_dot_or_dotdot {l:agz}{n:pos}
  (ent: !$A.arr(byte, l, n), len: int, max: int n): bool

implement is_dot_or_dotdot(ent, len, max) =
  if len = 1 then
    $AR.eq_int_int(byte2int0($A.get<byte>(ent, 0)), 46)
  else if len = 2 then
    $AR.eq_int_int(byte2int0($A.get<byte>(ent, 0)), 46) &&
    $AR.eq_int_int(peek_arr(ent, 1, max), 46)
  else false

(* ============================================================
   Filename matchers
   ============================================================ *)

(* Name length from $F.dir_next into a 256-byte buffer, or ~1 at the
   end of the directory. *)
#pub fn dir_name_len (o: $R.option([k:nat | k <= 256] int k)): [k:int | ~1 <= k; k <= 256] int k

implement dir_name_len (o) =
  case+ o of
  | ~$R.some(k) => k
  | ~$R.none() => ~1

(* Whether ent[0, len) ends with the chars sfx. *)
#pub fn ent_has_suffix {l:agz}{n:pos}{k:nat | k <= n}{m:pos | m <= 1048576}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n, sfx: &(@[char][m]), m: int m): bool

implement ent_has_suffix(ent, len, max, sfx, m) = let
  val @(f, b) = $A.freeze<byte>($S.from_char_array(sfx, m))
  val r = $S.has_suffix(ent, len, max, b, m)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
in r end

(* Whether ent[0, len) is exactly the chars s. *)
#pub fn ent_name_eq {l:agz}{n:pos}{k:nat | k <= n}{m:pos | m <= 1048576}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n, s: &(@[char][m]), m: int m): bool

implement ent_name_eq(ent, len, max, s, m) = let
  val @(f, b) = $A.freeze<byte>($S.from_char_array(s, m))
  val r = $S.name_eq(ent, len, max, b, m)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
in r end

(* Whether a byte can be part of an identifier *)
#pub fn is_ident_byte(b: int): bool

implement is_ident_byte(b) =
  (b >= 97 && b <= 122) ||
  (b >= 65 && b <= 90) ||
  (b >= 48 && b <= 57) ||
  $AR.eq_int_int(b, 95)

(* Whether src[pos, pos + m) spells the chars lit. *)
#pub fn lit_at {l:agz}{n:pos}{m:pos | m <= 1048576}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n, lit: &(@[char][m]), m: int m): bool

implement lit_at(src, pos, max, lit, m) =
  if pos < 0 then false
  else if pos + m > max then false
  else let
    val @(f, b) = $A.freeze<byte>($S.from_char_array(lit, m))
    val r = $S.match_at(src, pos, b, m)
    val () = $A.drop<byte>(f, b)
    val () = $A.free<byte>($A.thaw<byte>(f))
  in r end

#pub fn has_bats_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_bats_ext(ent, len, max) = let
  var c = @[char][5]('.', 'b', 'a', 't', 's')
in ent_has_suffix(ent, len, max, c, 5) end

#pub fn has_dats_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_dats_ext(ent, len, max) = let
  var c = @[char][5]('.', 'd', 'a', 't', 's')
in ent_has_suffix(ent, len, max, c, 5) end

#pub fn has_dats_c_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_dats_c_ext(ent, len, max) = let
  var c = @[char][7]('_', 'd', 'a', 't', 's', '.', 'c')
in ent_has_suffix(ent, len, max, c, 7) end

#pub fn has_dats_o_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_dats_o_ext(ent, len, max) = let
  var c = @[char][7]('_', 'd', 'a', 't', 's', '.', 'o')
in ent_has_suffix(ent, len, max, c, 7) end

#pub fn has_sha256_ext {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_sha256_ext(ent, len, max) = let
  var c = @[char][7]('.', 's', 'h', 'a', '2', '5', '6')
in ent_has_suffix(ent, len, max, c, 7) end

#pub fn has_lib_dats_c_sfx {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_lib_dats_c_sfx(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'c')
in ent_has_suffix(ent, len, max, c, 10) end

#pub fn has_lib_dats_o_sfx {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement has_lib_dats_o_sfx(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'o')
in ent_has_suffix(ent, len, max, c, 10) end

#pub fn is_lib_bats {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement is_lib_bats(ent, len, max) = let
  var c = @[char][8]('l', 'i', 'b', '.', 'b', 'a', 't', 's')
in ent_name_eq(ent, len, max, c, 8) end

#pub fn is_lib_dats {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement is_lib_dats(ent, len, max) = let
  var c = @[char][8]('l', 'i', 'b', '.', 'd', 'a', 't', 's')
in ent_name_eq(ent, len, max, c, 8) end

#pub fn is_lib_dats_c {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement is_lib_dats_c(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'c')
in ent_name_eq(ent, len, max, c, 10) end

#pub fn is_lib_dats_o {l:agz}{n:pos}{k:nat | k <= n}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n): bool

implement is_lib_dats_o(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'o')
in ent_name_eq(ent, len, max, c, 10) end

(* Keyword and literal matchers: whether src[pos, pos + len) spells it. *)

#pub fn lit_as {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_as(src, pos, max) = let
  var c = @[char][2]('a', 's')
in lit_at(src, pos, max, c, 2) end

#pub fn lit_begin {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_begin(src, pos, max) = let
  var c = @[char][5]('b', 'e', 'g', 'i', 'n')
in lit_at(src, pos, max, c, 5) end

#pub fn lit_binary {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_binary(src, pos, max) = let
  var c = @[char][6]('b', 'i', 'n', 'a', 'r', 'y')
in lit_at(src, pos, max, c, 6) end

#pub fn lit_dollar_UNITTEST {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_dollar_UNITTEST(src, pos, max) = let
  var c = @[char][9]('$', 'U', 'N', 'I', 'T', 'T', 'E', 'S', 'T')
in lit_at(src, pos, max, c, 9) end

#pub fn lit_dollar_UNSAFE {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_dollar_UNSAFE(src, pos, max) = let
  var c = @[char][7]('$', 'U', 'N', 'S', 'A', 'F', 'E')
in lit_at(src, pos, max, c, 7) end

#pub fn lit_dot_slash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_dot_slash(src, pos, max) = let
  var c = @[char][2]('.', '/')
in lit_at(src, pos, max, c, 2) end

#pub fn lit_end {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_end(src, pos, max) = let
  var c = @[char][3]('e', 'n', 'd')
in lit_at(src, pos, max, c, 3) end

#pub fn lit_exthash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_exthash(src, pos, max) = let
  var c = @[char][4]('e', 'x', 't', '#')
in lit_at(src, pos, max, c, 4) end

#pub fn lit_fun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_fun(src, pos, max) = let
  var c = @[char][3]('f', 'u', 'n')
in lit_at(src, pos, max, c, 3) end

#pub fn lit_hash_pub {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_hash_pub(src, pos, max) = let
  var c = @[char][4]('#', 'p', 'u', 'b')
in lit_at(src, pos, max, c, 4) end

#pub fn lit_hash_target {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_hash_target(src, pos, max) = let
  var c = @[char][7]('#', 't', 'a', 'r', 'g', 'e', 't')
in lit_at(src, pos, max, c, 7) end

#pub fn lit_hash_use {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_hash_use(src, pos, max) = let
  var c = @[char][4]('#', 'u', 's', 'e')
in lit_at(src, pos, max, c, 4) end

#pub fn lit_let {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_let(src, pos, max) = let
  var c = @[char][3]('l', 'e', 't')
in lit_at(src, pos, max, c, 3) end

#pub fn lit_local {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_local(src, pos, max) = let
  var c = @[char][5]('l', 'o', 'c', 'a', 'l')
in lit_at(src, pos, max, c, 5) end

#pub fn lit_machash {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_machash(src, pos, max) = let
  var c = @[char][4]('m', 'a', 'c', '#')
in lit_at(src, pos, max, c, 4) end

#pub fn lit_no_mangle {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_no_mangle(src, pos, max) = let
  var c = @[char][9]('n', 'o', '_', 'm', 'a', 'n', 'g', 'l', 'e')
in lit_at(src, pos, max, c, 9) end

#pub fn lit_prfn {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_prfn(src, pos, max) = let
  var c = @[char][4]('p', 'r', 'f', 'n')
in lit_at(src, pos, max, c, 4) end

#pub fn lit_prfun {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_prfun(src, pos, max) = let
  var c = @[char][5]('p', 'r', 'f', 'u', 'n')
in lit_at(src, pos, max, c, 5) end

#pub fn lit_primplement {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_primplement(src, pos, max) = let
  var c = @[char][11]('p', 'r', 'i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
in lit_at(src, pos, max, c, 11) end

#pub fn lit_slash_srcslash_libdot_dats {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_slash_srcslash_libdot_dats(src, pos, max) = let
  var c = @[char][13]('/', 's', 'r', 'c', '/', 'l', 'i', 'b', '.', 'd', 'a', 't', 's')
in lit_at(src, pos, max, c, 13) end

#pub fn lit_staload_dq {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_staload_dq(src, pos, max) = let
  var c = @[char][9]('s', 't', 'a', 'l', 'o', 'a', 'd', ' ', '\042')
in lit_at(src, pos, max, c, 9) end

#pub fn lit_target_wasm_binary {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_target_wasm_binary(src, pos, max) = let
  var c = @[char][18]('t', 'a', 'r', 'g', 'e', 't', ' ', 'w', 'a', 's', 'm', ' ', 'b', 'i', 'n', 'a', 'r', 'y')
in lit_at(src, pos, max, c, 18) end

#pub fn lit_while {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: pos_t, max: int n): bool

implement lit_while(src, pos, max) = let
  var c = @[char][5]('w', 'h', 'i', 'l', 'e')
in lit_at(src, pos, max, c, 5) end

(* ============================================================
   Byte-level helpers
   ============================================================ *)


#pub fun print_borrow {l:agz}{n:pos}{fuel:nat}  (buf: !$A.borrow(byte, l, n), i: pos_t, len: int, max: int n,
   fuel: int fuel): void

implement print_borrow(buf, i, len, max, fuel) =
  if fuel <= 0 then ()
  else if i >= len then ()
  else let
    val b = peek(buf, i, max)
    val () = print_char(int2char0(b))
  in print_borrow(buf, i + 1, len, max, fuel - 1) end

(* ============================================================
   Build pipeline helpers
   ============================================================ *)

#pub fun copy_to_builder {l:agz}{n:pos}{bn:nat}{fuel:nat | bn + fuel <= $B.BUILDER_CAP}  (src: !$A.borrow(byte, l, n), start: pos_t, len: int, max: int n,
   dst: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + fuel] $B.builder(m), fuel: int fuel): void

implement copy_to_builder(src, start, len, max, dst, fuel) =
  if fuel <= 0 then ()
  else if start >= len then ()
  else let
    val b = peek(src, start, max)
    val () = $B.put_char(dst, b)
  in copy_to_builder(src, start + 1, len, max, dst, fuel - 1) end

(* Builder_v wrappers: compute fuel from remaining capacity *)

#pub fn put_char_v(out: !$B.builder_v >> $B.builder_v, v: int): void

implement put_char_v(out, v) = let
  fun _put {bn:nat}{fuel:nat | bn + fuel <= $B.BUILDER_CAP} .<fuel>.
    (out: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + fuel] $B.builder(m),
     v: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else $B.put_char(out, v)
in _put(out, v, 524288 - $B.length(out)) end

#pub fn bput_v {sn:nat}
  (out: !$B.builder_v >> $B.builder_v, s: string sn): void

implement bput_v(out, s) = let
  fun loop {bn:nat}{fuel:nat | bn + fuel <= $B.BUILDER_CAP}{sl:nat}{i:nat | i <= sl} .<fuel>.
    (out: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + fuel] $B.builder(m),
     s: string sl, slen: int sl, i: int i, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if i >= slen then ()
    else let
      val c = char2int0(string_get_at(s, i))
      val () = $B.put_char(out, c)
    in loop(out, s, slen, i + 1, fuel - 1) end
  val slen_sz = string1_length(s)
  val slen = g1u2i(slen_sz)
in loop(out, s, slen, 0, 524288 - $B.length(out)) end

#pub fn bput_int_v(out: !$B.builder_v >> $B.builder_v, v: int): void

implement bput_int_v(out, v) = let
  fun emit_digits {fuel:nat} .<fuel>.
    (out: !$B.builder_v >> $B.builder_v, d: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if d < 10 then put_char_v(out, d + 48)
    else let
      val () = emit_digits(out, d / 10, fuel - 1)
    in put_char_v(out, (d mod 10) + 48) end
in
  if v < 0 then let
    val () = put_char_v(out, 45)
    val abs_v = ~v
  in
    if abs_v < 0 then put_char_v(out, 48)
    else emit_digits(out, abs_v, 20)
  end
  else if v = 0 then put_char_v(out, 48)
  else emit_digits(out, v, 20)
end

#pub fn put_int_v(out: !$B.builder_v >> $B.builder_v, v: int): void

implement put_int_v(out, v) = bput_int_v(out, v)

#pub fn put_newline_v(out: !$B.builder_v >> $B.builder_v): void

implement put_newline_v(out) = put_char_v(out, 10)

#pub fn copy_to_builder_v {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), start: pos_t, len: int, max: int n,
   dst: !$B.builder_v >> $B.builder_v): void

implement copy_to_builder_v(src, start, len, max, dst) =
  copy_to_builder(src, start, len, max, dst, 524288 - $B.length(dst))

#pub fun find_basename_start {l:agz}{n:pos}{fuel:nat}  (bv: !$A.borrow(byte, l, n), pos: pos_t, max: int n,
   last: pos_t, fuel: int fuel): pos_t

implement find_basename_start(bv, pos, max, last, fuel) =
  if fuel <= 0 then last + 1
  else let
    val b = peek(bv, pos, max)
  in
    if $AR.eq_int_int(b, 0) then last + 1
    else if $AR.eq_int_int(b, 47) then
      find_basename_start(bv, pos + 1, max, pos, fuel - 1)
    else find_basename_start(bv, pos + 1, max, last, fuel - 1)
  end

#pub fun wbw_loop {l:agz}{fuel:nat}  (bw: !$F.buf_writer, bv: !$A.borrow(byte, l, 524288),
   i: pos_t, lim: int, fuel: int fuel): void

implement wbw_loop(bw, bv, i, lim, fuel) =
  if fuel <= 0 then ()
  else if i >= lim then ()
  else let
    val b = peek(bv, i, 524288)
    val wr = $F.buf_write_byte(bw, b)
    val () = $R.discard<int><int>(wr)
  in wbw_loop(bw, bv, i + 1, lim, fuel - 1) end

#pub fn is_newer {l1:agz}{l2:agz}
  (p1: !$A.borrow(byte, l1, 524288), p2: !$A.borrow(byte, l2, 524288)): bool

implement is_newer(p1, p2) = let
  val mt1 = (case+ $F.file_mtime(p1, 524288) of
    | ~$R.ok(t) => t | ~$R.err(_) => ~1): int
  val mt2 = (case+ $F.file_mtime(p2, 524288) of
    | ~$R.ok(t) => t | ~$R.err(_) => ~1): int
in $AR.gt_int_int(mt1, 0) && $AR.gt_int_int(mt1, mt2) end

#pub fn freshness_check_bv
  (out_b: $B.builder_v, in_b: $B.builder_v): bool

implement freshness_check_bv(out_b, in_b) = let
  val @(oa, _) = $B.to_arr(out_b)
  val @(ia, _) = $B.to_arr(in_b)
  val @(fz_o, bv_o) = $A.freeze<byte>(oa)
  val @(fz_i, bv_i) = $A.freeze<byte>(ia)
  val result = is_newer(bv_o, bv_i)
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val () = $A.drop<byte>(fz_i, bv_i)
  val () = $A.free<byte>($A.thaw<byte>(fz_i))
in result end

#pub fun token_eq_arr {l:agz}{ls:agz}{fuel:nat}  (buf: !$A.arr(byte, l, 4096), tstart: pos_t, tend: int,
   sarr: !$A.arr(byte, ls, 4096), si: pos_t, fuel: int fuel): bool

implement token_eq_arr(buf, tstart, tend, sarr, si, fuel) =
  if fuel <= 0 then tstart >= tend
  else if tstart >= tend then
    if si < 0 then true
    else if si >= 4096 then true
    else $AR.eq_int_int(peek_arr(sarr, si, 4096), 0)
  else
    if tstart < 0 then false
    else if tstart >= 4096 then false
    else if si < 0 then false
    else if si >= 4096 then false
    else let
      val tb = peek_arr(buf, tstart, 4096)
      val sb = peek_arr(sarr, si, 4096)
    in
      if $AR.neq_int_int(tb, sb) then false
      else if $AR.eq_int_int(sb, 0) then false
      else token_eq_arr(buf, tstart + 1, tend, sarr, si + 1, fuel - 1)
    end

#pub fun arr_range_to_builder {l:agz}{bn:nat}{fuel:nat | bn + fuel <= $B.BUILDER_CAP}  (src: !$A.arr(byte, l, 4096), i: pos_t, lim: int,
   dst: !$B.builder(bn) >> [m:nat | bn <= m; m <= bn + fuel] $B.builder(m), fuel: int fuel): void

implement arr_range_to_builder(src, i, lim, dst, fuel) =
  if fuel <= 0 then ()
  else if i >= lim then ()
  else if i < 0 then ()
  else if i >= 4096 then ()
  else let
    val b = peek_arr(src, i, 4096)
    val () = $B.put_char(dst, b)
  in arr_range_to_builder(src, i + 1, lim, dst, fuel - 1) end

#pub fn arr_range_to_builder_v {l:agz}
  (src: !$A.arr(byte, l, 4096), i: pos_t, lim: int,
   dst: !$B.builder_v >> $B.builder_v): void

implement arr_range_to_builder_v(src, i, lim, dst) =
  arr_range_to_builder(src, i, lim, dst, 524288 - $B.length(dst))

#pub fun str_fill_loop {lb:agz}{sn:nat}{i:nat | i <= sn}{fuel:nat}  (b: !$A.arr(byte, lb, 4096), s: string sn, slen: int sn, i: int i, fuel: int fuel): void

implement str_fill_loop(b, s, slen, i, fuel) =
  if fuel <= 0 then ()
  else if i >= slen then ()
  else if i >= 4096 then ()
  else let
    val c = char2int0(string_get_at(s, i))
    val () = $A.set<byte>(b, i, int2byte0(c))
  in str_fill_loop(b, s, slen, i + 1, fuel - 1) end

#pub fn str_to_arr4096 {sn:nat} (s: string sn): [ls:agz] $A.arr(byte, ls, 4096)

implement str_to_arr4096(s) = let
  val b = $A.alloc<byte>(4096)
  val slen_sz = string1_length(s)
  val slen = g1u2i(slen_sz)
  val () = str_fill_loop(b, s, slen, 0, 4098)
in
  (if slen < 4096 then $A.set<byte>(b, slen, int2byte0(0))
  else ()); b
end

(* ============================================================
   Process execution
   ============================================================ *)

(* Convert a filled builder into a process arg_entry *)
#pub fn mk_arg(b: $B.builder_v): $P.arg_entry

implement mk_arg(b) = let
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fun _rev_arg_list {n:nat} .<n>.
  (xs: $L.list_vt($P.arg_entry, n), acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  case+ xs of
  | ~$L.list_vt_nil() => acc
  | ~$L.list_vt_cons(x, tl) => _rev_arg_list(tl, $L.list_vt_cons(x, acc))

(* xs reversed onto acc *)
#pub fn rev_arg_list
  (xs: $L.listv($P.arg_entry), acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry)

implement rev_arg_list (xs, acc) = _rev_arg_list(xs, acc)

(* Split a null-separated builder into a list of arg_entries *)
#pub fn split_null_to_list(b: $B.builder_v): $L.listv($P.arg_entry)

implement split_null_to_list(b) = let
  val @(arr, total_len) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  fun find_nul {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288), pos: pos_t, total: int,
     fuel: int fuel): pos_t =
    if fuel <= 0 then pos
    else if pos >= total then pos
    else if peek(bv, pos, 524288) = 0 then pos
    else find_nul(bv, pos + 1, total, fuel - 1)
  fun copy_word {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288),
     dst: !$B.builder_v >> $B.builder_v,
     soff: pos_t, di: pos_t, seg_len: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if di >= seg_len then ()
    else let
      val c = peek(bv, soff + di, 524288)
      val () = put_char_v(dst, c)
    in copy_word(bv, dst, soff, di + 1, seg_len, fuel - 1) end
  fun loop {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288), start: pos_t, total: int,
     acc: $L.listv($P.arg_entry), fuel: int fuel): $L.listv($P.arg_entry) =
    if fuel <= 0 then acc
    else if start >= total then acc
    else let
      val np = find_nul(bv, start, total, 524288)
      val seg_len = np - start
    in
      if seg_len <= 0 then loop(bv, np + 1, total, acc, fuel - 1)
      else let
        var wb = $B.create()
        val () = copy_word(bv, wb, start, 0, seg_len, 524288)
      in loop(bv, np + 1, total,
           $L.list_vt_cons(mk_arg(wb), acc), fuel - 1) end
    end
  val result = loop(bv, 0, total_len, $L.list_vt_nil(), 524288)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in rev_arg_list(result, $L.list_vt_nil()) end

(* Split a space-separated builder into a list of arg_entries *)
#pub fn split_spaces_to_list(b: $B.builder_v): $L.listv($P.arg_entry)

implement split_spaces_to_list(b) = let
  val @(arr, total_len) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  fun find_space {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288), pos: pos_t, total: int,
     fuel: int fuel): pos_t =
    if fuel <= 0 then pos
    else if pos >= total then pos
    else if peek(bv, pos, 524288) = 32 then pos
    else find_space(bv, pos + 1, total, fuel - 1)
  fun skip_spaces {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288), pos: pos_t, total: int,
     fuel: int fuel): pos_t =
    if fuel <= 0 then pos
    else if pos >= total then pos
    else if peek(bv, pos, 524288) <> 32 then pos
    else skip_spaces(bv, pos + 1, total, fuel - 1)
  fun copy_word {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288),
     dst: !$B.builder_v >> $B.builder_v,
     soff: pos_t, di: pos_t, seg_len: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if di >= seg_len then ()
    else let
      val c = peek(bv, soff + di, 524288)
      val () = put_char_v(dst, c)
    in copy_word(bv, dst, soff, di + 1, seg_len, fuel - 1) end
  fun loop {lb:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, lb, 524288), start: pos_t, total: int,
     acc: $L.listv($P.arg_entry), fuel: int fuel): $L.listv($P.arg_entry) =
    if fuel <= 0 then acc
    else if start >= total then acc
    else let
      val pos = skip_spaces(bv, start, total, 524288)
    in
      if pos >= total then acc
      else let
        val word_end = find_space(bv, pos, total, 524288)
        val word_len = word_end - pos
        var wb = $B.create()
        val () = copy_word(bv, wb, pos, 0, word_len, 524288)
      in loop(bv, word_end, total,
           $L.list_vt_cons(mk_arg(wb), acc), fuel - 1) end
    end
  val result = loop(bv, 0, total_len, $L.list_vt_nil(), 524288)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in rev_arg_list(result, $L.list_vt_nil()) end

(* Run mkdir -p <path>. path_b is consumed. Returns exit code. *)
#pub fn run_mkdir
  (path_b: $B.builder_v): int

implement run_mkdir(path_b) = let
  val exec = str_to_path_arr("mkdir")
  val @(fz_exec, bv_exec) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "mkdir")
  val a1 = mk_arg(b1)
  var b2 = $B.create()
  val () = bput_v(b2, "-p")
  val a2 = mk_arg(b2)
  val a3 = mk_arg(path_b)
  val argv = $L.list_vt_cons(a1, $L.list_vt_cons(a2,
    $L.list_vt_cons(a3, $L.list_vt_nil())))
  val rc = run_cmd(bv_exec, argv)
  val () = $A.drop<byte>(fz_exec, bv_exec)
  val () = $A.free<byte>($A.thaw<byte>(fz_exec))
in rc end

(* Runs exec with argv, sharing this process's stdin, stdout, stderr and
   environment, as the Rust bats's Command::status did. The exit status
   (1 if the program did not exit normally), or ~1 if it could not be
   started. *)
#pub fn run_program {le:agz}
  (exec_bv: !$A.borrow(byte, le, 524288), argv: $L.listv($P.arg_entry)): int

implement run_program (exec_bv, argv) =
  case+ $P.spawn_inherit_env(exec_bv, argv, $P.inherit(), $P.inherit(), $P.inherit()) of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val () = $P.pipe_end_close(sout_p)
      val () = $P.pipe_end_close(serr_p)
      val ec = (case+ $P.child_wait(child) of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in if ec >= 0 then ec else 1 end
  | ~$R.err(_) => ~1

#pub fn run_cmd {le:agz}
  (exec_bv: !$A.borrow(byte, le, 524288),
   argv: $L.listv($P.arg_entry)): int

implement run_cmd (exec_bv, argv) = let
  val sr = $P.spawn_inherit_env(exec_bv, argv,
    $P.dev_null(), $P.dev_null(), $P.pipe_new())
in
  case+ sr of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val () = $P.pipe_end_close(sout_p)
      val+ ~$P.pipe_fd(err_fd) = serr_p
      val eb = $A.alloc<byte>(65536)
      val err_r = $F.file_read(err_fd, eb, 65536)
      val elen = (case+ err_r of
        | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val ecr = $F.file_close(err_fd)
      val () = $R.discard<int><int>(ecr)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in
      if ec <> 0 then let
        val @(fz_eb2, bv_eb2) = $A.freeze<byte>(eb)
        val () = print_borrow(bv_eb2, 0, elen, 65536, 65536)
        val () = $A.drop<byte>(fz_eb2, bv_eb2)
        val () = $A.free<byte>($A.thaw<byte>(fz_eb2))
      in ec end
      else let
        val () = $A.free<byte>(eb)
      in 0 end
    end
  | ~$R.err(_) => ~1
end

(* Parse a decimal integer from a byte buffer *)
#pub fn parse_decimal {l:agz}{n:pos}
  (buf: !$A.arr(byte, l, n), len: int, max: int n): int

implement parse_decimal (buf, len, max) = let
  fun loop {l:agz}{n:pos}{fuel:nat} .<fuel>.
    (buf: !$A.arr(byte, l, n), max: int n, pos: pos_t, len: int,
     acc: int, fuel: int fuel): int =
    if fuel <= 0 then acc
    else if pos >= len then acc
    else let
      val b = peek_arr(buf, pos, max)
    in
      if b >= 48 then
        if b <= 57 then loop(buf, max, pos + 1, len, acc * 10 + (b - 48), fuel - 1)
        else acc
      else acc
    end
in loop(buf, max, 0, len, 0, 65536) end

(* Convert unix timestamp to calendar version: @(year, month, day, secs_of_day) *)
(* Hinnant's civil_from_days algorithm *)
#pub fn timestamp_to_calver(ts: int): @(int, int, int, int)

implement timestamp_to_calver(ts) = let
  val day_secs = 86400
  val days = ts / day_secs
  val secs_of_day = ts - days * day_secs
  val z = days + 719468
  val zz = (if z >= 0 then z else z - 146096): int
  val era = $AR.div_int_int(zz, 146097)
  val doe = z - $AR.mul_int_int(era, 146097)
  val yoe = $AR.div_int_int(doe - $AR.div_int_int(doe, 1460) + $AR.div_int_int(doe, 36524) - $AR.div_int_int(doe, 146096), 365)
  val y = yoe + $AR.mul_int_int(era, 400)
  val doy = doe - ($AR.mul_int_int(365, yoe) + $AR.div_int_int(yoe, 4) - $AR.div_int_int(yoe, 100))
  val mp = $AR.div_int_int($AR.mul_int_int(5, doy) + 2, 153)
  val d = doy - $AR.div_int_int($AR.mul_int_int(153, mp) + 2, 5) + 1
  val m = (if mp < 10 then $AR.add_int_int(mp, 3) else $AR.sub_int_int(mp, 9)): int
  val y2 = (if m <= 2 then $AR.add_int_int(y, 1) else y): int
in @(y2, m, d, secs_of_day) end

(* Run a command and capture stdout into outbuf. Returns @(exit_code,
   stdout_len); the exit code is -errno when the command could not be
   run (Rust: Command::output's Err). *)
#pub fn run_cmd_capture {le:agz}{lo:agz}
  (exec_bv: !$A.borrow(byte, le, 524288),
   argv: $L.listv($P.arg_entry),
   outbuf: !$A.arr(byte, lo, 4096)): @(int, [k:nat | k <= 4096] int k)

implement run_cmd_capture (exec_bv, argv, outbuf) = let
  val sr = $P.spawn_inherit_env(exec_bv, argv,
    $P.dev_null(), $P.pipe_new(), $P.pipe_new())
in
  case+ sr of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val+ ~$P.pipe_fd(out_fd) = sout_p
      val out_r = $F.file_read(out_fd, outbuf, 4096)
      val olen = (case+ out_r of
        | ~$R.ok(n) => n | ~$R.err(_) => 0): [k:nat | k <= 4096] int k
      val ocr = $F.file_close(out_fd)
      val () = $R.discard<int><int>(ocr)
      val+ ~$P.pipe_fd(err_fd) = serr_p
      val eb = $A.alloc<byte>(4096)
      val err_r = $F.file_read(err_fd, eb, 4096)
      val () = (case+ err_r of | ~$R.ok(_) => () | ~$R.err(_) => ())
      val ecr = $F.file_close(err_fd)
      val () = $R.discard<int><int>(ecr)
      val () = $A.free<byte>(eb)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in @(ec, olen) end
  | ~$R.err(e) => @(0 - e, 0)
end

#pub fn run_patsopt {lph:agz}{lo:agz}{li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int): int

implement run_patsopt(ph, phlen, out_bv, out_len, in_bv, in_len) = let
  var exec_b = $B.create()
  val () = copy_to_builder(ph, 0, phlen, 512, exec_b, 512)
  val () = $B.bput(exec_b, "/bin/patsopt")
  val () = put_char_v(exec_b, 0)
  val @(exec_a, _) = $B.to_arr(exec_b)
  val @(fz_exec, bv_exec) = $A.freeze<byte>(exec_a)
  var b1 = $B.create()
  val () = bput_v(b1, "patsopt")
  var b2 = $B.create()
  val () = bput_v(b2, "-IATS")
  var b3 = $B.create()
  val () = bput_v(b3, "build")
  var b4 = $B.create()
  val () = bput_v(b4, "-IATS")
  var b5 = $B.create()
  val () = bput_v(b5, "build/src")
  var b6 = $B.create()
  val () = bput_v(b6, "-IATS")
  var b7 = $B.create()
  val () = bput_v(b7, "build/bats_modules")
  var b8 = $B.create()
  val () = bput_v(b8, "-o")
  var b9 = $B.create()
  val out_clen = out_len - 1
  val () = copy_to_builder_v(out_bv, 0, out_clen, 524288, b9)
  var b10 = $B.create()
  val () = bput_v(b10, "-d")
  var b11 = $B.create()
  val in_clen = in_len - 1
  val () = copy_to_builder_v(in_bv, 0, in_clen, 524288, b11)
  val argv = $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3),
    $L.list_vt_cons(mk_arg(b4), $L.list_vt_cons(mk_arg(b5),
    $L.list_vt_cons(mk_arg(b6), $L.list_vt_cons(mk_arg(b7),
    $L.list_vt_cons(mk_arg(b8), $L.list_vt_cons(mk_arg(b9),
    $L.list_vt_cons(mk_arg(b10), $L.list_vt_cons(mk_arg(b11),
    $L.list_vt_nil())))))))))))
  var envp_b = $B.create()
  val () = bput_v(envp_b, "PATSHOME=")
  val () = copy_to_builder_v(ph, 0, phlen, 512, envp_b)
  val envp = $L.list_vt_cons(mk_arg(envp_b), $L.list_vt_nil())
  val _verbose = if is_verbose() then 1 else 0
  val () = (if $AR.gt_int_int(_verbose, 0) then let
    val () = print! ("  + patsopt -o ")
    val () = print_borrow(out_bv, 0, out_len, 524288,
      4096)
    val () = print! (" -d ")
    val () = print_borrow(in_bv, 0, in_len, 524288,
      4096)
  in print_newline() end else ())
  val sr = $P.spawn_inherit_env_with(bv_exec, argv, envp,
    $P.dev_null(), $P.dev_null(), $P.pipe_new())
  val () = $A.drop<byte>(fz_exec, bv_exec)
  val () = $A.free<byte>($A.thaw<byte>(fz_exec))
in
  case+ sr of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val () = $P.pipe_end_close(sout_p)
      val+ ~$P.pipe_fd(err_fd) = serr_p
      (* Read stderr BEFORE waiting — prevents deadlock if child
         writes more than PIPE_BUF (64KB) to stderr *)
      val eb = $A.alloc<byte>(65536)
      val err_r = $F.file_read(err_fd, eb, 65536)
      val elen = (case+ err_r of
        | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val ecr = $F.file_close(err_fd)
      val () = $R.discard<int><int>(ecr)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in
      if ec <> 0 then let
        val @(fz_eb2, bv_eb2) = $A.freeze<byte>(eb)
        val () = print_borrow(bv_eb2, 0, elen, 65536, 65536)
        val () = $A.drop<byte>(fz_eb2, bv_eb2)
        val () = $A.free<byte>($A.thaw<byte>(fz_eb2))
      in ec end
      else let
        val () = $A.free<byte>(eb)
      in 0 end
    end
  | ~$R.err(_) => ~1
end

#pub fn run_cc {lph:agz}{lo:agz}{li:agz}
  (ph: !$A.borrow(byte, lph, 512), phlen: int,
   out_bv: !$A.borrow(byte, lo, 524288), out_len: int,
   in_bv: !$A.borrow(byte, li, 524288), in_len: int,
   rel: int): int

implement run_cc(ph, phlen, out_bv, out_len, in_bv, in_len, rel) = let
  val exec = str_to_path_arr("clang")
  val @(fz_exec, bv_exec) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "clang")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, "-o")
  var b4 = $B.create()
  val cc_out_clen = out_len - 1
  val () = copy_to_builder_v(out_bv, 0, cc_out_clen, 524288, b4)
  var b5 = $B.create()
  val cc_in_clen = in_len - 1
  val () = copy_to_builder_v(in_bv, 0, cc_in_clen, 524288, b5)
  val opt_args: $L.listv($P.arg_entry) = (if rel > 0 then let
      var bo = $B.create()
      val () = bput_v(bo, "-O2")
    in $L.list_vt_cons(mk_arg(bo), $L.list_vt_nil()) end
    else let
      var bg = $B.create()
      val () = bput_v(bg, "-g")
      var bo0 = $B.create()
      val () = bput_v(bo0, "-O0")
    in $L.list_vt_cons(mk_arg(bg),
         $L.list_vt_cons(mk_arg(bo0), $L.list_vt_nil())) end): $L.listv($P.arg_entry)
  var b6 = $B.create()
  val () = bput_v(b6, "-I")
  val () = copy_to_builder_v(ph, 0, phlen, 512, b6)
  var b7 = $B.create()
  val () = bput_v(b7, "-I")
  val () = copy_to_builder_v(ph, 0, phlen, 512, b7)
  val () = bput_v(b7, "/ccomp/runtime")
  (* Build argv: clang -c -o <out> <in> [opt_flags] -I<ph> -I<ph>/ccomp/runtime *)
  val tail = $L.list_vt_cons(mk_arg(b6),
    $L.list_vt_cons(mk_arg(b7), $L.list_vt_nil()))
  fun append_vt {m:nat} .<m>.
    (xs: $L.list_vt($P.arg_entry, m),
     ys: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
    case+ xs of
    | ~$L.list_vt_nil() => ys
    | ~$L.list_vt_cons(x, tl) => $L.list_vt_cons(x, append_vt(tl, ys))
  val argv = $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(b5), append_vt(opt_args, tail))))))
  val _verbose = if is_verbose() then 1 else 0
  val () = (if $AR.gt_int_int(_verbose, 0) then let
    val () = print! ("  + cc -c -o ")
    val () = print_borrow(out_bv, 0, out_len, 524288,
      4096)
    val () = print! (" ")
    val () = print_borrow(in_bv, 0, in_len, 524288,
      4096)
  in print_newline() end else ())
  val sr = $P.spawn_inherit_env(bv_exec, argv,
    $P.dev_null(), $P.dev_null(), $P.pipe_new())
  val () = $A.drop<byte>(fz_exec, bv_exec)
  val () = $A.free<byte>($A.thaw<byte>(fz_exec))
in
  case+ sr of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val () = $P.pipe_end_close(sout_p)
      val+ ~$P.pipe_fd(err_fd) = serr_p
      (* Read stderr BEFORE waiting — prevents deadlock if child
         writes more than PIPE_BUF (64KB) to stderr *)
      val eb = $A.alloc<byte>(65536)
      val err_r = $F.file_read(err_fd, eb, 65536)
      val elen = (case+ err_r of
        | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val ecr = $F.file_close(err_fd)
      val () = $R.discard<int><int>(ecr)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in
      if ec <> 0 then let
        val @(fz_eb2, bv_eb2) = $A.freeze<byte>(eb)
        val () = print_borrow(bv_eb2, 0, elen, 65536, 65536)
        val () = $A.drop<byte>(fz_eb2, bv_eb2)
        val () = $A.free<byte>($A.thaw<byte>(fz_eb2))
      in ec end
      else let
        val () = $A.free<byte>(eb)
      in 0 end
    end
  | ~$R.err(_) => ~1
end

(* ============================================================
   File I/O
   ============================================================ *)

#pub fn write_file_from_builder {lp:agz}{np:pos | np < 1048576}
  (path_bv: !$A.borrow(byte, lp, np), path_len: int np,
   content_b: $B.builder_v): int

implement write_file_from_builder(path_bv, path_len, content_b) = let
  val @(content_arr, content_len) = $B.to_arr(content_b)
  val fd_r = $F.file_open(path_bv, path_len, 577, 420)
in case+ fd_r of
  | ~$R.ok(fd) => let
      val bw = $F.buf_writer_create(fd)
      val @(fz_c, bv_c) = $A.freeze<byte>(content_arr)
      val () = wbw_loop(bw, bv_c, 0, content_len, 524289)
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = $A.free<byte>($A.thaw<byte>(fz_c))
      val cr = $F.buf_writer_close(bw)
      val () = $R.discard<int><int>(cr)
    in 0 end
  | ~$R.err(_) => let val () = $A.free<byte>(content_arr) in ~1 end
end

#pub fn str_to_path_arr {sn:nat | sn < $B.BUILDER_CAP} (s: string sn): [l:agz] $A.arr(byte, l, 524288)

implement str_to_path_arr(s) = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val () = $B.put_char(b, 0)
  val @(arr, _) = $B.to_arr(b)
in arr end

(* ============================================================
   String constant builders
   ============================================================ *)

#pub fn make_bats_toml {l:agz}{n:pos | n >= 9}
  (buf: !$A.arr(byte, l, n)): void

implement make_bats_toml(buf) =
  let
    val () = $A.write_byte(buf, 0, 98)
    val () = $A.write_byte(buf, 1, 97)
    val () = $A.write_byte(buf, 2, 116)
    val () = $A.write_byte(buf, 3, 115)
    val () = $A.write_byte(buf, 4, 46)
    val () = $A.write_byte(buf, 5, 116)
    val () = $A.write_byte(buf, 6, 111)
    val () = $A.write_byte(buf, 7, 109)
    val () = $A.write_byte(buf, 8, 108)
  in end

#pub fn make_src_bin {l:agz}{n:pos | n >= 7}
  (buf: !$A.arr(byte, l, n)): void

implement make_src_bin(buf) =
  let
    val () = $A.write_byte(buf, 0, 115)
    val () = $A.write_byte(buf, 1, 114)
    val () = $A.write_byte(buf, 2, 99)
    val () = $A.write_byte(buf, 3, 47)
    val () = $A.write_byte(buf, 4, 98)
    val () = $A.write_byte(buf, 5, 105)
    val () = $A.write_byte(buf, 6, 110)
  in end

#pub fn make_package {l:agz}{n:pos | n >= 7}
  (buf: !$A.arr(byte, l, n)): void

implement make_package(buf) =
  let
    val () = $A.write_byte(buf, 0, 112)
    val () = $A.write_byte(buf, 1, 97)
    val () = $A.write_byte(buf, 2, 99)
    val () = $A.write_byte(buf, 3, 107)
    val () = $A.write_byte(buf, 4, 97)
    val () = $A.write_byte(buf, 5, 103)
    val () = $A.write_byte(buf, 6, 101)
  in end

#pub fn make_name {l:agz}{n:pos | n >= 4}
  (buf: !$A.arr(byte, l, n)): void

implement make_name(buf) =
  let
    val () = $A.write_byte(buf, 0, 110)
    val () = $A.write_byte(buf, 1, 97)
    val () = $A.write_byte(buf, 2, 109)
    val () = $A.write_byte(buf, 3, 101)
  in end

#pub fn make_kind {l:agz}{n:pos | n >= 4}
  (buf: !$A.arr(byte, l, n)): void

implement make_kind(buf) =
  let
    val () = $A.write_byte(buf, 0, 107)
    val () = $A.write_byte(buf, 1, 105)
    val () = $A.write_byte(buf, 2, 110)
    val () = $A.write_byte(buf, 3, 100)
  in end

(* ============================================================
   Argparse helpers
   ============================================================ *)

#pub fun count_argc_loop {l:agz}{n:pos}{fuel:nat}  (buf: !$A.arr(byte, l, n), pos: pos_t, len: int, max: int n,
   count: int, fuel: int fuel): int

implement count_argc_loop(buf, pos, len, max, count, fuel) =
  if fuel <= 0 then count
  else if pos >= len then count
  else if pos < 0 then count
  else if pos >= max then count
  else let
    val b = peek_arr(buf, pos, max)
  in
    if $AR.eq_int_int(b, 0) then
      count_argc_loop(buf, pos + 1, len, max, count + 1, fuel - 1)
    else count_argc_loop(buf, pos + 1, len, max, count, fuel - 1)
  end

#pub fn count_argc {l:agz}
  (buf: !$A.arr(byte, l, 4096), len: int): int

implement count_argc(buf, len) =
  count_argc_loop(buf, 0, len, 4096, 0, 4097)


#pub fn ap_flag {tp:nat}{ac:nat | ac < 64}{nn,nh:pos | tp + nn + nh <= 8192; nn <= 1048576; nh <= 1048576}
  (p: $AP.parser(tp, ac), name: &(@[char][nn]), nn: int nn, sc: int, help: &(@[char][nh]), nh: int nh
  ): @($AP.parser(tp + nn + nh, ac + 1), $AP.arg($AP.bool_val))

implement ap_flag(p, name, nn, sc, help, nh) = let
  val @(fzn, bvn) = $A.freeze<byte>($S.from_char_array(name, nn))
  val @(fzh, bvh) = $A.freeze<byte>($S.from_char_array(help, nh))
  val @(p2, h) = $AP.add_flag(p, bvn, nn, sc, bvh, nh)
  val () = $A.drop<byte>(fzn, bvn)
  val () = $A.free<byte>($A.thaw<byte>(fzn))
  val () = $A.drop<byte>(fzh, bvh)
  val () = $A.free<byte>($A.thaw<byte>(fzh))
in @(p2, h) end

#pub fn ap_string_opt {tp:nat}{ac:nat | ac < 64}{nn,nh:pos | tp + nn + nh <= 8192; nn <= 1048576; nh <= 1048576}
  (p: $AP.parser(tp, ac), name: &(@[char][nn]), nn: int nn, sc: int, help: &(@[char][nh]), nh: int nh
  ): @($AP.parser(tp + nn + nh, ac + 1), $AP.arg($AP.string_val))

implement ap_string_opt(p, name, nn, sc, help, nh) = let
  val @(fzn, bvn) = $A.freeze<byte>($S.from_char_array(name, nn))
  val @(fzh, bvh) = $A.freeze<byte>($S.from_char_array(help, nh))
  val @(p2, h) = $AP.add_string(p, bvn, nn, sc, bvh, nh, false)
  val () = $A.drop<byte>(fzn, bvn)
  val () = $A.free<byte>($A.thaw<byte>(fzn))
  val () = $A.drop<byte>(fzh, bvh)
  val () = $A.free<byte>($A.thaw<byte>(fzh))
in @(p2, h) end

#pub fn ap_string_pos {tp:nat}{ac:nat | ac < 64}{nn,nh:pos | tp + nn + nh <= 8192; nn <= 1048576; nh <= 1048576}
  (p: $AP.parser(tp, ac), name: &(@[char][nn]), nn: int nn, help: &(@[char][nh]), nh: int nh
  ): @($AP.parser(tp + nn + nh, ac + 1), $AP.arg($AP.string_val))

implement ap_string_pos(p, name, nn, help, nh) = let
  val @(fzn, bvn) = $A.freeze<byte>($S.from_char_array(name, nn))
  val @(fzh, bvh) = $A.freeze<byte>($S.from_char_array(help, nh))
  val @(p2, h) = $AP.add_string(p, bvn, nn, 0, bvh, nh, true)
  val () = $A.drop<byte>(fzn, bvn)
  val () = $A.free<byte>($A.thaw<byte>(fzn))
  val () = $A.drop<byte>(fzh, bvh)
  val () = $A.free<byte>($A.thaw<byte>(fzh))
in @(p2, h) end

(* Byte-lexicographic a[0..alen) < b[0..blen) for directory entry names.
   The index is statically bounded by the 256-byte buffers. *)
fun name_lt_loop {la:agz}{lb:agz}{i:nat | i <= 256} .<256 - i>.
  (a: !$A.borrow(byte, la, 256), alen: int,
   b: !$A.borrow(byte, lb, 256), blen: int, i: int i): bool =
  if i >= 256 then false
  else if i >= alen then i < blen
  else if i >= blen then false
  else let
    val ca = byte2int0($A.read<byte>(a, i))
    val cb = byte2int0($A.read<byte>(b, i))
  in
    if ca < cb then true
    else if ca > cb then false
    else name_lt_loop(a, alen, b, blen, i + 1)
  end

fn name_lt {la:agz}{lb:agz}
  (a: !$A.borrow(byte, la, 256), alen: int,
   b: !$A.borrow(byte, lb, 256), blen: int): bool =
  name_lt_loop(a, alen, b, blen, 0)

(* Smallest entry of directory `path` strictly after prev[0..prev_len)
   (prev_len <= 0: smallest entry overall). Returns the entry buffer and
   its length, or length -1 when there is none. Walking a directory with
   this makes generated output independent of readdir order. *)
#pub fn dir_next_sorted {lp:agz}{np:pos | np < 1048576}{lq:agz}
  (path: !$A.borrow(byte, lp, np), path_len: int np,
   prev: !$A.borrow(byte, lq, 256), prev_len: int)
  : [lo:agz] @($A.arr(byte, lo, 256), [k:int | ~1 <= k; k <= 256] int k)

implement dir_next_sorted (path, path_len, prev, prev_len) = let
  fun scan {lq:agz}{lb:agz}{k:nat} .<k>.
    (d: !$F.dir, prev: !$A.borrow(byte, lq, 256), prev_len: int,
     best: $A.arr(byte, lb, 256), best_len: [b:int | ~1 <= b; b <= 256] int b, fuel: int k)
    : [lo:agz] @($A.arr(byte, lo, 256), [k:int | ~1 <= k; k <= 256] int k) =
    if fuel <= 0 then @(best, best_len)
    else let
      val e = $A.alloc<byte>(256)
      val nr = $F.dir_next(d, e, 256)
      val el = dir_name_len(nr)
    in
      if el < 0 then let
        val () = $A.free<byte>(e)
      in @(best, best_len) end
      else let
        val @(fz_e, bv_e) = $A.freeze<byte>(e)
        val @(fz_b, bv_b) = $A.freeze<byte>(best)
        val after_prev = (if prev_len <= 0 then true
          else name_lt(prev, prev_len, bv_e, el)): bool
        val beats = (if ~after_prev then false
          else if best_len < 0 then true
          else name_lt(bv_e, el, bv_b, best_len)): bool
        val () = $A.drop<byte>(fz_b, bv_b)
        val best = $A.thaw<byte>(fz_b)
        val () = $A.drop<byte>(fz_e, bv_e)
        val e = $A.thaw<byte>(fz_e)
      in
        if beats then let
          val () = $A.free<byte>(best)
        in scan(d, prev, prev_len, e, el, fuel - 1) end
        else let
          val () = $A.free<byte>(e)
        in scan(d, prev, prev_len, best, best_len, fuel - 1) end
      end
    end
  val dr = $F.dir_open(path, path_len)
in
  case+ dr of
  | ~$R.ok(d) => let
      val none = $A.alloc<byte>(256)
      val r = scan(d, prev, prev_len, none, ~1, 4096)
      val dcr = $F.dir_close(d)
      val () = $R.discard<int><int>(dcr)
    in r end
  | ~$R.err(_) => let
      val none = $A.alloc<byte>(256)
    in @(none, ~1) end
end

(* Feeds the rest of the file fd to c, a chunk at a time *)
fun _hash_chunks {lb:agz}{f:nat} .<f>.
  (fd: !$F.fd, buf: !$A.arr(byte, lb, 65536), c: !$SHA.ctx, f: int f): void =
  if f <= 0 then ()
  else let
    val k = (case+ $F.file_read(fd, buf, 65536) of
      | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 65536] int k
    val () = $SHA.update(c, buf, k)
  in if k < 65536 then () else _hash_chunks(fd, buf, c, f - 1) end

(* Appends the sha256 of the file at the NUL-terminated path p to out,
   as 64 hex digits (Rust: sha256::sha256_hex), reading it in chunks so
   any size hashes; false when it cannot be opened *)
#pub fn put_file_sha256 {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), out: !$B.builder_v >> $B.builder_v): bool

implement put_file_sha256 {lp} (p, out) =
  case+ $F.file_open(p, 524288, 0, 0) of
  | ~$R.ok(afd) => let
      val buf = $A.alloc<byte>(65536)
      val c = $SHA.init()
      (* file_read fills the buffer unless the file ends first; fuel for
         2^40 bytes *)
      val () = _hash_chunks(afd, buf, c, 16777216)
      val () = $A.free<byte>(buf)
      val () = $R.discard<int><int>($F.file_close(afd))
      val hex = $A.alloc<byte>(64)
      val () = $SHA.finish(c, hex)
      val @(fh, bh) = $A.freeze<byte>(hex)
      val () = copy_to_builder_v(bh, 0, 64, 64, out)
      val () = $A.drop<byte>(fh, bh)
      val () = $A.free<byte>($A.thaw<byte>(fh))
    in true end
  | ~$R.err(_) => false

(* ============================================================
   Versions (Rust: version::Version)
   ============================================================ *)

(* The first '.' in [i, e), or e *)
fun find_dot {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if $AR.eq_int_int(peek(b, i, n), 46) then i
  else find_dot(b, i + 1, e, n, f - 1)

(* Whether [i, e) is all ASCII digits *)
fun all_digits {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n, f: int f): bool =
  if f <= 0 then false
  else if i >= e then true
  else let val c = peek(b, i, n)
  in if c >= 48 && c <= 57 then all_digits(b, i + 1, e, n, f - 1) else false end

(* The first position in [i, e) that is not '0', or e *)
fun first_nonzero {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n, f: int f): pos_t =
  if f <= 0 then e
  else if i >= e then e
  else if $AR.eq_int_int(peek(b, i, n), 48) then first_nonzero(b, i + 1, e, n, f - 1)
  else i

(* Whether the digits b[z, z + 10) are at most m[0, 10) *)
fun digits_le {l:agz}{n:pos}{lm:agz}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), z: pos_t, n: int n,
   m: !$A.borrow(byte, lm, 10), j: pos_t, f: int f): bool =
  if f <= 0 then true
  else if j >= 10 then true
  else let
    val x = peek(b, z + j, n)
    val y = peek(m, j, 10)
  in
    if x < y then true
    else if x > y then false
    else digits_le(b, z, n, m, j + 1, f - 1)
  end

(* The digits of a u32 part without leading zeros: [z, e), or z = ~1
   when [s, e) is not one (Rust: u32::from_str after an optional '+') *)
fn u32_digits {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, n: int n): pos_t = let
  val d = (if s < e then
    (if $AR.eq_int_int(peek(b, s, n), 43) then s + 1 else s) else s): pos_t
  var max_c = @[char][10]('4', '2', '9', '4', '9', '6', '7', '2', '9', '5')
  val @(fz_m, bv_m) = $A.freeze<byte>($S.from_char_array(max_c, 10))
  val z0 = first_nonzero(b, d, e, n, 8192)
  val z = (if z0 >= e then e - 1 else z0): pos_t
  val fits = (if e - z < 10 then true
    else if e - z > 10 then false
    else digits_le(b, z, n, bv_m, 0, 10)): bool
  val () = $A.drop<byte>(fz_m, bv_m)
  val () = $A.free<byte>($A.thaw<byte>(fz_m))
in
  if e - d < 1 then ~1
  else if ~all_digits(b, d, e, n, 8192) then ~1
  else if fits then z
  else ~1
end

(* Rust's Version::parse over the parts of b[i, be), rendered into out:
   @(~1, ~1), or the invalid part's [start, end) *)
fun version_parts {l:agz}{n:pos}{f:nat} .<f>.
  (b: !$A.borrow(byte, l, n), i: pos_t, be: pos_t, n: int n,
   out: !$B.builder_v >> $B.builder_v, f: int f): @(pos_t, pos_t) =
  if f <= 0 then @(~1, ~1)
  else let
    val pe = find_dot(b, i, be, n, 8192)
    val z = u32_digits(b, i, pe, n)
  in
    if z < 0 then @(i, pe)
    else let
      val () = copy_to_builder_v(b, z, pe, n, out)
    in
      if pe >= be then @(~1, ~1)
      else let
        val () = put_char_v(out, 46)
      in version_parts(b, pe + 1, be, n, out, f - 1) end
    end
  end

(* "dev1" when dev *)
#pub fn put_dev1 (out: !$B.builder_v >> $B.builder_v, dev: bool): void

implement put_dev1 (out, dev) =
  if dev then bput_v(out, "dev1") else ()


(* Rust's Version::parse over the parts of b[i, be), rendered into out
   (each part a u32 without '+' or leading zeros): @(~1, ~1), or the
   invalid part's [start, end) *)
#pub fn parse_version_parts {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), i: pos_t, be: pos_t, n: int n,
   out: !$B.builder_v >> $B.builder_v): @(pos_t, pos_t)

implement parse_version_parts (b, i, be, n, out) = version_parts(b, i, be, n, out, 8192)

(* The first '.' in b[i, e), or e *)
#pub fn next_dot {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), i: pos_t, e: pos_t, n: int n): pos_t

implement next_dot (b, i, e, n) = find_dot(b, i, e, n, 8192)
