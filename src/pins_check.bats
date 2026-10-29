(* pins_check -- bats pins-check <base> <head>: what the review of a pure pin or relock pull request verifies, as a command (bats-lang/bats#427; keyword: pins-check) *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use list as L
#use process as P
#use result as R

staload "helpers.sats"
staload "pins.sats"
staload "merge_proof.sats"
staload "check_push.sats"

(* ------------------------------------------------------------------ *)
(* The command line, kept as spans of the command (keyword: pins-check). ~1 for a start is "not given". *)

val g_base_at = ref<pos_t>(0)
val g_base_to = ref<int>(0)
val g_head_at = ref<pos_t>(0)
val g_head_to = ref<int>(0)
val g_compiler_at = ref<pos_t>(~1)
val g_compiler_to = ref<int>(0)
val g_repo_at = ref<pos_t>(~1)
val g_repo_to = ref<int>(0)
val g_require_at = ref<pos_t>(~1)
val g_require_to = ref<int>(0)

(* How many NOT OK lines were printed; a file passes when this does not move while it is checked *)
val g_failures = ref<int>(0)

(* ------------------------------------------------------------------ *)
(* Reading a buffer by lines, bytes read with peek (0 outside the first m bytes) (keyword: pins-check) *)

(* The first newline of bv[p, m), or m *)
fun line_end {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p <= r; r <= m] int r =
  if p >= m then p
  else if peek(bv, p, m) = 10 then p
  else line_end(bv, p + 1, m)

(* The start of the line after the one at p *)
fn next_line {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p < m}
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p < r; r <= m] int r = let
  val e = line_end(bv, p, m)
in
  if e >= m then m else e + 1
end

(* The start of the first hunk of a diff (the lines before it are its headers), or m *)
fun body_start {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m): [r:nat | p <= r; r <= m] int r =
  if p >= m then m
  else if peek(bv, p, m) = 64 then p
  else body_start(bv, next_line(bv, p, m), m)

(* How many lines of bv[p, m) start with the byte ch *)
fun count_prefix {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, ch: int, count: int): int =
  if p >= m then count
  else count_prefix(bv, next_line(bv, p, m), m, ch, (if peek(bv, p, m) = ch then count + 1 else count))

(* The start of the first line of bv[p, m) that starts with the byte ch, or ~1 *)
fun find_prefix {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, ch: int): [r:int | ~1 <= r; r < m] int r =
  if p >= m then ~1
  else if peek(bv, p, m) = ch then p
  else find_prefix(bv, next_line(bv, p, m), m, ch)

(* The first byte ch of bv[p, e), or e *)
fun char_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, ch: int): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if peek(bv, p, e) = ch then p
  else char_end(bv, p + 1, e, ch)

fn is_hex (b: int): bool = (b >= 48 && b <= 57) || (b >= 97 && b <= 102)

fn is_digit (b: int): bool = b >= 48 && b <= 57

fn is_alnum (b: int): bool = is_digit(b) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)

(* Whether bv[at, at + len) is len lowercase hex digits (k of them are read) *)
fun hex_run {l:agz}{n:pos}{m:nat | m <= n}{at:int}{len:nat}{k:nat | k <= len} .<len - k>.
  (bv: !$A.borrow(byte, l, n), at: int at, m: int m, k: int k, len: int len): bool =
  if k >= len then true
  else if is_hex(peek(bv, at + k, m)) then hex_run(bv, at, m, k + 1, len)
  else false

(* The end of the run of digits of bv[p, e) *)
fun digits_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_digit(peek(bv, p, e)) then digits_end(bv, p + 1, e)
  else p

(* The end of the run of letters and digits of bv[p, e) *)
fun alnum_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_alnum(peek(bv, p, e)) then alnum_end(bv, p + 1, e)
  else p

(* The start of the first word of bv[p, e) (a run of letters and digits) that is 40 lowercase hex digits, or ~1:
   the form of a commit pin, which a longer or shorter run of hex digits is not *)
fun find_pin_token {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:int | r == ~1 || (0 <= r && r + 40 <= e)] int r =
  if p >= e then ~1
  else if is_alnum(peek(bv, p, e)) then let
      val j = alnum_end(bv, p + 1, e)
    in
      if j - p = 40 then (if hex_run(bv, p, e, 0, 40) then p else find_pin_token(bv, j, e))
      else find_pin_token(bv, j, e)
    end
  else find_pin_token(bv, p + 1, e)

(* Whether bv[p, e) starts with the first sn bytes of s, from its byte i on *)
fun lit_here {l:agz}{n:pos}{e:nat | e <= n}{p:nat}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn, i: int i): bool =
  if i >= sn then true
  else if p + i >= e then false
  else if peek(bv, p + i, e) = char2int0(string_get_at(s, i)) then lit_here(bv, p, e, s, sn, i + 1)
  else false

(* Whether bv[p, e) holds the text s *)
fun has_sub {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e}{sn:nat} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn): bool =
  if p >= e then false
  else if lit_here(bv, p, e, s, sn, 0) then true
  else has_sub(bv, p + 1, e, s, sn)

fn contains_text {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e}{sn:nat}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn): bool =
  has_sub(bv, p, e, s, g1u2i(string1_length(s)))

(* Whether bv[p, e) is exactly the text s *)
fn span_is {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e}{sn:nat}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn): bool = let
  val len = g1u2i(string1_length(s))
in
  if e - p <> len then false else lit_here(bv, p, e, s, len, 0)
end

(* Whether bv[a, a + len) and bv[b, b + len) hold the same bytes (k are compared) *)
fun span_eq {l:agz}{n:pos}{m:nat | m <= n}{a,b:int}{len:nat}{k:nat | k <= len} .<len - k>.
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, m: int m, len: int len, k: int k): bool =
  if k >= len then true
  else if peek(bv, a + k, m) = peek(bv, b + k, m) then span_eq(bv, a, b, m, len, k + 1)
  else false

(* ------------------------------------------------------------------ *)
(* Calendar versions (keyword: pins-check): numbers separated by dots, compared number by number *)

(* The digits bv[a, ae) against bv[b, be), as numbers: ~1, 0 or 1 *)
fun cmp_same_length {l:agz}{n:pos}{m:nat | m <= n}{a,b:int}{len:nat}{k:nat | k <= len} .<len - k>.
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, m: int m, len: int len, k: int k): int =
  if k >= len then 0
  else let
    val x = peek(bv, a + k, m)
    val y = peek(bv, b + k, m)
  in
    if x < y then ~1 else if x > y then 1 else cmp_same_length(bv, a, b, m, len, k + 1)
  end

(* The first position of bv[p, e) that is no zero *)
fun zeros_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if peek(bv, p, e) = 48 then zeros_end(bv, p + 1, e)
  else p

fn cmp_digits {l:agz}{n:pos}{m:nat | m <= n}{a,ae,b,be:nat | a <= ae; ae <= m; b <= be; be <= m}
  (bv: !$A.borrow(byte, l, n), a: int a, ae: int ae, b: int b, be: int be, m: int m): int = let
  val a2 = zeros_end(bv, a, ae)
  val b2 = zeros_end(bv, b, be)
  val la = ae - a2
  val lb = be - b2
in
  if la < lb then ~1
  else if la > lb then 1
  else cmp_same_length(bv, a2, b2, m, la, 0)
end

(* The version bv[a, ea) against bv[b, eb): ~1 older, 0 the same, 1 newer, 2 when one is no run of numbers
   separated by single dots (a dev version, 2026.2.21.53844dev1, is one) *)
fun ver_cmp {l:agz}{n:pos}{m:nat | m <= n}{ea,eb:nat | ea <= m; eb <= m}{a:nat | a <= ea}{b:nat | b <= eb} .<ea - a>.
  (bv: !$A.borrow(byte, l, n), a: int a, ea: int ea, b: int b, eb: int eb, m: int m): int = let
  val ae = char_end(bv, a, ea, 46)
  val be = char_end(bv, b, eb, 46)
in
  if ae = a then 2
  else if be = b then 2
  else if digits_end(bv, a, ae) <> ae then 2
  else if digits_end(bv, b, be) <> be then 2
  else let
    val c = cmp_digits(bv, a, ae, b, be, m)
  in
    if c <> 0 then c
    else if ae >= ea then (if be >= eb then 0 else ~1)
    else if be >= eb then 1
    else ver_cmp(bv, ae + 1, ea, be + 1, eb, m)
  end
end

(* ------------------------------------------------------------------ *)
(* Running git (keyword: pins-check) *)

(* The command line's span cmd[at, to) as an argument *)
fn copy_arg {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), at: pos_t, to: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, at, to, 4096, b)
in mk_arg(b) end

(* base...head: the pull request's own diff, from the merge base *)
fn range_arg {lc:agz}(cmd: !$A.borrow(byte, lc, 4096)): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, !g_base_at, !g_base_to, 4096, b)
  val () = bput_v(b, "...")
  val () = copy_to_builder_v(cmd, !g_head_at, !g_head_to, 4096, b)
in mk_arg(b) end

(* head:path, the file as the head has it *)
fn head_file_arg {lc:agz}{sn:nat | sn < $B.BUILDER_CAP}(cmd: !$A.borrow(byte, lc, 4096), path: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, !g_head_at, !g_head_to, 4096, b)
  val () = put_char_v(b, 58)
  val () = bput_v(b, path)
in mk_arg(b) end

(* bv[at, at + 40) and the ending, as one argument *)
fn commit_arg {l:agz}{n:pos}{m:nat | m <= n}{sn:nat | sn < $B.BUILDER_CAP}
  (bv: !$A.borrow(byte, l, n), at: pos_t, m: int m, ending: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, at, at + 40, m, b)
  val () = bput_v(b, ending)
in mk_arg(b) end

(* git's output for rest in the 65536 bytes of out: its status, what was kept and whether there was more *)
fn git_wide {lo:agz}(rest: $L.listv($P.arg_entry), out: !$A.arr(byte, lo, 65536))
  : @(int, [k:nat | k <= 65536] int k, bool) = tool_output_wide("git", rest, out)

(* The diff of one path over the pull request, without context lines or renames: only the changed lines *)
fn diff_of {lc,lo:agz}{sn:nat | sn < $B.BUILDER_CAP}
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, out: !$A.arr(byte, lo, 65536))
  : @(int, [k:nat | k <= 65536] int k, bool) =
  git_wide(word("diff", word("--no-color", word("--no-ext-diff", word("--no-renames", word("-U0",
    $L.list_vt_cons(range_arg(cmd), word("--", word(path, $L.list_vt_nil())))))))), out)

(* git -C dir rest, the dir being the checkout that holds the pin's repository: which 0 the compiler's, 1 the package repository's *)
fn dir_known (which: int): bool =
  if which = 0 then !g_compiler_at >= 0 else repository_known(!g_repo_at)

fn dir_arg {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), which: int): $P.arg_entry =
  if which = 0 then copy_arg(cmd, !g_compiler_at, !g_compiler_to) else repository_arg(cmd, !g_repo_at, !g_repo_to)

fn in_dir {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), which: int, rest: $L.listv($P.arg_entry))
  : $L.listv($P.arg_entry) = $L.list_vt_cons(literal_arg("-C"), $L.list_vt_cons(dir_arg(cmd, which), rest))

fn say_dir {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), which: int): void =
  if which = 0 then print_borrow(cmd, !g_compiler_at, !g_compiler_to, 4096)
  else if !g_repo_at >= 0 then print_borrow(cmd, !g_repo_at, !g_repo_to, 4096)
  else print! ("$BATS_REPOSITORY")

(* ------------------------------------------------------------------ *)
(* The verdicts and their exit statuses (keyword: pins-check) *)

(* The start of a NOT OK line about a path; the reason follows, then a newline *)
fn not_ok_head (path: string): void = let
  val () = print! ("NOT OK: ", path, ": ")
  val () = (!g_failures := !g_failures + 1)
in (if get_exit_code() = 0 then set_exit_code(1) else ()) end

fn not_ok (path: string, why: string): void = let
  val () = not_ok_head(path)
  val () = print! (why)
in print_newline() end

fn git_error (what: string): void = let
  val () = prerr! ("error: bats pins-check: ", what)
  val () = prerr_newline()
in set_exit_code(2) end

fn dir_missing (which: int): void =
  if which = 0 then git_error("the checkout of the compiler is not named: --compiler <dir>")
  else git_error("the package repository is not named: --repository <dir>")

(* ------------------------------------------------------------------ *)
(* A pin: 40 lowercase hex digits that a commit of its repository's checkout has (keyword: pins-check) *)

(* Whether the checkout has the commit bv[at, at + 40) *)
fn commit_exists {lc,lb:agz}{n:pos}{m:nat | m <= n}
  (cmd: !$A.borrow(byte, lc, 4096), which: int, bv: !$A.borrow(byte, lb, n), at: pos_t, m: int m): bool =
  git_status(in_dir(cmd, which, word("cat-file", word("-e",
    $L.list_vt_cons(commit_arg(bv, at, m, "^{commit}"), $L.list_vt_nil()))))) = 0

(* The required commit (--require-contains) against the pin bv[at, at + 40): 1 when the checkout has the required
   commit, and then the pin must have it as an ancestor or be it; 0 when the checkout does not have it *)
fn required_in {lc,lb:agz}{n:pos}{m:nat | m <= n}{sn:nat | sn < $B.BUILDER_CAP}
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, which: int, bv: !$A.borrow(byte, lb, n), at: pos_t, m: int m): int =
  if !g_require_at < 0 then 0
  else let
    var req : $B.builder_v = $B.create()
    val () = copy_to_builder_v(cmd, !g_require_at, !g_require_to, 4096, req)
    val () = bput_v(req, "^{commit}")
    val has = git_status(in_dir(cmd, which, word("cat-file", word("-e", $L.list_vt_cons(mk_arg(req), $L.list_vt_nil())))))
  in
    if has <> 0 then 0
    else let
      val contained = git_status(in_dir(cmd, which, word("merge-base", word("--is-ancestor",
        $L.list_vt_cons(copy_arg(cmd, !g_require_at, !g_require_to),
        $L.list_vt_cons(commit_arg(bv, at, m, ""), $L.list_vt_nil()))))))
    in
      if contained = 0 then 1
      else let
        val () = not_ok_head(path)
        val () = print! ("the pin ")
        val () = print_borrow(bv, at, at + 40, m)
        val () = print! (" does not contain the required commit ")
        val () = print_borrow(cmd, !g_require_at, !g_require_to, 4096)
        val () = print_newline()
      in 1 end
    end
  end

(* A pin bv[at, at + 40) that moved: 0 when its checkout has no such commit (said), else 1, or 2 when the required
   commit was looked for in this checkout *)
fn pin_commit {lc,lb:agz}{n:pos}{m:nat | m <= n}{sn:nat | sn < $B.BUILDER_CAP}
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, which: int, bv: !$A.borrow(byte, lb, n), at: pos_t, m: int m): int =
  if ~dir_known(which) then let
    val () = dir_missing(which)
  in 0 end
  else if ~commit_exists(cmd, which, bv, at, m) then let
    val () = not_ok_head(path)
    val () = print! ("the pin ")
    val () = print_borrow(bv, at, at + 40, m)
    val () = print! (" is not a commit of ")
    val () = say_dir(cmd, which)
    val () = print_newline()
  in 0 end
  else if required_in(cmd, path, which, bv, at, m) = 1 then 2
  else 1

(* The new pin bv[at, at + 40) against the old one bv[old_at, old_at + 40): the old is an ancestor of the new *)
fn pin_ahead {lc,lb:agz}{n:pos}{m:nat | m <= n}{sn:nat | sn < $B.BUILDER_CAP}
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, which: int, bv: !$A.borrow(byte, lb, n), at: pos_t, old_at: pos_t, m: int m): void = let
  val status = git_status(in_dir(cmd, which, word("merge-base", word("--is-ancestor",
    $L.list_vt_cons(commit_arg(bv, old_at, m, ""), $L.list_vt_cons(commit_arg(bv, at, m, ""), $L.list_vt_nil()))))))
in
  if status = 0 then ()
  else if status = 1 then let
    (* not ahead: behind when the new pin is an ancestor of the old, else the two have diverged (the old one was never on the
       history of the new, as a commit that a rewrite of main dropped is) and the move is said, not refused *)
    val behind = git_status(in_dir(cmd, which, word("merge-base", word("--is-ancestor",
      $L.list_vt_cons(commit_arg(bv, at, m, ""), $L.list_vt_cons(commit_arg(bv, old_at, m, ""), $L.list_vt_nil()))))))
  in
    if behind = 0 then let
      val () = not_ok_head(path)
      val () = print! ("the new pin ")
      val () = print_borrow(bv, at, at + 40, m)
      val () = print! (" is behind the old pin ")
      val () = print_borrow(bv, old_at, old_at + 40, m)
      val () = print_newline()
    in () end
    else let
      val () = print! ("note: ", path, ": the old pin ")
      val () = print_borrow(bv, old_at, old_at + 40, m)
      val () = print! (" is not an ancestor of the new pin ")
      val () = print_borrow(bv, at, at + 40, m)
      val () = print! (" (the two have diverged)")
    in print_newline() end
  end
  else let
    val () = not_ok_head(path)
    val () = print! ("the old pin ")
    val () = print_borrow(bv, old_at, old_at + 40, m)
    val () = print! (" is not a commit of ")
    val () = say_dir(cmd, which)
    val () = print_newline()
  in () end
end

(* The old line of a pin file (bv[b, m) is the diff's hunk): when there is one it is a pin too, and the new pin is ahead of it *)
fn old_pin {lc,lb:agz}{n:pos}{m:nat | m <= n}{b:nat | b <= m}{sn:nat | sn < $B.BUILDER_CAP}
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, which: int, bv: !$A.borrow(byte, lb, n), b: int b, m: int m, at: pos_t): void = let
  val os = find_prefix(bv, b, m, 45)
in
  if os < 0 then ()
  else let
    val oe = line_end(bv, os + 1, m)
  in
    if oe - (os + 1) <> 40 then not_ok(path, "the old line is not a pin of 40 hex digits")
    else if ~hex_run(bv, os + 1, m, 0, 40) then not_ok(path, "the old line is not a pin of 40 lowercase hex digits")
    else pin_ahead(cmd, path, which, bv, at, os + 1, m)
  end
end

(* The new pin of a pin file *)
fn new_pin {lc,lb:agz}{n:pos}{m:nat | m <= n}{b:nat | b <= m}{ps:nat | ps < m}{sn:nat | sn < $B.BUILDER_CAP}
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, which: int, bv: !$A.borrow(byte, lb, n), b: int b, m: int m, ps: int ps): int = let
  val pe = line_end(bv, ps + 1, m)
in
  if pe - (ps + 1) <> 40 then let
    val () = not_ok(path, "the new line is not a pin of 40 hex digits")
  in 0 end
  else if ~hex_run(bv, ps + 1, m, 0, 40) then let
    val () = not_ok(path, "the new line is not a pin of 40 lowercase hex digits")
  in 0 end
  else let
    val here = pin_commit(cmd, path, which, bv, ps + 1, m)
    val () = (if here >= 1 then old_pin(cmd, path, which, bv, b, m, ps + 1) else ())
  in (if here = 2 then 1 else 0) end
end

(* A pin file the diff touches: it ends up holding one line, a pin that exists, ahead of the one before.
   Answers 1 when the required commit was looked for in the checkout of its pin. *)
fn pin_file {lc:agz}{sn:nat | sn < $B.BUILDER_CAP}(cmd: !$A.borrow(byte, lc, 4096), path: string sn, which: int): int = let
  val buf = $A.alloc<byte>(65536)
  val @(status, kept, longer) = diff_of(cmd, path, buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val before = !g_failures
  val resolved = (if status <> 0 then let
      val () = git_error("git did not answer for the diff of a pin file")
    in 0 end
    else if longer then let
      val () = not_ok(path, "the diff is longer than a pin move is")
    in 0 end
    else let
      val b = body_start(bv, 0, kept)
      val plus = count_prefix(bv, b, kept, 43, 0)
      val minus = count_prefix(bv, b, kept, 45, 0)
    in
      if plus <> 1 then let
        val () = not_ok(path, "the file does not end up holding exactly one line (deleted, or more than one new line)")
      in 0 end
      else if minus > 1 then let
        val () = not_ok(path, "the file had more than one line")
      in 0 end
      else let
        val ps = find_prefix(bv, b, kept, 43)
      in
        if ps < 0 then 0 else new_pin(cmd, path, which, bv, b, kept, ps)
      end
    end): int
  val () = (if !g_failures = before && get_exit_code() = 0 then println! ("ok   ", path) else ())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in resolved end

(* ------------------------------------------------------------------ *)
(* A workflow: every changed line is a pin, and a pin of the compiler or the package repository exists (keyword: pins-check) *)

fn say_line {l:agz}{n:pos}{m:nat | m <= n}(bv: !$A.borrow(byte, l, n), p: pos_t, e: int, m: int m): void = let
  val () = print_borrow(bv, p, e, m)
in print_newline() end

(* The first position of bv[p, e) that is no space, or e *)
fun spaces_end {l:agz}{n:pos}{e:nat | e <= n}{p:nat | p <= e} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if peek(bv, p, e) = 32 then spaces_end(bv, p + 1, e)
  else p

(* Each changed line of the hunks bv[p, m), a comment line (the first byte that is no space is #) being no code: the sum of the answers of pin_commit for the new lines of the compiler's or the package repository's
   workflows, in the form 1 when the required commit was looked for *)
fun workflow_lines {lc,lb:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m}{sn:nat | sn < $B.BUILDER_CAP} .<m - p>.
  (cmd: !$A.borrow(byte, lc, 4096), path: string sn, bv: !$A.borrow(byte, lb, n), p: int p, m: int m, resolved: int): int =
  if p >= m then resolved
  else let
    val e = line_end(bv, p, m)
    val c = peek(bv, p, m)
    val next = next_line(bv, p, m)
  in
    if c <> 43 && c <> 45 then workflow_lines(cmd, path, bv, next, m, resolved)
    else if e < p + 1 then workflow_lines(cmd, path, bv, next, m, resolved)
    else if peek(bv, spaces_end(bv, p + 1, e), e) = 35 then workflow_lines(cmd, path, bv, next, m, resolved)
    else let
      val t = find_pin_token(bv, p + 1, e)
    in
      if t < 0 then let
        val () = not_ok_head(path)
        val () = print! ("a changed line holds no pin of 40 hex digits: ")
        val () = say_line(bv, p, e, m)
      in workflow_lines(cmd, path, bv, next, m, resolved) end
      else if c = 45 then workflow_lines(cmd, path, bv, next, m, resolved)
      else let
        val which = (if contains_text(bv, p + 1, e, "bats-lang/repository-prototype/") then 1
          else if contains_text(bv, p + 1, e, "bats-lang/bats/") then 0
          else ~1): int
        val here = (if which >= 0 then pin_commit(cmd, path, which, bv, t, m) else 0): int
        val counted = (if here = 2 then 1 else 0): int
      in workflow_lines(cmd, path, bv, next, m, resolved + counted) end
    end
  end

fn workflow_file {lc:agz}{sn:nat | sn < $B.BUILDER_CAP}(cmd: !$A.borrow(byte, lc, 4096), path: string sn): int = let
  val buf = $A.alloc<byte>(65536)
  val @(status, kept, longer) = diff_of(cmd, path, buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val before = !g_failures
  val resolved = (if status <> 0 then let
      val () = git_error("git did not answer for the diff of a workflow")
    in 0 end
    else if longer then let
      val () = not_ok(path, "the diff is longer than a pin move is")
    in 0 end
    else workflow_lines(cmd, path, bv, body_start(bv, 0, kept), kept, 0)): int
  val () = (if !g_failures = before && get_exit_code() = 0 then println! ("ok   ", path) else ())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in resolved end

(* ------------------------------------------------------------------ *)
(* bats.lock: its new lines are well formed, move forward, and have the sha256 of the sidecar (keyword: pins-check) *)

(* The start of the removed line of the package bv[name_at, name_to) in the hunks bv[p, m), or ~1 *)
fun find_removed {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m}{na,nt:nat | na <= nt; nt <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, name_at: int na, name_to: int nt): [r:int | r == ~1 || (0 <= r && r < m)] int r =
  if p >= m then ~1
  else let
    val e = line_end(bv, p, m)
    val next = next_line(bv, p, m)
    val len = name_to - name_at
  in
    if peek(bv, p, m) <> 45 then find_removed(bv, next, m, name_at, name_to)
    else if p + 1 + len >= e then find_removed(bv, next, m, name_at, name_to)
    else if peek(bv, p + 1 + len, m) <> 32 then find_removed(bv, next, m, name_at, name_to)
    else if span_eq(bv, p + 1, name_at, m, len, 0) then p
    else find_removed(bv, next, m, name_at, name_to)
  end

(* The head of a NOT OK line about a lock entry *)
fn lock_head {l:agz}{n:pos}{m:nat | m <= n}
  (bv: !$A.borrow(byte, l, n), name_at: pos_t, version_to: int, m: int m): void = let
  val () = not_ok_head("bats.lock")
  val () = print_borrow(bv, name_at, version_to, m)
in print! (": ") end

(* One new line of the lock, whose name is bv[name_at, name_to), version bv[version_at, version_to) and sha256 at sha_at;
   the hunks are bv[b, kept) *)
fn lock_entry {lc,lb,lp:agz}{kept:nat | kept <= 65536}{b:nat | b <= kept}{na,nt,va,vt,sa:nat | na <= nt; nt < va; va <= vt; vt < sa; sa <= kept}
  (cmd: !$A.borrow(byte, lc, 4096), bv: !$A.borrow(byte, lb, 65536), pin: !$A.borrow(byte, lp, 4096),
   b: int b, kept: int kept, name_at: int na, name_to: int nt, version_at: int va, version_to: int vt, sha_at: int sa): void = let
  val removed = find_removed(bv, b, kept, name_at, name_to)
  val () = (if removed < 0 then ()
    else let
      val old_end = line_end(bv, removed, kept)
      val old_version_at = removed + 1 + (name_to - name_at) + 1
    in
      if old_version_at > old_end then ()
      else let
        val old_version_to = char_end(bv, old_version_at, old_end, 32)
        val order = ver_cmp(bv, version_at, version_to, old_version_at, old_version_to, kept)
      in
        if order = 2 then let
          val () = lock_head(bv, name_at, version_to, kept)
        in println! ("a version is not numbers separated by dots, so it cannot be compared with the old line") end
        else if order < 0 then let
          val () = lock_head(bv, name_at, version_to, kept)
        in println! ("the version moves backwards") end
        else if order = 0 && ~span_eq(bv, sha_at, old_version_to + 1, kept, 64, 0) then let
          val () = lock_head(bv, name_at, version_to, kept)
        in println! ("the version stayed and its sha256 changed") end
        else ()
      end
    end)
  val () = (case+ check_entry(bv, name_at, name_to, version_at, version_to, sha_at, 65536, pin, cmd, !g_repo_at, !g_repo_to) of
    | LocksPassed() => ()
    | LocksNotInRepository() => let
        val () = lock_head(bv, name_at, version_to, kept)
      in println! ("is not in the package repository at the commit of .github/repository-version") end
    | LocksDiffers() => let
        val () = lock_head(bv, name_at, version_to, kept)
      in println! ("has another sha256 than the sidecar of the package repository at the commit of .github/repository-version") end
    | LocksGitFailed() => let
        val () = lock_head(bv, name_at, version_to, kept)
      in println! ("could not be looked up: git did not run") end
    | _ => let
        val () = lock_head(bv, name_at, version_to, kept)
      in println! ("could not be checked against the package repository") end)
in () end

fn lock_bad {l:agz}{n:pos}{m:nat | m <= n}(bv: !$A.borrow(byte, l, n), p: pos_t, e: int, m: int m): void = let
  val () = not_ok_head("bats.lock")
  val () = print! ("a new line is not `<package> <version> <sha256>`: ")
in say_line(bv, p, e, m) end

(* Each new line of the hunks bv[p, kept) of the lock *)
fun lock_lines {lc,lb,lp:agz}{kept:nat | kept <= 65536}{b:nat | b <= kept}{p:nat | p <= kept} .<kept - p>.
  (cmd: !$A.borrow(byte, lc, 4096), bv: !$A.borrow(byte, lb, 65536), pin: !$A.borrow(byte, lp, 4096),
   b: int b, p: int p, kept: int kept): void =
  if p >= kept then ()
  else let
    val e = line_end(bv, p, kept)
    val next = next_line(bv, p, kept)
  in
    if peek(bv, p, kept) <> 43 then lock_lines(cmd, bv, pin, b, next, kept)
    else if e < p + 1 then lock_lines(cmd, bv, pin, b, next, kept)
    else let
      val name_at = p + 1
      val name_to = char_end(bv, name_at, e, 32)
      val () = (if name_to <= name_at then lock_bad(bv, p, e, kept)
        else if name_to >= e then lock_bad(bv, p, e, kept)
        else let
          val version_at = name_to + 1
          val version_to = char_end(bv, version_at, e, 32)
        in
          if version_to <= version_at then lock_bad(bv, p, e, kept)
          else if version_to >= e then lock_bad(bv, p, e, kept)
          else let
            val sha_at = version_to + 1
          in
            if e - sha_at <> 64 then lock_bad(bv, p, e, kept)
            else if ~hex_run(bv, sha_at, kept, 0, 64) then lock_bad(bv, p, e, kept)
            else lock_entry(cmd, bv, pin, b, kept, name_at, name_to, version_at, version_to, sha_at)
          end
        end)
    in lock_lines(cmd, bv, pin, b, next, kept) end
  end

(* The head's .github/repository-version, whose commit the sidecars are read at *)
fn lock_with_pin {lc,lb:agz}{kept:nat | kept <= 65536}{b:nat | b <= kept}
  (cmd: !$A.borrow(byte, lc, 4096), bv: !$A.borrow(byte, lb, 65536), b: int b, kept: int kept): void = let
  val pin_buf = $A.alloc<byte>(4096)
  val @(status, pin_len) = tool_output("git", word("show", $L.list_vt_cons(head_file_arg(cmd, ".github/repository-version"), $L.list_vt_nil())), pin_buf)
  val @(fz_pin, pin) = $A.freeze<byte>(pin_buf)
  val () = (if status <> 0 then not_ok("bats.lock", "the sidecars are read at the commit of .github/repository-version, which the head does not have")
    else if pin_len < 40 then not_ok("bats.lock", ".github/repository-version is not a pin of 40 hex digits")
    else if ~hex_run(pin, 0, 4096, 0, 40) then not_ok("bats.lock", ".github/repository-version is not a pin of 40 lowercase hex digits")
    else if ~repository_known(!g_repo_at) then dir_missing(1)
    else lock_lines(cmd, bv, pin, b, b, kept))
  val () = $A.drop<byte>(fz_pin, pin)
  val () = $A.free<byte>($A.thaw<byte>(fz_pin))
in () end

fn lock_file {lc:agz}(cmd: !$A.borrow(byte, lc, 4096)): void = let
  val buf = $A.alloc<byte>(65536)
  val @(status, kept, longer) = diff_of(cmd, "bats.lock", buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val before = !g_failures
  val () = (if status <> 0 then git_error("git did not answer for the diff of bats.lock")
    else if longer then not_ok("bats.lock", "the diff is longer than 65536 bytes, which a lock move is not")
    else lock_with_pin(cmd, bv, body_start(bv, 0, kept), kept))
  val () = (if !g_failures = before && get_exit_code() = 0 then println! ("ok   bats.lock") else ())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in () end

(* ------------------------------------------------------------------ *)
(* Which files changed (keyword: pins-check) *)

(* Whether one line of the names is the path *)
fun names_has {l:agz}{m:nat | m <= 65536}{p:nat | p <= m}{sn:nat} .<m - p>.
  (names: !$A.borrow(byte, l, 65536), p: int p, m: int m, path: string sn): bool =
  if p >= m then false
  else if span_is(names, p, line_end(names, p, m), path) then true
  else names_has(names, next_line(names, p, m), m, path)

(* Each changed path that is not one of the five a pin move touches is said *)
fun names_check {l:agz}{m:nat | m <= 65536}{p:nat | p <= m} .<m - p>.
  (names: !$A.borrow(byte, l, 65536), p: int p, m: int m): void =
  if p >= m then ()
  else let
    val e = line_end(names, p, m)
    val allowed = (span_is(names, p, e, ".github/bats-version") || span_is(names, p, e, ".github/repository-version")
      || span_is(names, p, e, "bats.lock") || span_is(names, p, e, ".github/workflows/relock.yml")
      || span_is(names, p, e, ".github/workflows/publish.yml")): bool
    val () = (if allowed then () else let
        val () = not_ok_head("the diff")
        val () = print_borrow(names, p, e, m)
      in println! (" is not a pin file (only .github/bats-version, .github/repository-version, bats.lock, .github/workflows/relock.yml and .github/workflows/publish.yml are)") end)
  in names_check(names, next_line(names, p, m), m) end

(* ------------------------------------------------------------------ *)
(* The checks, over the files the diff touches (keyword: pins-check) *)

fn prove {lc:agz}(cmd: !$A.borrow(byte, lc, 4096)): void = let
  val buf = $A.alloc<byte>(65536)
  val @(status, kept, longer) = git_wide(word("diff", word("--name-only", word("--no-renames", word("--no-color",
    $L.list_vt_cons(range_arg(cmd), $L.list_vt_nil()))))), buf)
  val @(fz, names) = $A.freeze<byte>(buf)
  val () = (if status <> 0 then git_error("git did not answer for the diff of the two revisions")
    else if longer then not_ok("the diff", "it has more changed paths than a pin move has")
    else if kept = 0 then not_ok("the diff", "no file changed")
    else let
      val () = names_check(names, 0, kept)
      val from_compiler = (if names_has(names, 0, kept, ".github/bats-version")
        then pin_file(cmd, ".github/bats-version", 0) else 0): int
      val from_repository = (if names_has(names, 0, kept, ".github/repository-version")
        then pin_file(cmd, ".github/repository-version", 1) else 0): int
      val from_relock = (if names_has(names, 0, kept, ".github/workflows/relock.yml")
        then workflow_file(cmd, ".github/workflows/relock.yml") else 0): int
      val from_publish = (if names_has(names, 0, kept, ".github/workflows/publish.yml")
        then workflow_file(cmd, ".github/workflows/publish.yml") else 0): int
      val resolved = from_compiler + from_repository + from_relock + from_publish
      val () = (if names_has(names, 0, kept, "bats.lock") then lock_file(cmd) else ())
      val () = (if !g_require_at >= 0 && resolved = 0 && !g_failures = 0
        then not_ok("--require-contains", "no moved pin is in a checkout that has the required commit, so none could be shown to contain it")
        else ())
    in
      if !g_failures = 0 && get_exit_code() = 0 then let
        val () = print! ("OK: ")
        val () = print_borrow(cmd, !g_base_at, !g_base_to, 4096)
        val () = print! ("...")
        val () = print_borrow(cmd, !g_head_at, !g_head_to, 4096)
      in println! (" changes only pins") end
      else ()
    end)
  val () = $A.drop<byte>(fz, names)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in () end

(* ------------------------------------------------------------------ *)
(* The command line (keyword: pins-check) *)

fn usage_error (): void = let
  val () = prerr! ("usage: bats pins-check <base> <head> [--compiler <dir>] [--repository <dir>] [--require-contains <sha>] (neither revision starts with -)")
  val () = prerr_newline()
in set_exit_code(2) end

(* Whether cmd[at, to) is exactly the flag s *)
fn flag_is {lc:agz}{at,to:int}{sn:nat}(cmd: !$A.borrow(byte, lc, 4096), at: int at, to: int to, s: string sn): bool = let
  val len = g1u2i(string1_length(s))
in
  if to - at <> len then false else named_file(cmd, at, to, s, len)
end

(* The options cmd[p, total), each a flag and its value, each at most once; they are kept in the spans above *)
fun options {lc:agz}{p:nat | p <= 4096} .<4096 - p>.
  (cmd: !$A.borrow(byte, lc, 4096), p: int p, total: int): bool =
  if p >= total then true
  else let
    val z = find_nul(cmd, p)
  in
    if z + 1 > 4096 then false
    else let
      val value_at = z + 1
      val value_to = find_nul(cmd, value_at)
    in
      if value_to = value_at then false
      else if value_to + 1 > 4096 then false
      else if flag_is(cmd, p, z, "--compiler") then
        (if !g_compiler_at >= 0 then false else let
          val () = (!g_compiler_at := value_at)
          val () = (!g_compiler_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--repository") then
        (if !g_repo_at >= 0 then false else let
          val () = (!g_repo_at := value_at)
          val () = (!g_repo_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--require-contains") then
        (if !g_require_at >= 0 then false
        else if value_to - value_at <> 40 then false
        else if ~hex_run(cmd, value_at, 4096, 0, 40) then false
        else let
          val () = (!g_require_at := value_at)
          val () = (!g_require_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else false
    end
  end

(* Reads the arguments after the command name *)
fn run_pins_check {lc:agz}{first:nat | first <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), first: int first, total: int): void = let
  val base_to = find_nul(cmd, first)
in
  if base_to = first then usage_error()
  else if base_to + 1 > 4096 then usage_error()
  else let
    val head_at = base_to + 1
    val head_to = find_nul(cmd, head_at)
  in
    if head_to = head_at then usage_error()
    else if head_to + 1 > 4096 then usage_error()
    else if peek(cmd, first, 4096) = 45 then usage_error()
    else if peek(cmd, head_at, 4096) = 45 then usage_error()
    else let
      val () = (!g_base_at := first)
      val () = (!g_base_to := base_to)
      val () = (!g_head_at := head_at)
      val () = (!g_head_to := head_to)
    in
      if options(cmd, head_to + 1, total) then prove(cmd) else usage_error()
    end
  end
end

(* Where the arguments start, or ~1 when argv[1] is not pins-check *)
fn arguments_at {l:agz}
  (cmd: !$A.borrow(byte, l, 4096)): [r:int | r == ~1 || (0 <= r && r <= 4096)] int r = let
  val a = find_nul(cmd, 0) + 1
in
  if a > 4096 then ~1
  else let
    val z = find_nul(cmd, a)
  in
    if z - a <> 10 then ~1
    else if z + 1 > 4096 then ~1
    else if named_file(cmd, a, z, "pins-check", 10) then z + 1
    else ~1
  end
end

(* Runs the command when it is the one given (keyword: pins-check) *)
#pub fn pins_check_main (): bool

implement pins_check_main () = let
  val buf = $A.alloc<byte>(4096)
  val read = $E.args_read(buf, 4096)
  val @(fz, cmd) = $A.freeze<byte>(buf)
  val handled = (case+ read of
    | ~$R.none() => false
    | ~$R.some(total) => let
        val first = arguments_at(cmd)
      in
        if first < 0 then false
        else let
          val () = (if total >= 4096 then let
              val () = prerr! ("error: bats pins-check: the command line is longer than 4095 bytes")
              val () = prerr_newline()
            in set_exit_code(2) end
            else if first >= total then usage_error()
            else run_pins_check(cmd, first, total))
        in true end
      end): bool
  val () = $A.drop<byte>(fz, cmd)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
