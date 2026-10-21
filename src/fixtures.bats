(* fixtures -- bats fixtures <dir> [--only <member>]... [--cold] [--work <dir>]
   [--memo <dir>] [--prune] [--repository <dir>] (bats-lang/bats#267, item 4: quire's static-test
   runner, tests/static/run.sh and expect.py, folded into bats).

   <dir> holds fixtures, each a directory

     <dir>/accept/<name>/  file, before, snippet.bats
     <dir>/reject/<name>/  file, before, snippet.bats, expect

   A fixture is not a package of its own, because what it tests is private
   to a module: its snippet is put into a copy of the project (the current
   directory), in the module `file` names (a path from the project's
   root), followed by one blank line, before the first line of that module
   that is exactly `before`. An accept fixture must then pass `bats check`;
   a reject fixture must fail it, and exactly as its `expect` says:

     function <the snippet's declaration the error is in>
     line <the line of snippet.bats patsopt reports it at>
     <patsopt's error as it says it: its message after "error(N): " and the
      lines it adds to it>

   patsopt's errors must all be in the module `file`, at that line of the
   snippet, inside that function, and their text, line for line, that text;
   nothing else may fail. A substring that another error could also hold is
   not enough. Only patsopt's variable numbers, which change with anything
   before the snippet, are compared as "_": the number of S2EVar(N->, of
   $N( and of S2Evar(name(N)). An expect that is not "function <name>",
   "line <n>", then the error is an error of the fixture, never a pass.

   The project is copied to <work>/app (everything but build, dist, .git,
   node_modules and test-results; bats_modules is copied), checked whole
   first (the fixtures mean nothing if it does not check), and its build/
   kept in <work>/build-checked, put back after each fixture, so each
   starts from the project as the check left it and only its module is
   checked again. With --work the directory is kept (and the app's build/
   in it is reused by the next run, for a CI to restore); else a temporary
   one is made and removed. Fixtures run one after another, each one line
   as run.sh printed it:

     ok   accept/<name> (N s)
     FAIL reject/<name>: rejected, but not as its expect says: <why>

   --only <member> (repeatable; accept/<name> or reject/<name>) runs only
   those. The exit status is 1 when anything failed, 2 for a usage error.

   The memo (below, "the memo") keeps the result of a fixture's check, so a
   second run does not run patsopt on what it already said; --cold reads
   no memo and audits it, --prune removes what a run did not use. *)

#include "share/atspre_staload.hats"

#use arith as AR
#use array as A
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R
#use sha256 as SHA

staload "helpers.sats"
staload "cache.sats"
staload "lock.sats"

(* An int of any index: what a function takes or answers when its index is
   not needed outside it (the sort-less int the prelude writes int as is not
   an indexed one, which peek, digits_end and the like are given) *)
typedef xi = [i:int] int i

(* The length of a text read whole: at most 524288 bytes *)
typedef tlen = [n:nat | n <= 524288] int n

(* ============================================================
   Text: a file read whole, at most 524288 bytes, with its length
   ============================================================ *)

(* The byte of bv[0, len) at p, or 0 outside it *)
fn byte_at {l:agz} (bv: !$A.borrow(byte, l, 524288), len: xi, p: xi): int =
  if p < 0 then 0
  else if p >= len then 0
  else peek(bv, p, 524288)

(* Whether the bytes of s are those of bv at p + i, from i on *)
fun text_has_from {l:agz}{sl:nat}{i:nat | i <= sl} .<sl - i>.
  (bv: !$A.borrow(byte, l, 524288), len: xi, p: xi, s: string sl, slen: int sl, i: int i): bool =
  if i >= slen then true
  else if byte_at(bv, len, p + i) = char2int0(string_get_at(s, i))
  then text_has_from(bv, len, p, s, slen, i + 1)
  else false

(* Whether bv holds the text s at p *)
fn text_has {l:agz}{sl:nat} (bv: !$A.borrow(byte, l, 524288), len: xi, p: xi, s: string sl): bool =
  text_has_from(bv, len, p, s, g1u2i(string1_length(s)), 0)

(* p after the text s when bv holds it at p, else ~1 (a p below 0 stays ~1):
   the text is within bv[0, len), which is checked, so what is answered
   is a position of it *)
fn step_text {l:agz}{len:nat | len <= 524288}{sl:nat}{p:int}
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, s: string sl): [r:int | r < 0 || (p <= r && r <= len)] int r =
  if p < 0 then ~1
  else if p + g1u2i(string1_length(s)) <= len then
    (if text_has_from(bv, len, p, s, g1u2i(string1_length(s)), 0) then p + g1u2i(string1_length(s)) else ~1)
  else ~1

(* The first position at or after p holding a non-digit *)
fun digits_end {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else let
    val c = peek(bv, p, 524288)
  in
    if c >= 48 && c <= 57 then digits_end(bv, len, p + 1) else p
  end

(* p after the digits at p (at least one), else ~1 *)
fn step_digits {l:agz}{len:nat | len <= 524288}{p:int}
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p): [r:int | r < 0 || (p < r && r <= len)] int r =
  if p < 0 then ~1
  else if p >= len then ~1
  else let
    val e = digits_end(bv, len, p)
  in if e > p then e else ~1 end

(* The value of the digits of bv[p, q), at most 10^9 *)
fun digits_value {l:agz}{len:nat | len <= 524288}{p,q:nat | p <= q; q <= len} .<q - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, q: int q, acc: int): int =
  if p >= q then acc
  else if acc > 100000000 then 1000000000
  else digits_value(bv, len, p + 1, q, acc * 10 + (peek(bv, p, 524288) - 48))

(* The end of the line that starts at p: the first '\n' (or '\r' too when
   crlf, as Python's splitlines breaks a log), else len *)
fun line_end {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, crlf: bool): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else let
    val c = peek(bv, p, 524288)
  in
    if c = 10 then p
    else if crlf && c = 13 then p
    else line_end(bv, len, p + 1, crlf)
  end

(* Where the next line starts, given the line ended at e < len: after the
   terminator, which is "\r\n" as one when crlf *)
fn next_line {l:agz}{len:nat | len <= 524288}{e:nat | e < len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, e: int e, crlf: bool): [r:nat | e < r; r <= len] int r =
  if e + 1 < len then
    (if crlf && peek(bv, e, 524288) = 13 && peek(bv, e + 1, 524288) = 10 then e + 2 else e + 1)
  else e + 1

(* Whitespace as Python's str.strip takes it (ASCII) *)
fn is_space (c: int): bool = c = 32 || (c >= 9 && c <= 13) || (c >= 28 && c <= 31)

(* The first position at or after p, below b, that is not whitespace *)
fun skip_space {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else if p >= b then p
  else if is_space(peek(bv, p, 524288)) then skip_space(bv, len, p + 1, b)
  else p

(* b less the whitespace that ends bv[a, b) *)
fun trim_end {l:agz}{len:nat | len <= 524288}{a:nat}{b:nat | a <= b; b <= len} .<b>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, a: int a, b: int b): [r:nat | a <= r; r <= b] int r =
  if b <= a then b
  else if is_space(peek(bv, b - 1, 524288)) then trim_end(bv, len, a, b - 1)
  else b

(* len less the line feeds that end bv[0, len) *)
fun trim_feeds {l:agz}{len:nat | len <= 524288} .<len>.
  (bv: !$A.borrow(byte, l, 524288), len: int len): [r:nat | r <= len] int r =
  if len <= 0 then len
  else if peek(bv, len - 1, 524288) = 10 then trim_feeds(bv, len - 1)
  else len

(* Whether bv[a, ae) and cv[c, ce) are the same bytes *)
fun same_range {l:agz}{m:agz}{la:nat}{j:nat | j <= la} .<la - j>.
  (bv: !$A.borrow(byte, l, 524288), blen: xi, a: xi, cv: !$A.borrow(byte, m, 524288), clen: xi, c: xi, la: int la, j: int j): bool =
  if j >= la then true
  else if byte_at(bv, blen, a + j) = byte_at(cv, clen, c + j) then same_range(bv, blen, a, cv, clen, c, la, j + 1)
  else false

(* The bytes b holds *)
fn bytes_in (b: !$B.builder_v >> $B.builder_v): int = $B.length(b)

(* bv[a, b) appended to out *)
fun put_range {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi, out: !$B.builder_v >> $B.builder_v): void =
  if p >= len then ()
  else if p >= b then ()
  else let
    val () = put_char_v(out, peek(bv, p, 524288))
  in put_range(bv, len, p + 1, b, out) end

(* The length a read_text answered as the length of a text: an unreadable
   file (its answer is below 0, and the caller has said so) is an empty one *)
fn text_len (k: [k:int | ~1 <= k; k <= 524288] int k): tlen =
  if k >= 0 then k else 0

(* The first position at or after p of a[0, len) that is not whitespace *)
fun lead_blank {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (a: !$A.arr(byte, l, 524288), len: int len, p: int p): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else if is_space(peek_arr(a, p, 524288)) then lead_blank(a, len, p + 1)
  else p

(* b less the whitespace that ends a[lo, b) *)
fun trail_blank {l:agz}{len:nat | len <= 524288}{lo:nat}{b:nat | lo <= b; b <= len} .<b>.
  (a: !$A.arr(byte, l, 524288), len: int len, lo: int lo, b: int b): [r:nat | lo <= r; r <= b] int r =
  if b <= lo then b
  else if is_space(peek_arr(a, b - 1, 524288)) then trail_blank(a, len, lo, b - 1)
  else b

(* a[from, from + n) moved down to a[0, n) *)
fun shift_down {l:agz}{n:nat | n <= 524288}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(byte, l, 524288), from: xi, n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = poke_arr(a, i, 524288, peek_arr(a, from + i, 524288))
  in shift_down(a, from, n, i + 1) end

(* The file at the NUL-terminated path read into dst, and its length; ~1
   when it cannot be read or holds over 524288 bytes *)
fn read_text {lp:agz}{ld:agz} (path: !$A.borrow(byte, lp, 524288), dst: !$A.arr(byte, ld, 524288)): [k:int | ~1 <= k; k <= 524288] int k = let
  fun copy_text {ls:agz}{m:pos}{n:nat | n < m; n <= 524288}{i:nat | i <= n} .<n - i>.
    (src: !$A.borrow(byte, ls, m), dst: !$A.arr(byte, ld, 524288), n: int n, i: int i): void =
    if i >= n then ()
    else let
      val () = $A.set<byte>(dst, i, $A.read<byte>(src, i))
    in copy_text(src, dst, n, i + 1) end
in
  case+ read_whole(path, 524288) of
  | ~whole_err(_) => ~1
  | ~whole_ok(ar, piece, m, n) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val k = (if n <= 524288 then let val () = copy_text(bv, dst, n, 0) in n end else ~1): [k:int | ~1 <= k; k <= 524288] int k
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in k end
end

(* The path in b (NUL-terminated) as an array *)
fn path_arr (b: $B.builder_v): [l:agz] $A.arr(byte, l, 524288) = let
  val @(a, _) = $B.to_arr(b)
in a end

(* The file whose NUL-terminated path is in b, read into dst as read_text does *)
fn read_file_text {ld:agz} (b: $B.builder_v, dst: !$A.arr(byte, ld, 524288)): [k:int | ~1 <= k; k <= 524288] int k = let
  val a = path_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val r = read_text(bv, dst)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* ============================================================
   What patsopt printed: its errors
   ============================================================ *)

(* Whether the line bv[a, b) starts with a line that ends an error's added
   lines: patsopt's summary, its exit, and bats's own lines *)
fn ends_error {l:agz} (bv: !$A.borrow(byte, l, 524288), len: xi, a: xi): bool =
  text_has(bv, len, a, "typechecking has failed") || text_has(bv, len, a, "exit(ATS)")
  || text_has(bv, len, a, "patsopt(") || text_has(bv, len, a, "error:")
  || text_has(bv, len, a, "warning:") || text_has(bv, len, a, "built ")
  || text_has(bv, len, a, "check ")

(* Whether bv[a, b) holds only whitespace *)
fn is_blank {l:agz}{len:nat | len <= 524288}{a:nat | a <= len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, a: int a, b: xi): bool =
  skip_space(bv, len, a, b) >= b

(* The first position at or after p, below b, of a space (the end of the
   first word of a line) *)
fun word_end {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else if p >= b then p
  else if peek(bv, p, 524288) = 32 then p
  else word_end(bv, len, p + 1, b)

(* A patsopt error's first line,

     <path>.bats: N(line=L, offs=N) -- N(line=N, offs=N): error(N): <message>

   at bv[a, b): whether it is one, where the path ends (before the colon),
   L, and where the message starts *)
fn header_parse {l:agz}{len:nat | len <= 524288}{a:nat | a <= len}{b:nat | b <= len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, a: int a, b: int b):
  @(bool, [pe:int | a <= pe; pe <= len] int pe, int, [m:int | a <= m; m <= len] int m) = let
  val w = word_end(bv, len, a, b)
in
  if w - a >= 7 then
    (if w < b then
      (if peek(bv, w - 1, 524288) = 58 && text_has(bv, len, w - 6, ".bats") && peek(bv, w, 524288) = 32 then
let
 val p2 = step_digits(bv, len, w + 1)
in if p2 >= 0 then let
 val p3 = step_text(bv, len, p2, "(line=")
in if p3 >= 0 then let
 val p4 = step_digits(bv, len, p3)
in if p4 >= 0 then let
val lineno = digits_value(bv, len, p3, p4, 0)
 val p5 = step_text(bv, len, p4, ", offs=")
in if p5 >= 0 then let
 val p6 = step_digits(bv, len, p5)
in if p6 >= 0 then let
 val p7 = step_text(bv, len, p6, ") -- ")
in if p7 >= 0 then let
 val p8 = step_digits(bv, len, p7)
in if p8 >= 0 then let
 val p9 = step_text(bv, len, p8, "(line=")
in if p9 >= 0 then let
 val p10 = step_digits(bv, len, p9)
in if p10 >= 0 then let
 val p11 = step_text(bv, len, p10, ", offs=")
in if p11 >= 0 then let
 val p12 = step_digits(bv, len, p11)
in if p12 >= 0 then let
 val p13 = step_text(bv, len, p12, "): error(")
in if p13 >= 0 then let
 val p14 = step_digits(bv, len, p13)
in if p14 >= 0 then let
 val p15 = step_text(bv, len, p14, "): ")
in if p15 >= 0 then (if p15 <= b then @(true, w - 1, lineno, p15) else @(false, a, 0, a)) else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end else @(false, a, 0, a) end
      else @(false, a, 0, a))
    else @(false, a, 0, a))
  else @(false, a, 0, a)
end

(* An identifier's end: letters, digits and '_', from p *)
fun ident_end {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else let
    val c = peek(bv, p, 524288)
  in
    if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c = 95
    then ident_end(bv, len, p + 1) else p
  end

(* Where a variable number at p ends, to be compared as "_": patsopt
   numbers its variables as it goes, so a change anywhere before the
   snippet renumbers them, and those numbers, only, are:

     S2EVar(<n>->           a unification variable (kind 1)
     $<n>(                  a dynamic variable: handed$6116(-1) (kind 2)
     S2Evar(<name>(<n>))    a static variable (kind 3)

   the end of the match, ~1 when there is none *)
fn variable_end {l:agz}{len:nat | len <= 524288}{p:nat | p <= len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p): [q:int | q < 0 || (p < q && q <= len)] int q = let
  val raw = (if p >= len then ~1
    else if text_has(bv, len, p, "S2EVar(") then step_text(bv, len, step_digits(bv, len, p + 7), "->")
    else if peek(bv, p, 524288) = 36 then step_text(bv, len, step_digits(bv, len, p + 1), "(")
    else if text_has(bv, len, p, "S2Evar(") then let
      val s = p + 7
      val c = byte_at(bv, len, s)
      val named = ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c = 95): bool
    in
      if named then
        (if s < len then step_text(bv, len, step_digits(bv, len, step_text(bv, len, ident_end(bv, len, s), "(")), "))") else ~1)
      else ~1
    end
    else ~1): int
  val r = g1ofg0(raw)
in
  if r > p then (if r <= len then r else ~1) else ~1
end

(* The kind of the variable number at p (variable_end gave its end) *)
fn variable_kind {l:agz}{len:nat | len <= 524288}
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: xi): int =
  if text_has(bv, len, p, "S2EVar(") then 1
  else if byte_at(bv, len, p) = 36 then 2
  else 3

(* What stands for the variable number of the given kind at p *)
fn put_normal {l:agz}{len:nat | len <= 524288}{p:nat | p <= len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, kind: int, out: !$B.builder_v >> $B.builder_v): void =
  if kind = 1 then bput_v(out, "S2EVar(_->")
  else if kind = 2 then bput_v(out, "$_(")
  else let
    val () = bput_v(out, "S2Evar(")
    val s = p + 7
    val () = (if s <= len then put_range(bv, len, s, ident_end(bv, len, s), out) else ())
  in bput_v(out, "(_))") end

(* bv[a, b) appended to out with its variable numbers as "_" *)
fun put_unnumbered {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi, out: !$B.builder_v >> $B.builder_v): void =
  if p >= len then ()
  else if p >= b then ()
  else let
    val q = variable_end(bv, len, p)
    val kind = variable_kind(bv, len, p)
  in
    if q > p then
      (if q <= b then
        (if q <= len then let
          val () = put_normal(bv, len, p, kind, out)
        in put_unnumbered(bv, len, q, b, out) end
        else let
          val () = put_char_v(out, peek(bv, p, 524288))
        in put_unnumbered(bv, len, p + 1, b, out) end)
      else let
        val () = put_char_v(out, peek(bv, p, 524288))
      in put_unnumbered(bv, len, p + 1, b, out) end)
    else let
      val () = put_char_v(out, peek(bv, p, 524288))
    in put_unnumbered(bv, len, p + 1, b, out) end
  end

(* ============================================================
   The snippet's declarations
   ============================================================ *)

(* Whether bv[a, e) is one of the words a declaration starts with *)
fn is_declaration_word {l:agz} (bv: !$A.borrow(byte, l, 524288), len: xi, a: xi, e: xi): bool = let
  fn is {sl:nat} (bv: !$A.borrow(byte, l, 524288), len: xi, a: xi, e: xi, s: string sl): bool =
    e - a = g1u2i(string1_length(s)) && text_has(bv, len, a, s)
in
  is(bv, len, a, e, "fn") || is(bv, len, a, e, "fun") || is(bv, len, a, e, "fnx")
  || is(bv, len, a, e, "prfn") || is(bv, len, a, e, "prfun") || is(bv, len, a, e, "implement")
  || is(bv, len, a, e, "val") || is(bv, len, a, e, "var") || is(bv, len, a, e, "and")
end

(* The first position at or after p, below b, of a whitespace (Python's \s) *)
fun space_from {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi): [r:nat | p <= r; r <= len] int r =
  if p >= len then p
  else if p >= b then p
  else if is_space(peek(bv, p, 524288)) then p
  else space_from(bv, len, p + 1, b)

(* After the {...} groups (each with the whitespace after it) at p, below b:
   the position where a name could start *)
fun skip_groups {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi): xi =
  if p >= len then p
  else if p >= b then p
  else if peek(bv, p, 524288) <> 123 then p
  else let
    (* the first '}' after the '{' *)
    fun close {l:agz}{len:nat | len <= 524288}{q:nat | q <= len} .<len - q>.
      (bv: !$A.borrow(byte, l, 524288), len: int len, q: int q, b: xi): [r:int | r < 0 || (q <= r && r < len)] int r =
      if q >= len then ~1
      else if q >= b then ~1
      else if peek(bv, q, 524288) = 125 then q
      else close(bv, len, q + 1, b)
    val c = close(bv, len, p + 1, b)
  in
    if c < 0 then p
    else if c + 1 > len then p
    else skip_groups(bv, len, skip_space(bv, len, c + 1, b), b)
  end

(* The name the declaration at line bv[a, b) declares as (start, end), if
   it is one: one of the words fn, fun, fnx, prfn, prfun, implement, val,
   var and and, then whitespace, then any number of {...} groups (each
   with the whitespace after it), then a name of letters, digits, '_' and
   '$' that starts with a letter or '_' (expect.py's DECLARATION) *)
fn declared_name {l:agz}{len:nat | len <= 524288}{a:nat | a <= len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, a: int a, b: xi): @(xi, xi) = let
  val w = space_from(bv, len, a, b)
in
  if w >= b then @(~1, ~1)
  else if ~is_declaration_word(bv, len, a, w) then @(~1, ~1)
  else let
    val s = skip_groups(bv, len, skip_space(bv, len, w, b), b)
    val c = byte_at(bv, len, s)
    fun name_end {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
      (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, b: xi): [r:nat | p <= r; r <= len] int r =
      if p >= len then p
      else if p >= b then p
      else let
        val d = peek(bv, p, 524288)
      in
        if (d >= 65 && d <= 90) || (d >= 97 && d <= 122) || (d >= 48 && d <= 57) || d = 95 || d = 36
        then name_end(bv, len, p + 1, b) else p
      end
  in
    if s >= 0 then
      (if s <= len then
        (if s < b then
          (if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c = 95 then @(s, name_end(bv, len, s, b)) else @(~1, ~1))
        else @(~1, ~1))
      else @(~1, ~1))
    else @(~1, ~1)
  end
end

(* The name of the last declaration among the first `upto` lines of the
   snippet bv[0, len) (split at line feeds), as (start, end); (~1, ~1) when
   there is none. k is the number of the line at p. *)
fun enclosing {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, k: int, upto: int, ns: int, ne: int): @(int, int) =
  if k > upto then @(ns, ne)
  else let
    val e = line_end(bv, len, p, false)
    val @(s, t) = declared_name(bv, len, p, e)
    val ns2 = (if s >= 0 then s else ns): int
    val ne2 = (if s >= 0 then t else ne): int
  in
    if e >= len then @(ns2, ne2)
    else enclosing(bv, len, e + 1, k + 1, upto, ns2, ne2)
  end

(* ============================================================
   Whether a reject fixture failed exactly as it says it must
   ============================================================ *)

(* Whether the path bv[a, path_end) ends with "/" and the module mv[0, mlen) *)
fn ends_with_module {l:agz}{ls:agz}
  (bv: !$A.borrow(byte, l, 524288), len: xi, a: xi, path_end: xi,
   mv: !$A.borrow(byte, ls, 524288), mlen: tlen): bool =
  if path_end - mlen - 1 >= a then
    (if byte_at(bv, len, path_end - mlen - 1) = 47 then same_range(bv, len, path_end - mlen, mv, mlen, 0, mlen, 0) else false)
  else false

(* Walks the log's lines from p: each patsopt error is checked in turn
   (its module, then its line), and its text, with the lines added to it,
   is appended to raw as written and to norm with the variable numbers
   as "_", a line feed after each line. A problem is appended to problem
   and ends the walk. Returns the number of errors seen. *)
fun walk_log {l:agz}{ls:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, in_error: bool, count: int,
   mv: !$A.borrow(byte, ls, 524288), mlen: tlen, first: int, want: int,
   raw: !$B.builder_v >> $B.builder_v, norm: !$B.builder_v >> $B.builder_v,
   problem: !$B.builder_v >> $B.builder_v): int = let
  val e = line_end(bv, len, p, true)
  val @(is_header, path_end, lineno, msg) = header_parse(bv, len, p, e)
  (* the path must end with "/" and the module *)
  val in_module = (if is_header then ends_with_module(bv, len, p, path_end, mv, mlen) else false): bool
  val snippet_line = lineno - first + 1
  val continues = (~is_header && in_error && ~ends_error(bv, len, p) && ~is_blank(bv, len, p, e)): bool
  val () = (if is_header then
      (if ~in_module then let
          val () = bput_v(problem, "an error is in ")
          val () = put_range(bv, len, p, path_end, problem)
          val () = bput_v(problem, ", not ")
          val () = put_range(mv, 524288, 0, mlen, problem)
          val () = bput_v(problem, ": ")
        in put_range(bv, len, msg, e, problem) end
      else if snippet_line <> want then let
          val () = bput_v(problem, "an error is at line ")
          val () = put_int_v(problem, snippet_line)
          val () = bput_v(problem, " of its snippet, not ")
          val () = put_int_v(problem, want)
          val () = bput_v(problem, ": ")
        in put_range(bv, len, msg, e, problem) end
      else let
          val () = put_range(bv, len, msg, e, raw)
          val () = put_char_v(raw, 10)
          val () = put_unnumbered(bv, len, msg, e, norm)
        in put_char_v(norm, 10) end)
    else if continues then let
      val () = put_range(bv, len, p, e, raw)
      val () = put_char_v(raw, 10)
      val () = put_unnumbered(bv, len, p, e, norm)
    in put_char_v(norm, 10) end
    else ()): void
  val count2 = (if is_header then count + 1 else count): int
  val still = (if is_header then true else continues): bool
in
  if bytes_in(problem) > 0 then count2
  else if e >= len then count2
  else walk_log(bv, len, next_line(bv, len, e, true), still, count2, mv, mlen, first, want, raw, norm, problem)
end

(* Whether bv[a, ae) is the text "kw" followed by the rest, and the rest's
   start; ~1 if not *)
fn after_word {l:agz}{kl:nat} (bv: !$A.borrow(byte, l, 524288), len: xi, a: xi, kw: string kl): xi =
  if text_has(bv, len, a, kw) then a + g1u2i(string1_length(kw)) else ~1

(* Whether the name sv[ds, de) (the declaration the error is in, if ds is
   not negative) is the function ev[ns, ne) of the expect *)
fn decl_is {l1,l2:agz}
  (sv: !$A.borrow(byte, l1, 524288), slen: tlen, ds: int, de: int,
   ev: !$A.borrow(byte, l2, 524288), elen: xi, ns: xi, ne: xi): bool = let
  val ds1 = g1ofg0(ds)
  val de1 = g1ofg0(de)
in
  if ds1 >= 0 then
    (if de1 - ds1 = ne - ns then
      (if ne >= ns then same_range(sv, slen, ds1, ev, elen, ns, ne - ns, 0) else false)
    else false)
  else false
end

(* The problem with a reject fixture's run, appended to problem (nothing
   when it failed as its expect says). lv is bats check's output; ev, sv
   and mv are the fixture's expect, snippet and module (`file`, trimmed);
   first is the line of the project's module at which the snippet's first
   line is. Each check is made only when none before it found a problem;
   the builders are all consumed on the one path, so none is dropped. *)
fn judge_in {l1,l2,l3,l4:agz}{elen:nat | elen <= 524288}
  (lv: !$A.borrow(byte, l1, 524288), llen: tlen,
   ev: !$A.borrow(byte, l2, 524288), elen: int elen,
   sv: !$A.borrow(byte, l3, 524288), slen: tlen,
   mv: !$A.borrow(byte, l4, 524288), mlen: tlen, first: int,
   problem: !$B.builder_v >> $B.builder_v): void = let
  (* the expect: line 1 "function <name>", line 2 "line <n>", the rest *)
  val e1 = line_end(ev, elen, 0, false)
  val s1 = e1 + 1
  val e2 = (if e1 < elen then line_end(ev, elen, s1, false) else elen): [r:nat | r <= elen] int r
  val whole_form = (e1 < elen && e2 < elen && text_has(ev, elen, 0, "function ")
    && text_has(ev, elen, s1, "line ")): bool
  val ns = (if 9 <= elen then skip_space(ev, elen, 9, e1) else elen): [r:nat | r <= elen] int r
  val ne = (if ns <= e1 then trim_end(ev, elen, ns, e1) else ns): [r:nat | r <= elen] int r
  val ls = (if whole_form then (if s1 + 5 <= elen then skip_space(ev, elen, s1 + 5, e2) else elen) else 0): [r:nat | r <= elen] int r
  val le = (if whole_form then (if ls <= e2 then trim_end(ev, elen, ls, e2) else ls) else 0): [r:nat | r <= elen] int r
  val ld = (if whole_form then step_digits(ev, elen, ls) else ~1): int
  val numeric = (ld >= ls && ld = le && ld > ls): bool
  val wanted = (if numeric then (if ls <= le then digits_value(ev, elen, ls, le, 0) else 0) else 0): int
  val () = (if ~whole_form || ~numeric then
      bput_v(problem, "its expect is not \"function <name>\", \"line <n>\", then the error")
    else ())
  (* the declaration the error is said to be in *)
  val @(ds, de) = enclosing(sv, slen, 0, 1, wanted, ~1, ~1)
  val same = decl_is(sv, slen, ds, de, ev, elen, ns, ne)
  val () = (if bytes_in(problem) = 0 && ~same then let
      val () = bput_v(problem, "line ")
      val () = put_int_v(problem, wanted)
      val () = bput_v(problem, " of its snippet is not in ")
    in put_range(ev, elen, ns, ne, problem) end
    else ())
  (* patsopt's errors: each checked, its text kept *)
  var raw : $B.builder_v = $B.create()
  var norm : $B.builder_v = $B.create()
  val count = (if bytes_in(problem) = 0 then walk_log(lv, llen, 0, false, 0, mv, mlen, first, wanted, raw, norm, problem) else 0): int
  val () = (if bytes_in(problem) = 0 && count = 0 then bput_v(problem, "no error of patsopt's") else ())
  (* the expected text from the expect's third line, a line feed after each *)
  var want : $B.builder_v = $B.create()
  val s3 = e2 + 1
  val () = (if s3 <= elen then put_unnumbered(ev, elen, s3, elen, want) else ())
  val () = put_char_v(want, 10)
  val @(na, nl) = $B.to_arr(norm)
  val @(wa, wl) = $B.to_arr(want)
  val @(ra, rl) = $B.to_arr(raw)
  val @(fz_n, bv_n) = $A.freeze<byte>(na)
  val @(fz_w, bv_w) = $A.freeze<byte>(wa)
  val @(fz_r, bv_r) = $A.freeze<byte>(ra)
  val equal = (nl = wl && same_range(bv_n, nl, 0, bv_w, wl, 0, nl, 0)): bool
  val () = (if bytes_in(problem) = 0 && ~equal then let
      val () = bput_v(problem, "its error is not the one expected:\n")
    in put_range(bv_r, rl, 0, rl, problem) end
    else ())
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
  val () = $A.drop<byte>(fz_w, bv_w)
  val () = $A.free<byte>($A.thaw<byte>(fz_w))
  val () = $A.drop<byte>(fz_r, bv_r)
  val () = $A.free<byte>($A.thaw<byte>(fz_r))
in end

fn judge {l1,l2,l3,l4:agz}
  (lv: !$A.borrow(byte, l1, 524288), llen: tlen,
   ev: !$A.borrow(byte, l2, 524288), elen0: tlen,
   sv: !$A.borrow(byte, l3, 524288), slen: tlen,
   mv: !$A.borrow(byte, l4, 524288), mlen: tlen, first: int,
   problem: !$B.builder_v >> $B.builder_v): void = let
  val elen = trim_feeds(ev, elen0)
in judge_in(lv, llen, ev, elen, sv, slen, mv, mlen, first, problem) end

(* ============================================================
   Running sh for what only the system does: copying a tree, running
   bats check with its output in a file, and putting a snippet in
   ============================================================ *)

(* sh -c script, with args as $1, $2, ...: sh's exit status, ~1 when it
   could not be run *)
fn run_sh {sn:nat} (script: string sn, args: $L.listv($P.arg_entry)): int = let
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
   The settings of a run, as NUL-terminated strings in one buffer
   ============================================================ *)

typedef settings = @{program= xi, directory= xi, work= xi, repository= xi, memo= xi, cold= int, prune= int}

(* The string at s of cfg (up to its NUL) appended to out *)
fun put_cfg_from {l:agz}{s:nat | s <= 524288} .<524288 - s>.
  (cfg: !$A.borrow(byte, l, 524288), s: int s, out: !$B.builder_v >> $B.builder_v): void =
  if s >= 524288 then ()
  else let
    val c = peek(cfg, s, 524288)
  in
    if c = 0 then () else let val () = put_char_v(out, c) in put_cfg_from(cfg, s + 1, out) end
  end

fn put_cfg {l:agz} (cfg: !$A.borrow(byte, l, 524288), s: xi, out: !$B.builder_v >> $B.builder_v): void =
  if s < 0 then ()
  else if s > 524288 then ()
  else put_cfg_from(cfg, s, out)

(* The string at s of cfg as an argument *)
fn cfg_arg {l:agz} (cfg: !$A.borrow(byte, l, 524288), s: xi): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = (if s >= 0 && s <= 524288 then put_cfg(cfg, s, b) else ())
in mk_arg(b) end

(* <directory>/<member>/<leaf> as a builder (no NUL) *)
fn fixture_text {l:agz}{lm:agz}{sl:nat}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e, leaf: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.directory, b)
  val () = bput_v(b, "/")
  val () = put_range(mv, 524288, a, e, b)
  val () = bput_v(b, "/")
  val () = bput_v(b, leaf)
in b end

(* The same, NUL-terminated, as a path *)
fn fixture_path {l:agz}{lm:agz}{sl:nat}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e, leaf: string sl): $B.builder_v = let
  var b = fixture_text(cfg, w, mv, a, e, leaf)
  val () = put_char_v(b, 0)
in b end

(* <work>/app/<module>, NUL-terminated, from the module name text *)
fn app_module_path {l:agz}{lm:agz}{sl:nat}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), mlen: tlen, work_leaf: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, b)
  val () = bput_v(b, "/")
  val () = bput_v(b, work_leaf)
  val () = bput_v(b, "/")
  val () = put_range(mv, 524288, 0, mlen, b)
  val () = put_char_v(b, 0)
in b end

(* The number (from 1) of the first line of the module bv[0, n) (read whole,
   in a piece of m bytes) that is exactly cv[0, clen), or 0 *)
fn find_module_line {l:agz}{ls:agz}{m:pos}{n:nat | n < m}
  (bv: !$A.borrow(byte, l, m), m: int m, n: int n, cv: !$A.borrow(byte, ls, 524288), clen: xi): int = let
  (* the end of the line at p *)
  fun eol {p:nat | p <= n} .<n - p>. (bv: !$A.borrow(byte, l, m), m: int m, n: int n, p: int p): [r:nat | p <= r; r <= n] int r =
    if p >= n then p
    else if peek(bv, p, m) = 10 then p
    else eol(bv, m, n, p + 1)
  fun equal {c:nat}{j:nat | j <= c} .<c - j>. (bv: !$A.borrow(byte, l, m), m: int m, p: xi, cv: !$A.borrow(byte, ls, 524288), clen: int c, j: int j): bool =
    if j >= clen then true
    else if peek(bv, p + j, m) = peek(cv, j, 524288) then equal(bv, m, p, cv, clen, j + 1)
    else false
  fun walk {p:nat | p <= n} .<n - p>.
    (bv: !$A.borrow(byte, l, m), m: int m, n: int n, p: int p, k: int, cv: !$A.borrow(byte, ls, 524288), clen: xi): int = let
    val e = eol(bv, m, n, p)
    fn same_line (bv: !$A.borrow(byte, l, m), m: int m, p: xi, e: xi, cv: !$A.borrow(byte, ls, 524288), clen: xi): bool =
      if e - p = clen then (if clen >= 0 then equal(bv, m, p, cv, clen, 0) else false) else false
  in
    if same_line(bv, m, p, e, cv, clen) then k
    else if e >= n then 0
    else walk(bv, m, n, e + 1, k + 1, cv, clen)
  end
in
  if clen < 0 then 0 else walk(bv, m, n, 0, 1, cv, clen)
end

(* ============================================================
   The checked copy: the snippet put in, bats check run, the build put back
   ============================================================ *)

(* <work>/check.log and <work>/check.seconds, NUL-terminated *)
fn work_file {l:agz}{sl:nat} (cfg: !$A.borrow(byte, l, 524288), w: settings, leaf: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, b)
  val () = bput_v(b, "/")
  val () = bput_v(b, leaf)
  val () = put_char_v(b, 0)
in b end

fn log_path {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): $B.builder_v = work_file(cfg, w, "check.log")

(* The seconds the last check took, as its script wrote them; 0 if unread *)
fn read_elapsed {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): int = let
  val ta = $A.alloc<byte>(524288): [l_ta:agz] $A.arr(byte, l_ta, 524288)
  val tn = read_file_text(work_file(cfg, w, "check.seconds"), ta)
  val @(fz, bv) = $A.freeze<byte>(ta)
  val n = text_len(tn)
  val e = digits_end(bv, n, 0)
  val v = digits_value(bv, n, 0, e, 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in v end

(* Puts the snippet of the fixture mv[a, e) into <work>/app's copy of the
   module bv_m[0, mlen), before line `at` and followed by one blank line:
   the exit status of the splice (98 when it could not be put in). The
   system does the splice (head, awk, tail: bats#297's); which line is
   decided here. *)
fn splice_snippet {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_m: !$A.borrow(byte, lx, 524288), mlen: xi, at: int): int = let
  var app : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, app)
  val () = bput_v(app, "/app")
  var module : $B.builder_v = $B.create()
  val () = put_range(bv_m, 524288, 0, mlen, module)
  val snippet = fixture_text(cfg, w, mv, a, e, "snippet.bats")
  var line : $B.builder_v = $B.create()
  val () = put_int_v(line, at)
in
  run_sh("app=$1; m=$2; snip=$3; at=$4; f=\"$app/$m\"; { head -n $((at - 1)) \"$f\"; awk 1 \"$snip\"; echo; tail -n +\"$at\" \"$f\"; } > \"$f.fixture\" || exit 98; mv -f \"$f.fixture\" \"$f\" || exit 98",
    $L.list_vt_cons(mk_arg(app), $L.list_vt_cons(mk_arg(module), $L.list_vt_cons(mk_arg(snippet),
    $L.list_vt_cons(mk_arg(line), $L.list_vt_nil())))))
end

(* ============================================================
   The fixtures' memo (bats-lang/bats#267, item 4b)

   A memo stands in for patsopt's answer on the spliced module and for
   nothing else: before it is asked, the project is validated as `bats
   check` validates it (validate_clean: the lexer's rules and the call
   cycles of every module, which have no patsopt in them), so a result
   kept is never served for a project that a check would refuse before
   patsopt. It lives in two files for each key:

     <memo>/<2 hex>/<key>.key   a bats-memo key (the check memo's text, see
                                cache.bats) of the files the module's check
                                reads, less the module's own .dats and .sats
     <memo>/<2 hex>/<key>.res   bats-fixture-result 2, the key, pass or log,
                                the sha256 of the .key's bytes, the log, and
                                the sha256 of every byte before it

   The memo is trusted only as far as it is checked: no file is renamed into
   place (the file package has no rename), a reader verifies the sum of the
   .res and the key's own test (closure_key_equal), so a file torn by a
   writer that died, or being written, is a miss and is written again.
   ============================================================ *)

(* A path (bytes, no NUL) as a NUL-terminated array *)
fn nul_path (b: $B.builder_v): [l:agz] $A.arr(byte, l, 524288) = let
  var p = b
  val () = put_char_v(p, 0)
in path_arr(p) end

(* A builder holding the text s *)
fn str_builder {sn:nat | sn < $B.BUILDER_CAP} (s: string sn): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, s)
in b end

(* <memo><tail> as a builder *)
fn memo_plus {lm:agz}{sl:nat} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen, tail: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(memo, 0, mlen, 524288, b)
  val () = bput_v(b, tail)
in b end

(* <memo>/<2 hex of key><tail> as a builder *)
fn memo_sub_plus {lm,lk:agz}{sl:nat} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  key: !$A.borrow(byte, lk, 524288), tail: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(memo, 0, mlen, 524288, b)
  val () = put_char_v(b, 47)
  val () = copy_to_builder_v(key, 0, 2, 524288, b)
  val () = bput_v(b, tail)
in b end

fn path_exists (b: $B.builder_v): bool = let
  val a = nul_path(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val r = $F.file_exists(bv, 524288)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* The sha256 of the file as 64 hex digits appended to out; false when it
   cannot be read *)
fn path_sha (b: $B.builder_v, out: !$B.builder_v >> $B.builder_v): bool = let
  val a = nul_path(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val r = put_file_sha256(bv, out)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* content written to the file; whether it was *)
fn path_write (b: $B.builder_v, content: $B.builder_v): bool = let
  val a = nul_path(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val r = write_settle(bv, 524288, write_file_from_builder(bv, 524288, content))
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r = 0 end

(* rm -f of the file (the process package has no unlink) *)
fn path_remove (b: $B.builder_v): void = let
  var p = b
  val n = $B.length(p) + 1
  val () = put_char_v(p, 0)
  val a = path_arr(p)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = remove_output(bv, n)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

fn path_mkdir (b: $B.builder_v): void = let
  val a = nul_path(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = $R.discard<int><$F.io_error>($F.file_mkdir(bv, 524288, 493))
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

(* The directories of an absolute path made one after another (mkdir -p) *)
fun mkdirs_from {l:agz}{len:nat | len <= 524288}{i:nat | i <= len} .<len - i>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, i: int i): void =
  if i >= len then ()
  else let
    val () = (if i > 0 && byte_at(bv, len, i) = 47 then let
        var pre : $B.builder_v = $B.create()
        val () = copy_to_builder_v(bv, 0, i, 524288, pre)
      in path_mkdir(pre) end else ())
  in mkdirs_from(bv, len, i + 1) end

fn mkdir_p (b: $B.builder_v): void = let
  val @(a, n) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = mkdirs_from(bv, n, 0)
  var whole : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, 0, n, 524288, whole)
  val () = path_mkdir(whole)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

(* The sha256 of the bytes b holds, as 64 hex digits appended to out *)
fn put_sha_of (b: $B.builder_v, out: !$B.builder_v >> $B.builder_v): void = let
  val @(a, n) = $B.to_arr(b)
  val c = $SHA.init()
  val () = $SHA.update(c, a, n)
  val () = $A.free<byte>(a)
  val hex = $A.alloc<byte>(64)
  val () = $SHA.finish(c, hex)
  val @(fz, bv) = $A.freeze<byte>(hex)
  val () = copy_to_builder_v(bv, 0, 64, 64, out)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

(* The sha256 of bv[a, e), appended to out *)
fn put_sha_range {l:agz}{a,e:int} (bv: !$A.borrow(byte, l, 524288), a: int a, e: int e, out: !$B.builder_v >> $B.builder_v): void = let
  var tmp : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, a, e, 524288, tmp)
in put_sha_of(tmp, out) end

(* Whether bv[0, len) holds the text s anywhere *)
fun find_text_from {l:agz}{sl:nat}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, s: string sl): bool =
  if p >= len then false
  else if text_has(bv, len, p, s) then true
  else find_text_from(bv, len, p + 1, s)

(* Whether bv[0, len) holds the text s at or after p as a whole word: the
   bytes around it are not part of an identifier (keyword: fixtures memo,
   a snippet that loads) *)
fun find_word_from {l:agz}{sl:nat}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, s: string sl): bool =
  if p >= len then false
  else if text_has(bv, len, p, s)
    && ~is_ident_byte(byte_at(bv, len, p - 1))
    && ~is_ident_byte(byte_at(bv, len, p + g1u2i(string1_length(s)))) then true
  else find_word_from(bv, len, p + 1, s)

(* Whether the log bv[0, len) has a line that is a patsopt error's first *)
fun has_error_from {l:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p): bool = let
  val e = line_end(bv, len, p, true)
  val @(is_header, _, _, _) = header_parse(bv, len, p, e)
in
  if is_header then true
  else if e >= len then false
  else has_error_from(bv, len, next_line(bv, len, e, true))
end

(* bv[i, e) appended to out, each occurrence of pv[0, plen) written /app/ *)
fun put_replaced {l:agz}{lp:agz}{len:nat | len <= 524288}{e:nat | e <= len}{i:nat | i <= e} .<e - i>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, i: int i, e: int e,
   pv: !$A.borrow(byte, lp, 524288), plen: tlen, out: !$B.builder_v >> $B.builder_v): void =
  if i >= e then ()
  else if plen > 0 then
    (if i + plen <= e then
      (if same_range(bv, len, i, pv, plen, 0, plen, 0) then let
        val () = bput_v(out, "/app/")
      in put_replaced(bv, len, i + plen, e, pv, plen, out) end
      else let
        val () = put_char_v(out, byte_at(bv, len, i))
      in put_replaced(bv, len, i + 1, e, pv, plen, out) end)
    else let
      val () = put_char_v(out, byte_at(bv, len, i))
    in put_replaced(bv, len, i + 1, e, pv, plen, out) end)
  else let
    val () = put_char_v(out, byte_at(bv, len, i))
  in put_replaced(bv, len, i + 1, e, pv, plen, out) end

(* The log as it is kept: the work directory's path (pv, with its final
   slash) written /app/, the lines a waiting bats and what bats says of an
   ATS2 it did not install (that it is checking it, and the warning or note
   with what the check found, bats#264) say dropped (they name this
   machine), a line feed after each line *)
fn normalize_line {l:agz}{lp:agz}{len:nat | len <= 524288}{p:nat | p <= len}{e:nat | p <= e; e <= len}
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p, e: int e,
   pv: !$A.borrow(byte, lp, 524288), plen: tlen, out: !$B.builder_v >> $B.builder_v): void =
  if text_has(bv, len, p, "waiting for another bats") then ()
  else if text_has(bv, len, p, "warning: the ATS2 in ") then ()
  else if text_has(bv, len, p, "note: the ATS2 in ") then ()
  else if text_has(bv, len, p, "checking the ATS2 in ") then ()
  else let
    val () = put_replaced(bv, len, p, e, pv, plen, out)
  in put_char_v(out, 10) end

fun normalize_from {l:agz}{lp:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, p: int p,
   pv: !$A.borrow(byte, lp, 524288), plen: tlen, out: !$B.builder_v >> $B.builder_v): void =
  if p >= len then ()
  else let
    val e = line_end(bv, len, p, false)
    val () = normalize_line(bv, len, p, e, pv, plen, out)
  in
    if e >= len then () else normalize_from(bv, len, next_line(bv, len, e, false), pv, plen, out)
  end

(* The current directory as a path (no NUL); empty when it is not known *)
fn cwd_into (out: !$B.builder_v >> $B.builder_v): void = let
  val buf = $A.alloc<byte>(4096)
  val k = (case+ $E.cwd_read(buf, 4096) of | ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= 4096] int k
  val @(fz, bv) = $A.freeze<byte>(buf)
  val () = copy_to_builder_v(bv, 0, k, 4096, out)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

fn chdir_path (b: $B.builder_v): bool = let
  val a = nul_path(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val ok = (case+ $F.file_chdir(bv, 524288) of
    | ~$R.ok(_) => true | ~$R.err(_) => false): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in ok end

(* ---- where the memo is ---- *)

(* The memo's directory (an absolute path) appended to out: --memo, else
   BATS_MEMO_DIR, else $XDG_CACHE_HOME/bats/fixtures, else
   $HOME/.cache/bats/fixtures; false when none can be named *)
fn memo_dir_into {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings, out: !$B.builder_v >> $B.builder_v): bool =
  if w.memo >= 0 && byte_at(cfg, 524288, w.memo) <> 0 then let
    val () = put_cfg(cfg, w.memo, out)
  in true end
  else if env_value("BATS_MEMO_DIR", out) then true
  else if env_value("XDG_CACHE_HOME", out) then let
    val () = bput_v(out, "/bats/fixtures")
  in true end
  else if env_value("HOME", out) then let
    val () = bput_v(out, "/.cache/bats/fixtures")
  in true end
  else false

(* <memo>/<2 hex of key>/<key><suffix> appended to out (no NUL) *)
fn entry_into {lm,lk:agz}{sl:nat} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  key: !$A.borrow(byte, lk, 524288), suffix: string sl, out: !$B.builder_v >> $B.builder_v): void = let
  val () = copy_to_builder_v(memo, 0, mlen, 524288, out)
  val () = put_char_v(out, 47)
  val () = copy_to_builder_v(key, 0, 2, 524288, out)
  val () = put_char_v(out, 47)
  val () = copy_to_builder_v(key, 0, 64, 524288, out)
in bput_v(out, suffix) end

(* The same as a builder *)
fn entry_path {lm,lk:agz}{sl:nat} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  key: !$A.borrow(byte, lk, 524288), suffix: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = entry_into(memo, mlen, key, suffix, b)
in b end

(* <work>/<leaf> appended: a path (no NUL) of the work directory *)
fn work_text {l:agz}{sl:nat} (cfg: !$A.borrow(byte, l, 524288), w: settings, leaf: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, b)
  val () = put_char_v(b, 47)
  val () = bput_v(b, leaf)
in b end

(* The file's bytes read into dst; the length, ~1 when it cannot be read *)
fn path_read {ld:agz} (b: $B.builder_v, dst: !$A.arr(byte, ld, 524288)): [k:int | ~1 <= k; k <= 524288] int k = let
  var p = b
  val () = put_char_v(p, 0)
in read_file_text(p, dst) end

(* Whether the 64 hex digits builder b holds are bv[at, at + 64) *)
fn hex_is {l:agz} (b: $B.builder_v, bv: !$A.borrow(byte, l, 524288), n: xi, at: xi): bool = let
  val @(ba, bn) = $B.to_arr(b)
  val @(fz, bb) = $A.freeze<byte>(ba)
  val r = (bn = 64 && same_range(bb, bn, 0, bv, n, at, 64, 0)): bool
  val () = $A.drop<byte>(fz, bb)
in ($A.free<byte>($A.thaw<byte>(fz)); r) end

(* key + a line feed added to <work>/memo-used (the keys this run asked
   for, which --prune keeps) *)
fn used_add {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings, key: $B.builder_v): void = let
  val ra = $A.alloc<byte>(524288): [l_ra:agz] $A.arr(byte, l_ra, 524288)
  val n = path_read(work_text(cfg, w, "memo-used"), ra)
  val @(fz, bv) = $A.freeze<byte>(ra)
  var out : $B.builder_v = $B.create()
  val () = (if n > 0 then copy_to_builder_v(bv, 0, n, 524288, out) else ())
  val () = append_builder(out, key)
  val () = put_char_v(out, 10)
  val _ = path_write(work_text(cfg, w, "memo-used"), out)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

(* The key's text of the fixture, appended to t; false when a file of it
   cannot be read. The current directory is the app. *)
fn key_text {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen, t: !$B.builder_v >> $B.builder_v): bool = let
  val () = bput_v(t, "bats-fixture-key 2\nmodule ")
  val () = put_range(bv_f, 524288, 0, mlen, t)
  val () = bput_v(t, "\nbefore ")
  val a1 = path_sha(fixture_text(cfg, w, mv, a, e, "before"), t)
  val () = bput_v(t, "\nsnippet ")
  val a2 = path_sha(fixture_text(cfg, w, mv, a, e, "snippet.bats"), t)
  val () = bput_v(t, "\nspliced ")
  var mp : $B.builder_v = $B.create()
  val () = put_range(bv_f, 524288, 0, mlen, mp)
  val a3 = path_sha(mp, t)
  val () = bput_v(t, "\ntoml ")
  val a4 = path_sha(str_builder("bats.toml"), t)
  val () = bput_v(t, "\nlock ")
  val lq = str_builder("bats.lock")
  val a6 = (if path_exists(str_builder("bats.lock")) then path_sha(lq, t)
    else let
      val () = $B.builder_free(lq)
      val () = bput_v(t, "none")
    in true end): bool
  val () = bput_v(t, "\nstamp ")
  val a5 = path_sha(str_builder("build/.bats_stamp"), t)
  val () = put_char_v(t, 10)
in a1 && a2 && a3 && a4 && a5 && a6 end

(* Whether bv[0, n) ends with the text s *)
fn ends_with_text {l:agz}{sl:nat} (bv: !$A.borrow(byte, l, 524288), n: tlen, s: string sl): bool = let
  val k = g1u2i(string1_length(s))
in (if n >= k then text_has(bv, n, n - k, s) else false) end

(* build/<the module's path less its .bats><suffix> (the module's path must
   end with .bats: the caller has seen it does) *)
fn built_path {l:agz}{sl:nat} (bv: !$A.borrow(byte, l, 524288), n: tlen, suffix: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, "build/")
  val () = put_range(bv, 524288, 0, (if n >= 5 then n - 5 else 0), b)
  val () = bput_v(b, suffix)
in b end

(* Lines from p of the key kb[0, len): each path that is not own1 or own2 is
   appended to out with a line feed, up to the rule "--"; whether the rule
   was reached *)
fn put_path_line {l:agz}{len:nat | len <= 524288}{p:nat | p <= len}{e:nat | p <= e; e <= len}
  (kb: !$A.borrow(byte, l, 524288), len: int len, p: int p, e: int e, own: bool,
   out: !$B.builder_v >> $B.builder_v): void =
  if own then ()
  else if e = p then ()
  else let
    val () = put_range(kb, len, p, e, out)
  in put_char_v(out, 10) end

fun list_paths {l:agz}{l1,l2:agz}{len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
  (kb: !$A.borrow(byte, l, 524288), len: int len, p: int p,
   o1: !$A.borrow(byte, l1, 524288), n1: tlen, o2: !$A.borrow(byte, l2, 524288), n2: tlen,
   out: !$B.builder_v >> $B.builder_v): bool = let
  val e = line_end(kb, len, p, false)
in
  if e - p = 2 && text_has(kb, len, p, "--") then true
  else let
    val own = ((e - p = n1 && same_range(kb, len, p, o1, n1, 0, n1, 0))
      || (e - p = n2 && same_range(kb, len, p, o2, n2, 0, n2, 0))): bool
    val () = put_path_line(kb, len, p, e, own, out)
  in
    if e >= len then false else list_paths(kb, len, next_line(kb, len, e, false), o1, n1, o2, n2, out)
  end
end

(* The closure the module's check reads, from its key in the base build
   (build/<module>_dats.c.key), less the module's own .dats and .sats:
   one path a line to <work>/memo.paths, its key to <work>/memo.closure,
   and the module's interface line to <work>/memo.iface. false when any
   of them cannot be had (the fixture is then not kept). The current
   directory is the app, whose build is the base's. *)
fn closure_state {l:agz}{lx:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings,
  bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen): bool =
  if ~ends_with_text(bv_f, mlen, ".bats") then false
  else let
    val @(oda, odn) = $B.to_arr(built_path(bv_f, mlen, ".dats"))
    val @(fz_od, bv_od) = $A.freeze<byte>(oda)
    val @(osa, osn) = $B.to_arr(built_path(bv_f, mlen, ".sats"))
    val @(fz_os, bv_os) = $A.freeze<byte>(osa)
    val ka = $A.alloc<byte>(524288): [l_ka:agz] $A.arr(byte, l_ka, 524288)
    val kn = path_read(built_path(bv_f, mlen, "_dats.c.key"), ka)
    val @(fz_k, bv_k) = $A.freeze<byte>(ka)
    var lst : $B.builder_v = $B.create()
    val knt = text_len(kn)
    val l1 = line_end(bv_k, knt, 0, false)
    val found = (if kn > 0 then
        (if l1 < knt then let
          val l2 = line_end(bv_k, knt, l1 + 1, false)
        in (if l2 < knt then list_paths(bv_k, knt, l2 + 1, bv_od, odn, bv_os, osn, lst) else false) end
        else false)
      else false): bool
    val lst2 = lst
    val wrote_list = (if found then path_write(work_text(cfg, w, "memo.paths"), lst2)
      else let val () = $B.builder_free(lst2) in false end): bool
    val keyed = (if wrote_list then let
        val la = nul_path(work_text(cfg, w, "memo.paths"))
        val @(fz_l, bv_l) = $A.freeze<byte>(la)
        val ca = nul_path(work_text(cfg, w, "memo.closure"))
        val @(fz_c, bv_c) = $A.freeze<byte>(ca)
        (* the base check ran in a process of its own, after any digest kept here *)
        val () = digests_forget()
        val r = closure_key_write(bv_l, bv_c)
        val () = $A.drop<byte>(fz_l, bv_l)
        val () = $A.free<byte>($A.thaw<byte>(fz_l))
        val () = $A.drop<byte>(fz_c, bv_c)
        val () = $A.free<byte>($A.thaw<byte>(fz_c))
      in r end else false): bool
    (* the interface line of the module's .sats *)
    val ia = nul_path(built_path(bv_f, mlen, ".sats"))
    val @(fz_i, bv_i) = $A.freeze<byte>(ia)
    var iline : $B.builder_v = $B.create()
    val hashed = (if keyed then memo_entry_hash(bv_i, 524288, iline) else false): bool
    val iline2 = iline
    val wrote_iface = (if hashed then path_write(work_text(cfg, w, "memo.iface"), iline2)
      else let val () = $B.builder_free(iline2) in false end): bool
    val () = $A.drop<byte>(fz_i, bv_i)
    val () = $A.free<byte>($A.thaw<byte>(fz_i))
    val () = $A.drop<byte>(fz_k, bv_k)
    val () = $A.free<byte>($A.thaw<byte>(fz_k))
    val () = $A.drop<byte>(fz_od, bv_od)
    val () = $A.free<byte>($A.thaw<byte>(fz_od))
    val () = $A.drop<byte>(fz_os, bv_os)
    val () = $A.free<byte>($A.thaw<byte>(fz_os))
  in wrote_iface end

(* ---- the .res file ---- *)

(* bats-fixture-result 2, the key, pass or log, the sha256 of the .key's
   bytes (closure_hex, 64 digits), the log (none for a pass), and the sha256
   of every byte before it; consumes closure_hex *)
fn res_content {lk:agz}{ll:agz} (key: !$A.borrow(byte, lk, 524288), pass: bool, closure_hex: $B.builder_v,
  lv: !$A.borrow(byte, ll, 524288), ln: tlen): $B.builder_v = let
  var r : $B.builder_v = $B.create()
  val () = bput_v(r, "bats-fixture-result 2\n")
  val () = copy_to_builder_v(key, 0, 64, 524288, r)
  val () = put_char_v(r, 10)
  val () = (if pass then bput_v(r, "pass\n") else bput_v(r, "log\n"))
  val () = append_builder(r, closure_hex)
  val () = put_char_v(r, 10)
  val () = (if pass then () else copy_to_builder_v(lv, 0, ln, 524288, r))
  val @(ra, rn) = $B.to_arr(r)
  val @(fz, bv) = $A.freeze<byte>(ra)
  var sum : $B.builder_v = $B.create()
  val () = put_sha_range(bv, 0, rn, sum)
  var out : $B.builder_v = $B.create()
  val () = copy_to_builder_v(bv, 0, rn, 524288, out)
  val () = append_builder(out, sum)
  val () = put_char_v(out, 10)
  val () = $A.drop<byte>(fz, bv)
in ($A.free<byte>($A.thaw<byte>(fz)); out) end

(* Where the closure's sha256 line starts in the .res rv[0, n) that is
   whole (its first line, the key, the kind asked for, its sum right), else
   ~1; the log is rv[that + 65, n - 65) *)
fn res_check {l:agz}{lk:agz} (rv: !$A.borrow(byte, l, 524288), n: tlen,
  key: !$A.borrow(byte, lk, 524288), is_accept: bool): [c:int] int c =
  if n < 221 then ~1
  else if ~text_has(rv, n, 0, "bats-fixture-result 2\n") then ~1
  else if ~same_range(rv, n, 22, key, 64, 0, 64, 0) then ~1
  else if byte_at(rv, n, 86) <> 10 then ~1
  else let
    val ok_kind = (if is_accept then text_has(rv, n, 87, "pass\n") else text_has(rv, n, 87, "log\n")): bool
    val cl = (if is_accept then 92 else 91): [c:int] int c
    val shaped = (ok_kind && byte_at(rv, n, cl + 64) = 10 && cl + 65 + 65 <= n
      && byte_at(rv, n, n - 1) = 10 && (if is_accept then cl + 65 + 65 = n else true)): bool
  in
    if ~shaped then ~1
    else let
      var sum : $B.builder_v = $B.create()
      val () = put_sha_range(rv, 0, n - 65, sum)
    in (if hex_is(sum, rv, n, n - 65) then cl else ~1) end
  end

(* ---- the probe ---- *)

(* Looks the fixture up in the memo at memo[0, mlen) under key[0, 64): 0 or
   1 for a hit, the status the check would have had (<work>/check.log is
   then the log it printed, check.seconds 0 and check.memo says hit); 100 for
   a miss. In a cold run (cold) an entry that would have been served is
   not: its result (pass or log, and the log) is kept in <work>/memo.prior
   for the audit of the run's own result, and the answer is a miss. *)
fn lookup {l:agz}{lm:agz}{lk:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings,
  is_accept: bool, cold: bool, memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  key: !$A.borrow(byte, lk, 524288)): int = let
  val ra = $A.alloc<byte>(524288): [l_ra:agz] $A.arr(byte, l_ra, 524288)
  val marked = path_exists(memo_plus(memo, mlen, "/.bats-fixtures-memo"))
  val rpath = entry_path(memo, mlen, key, ".res")
  val rn0 = path_read(rpath, ra)
  val rn = text_len(rn0)
  val @(fz_r, bv_r) = $A.freeze<byte>(ra)
  val cl = (if marked then (if rn0 >= 0 then res_check(bv_r, rn, key, is_accept) else ~1) else ~1): [c:int] int c
  (* the .key is the one the .res names, and its files are as it says *)
  val kpath = entry_path(memo, mlen, key, ".key")
  var kh : $B.builder_v = $B.create()
  val kdone = (if cl >= 0 then path_sha(kpath, kh) else let val () = $B.builder_free(kpath) in false end): bool
  val kh2 = kh
  val same_key = (if kdone then hex_is(kh2, bv_r, rn, cl) else let val () = $B.builder_free(kh2) in false end): bool
  val kpath2 = entry_path(memo, mlen, key, ".key")
  val fresh = (if same_key then let
      val a = nul_path(kpath2)
      val @(fz_a, bv_a) = $A.freeze<byte>(a)
      (* a check ran in a process of its own since any digest kept here *)
      val () = digests_forget()
      val r = closure_key_equal(bv_a, 524288)
      val () = $A.drop<byte>(fz_a, bv_a)
      val () = $A.free<byte>($A.thaw<byte>(fz_a))
    in r end else let val () = $B.builder_free(kpath2) in false end): bool
  val status = (if fresh then let
      var lb : $B.builder_v = $B.create()
      val () = (if is_accept then () else copy_to_builder_v(bv_r, cl + 65, rn - 65, 524288, lb))
      val lb2 = lb
    in
      if cold then let
        var pr : $B.builder_v = $B.create()
        val () = (if is_accept then bput_v(pr, "pass\n") else bput_v(pr, "log\n"))
        val () = append_builder(pr, lb2)
        val _ = path_write(work_text(cfg, w, "memo.prior"), pr)
      in 100 end
      else let
        val _ = path_write(work_text(cfg, w, "check.log"), lb2)
        val _ = path_write(work_text(cfg, w, "check.seconds"), str_builder("0\n"))
        val _ = path_write(work_text(cfg, w, "check.memo"), str_builder("hit"))
      in (if is_accept then 0 else 1) end
    end else 100): int
  val () = $A.drop<byte>(fz_r, bv_r)
in ($A.free<byte>($A.thaw<byte>(fz_r)); status) end

(* The probe, in the app (the current directory): 100 when the check must be
   run; the memo's state for the store that follows is then in the work
   directory *)
fn probe_in {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen, is_accept: bool, cold: bool): int = let
  var md0 : $B.builder_v = $B.create()
  val have_dir = memo_dir_into(cfg, w, md0)
  val md = md0
in
  (* what has no patsopt in it is checked first, as a check does it: a
     project that is refused there is not served from the memo *)
  if ~have_dir then let val () = $B.builder_free(md) in 100 end
  else if ~validate_clean() then let val () = $B.builder_free(md) in 100 end
  else let
    var t0 : $B.builder_v = $B.create()
    val ok = key_text(cfg, w, mv, a, e, bv_f, mlen, t0)
    val t = t0
  in
    if ~ok then let
      val () = $B.builder_free(t)
      val () = $B.builder_free(md)
    in 100 end
    else let
      val @(ta, tn) = $B.to_arr(t)
      val @(fz_t, bv_t) = $A.freeze<byte>(ta)
      var kh : $B.builder_v = $B.create()
      val () = put_sha_range(bv_t, 0, tn, kh)
      val @(ka, kn) = $B.to_arr(kh)
      val @(fz_k, bv_k) = $A.freeze<byte>(ka)
      var kc : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_k, 0, 64, 524288, kc)
      val () = put_char_v(kc, 10)
      val _ = path_write(work_text(cfg, w, "memo.key"), kc)
      var ku : $B.builder_v = $B.create()
      val () = copy_to_builder_v(bv_k, 0, 64, 524288, ku)
      val () = used_add(cfg, w, ku)
      val @(ma, mn) = $B.to_arr(md)
      val @(fz_m, bv_m) = $A.freeze<byte>(ma)
      val st = lookup(cfg, w, is_accept, cold, bv_m, mn, bv_k)
      (* a miss: the closure the check will read, as the base has it *)
      val st2 = (if st = 100 then let
          val kept = closure_state(cfg, w, bv_f, mlen)
          val _ = (if kept then true else path_write(work_text(cfg, w, "memo.nostore"), str_builder("no")))
        in 100 end else st): int
      val () = $A.drop<byte>(fz_m, bv_m)
      val () = $A.free<byte>($A.thaw<byte>(fz_m))
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val () = $A.drop<byte>(fz_t, bv_t)
      val () = $A.free<byte>($A.thaw<byte>(fz_t))
    in st2 end
  end
end

(* The state of the last fixture removed *)
fn memo_clear {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): void = let
  val () = path_remove(work_text(cfg, w, "check.log"))
  val () = path_remove(work_text(cfg, w, "check.seconds"))
  val () = path_remove(work_text(cfg, w, "check.memo"))
  val () = path_remove(work_text(cfg, w, "check.stale"))
  val () = path_remove(work_text(cfg, w, "memo.key"))
  val () = path_remove(work_text(cfg, w, "memo.prior"))
  val () = path_remove(work_text(cfg, w, "memo.nostore"))
  val () = path_remove(work_text(cfg, w, "memo.paths"))
  val () = path_remove(work_text(cfg, w, "memo.closure"))
in path_remove(work_text(cfg, w, "memo.iface")) end

(* Looks the fixture up (the snippet is already in the app's module): 100 when
   the check must be run, else the check's status, served from the memo *)
fn memo_probe {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen, is_accept: bool): int = let
  val () = memo_clear(cfg, w)
  var here0 : $B.builder_v = $B.create()
  val () = cwd_into(here0)
  val here = here0
  var back0 : $B.builder_v = $B.create()
  val () = cwd_into(back0)
  val back = back0
  var app0 : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, app0)
  val () = bput_v(app0, "/app")
  val app = app0
  val known = ($B.length(here) > 0): bool
  val inside = (if known then chdir_path(app) else let val () = $B.builder_free(app) in false end): bool
  val () = $B.builder_free(here)
  val cold = (w.cold <> 0 || is_cold()): bool
  val r = (if inside then probe_in(cfg, w, mv, a, e, bv_f, mlen, is_accept, cold) else 100): int
  val _ = (if inside then chdir_path(back) else let val () = $B.builder_free(back) in false end)
in r end

(* ---- the store ---- *)

(* Whether the snippet names a file to load (staload, dynload, load or
   include as a word, #use or #require anywhere in it): it reads a file the
   closure of the base module does not name. A word inside a longer name
   (Download, unloaded) loads nothing (bats#432) *)
fn snippet_loads {l:agz}{lm:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e): bool = let
  val sa = $A.alloc<byte>(524288): [l_sa:agz] $A.arr(byte, l_sa, 524288)
  val sn0 = read_file_text(fixture_path(cfg, w, mv, a, e, "snippet.bats"), sa)
  val sn = text_len(sn0)
  val @(fz, bv) = $A.freeze<byte>(sa)
  val loads = (sn0 < 0 || find_word_from(bv, sn, 0, "staload") || find_word_from(bv, sn, 0, "dynload")
    || find_word_from(bv, sn, 0, "load") || find_word_from(bv, sn, 0, "include")
    || find_text_from(bv, sn, 0, "#use") || find_text_from(bv, sn, 0, "#require")): bool
  val () = $A.drop<byte>(fz, bv)
in ($A.free<byte>($A.thaw<byte>(fz)); loads) end

(* Whether the module's interface line, as it is now, is the one the probe
   kept in <work>/memo.iface: the digests kept in memory are dropped
   first, so the .sats is digested as it is now, not as it was *)
fn iface_same {l:agz}{lx:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings,
  bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen): bool = let
  val () = digests_forget()
  val ia = nul_path(built_path(bv_f, mlen, ".sats"))
  val @(fz_i, bv_i) = $A.freeze<byte>(ia)
  var cur : $B.builder_v = $B.create()
  val ok = memo_entry_hash(bv_i, 524288, cur)
  val ka = $A.alloc<byte>(524288): [l_ka:agz] $A.arr(byte, l_ka, 524288)
  val kn = path_read(work_text(cfg, w, "memo.iface"), ka)
  val @(fz_k, bv_k) = $A.freeze<byte>(ka)
  val @(ca, cn) = $B.to_arr(cur)
  val @(fz_c, bv_c) = $A.freeze<byte>(ca)
  val same = (ok && kn > 0 && cn = kn && same_range(bv_c, cn, 0, bv_k, kn, 0, cn, 0)): bool
  val () = $A.drop<byte>(fz_c, bv_c)
  val () = $A.free<byte>($A.thaw<byte>(fz_c))
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
  val () = $A.drop<byte>(fz_i, bv_i)
in ($A.free<byte>($A.thaw<byte>(fz_i)); same) end

(* Whether the memo at the absolute path memo can be written to: it holds
   the mark, or it is empty or not there yet (then it is made and marked).
   A directory that holds anything else is not a memo. *)
fn memo_ready {lm:agz} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen): bool =
  if path_exists(memo_plus(memo, mlen, "/.bats-fixtures-memo")) then true
  else let
    (* how many entries the directory has, . and .. included: ~1 when it is not there *)
    val da = nul_path(memo_plus(memo, mlen, ""))
    val @(fz_d, bv_d) = $A.freeze<byte>(da)
    val held = (case+ $F.dir_read(bv_d, 524288) of
      | ~$R.err(_) => ~1
      | ~$R.ok(es) => let
          val n = $F.entries_count(es)
          val () = $F.entries_free(es)
        in n end): int
    val () = $A.drop<byte>(fz_d, bv_d)
    val () = $A.free<byte>($A.thaw<byte>(fz_d))
  in
    if held > 2 then false
    else let
      val () = (if held < 0 then mkdir_p(memo_plus(memo, mlen, "")) else ())
    in path_write(memo_plus(memo, mlen, "/.bats-fixtures-memo"), str_builder("bats-fixture-memo 2\n")) end
  end

(* <memo>/<2 hex of key>, made and marked when it is not: whether it can
   be written to *)
fn memo_subdir {lm:agz}{lk:agz} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  key: !$A.borrow(byte, lk, 524288)): bool = let
  val () = path_mkdir(memo_sub_plus(memo, mlen, key, ""))
in
  if path_exists(memo_sub_plus(memo, mlen, key, "/.memo-dir")) then true
  else path_write(memo_sub_plus(memo, mlen, key, "/.memo-dir"), str_builder("bats-fixture-memo 2\n"))
end

(* The audit of a cold run against the entry that would have been served
   (<work>/memo.prior, its kind and its log): when the run's own result is
   not what the entry says, the entry is dropped and <work>/check.stale
   says so; whether it did *)
fn audit {l:agz}{lm:agz}{lk:agz}{ln:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings,
  want_pass: bool, want_log: bool, nv: !$A.borrow(byte, ln, 524288), nn: tlen, status: int,
  memo: !$A.borrow(byte, lm, 524288), mlen: tlen, key: !$A.borrow(byte, lk, 524288)): bool = let
  val pa = $A.alloc<byte>(524288): [l_pa:agz] $A.arr(byte, l_pa, 524288)
  val pn0 = path_read(work_text(cfg, w, "memo.prior"), pa)
  val pn = text_len(pn0)
  val @(fz, pv) = $A.freeze<byte>(pa)
  val prior_pass = (pn0 >= 0 && text_has(pv, pn, 0, "pass\n")): bool
  val log_at = (if prior_pass then 5 else 4): [a:int] int a
  val same_log = (want_log && nn = pn - log_at && same_range(pv, pn, log_at, nv, nn, 0, nn, 0)): bool
  val stale = (pn0 >= 0 && (if prior_pass then ~want_pass else ~same_log)): bool
  val () = (if stale then let
      var m : $B.builder_v = $B.create()
      val () = bput_v(m, "STALE MEMO: ")
      val () = (if prior_pass then let
          val () = bput_v(m, "the memo says the check passes, the cold run's status is ")
        in put_int_v(m, status) end
        else if ~want_log then let
          val () = bput_v(m, "the memo holds the log of a check that fails, the cold run's status is ")
        in put_int_v(m, status) end
        else bput_v(m, "the log the memo holds is not the cold run's"))
      val () = bput_v(m, " (key ")
      val () = copy_to_builder_v(key, 0, 64, 524288, m)
      val () = bput_v(m, ")\n")
      val _ = path_write(work_text(cfg, w, "check.stale"), m)
      val () = path_remove(entry_path(memo, mlen, key, ".res"))
    in path_remove(entry_path(memo, mlen, key, ".key")) end else ())
  val () = $A.drop<byte>(fz, pv)
in ($A.free<byte>($A.thaw<byte>(fz)); stale) end

(* The store, in the app (the current directory): what the check just run
   said is audited (a cold run) and kept *)
fn store_in {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen, is_accept: bool, status: int): void = let
  val ka = $A.alloc<byte>(524288): [l_ka:agz] $A.arr(byte, l_ka, 524288)
  val kn = path_read(work_text(cfg, w, "memo.key"), ka)
  val @(fz_k, bv_k) = $A.freeze<byte>(ka)
  var md : $B.builder_v = $B.create()
  val have_dir = memo_dir_into(cfg, w, md)
  val @(ma, mn) = $B.to_arr(md)
  val @(fz_m, bv_m) = $A.freeze<byte>(ma)
  (* the log the check printed, as it is kept *)
  val la = $A.alloc<byte>(524288): [l_la:agz] $A.arr(byte, l_la, 524288)
  val ln0 = read_file_text(log_path(cfg, w), la)
  val ln = text_len(ln0)
  val @(fz_l, bv_l) = $A.freeze<byte>(la)
  val want_pass = (is_accept && status = 0): bool
  val want_log0 = (~is_accept && status = 1 && ln0 > 0 && has_error_from(bv_l, ln, 0)): bool
  var pb : $B.builder_v = $B.create()
  val () = cwd_into(pb)
  val () = put_char_v(pb, 47)
  val @(pa, pn) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  var nb : $B.builder_v = $B.create()
  val () = (if want_log0 then normalize_from(bv_l, ln, 0, bv_p, pn, nb) else ())
  val @(na, nn) = $B.to_arr(nb)
  val @(fz_n, bv_n) = $A.freeze<byte>(na)
  (* a log is kept when it leaves room in an entry *)
  val want_log = (want_log0 && nn <= 262144): bool
  val usable = (kn >= 64 && have_dir): bool
  val stale = (if usable then audit(cfg, w, want_pass, want_log, bv_n, nn, status, bv_m, mn, bv_k) else false): bool
  val keep = (usable && (want_pass || want_log)): bool
  val clean = (if keep then
      (~path_exists(work_text(cfg, w, "memo.nostore")) && ~snippet_loads(cfg, w, mv, a, e)
        && iface_same(cfg, w, bv_f, mlen) && memo_ready(bv_m, mn) && memo_subdir(bv_m, mn, bv_k))
    else false): bool
  val () = (if clean then let
      (* the closure's key, then the result that names it *)
      val ca = $A.alloc<byte>(524288): [l_ca:agz] $A.arr(byte, l_ca, 524288)
      val cn = path_read(work_text(cfg, w, "memo.closure"), ca)
      val @(fz_c, bv_c) = $A.freeze<byte>(ca)
      var kb : $B.builder_v = $B.create()
      val () = (if cn > 0 then copy_to_builder_v(bv_c, 0, cn, 524288, kb) else ())
      val kb2 = kb
      val wrote_key = (if cn > 0 then path_write(entry_path(bv_m, mn, bv_k, ".key"), kb2)
        else let val () = $B.builder_free(kb2) in false end): bool
      var ch : $B.builder_v = $B.create()
      val hashed = (if wrote_key then path_sha(entry_path(bv_m, mn, bv_k, ".key"), ch) else false): bool
      val ch2 = ch
      val () = (if hashed then let
          val res = res_content(bv_k, want_pass, ch2, bv_n, nn)
          val _ = path_write(entry_path(bv_m, mn, bv_k, ".res"), res)
        in () end
        else $B.builder_free(ch2))
      val () = $A.drop<byte>(fz_c, bv_c)
    in $A.free<byte>($A.thaw<byte>(fz_c)) end else ())
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
  val () = $A.drop<byte>(fz_l, bv_l)
  val () = $A.free<byte>($A.thaw<byte>(fz_l))
  val () = $A.drop<byte>(fz_m, bv_m)
  val () = $A.free<byte>($A.thaw<byte>(fz_m))
in ($A.drop<byte>(fz_k, bv_k); $A.free<byte>($A.thaw<byte>(fz_k))) end

(* The store: the app is the current directory while it runs *)
fn memo_store {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_f: !$A.borrow(byte, lx, 524288), mlen: tlen, is_accept: bool, status: int): void = let
  var here0 : $B.builder_v = $B.create()
  val () = cwd_into(here0)
  val here = here0
  var back0 : $B.builder_v = $B.create()
  val () = cwd_into(back0)
  val back = back0
  var app0 : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, app0)
  val () = bput_v(app0, "/app")
  val app = app0
  val known = ($B.length(here) > 0): bool
  val inside = (if known then chdir_path(app) else let val () = $B.builder_free(app) in false end): bool
  val () = $B.builder_free(here)
  val () = (if inside then store_in(cfg, w, mv, a, e, bv_f, mlen, is_accept, status) else ())
  val _ = (if inside then chdir_path(back) else let val () = $B.builder_free(back) in false end)
in end

(* ---- --prune ---- *)

fn is_hex_byte (c: int): bool = (c >= 48 && c <= 57) || (c >= 97 && c <= 102)

(* name[0, k) appended to out *)
fun name_copy {l:agz}{j:nat | j <= 1024} .<1024 - j>.
  (name: !$A.arr(byte, l, 1024), j: int j, k: int, out: !$B.builder_v >> $B.builder_v): void =
  if j >= 1024 then ()
  else if j >= k then ()
  else let
    val () = put_char_v(out, byte2int0($A.get<byte>(name, j)))
  in name_copy(name, j + 1, k, out) end

(* Whether bv[0, len) is 64 hex digits then the suffix s *)
fun hex_run {l:agz}{len:nat | len <= 524288}{i:nat | i <= 64} .<64 - i>.
  (bv: !$A.borrow(byte, l, 524288), len: int len, i: int i): bool =
  if i >= 64 then true
  else if is_hex_byte(byte_at(bv, len, i)) then hex_run(bv, len, i + 1)
  else false

(* Whether the 64 hex digits at nv[0, 64) are a line of the used keys uv[p, un) *)
fun key_used {l:agz}{ln:agz}{un:nat | un <= 524288}{p:nat | p <= un} .<un - p>.
  (uv: !$A.borrow(byte, l, 524288), un: int un, p: int p, nv: !$A.borrow(byte, ln, 524288), nlen: tlen): bool =
  if p + 64 > un then false
  else if same_range(uv, un, p, nv, nlen, 0, 64, 0) then true
  else key_used(uv, un, p + 1, nv, nlen)

val g_pruned = ref<int>(0)
val g_kept = ref<int>(0)

(* Entry i of es, its name appended to out *)
fn entry_name_into {n:nat}{i:nat | i < n} (es: !$F.entries(n), i: int i, out: !$B.builder_v >> $B.builder_v): void = let
  val name = $A.alloc<byte>(1024)
  val k = $F.entries_name(es, i, name, 1024)
  val () = name_copy(name, 0, k, out)
in $A.free<byte>(name) end

(* The files of a two-digit directory dir[0, dlen) of the memo (an
   absolute path, marked): each key file or result whose key is not among
   the used keys uv[0, un) is removed and said; removed and kept are counted
   in the cells *)
fun prune_files {n:nat}{i:nat | i <= n}{ld,lu:agz}{un:nat | un <= 524288} .<n - i>.
  (es: !$F.entries(n), n: int n, i: int i, dir: !$A.borrow(byte, ld, 524288), dlen: tlen,
   uv: !$A.borrow(byte, lu, 524288), un: int un): void =
  if i >= n then ()
  else let
    var nb : $B.builder_v = $B.create()
    val () = entry_name_into(es, i, nb)
    val @(na, nn) = $B.to_arr(nb)
    val @(fz_n, bv_n) = $A.freeze<byte>(na)
    (* <64 hex>.key or <64 hex>.res *)
    val shaped = (nn = 68 && hex_run(bv_n, nn, 0)
      && (text_has(bv_n, nn, 64, ".key") || text_has(bv_n, nn, 64, ".res"))): bool
    val used = (if shaped then key_used(uv, un, 0, bv_n, nn) else true): bool
    val () = (if shaped then (if used then !g_kept := !g_kept + 1 else let
        var rm : $B.builder_v = $B.create()
        val () = copy_to_builder_v(dir, 0, dlen, 524288, rm)
        val () = put_char_v(rm, 47)
        val () = copy_to_builder_v(bv_n, 0, nn, 524288, rm)
        val () = path_remove(rm)
        val () = !g_pruned := !g_pruned + 1
        val () = print! ("pruned ")
        val () = print_borrow(dir, (if dlen >= 2 then dlen - 2 else 0), dlen, 524288)
        val () = print! ("/")
        val () = print_borrow(bv_n, 0, nn, 524288)
      in println! () end) else ())
    val () = $A.drop<byte>(fz_n, bv_n)
    val () = $A.free<byte>($A.thaw<byte>(fz_n))
  in prune_files(es, n, i + 1, dir, dlen, uv, un) end

(* <memo>/<the two bytes of name><tail> as a builder *)
fn memo_sub2 {lm,ln:agz}{sl:nat} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  name: !$A.borrow(byte, ln, 524288), tail: string sl): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(memo, 0, mlen, 524288, b)
  val () = put_char_v(b, 47)
  val () = copy_to_builder_v(name, 0, 2, 524288, b)
  val () = bput_v(b, tail)
in b end

(* Whether <memo>/<name> is a directory of the memo itself and not a link to
   one elsewhere: the physical path the process stands in after a chdir into
   it (getcwd resolves links) is the memo's own physical path, a slash and the
   name. The file package lists names and gives no type, so this is how a
   link is told from a directory. The process is back where it was after *)
fn physical_sub {lm,ln:agz} (memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
  name: !$A.borrow(byte, ln, 524288)): bool = let
  var home : $B.builder_v = $B.create()
  val () = cwd_into(home)
  val in_memo = chdir_path(memo_plus(memo, mlen, ""))
  var pa : $B.builder_v = $B.create()
  val () = cwd_into(pa)
  val in_sub = chdir_path(memo_sub2(memo, mlen, name, ""))
  var pb : $B.builder_v = $B.create()
  val () = cwd_into(pb)
  val _ = chdir_path(home)
  val @(aa, an) = $B.to_arr(pa)
  val @(fz_a, bv_a) = $A.freeze<byte>(aa)
  val @(ba, bn) = $B.to_arr(pb)
  val @(fz_b, bv_b) = $A.freeze<byte>(ba)
  val plain = (in_memo && in_sub && an > 0 && bn = an + 3 && byte_at(bv_b, bn, an) = 47
    && byte_at(bv_b, bn, an + 1) = byte_at(name, 2, 0) && byte_at(bv_b, bn, an + 2) = byte_at(name, 2, 1)
    && same_range(bv_a, an, 0, bv_b, bn, 0, an, 0)): bool
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
  val () = $A.drop<byte>(fz_b, bv_b)
in ($A.free<byte>($A.thaw<byte>(fz_b)); plain) end

(* The directories of the memo named by two hex digits, each that holds the
   memo's mark in turn *)
fun prune_dirs {n:nat}{i:nat | i <= n}{lm,lu:agz}{un:nat | un <= 524288} .<n - i>.
  (es: !$F.entries(n), n: int n, i: int i, memo: !$A.borrow(byte, lm, 524288), mlen: tlen,
   uv: !$A.borrow(byte, lu, 524288), un: int un): void =
  if i >= n then ()
  else let
    var nb : $B.builder_v = $B.create()
    val () = entry_name_into(es, i, nb)
    val @(na, nn) = $B.to_arr(nb)
    val @(fz_n, bv_n) = $A.freeze<byte>(na)
    val two = (nn = 2 && is_hex_byte(byte_at(bv_n, nn, 0)) && is_hex_byte(byte_at(bv_n, nn, 1))): bool
    val () = (if two then let
        val d1 = memo_sub2(memo, mlen, bv_n, "")
        val dmarked = (path_exists(memo_sub2(memo, mlen, bv_n, "/.memo-dir")) && physical_sub(memo, mlen, bv_n)): bool
      in
        if dmarked then let
          val @(da, dn) = $B.to_arr(d1)
          val @(fz_d, bv_d) = $A.freeze<byte>(da)
          val dp = nul_path(memo_sub2(memo, mlen, bv_n, ""))
          val @(fz_p, bv_p) = $A.freeze<byte>(dp)
          val () = (case+ $F.dir_read(bv_p, 524288) of
            | ~$R.err(_) => ()
            | ~$R.ok(fes) => let
                val () = prune_files(fes, $F.entries_count(fes), 0, bv_d, dn, uv, un)
              in $F.entries_free(fes) end)
          val () = $A.drop<byte>(fz_p, bv_p)
          val () = $A.free<byte>($A.thaw<byte>(fz_p))
          val () = $A.drop<byte>(fz_d, bv_d)
        in $A.free<byte>($A.thaw<byte>(fz_d)) end
        else $B.builder_free(d1)
      end else ())
    val () = $A.drop<byte>(fz_n, bv_n)
    val () = $A.free<byte>($A.thaw<byte>(fz_n))
  in prune_dirs(es, n, i + 1, memo, mlen, uv, un) end

(* Removes from the memo the files of the keys no fixture of this run asked
   for, saying each; only in a directory that holds the memo's mark, only in
   its two-digit directories that hold theirs, only files named by a key
   (rm -f of a name, never through a directory) *)
fn memo_prune {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): void = let
  var md : $B.builder_v = $B.create()
  val have_dir = memo_dir_into(cfg, w, md)
  val @(ma, mn) = $B.to_arr(md)
  val @(fz_m, bv_m) = $A.freeze<byte>(ma)
  val marked = (have_dir && path_exists(memo_plus(bv_m, mn, "/.bats-fixtures-memo"))): bool
  val ua = $A.alloc<byte>(524288): [l_ua:agz] $A.arr(byte, l_ua, 524288)
  val un0 = path_read(work_text(cfg, w, "memo-used"), ua)
  val un = text_len(un0)
  val @(fz_u, bv_u) = $A.freeze<byte>(ua)
  val () = (if ~marked then let
      val () = print! ("memo: nothing pruned, ")
      val () = print_borrow(bv_m, 0, mn, 524288)
    in println! (" is not a fixtures memo") end
    else let
      val () = !g_pruned := 0
      val () = !g_kept := 0
      val da = nul_path(memo_plus(bv_m, mn, ""))
      val @(fz_d, bv_d) = $A.freeze<byte>(da)
      val () = (case+ $F.dir_read(bv_d, 524288) of
        | ~$R.err(_) => ()
        | ~$R.ok(es) => let
            val () = prune_dirs(es, $F.entries_count(es), 0, bv_m, mn, bv_u, un)
          in $F.entries_free(es) end)
      val () = $A.drop<byte>(fz_d, bv_d)
      val () = $A.free<byte>($A.thaw<byte>(fz_d))
    in println! ("memo: pruned ", !g_pruned, " files, kept ", !g_kept) end)
  val () = $A.drop<byte>(fz_u, bv_u)
  val () = $A.free<byte>($A.thaw<byte>(fz_u))
  val () = $A.drop<byte>(fz_m, bv_m)
in $A.free<byte>($A.thaw<byte>(fz_m)) end

(* Runs bats check in <work>/app with its output in <work>/check.log and the
   seconds it took in <work>/check.seconds: the exit status of the check *)
fn run_check {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): int = let
  var app : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, app)
  val () = bput_v(app, "/app")
  var repository : $B.builder_v = $B.create()
  val () = (if w.repository >= 0 then put_cfg(cfg, w.repository, repository) else ())
  var log : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, log)
  val () = bput_v(log, "/check.log")
  var secs : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, secs)
  val () = bput_v(secs, "/check.seconds")
  var project : $B.builder_v = $B.create()
  val () = bput_v(project, ".")
in
  run_sh("app=$1; prog=$2; repo=$3; log=$4; secs=$5; proj=$6; case $prog in */*) prog=$(cd \"$(dirname \"$prog\")\" && pwd)/$(basename \"$prog\") ;; esac; case $log in /*) ;; *) log=$PWD/$log ;; esac; case $secs in /*) ;; *) secs=$PWD/$secs ;; esac; case $repo in ''|/*) ;; *) repo=$PWD/$repo ;; esac; if [ -z \"${GIT_DIR:-}\" ]; then g=$(git -C \"$proj\" rev-parse --absolute-git-dir 2>/dev/null) && GIT_DIR=$g && export GIT_DIR; fi; s=$(date +%s); cd \"$app\" || exit 98; if [ -n \"$repo\" ]; then \"$prog\" check --repository \"$repo\"; else \"$prog\" check; fi > \"$log\" 2>&1; rc=$?; echo $(( $(date +%s) - s )) > \"$secs\"; exit $rc",
    $L.list_vt_cons(mk_arg(app), $L.list_vt_cons(cfg_arg(cfg, w.program), $L.list_vt_cons(mk_arg(repository),
    $L.list_vt_cons(mk_arg(log), $L.list_vt_cons(mk_arg(secs), $L.list_vt_cons(mk_arg(project), $L.list_vt_nil())))))))
end

(* The build and the module of <work>/app as the base check left them: the
   build from <work>/build-checked, the module from the project *)
fn restore_copy {l:agz}{lx:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings, bv_m: !$A.borrow(byte, lx, 524288), mlen: xi, hit: bool): void = let
  var work : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, work)
  var module : $B.builder_v = $B.create()
  val () = put_range(bv_m, 524288, 0, mlen, module)
  var project : $B.builder_v = $B.create()
  val () = bput_v(project, ".")
  var served : $B.builder_v = $B.create()
  val () = (if hit then bput_v(served, "hit") else bput_v(served, "run"))
  (* a memo hit ran no check, so the build is as the base check left it *)
  val _ = run_sh("if [ \"$4\" = run ]; then rm -rf \"$1/app/build\" && cp -a \"$1/build-checked\" \"$1/app/build\"; fi && cp -p \"$2/$3\" \"$1/app/$3\"",
    $L.list_vt_cons(mk_arg(work), $L.list_vt_cons(mk_arg(project), $L.list_vt_cons(mk_arg(module),
    $L.list_vt_cons(mk_arg(served), $L.list_vt_nil())))))
in end

(* ============================================================
   One fixture
   ============================================================ *)

val g_passed = ref<int>(0)
val g_failed = ref<int>(0)
val g_memo = ref<int>(0)

(* The length of the file <leaf> of the work directory (~1 when it is not
   there) *)
fn read_text_there {l:agz}{sl:nat} (cfg: !$A.borrow(byte, l, 524288), w: settings, leaf: string sl): int = let
  val ta = $A.alloc<byte>(524288): [l_ta:agz] $A.arr(byte, l_ta, 524288)
  val tn = read_file_text(work_file(cfg, w, leaf), ta)
  val () = $A.free<byte>(ta)
in tn end

(* The file <leaf> of the work directory to the output *)
fn print_text_there {l:agz}{sl:nat} (cfg: !$A.borrow(byte, l, 524288), w: settings, leaf: string sl): void = let
  val ta = $A.alloc<byte>(524288): [l_ta:agz] $A.arr(byte, l_ta, 524288)
  val tn = read_file_text(work_file(cfg, w, leaf), ta)
  val @(fz, bv) = $A.freeze<byte>(ta)
  val () = (if tn > 0 then print_borrow(bv, 0, text_len(tn), 524288) else ())
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in end

(* A decimal number as text *)
fn say_failed_lines {l:agz} (lv: !$A.borrow(byte, l, 524288), llen: tlen): void = let
  (* the first five lines of the log that name an error, as run.sh showed *)
  fun loop {len:nat | len <= 524288}{p:nat | p <= len} .<len - p>.
    (lv: !$A.borrow(byte, l, 524288), len: int len, p: int p, shown: xi): void =
    if p >= len then ()
    else if shown >= 5 then ()
    else let
      val e = line_end(lv, len, p, false)
      fun has_error {len:nat | len <= 524288}{q:nat | q <= len} .<len - q>.
        (lv: !$A.borrow(byte, l, 524288), len: int len, q: int q, e: xi): bool =
        if q >= len then false
        else if q >= e then false
        else if text_has(lv, len, q, "error") then true
        else has_error(lv, len, q + 1, e)
      val hit = has_error(lv, len, p, e)
      val () = (if hit then let
          val () = print_borrow(lv, p, e, 524288)
        in println! () end else ())
    in
      if e >= len then ()
      else loop(lv, len, e + 1, (if hit then shown + 1 else shown))
    end
in
  loop(lv, llen, 0, 0)
end

(* The member name mv[a, e) printed *)
fn say_member {lm:agz} (mv: !$A.borrow(byte, lm, 524288), a: xi, e: xi): void =
  print_borrow(mv, a, e, 524288)

fn fail_member {lm:agz} (mv: !$A.borrow(byte, lm, 524288), a: xi, e: xi): void = let
  val () = !g_failed := !g_failed + 1
  val () = print! ("FAIL ")
in say_member(mv, a, e) end

(* Runs the fixture whose name is mv[a, e) (accept/<name> or reject/<name>)
   in the checked copy, and says how it went *)
fn run_member {l:agz}{lm:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e): void = let
  val is_accept = text_has(mv, e, a, "accept/")
  (* the module and the line the snippet goes before *)
  val fa = $A.alloc<byte>(524288): [l_fa:agz] $A.arr(byte, l_fa, 524288)
  val flen0 = read_file_text(fixture_path(cfg, w, mv, a, e, "file"), fa)
  val ba = $A.alloc<byte>(524288): [l_ba:agz] $A.arr(byte, l_ba, 524288)
  val blen0 = read_file_text(fixture_path(cfg, w, mv, a, e, "before"), ba)
  val sa = $A.alloc<byte>(524288): [l_sa:agz] $A.arr(byte, l_sa, 524288)
  val slen0 = read_file_text(fixture_path(cfg, w, mv, a, e, "snippet.bats"), sa)
  val xa = $A.alloc<byte>(524288): [l_xa:agz] $A.arr(byte, l_xa, 524288)
  val xlen0 = read_file_text(fixture_path(cfg, w, mv, a, e, "expect"), xa)
  (* `file`, as expect.py reads it, stripped (moved down in its array, so
     the module's name is fa[0, mlen)) *)
  val flen = text_len(flen0)
  val fstart = lead_blank(fa, flen, 0)
  val fstop = trail_blank(fa, flen, fstart, flen)
  val mlen = fstop - fstart
  val () = shift_down(fa, fstart, mlen, 0)
  val @(fz_f, bv_f) = $A.freeze<byte>(fa)
  val @(fz_b, bv_b) = $A.freeze<byte>(ba)
  val @(fz_s, bv_s) = $A.freeze<byte>(sa)
  val @(fz_x, bv_x) = $A.freeze<byte>(xa)
  (* `before`, as the shell reads it, without its trailing line feeds *)
  val blen1 = text_len(blen0)
  val slen = text_len(slen0)
  val xlen = text_len(xlen0)
  val blen = trim_feeds(bv_b, blen1)
  val missing = (flen0 < 0 || blen0 < 0 || slen0 < 0 || (xlen0 < 0 && ~is_accept)): bool
in
  if missing then let
    val () = fail_member(mv, a, e)
    val () = println! (": a file of the fixture (file, before, snippet.bats, expect) cannot be read")
    val () = $A.drop<byte>(fz_f, bv_f)
    val () = $A.free<byte>($A.thaw<byte>(fz_f))
    val () = $A.drop<byte>(fz_b, bv_b)
    val () = $A.free<byte>($A.thaw<byte>(fz_b))
    val () = $A.drop<byte>(fz_s, bv_s)
    val () = $A.free<byte>($A.thaw<byte>(fz_s))
    val () = $A.drop<byte>(fz_x, bv_x)
    val () = $A.free<byte>($A.thaw<byte>(fz_x))
  in () end
  else let
    (* the module of the fixture is bv_f[0, mlen) *)
    (* the module of the checked copy, to find the line in *)
    val pa = path_arr(app_module_path(cfg, w, bv_f, mlen, "app"))
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val at = (case+ read_whole(bv_p, 524288) of
      | ~whole_err(_) => ~1
      | ~whole_ok(ar, piece, pm, pn) => let
          val @(fz_pc, bv_pc) = $A.freeze<byte>(piece)
          (* the module may be larger than a text; find_line reads it
             through peek, which is bounded by the array it is given *)
          val r = find_module_line(bv_pc, pm, pn, bv_b, blen)
          val () = $A.drop<byte>(fz_pc, bv_pc)
          val () = whole_free(ar, $A.thaw<byte>(fz_pc))
        in r end): int
  in
    if at <= 0 then let
      val () = fail_member(mv, a, e)
      val () = (if at < 0 then println! (": the module ", "cannot be read in the checked copy") else let
          val () = print! (": no line \"")
          val () = print_borrow(bv_b, 0, blen, 524288)
          val () = print! ("\" in ")
          val () = print_borrow(bv_f, 0, mlen, 524288)
        in println! () end)
      val () = $A.drop<byte>(fz_f, bv_f)
      val () = $A.free<byte>($A.thaw<byte>(fz_f))
      val () = $A.drop<byte>(fz_p, bv_p)
      val () = $A.free<byte>($A.thaw<byte>(fz_p))
      val () = $A.drop<byte>(fz_b, bv_b)
      val () = $A.free<byte>($A.thaw<byte>(fz_b))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
      val () = $A.drop<byte>(fz_x, bv_x)
      val () = $A.free<byte>($A.thaw<byte>(fz_x))
    in () end
    else let
      val () = $A.drop<byte>(fz_p, bv_p)
      val () = $A.free<byte>($A.thaw<byte>(fz_p))
      (* put the snippet in and ask the memo; on a miss run the check and
         keep what it said; then read what it said *)
      val () = memo_clear(cfg, w)
      val spliced = splice_snippet(cfg, w, mv, a, e, bv_f, mlen, at)
      val probed = (if spliced = 0 then memo_probe(cfg, w, mv, a, e, bv_f, mlen, is_accept) else spliced): int
      val hit = (probed = 0 || probed = 1): bool
      val rc = (if hit then probed
        else if probed = 100 then let
          val ran = run_check(cfg, w)
          val () = memo_store(cfg, w, mv, a, e, bv_f, mlen, is_accept, ran)
        in ran end
        else probed): int
      val elapsed = read_elapsed(cfg, w)
      val stale = (read_text_there(cfg, w, "check.stale") > 0): bool
      val marker = (if hit then " [memo]" else ""): string
      val la = $A.alloc<byte>(524288): [l_la:agz] $A.arr(byte, l_la, 524288)
      val llen0 = read_file_text(log_path(cfg, w), la)
      val llen = text_len(llen0)
      val @(fz_l, bv_l) = $A.freeze<byte>(la)
      val () = (if stale then let
          val () = fail_member(mv, a, e)
          val () = print! (": ")
        in print_text_there(cfg, w, "check.stale") end
        else if llen0 < 0 then let
          val () = fail_member(mv, a, e)
        in println! (": the check's log cannot be read") end
        else if is_accept then
          (if rc = 0 then let
              val () = !g_passed := !g_passed + 1
              val () = (if hit then !g_memo := !g_memo + 1 else ())
              val () = print! ("ok   ")
              val () = say_member(mv, a, e)
            in println! (" (", elapsed, " s)", marker) end
          else let
              val () = fail_member(mv, a, e)
              val () = println! (": should type-check")
            in say_failed_lines(bv_l, llen) end)
        else
          (if rc = 0 then let
              val () = fail_member(mv, a, e)
            in println! (": should be rejected") end
          else let
              var problem : $B.builder_v = $B.create()
              val () = judge(bv_l, llen, bv_x, xlen, bv_s, slen, bv_f, mlen, at, problem)
              val @(pa2, pl2) = $B.to_arr(problem)
              val @(fz_q, bv_q) = $A.freeze<byte>(pa2)
              val () = (if pl2 > 0 then let
                  val () = fail_member(mv, a, e)
                  val () = print! (": rejected, but not as its expect says: ")
                  val () = print_borrow(bv_q, 0, pl2, 524288)
                  val () = println! ()
                in say_failed_lines(bv_l, llen) end
                else let
                  val () = !g_passed := !g_passed + 1
                  val () = (if hit then !g_memo := !g_memo + 1 else ())
                  val () = print! ("ok   ")
                  val () = say_member(mv, a, e)
                in println! (" (", elapsed, " s)", marker) end)
              val () = $A.drop<byte>(fz_q, bv_q)
              val () = $A.free<byte>($A.thaw<byte>(fz_q))
            in () end))
      val () = $A.drop<byte>(fz_l, bv_l)
      val () = $A.free<byte>($A.thaw<byte>(fz_l))
      val () = restore_copy(cfg, w, bv_f, mlen, hit)
      val () = $A.drop<byte>(fz_f, bv_f)
      val () = $A.free<byte>($A.thaw<byte>(fz_f))
      val () = $A.drop<byte>(fz_b, bv_b)
      val () = $A.free<byte>($A.thaw<byte>(fz_b))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
      val () = $A.drop<byte>(fz_x, bv_x)
      val () = $A.free<byte>($A.thaw<byte>(fz_x))
    in () end
  end
end


(* ============================================================
   The command line: bats fixtures <dir> [--only <member>]... [--cold]
   [--work <dir>] [--repository <dir>]
   ============================================================ *)

(* The end of the word at p of the NUL-separated arguments *)
fun word_stop {l:agz}{t:nat | t <= 4096}{p:nat | p <= t} .<t - p>.
  (bv: !$A.borrow(byte, l, 4096), t: int t, p: int p): [r:nat | p <= r; r <= t] int r =
  if p >= t then p
  else if peek(bv, p, 4096) = 0 then p
  else word_stop(bv, t, p + 1)

fun arg_is_from {l:agz}{sl:nat}{i:nat | i <= sl} .<sl - i>.
  (bv: !$A.borrow(byte, l, 4096), p: xi, s: string sl, slen: int sl, i: int i): bool =
  if i >= slen then true
  else if peek(bv, p + i, 4096) = char2int0(string_get_at(s, i)) then arg_is_from(bv, p, s, slen, i + 1)
  else false

(* Whether the word bv[a, e) is exactly the text s *)
fn arg_is {l:agz}{sl:nat} (bv: !$A.borrow(byte, l, 4096), a: xi, e: xi, s: string sl): bool =
  e - a = g1u2i(string1_length(s)) && arg_is_from(bv, a, s, g1u2i(string1_length(s)), 0)

(* What the options said: the spans of the directory, --work, --repository
   and --memo (~1 when not given), whether --cold, --prune and --only were
   given (1 or 0), and the first thing wrong with the line (kind 1: an
   option that is not one of ours, 2: an option with no value, 3: a second
   directory), as a span *)
typedef options = @{dir_s= xi, dir_e= xi, work_s= xi, work_e= xi, repo_s= xi, repo_e= xi,
  memo_s= xi, memo_e= xi, cold= int, prune= int, only= int,
  bad_kind= int, bad_s= xi, bad_e= xi}

fn opt_dir (o: options, s: xi, e: xi): options =
  @{dir_s= s, dir_e= e, work_s= o.work_s, work_e= o.work_e, repo_s= o.repo_s, repo_e= o.repo_e,
    memo_s= o.memo_s, memo_e= o.memo_e, cold= o.cold, prune= o.prune, only= o.only,
    bad_kind= o.bad_kind, bad_s= o.bad_s, bad_e= o.bad_e}

fn opt_work (o: options, s: xi, e: xi): options =
  @{dir_s= o.dir_s, dir_e= o.dir_e, work_s= s, work_e= e, repo_s= o.repo_s, repo_e= o.repo_e,
    memo_s= o.memo_s, memo_e= o.memo_e, cold= o.cold, prune= o.prune, only= o.only,
    bad_kind= o.bad_kind, bad_s= o.bad_s, bad_e= o.bad_e}

fn opt_repo (o: options, s: xi, e: xi): options =
  @{dir_s= o.dir_s, dir_e= o.dir_e, work_s= o.work_s, work_e= o.work_e, repo_s= s, repo_e= e,
    memo_s= o.memo_s, memo_e= o.memo_e, cold= o.cold, prune= o.prune, only= o.only,
    bad_kind= o.bad_kind, bad_s= o.bad_s, bad_e= o.bad_e}

fn opt_memo (o: options, s: xi, e: xi): options =
  @{dir_s= o.dir_s, dir_e= o.dir_e, work_s= o.work_s, work_e= o.work_e, repo_s= o.repo_s, repo_e= o.repo_e,
    memo_s= s, memo_e= e, cold= o.cold, prune= o.prune, only= o.only,
    bad_kind= o.bad_kind, bad_s= o.bad_s, bad_e= o.bad_e}

fn opt_flags (o: options, cold: int, prune: int, only: int): options =
  @{dir_s= o.dir_s, dir_e= o.dir_e, work_s= o.work_s, work_e= o.work_e, repo_s= o.repo_s, repo_e= o.repo_e,
    memo_s= o.memo_s, memo_e= o.memo_e, cold= cold, prune= prune, only= only,
    bad_kind= o.bad_kind, bad_s= o.bad_s, bad_e= o.bad_e}

fn opt_bad (o: options, kind: int, s: xi, e: xi): options =
  @{dir_s= o.dir_s, dir_e= o.dir_e, work_s= o.work_s, work_e= o.work_e, repo_s= o.repo_s, repo_e= o.repo_e,
    memo_s= o.memo_s, memo_e= o.memo_e, cold= o.cold, prune= o.prune, only= o.only,
    bad_kind= kind, bad_s= s, bad_e= e}

fun parse_options {l:agz}{t:nat | t <= 4096}{p:nat | p <= t} .<t - p>.
  (bv: !$A.borrow(byte, l, 4096), t: int t, p: int p, o: options): options =
  if p >= t then o
  else if o.bad_kind <> 0 then o
  else let
    val e = word_stop(bv, t, p)
    val nxt = e + 1
    val valued = (arg_is(bv, p, e, "--only") || arg_is(bv, p, e, "--work") || arg_is(bv, p, e, "--repository")
      || arg_is(bv, p, e, "--memo")): bool
  in
    if arg_is(bv, p, e, "--cold") then let
      val o2 = opt_flags(o, 1, o.prune, o.only)
    in (if nxt <= t then parse_options(bv, t, nxt, o2) else o2) end
    else if arg_is(bv, p, e, "--prune") then let
      val o2 = opt_flags(o, o.cold, 1, o.only)
    in (if nxt <= t then parse_options(bv, t, nxt, o2) else o2) end
    else if valued then
      (if nxt >= t then opt_bad(o, 2, p, e)
      else let
        val ve = word_stop(bv, t, nxt)
        val o2 = (if arg_is(bv, p, e, "--work") then opt_work(o, nxt, ve)
          else if arg_is(bv, p, e, "--repository") then opt_repo(o, nxt, ve)
          else if arg_is(bv, p, e, "--memo") then opt_memo(o, nxt, ve)
          else if arg_is(bv, p, e, "--only") then opt_flags(o, o.cold, o.prune, 1)
          else o): options
      in
        if ve + 1 <= t then parse_options(bv, t, ve + 1, o2) else o2
      end)
    else if e - p >= 2 && peek(bv, p, 4096) = 45 && peek(bv, p + 1, 4096) = 45 then opt_bad(o, 1, p, e)
    else if o.dir_s >= 0 then opt_bad(o, 3, p, e)
    else let
      val o2 = opt_dir(o, p, e)
    in
      if nxt <= t then parse_options(bv, t, nxt, o2) else o2
    end
  end

(* Whether member mv[a, e) is the word bv[vs, ve) *)
fn member_is {lm:agz}{l:agz} (mv: !$A.borrow(byte, lm, 524288), mlen: xi, a: xi, e: xi,
  bv: !$A.borrow(byte, l, 4096), vs: xi, ve: xi): bool = let
  fun same {n:nat}{j:nat | j <= n} .<n - j>. (mv: !$A.borrow(byte, lm, 524288), mlen: xi, a: xi, bv: !$A.borrow(byte, l, 4096), vs: xi, n: int n, j: int j): bool =
    if j >= n then true
    else if byte_at(mv, mlen, a + j) = peek(bv, vs + j, 4096) then same(mv, mlen, a, bv, vs, n, j + 1)
    else false
in if e - a = ve - vs then (if ve >= vs then same(mv, mlen, a, bv, vs, ve - vs, 0) else false) else false end

(* The end of the word after the one that ends at we when that was --only,
   else we *)
fn value_end {l:agz}{t:nat | t <= 4096}{we:nat | we <= t}
  (bv: !$A.borrow(byte, l, 4096), t: int t, we: int we, is_only: bool): [r:nat | we <= r; r <= t] int r =
  if is_only then (if we + 1 <= t then word_stop(bv, t, we + 1) else we) else we

(* Whether the member mv[a, e) is among those the --only options name, or
   there are none: scans the words after `fixtures` *)
fun chosen {lm:agz}{l:agz}{t:nat | t <= 4096}{p:nat | p <= t} .<t - p>.
  (mv: !$A.borrow(byte, lm, 524288), mlen: xi, a: xi, e: xi,
   bv: !$A.borrow(byte, l, 4096), t: int t, p: int p, only_seen: bool, named: bool): bool =
  if p >= t then (if only_seen then named else true)
  else let
    val we = word_stop(bv, t, p)
    val is_only = arg_is(bv, p, we, "--only")
    val ve = value_end(bv, t, we, is_only)
    val hit = (is_only && we + 1 < t && member_is(mv, mlen, a, e, bv, we + 1, ve)): bool
    val nxt = ve + 1
  in
    if nxt > t then (if only_seen || is_only then (named || hit) else true)
    else chosen(mv, mlen, a, e, bv, t, nxt, only_seen || is_only, named || hit)
  end

(* Whether every --only value is a member listed in mv[0, mlen): the
   first that is not is returned as a span (~1 if all are) *)
fun unlisted {lm:agz}{l:agz}{t:nat | t <= 4096}{p:nat | p <= t} .<t - p>.
  (mv: !$A.borrow(byte, lm, 524288), mlen: tlen, bv: !$A.borrow(byte, l, 4096), t: int t, p: int p): @(xi, xi) = let
  fun listed {mlen:nat | mlen <= 524288}{q:nat | q <= mlen} .<mlen - q>.
    (mv: !$A.borrow(byte, lm, 524288), mlen: int mlen, q: int q, bv: !$A.borrow(byte, l, 4096), vs: xi, ve: xi): bool = let
    val e = line_end(mv, mlen, q, false)
  in
    if member_is(mv, mlen, q, e, bv, vs, ve) then true
    else if e >= mlen then false
    else listed(mv, mlen, e + 1, bv, vs, ve)
  end
in
  if p >= t then @(~1, ~1)
  else let
    val we = word_stop(bv, t, p)
  in
    if arg_is(bv, p, we, "--only") then
      (if we + 1 < t then let
        val ve = word_stop(bv, t, we + 1)
        val ok = listed(mv, mlen, 0, bv, we + 1, ve)
      in
        if ~ok then @(we + 1, ve)
        else if ve + 1 <= t then unlisted(mv, mlen, bv, t, ve + 1)
        else @(~1, ~1)
      end
      else if we + 1 <= t then unlisted(mv, mlen, bv, t, we + 1)
      else @(~1, ~1))
    else if we + 1 <= t then unlisted(mv, mlen, bv, t, we + 1)
    else @(~1, ~1)
  end
end

(* Runs (or only counts, when run is false) the chosen members among the
   lines of mv[0, mlen) from q on; returns the number chosen *)
fun members_loop {lc:agz}{lm:agz}{l:agz}{mlen:nat | mlen <= 524288}{t:nat | t <= 4096}{o:nat | o <= t}{q:nat | q <= mlen} .<mlen - q>.
  (cfg: !$A.borrow(byte, lc, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), mlen: int mlen, q: int q,
   bv: !$A.borrow(byte, l, 4096), t: int t, o: int o, run: bool, n: xi): xi =
  if q >= mlen then n
  else let
    val e = line_end(mv, mlen, q, false)
    val take = (e > q && chosen(mv, mlen, q, e, bv, t, o, false, false)): bool
    val () = (if take && run then run_member(cfg, w, mv, q, e) else ())
  in
    if e >= mlen then (if take then n + 1 else n)
    else members_loop(cfg, w, mv, mlen, e + 1, bv, t, o, run, (if take then n + 1 else n))
  end

(* A directory made by mktemp -d, as a builder; empty when it cannot be *)
fn make_work_dir (out: !$B.builder_v >> $B.builder_v): void = let
  val exec = str_to_path_arr("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(exec)
  var b1 = $B.create()
  val () = bput_v(b1, "sh")
  var b2 = $B.create()
  val () = bput_v(b2, "-c")
  var b3 = $B.create()
  val () = bput_v(b3, "mktemp -d")
  val cap = $A.alloc<byte>(4096)
  val @(rc, k) = run_cmd_capture(bv_x, $L.list_vt_cons(mk_arg(b1),
    $L.list_vt_cons(mk_arg(b2), $L.list_vt_cons(mk_arg(b3), $L.list_vt_nil()))), cap)
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
  val @(fz_o, bv_o) = $A.freeze<byte>(cap)
  val stop = (if k > 0 then (if peek(bv_o, k - 1, 4096) = 10 then k - 1 else k) else 0): xi
  val () = (if rc = 0 && stop > 0 then copy_to_builder_v(bv_o, 0, stop, 4096, out) else ())
  val () = $A.drop<byte>(fz_o, bv_o)
  val () = $A.free<byte>($A.thaw<byte>(fz_o))
in end

(* The string at s of cfg to stderr *)
fn prerr_cfg {l:agz} (cfg: !$A.borrow(byte, l, 524288), s: xi): void = let
  var b : $B.builder_v = $B.create()
  val () = (if s >= 0 && s <= 524288 then put_cfg(cfg, s, b) else ())
in prerr_builder(b) end

(* The word bv[s, e) to stderr *)
fn prerr_args {l:agz} (bv: !$A.borrow(byte, l, 4096), s: xi, e: xi): void = prerr_seg(bv, s, e, 4096)

fn usage (): void = let
  val () = prerr! ("usage: bats fixtures <dir> [--only <member>]... [--cold] [--work <dir>] [--memo <dir>] [--prune] [--repository <dir>]\n")
in set_exit_code(2) end

(* Runs the fixtures: the chosen ones of <dir> against a copy of the
   project in <work>/app *)
fn fixtures_with {lc:agz}{l:agz}{t:nat | t <= 4096}{o:nat | o <= t}
  (cfg: !$A.borrow(byte, lc, 524288), w: settings, bv: !$A.borrow(byte, l, 4096), t: int t, o: int o): void = let
  var work : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, work)
  var dir : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.directory, dir)
  (* the members, in the order of the directory's names *)
  val listed = run_sh("mkdir -p \"$1\" && LC_ALL=C && export LC_ALL && for v in accept reject; do for d in \"$2/$v\"/*/; do if [ -d \"$d\" ]; then printf '%s/%s\\n' \"$v\" \"$(basename \"$d\")\"; fi; done; done > \"$1/members\"",
    $L.list_vt_cons(mk_arg(work), $L.list_vt_cons(mk_arg(dir), $L.list_vt_nil())))
  val ma = $A.alloc<byte>(524288): [l_ma:agz] $A.arr(byte, l_ma, 524288)
  val mn = read_file_text(work_file(cfg, w, "members"), ma)
  val @(fz_m, bv_m) = $A.freeze<byte>(ma)
  val mlen = text_len(mn)
  val @(bad_s, bad_e) = unlisted(bv_m, mlen, bv, t, o)
  val () = (
  if listed <> 0 || mn < 0 then let
    val () = prerr! ("error: bats fixtures: the fixtures in ")
    val () = prerr_cfg(cfg, w.directory)
    val () = prerr! (" cannot be listed\n")
  in set_exit_code(2) end
  else if mn = 0 then let
    val () = prerr! ("error: bats fixtures: no fixtures in ")
    val () = prerr_cfg(cfg, w.directory)
    val () = prerr! (" (it holds accept/<name> and reject/<name> directories)\n")
  in set_exit_code(2) end
  else if bad_s >= 0 then let
    val () = prerr! ("error: bats fixtures: no fixture ")
    val () = prerr_args(bv, bad_s, bad_e)
    val () = prerr! (" (a member is accept/<name> or reject/<name>)\n")
  in set_exit_code(2) end
  else let
    val chosen_count = members_loop(cfg, w, bv_m, mlen, 0, bv, t, o, false, 0)
  in
    if chosen_count = 0 then println! ("fixtures: 0 ok, 0 failed")
    else let
      (* the app: a copy of the project, checked whole *)
      var work2 : $B.builder_v = $B.create()
      val () = put_cfg(cfg, w.work, work2)
      var project2 : $B.builder_v = $B.create()
      val () = bput_v(project2, ".")
      val copied = run_sh("mkdir -p \"$1/app\" && p=$(cd \"$2\" && pwd -P) && w=$(cd \"$1\" && pwd -P) && x=--exclude=./build && case $w in \"$p\"/*) x=--exclude=./${w#$p/} ;; esac && find \"$1/app\" -mindepth 1 -maxdepth 1 ! -name build -exec rm -rf {} + && (cd \"$2\" && tar cf - --exclude=./build --exclude=./dist --exclude=./.git --exclude=./node_modules --exclude=./test-results \"$x\" .) | (cd \"$1/app\" && tar xf -)",
        $L.list_vt_cons(mk_arg(work2), $L.list_vt_cons(mk_arg(project2), $L.list_vt_nil())))
      val checked = (if copied <> 0 then 97 else let
          var work3 : $B.builder_v = $B.create()
          val () = put_cfg(cfg, w.work, work3)
          var repository : $B.builder_v = $B.create()
          val () = (if w.repository >= 0 then put_cfg(cfg, w.repository, repository) else ())
          var project3 : $B.builder_v = $B.create()
          val () = bput_v(project3, ".")
        in
        run_sh("w=$1; prog=$2; repo=$3; proj=$4; case $prog in */*) prog=$(cd \"$(dirname \"$prog\")\" && pwd)/$(basename \"$prog\") ;; esac; case $w in /*) ;; *) w=$PWD/$w ;; esac; case $repo in ''|/*) ;; *) repo=$PWD/$repo ;; esac; if [ -z \"${GIT_DIR:-}\" ]; then g=$(git -C \"$proj\" rev-parse --absolute-git-dir 2>/dev/null) && GIT_DIR=$g && export GIT_DIR; fi; cd \"$w/app\" || exit 98; if [ -n \"$repo\" ]; then \"$prog\" check --repository \"$repo\"; else \"$prog\" check; fi > \"$w/app.log\" 2>&1 || exit 1; rm -rf \"$w/build-checked\" && cp -a build \"$w/build-checked\"",
          $L.list_vt_cons(mk_arg(work3), $L.list_vt_cons(cfg_arg(cfg, w.program), $L.list_vt_cons(mk_arg(repository),
          $L.list_vt_cons(mk_arg(project3), $L.list_vt_nil()))))) end): int
    in
      if checked <> 0 then let
        val () = set_exit_code(1)
        val () = println! ("FAIL check (the app, which the fixtures start from):")
        val () = (if copied <> 0 then println! ("the project could not be copied") else let
            val la = $A.alloc<byte>(524288): [l_la:agz] $A.arr(byte, l_la, 524288)
            val ln = read_file_text(work_file(cfg, w, "app.log"), la)
            val @(fz_l, bv_l) = $A.freeze<byte>(la)
            val () = (if ln > 0 then print_borrow(bv_l, 0, ln, 524288) else ())
            val () = $A.drop<byte>(fz_l, bv_l)
            val () = $A.free<byte>($A.thaw<byte>(fz_l))
          in () end)
      in () end
      else let
        val () = path_remove(work_text(cfg, w, "memo-used"))
        val ran = members_loop(cfg, w, bv_m, mlen, 0, bv, t, o, true, 0)
        val () = (if w.prune <> 0 then memo_prune(cfg, w) else ())
        val () = print! ("fixtures: ", !g_passed, " ok, ", !g_failed, " failed")
        val () = (if !g_memo > 0 then print! (" (", !g_memo, " from the memo)") else ())
        val () = println! ()
      in (if !g_failed > 0 then set_exit_code(1) else ()) end
    end
  end): void
  val () = $A.drop<byte>(fz_m, bv_m)
  val () = $A.free<byte>($A.thaw<byte>(fz_m))
in end

(* The argument bv[s, e) appended to out as an absolute path: as it is when
   it begins with a slash, else after the current directory cwd[0, cn) (the
   memo works in the app, where a relative path would be another's) *)
fn put_absolute {l:agz}{lc:agz}{s,e:int} (bv: !$A.borrow(byte, l, 4096), s: int s, e: int e,
  cwd: !$A.borrow(byte, lc, 524288), cn: tlen, out: !$B.builder_v >> $B.builder_v): void =
  if peek(bv, s, 4096) = 47 then copy_to_builder_v(bv, s, e, 4096, out)
  else let
    val () = copy_to_builder_v(cwd, 0, cn, 524288, out)
    val () = put_char_v(out, 47)
  in copy_to_builder_v(bv, s, e, 4096, out) end

(* Runs bats fixtures for the arguments bv[0, t) *)
fn fixtures_run {l:agz}{t:nat | t <= 4096} (bv: !$A.borrow(byte, l, 4096), t: int t): void = let
  val a0 = word_stop(bv, t, 0)
  val a1 = a0 + 1
  val a1e = (if a1 <= t then word_stop(bv, t, a1) else t): [r:nat | r <= t] int r
  val none = @{dir_s= ~1, dir_e= ~1, work_s= ~1, work_e= ~1, repo_s= ~1, repo_e= ~1,
    memo_s= ~1, memo_e= ~1, cold= 0, prune= 0, only= 0, bad_kind= 0, bad_s= ~1, bad_e= ~1}: options
  val o = (if a1e + 1 <= t then parse_options(bv, t, a1e + 1, none) else none): options
in
  if o.bad_kind <> 0 then let
    val () = (if o.bad_kind = 1 then prerr! ("error: bats fixtures: unknown option ")
      else if o.bad_kind = 2 then prerr! ("error: bats fixtures: no value after ")
      else prerr! ("error: bats fixtures: a second directory, "))
    val () = prerr_args(bv, o.bad_s, o.bad_e)
    val () = prerr_newline()
  in usage() end
  else if o.dir_s < 0 then usage()
  else if o.prune <> 0 && o.only <> 0 then let
    val () = prerr! ("error: bats fixtures: --prune removes what no fixture of the run used, so it needs the whole set: not with --only\n")
  in set_exit_code(2) end
  else let
    (* the work directory: --work, else a temporary one, removed at the end *)
    var made : $B.builder_v = $B.create()
    val () = (if o.work_s < 0 then make_work_dir(made) else ())
    val @(ma, made_len) = $B.to_arr(made)
    val have_work = (o.work_s >= 0 || made_len > 0): bool
  in
    if ~have_work then let
      val () = $A.free<byte>(ma)
      val () = prerr! ("error: bats fixtures: a temporary directory cannot be made (use --work)\n")
    in set_exit_code(2) end
    else let
      (* the settings, as NUL-terminated strings in one buffer *)
      var cb : $B.builder_v = $B.create()
      var cw : $B.builder_v = $B.create()
      val () = cwd_into(cw)
      val @(cwa, cwn) = $B.to_arr(cw)
      val @(fz_cw, bv_cw) = $A.freeze<byte>(cwa)
      val () = copy_to_builder_v(bv, 0, a0, 4096, cb)
      val () = put_char_v(cb, 0)
      val off_dir = g1ofg0(bytes_in(cb))
      val () = put_absolute(bv, o.dir_s, o.dir_e, bv_cw, cwn, cb)
      val () = put_char_v(cb, 0)
      val off_work = g1ofg0(bytes_in(cb))
      val @(fz_ma, bv_ma) = $A.freeze<byte>(ma)
      val () = (if o.work_s >= 0 then put_absolute(bv, o.work_s, o.work_e, bv_cw, cwn, cb)
        else copy_to_builder_v(bv_ma, 0, made_len, 524288, cb))
      val () = $A.drop<byte>(fz_ma, bv_ma)
      val () = $A.free<byte>($A.thaw<byte>(fz_ma))
      val () = put_char_v(cb, 0)
      val off_repo = g1ofg0(bytes_in(cb))
      val has_repo = (o.repo_s >= 0): bool
      val () = (if has_repo then copy_to_builder_v(bv, o.repo_s, o.repo_e, 4096, cb) else ())
      val () = put_char_v(cb, 0)
      val off_memo = g1ofg0(bytes_in(cb))
      val has_memo = (o.memo_s >= 0): bool
      val () = (if has_memo then put_absolute(bv, o.memo_s, o.memo_e, bv_cw, cwn, cb) else ())
      val () = put_char_v(cb, 0)
      val () = $A.drop<byte>(fz_cw, bv_cw)
      val () = $A.free<byte>($A.thaw<byte>(fz_cw))
      val w = @{program= 0, directory= off_dir, work= off_work, repository= (if has_repo then off_repo else ~1),
        memo= off_memo, cold= o.cold, prune= o.prune}: settings
      val @(ca, _) = $B.to_arr(cb)
      val @(fz_c, bv_c) = $A.freeze<byte>(ca)
      val () = (if a1e + 1 <= t then fixtures_with(bv_c, w, bv, t, a1e + 1) else fixtures_with(bv_c, w, bv, t, t))
      (* a temporary directory goes; a --work one is kept *)
      val () = (if o.work_s < 0 then let
          var rm : $B.builder_v = $B.create()
          val () = put_cfg(bv_c, off_work, rm)
          val _ = run_sh("rm -rf \"$1\"", $L.list_vt_cons(mk_arg(rm), $L.list_vt_nil()))
        in () end else ())
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = $A.free<byte>($A.thaw<byte>(fz_c))
    in end
  end
end

(* Whether argv[1] is fixtures *)
fn names_fixtures {l:agz}{t:nat | t <= 4096} (bv: !$A.borrow(byte, l, 4096), t: int t): bool = let
  val a0 = word_stop(bv, t, 0)
in
  if a0 + 1 >= t then false
  else arg_is(bv, a0 + 1, word_stop(bv, t, a0 + 1), "fixtures")
end

(* Runs bats fixtures when that is the command given and answers true;
   false for any other command, which is left to the caller *)
#pub fn fixtures_main (): bool

implement fixtures_main () = let
  val buf = $A.alloc<byte>(4096)
  val read = $E.args_read(buf, 4096)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val handled = (case+ read of
    | ~$R.none() => false
    | ~$R.some(total) =>
        if total > 4096 then false
        else if total >= 4096 then false
        else if names_fixtures(bv, total) then let val () = fixtures_run(bv, total) in true end
        else false): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
