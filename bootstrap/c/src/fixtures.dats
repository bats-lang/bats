staload "./fixtures.sats"
staload "arith/src/lib.dats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* fixtures -- bats fixtures <dir> [--only <member>]... [--cold] [--work <dir>]
   [--repository <dir>] (bats-lang/bats#267, item 4: quire's static-test
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
   those. --cold is accepted and changes nothing: nothing is remembered
   between runs yet, so every run is cold. The exit status is 1 when
   anything failed, 2 for a usage error. *)

#include "share/atspre_staload.hats"

staload AR = "arith/src/lib.sats"
staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"

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

(* The memo's script (put_memo_script, below) is run as
   `sh <work>/memo.sh <verb> ...`; its verbs return their statuses to this
   side: probe 98 when the snippet could not be put in, 100 when the check
   must be run, 0 and 1 for a memo hit (the check passed, or failed with the
   log it left in <work>/check.log); store and prune 0 *)

(* Puts the snippet of the fixture mv[a, e) into <work>/app's copy of the
   module bv_m[0, mlen), before line `at` and followed by one blank line,
   and looks the fixture up in the memo (the script's probe). The system
   does the splice and the lookup (head, awk, tail, sha256sum, sed); which
   line, and what the output means, are decided here. *)
fn memo_probe {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_m: !$A.borrow(byte, lx, 524288), mlen: xi, at: int, is_accept: bool): int = let
  var work : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, work)
  var module : $B.builder_v = $B.create()
  val () = put_range(bv_m, 524288, 0, mlen, module)
  var kind : $B.builder_v = $B.create()
  val () = (if is_accept then bput_v(kind, "accept") else bput_v(kind, "reject"))
  val snippet = fixture_text(cfg, w, mv, a, e, "snippet.bats")
  val before = fixture_text(cfg, w, mv, a, e, "before")
  var line : $B.builder_v = $B.create()
  val () = put_int_v(line, at)
  var memo : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.memo, memo)
  var cold : $B.builder_v = $B.create()
  val () = put_int_v(cold, w.cold)
in
  run_sh("sh \"$1/memo.sh\" probe \"$@\"",
    $L.list_vt_cons(mk_arg(work), $L.list_vt_cons(mk_arg(module), $L.list_vt_cons(mk_arg(kind),
    $L.list_vt_cons(mk_arg(snippet), $L.list_vt_cons(mk_arg(before), $L.list_vt_cons(mk_arg(line),
    $L.list_vt_cons(mk_arg(memo), $L.list_vt_cons(mk_arg(cold), $L.list_vt_nil())))))))))
end

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

(* Keeps the result of the check just run in the memo, and audits the memo
   in a cold run (the script's store) *)
fn memo_store {l:agz}{lm:agz}{lx:agz}{a,e:nat | a <= e; e <= 524288}
  (cfg: !$A.borrow(byte, l, 524288), w: settings, mv: !$A.borrow(byte, lm, 524288), a: int a, e: int e,
   bv_m: !$A.borrow(byte, lx, 524288), mlen: xi, is_accept: bool, status: int): int = let
  var work : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, work)
  var module : $B.builder_v = $B.create()
  val () = put_range(bv_m, 524288, 0, mlen, module)
  var kind : $B.builder_v = $B.create()
  val () = (if is_accept then bput_v(kind, "accept") else bput_v(kind, "reject"))
  var st : $B.builder_v = $B.create()
  val () = put_int_v(st, status)
  val snippet = fixture_text(cfg, w, mv, a, e, "snippet.bats")
  var cold : $B.builder_v = $B.create()
  val () = put_int_v(cold, w.cold)
in
  run_sh("sh \"$1/memo.sh\" store \"$@\"",
    $L.list_vt_cons(mk_arg(work), $L.list_vt_cons(mk_arg(module), $L.list_vt_cons(mk_arg(kind),
    $L.list_vt_cons(mk_arg(st), $L.list_vt_cons(mk_arg(snippet), $L.list_vt_cons(mk_arg(cold), $L.list_vt_nil())))))))
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
      val probed = memo_probe(cfg, w, mv, a, e, bv_f, mlen, at, is_accept)
      val hit = (probed = 0 || probed = 1): bool
      val rc = (if hit then probed
        else if probed = 100 then let
          val ran = run_check(cfg, w)
          val _ = memo_store(cfg, w, mv, a, e, bv_f, mlen, is_accept, ran)
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

(* BEGIN fixtures-memo.sh *)
fn put_memo_script (out: !$B.builder_v >> $B.builder_v): void = let
  val () = bput_v(out, "#!/bin/sh\n")
  val () = bput_v(out, "# The memo of bats fixtures (bats-lang/bats#267, item 4b), run by it as\n")
  val () = bput_v(out, "#   sh memo.sh probe <work> <module> <kind> <snippet> <before> <at> <memo> <cold>\n")
  val () = bput_v(out, "#   sh memo.sh store <work> <module> <kind> <status> <snippet> <cold>\n")
  val () = bput_v(out, "#   sh memo.sh prune <work> <memo>\n")
  val () = bput_v(out, "# No time is read anywhere in it: an entry is trusted when the digests of the\n")
  val () = bput_v(out, "# files it names, and a checksum of its own bytes, are those it holds.\n")
  val () = bput_v(out, "LC_ALL=C\n")
  val () = bput_v(out, "export LC_ALL\n")
  val () = bput_v(out, "if command -v sha256sum >/dev/null 2>&1; then\n")
  val () = bput_v(out, "  digest() { sha256sum | cut -d' ' -f1; }\n")
  val () = bput_v(out, "else\n")
  val () = bput_v(out, "  digest() { shasum -a 256 | cut -d' ' -f1; }\n")
  val () = bput_v(out, "fi\n")
  val () = bput_v(out, "# A file as the memo knows it: a .sats by its interface (its text with each\n")
  val () = bput_v(out, "# run of line feeds as one, as bats's own check memo takes it), unless it\n")
  val () = bput_v(out, "# holds a quote or a percent sign (a string, a char, C code: a line feed\n")
  val () = bput_v(out, "# may be part of what it says), then as it is. A file that is not there is\n")
  val () = bput_v(out, "# MISSING.\n")
  val () = bput_v(out, "file_digest() {\n")
  val () = bput_v(out, "  if [ ! -f \"$1\" ]; then echo MISSING; return 0; fi\n")
  val () = bput_v(out, "  case $1 in\n")
  val () = bput_v(out, "    *.sats)\n")
  val () = bput_v(out, "      if grep -q \"[\\\"'%]\" \"$1\"; then echo \"R $(digest < \"$1\")\"\n")
  val () = bput_v(out, "      else echo \"C $(tr -s '\\n' < \"$1\" | digest)\"; fi ;;\n")
  val () = bput_v(out, "    *) echo \"R $(digest < \"$1\")\" ;;\n")
  val () = bput_v(out, "  esac\n")
  val () = bput_v(out, "}\n")
  val () = bput_v(out, "# The names patsopt might have read instead of a file it did read: the\n")
  val () = bput_v(out, "# .sats and .hats of build/ (not the stashes' nor the digests' kept there),\n")
  val () = bput_v(out, "# and the .bats of src and bats_modules (which bats checks the whole of\n")
  val () = bput_v(out, "# before patsopt runs)\n")
  val () = bput_v(out, "names_of() {\n")
  val () = bput_v(out, "  (cd \"$1\" && {\n")
  val () = bput_v(out, "    find build \\( -path build/.stash -o -path build/.bats_dg \\) -prune -o -type f \\( -name '*.sats' -o -name '*.hats' \\) -print\n")
  val () = bput_v(out, "    find src bats_modules -type f -name '*.bats' -print 2>/dev/null\n")
  val () = bput_v(out, "  } | sort | digest)\n")
  val () = bput_v(out, "}\n")
  val () = bput_v(out, "# --memo, else BATS_MEMO_DIR, else the user's cache; empty when there is none\n")
  val () = bput_v(out, "memo_dir() {\n")
  val () = bput_v(out, "  if [ -n \"$1\" ]; then echo \"$1\"\n")
  val () = bput_v(out, "  elif [ -n \"${BATS_MEMO_DIR:-}\" ]; then echo \"$BATS_MEMO_DIR\"\n")
  val () = bput_v(out, "  elif [ -n \"${XDG_CACHE_HOME:-}\" ]; then echo \"$XDG_CACHE_HOME/bats/fixtures\"\n")
  val () = bput_v(out, "  elif [ -n \"${HOME:-}\" ]; then echo \"$HOME/.cache/bats/fixtures\"\n")
  val () = bput_v(out, "  fi\n")
  val () = bput_v(out, "}\n")
  val () = bput_v(out, "# A log as it is kept: the work directory's path as /app/, the line a\n")
  val () = bput_v(out, "# waiting bats says dropped, a line feed at the end\n")
  val () = bput_v(out, "normalize() {\n")
  val () = bput_v(out, "  PHYS=$(cd \"$1\" && pwd -P) LOGI=$(cd \"$1\" && pwd) awk '\n")
  val () = bput_v(out, "    BEGIN { n = 0; v[n++] = ENVIRON[\"PHYS\"] \"/\"; if (ENVIRON[\"LOGI\"] != ENVIRON[\"PHYS\"]) v[n++] = ENVIRON[\"LOGI\"] \"/\" }\n")
  val () = bput_v(out, "    /^waiting for another bats/ { next }\n")
  val () = bput_v(out, "    /^warning: the ATS2 in / { next }\n")
  val () = bput_v(out, "    { s = $0; for (k = 0; k < n; k++) { out = \"\"; while ((i = index(s, v[k])) > 0) { out = out substr(s, 1, i - 1) \"/app/\"; s = substr(s, i + length(v[k])) } s = out s }\n")
  val () = bput_v(out, "      print s }'\n")
  val () = bput_v(out, "}\n")
  val () = bput_v(out, "cold_wanted() {\n")
  val () = bput_v(out, "  if [ \"$1\" = 1 ]; then echo 1\n")
  val () = bput_v(out, "  elif [ -n \"${BATS_COLD:-}\" ] && [ \"${BATS_COLD}\" != 0 ]; then echo 1\n")
  val () = bput_v(out, "  else echo 0; fi\n")
  val () = bput_v(out, "}\n")
  val () = bput_v(out, "# Whether the entry $1 is whole and is the one for key $2 and names $3 of\n")
  val () = bput_v(out, "# kind $4 whose files, under directory $5, are as it says. It sets res (pass\n")
  val () = bput_v(out, "# or log), cnt (its files) and loglines.\n")
  val () = bput_v(out, "entry_ok() {\n")
  val () = bput_v(out, "  e=$1\n")
  val () = bput_v(out, "  [ -f \"$e\" ] && [ ! -L \"$e\" ] || return 1\n")
  val () = bput_v(out, "  total=$(wc -l < \"$e\" | tr -d ' ')\n")
  val () = bput_v(out, "  case $total in ''|*[!0-9]*) return 1 ;; esac\n")
  val () = bput_v(out, "  [ \"$total\" -ge 16 ] || return 1\n")
  val () = bput_v(out, "  last=$(tail -n 1 \"$e\")\n")
  val () = bput_v(out, "  [ \"${last%% *}\" = sum ] || return 1\n")
  val () = bput_v(out, "  [ \"$(sed '$d' \"$e\" | digest)\" = \"${last#sum }\" ] || return 1\n")
  val () = bput_v(out, "  [ \"$(sed -n 1p \"$e\")\" = 'bats-fixture-memo 1' ] || return 1\n")
  val () = bput_v(out, "  [ \"$(sed -n 2p \"$e\")\" = \"key $2\" ] || return 1\n")
  val () = bput_v(out, "  res=$(sed -n 3p \"$e\"); res=${res#result }\n")
  val () = bput_v(out, "  case \"$4:$res\" in accept:pass|reject:log) ;; *) return 1 ;; esac\n")
  val () = bput_v(out, "  [ \"$(sed -n 4p \"$e\")\" = \"names $3\" ] || return 1\n")
  val () = bput_v(out, "  cnt=$(sed -n 5p \"$e\"); cnt=${cnt#files }\n")
  val () = bput_v(out, "  case $cnt in ''|*[!0-9]*) return 1 ;; esac\n")
  val () = bput_v(out, "  loglines=$(sed -n \"$((6 + cnt))p\" \"$e\"); loglines=${loglines#log }\n")
  val () = bput_v(out, "  case $loglines in ''|*[!0-9]*) return 1 ;; esac\n")
  val () = bput_v(out, "  [ \"$total\" -eq $((cnt + loglines + 16)) ] || return 1\n")
  val () = bput_v(out, "  if [ \"$cnt\" -gt 0 ]; then sed -n \"6,$((5 + cnt))p\" \"$e\"; fi > \"$work/memo.list\"\n")
  val () = bput_v(out, "  while IFS= read -r l; do\n")
  val () = bput_v(out, "    shape=${l%% *}; r=${l#* }; hex=${r%% *}; p=${r#* }\n")
  val () = bput_v(out, "    [ \"$(file_digest \"$5/$p\")\" = \"$shape $hex\" ] || return 1\n")
  val () = bput_v(out, "  done < \"$work/memo.list\"\n")
  val () = bput_v(out, "  return 0\n")
  val () = bput_v(out, "}\n")
  val () = bput_v(out, "# The paths a bats-memo key lists (its lines from the third to its rule)\n")
  val () = bput_v(out, "key_paths() { sed -n '3,$p' \"$1\" | sed '/^--$/,$d'; }\n")
  val () = bput_v(out, "\n")
  val () = bput_v(out, "verb=$1; shift\n")
  val () = bput_v(out, "case $verb in\n")
  val () = bput_v(out, "\n")
  val () = bput_v(out, "probe)\n")
  val () = bput_v(out, "  work=$1; module=$2; kind=$3; snippet=$4; before=$5; at=$6; memo_arg=$7; cold_arg=$8\n")
  val () = bput_v(out, "  app=$work/app; f=$app/$module\n")
  val () = bput_v(out, "  rm -f \"$work/check.log\" \"$work/check.seconds\" \"$work/check.memo\" \"$work/check.stale\" \"$work/memo.key\" \"$work/memo.prior\"\n")
  val () = bput_v(out, "  { head -n $((at - 1)) \"$f\"; awk 1 \"$snippet\"; echo; tail -n +\"$at\" \"$f\"; } > \"$f.fixture\" || exit 98\n")
  val () = bput_v(out, "  mv -f \"$f.fixture\" \"$f\" || exit 98\n")
  val () = bput_v(out, "  memo=$(memo_dir \"$memo_arg\")\n")
  val () = bput_v(out, "  [ -n \"$memo\" ] || exit 100\n")
  val () = bput_v(out, "  case $memo in /*) ;; *) memo=$PWD/$memo ;; esac\n")
  val () = bput_v(out, "  [ -f \"$app/build/.bats_stamp\" ] || exit 100\n")
  val () = bput_v(out, "  toml=none; [ -f \"$app/bats.toml\" ] && toml=$(digest < \"$app/bats.toml\")\n")
  val () = bput_v(out, "  lock=none; [ -f \"$app/bats.lock\" ] && lock=$(digest < \"$app/bats.lock\")\n")
  val () = bput_v(out, "  text=$(printf 'bats-fixture-key 1\\nmodule %s\\nbefore %s\\nsnippet %s\\nspliced %s\\ntoml %s\\nlock %s\\nstamp %s\\n' \\\n")
  val () = bput_v(out, "    \"$module\" \"$(digest < \"$before\")\" \"$(digest < \"$snippet\")\" \"$(digest < \"$f\")\" \"$toml\" \"$lock\" \\\n")
  val () = bput_v(out, "    \"$(digest < \"$app/build/.bats_stamp\")\")\n")
  val () = bput_v(out, "  key=$(printf '%s\\n' \"$text\" | digest)\n")
  val () = bput_v(out, "  names=$(names_of \"$app\")\n")
  val () = bput_v(out, "  printf '%s\\n' \"$key\" > \"$work/memo.key\"\n")
  val () = bput_v(out, "  printf '%s\\n' \"$text\" > \"$work/memo.text\"\n")
  val () = bput_v(out, "  printf '%s\\n' \"$names\" > \"$work/memo.names\"\n")
  val () = bput_v(out, "  printf '%s\\n' \"$memo\" > \"$work/memo.dir\"\n")
  val () = bput_v(out, "  echo \"$key\" >> \"$work/memo-used\"\n")
  val () = bput_v(out, "  entry=$memo/$(printf '%s' \"$key\" | cut -c1-2)/$key\n")
  val () = bput_v(out, "  if [ -f \"$memo/.bats-fixtures-memo\" ] && entry_ok \"$entry\" \"$key\" \"$names\" \"$kind\" \"$app\"; then\n")
  val () = bput_v(out, "    if [ \"$(cold_wanted \"$cold_arg\")\" = 1 ]; then echo \"$entry\" > \"$work/memo.prior\"; exit 100; fi\n")
  val () = bput_v(out, "    if [ \"$res\" = pass ]; then : > \"$work/check.log\"; status=0\n")
  val () = bput_v(out, "    else sed -n \"$((7 + cnt)),$((6 + cnt + loglines))p\" \"$entry\" > \"$work/check.log\"; status=1; fi\n")
  val () = bput_v(out, "    echo 0 > \"$work/check.seconds\"\n")
  val () = bput_v(out, "    echo hit > \"$work/check.memo\"\n")
  val () = bput_v(out, "    exit $status\n")
  val () = bput_v(out, "  fi\n")
  val () = bput_v(out, "  exit 100\n")
  val () = bput_v(out, "  ;;\n")
  val () = bput_v(out, "\n")
  val () = bput_v(out, "store)\n")
  val () = bput_v(out, "  work=$1; module=$2; kind=$3; status=$4; snippet=$5; cold_arg=$6\n")
  val () = bput_v(out, "  [ -f \"$work/memo.key\" ] || exit 0\n")
  val () = bput_v(out, "  key=$(cat \"$work/memo.key\"); names=$(cat \"$work/memo.names\"); memo=$(cat \"$work/memo.dir\")\n")
  val () = bput_v(out, "  app=$work/app; base=$work/build-checked; log=$work/check.log\n")
  val () = bput_v(out, "  entry=$memo/$(printf '%s' \"$key\" | cut -c1-2)/$key\n")
  val () = bput_v(out, "  # what is to be kept: an accept that passed, or a reject that failed the\n")
  val () = bput_v(out, "  # ordinary way (a patsopt error in a log of at most 524288 bytes); never a\n")
  val () = bput_v(out, "  # failure of an accept, a reject that passed, a status 124 or 125 (a cap),\n")
  val () = bput_v(out, "  # a signal, or a check that failed with no error of patsopt's\n")
  val () = bput_v(out, "  want=none\n")
  val () = bput_v(out, "  case \"$kind:$status\" in\n")
  val () = bput_v(out, "    accept:0) want=pass ;;\n")
  val () = bput_v(out, "    reject:1)\n")
  val () = bput_v(out, "      if [ -f \"$log\" ] && grep -aq '): error([0-9][0-9]*): ' \"$log\"; then\n")
  val () = bput_v(out, "        normalize \"$app\" < \"$log\" > \"$work/memo.log\"\n")
  val () = bput_v(out, "        if [ \"$(wc -c < \"$work/memo.log\" | tr -d ' ')\" -le 524288 ]; then want=log; fi\n")
  val () = bput_v(out, "      fi ;;\n")
  val () = bput_v(out, "  esac\n")
  val () = bput_v(out, "  # a cold run audits the memo that would have been served\n")
  val () = bput_v(out, "  if [ -f \"$work/memo.prior\" ]; then\n")
  val () = bput_v(out, "    prior=$(cat \"$work/memo.prior\")\n")
  val () = bput_v(out, "    pres=$(sed -n 3p \"$prior\"); pres=${pres#result }\n")
  val () = bput_v(out, "    pcnt=$(sed -n 5p \"$prior\"); pcnt=${pcnt#files }\n")
  val () = bput_v(out, "    plines=$(sed -n \"$((6 + pcnt))p\" \"$prior\"); plines=${plines#log }\n")
  val () = bput_v(out, "    stale=\n")
  val () = bput_v(out, "    if [ \"$pres\" = pass ]; then\n")
  val () = bput_v(out, "      [ \"$want\" = pass ] || stale=\"the memo says the check passes, the cold run's status is $status\"\n")
  val () = bput_v(out, "    else\n")
  val () = bput_v(out, "      if [ \"$want\" != log ]; then stale=\"the memo holds the log of a check that fails, the cold run's status is $status\"\n")
  val () = bput_v(out, "      else\n")
  val () = bput_v(out, "        sed -n \"$((7 + pcnt)),$((6 + pcnt + plines))p\" \"$prior\" > \"$work/memo.prior.log\"\n")
  val () = bput_v(out, "        cmp -s \"$work/memo.prior.log\" \"$work/memo.log\" || stale=\"the log the memo holds is not the cold run's\"\n")
  val () = bput_v(out, "      fi\n")
  val () = bput_v(out, "    fi\n")
  val () = bput_v(out, "    # a memo that lied is removed, so it is not served again\n")
  val () = bput_v(out, "    if [ -n \"$stale\" ]; then\n")
  val () = bput_v(out, "      printf 'STALE MEMO: %s (key %s)\\n' \"$stale\" \"$key\" > \"$work/check.stale\"\n")
  val () = bput_v(out, "      rm -f \"$prior\"\n")
  val () = bput_v(out, "    fi\n")
  val () = bput_v(out, "  fi\n")
  val () = bput_v(out, "  [ \"$want\" != none ] || exit 0\n")
  val () = bput_v(out, "  # a snippet that loads a file (staload, include, #use) reads one the base\n")
  val () = bput_v(out, "  # module's closure does not name: not kept\n")
  val () = bput_v(out, "  if grep -Eq 'load|include|#use|#require' \"$snippet\"; then exit 0; fi\n")
  val () = bput_v(out, "  own=build/${module%.bats}\n")
  val () = bput_v(out, "  basekey=$base/${module%.bats}_dats.c.key\n")
  val () = bput_v(out, "  [ -f \"$basekey\" ] || exit 0\n")
  val () = bput_v(out, "  key_paths \"$basekey\" > \"$work/memo.paths\"\n")
  val () = bput_v(out, "  # the interface of the module with the snippet in, against the base's: if\n")
  val () = bput_v(out, "  # it changed, the modules that read it are in the entry too\n")
  val () = bput_v(out, "  if [ \"$(file_digest \"$app/${own}.sats\")\" != \"$(file_digest \"$base/${own#build/}.sats\")\" ]; then\n")
  val () = bput_v(out, "    wc_dats=$(find \"$base\" -path \"$base/.stash\" -prune -o -name '*.dats' -print | wc -l | tr -d ' ')\n")
  val () = bput_v(out, "    wc_keys=$(find \"$base\" -path \"$base/.stash\" -prune -o -name '*_dats.c.key' -print | wc -l | tr -d ' ')\n")
  val () = bput_v(out, "    [ \"$wc_dats\" = \"$wc_keys\" ] || exit 0\n")
  val () = bput_v(out, "    find \"$base\" -path \"$base/.stash\" -prune -o -name '*_dats.c.key' -print | while IFS= read -r k; do\n")
  val () = bput_v(out, "      if grep -qxF \"${own}.sats\" \"$k\"; then key_paths \"$k\"; fi\n")
  val () = bput_v(out, "    done >> \"$work/memo.paths\"\n")
  val () = bput_v(out, "  fi\n")
  val () = bput_v(out, "  # the module's own .dats and .sats are those with the snippet in: the\n")
  val () = bput_v(out, "  # spliced source stands for them in the key\n")
  val () = bput_v(out, "  sort -u \"$work/memo.paths\" | grep -vxF -e \"${own}.dats\" -e \"${own}.sats\" > \"$work/memo.paths.sorted\"\n")
  val () = bput_v(out, "  : > \"$work/memo.files\"\n")
  val () = bput_v(out, "  while IFS= read -r p; do\n")
  val () = bput_v(out, "    case $p in build/*) ;; *) exit 0 ;; esac\n")
  val () = bput_v(out, "    d=$(file_digest \"$base/${p#build/}\")\n")
  val () = bput_v(out, "    case $d in MISSING) exit 0 ;; esac\n")
  val () = bput_v(out, "    printf '%s %s\\n' \"$d\" \"$p\" >> \"$work/memo.files\"\n")
  val () = bput_v(out, "  done < \"$work/memo.paths.sorted\"\n")
  val () = bput_v(out, "  nfiles=$(wc -l < \"$work/memo.files\" | tr -d ' ')\n")
  val () = bput_v(out, "  if [ \"$want\" = log ]; then nlog=$(wc -l < \"$work/memo.log\" | tr -d ' '); else nlog=0; : > \"$work/memo.log\"; fi\n")
  val () = bput_v(out, "  # a directory is a memo when it is marked or empty: another is not written\n")
  val () = bput_v(out, "  # to (a path given by mistake is not filled with entries, nor pruned)\n")
  val () = bput_v(out, "  mkdir -p \"$memo\" || exit 0\n")
  val () = bput_v(out, "  if [ ! -f \"$memo/.bats-fixtures-memo\" ]; then\n")
  val () = bput_v(out, "    [ -z \"$(ls -A \"$memo\")\" ] || exit 0\n")
  val () = bput_v(out, "    echo 'bats-fixture-memo 1' > \"$memo/.bats-fixtures-memo\" || exit 0\n")
  val () = bput_v(out, "  fi\n")
  val () = bput_v(out, "  dir=$(dirname \"$entry\")\n")
  val () = bput_v(out, "  mkdir -p \"$dir\" || exit 0\n")
  val () = bput_v(out, "  tmp=$dir/.tmp.$key.$$\n")
  val () = bput_v(out, "  {\n")
  val () = bput_v(out, "    printf 'bats-fixture-memo 1\\nkey %s\\nresult %s\\nnames %s\\nfiles %s\\n' \"$key\" \"$want\" \"$names\" \"$nfiles\"\n")
  val () = bput_v(out, "    cat \"$work/memo.files\"\n")
  val () = bput_v(out, "    printf 'log %s\\n' \"$nlog\"\n")
  val () = bput_v(out, "    cat \"$work/memo.log\"\n")
  val () = bput_v(out, "    printf 'text 8\\n'\n")
  val () = bput_v(out, "    cat \"$work/memo.text\"\n")
  val () = bput_v(out, "  } > \"$tmp.body\" || { rm -f \"$tmp.body\"; exit 0; }\n")
  val () = bput_v(out, "  { cat \"$tmp.body\"; printf 'sum %s\\n' \"$(digest < \"$tmp.body\")\"; } > \"$tmp\" && mv -f \"$tmp\" \"$entry\"\n")
  val () = bput_v(out, "  rm -f \"$tmp.body\" \"$tmp\"\n")
  val () = bput_v(out, "  exit 0\n")
  val () = bput_v(out, "  ;;\n")
  val () = bput_v(out, "\n")
  val () = bput_v(out, "prune)\n")
  val () = bput_v(out, "  work=$1; memo=$(memo_dir \"$2\")\n")
  val () = bput_v(out, "  case $memo in /*) ;; *) memo=$PWD/$memo ;; esac\n")
  val () = bput_v(out, "  if [ ! -d \"$memo\" ] || [ -L \"$memo\" ] || [ ! -f \"$memo/.bats-fixtures-memo\" ]; then\n")
  val () = bput_v(out, "    echo \"memo: nothing pruned, $memo is not a fixtures memo\"\n")
  val () = bput_v(out, "    exit 0\n")
  val () = bput_v(out, "  fi\n")
  val () = bput_v(out, "  kept=0; removed=0\n")
  val () = bput_v(out, "  find \"$memo\" -mindepth 1 -maxdepth 1 -type d -name '[0-9a-f][0-9a-f]' > \"$work/memo.dirs\"\n")
  val () = bput_v(out, "  while IFS= read -r d; do\n")
  val () = bput_v(out, "    find \"$d\" -mindepth 1 -maxdepth 1 -type f > \"$work/memo.entries\"\n")
  val () = bput_v(out, "    while IFS= read -r p; do\n")
  val () = bput_v(out, "      name=${p##*/}\n")
  val () = bput_v(out, "      case $name in\n")
  val () = bput_v(out, "        .tmp.*.*)\n")
  val () = bput_v(out, "          pid=${name##*.}\n")
  val () = bput_v(out, "          if kill -0 \"$pid\" 2>/dev/null; then kept=$((kept + 1)); continue; fi ;;\n")
  val () = bput_v(out, "        *[!0-9a-f]*) continue ;;\n")
  val () = bput_v(out, "        *)\n")
  val () = bput_v(out, "          [ ${#name} -eq 64 ] || continue\n")
  val () = bput_v(out, "          if grep -qxF \"$name\" \"$work/memo-used\" 2>/dev/null; then kept=$((kept + 1)); continue; fi ;;\n")
  val () = bput_v(out, "      esac\n")
  val () = bput_v(out, "      rm -f \"$p\" && { echo \"pruned ${p#\"$memo\"/}\"; removed=$((removed + 1)); }\n")
  val () = bput_v(out, "    done < \"$work/memo.entries\"\n")
  val () = bput_v(out, "  done < \"$work/memo.dirs\"\n")
  val () = bput_v(out, "  echo \"memo: pruned $removed entries, kept $kept\"\n")
  val () = bput_v(out, "  exit 0\n")
  val () = bput_v(out, "  ;;\n")
  val () = bput_v(out, "\n")
  val () = bput_v(out, "esac\n")
  val () = bput_v(out, "exit 2\n")
in end
(* END fixtures-memo.sh *)

(* <work>/memo.sh written: the script the memo's verbs are *)
fn write_memo_script {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): void = let
  var work : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, work)
  var script : $B.builder_v = $B.create()
  val () = put_memo_script(script)
  val _ = run_sh("rm -f \"$1/memo-used\"; printf '%s' \"$2\" > \"$1/memo.sh\"",
    $L.list_vt_cons(mk_arg(work), $L.list_vt_cons(mk_arg(script), $L.list_vt_nil())))
in end

(* Removes from the memo the entries no fixture of this run used (the
   script's prune, whose lines say what it removes, are printed from the
   file they were written to: bats runs what it starts with its output
   discarded) *)
fn memo_prune {l:agz} (cfg: !$A.borrow(byte, l, 524288), w: settings): void = let
  var work : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.work, work)
  var memo : $B.builder_v = $B.create()
  val () = put_cfg(cfg, w.memo, memo)
  val _ = run_sh("sh \"$1/memo.sh\" prune \"$1\" \"$2\" > \"$1/prune.out\" 2>&1",
    $L.list_vt_cons(mk_arg(work), $L.list_vt_cons(mk_arg(memo), $L.list_vt_nil())))
in print_text_there(cfg, w, "prune.out") end

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
        val () = write_memo_script(cfg, w)
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
      val () = copy_to_builder_v(bv, 0, a0, 4096, cb)
      val () = put_char_v(cb, 0)
      val off_dir = g1ofg0(bytes_in(cb))
      val () = copy_to_builder_v(bv, o.dir_s, o.dir_e, 4096, cb)
      val () = put_char_v(cb, 0)
      val off_work = g1ofg0(bytes_in(cb))
      val @(fz_ma, bv_ma) = $A.freeze<byte>(ma)
      val () = (if o.work_s >= 0 then copy_to_builder_v(bv, o.work_s, o.work_e, 4096, cb)
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
      val () = (if has_memo then copy_to_builder_v(bv, o.memo_s, o.memo_e, 4096, cb) else ())
      val () = put_char_v(cb, 0)
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
