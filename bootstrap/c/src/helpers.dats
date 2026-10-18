staload "./helpers.sats"
staload "argparse/src/lib.dats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "path/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
staload "str/src/lib.dats"
staload "sha256/src/lib.dats"
(* helpers -- shared utilities for the bats compiler *)

#include "share/atspre_staload.hats"

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

(* ============================================================
   Proven byte reads
   ============================================================ *)

(* A position in a buffer. Indexed, so a read at it is proven in bounds
   by the comparisons in peek, with no cast. *)


(* Byte at p, or 0 outside [0, n). *)



implement peek (src, p, n) =
  if p < 0 then 0
  else if p >= n then 0
  else byte2int0($A.read<byte>(src, p))

(* Byte at p of an array, or 0 outside [0, n). *)



implement peek_arr (buf, p, n) =
  if p < 0 then 0
  else if p >= n then 0
  else byte2int0($A.get<byte>(buf, p))

(* Writes byte v at p of an array; does nothing outside [0, n). *)



implement poke_arr (buf, p, n, v) =
  if p < 0 then ()
  else if p >= n then ()
  else $A.set<byte>(buf, p, int2byte0(v))

(* First NUL at or after p, or p itself when p is outside [0, n]. *)



implement find_null_from (buf, p, n) =
  if p < 0 then p
  else if p > n then p
  else $S.find_null_at(buf, p, n)




implement find_null_bv_from (bv, p, n) =
  if p < 0 then p
  else if p > n then p
  else $S.find_null_bv_at(bv, p, n)

(* ============================================================
   Opening a path at its own length
   ============================================================ *)

(* Every path in bats is a NUL-terminated string in an array of 524288
   bytes (the builder's capacity), and the file package copies the whole
   of the length it is given to make the C string: file_open of such a
   path allocated, zeroed and copied 512 KiB to open a name of 60 bytes
   (bats#296: 20,000 opens made 37% of an unchanged check's instructions,
   and the zeroing 19% more). These open the path at its own length: the
   bytes up to and including its first NUL are copied into an array of
   that size, which is the path the file package is given. A path with
   no NUL in its array is given whole, as before. *)

fun fill_path {l:agz}{lc:agz}{n:pos}{k:nat | k <= n}{i:nat | i <= k} .<k - i>.
  (p: !$A.borrow(byte, l, n), c: !$A.arr(byte, lc, k + 1), i: int i, k: int k, n: int n): void =
  if i >= k then ()
  else let
    val () = $A.set<byte>(c, i, $A.read<byte>(p, i))
  in fill_path(p, c, i + 1, k, n) end

(* The path's bytes up to its first NUL, and that NUL, in an array of
   their number *)
fn path_short {l:agz}{n:pos | n <= 524288} (p: !$A.borrow(byte, l, n), n: int n)
  : [m:pos | m <= 524289][lc:agz] @($A.arr(byte, lc, m), int m) = let
  val z = find_null_bv_from(p, 0, n)
  val k = (if z >= 0 then (if z < n then z else n) else n): [k:nat | k <= n] int k
  val c = $A.alloc<byte>(k + 1)
  val () = fill_path(p, c, 0, k, n)
in @(c, k + 1) end

(* $F.file_open of the path p[0, n) at its own length *)




implement file_open_n (p, n, access, opening, mode) =
  if n <= 524288 then let
    val @(c, m) = path_short(p, n)
    val @(fz, bv) = $A.freeze<byte>(c)
    val r = $F.file_open(bv, m, access, opening, mode)
    val () = $A.drop<byte>(fz, bv)
    val () = $A.free<byte>($A.thaw<byte>(fz))
  in r end
  else $F.file_open(p, n, access, opening, mode)

(* ... of a path in an array of 524288 bytes *)




implement file_open_path (p, access, opening, mode) = file_open_n(p, 524288, access, opening, mode)

(* $F.file_exists of the path at its own length *)


implement file_exists_path (p) = let
  val @(c, m) = path_short(p, 524288)
  val @(fz, bv) = $A.freeze<byte>(c)
  val r = $F.file_exists(bv, m)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* $F.dir_open of the path at its own length *)


implement dir_open_path (p) = let
  val @(c, m) = path_short(p, 524288)
  val @(fz, bv) = $A.freeze<byte>(c)
  val r = $F.dir_open(bv, m)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* ============================================================
   Global state using ATS2 refs (replaces C statics)
   ============================================================ *)

val g_verbose = ref<bool>(false)
val g_quiet = ref<bool>(false)
val g_test_mode = ref<bool>(false)
val g_cold = ref<bool>(false)
val g_names_fresh = ref<bool>(false)
val g_lock_dev = ref<bool>(false)
val g_repo: ref(string) = ref("")
val g_bin: ref(string) = ref("")
val g_to_c = ref<bool>(false)
val g_to_c_done = ref<bool>(false)
val g_self_path: ref(string) = ref("")
val g_build_err = ref<bool>(false)
(* The machine slot this bats holds (bats-lang/bats#252): its number
   plus 1, 0 when it holds none *)
val g_slot_held = ref<int>(0)
val g_exit_code = ref<int>(0)
(* The optional cap on every patsopt run (BATS_PATSOPT_TIMEOUT_S,
   BATS_PATSOPT_MEM_MB): whether the environment was read, the seconds
   and the megabytes (0: no cap), and the status bats exits with when
   the cap ended a run (0 when none did) *)
val g_cap_read = ref<bool>(false)
val g_cap_secs = ref<int>(0)
val g_cap_mb = ref<int>(0)
val g_cap_exit = ref<int>(0)

















(* Whether the listing of the names of build/'s .sats and .hats (the check
   memo's `names`, build/.bats_names) is still the one of build/ as it is:
   it is made once after anything that adds, removes or moves such a file
   (a .sats emitted, build/ swapped in, the orphans pruned) and not for
   each module *)
















(* Whether --to-c was given: the build writes C to a directory *)


(* Whether the --to-c output was written *)














(* The status bats exits with when no error was recorded (bats run
   passes on its program's). *)




(* The status bats exits with when a build error was recorded, as
   patsopt_only sets it when a cap ended a patsopt run: 124 for the time
   cap, 125 for the memory cap, 0 when no cap did (the status is 1) *)


implement is_verbose() = !g_verbose
implement is_quiet() = !g_quiet
implement is_test_mode() = !g_test_mode
implement is_to_c() = !g_to_c
implement set_verbose(v) = !g_verbose := v
implement set_quiet(v) = !g_quiet := v
implement set_test_mode(v) = !g_test_mode := v
implement set_cold(v) = !g_cold := v
implement names_fresh () = !g_names_fresh
implement names_set_fresh (v) = !g_names_fresh := v
implement set_lock_dev(v) = !g_lock_dev := v
implement is_lock_dev() = !g_lock_dev
implement set_repo(s) = !g_repo := s
implement get_repo() = !g_repo
implement set_bin(s) = !g_bin := s
implement get_bin() = !g_bin
implement set_to_c(v) = !g_to_c := v
implement set_to_c_done(v) = !g_to_c_done := v
implement is_to_c_done() = !g_to_c_done
implement set_self_path(s) = !g_self_path := s
implement get_self_path() = !g_self_path
implement set_build_err() = !g_build_err := true
implement has_build_err() = !g_build_err
implement clear_build_err() = !g_build_err := false
implement set_exit_code(v) = !g_exit_code := v
implement get_exit_code() = !g_exit_code
implement get_cap_exit() = !g_cap_exit

(* ============================================================
   String builder helpers
   ============================================================ *)

(* buf[i, len) to stdout, stopping at the end of buf *)


implement print_arr(buf, i, len, max) = let
  fun loop {l:agz}{n:pos}{j:nat | j <= n} .<n - j>.
    (buf: !$A.arr(byte, l, n), j: int j, len: int, max: int n): void =
    if j >= max then ()
    else if j >= len then ()
    else let
      val () = print_char(int2char0(byte2int0($A.get<byte>(buf, j))))
    in loop(buf, j + 1, len, max) end
in
  if i < 0 then loop(buf, 0, len, max)
  else if i > max then ()
  else loop(buf, i, len, max)
end




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

(* Whether ent[0, len) ends with the chars sfx. *)



implement ent_has_suffix(ent, len, max, sfx, m) = let
  val @(f, b) = $A.freeze<byte>($S.from_char_array(sfx, m))
  val r = $S.has_suffix(ent, len, max, b, m)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
in r end

(* Whether ent[0, len) is exactly the chars s. *)



implement ent_name_eq(ent, len, max, s, m) = let
  val @(f, b) = $A.freeze<byte>($S.from_char_array(s, m))
  val r = $S.name_eq(ent, len, max, b, m)
  val () = $A.drop<byte>(f, b)
  val () = $A.free<byte>($A.thaw<byte>(f))
in r end

(* Whether a byte can be part of an identifier *)


implement is_ident_byte(b) =
  (b >= 97 && b <= 122) ||
  (b >= 65 && b <= 90) ||
  (b >= 48 && b <= 57) ||
  $AR.eq_int_int(b, 95)

(* Whether src[pos, pos + m) spells the chars lit. *)
(* ============================================================
   The prelude's non-linear builders
   ============================================================ *)

(* What a word of the ATS prelude, or of libats/ML, builds that is boxed
   and not linear: allocated, and never freed without a garbage
   collector (bats-lang/bats#228) *)


(* The words, each followed by one space. Enumerated from the prelude's
   SATS files (list.sats, option.sats, stream.sats, stream_vt.sats,
   grandom.sats, basics_dyn.sats) and libats/ML's basis.sats: the
   constructors of list, option and stream_con, the nil and cons macros,
   and every function whose result is a non-linear list, option or
   stream built from something that is not one (list_tail, which shares
   a list it is given, is not) *)
fn list_builders (): string = "list_cons list_nil nil cons list_append list_append1_vt list_reverse_append list_reverse_append1_vt list_insert_at list_remove_at list_takeout_at list_fset_at list_fexch_at list_split_at list_tuple_0 list_tuple_1 list_tuple_2 list_tuple_3 list_tuple_4 list_tuple_5 list_tuple_6 list_of_list_vt list_vt2t grandom_list list0 list0_cons list0_nil nil0 cons0 "
fn option_builders (): string = "Some None option_some option_none option_of_option_vt option_vt2t Some0 None0 option0 "
fn stream_builders (): string = "stream_cons stream_nil stream_append stream_concat stream_cross stream_differ stream_drop_exn stream_filter stream_filter_cloref stream_filter_fun stream_imap stream_imap_cloref stream_imap_fun stream_inter stream_labelize stream_make_cons stream_make_nil stream_make_sing stream_map stream_map2 stream_map2_cloref stream_map2_fun stream_map_cloref stream_map_fun stream_merge stream_merge_cloref stream_merge_fun stream_mergeq stream_mergeq_cloref stream_mergeq_fun stream_scan stream_scan_cloref stream_scan_fun stream_symdiff stream_tabulate stream_tabulate_cloref stream_tabulate_fun stream_tail_exn stream_union stream_vt2t stream_zip "

(* The end of the table's word that starts at i: the next space, or the
   table's end *)
fun table_word_end {t:nat}{i:nat | i <= t} .<t - i>.
  (table: string t, table_len: int t, i: int i): [j:nat | i <= j; j <= t] int j =
  if i >= table_len then i
  else if string_get_at(table, i) = ' ' then i
  else table_word_end(table, table_len, i + 1)

(* Whether src[s, s + k) holds table[i, i + k) *)
fun table_bytes_match {l:agz}{n:pos}{p:int}{t:nat}{i,k:nat | i + k <= t} .<k>.
  (src: !$A.borrow(byte, l, n), s: int p, max: int n, table: string t, i: int i, k: int k): bool =
  if k <= 0 then true
  else if peek(src, s, max) = char2int0(string_get_at(table, i)) then
    table_bytes_match(src, s + 1, max, table, i + 1, k - 1)
  else false

(* Whether src[s, s + len) is one of the words of table[i, ...) *)
fun in_table {l:agz}{n:pos}{p:int}{t:nat}{i:nat | i <= t} .<t - i>.
  (src: !$A.borrow(byte, l, n), s: int p, len: int, max: int n,
   table: string t, table_len: int t, i: int i): bool =
  if i >= table_len then false
  else let
    val j = table_word_end(table, table_len, i)
  in
    if j - i = len && table_bytes_match(src, s, max, table, i, j - i) then true
    else if j >= table_len then false
    else in_table(src, s, len, max, table, table_len, j + 1)
  end

fn in_word_table {l:agz}{n:pos}{p:int}
  (src: !$A.borrow(byte, l, n), s: int p, len: int, max: int n, table: string): bool = let
  val table1 = g1ofg0(table)
in in_table(src, s, len, max, table1, g1u2i(string1_length(table1)), 0) end

(* Whether build is the kind of build kind *)


implement prelude_build_is (build, kind) =
  case+ (build, kind) of
  | (NoPreludeBuild(), NoPreludeBuild()) => true
  | (BuildsList(), BuildsList()) => true
  | (BuildsOption(), BuildsOption()) => true
  | (BuildsStream(), BuildsStream()) => true
  | (_, _) => false




implement prelude_build_of (src, s, e, max) = let
  val len = e - s
in
  if len <= 0 then NoPreludeBuild()
  else if in_word_table(src, s, len, max, list_builders()) then BuildsList()
  else if in_word_table(src, s, len, max, option_builders()) then BuildsOption()
  else if in_word_table(src, s, len, max, stream_builders()) then BuildsStream()
  else NoPreludeBuild()
end

(* A package's kind: a library (kind = "lib", the default) or a binary
   (kind = "bin") *)





implement lit_at(src, pos, max, lit, m) =
  if pos < 0 then false
  else if pos + m > max then false
  else let
    val @(f, b) = $A.freeze<byte>($S.from_char_array(lit, m))
    val r = $S.match_at(src, pos, b, m)
    val () = $A.drop<byte>(f, b)
    val () = $A.free<byte>($A.thaw<byte>(f))
  in r end




implement has_bats_ext(ent, len, max) = let
  var c = @[char][5]('.', 'b', 'a', 't', 's')
in ent_has_suffix(ent, len, max, c, 5) end




implement has_dats_ext(ent, len, max) = let
  var c = @[char][5]('.', 'd', 'a', 't', 's')
in ent_has_suffix(ent, len, max, c, 5) end




implement has_dats_c_ext(ent, len, max) = let
  var c = @[char][7]('_', 'd', 'a', 't', 's', '.', 'c')
in ent_has_suffix(ent, len, max, c, 7) end




implement has_dats_o_ext(ent, len, max) = let
  var c = @[char][7]('_', 'd', 'a', 't', 's', '.', 'o')
in ent_has_suffix(ent, len, max, c, 7) end




implement has_sha256_ext(ent, len, max) = let
  var c = @[char][7]('.', 's', 'h', 'a', '2', '5', '6')
in ent_has_suffix(ent, len, max, c, 7) end




implement has_lib_dats_c_sfx(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'c')
in ent_has_suffix(ent, len, max, c, 10) end




implement has_lib_dats_o_sfx(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'o')
in ent_has_suffix(ent, len, max, c, 10) end




implement is_lib_bats(ent, len, max) = let
  var c = @[char][8]('l', 'i', 'b', '.', 'b', 'a', 't', 's')
in ent_name_eq(ent, len, max, c, 8) end




implement is_lib_dats(ent, len, max) = let
  var c = @[char][8]('l', 'i', 'b', '.', 'd', 'a', 't', 's')
in ent_name_eq(ent, len, max, c, 8) end




implement is_lib_dats_c(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'c')
in ent_name_eq(ent, len, max, c, 10) end




implement is_lib_dats_o(ent, len, max) = let
  var c = @[char][10]('l', 'i', 'b', '_', 'd', 'a', 't', 's', '.', 'o')
in ent_name_eq(ent, len, max, c, 10) end

(* Keyword and literal matchers: whether src[pos, pos + len) spells it. *)




implement lit_as(src, pos, max) = let
  var c = @[char][2]('a', 's')
in lit_at(src, pos, max, c, 2) end




implement lit_begin(src, pos, max) = let
  var c = @[char][5]('b', 'e', 'g', 'i', 'n')
in lit_at(src, pos, max, c, 5) end




implement lit_binary(src, pos, max) = let
  var c = @[char][6]('b', 'i', 'n', 'a', 'r', 'y')
in lit_at(src, pos, max, c, 6) end




implement lit_dollar_UNITTEST(src, pos, max) = let
  var c = @[char][9]('$', 'U', 'N', 'I', 'T', 'T', 'E', 'S', 'T')
in lit_at(src, pos, max, c, 9) end




implement lit_dollar_UNSAFE(src, pos, max) = let
  var c = @[char][7]('$', 'U', 'N', 'S', 'A', 'F', 'E')
in lit_at(src, pos, max, c, 7) end




implement lit_dot_slash(src, pos, max) = let
  var c = @[char][2]('.', '/')
in lit_at(src, pos, max, c, 2) end




implement lit_end(src, pos, max) = let
  var c = @[char][3]('e', 'n', 'd')
in lit_at(src, pos, max, c, 3) end




implement lit_exthash(src, pos, max) = let
  var c = @[char][4]('e', 'x', 't', '#')
in lit_at(src, pos, max, c, 4) end




implement lit_fun(src, pos, max) = let
  var c = @[char][3]('f', 'u', 'n')
in lit_at(src, pos, max, c, 3) end




implement lit_hash_pub(src, pos, max) = let
  var c = @[char][4]('#', 'p', 'u', 'b')
in lit_at(src, pos, max, c, 4) end




implement lit_hash_target(src, pos, max) = let
  var c = @[char][7]('#', 't', 'a', 'r', 'g', 'e', 't')
in lit_at(src, pos, max, c, 7) end




implement lit_hash_use(src, pos, max) = let
  var c = @[char][4]('#', 'u', 's', 'e')
in lit_at(src, pos, max, c, 4) end




implement lit_let(src, pos, max) = let
  var c = @[char][3]('l', 'e', 't')
in lit_at(src, pos, max, c, 3) end




implement lit_local(src, pos, max) = let
  var c = @[char][5]('l', 'o', 'c', 'a', 'l')
in lit_at(src, pos, max, c, 5) end




implement lit_machash(src, pos, max) = let
  var c = @[char][4]('m', 'a', 'c', '#')
in lit_at(src, pos, max, c, 4) end




implement lit_no_mangle(src, pos, max) = let
  var c = @[char][9]('n', 'o', '_', 'm', 'a', 'n', 'g', 'l', 'e')
in lit_at(src, pos, max, c, 9) end




implement lit_prfn(src, pos, max) = let
  var c = @[char][4]('p', 'r', 'f', 'n')
in lit_at(src, pos, max, c, 4) end




implement lit_prfun(src, pos, max) = let
  var c = @[char][5]('p', 'r', 'f', 'u', 'n')
in lit_at(src, pos, max, c, 5) end




implement lit_primplement(src, pos, max) = let
  var c = @[char][11]('p', 'r', 'i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
in lit_at(src, pos, max, c, 11) end




implement lit_slash_srcslash_libdot_dats(src, pos, max) = let
  var c = @[char][13]('/', 's', 'r', 'c', '/', 'l', 'i', 'b', '.', 'd', 'a', 't', 's')
in lit_at(src, pos, max, c, 13) end




implement lit_staload_dq(src, pos, max) = let
  var c = @[char][9]('s', 't', 'a', 'l', 'o', 'a', 'd', ' ', '\042')
in lit_at(src, pos, max, c, 9) end




implement lit_while(src, pos, max) = let
  var c = @[char][5]('w', 'h', 'i', 'l', 'e')
in lit_at(src, pos, max, c, 5) end

(* ============================================================
   Byte-level helpers
   ============================================================ *)


(* b[i, len) to stdout (err = false) or stderr, stopping at the end of b *)
fn put_seg {l:agz}{m:pos}
  (b: !$A.borrow(byte, l, m), i: pos_t, len: int, m: int m, err: bool): void = let
  fun loop {j:nat | j <= m} .<m - j>.
    (b: !$A.borrow(byte, l, m), j: int j, len: int, m: int m, err: bool): void =
    if j >= m then ()
    else if j >= len then ()
    else let
      val c = int2char0(byte2int0($A.read<byte>(b, j)))
      val () = (if err then prerr_char(c) else print_char(c))
    in loop(b, j + 1, len, m, err) end
in
  if i < 0 then loop(b, 0, len, m, err)
  else if i > m then ()
  else loop(b, i, len, m, err)
end

(* b[i, len) to stderr. *)



implement prerr_seg(b, i, len, m) = put_seg(b, i, len, m, true)

(* buf[i, len) to stdout. *)


implement print_borrow(buf, i, len, max) = put_seg(buf, i, len, max, false)

(* ============================================================
   Build pipeline helpers
   ============================================================ *)

(* src[start, stop) appended to dst, stopping at the end of src *)



implement copy_to_builder(src, start, stop, max, dst) = let
  fun loop {l:agz}{n:pos}{j:nat | j <= n}{bm:nat | bm + n - j <= $B.BUILDER_CAP} .<n - j>.
    (src: !$A.borrow(byte, l, n), j: int j, stop: int, max: int n,
     dst: !$B.builder(bm) >> [m:nat | bm <= m; m <= bm + n - j] $B.builder(m)): void =
    if j >= max then ()
    else if j >= stop then ()
    else let
      val () = $B.put_char(dst, $AR.low_byte(byte2int0($A.read<byte>(src, j))))
    in loop(src, j + 1, stop, max, dst) end
in
  if start < 0 then loop(src, 0, stop, max, dst)
  else if start > max then ()
  else loop(src, start, stop, max, dst)
end

(* Builder_v writers: a byte that does not fit is dropped, which leaves
   the builder full; write_file_from_builder refuses a full builder *)



implement put_char_v(out, v) =
  if $B.length(out) < 524288 then $B.put_char(out, $AR.low_byte(v)) else ()




implement bput_v(out, s) = let
  fun loop {sl:nat}{i:nat | i <= sl} .<sl - i>.
    (out: !$B.builder_v >> $B.builder_v, s: string sl, slen: int sl, i: int i): void =
    if i >= slen then ()
    else let
      val () = put_char_v(out, char2int0(string_get_at(s, i)))
    in loop(out, s, slen, i + 1) end
in loop(out, s, g1u2i(string1_length(s)), 0) end

(* v in decimal appended to out, as much of it as there is room for, as
   the other builder_v writers do: a builder_v that drops a byte ends up
   full, which write_file_from_builder refuses *)




implement put_newline_v(out) = put_char_v(out, 10)

(* src[start, stop) appended to dst, stopping at the end of src or of
   the builder's capacity *)




implement copy_to_builder_v(src, start, stop, max, dst) = let
  fun loop {l:agz}{n:pos}{j:nat | j <= n}{bm:nat | bm <= $B.BUILDER_CAP} .<n - j>.
    (src: !$A.borrow(byte, l, n), j: int j, stop: int, max: int n,
     dst: !$B.builder(bm) >> $B.builder_v): void =
    if j >= max then ()
    else if j >= stop then ()
    else if $B.length(dst) >= 524288 then ()
    else let
      val () = $B.put_char(dst, $AR.low_byte(byte2int0($A.read<byte>(src, j))))
    in loop(src, j + 1, stop, max, dst) end
in
  if start < 0 then loop(src, 0, stop, max, dst)
  else if start > max then ()
  else loop(src, start, stop, max, dst)
end

(* One past the last '/' in bv before the NUL at or after pos (last + 1
   when there is none) *)
(* b's bytes appended to out; consumes b *)


implement put_int_v(out, v) =
  if $B.length(out) + 11 <= 524288 then $B.put_int(out, v)
  else let
    var t : $B.builder_v = $B.create()
    val () = $B.put_int(t, v)
  in append_builder(out, t) end

implement append_builder (out, b) = let
  val @(ba, bl) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(ba)
  val () = copy_to_builder_v(bv, 0, bl, 524288, out)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end




implement find_basename_start(bv, pos, max, last) = let
  fun loop {l:agz}{n:pos}{j:nat | j <= n} .<n - j>.
    (bv: !$A.borrow(byte, l, n), j: int j, max: int n, last: pos_t): pos_t =
    if j >= max then last + 1
    else let
      val b = byte2int0($A.read<byte>(bv, j))
    in
      if $AR.eq_int_int(b, 0) then last + 1
      else if $AR.eq_int_int(b, 47) then loop(bv, j + 1, max, j)
      else loop(bv, j + 1, max, last)
    end
in
  if pos < 0 then last + 1
  else if pos > max then last + 1
  else loop(bv, pos, max, last)
end

(* bv[i, lim) to bw *)



implement wbw_loop(bw, bv, i, lim) = let
  fun loop {l:agz}{j:nat | j <= 524288} .<524288 - j>.
    (bw: !$F.buf_writer, bv: !$A.borrow(byte, l, 524288), j: int j, lim: int): void =
    if j >= 524288 then ()
    else if j >= lim then ()
    else let
      val wr = $F.buf_write_byte(bw, byte2int0($A.read<byte>(bv, j)))
      val () = $R.discard<int><$F.io_error>(wr)
    in loop(bw, bv, j + 1, lim) end
in
  if i < 0 then loop(bw, bv, 0, lim)
  else if i > 524288 then ()
  else loop(bw, bv, i, lim)
end

(* build/.sats_changed is written whenever an emitted .sats changes, with
   new bytes each time: the sha256 of what it held (a chain, so no content
   comes back). A module's C is fresh only when the key recorded beside it
   (<C>.key: the sha256 of its .dats and of this file) is the one its
   inputs give now, so a change to a .sats rebuilds every module (bats#254:
   a time cannot tell, a build and its inputs share a second) *)
fn sats_stamp_path (): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, "build/.sats_changed")
  val () = put_char_v(b, 0)
in b end



implement touch_sats_stamp () = let
  val () = names_set_fresh(false)
  val @(pa, _) = $B.to_arr(sats_stamp_path())
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  var nb : $B.builder_v = $B.create()
  val had = put_file_sha256(bv_p, nb)
  val () = (if had then () else bput_v(nb, "1"))
  val _ = write_file_from_builder(bv_p, 524288, nb)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in end

(* Whether the C at out_b, patsopt's output for the .dats at in_b, is
   fresh: newer than the .dats and than the last .sats change *)



implement c_fresh_bv(out_b, in_b) = key_fresh(KeyOfCFile(), out_b, in_b)

(* Whether the file at path_bv holds exactly bv[0, len) *)



implement file_has_bytes {lp}{lb} (path_bv, bv, len) =
  case+ file_open_path(path_bv, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(524288)
      val rr = $F.file_read(fd, buf, 524288)
      val k = (case+ rr of | ~$R.ok(n) => n | ~$R.err(_) => 0): [k:nat | k <= 524288] int k
      val cr = $F.file_close(fd)
      val () = $R.discard<int><$F.io_error>(cr)
      fun same {la:agz}{m:nat | m <= 524288}{j:nat | j <= m} .<m - j>.
        (a: !$A.borrow(byte, la, 524288), bv: !$A.borrow(byte, lb, 524288), m: int m, j: int j): bool =
        if j >= m then true
        else if $AR.eq_int_int(byte2int0($A.read<byte>(a, j)), byte2int0($A.read<byte>(bv, j)))
        then same(a, bv, m, j + 1)
        else false
      val @(fz_f, bv_f) = $A.freeze<byte>(buf)
      val eq = (if $AR.eq_int_int(k, len) then same(bv_f, bv, k, 0) else false): bool
      val () = $A.drop<byte>(fz_f, bv_f)
      val () = $A.free<byte>($A.thaw<byte>(fz_f))
    in eq end
  | ~$R.err(_) => false

(* The profile a build makes: debug (-g -O0, into dist/debug) or release
   (-O2, into dist/release) *)




implement is_release (p) = case+ p of Release() => true | Debug() => false

(* ============================================================
   Content keys: when an output is fresh (bats#254)
   ============================================================ *)

(* The kind of output a key is for. A native object's bytes depend on the
   profile (its cc flags: -g -O0 or -O2), so its key names the profile
   (bats-lang/bats#320); a C's bytes do not (patsopt's output is the same
   in both profiles), and a wasm object's are fixed (run_wasm_cc passes
   -O2 always), so neither names it. Every key is written and checked by
   key_fresh and key_record alone. *)




implement object_key (rel) = case+ rel of
  | Release() => KeyOfReleaseObject()
  | Debug() => KeyOfDebugObject()

(* Whether the key's output is a C (its key takes build/.sats_changed) *)
fn key_is_c (kind: key_of): bool = case+ kind of
  | KeyOfCFile() => true
  | KeyOfWasmObject() => false
  | KeyOfDebugObject() => false
  | KeyOfReleaseObject() => false

(* The first line of the sizes part for a native object's profile; none
   for the others, so their keys keep their text *)
fn key_profile_line (kind: key_of, b: !$B.builder_v >> $B.builder_v): void =
  case+ kind of
  | KeyOfCFile() => ()
  | KeyOfWasmObject() => ()
  | KeyOfDebugObject() => let
      val () = bput_v(b, "debug")
      val () = put_char_v(b, 10)
    in end
  | KeyOfReleaseObject() => let
      val () = bput_v(b, "release")
      val () = put_char_v(b, 10)
    in end

(* An output (a module's C, an object) is fresh when the key recorded
   beside it, <output>.key, equals the one its inputs give now, and the
   output is there. The key of a C is the sha256 of its .dats, a line feed
   and the sha256 of build/.sats_changed (which holds new bytes whenever a
   .sats changed, so a changed .sats makes every C stale, as before); the
   key of an object is the sha256 of its C (the flags, the target and the
   mode are in build/.bats_stamp, which drops a build/ that differs). No
   time is read: a build and its inputs made in one second, a stash moved
   with its mtimes, a file touched or replaced with an old mtime, all give
   the answer their bytes give. A key that is missing, short or garbled
   is not equal, so the output is made again. The key is removed before
   the tool runs and written after it passed, so an output a killed run
   left half written has none. *)

(* <out>.key for the NUL-terminated path out *)
fn key_file_path {lo:agz} (out_bv: !$A.borrow(byte, lo, 524288)): $B.builder_v = let
  var kb : $B.builder_v = $B.create()
  val n = find_null_bv_from(out_bv, 0, 524288)
  val () = copy_to_builder_v(out_bv, 0, n, 524288, kb)
  val () = bput_v(kb, ".key")
  val () = put_char_v(kb, 0)
in kb end

(* The size of the file at the NUL-terminated path, or ~1 *)
fn size_of_file {lp:agz} (p: !$A.borrow(byte, lp, 524288)): int =
  case+ file_open_path(p, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(fd) => let
      val z = (case+ $F.fd_size(fd) of
        | ~$R.ok(z) => z | ~$R.err(_) => ~1): int
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in z end
  | ~$R.err(_) => ~1

(* Whether the file at path_bv begins with bv[0, len) *)
fn file_has_prefix {lp:agz}{lb:agz}{n:nat | n <= 524288}
  (path_bv: !$A.borrow(byte, lp, 524288), bv: !$A.borrow(byte, lb, 524288), len: int n): bool =
  case+ file_open_path(path_bv, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(524288)
      val rr = $F.file_read(fd, buf, 524288)
      val k = (case+ rr of | ~$R.ok(n) => n | ~$R.err(_) => 0): [k:nat | k <= 524288] int k
      val cr = $F.file_close(fd)
      val () = $R.discard<int><$F.io_error>(cr)
      fun same {la:agz}{m:nat | m <= 524288}{j:nat | j <= m} .<m - j>.
        (a: !$A.borrow(byte, la, 524288), bv: !$A.borrow(byte, lb, 524288), m: int m, j: int j): bool =
        if j >= m then true
        else if $AR.eq_int_int(byte2int0($A.read<byte>(a, j)), byte2int0($A.read<byte>(bv, j)))
        then same(a, bv, m, j + 1)
        else false
      val @(fz_f, bv_f) = $A.freeze<byte>(buf)
      val ok = (if len <= k then same(bv_f, bv, len, 0) else false): bool
      val () = $A.drop<byte>(fz_f, bv_f)
      val () = $A.free<byte>($A.thaw<byte>(fz_f))
    in ok end
  | ~$R.err(_) => false

(* The size of the file named by the NUL-terminated builder, or ~1 *)
fn size_of_built (pb: $B.builder_v): int = let
  val @(sa, _) = $B.to_arr(pb)
  val @(fz_s, bv_s) = $A.freeze<byte>(sa)
  val z = size_of_file(bv_s)
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in z end

(* Appends the sha256 of the file named by the NUL-terminated builder, or
   "-" when it is not there *)
fn hash_of_built (pb: $B.builder_v, b: !$B.builder_v >> $B.builder_v): void = let
  val @(sa, _) = $B.to_arr(pb)
  val @(fz_s, bv_s) = $A.freeze<byte>(sa)
  val has = put_file_sha256(bv_s, b)
  val () = (if has then () else bput_v(b, "-"))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in end

fn bats_stamp_path (): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, "build/.bats_stamp")
  val () = put_char_v(b, 0)
in b end

(* ---- The input digest (bats#254, for #267's memos) ----

   What a build step was made from, as text: the part that is sizes, one
   per line, then the part that is sha256s (64 hex digits, or "-" for a
   file that is not there), one per line, the same files in the same order:
     1. the step's input: for a C its .dats, for an object its C;
     2. for a C only, build/.sats_changed: it holds new bytes whenever any
        emitted .sats changed, so it stands for every .sats a module may
        staload (a coarse, sound stand-in for the files patsopt reads: a
        .sats change makes every C stale, as it always did);
     3. build/.bats_stamp: the digest of this bats, patsopt, cc, the flag
        templates and the target and mode that made build/ (bats#273).
   A size is a negative only: equal sizes say nothing until the hashes
   agree. No time is read. The record of a step is this text in
   <output>.key, written after the step passed and removed before it
   runs. A caller that wants a digest of its own (a memo of a check, of a
   fixture) calls input_digest_sizes and input_digest_hashes on its
   input, or input_digest for both: false when the input cannot be read,
   and then nothing it appended is a digest. *)
(* The size line and the hash line of build/.bats_stamp, the last of every
   digest: the part of a key that is the same for all of build/ *)


implement stamp_digest_sizes(b) = let
  val () = put_int_v(b, size_of_built(bats_stamp_path()))
in put_char_v(b, 10) end



implement stamp_digest_hashes(b) = let
  val () = hash_of_built(bats_stamp_path(), b)
in put_char_v(b, 10) end




implement input_digest_sizes(kind, in_bv, b) = let
  val () = key_profile_line(kind, b)
  val z = size_of_file(in_bv)
  val () = put_int_v(b, z)
  val () = put_char_v(b, 10)
  val () = (if key_is_c(kind) then let
      val () = put_int_v(b, size_of_built(sats_stamp_path()))
    in put_char_v(b, 10) end else ())
  val () = stamp_digest_sizes(b)
in $AR.gte_int_int(z, 0) end




implement input_digest_hashes(kind, in_bv, b) = let
  val ok = put_file_sha256(in_bv, b)
  val () = put_char_v(b, 10)
  val () = (if key_is_c(kind) then let
      val () = hash_of_built(sats_stamp_path(), b)
    in put_char_v(b, 10) end else ())
  val () = stamp_digest_hashes(b)
in ok end

(* Sizes and then hashes, for a caller that has no use for the sizes alone *)



implement input_digest(kind, in_bv, b) = let
  val sized = input_digest_sizes(kind, in_bv, b)
in if sized then input_digest_hashes(kind, in_bv, b) else false end

(* The one reader of an output's key: fresh when <output>.key is the key
   the input gives now (see the comment above). Every object kind comes
   through here with its own key_of. *)


implement key_fresh(kind, out_b, in_b) = let
  val @(oa, _) = $B.to_arr(out_b)
  val @(ia, _) = $B.to_arr(in_b)
  val @(fz_o, bv_o) = $A.freeze<byte>(oa)
  val @(fz_i, bv_i) = $A.freeze<byte>(ia)
  val there = file_exists_path(bv_o)
  val @(ka, _) = $B.to_arr(key_file_path(bv_o))
  val @(fz_k, bv_k) = $A.freeze<byte>(ka)
  (* sizes first: a different size is a changed file, with no hashing *)
  var sb : $B.builder_v = $B.create()
  val sized = input_digest_sizes(kind, bv_i, sb)
  val @(sa2, slen) = $B.to_arr(sb)
  val @(fz_sz, bv_sz) = $A.freeze<byte>(sa2)
  val same_sizes = (if there && sized then file_has_prefix(bv_k, bv_sz, slen) else false): bool
  var hb : $B.builder_v = $B.create()
  val () = (if same_sizes then let
      val () = copy_to_builder_v(bv_sz, 0, slen, 524288, hb)
    in () end else ())
  val hashed = (if same_sizes then input_digest_hashes(kind, bv_i, hb) else false): bool
  val @(ha2, hlen) = $B.to_arr(hb)
  val @(fz_h, bv_h) = $A.freeze<byte>(ha2)
  val result = (if hashed then file_has_bytes(bv_k, bv_h, hlen) else false): bool
  val () = $A.drop<byte>(fz_h, bv_h)
  val () = $A.free<byte>($A.thaw<byte>(fz_h))
  val () = $A.drop<byte>(fz_sz, bv_sz)
  val () = $A.free<byte>($A.thaw<byte>(fz_sz))
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val () = $A.drop<byte>(fz_i, bv_i)
  val () = $A.free<byte>($A.thaw<byte>(fz_i))
in result end

(* Writes <out>.key from the input now (after the tool passed) *)



implement key_record(kind, out_bv, in_bv) = let
  var tb : $B.builder_v = $B.create()
  val ok = input_digest(kind, in_bv, tb)
  val tbv = tb
  val @(ka, _) = $B.to_arr(key_file_path(out_bv))
  val @(fz_k, bv_k) = $A.freeze<byte>(ka)
  val _ = (if ok then write_file_from_builder(bv_k, 524288, tbv)
    else let val () = $B.builder_free(tbv) in 0 end): int
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
in end

(* The keys of the objects: a native object's names its profile, a wasm
   object's does not (bats-lang/bats#320). Written and read by key_record
   and key_fresh alone. *)


implement native_object_fresh(rel, out_b, in_b) = key_fresh(object_key(rel), out_b, in_b)



implement wasm_object_fresh(out_b, in_b) = key_fresh(KeyOfWasmObject(), out_b, in_b)




implement native_object_record(rel, out_bv, in_bv) = key_record(object_key(rel), out_bv, in_bv)




implement wasm_object_record(out_bv, in_bv) = key_record(KeyOfWasmObject(), out_bv, in_bv)

(* Removes <out>.key (before the tool that makes out runs) *)


implement key_drop(out_bv) = let
  val @(ka, kl) = $B.to_arr(key_file_path(out_bv))
  val @(fz_k, bv_k) = $A.freeze<byte>(ka)
  val () = remove_output(bv_k, kl)
  val () = $A.drop<byte>(fz_k, bv_k)
in $A.free<byte>($A.thaw<byte>(fz_k)) end

(* src[i, lim) appended to dst, stopping at the end of src or of the
   builder's capacity *)




implement arr_range_to_builder_v(src, i, lim, dst) = let
  fun loop {l:agz}{j:nat | j <= 4096}{bm:nat | bm <= $B.BUILDER_CAP} .<4096 - j>.
    (src: !$A.arr(byte, l, 4096), j: int j, lim: int,
     dst: !$B.builder(bm) >> $B.builder_v): void =
    if j >= 4096 then ()
    else if j >= lim then ()
    else if $B.length(dst) >= 524288 then ()
    else let
      val () = $B.put_char(dst, $AR.low_byte(byte2int0($A.get<byte>(src, j))))
    in loop(src, j + 1, lim, dst) end
in
  if i < 0 then ()
  else if i > 4096 then ()
  else loop(src, i, lim, dst)
end

(* s in a NUL-terminated 4096-byte array (cut at 4095 bytes) *)


implement str_to_arr4096(s) = let
  fun fill {lb:agz}{sn:nat}{i:nat | i <= sn} .<sn - i>.
    (b: !$A.arr(byte, lb, 4096), s: string sn, slen: int sn, i: int i): void =
    if i >= slen then ()
    else if i >= 4095 then ()
    else let
      val () = $A.set<byte>(b, i, $A.int2byte($AR.low_byte(char2int0(string_get_at(s, i)))))
    in fill(b, s, slen, i + 1) end
  val b = $A.alloc<byte>(4096)
  val slen = g1u2i(string1_length(s))
  val () = fill(b, s, slen, 0)
in b end

(* ============================================================
   Process execution
   ============================================================ *)

(* Convert a filled builder into a process arg_entry *)


implement mk_arg(b) = let
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fun _rev_arg_list {n:nat} .<n>.
  (xs: $L.list_vt($P.arg_entry, n), acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  case+ xs of
  | ~$L.list_vt_nil() => acc
  | ~$L.list_vt_cons(x, tl) => _rev_arg_list(tl, $L.list_vt_cons(x, acc))

(* xs reversed onto acc *)



implement rev_arg_list (xs, acc) = _rev_arg_list(xs, acc)

(* Split a null-separated builder into a list of arg_entries *)


(* The first position of bv[p, t) holding c, or t *)
fun find_byte {lb:agz}{p,t:nat | p <= t; t <= 524288} .<t - p>.
  (bv: !$A.borrow(byte, lb, 524288), p: int p, t: int t, c: int): [r:nat | p <= r; r <= t] int r =
  if p >= t then p
  else if byte2int0($A.read<byte>(bv, p)) = c then p
  else find_byte(bv, p + 1, t, c)

(* The first position of bv[p, t) not holding c, or t *)
fun skip_byte {lb:agz}{p,t:nat | p <= t; t <= 524288} .<t - p>.
  (bv: !$A.borrow(byte, lb, 524288), p: int p, t: int t, c: int): [r:nat | p <= r; r <= t] int r =
  if p >= t then p
  else if byte2int0($A.read<byte>(bv, p)) <> c then p
  else skip_byte(bv, p + 1, t, c)

(* The words of bv[p, t) separated by sep (runs of sep when skip),
   onto acc, last first *)
fun split_words {lb:agz}{p,t:nat | p <= t; t <= 524288} .<t - p>.
  (bv: !$A.borrow(byte, lb, 524288), p: int p, t: int t, sep: int, skip: bool,
   acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if p >= t then acc
  else let
    val s0 = (if skip then skip_byte(bv, p, t, sep) else p): [r:nat | p <= r; r <= t] int r
    val we = find_byte(bv, s0, t, sep)
    val acc2 = (if we > s0 then let
        var wb = $B.create()
        val () = copy_to_builder_v(bv, s0, we, 524288, wb)
      in $L.list_vt_cons(mk_arg(wb), acc) end
      else acc): $L.listv($P.arg_entry)
  in
    if we >= t then acc2 else split_words(bv, we + 1, t, sep, skip, acc2)
  end

implement split_null_to_list(b) = let
  val @(arr, total_len) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val result = split_words(bv, 0, total_len, 0, false, $L.list_vt_nil())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in rev_arg_list(result, $L.list_vt_nil()) end

(* Split a space-separated builder into a list of arg_entries *)


implement split_spaces_to_list(b) = let
  val @(arr, total_len) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val result = split_words(bv, 0, total_len, 32, true, $L.list_vt_nil())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in rev_arg_list(result, $L.list_vt_nil()) end

(* Run mkdir -p <path>. path_b is consumed. Returns exit code. *)



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

(* ============================================================
   The machine's slots (bats-lang/bats#252): names and paths
   ============================================================ *)

(* The environment variable name appended to out; false when it is not
   set or is empty *)



implement env_value (name, out) = let
  val na = str_to_path_arr(name)
  val buf = $A.alloc<byte>(4096)
  val got = $E.get_cstr(na, 524288, buf, 4096)
  val () = $A.free<byte>(na)
  val k = (case+ got of | ~$R.some(n) => n | ~$R.none() => 0): int
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val () = (if k > 0 then copy_to_builder_v(bv_b, 0, k, 4096, out) else ())
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in k > 0 end

(* The slots' directory appended to out: BATS_LOCK_DIR, else
   ~/.cache/bats (as gen-pwa test's PWA_TEST_LOCK_DIR, else
   ~/.cache/pwa-test) *)


implement slot_dir (out) =
  if env_value("BATS_LOCK_DIR", out) then ()
  else let
    val _ = env_value("HOME", out)
  in bput_v(out, "/.cache/bats") end

(* The file of slot i appended to out: <dir>/slot-<i>.lock, the name
   gen-pwa test gives its slots, so one directory is one pool *)


implement slot_path (i, out) = let
  val () = slot_dir(out)
  val () = bput_v(out, "/slot-")
  val () = put_int_v(out, i)
in bput_v(out, ".lock") end

(* What bats starts (patsopt, cc, a test runner) gets this process's
   environment, and, while this bats holds a machine slot
   (bats-lang/bats#252), BATS_SLOT_HELD naming it: a bats started by it
   runs in that slot instead of waiting for another, as a command make
   starts runs in the job slot make reserved for it. Holding none, the
   environment is this process's alone. extra's NAME=VALUE entries are
   added too, each replacing that variable. *)











implement spawn_child_with (path, argv, extra, stdin_cfg, stdout_cfg, stderr_cfg) = let
  val held = !g_slot_held
  val extra = (if held > 0 then let
      var e : $B.builder_v = $B.create()
      val () = bput_v(e, "BATS_SLOT_HELD=")
      val () = slot_path(held - 1, e)
    in $L.list_vt_cons(mk_arg(e), extra) end
    else extra): $L.listv($P.arg_entry)
in
  case+ extra of
  | ~$L.list_vt_nil() => $P.spawn_inherit_env(path, argv, stdin_cfg, stdout_cfg, stderr_cfg)
  | $L.list_vt_cons(_, _) => $P.spawn_inherit_env_with(path, argv, extra, stdin_cfg, stdout_cfg, stderr_cfg)
end

(* As spawn_child_with, with no extra entries *)










implement spawn_child (path, argv, stdin_cfg, stdout_cfg, stderr_cfg) =
  spawn_child_with(path, argv, $L.list_vt_nil(), stdin_cfg, stdout_cfg, stderr_cfg)

(* How running a program went: it exited with a status (1 if it did not
   exit normally), or it could not be started *)


(* Runs exec with argv, sharing this process's stdin, stdout, stderr and
   environment, as the Rust bats's Command::status did *)



implement run_program (exec_bv, argv) = let
  val spawned = spawn_child(exec_bv, argv, $P.inherit(), $P.inherit(), $P.inherit())
in
  case+ spawned of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $P.pipe_end_close(sin_p)
      val () = $P.pipe_end_close(sout_p)
      val () = $P.pipe_end_close(serr_p)
      val ec = (case+ $P.child_wait(child) of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in Exited(if ec >= 0 then ec else 1) end
  | ~$R.err(_) => NotStarted()
end





implement run_cmd (exec_bv, argv) = let
  val sr = spawn_child(exec_bv, argv,
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
      val () = $R.discard<int><$F.io_error>(ecr)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in
      if ec <> 0 then let
        val @(fz_eb2, bv_eb2) = $A.freeze<byte>(eb)
        val () = print_borrow(bv_eb2, 0, elen, 65536)
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



implement parse_decimal (buf, len, max) = let
  fun loop {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
    (buf: !$A.arr(byte, l, n), max: int n, pos: int p, len: int, acc: int): int =
    if pos >= max then acc
    else if pos >= len then acc
    else let
      val b = byte2int0($A.get<byte>(buf, pos))
    in
      if b >= 48 then
        if b <= 57 then loop(buf, max, pos + 1, len, acc * 10 + (b - 48))
        else acc
      else acc
    end
in loop(buf, max, 0, len, 0) end

(* Convert unix timestamp to calendar version: @(year, month, day, secs_of_day) *)
(* Hinnant's civil_from_days algorithm *)


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





implement run_cmd_capture (exec_bv, argv, outbuf) = let
  val sr = spawn_child(exec_bv, argv,
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
      val () = $R.discard<int><$F.io_error>(ocr)
      val+ ~$P.pipe_fd(err_fd) = serr_p
      val eb = $A.alloc<byte>(4096)
      val err_r = $F.file_read(err_fd, eb, 4096)
      val () = (case+ err_r of | ~$R.ok(_) => () | ~$R.err(_) => ())
      val ecr = $F.file_close(err_fd)
      val () = $R.discard<int><$F.io_error>(ecr)
      val () = $A.free<byte>(eb)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in @(ec, olen) end
  | ~$R.err(e) => @(0 - e, 0)
end

(* b's bytes to stderr; consumes b *)


implement prerr_builder (b) = let
  val @(ba, bl) = $B.to_arr(b)
  fun loop {lb:agz}{i,n:nat | i <= n; n <= 524288} .<n - i>.
    (a: !$A.arr(byte, lb, 524288), i: int i, n: int n): void =
    if i >= n then ()
    else let
      val () = prerr_char(int2char0(byte2int0($A.get<byte>(a, i))))
    in loop(a, i + 1, n) end
  val () = loop(ba, 0, bl)
in $A.free<byte>(ba) end

(* The prelude line count in <in>.pre, written next to the .dats
   in[0, il) by preprocess_one; 0 when there is none *)
fun digits_val {lb:agz}{i,k:nat | i <= k; k <= 16} .<k - i>.
  (b: !$A.borrow(byte, lb, 16), i: int i, k: int k, v: int): int =
  if i >= k then v
  else let val c = byte2int0($A.read<byte>(b, i)) in
    if c < 48 then v else if c > 57 then v
    else digits_val(b, i + 1, k, v * 10 + (c - 48))
  end

fn read_prelude {li:agz} (in_bv: !$A.borrow(byte, li, 524288), il: int): int = let
  var pb : $B.builder_v = $B.create()
  val () = copy_to_builder_v(in_bv, 0, il, 524288, pb)
  val () = bput_v(pb, ".pre")
  val () = put_char_v(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val n = (case+ file_open_path(bv_p, $F.ReadOnly(), $F.OpenExisting(), 0) of
    | ~$R.err(_) => 0
    | ~$R.ok(fd) => let
        val buf = $A.alloc<byte>(16)
        val k = (case+ $F.file_read(fd, buf, 16) of
          | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 16] int k
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        val @(fz_b, bv_b) = $A.freeze<byte>(buf)
        val v = digits_val(bv_b, 0, k, 0)
        val () = $A.drop<byte>(fz_b, bv_b)
        val () = $A.free<byte>($A.thaw<byte>(fz_b))
      in v end): int
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in n end

(* Everything left to read from fd appended to out, up to about 500000
   bytes (Rust reads patsopt's whole stderr); total bytes read so far *)
fun drain_fd {t:nat | t <= 500000} .<500000 - t>.
  (fd: !$F.fd, out: !$B.builder_v >> $B.builder_v, total: int t): void = let
  val buf = $A.alloc<byte>(4096)
  val k = (case+ $F.file_read(fd, buf, 4096) of
    | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 4096] int k
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val () = copy_to_builder_v(bv_b, 0, k, 4096, out)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in
  if k <= 0 then ()
  else if total + k > 500000 then ()
  else drain_fd(fd, out, total + k)
end

(* The end of the line holding e[i] (its newline, or n) *)
fun line_end_at {le:agz}{i,n:nat | i <= n; n <= 524288} .<n - i>.
  (e: !$A.borrow(byte, le, 524288), i: int i, n: int n): [j:nat | i <= j; j <= n] int j =
  if i >= n then i
  else if byte2int0($A.read<byte>(e, i)) = 10 then i
  else line_end_at(e, i + 1, n)

(* Whether e[i, j) holds the k bytes of lit somewhere *)
fun has_lit {le:agz}{m:pos | m <= 16}{i,j:nat | i <= j; j <= 524288} .<j - i>.
  (e: !$A.borrow(byte, le, 524288), i: int i, j: int j, lit: &(@[char][m]), k: int m): bool =
  if i + k > j then false
  else if lit_at(e, i, 524288, lit, k) then true
  else has_lit(e, i + 1, j, lit, k)

(* The digits at e[i, j): their end, and their value *)
fun num_at {le:agz}{i,j:nat | i <= j; j <= 524288} .<j - i>.
  (e: !$A.borrow(byte, le, 524288), i: int i, j: int j, v: int): @([r:nat | i <= r; r <= j] int r, int) =
  if i >= j then @(i, v)
  else let val c = byte2int0($A.read<byte>(e, i)) in
    if c < 48 then @(i, v) else if c > 57 then @(i, v)
    else num_at(e, i + 1, j, v * 10 + (c - 48))
  end

(* v - off (at least 0) when there were digits *)
fn put_line_num (out: !$B.builder_v >> $B.builder_v, has: bool, v: int, off: int): void =
  if ~has then bput_v(out, "")
  else if v > off then put_int_v(out, v - off)
  else put_int_v(out, 0)

(* i + k, but at most j *)
fn adv_to {i,j:nat | i < j}{k:pos} (i: int i, k: int k, j: int j): [r:int | i < r; r <= j] int r =
  if i + k <= j then i + k else j

(* e[i, j) with .sats and .dats as .bats and build/ dropped, and, when
   adj, each line=N as line=N-off (at least 0) *)
fun remap_line {le:agz}{i,j:nat | i <= j; j <= 524288} .<j - i>.
  (e: !$A.borrow(byte, le, 524288), i: int i, j: int j, adj: bool, off: int,
   out: !$B.builder_v >> $B.builder_v): void =
  if i >= j then ()
  else let
    var s_c = @[char][5]('.', 's', 'a', 't', 's')
    var d_c = @[char][5]('.', 'd', 'a', 't', 's')
    var b_c = @[char][6]('b', 'u', 'i', 'l', 'd', '/')
    var l_c = @[char][5]('l', 'i', 'n', 'e', '=')
    val ext = (if i + 5 > j then false
               else if lit_at(e, i, 524288, s_c, 5) then true
               else lit_at(e, i, 524288, d_c, 5)): bool
    val bld = (if i + 6 > j then false else lit_at(e, i, 524288, b_c, 6)): bool
    val lin = (if ~adj then false else if i + 5 > j then false
               else lit_at(e, i, 524288, l_c, 5)): bool
  in
    if ext then let
      val () = bput_v(out, ".bats")
    in remap_line(e, adv_to(i, 5, j), j, adj, off, out) end
    else if bld then let
      val () = bput_v(out, "")
    in remap_line(e, adv_to(i, 6, j), j, adj, off, out) end
    else if lin then let
      val () = bput_v(out, "line=")
      val ds = adv_to(i, 5, j)
      val @(ne, v) = num_at(e, ds, j, 0)
      val () = put_line_num(out, ne > ds, v, off)
    in remap_line(e, ne, j, adj, off, out) end
    else let
      val () = put_char_v(out, byte2int0($A.read<byte>(e, i)))
    in remap_line(e, i + 1, j, adj, off, out) end
  end

(* The line e[i, j): as is when keep, else remapped *)
fn emit_line {le:agz}{i,j:nat | i <= j; j <= 524288}
  (e: !$A.borrow(byte, le, 524288), i: int i, j: int j, keep: bool, adj: bool, off: int,
   out: !$B.builder_v >> $B.builder_v): void =
  if keep then copy_to_builder_v(e, i, j, 524288, out)
  else remap_line(e, i, j, adj, off, out)

(* Rust's remap_errors of patsopt's stderr e[i, n), line by line *)
fun remap_errors {le:agz}{i,n:nat | i <= n; n <= 524288} .<n - i>.
  (e: !$A.borrow(byte, le, 524288), i: int i, n: int n, off: int,
   out: !$B.builder_v >> $B.builder_v): void =
  if i >= n then ()
  else let
    val j = line_end_at(e, i, n)
    var t_c = @[char][11]('_', 'b', 'a', 't', 's', '_', 'e', 'n', 't', 'r', 'y')
    var d_c = @[char][5]('.', 'd', 'a', 't', 's')
    val keep = has_lit(e, i, j, t_c, 11)
    val adj = has_lit(e, i, j, d_c, 5)
    val () = emit_line(e, i, j, keep, adj, off, out)
    val () = put_char_v(out, 10)
  in if j >= n then () else remap_errors(e, j + 1, n, off, out) end

(* A failed patsopt of in[0, il): its stderr as Rust prints it,
   "error: patsopt error:" and the lines remapped to the .bats *)
fn report_patsopt {li:agz}
  (in_bv: !$A.borrow(byte, li, 524288), il: int, err: $B.builder_v): void = let
  val off = read_prelude(in_bv, il)
  val @(ea, en) = $B.to_arr(err)
  val @(fz_e, bv_e) = $A.freeze<byte>(ea)
  var out : $B.builder_v = $B.create()
  val () = bput_v(out, "error: patsopt error:\n")
  val () = remap_errors(bv_e, 0, en, off, out)
  val () = put_char_v(out, 10)
  val () = $A.drop<byte>(fz_e, bv_e)
  val () = $A.free<byte>($A.thaw<byte>(fz_e))
in prerr_builder(out) end

(* ============================================================
   What patsopt emits but only cc rejects: a template instance with no
   implementation, a function that captures its environment
   ============================================================ *)

(* What in patsopt's C only cc would reject *)
datatype emitted_flaw =
  | UnresolvedTemplate   (* PMVtmpltcstmat: an instance with no implementation *)
  | CapturingFunction    (* ATSERRORnotenvless: a plain function that captures *)

(* Whether "PMVtmpltcstmat" is at c[i]: patsopt's mark for a template
   instance it found no implementation for, which only cc rejects *)
fn is_unresolved_at {l:agz}{m:pos}
  (c: !$A.borrow(byte, l, m), i: pos_t, max: int m): bool = let
  var mark = @[char][14]('P', 'M', 'V', 't', 'm', 'p', 'l', 't', 'c', 's', 't', 'm', 'a', 't')
in lit_at(c, i, max, mark, 14) end

(* Whether "ATSERRORnotenvless" is at c[i]: patsopt's mark for a lambda
   whose kind is a plain function (FUN) but which captures a variable, so
   it has an environment a plain function cannot carry *)
fn is_capturing_at {l:agz}{m:pos}
  (c: !$A.borrow(byte, l, m), i: pos_t, max: int m): bool = let
  var mark = @[char][18]('A', 'T', 'S', 'E', 'R', 'R', 'O', 'R', 'n', 'o', 't', 'e', 'n', 'v', 'l', 'e', 's', 's')
in lit_at(c, i, max, mark, 18) end

(* Whether "loc0 = " is at c[i]: an instruction's source location
   follows it, in the comment patsopt writes before the instruction *)
fn is_location_at {l:agz}{m:pos}
  (c: !$A.borrow(byte, l, m), i: pos_t, max: int m): bool = let
  var mark = @[char][7]('l', 'o', 'c', '0', ' ', '=', ' ')
in lit_at(c, i, max, mark, 7) end

(* The first flaw in c[i, n), or n when there is none, and which it is;
   whether a source location comes before it, and where the last one
   before it starts (seen and location say so for c[0, i)) *)
fun find_flaw {l:agz}{m:pos}{i,n:nat | i <= n; n < m}{k:nat | k <= n} .<n - i>.
  (c: !$A.borrow(byte, l, m), i: int i, n: int n, max: int m, seen: bool, location: int k)
  : [r,q:nat | r <= n; q <= n] @(int r, emitted_flaw, bool, int q) =
  if i >= n then @(n, UnresolvedTemplate(), seen, location)
  else let
    val b = byte2int0($A.read<byte>(c, i))
  in
    if b = 80 && is_unresolved_at(c, i, max) then @(i, UnresolvedTemplate(), seen, location)
    else if b = 65 && is_capturing_at(c, i, max) then @(i, CapturingFunction(), seen, location)
    else if b = 108 && is_location_at(c, i, max) then
      find_flaw(c, i + 1, n, max, true, (if i + 7 <= n then i + 7 else n): [q:nat | q <= n] int q)
    else find_flaw(c, i + 1, n, max, seen, location)
  end

(* The first index in c[i, n) holding byte b, or n *)
fun index_of_byte {l:agz}{m:pos}{i,n:nat | i <= n; n < m} .<n - i>.
  (c: !$A.borrow(byte, l, m), i: int i, n: int n, b: int): [r:nat | i <= r; r <= n] int r =
  if i >= n then n
  else if byte2int0($A.read<byte>(c, i)) = b then i
  else index_of_byte(c, i + 1, n, b)

(* The end of the template name at c[i, n): its first '<', '(' or ')',
   or n *)
fun template_name_end {l:agz}{m:pos}{i,n:nat | i <= n; n < m} .<n - i>.
  (c: !$A.borrow(byte, l, m), i: int i, n: int n): [r:nat | i <= r; r <= n] int r =
  if i >= n then n
  else let
    val b = byte2int0($A.read<byte>(c, i))
  in
    if b = 60 || b = 40 || b = 41 then i
    else template_name_end(c, i + 1, n)
  end

(* The end of the instance at c[i, n): the ')' that closes the "(" it
   follows (depth counts the '(' opened since), or n *)
fun instance_end {l:agz}{m:pos}{i,n:nat | i <= n; n < m} .<n - i>.
  (c: !$A.borrow(byte, l, m), i: int i, n: int n, depth: int): [r:nat | i <= r; r <= n] int r =
  if i >= n then n
  else let
    val b = byte2int0($A.read<byte>(c, i))
  in
    if b = 40 then instance_end(c, i + 1, n, depth + 1)
    else if b = 41 then (if depth <= 0 then i else instance_end(c, i + 1, n, depth - 1))
    else instance_end(c, i + 1, n, depth)
  end

(* " --> " and the location c[s, e) (patsopt's "<path>.dats: <offset>
   (line=L, offs=O) -- ..."), as the .bats location: the path's .dats
   as .bats and build/ dropped, each line=L past the prelude's off
   lines (as patsopt's errors are reported) *)
fn put_location {l:agz}{m:pos}{s:nat}
  (c: !$A.borrow(byte, l, m), s: int s, e: int, max: int m, off: int,
   out: !$B.builder_v >> $B.builder_v): void = let
  var text : $B.builder_v = $B.create()
  val () = copy_to_builder_v(c, s, e, max, text)
  val @(text_array, text_len) = $B.to_arr(text)
  val @(fz_text, bv_text) = $A.freeze<byte>(text_array)
  val () = bput_v(out, " --> ")
  val () = remap_line(bv_text, 0, text_len, true, off, out)
  val () = put_char_v(out, 10)
  val () = $A.drop<byte>(fz_text, bv_text)
in $A.free<byte>($A.thaw<byte>(fz_text)) end

(* The error for the unresolved instance at c[at, n): the template's
   name, the instance as patsopt wrote it (at most 400 bytes of it),
   and, when seen, the .bats location of the instruction that uses it,
   whose text starts at c[location] *)
fn report_unresolved {l:agz}{m:pos}{at,n:nat | at <= n; n < m}{q:nat | q <= n}
  (c: !$A.borrow(byte, l, m), at: int at, n: int n, max: int m,
   seen: bool, location: int q, off: int): void = let
  val open_paren = index_of_byte(c, at, n, 40)
  val name_start = (if open_paren < n then open_paren + 1 else n): [s:nat | s <= n] int s
  val name_end = template_name_end(c, name_start, n)
  val whole_end = instance_end(c, name_start, n, 0)
  val shown_end = (if whole_end - name_start > 400 then name_start + 400 else whole_end): int
  var out : $B.builder_v = $B.create()
  val () = bput_v(out, "error: template '")
  val () = copy_to_builder_v(c, name_start, name_end, max, out)
  val () = bput_v(out, "' has no implementation for the instance ")
  val () = copy_to_builder_v(c, name_start, shown_end, max, out)
  val () = bput_v(out, "; implement it for that type where the instance can see it\n")
  val () = (if seen then put_location(c, location, index_of_byte(c, location, n, 10), max, off, out)
            else ()): void
in prerr_builder(out) end

(* The error for a capturing function at c[at, n): what it is, and, when
   seen, the .bats location of the lambda, whose text starts at
   c[location] *)
fn report_capturing {l:agz}{m:pos}{n:nat | n < m}{q:nat | q <= n}
  (c: !$A.borrow(byte, l, m), n: int n, max: int m, seen: bool, location: int q, off: int): void = let
  var out : $B.builder_v = $B.create()
  val () = bput_v(out, "error: a lambda whose kind is a plain function (=<fun1>, or a context that makes it one) captures a variable, which a plain function cannot carry; pass what it captures as an argument, or make it a linear closure (llam)\n")
  val () = (if seen then put_location(c, location, index_of_byte(c, location, n, 10), max, off, out)
            else ()): void
in prerr_builder(out) end

(* After patsopt made the C out[0, ol) of in[0, il) (paths), whether it
   holds what only cc would reject (a template instance with no
   implementation, a plain function that captures): the first one is
   reported, and the build fails, at check as at build (check runs no
   cc). 0 when there is none, else 1 *)



implement check_emitted_flaws {lo,li} (out_bv, in_bv, il) =
  case+ read_whole(out_bv, 524288) of
  | ~whole_err(_) => 0
  | ~whole_ok(ar, piece, size, n) => let
      val @(fz_c, bv_c) = $A.freeze<byte>(piece)
      val @(at, flaw, seen, location) = find_flaw(bv_c, 0, n, size, false, 0)
      val rc = (if at >= n then 0 else let
          val off = read_prelude(in_bv, il)
          val () = (case+ flaw of
            | UnresolvedTemplate() => report_unresolved(bv_c, at, n, size, seen, location, off)
            | CapturingFunction() => report_capturing(bv_c, n, size, seen, location, off)): void
          val () = set_build_err()
        in 1 end): int
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = whole_free(ar, $A.thaw<byte>(fz_c))
    in rc end

(* ============================================================
   An optional cap on every patsopt run (BATS_PATSOPT_TIMEOUT_S,
   BATS_PATSOPT_MEM_MB)
   ============================================================ *)

(* The GMP build of ATS2's constraint solver can run away in time and in
   memory on a proof the machine-integer solver answers at once (one
   function of quire's library.bats grew past 6.4 GB in 14 minutes, an
   earlier run was killed by the system at 9.9 GB without a module being
   named: bats-lang/quire#594). With BATS_PATSOPT_TIMEOUT_S set to a
   number of seconds (wall clock) and/or BATS_PATSOPT_MEM_MB set to a
   number of megabytes (the address space), every patsopt run
   (patsopt_only, the one place patsopt is started) is held to it, and a
   run the cap ends fails the build naming its module, the cap and how to
   raise it, with its own exit status: 124 for the time, 125 for the
   memory. Unset or empty, nothing is read, made or said, as for
   BATS_SLOTS; anything else is said and ignored.

   This is a resource cap on an external process, not a runtime check of
   the program's safety (CLAUDE.md): the types prove nothing about how
   long or how large patsopt's solver gets, so bats bounds the process.

   How, with what is portable (sh and kill, which POSIX has; there is no
   timeout(1) on macOS, and the process package has no setrlimit or kill):
   a capped patsopt is started by sh -c, which lowers its own address
   space limit (ulimit -v, in KiB) and runs patsopt under it, and, for the
   time, keeps patsopt as its child and ends it with SIGALRM after the
   seconds (a sleep, killed when patsopt ends first), which it tells from
   any other death by the status 128 + 14 that wait gives (POSIX gives
   SIGALRM the number 14). The memory cap has no such sign, since
   RLIMIT_AS only makes allocations fail: a patsopt that fails with a
   signal under it, or whose stderr says its allocator or GMP's failed
   ("ats_malloc_gc", "Cannot allocate memory"), is the memory
   cap's. Where sh cannot lower the limit (ulimit -v is refused, as on
   systems that do not enforce RLIMIT_AS), that is said once and patsopt
   runs without the memory cap. *)

(* The count the environment variable name holds: 0 when it is not set
   or empty, -1 when it is not a number from 1 up (or has over 9 digits),
   else the number *)
fn env_count {sn:nat | sn < $B.BUILDER_CAP} (name: string sn): int = let
  var b : $B.builder_v = $B.create()
  val set = env_value(name, b)
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  fun digits {l:agz}{i:nat | i <= 524288} .<524288 - i>.
    (bv: !$A.borrow(byte, l, 524288), i: int i, k: int, acc: int): int =
    if i >= 524288 then acc
    else if i >= k then acc
    else let
      val c = byte2int0($A.read<byte>(bv, i))
    in
      if c < 48 then ~1
      else if c > 57 then ~1
      else if acc > 99999999 then ~1
      else digits(bv, i + 1, k, acc * 10 + (c - 48))
    end
  val n = (if set then digits(bv, 0, k, 0) else 0): int
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  if ~set then 0
  else if n < 1 then ~1
  else n
end

(* Whether this system's sh can limit its address space to mb megabytes *)
fn memory_limitable (mb: int): bool = let
  val exec = str_to_path_arr("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 : $B.builder_v = $B.create()
  val () = bput_v(b1, "sh")
  var b2 : $B.builder_v = $B.create()
  val () = bput_v(b2, "-c")
  var b3 : $B.builder_v = $B.create()
  val () = bput_v(b3, "ulimit -v $(($1 * 1024)) 2>/dev/null")
  var b4 : $B.builder_v = $B.create()
  val () = bput_v(b4, "sh")
  var b5 : $B.builder_v = $B.create()
  val () = put_int_v(b5, mb)
  val rc = run_cmd(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_cons(mk_arg(b4),
    $L.list_vt_cons(mk_arg(b5), $L.list_vt_nil()))))))
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in rc = 0 end

(* Reads the two variables, once per process, into g_cap_secs and
   g_cap_mb (0: no cap) *)
fn caps_read (): void =
  if !g_cap_read then () else let
    val () = !g_cap_read := true
    val t = env_count("BATS_PATSOPT_TIMEOUT_S")
    val m = env_count("BATS_PATSOPT_MEM_MB")
    val () = (if t < 0 then
        prerr! ("warning: BATS_PATSOPT_TIMEOUT_S is not a number of seconds from 1 up, so patsopt runs without a time cap\n")
      else !g_cap_secs := t): void
    val () = (if m < 0 then
        prerr! ("warning: BATS_PATSOPT_MEM_MB is not a number of megabytes from 1 up, so patsopt runs without a memory cap\n")
      else if m = 0 then ()
      else if memory_limitable(m) then !g_cap_mb := m
      else
        prerr! ("warning: BATS_PATSOPT_MEM_MB is set, but this system's sh cannot limit memory (ulimit -v), so patsopt runs without a memory cap\n")): void
  in end

(* Whether e[i] starts what ATS's allocator says when memory runs out *)
fn is_ats_malloc_at {l:agz}{n:pos}
  (e: !$A.borrow(byte, l, n), i: pos_t, max: int n): bool = let
  var mark = @[char][13]('a', 't', 's', '_', 'm', 'a', 'l', 'l', 'o', 'c', '_', 'g', 'c')
in lit_at(e, i, max, mark, 13) end

(* Whether e[i] starts what GMP says when memory runs out *)
fn is_gmp_alloc_at {l:agz}{n:pos}
  (e: !$A.borrow(byte, l, n), i: pos_t, max: int n): bool = let
  var mark = @[char][22]('C', 'a', 'n', 'n', 'o', 't', ' ', 'a', 'l', 'l', 'o', 'c', 'a', 't', 'e', ' ', 'm', 'e', 'm', 'o', 'r', 'y')
in lit_at(e, i, max, mark, 22) end

(* Whether patsopt's stderr err says its allocator or GMP's failed (only
   looked for when wanted), and the same stderr again *)
fn memory_said (wanted: bool, err: $B.builder_v): @(bool, $B.builder_v) =
  if ~wanted then @(false, err) else let
  val @(ea, en) = $B.to_arr(err)
  val @(fz, bv) = $A.freeze<byte>(ea)
  fun scan {l:agz}{i:nat | i <= 524288} .<524288 - i>.
    (bv: !$A.borrow(byte, l, 524288), i: int i, n: int): bool =
    if i >= 524288 then false
    else if i >= n then false
    else if is_ats_malloc_at(bv, i, 524288) then true
    else if is_gmp_alloc_at(bv, i, 524288) then true
    else scan(bv, i + 1, n)
  val said = scan(bv, 0, en)
  var again : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, 0, en, 524288, again)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(said, again) end

(* The module whose .dats is in[0, in_len - 1) (build/src/m.dats) as its
   source is named, src/m.bats, appended to out *)
fn module_put {li:agz}
  (in_bv: !$A.borrow(byte, li, 524288), in_len: int,
   out: !$B.builder_v >> $B.builder_v): void = let
  val stop = g1ofg0(in_len - 1)
  val built = (peek(in_bv, 0, 524288) = 98 && peek(in_bv, 1, 524288) = 117
    && peek(in_bv, 2, 524288) = 105 && peek(in_bv, 3, 524288) = 108
    && peek(in_bv, 4, 524288) = 100 && peek(in_bv, 5, 524288) = 47): bool
  val start = g1ofg0((if built then 6 else 0): int)
  val dats = (stop >= start + 5 && peek(in_bv, stop - 5, 524288) = 46
    && peek(in_bv, stop - 4, 524288) = 100 && peek(in_bv, stop - 3, 524288) = 97
    && peek(in_bv, stop - 2, 524288) = 116 && peek(in_bv, stop - 1, 524288) = 115): bool
  val () = copy_to_builder_v(in_bv, start, (if dats then stop - 5 else stop), 524288, out)
in (if dats then bput_v(out, ".bats") else ()) end

(* A run the cap ended, reported (the time cap's when time is true, else
   the memory cap's), and the build failed with the cap's own status *)
fn cap_report {li:agz}
  (time: bool, in_bv: !$A.borrow(byte, li, 524288), in_len: int): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: patsopt on ")
  val () = module_put(in_bv, in_len, m)
  val () = (if time then let
      val () = bput_v(m, " was stopped by the time cap: it did not finish within BATS_PATSOPT_TIMEOUT_S=")
      val () = put_int_v(m, !g_cap_secs)
    in bput_v(m, " seconds. Raise BATS_PATSOPT_TIMEOUT_S, or unset it for no time cap.\n") end
    else let
      val () = bput_v(m, " was stopped by the memory cap: it ran out of memory under BATS_PATSOPT_MEM_MB=")
      val () = put_int_v(m, !g_cap_mb)
    in bput_v(m, " megabytes of address space. Raise BATS_PATSOPT_MEM_MB, or unset it for no memory cap.\n") end)
  val () = prerr_builder(m)
  val () = !g_cap_exit := (if time then 124 else 125)
in set_build_err() end

(* ============================================================
   A patsopt that fails and prints nothing (bats-lang/bats#301): on a full
   disk its own messages fail with ENOSPC, so its stderr is empty, and
   "error: patsopt error:" with no text used to be all that was said.
   What bats says then: the module, the status, and what patsopt wrote to
   stdout (its first 4096 bytes), and, as a fact and not a verdict, the free
   space of the build's file system: "(N MB free in build; if that is near
   0 the disk is full)". No threshold decides that the disk is full: cargo,
   rustc and ld report the failed write's OS error, and apt and dpkg compare
   an estimate of the space needed, none a fixed number of megabytes
   (research in the comment of bats#313). Without df's answer the clause is
   left out.
   patsopt's stdout is a file in build/ (truncated by each run, so it is
   not removed): a pipe would block patsopt once it wrote more than a
   pipe holds, while bats was still reading its stderr. Nothing else of
   the platform says free space (the file package has no statvfs), so
   the free space is df -Pk's Available column, found from the Capacity
   column after it (df runs only on this failure, never on a build that
   succeeds).
   ============================================================ *)

(* What patsopt's stdout is kept in *)
fn stdout_path_arr (): [l:agz] $A.arr(byte, l, 524288) =
  str_to_path_arr("build/.patsopt_stdout")

(* The stdout file for a run, truncated, as a stream for the child: the
   flag says whether it could be made (else patsopt's stdout is /dev/null) *)
fn stdout_config(): @(bool, $P.stream_config(false)) = let
  val a = stdout_path_arr()
  val @(fz, bv) = $A.freeze<byte>(a)
  val r = file_open_path(bv, $F.WriteOnly(), $F.CreateOrTruncate(), 420)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ r of
  | ~$R.ok(fd) => @(true, $P.inherit_fd(fd))
  | ~$R.err(_) => @(false, $P.dev_null())
end

(* The first 4096 bytes of the open file fd appended to out; whether the
   file is longer (consumes r) *)
fn stdout_fd_read (r: $R.result($F.fd, $F.io_error), out: !$B.builder_v >> $B.builder_v): bool =
  case+ r of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val size = (case+ $F.fd_size(fd) of
        | ~$R.ok(s) => s | ~$R.err(_) => 0): int
      val buf = $A.alloc<byte>(4096)
      val k = (case+ $F.file_read(fd, buf, 4096) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 4096] int k
      val @(fz, bv) = $A.freeze<byte>(buf)
      val () = copy_to_builder_v(bv, 0, k, 4096, out)
      val () = $A.drop<byte>(fz, bv)
      val () = $A.free<byte>($A.thaw<byte>(fz))
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in size > 4096 end

(* patsopt's stdout of the run (its first 4096 bytes, and whether it wrote
   more), when the stdout file could be made (ok) *)
fn stdout_take (ok: bool): @(bool, $B.builder_v) = let
  var ob : $B.builder_v = $B.create()
  val a = stdout_path_arr()
  val @(fz, bv) = $A.freeze<byte>(a)
  val cut = (if ok then stdout_fd_read(file_open_path(bv, $F.ReadOnly(), $F.OpenExisting(), 0), ob)
    else false): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(cut, ob) end

(* Whether e[i] is a space or a tab *)
fn is_blank_byte (c: int): bool = (c = 32) || (c = 9)

(* The position after the blanks from i, at most n *)
fun blanks_end {l:agz}{i,n:nat | i <= n; n <= 4096} .<n - i>.
  (e: !$A.borrow(byte, l, 4096), i: int i, n: int n): [r:nat | i <= r; r <= n] int r =
  if i >= n then i
  else if is_blank_byte(byte2int0($A.read<byte>(e, i))) then blanks_end(e, i + 1, n)
  else i

(* The position of the first blank, newline or n from i *)
fun token_end {l:agz}{i,n:nat | i <= n; n <= 4096} .<n - i>.
  (e: !$A.borrow(byte, l, 4096), i: int i, n: int n): [r:nat | i <= r; r <= n] int r =
  if i >= n then i
  else let val c = byte2int0($A.read<byte>(e, i)) in
    if is_blank_byte(c) || (c = 10) then i else token_end(e, i + 1, n)
  end

(* The position of the first newline from i, or n *)
fun newline_at {l:agz}{i,n:nat | i <= n; n <= 4096} .<n - i>.
  (e: !$A.borrow(byte, l, 4096), i: int i, n: int n): [r:nat | i <= r; r <= n] int r =
  if i >= n then i
  else if byte2int0($A.read<byte>(e, i)) = 10 then i
  else newline_at(e, i + 1, n)

(* The decimal number of e[i, j); -1 when it holds a byte that is no digit,
   or when it has more than 9 digits (it would not fit an int: it is no
   number here, never a smaller one) *)
fun digits_at {l:agz}{i,j:nat | i <= j; j <= 4096} .<j - i>.
  (e: !$A.borrow(byte, l, 4096), i: int i, j: int j, v: int): int =
  if i >= j then v
  else let val c = byte2int0($A.read<byte>(e, i)) in
    if c < 48 then ~1
    else if c > 57 then ~1
    else if v >= 100000000 then ~1
    else digits_at(e, i + 1, j, v * 10 + (c - 48))
  end

(* The end of e[0, n) without the blanks and newlines at its end *)
fun trimmed_end {l:agz}{n:nat | n <= 4096} .<n>.
  (e: !$A.borrow(byte, l, 4096), n: int n): [r:nat | r <= n] int r =
  if n <= 0 then 0
  else let val c = byte2int0($A.read<byte>(e, n - 1)) in
    if is_blank_byte(c) || (c = 10) then trimmed_end(e, n - 1) else n
  end

(* The start of the last line of e[0, n): the position after the last
   newline from i on (s is the start so far) *)
fun last_line_from {l:agz}{i,n:nat | i <= n; n <= 4096}{s:nat | s <= n} .<n - i>.
  (e: !$A.borrow(byte, l, 4096), i: int i, n: int n, s: int s): [r:nat | r <= n] int r =
  if i >= n then s
  else if byte2int0($A.read<byte>(e, i)) = 10 then last_line_from(e, i + 1, n, i + 1)
  else last_line_from(e, i + 1, n, s)

(* The number just before the first token of e[i, n) that is digits and a
   percent sign; the previous token is e[ps, pe). -1 when there is no such
   token, or what comes before it is no number *)
fun number_before_percent {l:agz}{i,n,ps,pe:nat | i <= n; n <= 4096; ps <= pe; pe <= n} .<n - i>.
  (e: !$A.borrow(byte, l, 4096), i: int i, n: int n, ps: int ps, pe: int pe): int = let
  val a = blanks_end(e, i, n)
in
  if a >= n then ~1
  else let
    val b = token_end(e, a, n)
  in
    if b <= a then ~1
    else if b - a >= 2 && byte2int0($A.read<byte>(e, b - 1)) = 37 && digits_at(e, a, b - 1, 0) >= 0 then
      (if pe > ps then digits_at(e, ps, pe, 0) else ~1)
    else number_before_percent(e, b, n, a, b)
  end
end

(* The free space (1024-byte blocks) in df -Pk's output e[0, n): the
   number immediately before the first token of its last line that is
   digits followed by a percent sign (the Capacity column), so that a
   blank in the file system's name, which shifts the columns from the
   left, does not matter (POSIX: Filesystem, 1024-blocks, Used, Available,
   Capacity, Mounted on). -1 when there is no such token *)
fn df_available {l:agz}{n:nat | n <= 4096} (e: !$A.borrow(byte, l, 4096), n: int n): int = let
  val m = trimmed_end(e, n)
  val s = last_line_from(e, 0, m, 0)
in number_before_percent(e, s, m, s, s) end

(* The free space in KiB of build/ (df -Pk build's Available column), or
   -1 when df gave none *)
fn disk_free_kib (): int = let
  val exec = str_to_path_arr("df")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 : $B.builder_v = $B.create()
  val () = bput_v(b1, "df")
  var b2 : $B.builder_v = $B.create()
  val () = bput_v(b2, "-Pk")
  var b3 : $B.builder_v = $B.create()
  val () = bput_v(b3, "build")
  val out = $A.alloc<byte>(4096)
  val @(rc, k) = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))), out)
  val @(fz_o, bv_o) = $A.freeze<byte>(out)
  val v = (if rc = 0 then df_available(bv_o, k) else ~1): int
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in v end

(* A patsopt run that failed and printed nothing on stderr: the module,
   the status, the free space of build/ when df said it, and stdout
   (consumes out) *)
fn report_silent {li:agz}
  (ec: int, in_bv: !$A.borrow(byte, li, 524288), in_len: int,
   out: $B.builder_v, out_cut: bool): void = let
  val free_kib = disk_free_kib()
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "error: ")
  val () = bput_v(m, "patsopt on ")
  val () = module_put(in_bv, in_len, m)
  val () = bput_v(m, " failed with ")
  val () = (if ec >= 0 then let
      val () = bput_v(m, "status ")
    in put_int_v(m, ec) end
    else bput_v(m, "an unknown status"))
  val () = bput_v(m, " and printed nothing")
  val () = (if free_kib >= 0 then let
      val () = bput_v(m, " (")
      val () = put_int_v(m, free_kib / 1024)
    in bput_v(m, " MB free in build; if that is near 0 the disk is full)") end
    else ())
  val () = (if $B.length(out) > 0 then let
      val () = bput_v(m, "; stdout was: ")
      val () = append_builder(m, out)
      val () = (if out_cut then bput_v(m, " [cut]") else ())
      val () = put_newline_v(m)
    in () end
    else let
      val () = $B.builder_free(out)
      val () = bput_v(m, ".")
    in put_newline_v(m) end)
in prerr_builder(m) end

(* patsopt's exit code ec, reported as Rust reports a failure. Its stderr
   err is consumed, and out (its stdout, with whether it was cut) too.
   A failure that printed nothing is said as such, never as a patsopt
   error with no text *)
fn finish_patsopt {li:agz}
  (ec: int, in_bv: !$A.borrow(byte, li, 524288), in_len: int,
   err: $B.builder_v, out: $B.builder_v, out_cut: bool): int =
  if ec <> 0 then let
    val silent = ($B.length(err) = 0): bool
  in
    if silent then let
      val () = $B.builder_free(err)
      val () = report_silent(ec, in_bv, in_len, out, out_cut)
      val () = set_build_err()
    in ec end
    else let
      val () = $B.builder_free(out)
      val () = report_patsopt(in_bv, in_len - 1, err)
      val () = set_build_err()
    in ec end
  end
  else let
    val () = $B.builder_free(err)
    val () = $B.builder_free(out)
  in 0 end

(* The caps, read from the environment once: seconds (0: none) and
   megabytes (0: none) *)


implement cap_secs_now () = let val () = caps_read() in !g_cap_secs end



implement cap_mb_now () = let val () = caps_read() in !g_cap_mb end

(* A patsopt run (the check memo's --depgen too) the time cap (true) or
   the memory cap ended: said, and the build fails with the cap's status *)



implement cap_stopped (time, in_bv, in_len) = cap_report(time, in_bv, in_len)

(* patsopt run on the .dats in[0, in_len) (a NUL-terminated path),
   writing its C to out[0, out_len): 0, or patsopt's failure, reported,
   its output removed. What only cc would reject in the C is not looked
   for here (check_emitted_flaws): run_patsopt, in cache.bats, runs both. *)





(* rm -f the NUL-terminated path out[0, len - 1) *)


implement remove_output {lo} (out_bv, out_len) = let
  val exec = str_to_path_arr("rm")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "rm")
  var b2 = $B.create()
  val () = bput_v(b2, "-f")
  var b3 = $B.create()
  val () = copy_to_builder_v(out_bv, 0, out_len - 1, 524288, b3)
  val _ = run_cmd(bv_x, $L.list_vt_cons(mk_arg(b1), $L.list_vt_cons(mk_arg(b2),
    $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))))
  val () = $A.drop<byte>(fz_x, bv_x)
in $A.free<byte>($A.thaw<byte>(fz_x)) end

(* After a failure, as Rust's build stops at its first error, nothing
   more runs. A failed run's output (patsopt writes its #error line
   there) is removed, so it is not taken for fresh next time: the Rust
   bats records a module in its build cache only when patsopt succeeds *)
implement patsopt_only(ph, phlen, out_bv, out_len, in_bv, in_len) =
  if has_build_err() then 1 else let
  val () = caps_read()
  val secs = !g_cap_secs
  val mb = !g_cap_mb
  val capped = (secs > 0 || mb > 0): bool
  (* uncapped, patsopt itself is started; capped, sh is, with patsopt as
     its first argument (see the cap's comment above) *)
  var exec_b : $B.builder_v = $B.create()
  val () = (if capped then bput_v(exec_b, "sh") else let
      val () = copy_to_builder_v(ph, 0, phlen, 512, exec_b)
    in bput_v(exec_b, "/bin/patsopt") end)
  val () = put_char_v(exec_b, 0)
  val @(exec_a, _) = $B.to_arr(exec_b)
  val @(fz_exec, bv_exec) = $A.freeze<byte>(exec_a)
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
  val rest = $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3),
    $L.list_vt_cons(mk_arg(b4), $L.list_vt_cons(mk_arg(b5),
    $L.list_vt_cons(mk_arg(b6), $L.list_vt_cons(mk_arg(b7),
    $L.list_vt_cons(mk_arg(b8), $L.list_vt_cons(mk_arg(b9),
    $L.list_vt_cons(mk_arg(b10), $L.list_vt_cons(mk_arg(b11),
    $L.list_vt_nil())))))))))): $L.listv($P.arg_entry)
  val argv = (if capped then let
      (* sh -c <script> sh <MB or 0> <seconds or 0> <patsopt> <its arguments> *)
      var w1 : $B.builder_v = $B.create()
      val () = bput_v(w1, "sh")
      var w2 : $B.builder_v = $B.create()
      val () = bput_v(w2, "-c")
      var w3 : $B.builder_v = $B.create()
      val () = bput_v(w3, "mb=$1; secs=$2; shift 2\n[ \"$mb\" = 0 ] || ulimit -v $((mb * 1024)) 2>/dev/null\n[ \"$secs\" = 0 ] && exec \"$@\"\n\"$@\" &\npid=$!\n( trap 'kill $sp 2>/dev/null; exit 0' TERM; sleep \"$secs\" & sp=$!; wait $sp; kill -s ALRM $pid 2>/dev/null ) >/dev/null 2>&1 &\nwd=$!\nwait $pid\nrc=$?\nkill $wd 2>/dev/null\nwait $wd 2>/dev/null\n[ $rc -eq 142 ] && exit 124\n[ $rc -eq 124 ] && exit 1\nexit $rc\n")
      var w4 : $B.builder_v = $B.create()
      val () = bput_v(w4, "sh")
      var w5 : $B.builder_v = $B.create()
      val () = put_int_v(w5, mb)
      var w6 : $B.builder_v = $B.create()
      val () = put_int_v(w6, secs)
      var w7 : $B.builder_v = $B.create()
      val () = copy_to_builder_v(ph, 0, phlen, 512, w7)
      val () = bput_v(w7, "/bin/patsopt")
    in $L.list_vt_cons(mk_arg(w1), $L.list_vt_cons(mk_arg(w2),
        $L.list_vt_cons(mk_arg(w3), $L.list_vt_cons(mk_arg(w4),
        $L.list_vt_cons(mk_arg(w5), $L.list_vt_cons(mk_arg(w6),
        $L.list_vt_cons(mk_arg(w7), rest))))))) end
    else let
      var b1 : $B.builder_v = $B.create()
      val () = bput_v(b1, "patsopt")
    in $L.list_vt_cons(mk_arg(b1), rest) end): $L.listv($P.arg_entry)
  var envp_b = $B.create()
  val () = bput_v(envp_b, "PATSHOME=")
  val () = copy_to_builder_v(ph, 0, phlen, 512, envp_b)
  val envp = $L.list_vt_cons(mk_arg(envp_b), $L.list_vt_nil())
  val _verbose = if is_verbose() then 1 else 0
  val () = (if $AR.gt_int_int(_verbose, 0) then let
    val () = print! ("  + patsopt -o ")
    val () = print_borrow(out_bv, 0, out_len, 524288)
    val () = print! (" -d ")
    val () = print_borrow(in_bv, 0, in_len, 524288)
  in print_newline() end else ())
  val @(out_ok, out_cfg) = stdout_config()
  val sr = spawn_child_with(bv_exec, argv, envp,
    $P.dev_null(), out_cfg, $P.pipe_new())
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
      var eb : $B.builder_v = $B.create()
      val () = drain_fd(err_fd, eb, 0)
      val ecr = $F.file_close(err_fd)
      val () = $R.discard<int><$F.io_error>(ecr)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
      (* the time cap ended it: sh's status 124 (a patsopt that exits 124
         itself is made 1 there); the memory cap: it failed with a signal
         (ec < 0 direct, over 128 through sh) or said its allocator failed *)
      val @(out_cut, ob) = stdout_take(out_ok)
      val time_hit = (secs > 0 && ec = 124): bool
      val signalled = (ec < 0 || ec > 128): bool
      val @(said, eb2) = memory_said(mb > 0 && ec <> 0 && ~time_hit && ~signalled, eb)
      val mem_hit = (mb > 0 && ec <> 0 && ~time_hit && (signalled || said)): bool
      val rc = (if time_hit then let
          val () = $B.builder_free(eb2)
          val () = $B.builder_free(ob)
          val () = cap_report(true, in_bv, in_len)
        in 1 end
        else if mem_hit then let
          val () = $B.builder_free(eb2)
          val () = $B.builder_free(ob)
          val () = cap_report(false, in_bv, in_len)
        in 1 end
        else finish_patsopt(ec, in_bv, in_len, eb2, ob, out_cut)): int
      val () = (if rc <> 0 then remove_output(out_bv, out_len) else ())
    in rc end
  | ~$R.err(_) => ~1
end







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
  val opt_args: $L.listv($P.arg_entry) = (if is_release(rel) then let
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
  val () = key_drop(out_bv)
  val _verbose = if is_verbose() then 1 else 0
  val () = (if $AR.gt_int_int(_verbose, 0) then let
    val () = print! ("  + cc -c -o ")
    val () = print_borrow(out_bv, 0, out_len, 524288)
    val () = print! (" ")
    val () = print_borrow(in_bv, 0, in_len, 524288)
  in print_newline() end else ())
  val sr = spawn_child(bv_exec, argv,
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
      val () = $R.discard<int><$F.io_error>(ecr)
      val wr = $P.child_wait(child)
      val ec = (case+ wr of
        | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
    in
      if ec <> 0 then let
        val @(fz_eb2, bv_eb2) = $A.freeze<byte>(eb)
        val () = print_borrow(bv_eb2, 0, elen, 65536)
        val () = $A.drop<byte>(fz_eb2, bv_eb2)
        val () = $A.free<byte>($A.thaw<byte>(fz_eb2))
      in ec end
      else let
        val () = $A.free<byte>(eb)
        val () = native_object_record(rel, out_bv, in_bv)
      in 0 end
    end
  | ~$R.err(_) => ~1
end

(* ============================================================
   The machine's slots (bats-lang/bats#252)
   ============================================================ *)

(* A limit on heavy bats work across the machine, for a machine shared
   by several checkouts or agents (two worktrees are two projects, so
   the project's lock does not keep their builds apart). Opt-in: with
   BATS_SLOTS set to a number from 1 to 64, check, build, test and run's
   build each hold one of that many slots, flock(2) on
   <dir>/slot-<i>.lock in BATS_LOCK_DIR (else ~/.cache/bats), as gen-pwa
   test holds PWA_TEST_SLOTS of PWA_TEST_LOCK_DIR: pointing both at one
   directory makes one pool, so a build and an e2e run take turns too.
   The kernel releases a slot when bats ends however it ends, so none is
   left held by a bats that is gone. Unset or empty, nothing is read or
   written and nothing is said. *)

(* The commands that take a slot, and the word each is noted by *)



(* A machine slot: held (its file, open and locked, and its number), the
   parent's (a bats that holds one started this one, BATS_SLOT_HELD), or
   none (BATS_SLOTS unset, or the slot could not be taken, which is
   said) *)









(* BATS_SLOTS: 0 when it is not set or empty, -1 when it is not a number
   from 1 up, else the number, at most 64 *)
fn slots_wanted (): int = let
  var b : $B.builder_v = $B.create()
  val set = env_value("BATS_SLOTS", b)
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  fun digits {l:agz}{i:nat | i <= 524288} .<524288 - i>.
    (bv: !$A.borrow(byte, l, 524288), i: int i, k: int, acc: int): int =
    if i >= 524288 then acc
    else if i >= k then acc
    else let
      val c = byte2int0($A.read<byte>(bv, i))
    in
      if c < 48 then ~1
      else if c > 57 then ~1
      else digits(bv, i + 1, k, (if acc > 64 then 65 else acc * 10 + (c - 48)))
    end
  val n = (if set then digits(bv, 0, k, 0) else 0): int
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  if ~set then 0
  else if n < 1 then ~1
  else if n > 64 then 64
  else n
end

(* Opens the file at the path b holds (b is consumed) *)
fn open_built (b: $B.builder_v, acc: $F.access, how: $F.opening): $R.result($F.fd, $F.io_error) = let
  var p = b
  val () = put_char_v(p, 0)
  val @(pa, _) = $B.to_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val r = file_open_path(bv_p, acc, how, 420)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in r end

(* What trying slot i found *)
datavtype slot_found =
  | SlotTaken of $F.fd
  | SlotBusy
  | SlotUnopenable   (* its file cannot be opened *)
  | SlotUnlockable   (* it opens, but its file system has no locks *)

fn slot_try (i: int, wait: $F.lock_wait): slot_found = let
  var p : $B.builder_v = $B.create()
  val () = slot_path(i, p)
in
  case+ open_built(p, $F.ReadWrite(), $F.CreateOrOpen()) of
  | ~$R.err(_) => SlotUnopenable()
  | ~$R.ok(fd) =>
    (case+ $F.fd_lock(fd, $F.LockExclusive(), wait) of
    | ~$R.ok(_) => SlotTaken(fd)
    | ~$R.err(e) => let
        val busy = (case+ e of $F.WouldBlock() => true | _ => false): bool
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in if busy then SlotBusy() else SlotUnlockable() end)
end

(* The first free slot of i to n - 1, without waiting, and its number *)
fun slot_free {i,n:nat} .<max(n - i, 0)>. (i: int i, n: int n): @(slot_found, int) =
  if i >= n then @(SlotBusy(), 0)
  else (case+ slot_try(i, $F.LockFailsAtOnce()) of
    | ~SlotBusy() => slot_free(i + 1, n)
    | ~SlotTaken(fd) => @(SlotTaken(fd), i)
    | ~SlotUnopenable() => @(SlotUnopenable(), i)
    | ~SlotUnlockable() => @(SlotUnlockable(), i))

(* Writes the bytes b holds (b is consumed) at the start of the file at
   the path p holds (p is consumed), over what was there *)
fn note_write (p: $B.builder_v, b: $B.builder_v): void =
  case+ open_built(p, $F.WriteOnly(), $F.OpenExisting()) of
  | ~$R.err(_) => $B.builder_free(b)
  | ~$R.ok(fd) => let
      val bw = $F.buf_writer_create(fd)
      val @(ba, bl) = $B.to_arr(b)
      val @(fz_b, bv_b) = $A.freeze<byte>(ba)
      val () = wbw_loop(bw, bv_b, 0, bl)
      val () = $A.drop<byte>(fz_b, bv_b)
      val () = $A.free<byte>($A.thaw<byte>(fz_b))
    in $R.discard<int><$F.io_error>($F.buf_writer_close(bw)) end

(* Notes in slot i's file who took it, "bats check in <directory>", its
   first line, for a bats that waits for it to name. A slot's file is
   never emptied (only a holder may write it, and an empty file could
   not be told from one being written): its first line is the note,
   what follows a shorter note's line is not read. *)
fn note_holder (i: int, heavy: heavy_command): void = let
  var p : $B.builder_v = $B.create()
  val () = slot_path(i, p)
  var b : $B.builder_v = $B.create()
  val () = (case+ heavy of
    | HeavyCheck() => bput_v(b, "bats check")
    | HeavyBuild() => bput_v(b, "bats build")
    | HeavyTest() => bput_v(b, "bats test")
    | HeavyRun() => bput_v(b, "bats run")
    | NotHeavy() => bput_v(b, "bats"))
  val cwd = $A.alloc<byte>(4096)
  val k = (case+ $E.cwd_read(cwd, 4096) of | ~$R.some(k) => k | ~$R.none() => 0): int
  val @(fz_c, bv_c) = $A.freeze<byte>(cwd)
  val () = (if k > 0 then bput_v(b, " in ") else ())
  val () = copy_to_builder_v(bv_c, 0, k, 4096, b)
  val () = $A.drop<byte>(fz_c, bv_c)
  val () = $A.free<byte>($A.thaw<byte>(fz_c))
  val () = put_char_v(b, 10)
in note_write(p, b) end

(* Slot i's note appended to out: the first line of its file; false
   when it has none (a free slot's file, or one gen-pwa test holds) *)
fn note_read (i: int, out: !$B.builder_v >> $B.builder_v): bool = let
  var p : $B.builder_v = $B.create()
  val () = slot_path(i, p)
in
  case+ open_built(p, $F.ReadOnly(), $F.OpenExisting()) of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(4096)
      val k = (case+ $F.file_read(fd, buf, 4096) of | ~$R.ok(k) => k | ~$R.err(_) => 0): int
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      val @(fz_b, bv_b) = $A.freeze<byte>(buf)
      fun line_end {l:agz}{i:nat | i <= 4096} .<4096 - i>.
        (bv: !$A.borrow(byte, l, 4096), i: int i, k: int): int =
        if i >= 4096 then i
        else if i >= k then i
        else if byte2int0($A.read<byte>(bv, i)) = 10 then i
        else line_end(bv, i + 1, k)
      val line = line_end(bv_b, 0, k)
      val () = copy_to_builder_v(bv_b, 0, line, 4096, out)
      val () = $A.drop<byte>(fz_b, bv_b)
      val () = $A.free<byte>($A.thaw<byte>(fz_b))
    in line > 0 end
end

(* A slot's note says who last took it; the holder clears it as it
   releases the slot, so a note left is a bats that was killed, or one
   that holds the slot now *)
fn note_clear (i: int): void = let
  var p : $B.builder_v = $B.create()
  val () = slot_path(i, p)
  var b : $B.builder_v = $B.create()
  val () = put_char_v(b, 10)
in note_write(p, b) end

(* Whether the slot BATS_SLOT_HELD names is held by another open of its
   file: this bats's parent's, which started it while holding it. A
   variable left set with no holder (exported by hand, or by a bats
   that is gone) is not trusted: its slot is free, and this bats takes
   a slot as any other *)
fn parent_holds (): bool = let
  var p : $B.builder_v = $B.create()
  val set = env_value("BATS_SLOT_HELD", p)
  val path = p
in
  if ~set then let
    val () = $B.builder_free(path)
  in false end
  else (case+ open_built(path, $F.ReadOnly(), $F.OpenExisting()) of
    | ~$R.err(_) => false
    | ~$R.ok(fd) => let
        val held = (case+ $F.fd_lock(fd, $F.LockShared(), $F.LockFailsAtOnce()) of
          | ~$R.ok(_) => false
          | ~$R.err(e) => (case+ e of $F.WouldBlock() => true | _ => false)): bool
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in held end)
end

fn slot_warn {what_len,why_len:nat} (what: string what_len, i: int, why: string why_len): void = let
  var m : $B.builder_v = $B.create()
  val () = bput_v(m, "warning: ")
  val () = bput_v(m, what)
  val () = (if i >= 0 then slot_path(i, m) else slot_dir(m))
  val () = bput_v(m, why)
  val () = bput_v(m, ", so this bats runs without a machine slot (BATS_SLOTS)\n")
in prerr_builder(m) end

fn slot_held (fd: $F.fd, i: int, heavy: heavy_command): machine_slot = let
  val () = note_holder(i, heavy)
  val () = !g_slot_held := i + 1
in SlotHeld(fd, i) end

implement machine_slot_take (heavy) = let
  val n0 = (case+ heavy of NotHeavy() => 0 | _ => slots_wanted()): int
in
  if n0 = 0 then SlotNone()
  else if n0 < 0 then let
    val () = prerr! ("warning: BATS_SLOTS is not a number from 1 to 64, so this bats runs without a machine slot\n")
  in SlotNone() end
  else if parent_holds() then SlotOfParent()
  else let
    var d : $B.builder_v = $B.create()
    val () = slot_dir(d)
    val made = run_mkdir(d)
    val n = g1ofg0(n0)
  in
    if made <> 0 then let
      val () = slot_warn("cannot make the slots' directory ", ~1, "")
    in SlotNone() end
    else if n < 1 then SlotNone()
    else let
      val @(found, i) = slot_free(0, n)
    in
      case+ found of
      | ~SlotTaken(fd) => slot_held(fd, i, heavy)
      | ~SlotUnopenable() => let
          val () = slot_warn("cannot open ", i, "")
        in SlotNone() end
      | ~SlotUnlockable() => let
          val () = slot_warn("cannot lock ", i, " (its file system has no locks)")
        in SlotNone() end
      | ~SlotBusy() => let
          (* With more than one slot, a bats that waits waits for slot
             0, though another may be freed first, as gen-pwa test does *)
          val () = (if is_quiet() then () else let
              var m : $B.builder_v = $B.create()
              val () = bput_v(m, "waiting for another bats on this machine (")
              val () = put_int_v(m, n)
              val () = bput_v(m, " at once, BATS_SLOTS")
              var note : $B.builder_v = $B.create()
              val noted = note_read(0, note)
              val holder = note
              val () = (if noted then let
                  val () = bput_v(m, "; ")
                  val () = slot_path(0, m)
                  val () = bput_v(m, " was last taken by ")
                in append_builder(m, holder) end
                else $B.builder_free(holder))
              val () = bput_v(m, ")\n")
            in prerr_builder(m) end)
        in
          case+ slot_try(0, $F.LockWaits()) of
          | ~SlotTaken(fd) => slot_held(fd, 0, heavy)
          | ~SlotBusy() => SlotNone()
          | ~SlotUnopenable() => let
              val () = slot_warn("cannot open ", 0, "")
            in SlotNone() end
          | ~SlotUnlockable() => let
              val () = slot_warn("cannot lock ", 0, " (its file system has no locks)")
            in SlotNone() end
        end
    end
  end
end

implement machine_slot_release (slot) =
  case+ slot of
  | ~SlotHeld(fd, i) => let
      val () = note_clear(i)
      val () = !g_slot_held := 0
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
  | ~SlotOfParent() => ()
  | ~SlotNone() => ()

(* ============================================================
   The project's lock (bats-lang/bats#250)
   ============================================================ *)

(* The lock a command that writes build/, dist/ or bats_modules/ holds,
   so two bats never write one project's at once. It is flock(2) on
   bats.toml opened read-only (file's fd_lock): bats.toml is always
   there and bats clean leaves it, where a lock file in build/ would be
   deleted while another bats waits on it, and the kernel releases the
   lock when bats ends however it ends, so it is never left stale.
   Where the file system has no locks (an error other than WouldBlock),
   bats runs unlocked, as Cargo does. *)




(* Takes the project's lock, saying on stderr when another bats holds it
   and waiting until it is free; then, for a heavy command, a slot of
   the machine's (below) *)


(* Releases the project's lock and the machine slot *)


implement project_lock_take (heavy) = let
  val p = str_to_path_arr("bats.toml")
  val @(fz_p, bv_p) = $A.freeze<byte>(p)
  val opened = file_open_path(bv_p, $F.ReadOnly(), $F.OpenExisting(), 0)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
  val project = (case+ opened of
  | ~$R.err(_) => $R.none()
  | ~$R.ok(fd) =>
    (case+ $F.fd_lock(fd, $F.LockExclusive(), $F.LockFailsAtOnce()) of
    | ~$R.ok(_) => $R.some(fd)
    | ~$R.err(e) =>
      (case+ e of
      | $F.WouldBlock() => let
          val () = (if is_quiet() then ()
            else prerr! ("waiting for another bats running in this project (it holds the lock on bats.toml)\n"))
        in
          case+ $F.fd_lock(fd, $F.LockExclusive(), $F.LockWaits()) of
          | ~$R.ok(_) => $R.some(fd)
          | ~$R.err(_) => let
              val () = $R.discard<int><$F.io_error>($F.file_close(fd))
            in $R.none() end
        end
      | _ => let
          val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        in $R.none() end))): $R.option($F.fd)
  (* The slot after the project's lock, so a bats waiting for its project
     holds no slot, and no two bats wait on each other: one that holds a
     slot holds its project's lock already *)
  val slot = machine_slot_take(heavy)
in
  case+ project of
  | ~$R.some(fd) => ProjectLocked(fd, slot)
  | ~$R.none() => ProjectUnlocked(slot)
end

implement project_lock_release (lk) =
  case+ lk of
  | ~ProjectLocked(fd, slot) => let
      val () = machine_slot_release(slot)
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
  | ~ProjectUnlocked(slot) => machine_slot_release(slot)

(* ============================================================
   File I/O
   ============================================================ *)





implement write_file_from_builder(path_bv, path_len, content_b) = let
  val @(content_arr, content_len) = $B.to_arr(content_b)
in
  (* A builder_v drops what does not fit and is then full: its text is
     cut short, so it is not written *)
  if content_len >= 524288 then let
    val () = $A.free<byte>(content_arr)
    var m : $B.builder_v = $B.create()
    val () = bput_v(m, "error: the output for '")
    val () = copy_to_builder_v(path_bv, 0, find_null_bv_from(path_bv, 0, path_len), path_len, m)
    val () = bput_v(m, "' is larger than 524288 bytes, the most bats can write\n")
    val () = prerr_builder(m)
    val () = set_build_err()
  in ~1 end
  else let
  val fd_r = file_open_n(path_bv, path_len, $F.WriteOnly(), $F.CreateOrTruncate(), 420)
in case+ fd_r of
  | ~$R.ok(fd) => let
      val bw = $F.buf_writer_create(fd)
      val @(fz_c, bv_c) = $A.freeze<byte>(content_arr)
      val () = wbw_loop(bw, bv_c, 0, content_len)
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = $A.free<byte>($A.thaw<byte>(fz_c))
      val cr = $F.buf_writer_close(bw)
      val () = $R.discard<int><$F.io_error>(cr)
    in 0 end
  | ~$R.err(_) => let val () = $A.free<byte>(content_arr) in ~1 end
end
end

(* ============================================================
   Ropes: text of any length (a module's .sats and .dats)
   ============================================================ *)



implement rput(r, v) = $B.rope_put(r, $AR.low_byte(v))



implement rbput(r, s) = $B.rope_bput(r, s)

(* v in decimal *)


implement rput_int(r, v) = let
  var b : $B.builder_v = $B.create()
  val () = put_int_v(b, v)
in $B.rope_append(r, b) end

(* Whether a[0, m) and b[0, m) hold the same bytes, from j on *)
fun same_bytes {la,lb:agz}{na,nb:pos}{m:nat | m <= na; m <= nb}{j:nat | j <= m} .<m - j>.
  (a: !$A.borrow(byte, la, na), b: !$A.borrow(byte, lb, nb), m: int m, j: int j): bool =
  if j >= m then true
  else if $AR.eq_int_int(byte2int0($A.read<byte>(a, j)), byte2int0($A.read<byte>(b, j)))
  then same_bytes(a, b, m, j + 1)
  else false

(* Whether the next bytes of fd are the texts of cs, in order *)
fun fd_has_chunks {k:nat} .<k>. (fd: !$F.fd, cs: !$B.rope_list(k)): bool =
  case+ cs of
  | $B.rope_nil() => true
  | @$B.rope_cons(a, n, tl) =>
    if n <= 0 then let
      val r = fd_has_chunks(fd, tl)
      prval () = fold@(cs)
    in r end
    else let
      val buf = $A.alloc<byte>(n)
      val k = (case+ $F.file_read(fd, buf, n) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0)
      val @(fz_f, bv_f) = $A.freeze<byte>(buf)
      val @(fz_a, bv_a) = $A.freeze<byte>(a)
      val eq = (if $AR.eq_int_int(k, n) then same_bytes(bv_f, bv_a, n, 0) else false): bool
      val () = $A.drop<byte>(fz_a, bv_a)
      val () = a := $A.thaw<byte>(fz_a)
      val () = $A.drop<byte>(fz_f, bv_f)
      val () = $A.free<byte>($A.thaw<byte>(fz_f))
      val r = (if eq then fd_has_chunks(fd, tl) else false): bool
      prval () = fold@(cs)
    in r end

(* Whether the file at path holds exactly the text of cs *)



implement file_has_rope (path_bv, cs) =
  case+ file_open_path(path_bv, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(fd) => let
      val same = fd_has_chunks(fd, cs)
      (* and nothing after them *)
      val one = $A.alloc<byte>(1)
      val more = (case+ $F.file_read(fd, one, 1) of
        | ~$R.ok(k) => k > 0 | ~$R.err(_) => true): bool
      val () = $A.free<byte>(one)
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in if same then ~more else false end
  | ~$R.err(_) => false

(* The texts of cs to fd, in order; 0, or ~1 after a failed write *)
fun fd_write_chunks {k:nat} .<k>. (fd: !$F.fd, cs: !$B.rope_list(k)): int =
  case+ cs of
  | $B.rope_nil() => 0
  | @$B.rope_cons(a, n, tl) => let
      val w = (if n <= 0 then 0 else let
          val @(fz, bv) = $A.freeze<byte>(a)
          val @(left, right) = $A.borrow_split<byte>(fz, bv, n)
          val ok = (case+ $F.file_write(fd, left, n) of
            | ~$R.ok(_) => 0 | ~$R.err(_) => ~1): int
          val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, left, right))
          val () = a := $A.thaw<byte>(fz)
        in ok end): int
      val r = (if w < 0 then w else fd_write_chunks(fd, tl)): int
      prval () = fold@(cs)
    in r end

(* The text of cs written to the file at path (created, or truncated);
   0, or ~1 when it cannot be opened or written *)



implement write_file_from_rope (path_bv, cs) = let
  (* a .sats or .dats is written: what is kept of the names and digests of
     the files of build/ is no longer the files' *)
  val () = names_set_fresh(false)
in
  case+ file_open_path(path_bv, $F.WriteOnly(), $F.CreateOrTruncate(), 420) of
  | ~$R.ok(fd) => let
      val w = fd_write_chunks(fd, cs)
      val c = (case+ $F.file_close(fd) of | ~$R.ok(_) => 0 | ~$R.err(_) => ~1): int
    in if w < 0 then w else c end
  | ~$R.err(_) => ~1
end

(* ============================================================
   A file read whole (a module of any size)
   ============================================================ *)

(* The errno a failure is reported with, as the Rust bats reported the
   io::Error ("<text> (os error <errno>)"): file's io_error keeps the
   kind, not the number, so each kind has its Linux errno; Unrecognized
   is EIO's *)


implement io_error_errno (e) =
  case+ e of
  | $F.NotFound() => 2 | $F.PermissionDenied() => 13 | $F.AlreadyExists() => 17
  | $F.NotADirectory() => 20 | $F.IsADirectory() => 21 | $F.DirectoryNotEmpty() => 39
  | $F.ReadOnlyFilesystem() => 30 | $F.FilesystemLoop() => 40 | $F.InvalidFilename() => 36
  | $F.InvalidInput() => 22 | $F.FileTooLarge() => 27 | $F.StorageFull() => 28
  | $F.TooManyOpenFiles() => 24 | $F.OutOfMemory() => 12 | $F.ResourceBusy() => 16
  | $F.BrokenPipe() => 32 | $F.WouldBlock() => 11 | $F.BadDescriptor() => 9
  | $F.DeviceError() => 5 | $F.Unsupported() => 95 | $F.CrossesDevices() => 18
  | $F.Unrecognized() => 5

(* The n bytes of a file, then a NUL (m = n + 1), in the one piece of an
   arena of its own; or what failed *)





(* The file at the NUL-terminated path read whole: sized first, then
   read into a piece that holds it (a file that changes size meanwhile
   is EIO, one too large for an arena EFBIG) *)



implement read_whole (path, plen) =
  case+ file_open_n(path, plen, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.err(e) => whole_err(e)
  | ~$R.ok(fd) =>
    (case+ $F.fd_size(fd) of
    | ~$R.err(e) => let
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in whole_err(e) end
    | ~$R.ok(z) =>
      if z >= 268435455 then let
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in whole_err($F.FileTooLarge()) end
      else (case+ $A.arena_create<byte>(z + 1) of
      | ~$A.arena_none() => let
          val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        in whole_err($F.OutOfMemory()) end
      | ~$A.arena_some(ar) => let
          val p = $A.arena_alloc<byte>(ar, z + 1)
          val k = (case+ $F.file_read(fd, p, z + 1) of
            | ~$R.ok(k) => k | ~$R.err(_) => ~1): int
          val () = $R.discard<int><$F.io_error>($F.file_close(fd))
        in
          if k = z then whole_ok(ar, p, z + 1, z)
          else let
            val () = $A.arena_return<byte>(ar, p)
            val () = $A.arena_destroy<byte>(ar)
          in whole_err($F.DeviceError()) end
        end))

(* Frees what read_whole read *)



implement whole_free (ar, p) = let
  val () = $A.arena_return<byte>(ar, p)
in $A.arena_destroy<byte>(ar) end

(* build/.sats_changed is touched BEFORE a .sats is written, so a bats
   killed between the two leaves the stamp ahead (every C is made again),
   never behind (a C built from the older .sats kept fresh). Where a .sats
   turns out to have only moved (check and test mode), the stamp is put
   back as it was: sats_stamp_save before the touch, and sats_stamp_end
   after the write, with back = true to restore it, false to keep the
   touched one. *)


implement sats_stamp_save () = let
  val @(pa, _) = $B.to_arr(sats_stamp_path())
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val w = read_whole(bv_p, 524288)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in w end



implement sats_stamp_end (saved, back) =
  case+ saved of
  | ~whole_ok(ar, piece, m, n) => let
      val @(fz_c, bv_c) = $A.freeze<byte>(piece)
      val () = (if back then let
          var cb : $B.builder_v = $B.create()
          val () = copy_to_builder_v(bv_c, 0, n, m, cb)
          val @(pa, _) = $B.to_arr(sats_stamp_path())
          val @(fz_p, bv_p) = $A.freeze<byte>(pa)
          val _ = write_file_from_builder(bv_p, 524288, cb)
          val () = $A.drop<byte>(fz_p, bv_p)
        in $A.free<byte>($A.thaw<byte>(fz_p)) end else ())
      val () = $A.drop<byte>(fz_c, bv_c)
    in whole_free(ar, $A.thaw<byte>(fz_c)) end
  | ~whole_err(_) => (if back then let
        val @(pa, pl) = $B.to_arr(sats_stamp_path())
        val @(fz_p, bv_p) = $A.freeze<byte>(pa)
        val () = remove_output(bv_p, pl)
        val () = $A.drop<byte>(fz_p, bv_p)
      in $A.free<byte>($A.thaw<byte>(fz_p)) end else ())


(* ============================================================
   A .sats that only moved: its declarations the same, at other lines
   ============================================================ *)

(* The byte of b at i, or ~1 outside b[0, n) *)
fn byte_at {l:agz}{m:pos}{n:nat | n < m}{i:int}
  (b: !$A.borrow(byte, l, m), n: int n, i: int i): int =
  if i < 0 then ~1
  else if i >= n then ~1
  else byte2int0($A.read<byte>(b, i))

(* i + k, at most n: k bytes on from i (k at least 1) *)
fn ahead {n:nat}{i:nat | i < n}{k:int | k >= 1}
  (n: int n, i: int i, k: int k): [j:int | i < j; j <= n] int j =
  if i + k <= n then i + k else n

(* Past the newlines of b from i *)
fun past_newlines {l:agz}{m:pos}{n:nat | n < m}{i:nat | i <= n} .<n - i>.
  (b: !$A.borrow(byte, l, m), n: int n, i: int i): [j:int | i <= j; j <= n] int j =
  if i >= n then i
  else if byte2int0($A.read<byte>(b, i)) = 10 then past_newlines(b, n, i + 1)
  else i

(* Whether a[i, an) and b[j, bn) are the same text once each run of
   newlines, in either, is taken as one newline *)
fun same_but_newline_runs
  {la,lb:agz}{ma,mb:pos}{an:nat | an < ma}{bn:nat | bn < mb}
  {i:nat | i <= an}{j:nat | j <= bn} .<an - i + bn - j>.
  (a: !$A.borrow(byte, la, ma), an: int an, i: int i,
   b: !$A.borrow(byte, lb, mb), bn: int bn, j: int j): bool =
  if i >= an then j >= bn
  else if j >= bn then false
  else let
    val x = byte2int0($A.read<byte>(a, i))
    val y = byte2int0($A.read<byte>(b, j))
  in
    if x <> y then false
    else if x = 10 then
      same_but_newline_runs(a, an, past_newlines(a, an, i + 1),
                            b, bn, past_newlines(b, bn, j + 1))
    else same_but_newline_runs(a, an, i + 1, b, bn, j + 1)
  end

(* Whether no newline of b[i, n) is part of a literal: none in a string
   literal (whose length it is part of) or a char literal, no C code
   (%{, whose text is not read here), and no literal or block comment
   left open at the end. A newline in a comment or between tokens is
   only where the next line starts. state: 0 in code, 1 in a line
   comment, 2 in ML comments depth deep, 3 in a string literal, 4 in a
   C comment. Where it cannot tell, it says no. *)
fun newlines_between_tokens {l:agz}{m:pos}{n:nat | n < m}{i:nat | i <= n} .<n - i>.
  (b: !$A.borrow(byte, l, m), n: int n, i: int i, state: int, depth: int): bool =
  if i >= n then (state = 0 || state = 1)
  else let
    val c = byte2int0($A.read<byte>(b, i))
    val d = byte_at(b, n, i + 1)
  in
    if state = 1 then
      newlines_between_tokens(b, n, i + 1, (if c = 10 then 0 else 1), 0)
    else if state = 2 then
      (if c = 40 && d = 42 then newlines_between_tokens(b, n, ahead(n, i, 2), 2, depth + 1)
       else if c = 42 && d = 41 then
         newlines_between_tokens(b, n, ahead(n, i, 2), (if depth <= 1 then 0 else 2), depth - 1)
       else newlines_between_tokens(b, n, i + 1, 2, depth))
    else if state = 3 then
      (if c = 10 then false
       else if c = 92 then (if d = 10 then false else if d < 0 then false
         else newlines_between_tokens(b, n, ahead(n, i, 2), 3, 0))
       else if c = 34 then newlines_between_tokens(b, n, i + 1, 0, 0)
       else newlines_between_tokens(b, n, i + 1, 3, 0))
    else if state = 4 then
      (if c = 42 && d = 47 then newlines_between_tokens(b, n, ahead(n, i, 2), 0, 0)
       else newlines_between_tokens(b, n, i + 1, 4, 0))
    else if c = 34 then newlines_between_tokens(b, n, i + 1, 3, 0)
    else if c = 47 && d = 47 then newlines_between_tokens(b, n, ahead(n, i, 2), 1, 0)
    else if c = 47 && d = 42 then newlines_between_tokens(b, n, ahead(n, i, 2), 4, 0)
    else if c = 40 && d = 42 then newlines_between_tokens(b, n, ahead(n, i, 2), 2, 1)
    else if c = 37 && d = 123 then false
    else if c = 39 then let
      val e = byte_at(b, n, i + 2)
      val f = byte_at(b, n, i + 3)
    in
      if d = 10 || e = 10 || f = 10 then false
      (* '\x': an escape, closed at once, or not read here *)
      else if d = 92 then (if f = 39 then newlines_between_tokens(b, n, ahead(n, i, 4), 0, 0)
                           else false)
      (* 'x' *)
      else if e = 39 then newlines_between_tokens(b, n, ahead(n, i, 3), 0, 0)
      (* a quote before a tuple, record or list: '( '{ '[ *)
      else newlines_between_tokens(b, n, i + 1, 0, 0)
    end
    else newlines_between_tokens(b, n, i + 1, 0, 0)
  end

(* Whether a module's .sats, before (as it was read before it was
   written again) and now at path, has only moved: the same text but
   for how many newlines are in each run of them, none of them in a
   literal. A private declaration added, removed or changed moves the
   #pub ones after it to other lines (its lines are kept blank, so
   patsopt's line numbers stay those of the .bats), and that changes
   nothing a module that staloads the .sats is checked against. *)



implement sats_moved (before, path) =
  case+ before of
  | ~whole_err(_) => false
  | ~whole_ok(ar0, p0, m0, n0) =>
    (case+ read_whole(path, 524288) of
    | ~whole_err(_) => let
        val () = whole_free(ar0, p0)
      in false end
    | ~whole_ok(ar1, p1, m1, n1) => let
        val @(fz0, bv0) = $A.freeze<byte>(p0)
        val @(fz1, bv1) = $A.freeze<byte>(p1)
        val moved = (if ~same_but_newline_runs(bv0, n0, 0, bv1, n1, 0) then false
          else if ~newlines_between_tokens(bv0, n0, 0, 0, 0) then false
          else newlines_between_tokens(bv1, n1, 0, 0, 0)): bool
        val () = $A.drop<byte>(fz0, bv0)
        val () = whole_free(ar0, $A.thaw<byte>(fz0))
        val () = $A.drop<byte>(fz1, bv1)
        val () = whole_free(ar1, $A.thaw<byte>(fz1))
      in moved end)

(* ---- The check memo's entries (bats#267, item 3) ----

   In check and test mode a module's C is the record that it type-checked,
   and what that rests on is every file patsopt read for it (cache.bats
   lists them, from patsopt --depgen). Each is digested here as the other
   digests are, a size and then a sha256, never a time, except that a
   .sats is digested as its interface: its bytes with each run of line
   feeds taken as one line feed, the equivalence sats_moved uses for a
   .sats that only moved, so a declaration added before a module's #pub
   ones (a static test's snippet) changes no module that staloads it. A
   .sats's "size" is the length of that text, so it is still a negative
   only: a different length is a different interface. *)

(* Whether the NUL-terminated path ends in ".sats" *)
fn is_sats_path {lp:agz} (p: !$A.borrow(byte, lp, 524288)): bool = let
  val n = find_null_bv_from(p, 0, 524288)
in
  n >= 5 && peek(p, n - 5, 524288) = 46 && peek(p, n - 4, 524288) = 115
  && peek(p, n - 3, 524288) = 97 && peek(p, n - 2, 524288) = 116
  && peek(p, n - 1, 524288) = 115
end

(* src[i, k) written to dst from j without the line feeds that follow a
   line feed (prev is the byte before src[i], 0 at the start of a file);
   how many bytes were written *)
fun _collapse_lines {la,lb:agz}{k:nat | k <= 65536}{i:nat | i <= k}{j:nat | j <= i} .<k - i>.
  (src: !$A.arr(byte, la, 65536), dst: !$A.arr(byte, lb, 65536),
   k: int k, i: int i, j: int j, prev: int, squeeze: bool): [r:nat | r <= k] int r =
  if i >= k then j
  else let
    val b = peek_arr(src, i, 65536)
  in
    if squeeze && b = 10 && prev = 10 then _collapse_lines(src, dst, k, i + 1, j, b, squeeze)
    else let
      val () = poke_arr(dst, j, 65536, b)
    in _collapse_lines(src, dst, k, i + 1, j + 1, b, squeeze) end
  end

(* The interface of the r bytes left of fd, a chunk at a time, fed to c;
   len is the length so far, and the length of all of it is the answer *)
fun _interface_chunks {lb,lc:agz}{r:int} .<max(r, 0)>.
  (fd: !$F.fd, buf: !$A.arr(byte, lb, 65536), out: !$A.arr(byte, lc, 65536),
   c: !$SHA.ctx, r: int r, prev: int, len: int, squeeze: bool): int =
  if r <= 0 then len
  else let
    val k = (case+ $F.file_read(fd, buf, 65536) of
      | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 65536] int k
    val m = _collapse_lines(buf, out, k, 0, 0, prev, squeeze)
    val () = $SHA.update(c, out, m)
    val last = (if k > 0 then peek_arr(buf, k - 1, 65536) else prev): int
  in
    if k <= 0 then len else _interface_chunks(fd, buf, out, c, r - k, last, len + m, squeeze)
  end

(* The length of the interface of the file at p, or its sha256, appended
   to b (the length when want_hash is false); false when it cannot be
   opened. squeeze: each run of line feeds is taken as one. *)
fn interface_digest {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), b: !$B.builder_v >> $B.builder_v, want_hash: bool,
   squeeze: bool): bool =
  case+ file_open_path(p, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(65536)
      val out = $A.alloc<byte>(65536)
      val c = $SHA.init()
      val size = (case+ $F.fd_size(fd) of
        | ~$R.ok(s) => s | ~$R.err(_) => 0): [s:nat] int s
      (* a tag first: the text was squeezed (C) or is as it is (R), so
         the digest of one is never that of the other *)
      val () = poke_arr(out, 0, 65536, (if squeeze then 67 else 82))
      val () = $SHA.update(c, out, 1)
      val len = _interface_chunks(fd, buf, out, c, size, 0, 1, squeeze)
      val () = $A.free<byte>(buf)
      val () = $A.free<byte>(out)
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      val hex = $A.alloc<byte>(64)
      val () = $SHA.finish(c, hex)
      val @(fh, bh) = $A.freeze<byte>(hex)
      val () = (if want_hash then copy_to_builder_v(bh, 0, 64, 64, b) else put_int_v(b, len))
      val () = $A.drop<byte>(fh, bh)
      val () = $A.free<byte>($A.thaw<byte>(fh))
    in true end
  | ~$R.err(_) => false

(* Whether the .sats at p only has line feeds that may be squeezed (none
   in a literal, as sats_moved asks), so that a run of them more or fewer
   is no change; false when it cannot be read *)
fn squeezable {lp:agz} (p: !$A.borrow(byte, lp, 524288)): bool =
  case+ read_whole(p, 524288) of
  | ~whole_err(_) => false
  | ~whole_ok(ar, piece, m, n) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val ok = newlines_between_tokens(bv, n, 0, 0, 0)
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in ok end

(* The interface of the .sats at p: squeezed when sats_moved would take
   a run of line feeds more or fewer for a move, else as it is *)
fn interface_scan {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), b: !$B.builder_v >> $B.builder_v, want_hash: bool): bool = let
  val squeeze = squeezable(p)
in interface_digest(p, b, want_hash, squeeze) end

(* The size line of one file of a closure: its size, or a .sats's
   interface length; false when it cannot be read *)
fn memo_size_raw {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), out: !$B.builder_v >> $B.builder_v): bool = let
  val ok = (if is_sats_path(p) then interface_scan(p, out, false)
    else let
      val z = size_of_file(p)
      val () = put_int_v(out, z)
    in z >= 0 end): bool
  val () = put_char_v(out, 10)
in ok end

(* The hash line of one file of a closure: its sha256, or a .sats's
   interface's *)
fn memo_hash_raw {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), out: !$B.builder_v >> $B.builder_v): bool = let
  val ok = (if is_sats_path(p) then interface_scan(p, out, true)
    else put_file_sha256(p, out)): bool
  val () = put_char_v(out, 10)
in ok end


(* ---- Digests kept for a pass ----

   A staloaded dependency's .dats and the .sats of the project are in the
   closure of many modules, and digesting one (a sha256 of a few hundred
   kilobytes, or a scan for its interface) for each of them was most of
   what a no-change check cost over main's. The digest of such a file is
   kept in memory for the pass, in one table of this process, not in a file
   each (an unchanged check of a project of quire's size read about 5,000
   small files for them, an open each: bats#311). Only a .sats and the files
   under build/bats_modules are kept; a module's own .dats is hashed where
   it is needed.

   The table is one array of 1 MiB of entries and one of 16384 ints, the
   slots of an open-addressing index. An entry is the file's path, a line
   feed, the size line and the hash line (each ends with its line feed, the
   hash line is 64 hex digits and its line feed), the text memo_size_raw and
   memo_hash_raw make; a slot holds an entry's offset plus one, 0 being
   empty. A file is looked up by the full path, compared byte for byte, so
   a slot that holds another path is passed over. The table is emptied
   (digests_forget) wherever the names are listed again (names_digest in
   cache.bats), which is after anything that writes a .sats or a .dats of
   the project (names_fresh is made false by touch_sats_stamp,
   write_file_from_rope, cache_swap and prune_orphans), so an entry is never
   older than the file it digests within a run, and it lives in the memory
   of one process, so none outlives a run. A table that is full keeps no
   more: those files are digested each time, as before.

   What is proved is every read and write of the two arrays by its index
   (an entry is read only inside the first u bytes, which are the bytes
   written, and u is at most the array's size) and the termination of every
   loop. What is not: a slot is an int read back from memory, which has no
   index in its type (the array package has no array of indexed ints:
   bats-lang/array#49), so slot_read takes a value outside [0, u] to be 0, an
   empty slot, as with_env's table_read does; it cannot happen, since only
   dg_insert writes a slot, with an offset it has just written an entry at,
   and a slot read as empty is a miss, which digests the file again. *)

(* Whether p begins with "build/bats_modules/" *)
fn in_modules {lp:agz} (p: !$A.borrow(byte, lp, 524288)): bool = let
  fun same {lp:agz}{i:nat | i <= 19} .<19 - i>.
    (p: !$A.borrow(byte, lp, 524288), s: string 19, i: int i): bool =
    if i >= 19 then true
    else if byte2int0($A.read<byte>(p, i)) = char2int0(string_get_at(s, i)) then same(p, s, i + 1)
    else false
in same(p, "build/bats_modules/", 0) end

fn digest_kept {lp:agz} (p: !$A.borrow(byte, lp, 524288)): bool =
  if is_sats_path(p) then true else in_modules(p)

datavtype digest_table =
  | table_none of ()
  | {li,lt:agz}{u:nat | u <= 1048576}
    table_some of ($A.arr(int, li, 16384), $A.arr(byte, lt, 1048576), int u)

val g_digests = ref<digest_table>(table_none())

fn table_free (t: digest_table): void =
  case+ t of
  | ~table_none() => ()
  | ~table_some(ix, tx, _) => let
      val () = $A.free<int>(ix)
    in $A.free<byte>(tx) end

(* Forgets every digest kept: the next ones are made from the files *)


implement digests_forget () = let
  var taken : digest_table = table_none()
  val () = ref_exch_elt<digest_table>(g_digests, taken)
in table_free(taken) end

(* The length of the NUL-terminated path in p, at most 524272 *)
fn path_length {lp:agz} (p: !$A.borrow(byte, lp, 524288)): [k:nat | k <= 524272] int k = let
  val z = find_null_bv_from(p, 0, 524288)
in (if z >= 0 then (if z <= 524272 then z else 524272) else 524272) end

(* The slot at which the path p[0, stop) starts being looked for: its hash,
   below 16384, h being the hash so far *)
fun dg_hash {lp:agz}{i:nat | i <= 524288}{h:nat | h < 16384} .<524288 - i>.
  (p: !$A.borrow(byte, lp, 524288), i: int i, stop: int, h: int h): [r:nat | r < 16384] int r =
  if i >= 524288 then h
  else if i >= stop then h
  else dg_hash(p, i + 1, stop, nmod(h * 31 + $AR.low_byte(byte2int0($A.read<byte>(p, i))), 16384))

(* The offset kept in slot s: an entry's offset plus one, or 0 for an empty
   slot (and for a value read that is none of those) *)
fn slot_read {li:agz}{s:nat | s < 16384}{u:nat | u <= 1048576}
  (ix: !$A.arr(int, li, 16384), s: int s, u: int u): [r:nat | r <= u] int r = let
  val v = g1ofg0($A.get<int>(ix, s))
in
  if v < 0 then 0
  else if v > u then 0
  else v
end

(* Whether p[i, k) is tx[off + i, off + k) *)
fun bytes_equal {lp,lt:agz}{k:nat | k <= 524272}{u:nat | u <= 1048576}{off:nat | off + k < u}{i:nat | i <= k} .<k - i>.
  (p: !$A.borrow(byte, lp, 524288), tx: !$A.borrow(byte, lt, 1048576),
   off: int off, i: int i, k: int k, u: int u): bool =
  if i >= k then true
  else if byte2int0($A.read<byte>(p, i)) = byte2int0($A.read<byte>(tx, off + i))
  then bytes_equal(p, tx, off, i + 1, k, u)
  else false

(* Whether the entry at off, in the first u bytes of tx, is the path p[0, k) *)
fn entry_is {lp,lt:agz}{k:nat | k <= 524272}{u:nat | u <= 1048576}{off:nat | off <= u}
  (p: !$A.borrow(byte, lp, 524288), k: int k, tx: !$A.borrow(byte, lt, 1048576),
   off: int off, u: int u): bool =
  if off + k + 1 > u then false
  else if bytes_equal(p, tx, off, 0, k, u) then byte2int0($A.read<byte>(tx, off + k)) = 10
  else false

(* The offset of the entry for p[0, k), or ~1 when there is none, looking
   from slot s and at most fuel slots on; an empty slot ends the look *)
fun dg_find {lp,li,lt:agz}{k:nat | k <= 524272}{u:nat | u <= 1048576}{s:nat | s < 16384}{f:nat} .<f>.
  (p: !$A.borrow(byte, lp, 524288), k: int k, ix: !$A.arr(int, li, 16384),
   tx: !$A.borrow(byte, lt, 1048576), u: int u, s: int s, fuel: int f)
  : [r:int | ~1 <= r; r <= u] int r =
  if fuel <= 0 then ~1
  else let
    val v = slot_read(ix, s, u)
  in
    if v <= 0 then ~1
    else if entry_is(p, k, tx, v - 1, u) then v - 1
    else dg_find(p, k, ix, tx, u, nmod(s + 1, 16384), fuel - 1)
  end

(* The first empty slot from s on, or ~1 when fuel slots are all taken *)
fun dg_empty {li:agz}{u:nat | u <= 1048576}{s:nat | s < 16384}{f:nat} .<f>.
  (ix: !$A.arr(int, li, 16384), u: int u, s: int s, fuel: int f): [r:int | ~1 <= r; r < 16384] int r =
  if fuel <= 0 then ~1
  else if slot_read(ix, s, u) <= 0 then s
  else dg_empty(ix, u, nmod(s + 1, 16384), fuel - 1)

(* The first line feed of tx[i, u), or u *)
fun lf_from {lt:agz}{u:nat | u <= 1048576}{i:nat | i <= u} .<u - i>.
  (tx: !$A.borrow(byte, lt, 1048576), i: int i, u: int u): [r:nat | i <= r; r <= u] int r =
  if i >= u then i
  else if byte2int0($A.read<byte>(tx, i)) = 10 then i
  else lf_from(tx, i + 1, u)

(* Where the size line (hashes false) or the hash line of the entry at off,
   whose path has k bytes, lies in tx: true and its first byte and the one
   after its line feed; false when the entry is not whole *)
fn dg_span {lt:agz}{k:nat | k <= 524272}{u:nat | u <= 1048576}{off:nat | off <= u}
  (tx: !$A.borrow(byte, lt, 1048576), off: int off, k: int k, u: int u, hashes: bool)
  : [a,b:int] @(bool, int a, int b) = let
  val s = off + k + 1
in
  if s > u then @(false, 0, 0)
  else let
    val e = lf_from(tx, s, u)
  in
    if e + 66 > u then @(false, 0, 0)
    else if hashes then @(true, e + 1, e + 66)
    else @(true, s, e + 1)
  end
end

(* src[base + i, base + k) written to tx from u + i on *)
fun blit {lt,ls:agz}{n:pos}{u:nat}{base:int}{k:nat | u + k <= 1048576}{i:nat | i <= k} .<k - i>.
  (tx: !$A.arr(byte, lt, 1048576), u: int u, src: !$A.borrow(byte, ls, n), n: int n,
   base: int base, i: int i, k: int k): void =
  if i >= k then ()
  else let
    val () = $A.set<byte>(tx, u + i, int2byte0(peek(src, base + i, n)))
  in blit(tx, u, src, n, base, i + 1, k) end

(* Whether sb[i, sl) is digits and then the line feed that ends it: a size line *)
fun size_line_shaped {ls:agz}{sl:nat | sl <= 524288}{i:nat | i <= sl} .<sl - i>.
  (sb: !$A.borrow(byte, ls, 524288), sl: int sl, i: int i): bool =
  if i >= sl then false
  else if i + 1 = sl then byte2int0($A.read<byte>(sb, i)) = 10
  else let
    val c = byte2int0($A.read<byte>(sb, i))
  in
    if c >= 48 then (if c <= 57 then size_line_shaped(sb, sl, i + 1) else false) else false
  end

(* The entry p[0, k), a line feed, sb[0, sl) and hb[0, hl) put in the table
   that holds u bytes and indexes from slot s: the bytes it holds then. Not
   put (u again) when the lines are not a size line and a hash line, when
   the entry does not fit or when no slot is free. *)
fn dg_insert {lp,li,lt,ls,lh:agz}{k:nat | k <= 524272}{u:nat | u <= 1048576}{s:nat | s < 16384}
  {sl,hl:nat | sl <= 524288; hl <= 524288}
  (p: !$A.borrow(byte, lp, 524288), k: int k, ix: !$A.arr(int, li, 16384),
   tx: !$A.arr(byte, lt, 1048576), u: int u, s: int s,
   sb: !$A.borrow(byte, ls, 524288), sl: int sl, hb: !$A.borrow(byte, lh, 524288), hl: int hl)
  : [u2:nat | u2 <= 1048576] int u2 =
  if hl <> 65 then u
  else if sl > 24 then u
  else if ~size_line_shaped(sb, sl, 0) then u
  else if u + k + 1 + sl + hl > 1048576 then u
  else let
    val slot = dg_empty(ix, u, s, 16384)
  in
    if slot < 0 then u
    else let
      val () = blit(tx, u, p, 524288, 0, 0, k)
      val () = $A.set<byte>(tx, u + k, int2byte0(10))
      val () = blit(tx, u + k + 1, sb, 524288, 0, 0, sl)
      val () = blit(tx, u + k + 1 + sl, hb, 524288, 0, 0, hl)
      val () = $A.set<int>(ix, slot, u + 1)
    in u + k + 1 + sl + hl end
  end

(* Digests p, appends the line asked for to out and, when both lines could
   be made, puts them in the table: false when p cannot be read; the bytes
   the table holds then *)
fn digest_miss {lp,li,lt:agz}{k:nat | k <= 524272}{u:nat | u <= 1048576}{s:nat | s < 16384}
  (p: !$A.borrow(byte, lp, 524288), k: int k, ix: !$A.arr(int, li, 16384),
   tx: !$A.arr(byte, lt, 1048576), u: int u, s: int s, hashes: bool,
   out: !$B.builder_v >> $B.builder_v): [u2:nat | u2 <= 1048576] @(bool, int u2) = let
  var sb : $B.builder_v = $B.create()
  var hb : $B.builder_v = $B.create()
  val a = memo_size_raw(p, sb)
  val b = memo_hash_raw(p, hb)
  val both = (a && b): bool
  val @(sa, sl) = $B.to_arr(sb)
  val @(fz_s, bv_s) = $A.freeze<byte>(sa)
  val @(ha, hl) = $B.to_arr(hb)
  val @(fz_h, bv_h) = $A.freeze<byte>(ha)
  val u2 = (if both then dg_insert(p, k, ix, tx, u, s, bv_s, sl, bv_h, hl) else u): [u2:nat | u2 <= 1048576] int u2
  val () = (if hashes then copy_to_builder_v(bv_h, 0, hl, 524288, out)
            else copy_to_builder_v(bv_s, 0, sl, 524288, out))
  val () = $A.drop<byte>(fz_h, bv_h)
  val () = $A.free<byte>($A.thaw<byte>(fz_h))
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
in @(both, u2) end

(* The kept size line (hashes false) or hash line of p, appended to out,
   each with its line feed: made and kept when none is kept; false when p
   cannot be read *)
fn digest_entry {lp:agz}
  (p: !$A.borrow(byte, lp, 524288), hashes: bool, out: !$B.builder_v >> $B.builder_v): bool = let
  var taken : digest_table = table_none()
  val () = ref_exch_elt<digest_table>(g_digests, taken)
  val @(ix, tx, u) = (case+ taken of
    | ~table_none() => let
        val fresh_ix = $A.alloc<int>(16384)
        val fresh_tx = $A.alloc<byte>(1048576)
      in @(fresh_ix, fresh_tx, 0) end
    | ~table_some(ix, tx, u) => @(ix, tx, u))
    : [li,lt:agz][u:nat | u <= 1048576] @($A.arr(int, li, 16384), $A.arr(byte, lt, 1048576), int u)
  val k = path_length(p)
  val start = dg_hash(p, 0, k, 0)
  val @(fz_x, bv_x) = $A.freeze<byte>(tx)
  val off = dg_find(p, k, ix, bv_x, u, start, 16384)
  val span = (if off >= 0 then dg_span(bv_x, off, k, u, hashes) else @(false, 0, 0)): [a,b:int] @(bool, int a, int b)
  val @(hit, first, past) = span
  val () = (if hit then copy_to_builder_v(bv_x, first, past, 1048576, out) else ())
  val () = $A.drop<byte>(fz_x, bv_x)
  val tx1 = $A.thaw<byte>(fz_x)
  val @(ok, u2) = (if hit then @(true, u) else digest_miss(p, k, ix, tx1, u, start, hashes, out))
    : [u2:nat | u2 <= 1048576] @(bool, int u2)
  var back : digest_table = table_some(ix, tx1, u2)
  val () = ref_exch_elt<digest_table>(g_digests, back)
  val () = table_free(back)
in ok end

(* The size line of one file of a closure: its size, or a .sats's
   interface length; false when it cannot be read *)



implement memo_entry_size(p, out) =
  if ~digest_kept(p) then memo_size_raw(p, out)
  else digest_entry(p, false, out)

(* The hash line of one file of a closure: its sha256, or a .sats's
   interface's *)



implement memo_entry_hash(p, out) =
  if ~digest_kept(p) then memo_hash_raw(p, out)
  else digest_entry(p, true, out)

(* Whether the file at path_bv begins with bv[0, len) *)



implement file_starts_with(path_bv, bv, len) = file_has_prefix(path_bv, bv, len)

(* BATS_COLD: set to anything but "0", or --cold: the check memo is
   ignored (and written again) *)


implement is_cold () =
  if !g_cold then true
  else let
    var b : $B.builder_v = $B.create()
    val set = env_value("BATS_COLD", b)
    val @(a, k) = $B.to_arr(b)
    val @(fz, bv) = $A.freeze<byte>(a)
    val zero = (k = 1 && peek(bv, 0, 524288) = 48): bool
    val () = $A.drop<byte>(fz, bv)
    val () = $A.free<byte>($A.thaw<byte>(fz))
  in set && ~zero end




implement str_to_path_arr(s) = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val () = $B.put_char(b, 0)
  val @(arr, _) = $B.to_arr(b)
in arr end

(* ============================================================
   String constant builders
   ============================================================ *)




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




implement make_name(buf) =
  let
    val () = $A.write_byte(buf, 0, 110)
    val () = $A.write_byte(buf, 1, 97)
    val () = $A.write_byte(buf, 2, 109)
    val () = $A.write_byte(buf, 3, 101)
  in end




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

(* The number of NULs in buf[0, len) *)



implement count_argc(buf, len) = let
  fun loop {l:agz}{j:nat | j <= 4096} .<4096 - j>.
    (buf: !$A.arr(byte, l, 4096), j: int j, len: int, count: int): int =
    if j >= 4096 then count
    else if j >= len then count
    else if $AR.eq_int_int(byte2int0($A.get<byte>(buf, j)), 0) then loop(buf, j + 1, len, count + 1)
    else loop(buf, j + 1, len, count)
in loop(buf, 0, len, 0) end






implement ap_flag(p, name, nn, sc, help, nh) = let
  val @(fzn, bvn) = $A.freeze<byte>($S.from_char_array(name, nn))
  val @(fzh, bvh) = $A.freeze<byte>($S.from_char_array(help, nh))
  val @(p2, h) = $AP.add_flag(p, bvn, nn, sc, bvh, nh)
  val () = $A.drop<byte>(fzn, bvn)
  val () = $A.free<byte>($A.thaw<byte>(fzn))
  val () = $A.drop<byte>(fzh, bvh)
  val () = $A.free<byte>($A.thaw<byte>(fzh))
in @(p2, h) end





implement ap_string_opt(p, name, nn, sc, help, nh) = let
  val @(fzn, bvn) = $A.freeze<byte>($S.from_char_array(name, nn))
  val @(fzh, bvh) = $A.freeze<byte>($S.from_char_array(help, nh))
  val @(p2, h) = $AP.add_string(p, bvn, nn, sc, bvh, nh, false)
  val () = $A.drop<byte>(fzn, bvn)
  val () = $A.free<byte>($A.thaw<byte>(fzn))
  val () = $A.drop<byte>(fzh, bvh)
  val () = $A.free<byte>($A.thaw<byte>(fzh))
in @(p2, h) end





implement ap_string_pos(p, name, nn, help, nh) = let
  val @(fzn, bvn) = $A.freeze<byte>($S.from_char_array(name, nn))
  val @(fzh, bvh) = $A.freeze<byte>($S.from_char_array(help, nh))
  val @(p2, h) = $AP.add_string(p, bvn, nn, $R.none(), bvh, nh, true)
  val () = $A.drop<byte>(fzn, bvn)
  val () = $A.free<byte>($A.thaw<byte>(fzn))
  val () = $A.drop<byte>(fzh, bvh)
  val () = $A.free<byte>($A.thaw<byte>(fzh))
in @(p2, h) end

(* Feeds the r bytes left of the file fd to c, a chunk at a time, until
   they are read or the file ends first *)
fun _hash_chunks {lb:agz}{r:int} .<max(r, 0)>.
  (fd: !$F.fd, buf: !$A.arr(byte, lb, 65536), c: !$SHA.ctx, r: int r): void =
  if r <= 0 then ()
  else let
    val k = (case+ $F.file_read(fd, buf, 65536) of
      | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 65536] int k
    val () = $SHA.update(c, buf, k)
  in if k <= 0 then () else _hash_chunks(fd, buf, c, r - k) end

(* Appends the sha256 of the file at the NUL-terminated path p to out,
   as 64 hex digits (Rust: sha256::sha256_hex), reading it in chunks so
   any size hashes; false when it cannot be opened *)



implement put_file_sha256 {lp} (p, out) =
  case+ file_open_path(p, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(afd) => let
      val buf = $A.alloc<byte>(65536)
      val c = $SHA.init()
      val size = (case+ $F.fd_size(afd) of
        | ~$R.ok(s) => s | ~$R.err(_) => 0): [s:nat] int s
      val () = _hash_chunks(afd, buf, c, size)
      val () = $A.free<byte>(buf)
      val () = $R.discard<int><$F.io_error>($F.file_close(afd))
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
fun find_dot {l:agz}{n:pos}{i,e:int} .<max(e - i, 0)>.
  (b: !$A.borrow(byte, l, n), i: int i, e: int e, n: int n)
  : [r:int | min(i, e) <= r; r <= max(i, e)] int r =
  if i >= e then e
  else if $AR.eq_int_int(peek(b, i, n), 46) then i
  else find_dot(b, i + 1, e, n)

(* Whether [i, e) is all ASCII digits *)
fun all_digits {l:agz}{n:pos}{i,e:int} .<max(e - i, 0)>.
  (b: !$A.borrow(byte, l, n), i: int i, e: int e, n: int n): bool =
  if i >= e then true
  else let val c = peek(b, i, n)
  in if c >= 48 && c <= 57 then all_digits(b, i + 1, e, n) else false end

(* The first position in [i, e) that is not '0', or e *)
fun first_nonzero {l:agz}{n:pos}{i,e:int} .<max(e - i, 0)>.
  (b: !$A.borrow(byte, l, n), i: int i, e: int e, n: int n): pos_t =
  if i >= e then e
  else if $AR.eq_int_int(peek(b, i, n), 48) then first_nonzero(b, i + 1, e, n)
  else i

(* Whether the digits b[z, z + 10) are at most m[0, 10) *)
fun digits_le {l:agz}{n:pos}{lm:agz}{j:nat | j <= 10} .<10 - j>.
  (b: !$A.borrow(byte, l, n), z: pos_t, n: int n,
   m: !$A.borrow(byte, lm, 10), j: int j): bool =
  if j >= 10 then true
  else let
    val x = peek(b, z + j, n)
    val y = byte2int0($A.read<byte>(m, j))
  in
    if x < y then true
    else if x > y then false
    else digits_le(b, z, n, m, j + 1)
  end

(* The digits of a u32 part without leading zeros: [z, e), or z = ~1
   when [s, e) is not one (Rust: u32::from_str after an optional '+') *)
fn u32_digits {l:agz}{n:pos}
  (b: !$A.borrow(byte, l, n), s: pos_t, e: pos_t, n: int n): pos_t = let
  val d = (if s < e then
    (if $AR.eq_int_int(peek(b, s, n), 43) then s + 1 else s) else s): pos_t
  var max_c = @[char][10]('4', '2', '9', '4', '9', '6', '7', '2', '9', '5')
  val @(fz_m, bv_m) = $A.freeze<byte>($S.from_char_array(max_c, 10))
  val z0 = first_nonzero(b, d, e, n)
  val z = (if z0 >= e then e - 1 else z0): pos_t
  val fits = (if e - z < 10 then true
    else if e - z > 10 then false
    else digits_le(b, z, n, bv_m, 0)): bool
  val () = $A.drop<byte>(fz_m, bv_m)
  val () = $A.free<byte>($A.thaw<byte>(fz_m))
in
  if e - d < 1 then ~1
  else if ~all_digits(b, d, e, n) then ~1
  else if fits then z
  else ~1
end

(* Rust's Version::parse over the parts of b[i, be), rendered into out:
   @(~1, ~1), or the invalid part's [start, end) *)
fun version_parts {l:agz}{n:pos}{i,be:int} .<max(be - i, 0)>.
  (b: !$A.borrow(byte, l, n), i: int i, be: int be, n: int n,
   out: !$B.builder_v >> $B.builder_v): @(pos_t, pos_t) = let
    val pe = find_dot(b, i, be, n)
    val z = u32_digits(b, i, pe, n)
  in
    if z < 0 then @(i, pe)
    else let
      val () = copy_to_builder_v(b, z, pe, n, out)
    in
      if pe >= be then @(~1, ~1)
      else let
        val () = put_char_v(out, 46)
      in version_parts(b, pe + 1, be, n, out) end
    end
  end

(* "dev1" when dev *)


implement put_dev1 (out, dev) =
  if dev then bput_v(out, "dev1") else ()


(* Rust's Version::parse over the parts of b[i, be), rendered into out
   (each part a u32 without '+' or leading zeros): @(~1, ~1), or the
   invalid part's [start, end) *)




implement parse_version_parts (b, i, be, n, out) = version_parts(b, i, be, n, out)

(* The first '.' in b[i, e), or e *)



implement next_dot (b, i, e, n) = find_dot(b, i, e, n)
