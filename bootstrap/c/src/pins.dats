staload "./pins.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* pins -- bats check-pins <file>...: the inputs of CI that move under a passing commit (bats-lang/bats#390) *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"

(* The byte at p of bv[0, n) *)
fn read_byte {l:agz}{n:pos}{p:nat | p < n}
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n): int =
  byte2int0($A.read<byte>(bv, p))

(* The byte at p of bv[0, b), or 0 at and past b *)
fn byte_in {l:agz}{n:pos}{p,b:nat | b <= n}
  (bv: !$A.borrow(byte, l, n), p: int p, b: int b, n: int n): int =
  if p >= b then 0 else read_byte(bv, p, n)

(* Space, tab or carriage return *)
fn is_blank (c: int): bool = c = 32 || c = 9 || c = 13

(* The first position of bv[p, e) that is no blank, or e *)
fun skip_blank {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n)
  : [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_blank(read_byte(bv, p, n)) then skip_blank(bv, p + 1, e, n)
  else p

(* q less the blanks that end bv[lo, q) *)
fun trim_end {l:agz}{n:pos}{lo,q:nat | lo <= q; q <= n} .<q - lo>.
  (bv: !$A.borrow(byte, l, n), lo: int lo, q: int q, n: int n)
  : [r:nat | lo <= r; r <= q] int r =
  if q <= lo then q
  else if is_blank(read_byte(bv, q - 1, n)) then trim_end(bv, lo, q - 1, n)
  else q

(* The end of the line at p *)
fun line_end {l:agz}{n:pos}{p,nb:nat | p <= nb; nb <= n} .<nb - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, nb: int nb, n: int n)
  : [q:nat | p <= q; q <= nb] int q =
  if p >= nb then p
  else if read_byte(bv, p, n) = 10 then p
  else line_end(bv, p + 1, nb, n)

(* The first # of bv[p, e) that starts the span or follows a blank, or e *)
fun find_comment {l:agz}{n:pos}{start,p,e:nat | start <= p; p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), start: int start, p: int p, e: int e, n: int n)
  : [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if read_byte(bv, p, n) <> 35 then find_comment(bv, start, p + 1, e, n)
  else if p = start then p
  else if is_blank(read_byte(bv, p - 1, n)) then p
  else find_comment(bv, start, p + 1, e, n)

(* Whether bv[p, e) holds a byte that is no blank *)
fn has_text {l:agz}{n:pos}{p,e:nat | p <= e; e <= n}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): bool =
  skip_blank(bv, p, e, n) < e

(* Whether c is a letter, a digit, an underscore, a dot or a hyphen; slash also when slash *)
fn is_name_byte (c: int, slash: bool): bool =
  (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
  || c = 95 || c = 46 || c = 45 || (slash && c = 47)

(* The end of the run of name bytes of bv[p, e) *)
fun name_run {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n, slash: bool)
  : [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_name_byte(read_byte(bv, p, n), slash) then name_run(bv, p + 1, e, n, slash)
  else p

(* Whether bv[p, e) is lowercase hex digits only *)
fun all_hex {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): bool =
  if p >= e then true
  else let
    val c = read_byte(bv, p, n)
  in
    if (c >= 48 && c <= 57) || (c >= 97 && c <= 102) then all_hex(bv, p + 1, e, n)
    else false
  end

(* Whether bv[a, b) is owner/repository[/path]@ and 40 lowercase hex digits *)
fn is_pinned {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): bool = let
  val owner_end = name_run(bv, a, b, n, false)
in
  if owner_end <= a then false
  else if owner_end + 1 > b then false
  else if byte_in(bv, owner_end, b, n) <> 47 then false
  else let
    val repository_end = name_run(bv, owner_end + 1, b, n, true)
  in
    if repository_end <= owner_end + 1 then false
    else if byte_in(bv, repository_end, b, n) <> 64 then false
    else if b - (repository_end + 1) <> 40 then false
    else all_hex(bv, repository_end + 1, b, n)
  end
end

(* Whether bv[a, b) starts with ./ *)
fn is_local {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): bool =
  byte_in(bv, a, b, n) = 46 && byte_in(bv, a + 1, b, n) = 47

(* The position after uses: when it starts bv[s, le), else ~1 *)
fn uses_key {l:agz}{n:pos}{s,le:nat | s <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), s: int s, le: int le, n: int n)
  : [r:int | r == ~1 || (s <= r && r <= le)] int r =
  if s + 5 > le then ~1
  else if read_byte(bv, s, n) = 117 && read_byte(bv, s + 1, n) = 115
    && read_byte(bv, s + 2, n) = 101 && read_byte(bv, s + 3, n) = 115
    && read_byte(bv, s + 4, n) = 58 then s + 5
  else ~1

(* The position after the uses: key of the line bv[ls, le), a step's - uses: too, else ~1 *)
fn uses_value {l:agz}{n:pos}{ls,le:nat | ls <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, le: int le, n: int n)
  : [r:int | r == ~1 || (ls <= r && r <= le)] int r = let
  val s0 = skip_blank(bv, ls, le, n)
in
  if s0 >= le then ~1
  else if read_byte(bv, s0, n) = 45 then
    (if s0 + 1 >= le then ~1
    else if is_blank(read_byte(bv, s0 + 1, n)) then uses_key(bv, skip_blank(bv, s0 + 1, le, n), le, n)
    else ~1)
  else uses_key(bv, s0, le, n)
end


(* The first position at or after p of bv[0, 4096) that holds a NUL, or 4096 (public: bats affected reads its arguments so) *)



implement find_nul (bv, p) = let
  fun loop {l:agz}{p:nat | p <= 4096} .<4096 - p>.
    (bv: !$A.borrow(byte, l, 4096), p: int p): [r:nat | p <= r; r <= 4096] int r =
    if p >= 4096 then p
    else if read_byte(bv, p, 4096) = 0 then p
    else loop(bv, p + 1)
in loop(bv, p) end

(* Whether bv[p, e) starts with the first sn bytes of s, from its byte i on *)
fun lit_from {l:agz}{n:pos}{p,e:nat | e <= n}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n, s: string sn, sn: int sn, i: int i): bool =
  if i >= sn then true
  else if p + i >= e then false
  else if read_byte(bv, p + i, n) = char2int0(string_get_at(s, i)) then lit_from(bv, p, e, n, s, sn, i + 1)
  else false

(* The end of the word of bv[p, e): the first blank, or e *)
fun word_end {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if is_blank(read_byte(bv, p, n)) then p
  else word_end(bv, p + 1, e, n)

(* Whether bv[a, b) is the text s *)
fn word_is {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}{sn:nat}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n, s: string sn, sn: int sn): bool =
  if b - a <> sn then false else lit_from(bv, a, b, n, s, sn, 0)

(* Whether bv[p, e) holds the text s anywhere *)
fun contains_lit {l:agz}{n:pos}{p,e:nat | p <= e; e <= n}{sn:nat} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n, s: string sn, sn: int sn): bool =
  if p >= e then false
  else if lit_from(bv, p, e, n, s, sn, 0) then true
  else contains_lit(bv, p + 1, e, n, s, sn)

(* The end of the run of digits of bv[p, e) *)
fun digit_run {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else let
    val c = read_byte(bv, p, n)
  in
    if c >= 48 && c <= 57 then digit_run(bv, p + 1, e, n) else p
  end

(* Whether bv[p, e) is name bytes and plus signs only *)
fun suffix_ok {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): bool =
  if p >= e then true
  else let
    val c = read_byte(bv, p, n)
  in
    if is_name_byte(c, false) || c = 43 then suffix_ok(bv, p + 1, e, n) else false
  end

(* Whether bv[a, b) is an exact version: three numbers, then nothing or a - or + suffix *)
fn exact_version {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): bool = let
  val major_end = digit_run(bv, a, b, n)
in
  if major_end <= a then false
  else if byte_in(bv, major_end, b, n) <> 46 then false
  else if major_end + 1 > b then false
  else let
    val minor_end = digit_run(bv, major_end + 1, b, n)
  in
    if minor_end <= major_end + 1 then false
    else if byte_in(bv, minor_end, b, n) <> 46 then false
    else if minor_end + 1 > b then false
    else let
      val patch_end = digit_run(bv, minor_end + 1, b, n)
    in
      if patch_end <= minor_end + 1 then false
      else if patch_end >= b then true
      else if byte_in(bv, patch_end, b, n) = 43 || byte_in(bv, patch_end, b, n) = 45 then
        (if patch_end + 1 >= b then false else suffix_ok(bv, patch_end + 1, b, n))
      else false
    end
  end
end

(* A finding: its code (0 for none) and the span it names *)
typedef finding = @(int, pos_t, pos_t)

(* A finding and the block state after the line *)
typedef keyed = @(int, pos_t, pos_t, int, int)

(* The findings and dependencies counted so far in a package.json, and whether the walk is inside a section *)
typedef packaged = @(int, int, bool)

(* A double or single quote *)
fn is_quote (c: int): bool = c = 34 || c = 39

(* Whether bv[a, b) is an exact version, or an expression whose own source is checked *)
fn version_plain {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): bool =
  if lit_from(bv, a, b, n, "${{", 3, 0) then true else exact_version(bv, a, b, n)

(* ... with one pair of quotes around it taken off *)
fn version_ok {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): bool =
  if b - a >= 2 then
    (if read_byte(bv, a, n) = read_byte(bv, b - 1, n) && is_quote(read_byte(bv, a, n))
    then version_plain(bv, a + 1, b - 1, n) else version_plain(bv, a, b, n))
  else version_plain(bv, a, b, n)

(* Whether bv[p, e) holds a label that ends in -latest *)
fun has_latest {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): bool =
  if p >= e then false
  else if lit_from(bv, p, e, n, "-latest", 7, 0) then
    (if p + 7 >= e then true
    else if is_name_byte(read_byte(bv, p + 7, n), false) then has_latest(bv, p + 1, e, n)
    else true)
  else has_latest(bv, p + 1, e, n)

(* Whether bv[p, e) is a run of 64 lowercase hex digits somewhere; run counts the digits before p *)
fun has_hex_run {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n, run: int): bool =
  if run >= 64 then true
  else if p >= e then false
  else let
    val c = read_byte(bv, p, n)
  in
    if (c >= 48 && c <= 57) || (c >= 97 && c <= 102) then has_hex_run(bv, p + 1, e, n, run + 1)
    else has_hex_run(bv, p + 1, e, n, 0)
  end

(* Whether the content bv[cs, ce) starts a list item *)
fn is_item {l:agz}{n:pos}{cs,ce:nat | cs <= ce; ce <= n}
  (bv: !$A.borrow(byte, l, n), cs: int cs, ce: int ce, n: int n): bool =
  if cs >= ce then false
  else if read_byte(bv, cs, n) <> 45 then false
  else if cs + 1 >= ce then true
  else is_blank(read_byte(bv, cs + 1, n))

(* The start of the key of the content bv[cs, ce): after a list item's dash *)
fn key_start {l:agz}{n:pos}{cs,ce:nat | cs <= ce; ce <= n}
  (bv: !$A.borrow(byte, l, n), cs: int cs, ce: int ce, n: int n): [r:nat | cs <= r; r <= ce] int r =
  if cs >= ce then cs
  else if read_byte(bv, cs, n) <> 45 then cs
  else if cs + 1 >= ce then ce
  else if is_blank(read_byte(bv, cs + 1, n)) then skip_blank(bv, cs + 1, ce, n)
  else cs

(* The colon that ends the key from ks, or ~1 when bv[ks, ce) does not start with a key *)
fn key_stop {l:agz}{n:pos}{ks,ce:nat | ks <= ce; ce <= n}
  (bv: !$A.borrow(byte, l, n), ks: int ks, ce: int ce, n: int n)
  : [r:int | r == ~1 || (ks <= r && r < ce)] int r = let
  val name_stop = name_run(bv, ks, ce, n, false)
in
  if name_stop >= ce then ~1
  else if name_stop <= ks then ~1
  else if read_byte(bv, name_stop, n) <> 58 then ~1
  else if name_stop + 1 >= ce then name_stop
  else if is_blank(read_byte(bv, name_stop + 1, n)) then name_stop
  else ~1
end

(* The start of the line that holds position p *)
fun line_start {l:agz}{n:pos}{p:nat | p <= n} .<p>.
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n): [r:nat | r <= p] int r =
  if p <= 0 then 0
  else if read_byte(bv, p - 1, n) = 10 then p
  else line_start(bv, p - 1, n)

(* The start of the step the line at ls is in: the nearest line above that starts a list item indented less than every line between *)
fun step_back {l:agz}{n:pos}{ls:nat | ls <= n} .<ls>.
  (bv: !$A.borrow(byte, l, n), ls: int ls, n: int n, floor: int): [r:nat | r <= ls] int r =
  if ls <= 0 then 0
  else let
    val before = line_start(bv, ls - 1, n)
    val content = skip_blank(bv, before, ls - 1, n)
  in
    if content >= ls - 1 then step_back(bv, before, n, floor)
    else if content - before < floor && is_item(bv, content, ls - 1, n) then before
    else step_back(bv, before, n, (if content - before < floor then content - before else floor))
  end

(* The start of the first line at or after p (a line start) that is indented d or less *)
fun step_forward {l:agz}{n:pos}{p,nb:nat | p <= nb; nb <= n} .<nb - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, nb: int nb, n: int n, d: int): [r:nat | p <= r; r <= nb] int r =
  if p >= nb then p
  else let
    val stop = line_end(bv, p, nb, n)
    val content = skip_blank(bv, p, stop, n)
  in
    if content >= stop then (if stop >= nb then nb else step_forward(bv, stop + 1, nb, n, d))
    else if content - p <= d then p
    else if stop >= nb then nb
    else step_forward(bv, stop + 1, nb, n, d)
  end

(* Whether bv[p, e) names a checksum tool *)
fn has_checksum {l:agz}{n:pos}{p,e:nat | p <= e; e <= n}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n): bool =
  contains_lit(bv, p, e, n, "sha256sum", 9) || contains_lit(bv, p, e, n, "shasum", 6)
  || contains_lit(bv, p, e, n, "sha512sum", 9) || contains_lit(bv, p, e, n, "sha384sum", 9)
  || contains_lit(bv, p, e, n, "b2sum", 5)

(* Whether the step that starts at start holds the line at ls of bv[0, nb) and checks a checksum *)
fn step_checks_from {l:agz}{n:pos}{start,ls,nb:nat | start <= ls; ls <= nb; nb <= n}
  (bv: !$A.borrow(byte, l, n), start: int start, ls: int ls, nb: int nb, n: int n): bool = let
  val own_stop = line_end(bv, ls, nb, n)
  val start_stop = line_end(bv, start, nb, n)
  val start_content = skip_blank(bv, start, start_stop, n)
  val d = (if is_item(bv, start_content, start_stop, n) then start_content - start else ~1): int
in
  if own_stop >= nb then has_checksum(bv, start, nb, n)
  else has_checksum(bv, start, step_forward(bv, own_stop + 1, nb, n, d), n)
end

(* Whether the step that holds the line at ls of bv[0, nb) checks a checksum *)
fn step_checks {l:agz}{n:pos}{ls,nb:nat | ls <= nb; nb <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, nb: int nb, n: int n): bool = let
  val own_stop = line_end(bv, ls, nb, n)
  val own_content = skip_blank(bv, ls, own_stop, n)
in
  if is_item(bv, own_content, own_stop, n) then step_checks_from(bv, ls, ls, nb, n)
  else step_checks_from(bv, step_back(bv, ls, n, own_content - ls), ls, nb, n)
end

(* The last @ of bv[p, e) after the first byte, kept in at; ~1 when none *)
fun last_at {l:agz}{n:pos}{first,p,e:nat | first <= p; p <= e; e <= n}{at:int | at == ~1 || (first <= at && at < p)} .<e - p>.
  (bv: !$A.borrow(byte, l, n), first: int first, p: int p, e: int e, n: int n, at: int at)
  : [r:int | r == ~1 || (first <= r && r < e)] int r =
  if p >= e then at
  else if p > first && read_byte(bv, p, n) = 64 then last_at(bv, first, p + 1, e, n, p)
  else last_at(bv, first, p + 1, e, n, at)

(* The arguments of npx from p: the first that is no flag must be name@exact version *)
fun npx_arguments {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n, command: pos_t): @(int, pos_t, pos_t) = let
  val at = skip_blank(bv, p, e, n)
in
  if at >= e then @(0, 0, 0)
  else let
    val stop = word_end(bv, at + 1, e, n)
  in
    if read_byte(bv, at, n) = 45 then npx_arguments(bv, stop, e, n, command)
    else let
      val sign = last_at(bv, at, at, stop, n, ~1)
    in
      if sign < 0 then @(6, command, stop)
      else if sign + 1 >= stop then @(6, command, stop)
      else if exact_version(bv, sign + 1, stop, n) then @(0, 0, 0)
      else @(6, command, stop)
    end
  end
end

(* b less a closing parenthesis or semicolon that ends bv[a, b) *)
fn core_end {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): [r:nat | a <= r; r <= b] int r =
  if b <= a then b
  else if read_byte(bv, b - 1, n) = 41 || read_byte(bv, b - 1, n) = 59 then b - 1
  else b

(* The finding of the command word bv[at, stop) of the content ending at ce, in the line at ls *)
fn command_rule {l:agz}{n:pos}{at,stop,ce,ls,nb:nat | at <= stop; stop <= ce; ce <= n; ls <= nb; nb <= n}
  (bv: !$A.borrow(byte, l, n), at: int at, stop: int stop, ce: int ce, n: int n, ls: int ls, nb: int nb)
  : @(int, pos_t, pos_t) = let
  val second_at = skip_blank(bv, stop, ce, n)
in
  if word_is(bv, at, stop, n, "npx", 3) then npx_arguments(bv, stop, ce, n, at)
  else if word_is(bv, at, stop, n, "curl", 4) || word_is(bv, at, stop, n, "wget", 4) then
    (if step_checks(bv, ls, nb, n) then @(0, 0, 0) else @(8, at, stop))
  else if second_at >= ce then @(0, 0, 0)
  else let
    val second_stop = core_end(bv, second_at, word_end(bv, second_at + 1, ce, n), n)
    val installs = word_is(bv, second_at, second_stop, n, "install", 7) || word_is(bv, second_at, second_stop, n, "i", 1)
  in
    if ~installs then @(0, 0, 0)
    else if word_is(bv, at, stop, n, "npm", 3) then @(5, at, second_stop)
    else if word_is(bv, at, stop, n, "pnpm", 4) then
      (if contains_lit(bv, second_stop, ce, n, "--frozen-lockfile", 17) then @(0, 0, 0) else @(7, at, second_stop))
    else @(0, 0, 0)
  end
end

(* Whether the word bv[at, stop) leaves the next word in the position of a command *)
fn continues_command {l:agz}{n:pos}{at,stop:nat | at <= stop; stop <= n}
  (bv: !$A.borrow(byte, l, n), at: int at, stop: int stop, n: int n): bool =
  word_is(bv, at, stop, n, "-", 1) || word_is(bv, at, stop, n, "run:", 4)
  || word_is(bv, at, stop, n, "&&", 2) || word_is(bv, at, stop, n, "||", 2)
  || word_is(bv, at, stop, n, "|", 1) || word_is(bv, at, stop, n, "sudo", 4)
  || word_is(bv, at, stop, n, "then", 4) || word_is(bv, at, stop, n, "do", 2)
  || word_is(bv, at, stop, n, "else", 4) || word_is(bv, at, stop, n, "exec", 4)
  || (stop > at && read_byte(bv, stop - 1, n) = 59)

(* The first refused command among the words of the content bv[pos, ce): only a word in the position of a command is one *)
fun words {l:agz}{n:pos}{pos,ce,ls,nb:nat | pos <= ce; ce <= n; ls <= nb; nb <= n} .<ce - pos>.
  (bv: !$A.borrow(byte, l, n), pos: int pos, ce: int ce, n: int n, command: bool, ls: int ls, nb: int nb)
  : @(int, pos_t, pos_t) = let
  val at = skip_blank(bv, pos, ce, n)
in
  if at >= ce then @(0, 0, 0)
  else if command && read_byte(bv, at, n) = 40 then words(bv, at + 1, ce, n, true, ls, nb)
  else let
    val stop = word_end(bv, at + 1, ce, n)
    val made = (if command then command_rule(bv, at, stop, ce, n, ls, nb) else @(0, 0, 0)): finding
    val @(code, from, to) = made
  in
    if code <> 0 then @(code, from, to)
    else words(bv, stop, ce, n, continues_command(bv, at, stop, n), ls, nb)
  end
end

(* The finding of a uses: value bv[a, b) whose comment starts at c of the line ending at le *)
fn uses_judge {l:agz}{n:pos}{a,b,c,le:nat | a <= b; b <= n; c <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, c: int c, le: int le, n: int n): @(int, pos_t, pos_t) =
  if is_local(bv, a, b, n) then @(0, 0, 0)
  else if ~is_pinned(bv, a, b, n) then @(1, a, b)
  else if c >= le then @(2, a, b)
  else if has_text(bv, c + 1, le, n) then @(0, 0, 0)
  else @(2, a, b)

(* The finding of the line bv[ls, le) as a uses: *)
fn uses_rule {l:agz}{n:pos}{ls,le:nat | ls <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, le: int le, n: int n): @(int, pos_t, pos_t) = let
  val k = uses_value(bv, ls, le, n)
in
  if k < 0 then @(0, 0, 0)
  else let
    val v = skip_blank(bv, k, le, n)
    val c = find_comment(bv, v, v, le, n)
    val e = trim_end(bv, v, c, n)
  in
    if e - v >= 2 then
      (if read_byte(bv, v, n) = read_byte(bv, e - 1, n) && is_quote(read_byte(bv, v, n))
      then uses_judge(bv, v + 1, e - 1, c, le, n)
      else uses_judge(bv, v, e, c, le, n))
    else uses_judge(bv, v, e, c, le, n)
  end
end

(* Whether the key bv[ks, ke) is a version input of a setup action *)
fn is_version_key {l:agz}{n:pos}{ks,ke:nat | ks <= ke; ke <= n}
  (bv: !$A.borrow(byte, l, n), ks: int ks, ke: int ke, n: int n): bool =
  word_is(bv, ks, ke, n, "node-version", 12) || word_is(bv, ks, ke, n, "java-version", 12)
  || word_is(bv, ks, ke, n, "python-version", 14)

(* The finding of the content bv[cs, ce) as a runner label or a version, and the block it opens:
   block 1 is the items of a runs-on or os list, 2 the default of a version input *)
fn key_rule {l:agz}{n:pos}{cs,ce:nat | cs <= ce; ce <= n}
  (bv: !$A.borrow(byte, l, n), cs: int cs, ce: int ce, n: int n, indent: int, block: int, block_indent: int)
  : @(int, pos_t, pos_t, int, int) = let
  val ks = key_start(bv, cs, ce, n)
  val ke = key_stop(bv, ks, ce, n)
in
  if block = 1 && is_item(bv, cs, ce, n) then
    (if has_latest(bv, cs, ce, n) then @(3, cs, ce, 1, block_indent) else @(0, 0, 0, 1, block_indent))
  else if block = 2 && indent > block_indent then
    (if ke < 0 then @(0, 0, 0, 2, block_indent)
    else if word_is(bv, ks, ke, n, "default", 7) then let
      val vs = skip_blank(bv, ke + 1, ce, n)
    in
      if version_ok(bv, vs, ce, n) then @(0, 0, 0, 0, 0) else @(4, vs, ce, 0, 0)
    end
    else @(0, 0, 0, 2, block_indent))
  else if ke < 0 then @(0, 0, 0, 0, 0)
  else let
    val vs = skip_blank(bv, ke + 1, ce, n)
  in
    if word_is(bv, ks, ke, n, "runs-on", 7) || word_is(bv, ks, ke, n, "os", 2) then
      (if vs >= ce then @(0, 0, 0, 1, indent)
      else if has_latest(bv, vs, ce, n) then @(3, vs, ce, 0, 0)
      else @(0, 0, 0, 0, 0))
    else if is_version_key(bv, ks, ke, n) then
      (if vs >= ce then @(0, 0, 0, 2, indent)
      else if version_ok(bv, vs, ce, n) then @(0, 0, 0, 0, 0)
      else @(4, vs, ce, 0, 0))
    else @(0, 0, 0, 0, 0)
  end
end

(* The finding of the line bv[ls, le) as one that names the ATS2 tarball or a digest, outside a uses: *)
fn ats2_named_rule {l:agz}{n:pos}{ls,le:nat | ls <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, le: int le, n: int n): @(int, pos_t, pos_t) =
  if uses_value(bv, ls, le, n) >= 0 then @(0, 0, 0)
  else if contains_lit(bv, ls, le, n, "ATS2-Postiats", 13) || has_hex_run(bv, ls, le, n, 0) then
    @(15, skip_blank(bv, ls, le, n), le)
  else @(0, 0, 0)

(* The reason of the exception whose comment starts at c of the line ending at le: its span, or ~1 for no exception, ~2 for no reason *)
fn exception_at {l:agz}{n:pos}{c,le:nat | c <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), c: int c, le: int le, n: int n): @(pos_t, pos_t) =
  if c >= le then @(~1, 0)
  else let
    val at = skip_blank(bv, c + 1, le, n)
  in
    if ~lit_from(bv, at, le, n, "unpinned:", 9, 0) then @(~1, 0)
    else if at + 9 > le then @(~1, 0)
    else let
      val reason = skip_blank(bv, at + 9, le, n)
      val reason_stop = trim_end(bv, reason, le, n)
    in
      if reason_stop <= reason then @(~2, 0) else @(reason, reason_stop)
    end
  end

(* ------------------------------------------------------------------ *)

(* Prints file:line: and the message of a finding, its span being bv[a, b) *)
fn print_finding {l:agz}{n:pos}{lc:agz}
  (bv: !$A.borrow(byte, l, n), n: int n, cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t,
   number: int, code: int, a: pos_t, b: int): void = let
  val () = prerr_seg(cmd, file_at, file_to, 4096)
  val () = prerr! (":", number, ": ")
  val () = (if code = 1 then let
      val () = prerr! ("uses '")
      val () = prerr_seg(bv, a, b, n)
    in prerr! ("' is not pinned: name the repository at a full commit SHA (40 lowercase hex digits)") end
    else if code = 2 then let
      val () = prerr! ("uses '")
      val () = prerr_seg(bv, a, b, n)
    in prerr! ("' has no comment saying which version the commit is (# v4)") end
    else if code = 3 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" names a runner image that moves: name the image (ubuntu-24.04), not a -latest label") end
    else if code = 4 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" is not an exact version: name all of it (22.23.3), or read a version file") end
    else if code = 5 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" installs what no lock names: use npm ci") end
    else if code = 6 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" is not a package at an exact version: name it package@1.2.3") end
    else if code = 7 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" may move the lock: add --frozen-lockfile") end
    else if code = 8 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" downloads with no checksum check in its step: check it with sha256sum -c") end
    else if code = 9 then let
      val () = prerr! ("dependency ")
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" is not at an exact version: no range, tag or *") end
    else if code = 11 then prerr! ("unpinned: the exception exempts nothing: remove it")
    else if code = 12 then prerr! ("unpinned: an exception needs a reason after the colon")
    else if code = 13 then prerr! ("ATS2_SHA256 is not a SHA-256 (#define ATS2_SHA256 followed by 64 lowercase hex digits in quotes)")
    else if code = 14 then prerr! ("ATS2_URL is not an https tarball (#define ATS2_URL \"https://...tgz\")")
    else if code = 15 then let
      val () = prerr_seg(bv, a, b, n)
    in prerr! (" names a tarball or a digest: the ATS2 pin is in src/ats2.bats alone") end
    else if code = 16 then prerr! ("dependencies are one to a line, as \"name\": \"version\"")
    else if code = 18 then prerr! ("check-pins-fixture needs a reason on its first line: why the package.json files below it float")
    else if code = 19 then prerr! ("check-pins-fixture covers no package.json at or below its directory among the files checked: remove it")
    else prerr! ("package.json has dependencies and no committed lock (package-lock.json, pnpm-lock.yaml or yarn.lock)"))
in prerr_newline() end

(* Prints file:line: unpinned: reason for an exception that exempted a finding, its reason being bv[a, b) *)
fn print_accepted {l:agz}{n:pos}{lc:agz}
  (bv: !$A.borrow(byte, l, n), n: int n, cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t,
   number: int, a: pos_t, b: int): void = let
  val () = print_borrow(cmd, file_at, file_to, 4096)
  val () = print! (":", number, ": unpinned: ")
  val () = print_borrow(bv, a, b, n)
in print_newline() end

(* The line state of the walk: found, block, block indent, then the exception above (its reason, its line, 0 for none) *)
typedef walk = @(int, int, int, pos_t, pos_t, int)

(* A pending exception that exempted nothing, being the one at line pending *)
fn unused_pending {l:agz}{n:pos}{lc:agz}
  (bv: !$A.borrow(byte, l, n), n: int n, cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t,
   pending: int): int =
  if pending <= 0 then 0
  else let
    val () = print_finding(bv, n, cmd, file_at, file_to, pending, 11, 0, 0)
  in 1 end

(* The walk over one line of a workflow or action, bv[ls, le) being the line and nb the end of the file *)
fn yaml_line {l:agz}{n:pos}{lc:agz}{ls,le,nb:nat | ls <= le; le <= nb; nb <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, le: int le, nb: int nb, n: int n,
   cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, number: int, ats2_named: bool, state: walk): walk = let
  val @(found, block, block_indent, pending_at, pending_to, pending) = state
  val cs = skip_blank(bv, ls, le, n)
  val c = find_comment(bv, cs, cs, le, n)
  val ce = trim_end(bv, cs, c, n)
  val @(reason_at, reason_to) = exception_at(bv, c, le, n)
in
  if cs >= le then let
    val gone = unused_pending(bv, n, cmd, file_at, file_to, pending)
  in @(found + gone, block, block_indent, 0, 0, 0) end
  else if c = cs then
    (if reason_at = ~2 then let
      val () = print_finding(bv, n, cmd, file_at, file_to, number, 12, 0, 0)
    in @(found + 1, block, block_indent, pending_at, pending_to, pending) end
    else if reason_at >= 0 then let
      val gone = unused_pending(bv, n, cmd, file_at, file_to, pending)
    in @(found + gone, block, block_indent, reason_at, reason_to, number) end
    else @(found, block, block_indent, pending_at, pending_to, pending))
  else let
    val @(uses_code, uses_from, uses_to) = uses_rule(bv, ls, le, n)
    val keyed_made = (if uses_code <> 0 then @(uses_code, uses_from, uses_to, block, block_indent)
      else key_rule(bv, cs, ce, n, cs - ls, block, block_indent)): keyed
    val @(key_code, key_from, key_to, block2, indent2) = keyed_made
    val command_made = (if key_code <> 0 then @(key_code, key_from, key_to) else words(bv, cs, ce, n, true, ls, nb)): finding
    val @(command_code, command_from, command_to) = command_made
    val ats2_made = (if command_code <> 0 || ~ats2_named then @(command_code, command_from, command_to)
      else ats2_named_rule(bv, ls, le, n)): finding
    val @(code, from, to) = ats2_made
    val inline_empty = (reason_at = ~2)
    val exempt_inline = (reason_at >= 0)
    val extra = (if inline_empty then let
        val () = print_finding(bv, n, cmd, file_at, file_to, number, 12, 0, 0)
      in 1 end else 0): int
  in
    if code <> 0 then
      (if pending > 0 then let
        val () = print_accepted(bv, n, cmd, file_at, file_to, pending, pending_at, pending_to)
      in @(found + extra, block2, indent2, 0, 0, 0) end
      else if exempt_inline then let
        val () = print_accepted(bv, n, cmd, file_at, file_to, number, reason_at, reason_to)
      in @(found + extra, block2, indent2, 0, 0, 0) end
      else let
        val () = print_finding(bv, n, cmd, file_at, file_to, number, code, from, to)
      in @(found + extra + 1, block2, indent2, 0, 0, 0) end)
    else let
      val gone = unused_pending(bv, n, cmd, file_at, file_to, pending)
      val inline_gone = (if exempt_inline then let
          val () = print_finding(bv, n, cmd, file_at, file_to, number, 11, 0, 0)
        in 1 end else 0): int
    in @(found + extra + gone + inline_gone, block2, indent2, 0, 0, 0) end
  end
end

(* The number of findings among the lines of bv[p, nb) of a workflow or action *)
fun yaml_lines {l:agz}{n:pos}{lc:agz}{p,nb:nat | p <= nb; nb <= n} .<nb - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, nb: int nb, n: int n,
   cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, number: int, ats2_named: bool, state: walk): int =
  if p >= nb then let
    val @(found, _, _, _, _, pending) = state
  in found + unused_pending(bv, n, cmd, file_at, file_to, pending) end
  else let
    val le = line_end(bv, p, nb, n)
    val after = yaml_line(bv, p, le, nb, n, cmd, file_at, file_to, number, ats2_named, state)
  in
    if le >= nb then let
      val @(found, _, _, _, _, pending) = after
    in found + unused_pending(bv, n, cmd, file_at, file_to, pending) end
    else yaml_lines(bv, le + 1, nb, n, cmd, file_at, file_to, number + 1, ats2_named, after)
  end

(* ------------------------------------------------------------------ *)

(* The first position of bv[p, e) that holds byte c, or e *)
fun find_byte {l:agz}{n:pos}{p,e:nat | p <= e; e <= n} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, n: int n, c: int): [r:nat | p <= r; r <= e] int r =
  if p >= e then p
  else if read_byte(bv, p, n) = c then p
  else find_byte(bv, p + 1, e, n, c)

(* Whether a dependency version bv[a, b) is exact, a git commit, or a workspace: package (local source, pinned by the commit) *)
fn dependency_ok {l:agz}{n:pos}{a,b:nat | a <= b; b <= n}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, n: int n): bool =
  if exact_version(bv, a, b, n) then true
  else if lit_from(bv, a, b, n, "workspace:", 10, 0) then true
  else if lit_from(bv, a, b, n, "github:", 7, 0) then
    (if b - 41 < a then false
    else if read_byte(bv, b - 41, n) <> 35 then false
    else all_hex(bv, b - 40, b, n))
  else false

(* Whether bv[cs, ce) is the quoted key s followed by a colon and a brace; the position after the brace, or ~1 *)
fn section_open {l:agz}{n:pos}{cs,ce:nat | cs <= ce; ce <= n}{sn:nat}
  (bv: !$A.borrow(byte, l, n), cs: int cs, ce: int ce, n: int n, s: string sn, sn: int sn)
  : [r:int | r == ~1 || (cs <= r && r <= ce)] int r =
  if cs + sn + 2 > ce then ~1
  else if read_byte(bv, cs, n) <> 34 then ~1
  else if ~lit_from(bv, cs + 1, ce, n, s, sn, 0) then ~1
  else if read_byte(bv, cs + sn + 1, n) <> 34 then ~1
  else let
    val colon = skip_blank(bv, cs + sn + 2, ce, n)
  in
    if colon >= ce then ~1
    else if read_byte(bv, colon, n) <> 58 then ~1
    else let
      val brace = skip_blank(bv, colon + 1, ce, n)
    in
      if brace >= ce then ~1
      else if read_byte(bv, brace, n) <> 123 then ~1
      else brace + 1
    end
  end

(* The position after the brace of a dependencies section that opens the content bv[cs, ce), or ~1 *)
fn dependencies_open {l:agz}{n:pos}{cs,ce:nat | cs <= ce; ce <= n}
  (bv: !$A.borrow(byte, l, n), cs: int cs, ce: int ce, n: int n)
  : [r:int | r == ~1 || (cs <= r && r <= ce)] int r = let
  val plain = section_open(bv, cs, ce, n, "dependencies", 12)
in
  if plain >= 0 then plain
  else let
    val dev = section_open(bv, cs, ce, n, "devDependencies", 15)
  in
    if dev >= 0 then dev else section_open(bv, cs, ce, n, "optionalDependencies", 20)
  end
end

(* The finding of the content bv[cs, ce) inside a dependencies section: "name": "version" *)
fn dependency_rule {l:agz}{n:pos}{cs,ce:nat | cs <= ce; ce <= n}
  (bv: !$A.borrow(byte, l, n), cs: int cs, ce: int ce, n: int n): @(int, pos_t, pos_t) =
  if cs >= ce then @(16, cs, ce)
  else if read_byte(bv, cs, n) <> 34 then @(16, cs, ce)
  else let
    val name_stop = find_byte(bv, cs + 1, ce, n, 34)
  in
    if name_stop >= ce then @(16, cs, ce)
    else let
      val colon = skip_blank(bv, name_stop + 1, ce, n)
    in
      if colon >= ce then @(16, cs, ce)
      else if read_byte(bv, colon, n) <> 58 then @(16, cs, ce)
      else let
        val value_open = skip_blank(bv, colon + 1, ce, n)
      in
        if value_open >= ce then @(16, cs, ce)
        else if read_byte(bv, value_open, n) <> 34 then @(9, cs, ce)
        else let
          val value_stop = find_byte(bv, value_open + 1, ce, n, 34)
        in
          if value_stop >= ce then @(16, cs, ce)
          else if dependency_ok(bv, value_open + 1, value_stop, n) then @(0, 0, 0)
          else @(9, cs, value_stop + 1)
        end
      end
    end
  end

(* The walk over the lines of bv[p, nb) of a package.json: the findings, then how many dependencies there were *)
fun package_lines {l:agz}{n:pos}{lc:agz}{p,nb:nat | p <= nb; nb <= n} .<nb - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, nb: int nb, n: int n,
   cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, number: int,
   found: int, dependencies: int, inside: bool): @(int, int) =
  if p >= nb then @(found, dependencies)
  else let
    val le = line_end(bv, p, nb, n)
    val cs = skip_blank(bv, p, le, n)
    val ce = trim_end(bv, cs, le, n)
    val after = (if cs >= ce then @(found, dependencies, inside)
      else if inside then
        (if read_byte(bv, cs, n) = 125 then @(found, dependencies, false)
        else let
          val @(code, from, to) = dependency_rule(bv, cs, ce, n)
          val () = (if code <> 0 then print_finding(bv, n, cmd, file_at, file_to, number, code, from, to) else ())
        in @((if code <> 0 then found + 1 else found), dependencies + 1, true) end)
      else let
        val brace = dependencies_open(bv, cs, ce, n)
      in
        if brace < 0 then @(found, dependencies, false)
        else let
          val rest = skip_blank(bv, brace, ce, n)
        in
          if rest >= ce then @(found, dependencies, true)
          else if read_byte(bv, rest, n) = 125 then @(found, dependencies, false)
          else let
            val () = print_finding(bv, n, cmd, file_at, file_to, number, 16, cs, ce)
          in @(found + 1, dependencies + 1, false) end
        end
      end): packaged
    val @(found2, dependencies2, inside2) = after
  in
    if le >= nb then @(found2, dependencies2)
    else package_lines(bv, le + 1, nb, n, cmd, file_at, file_to, number + 1, found2, dependencies2, inside2)
  end

(* ------------------------------------------------------------------ *)

(* Whether the line bv[ls, le) is the quoted define s followed by 64 lowercase hex digits and a closing quote *)
fn sha_line {l:agz}{n:pos}{ls,le:nat | ls <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, le: int le, n: int n): bool =
  if ~lit_from(bv, ls, le, n, "#define ATS2_SHA256 \"", 21, 0) then false
  else if le - ls <> 21 + 64 + 1 then false
  else if read_byte(bv, le - 1, n) <> 34 then false
  else all_hex(bv, ls + 21, le - 1, n)

(* Whether the line bv[ls, le) is the define of an https tarball *)
fn url_line {l:agz}{n:pos}{ls,le:nat | ls <= le; le <= n}
  (bv: !$A.borrow(byte, l, n), ls: int ls, le: int le, n: int n): bool =
  if ~lit_from(bv, ls, le, n, "#define ATS2_URL \"https://", 26, 0) then false
  else if le - ls < 26 + 5 then false
  else if ~lit_from(bv, le - 5, le, n, ".tgz\"", 5, 0) then false
  else find_byte(bv, ls + 26, le - 1, n, 34) >= le - 1

(* Which of the two defines of src/ats2.bats the lines of bv[p, nb) hold: 1 the digest, 2 the URL, 3 both *)
fun ats2_lines {l:agz}{n:pos}{p,nb:nat | p <= nb; nb <= n} .<nb - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, nb: int nb, n: int n, seen: int): int =
  if p >= nb then seen
  else let
    val le = line_end(bv, p, nb, n)
    val seen2 = (if sha_line(bv, p, le, n) then (if seen = 2 || seen = 3 then 3 else 1)
      else if url_line(bv, p, le, n) then (if seen = 1 || seen = 3 then 3 else 2)
      else seen): int
  in
    if le >= nb then seen2 else ats2_lines(bv, le + 1, nb, n, seen2)
  end

(* ------------------------------------------------------------------ *)

(* Whether cmd[at, to) ends with the name s after a slash or at its start (public: bats affected names its command so) *)



implement named_file (cmd, at, to, s, sn) =
  if at < 0 then false
  else if to > 4096 then false
  else if to - at < sn then false
  else if at > to then false
  else if to - at = sn then lit_from(cmd, at, to, 4096, s, sn, 0)
  else if read_byte(cmd, to - sn - 1, 4096) <> 47 then false
  else lit_from(cmd, to - sn, to, 4096, s, sn, 0)

(* Whether one of the arguments cmd[p, total) is src/ats2.bats's file *)
fun ats2_among {lc:agz}{p:nat | p <= 4096} .<4096 - p>.
  (cmd: !$A.borrow(byte, lc, 4096), p: int p, total: int): bool =
  if p >= total then false
  else let
    val z = find_nul(cmd, p)
  in
    if named_file(cmd, p, z, "ats2.bats", 9) then true
    else if z + 1 > 4096 then false
    else ats2_among(cmd, z + 1, total)
  end

(* Whether the file name is in the directory cmd[file_at, dir_to) (the path of the directory ends with its slash, or is empty for the current directory) *)
fn file_in {lc:agz}{sn:nat}
  (cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, dir_to: pos_t, name: string sn, name_len: int sn): bool = let
  var path : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, file_at, dir_to, 4096, path)
  val () = bput_v(path, name)
  val () = put_char_v(path, 0)
  val @(path_a, path_len) = $B.into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
  val exists = file_exists_m(bv_p, path_len)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in exists end

(* The lock files a package.json may be beside *)
fn lock_beside {lc:agz}{sn:nat}
  (cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, name: string sn, name_len: int sn): bool =
  file_in(cmd, file_at, file_to - 12, name, name_len)

(* Where the last component of the directory cmd[a, e) starts, the directory ending with its slash at e - 1 *)
fun component_start {lc:agz}{a,q:nat | a <= q; q <= 4096} .<q - a>.
  (cmd: !$A.borrow(byte, lc, 4096), a: int a, q: int q): [s:nat | a <= s; s <= q] int s =
  if q <= a then a
  else if read_byte(cmd, q - 1, 4096) = 47 then q
  else component_start(cmd, a, q - 1)

(* The end of the parent directory of cmd[a, e) (its slash included, or a for the current directory), or ~1 when it has none: the root, or a component named .. (workspace roots, keyword: pnpm workspace lock) *)
fn parent_dir {lc:agz}{a,e:nat | a <= e; e <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), a: int a, e: int e): [r:int | r < e] int r =
  if e <= a then ~1
  else if e - a = 1 && read_byte(cmd, a, 4096) = 47 then ~1
  else let
    val s = component_start(cmd, a, e - 1)
  in
    if e - 1 - s = 2 then (if read_byte(cmd, s, 4096) = 46 && read_byte(cmd, s + 1, 4096) = 46 then ~1 else s)
    else s
  end

(* Whether the nearest directory at or above cmd[a, e) that holds a pnpm-workspace.yaml also holds a pnpm-lock.yaml (only the existence of the two files is tested; pnpm keeps one lock at the root of a workspace; keyword: pnpm workspace lock) *)
fun workspace_lock {lc:agz}{a,e:nat | a <= e; e <= 4096} .<e - a>.
  (cmd: !$A.borrow(byte, lc, 4096), a: int a, e: int e): bool =
  if file_in(cmd, a, e, "pnpm-workspace.yaml", 19) then file_in(cmd, a, e, "pnpm-lock.yaml", 14)
  else let
    val p = parent_dir(cmd, a, e)
  in
    if p >= a then workspace_lock(cmd, a, p) else false
  end

(* Whether cmd[x, x + len) and cmd[y, y + len) are the same bytes *)
fun same_range {lc:agz}{x,y,len:nat | x + len <= 4096; y + len <= 4096} .<len>.
  (cmd: !$A.borrow(byte, lc, 4096), x: int x, y: int y, len: int len): bool =
  if len <= 0 then true
  else if read_byte(cmd, x, 4096) <> read_byte(cmd, y, 4096) then false
  else same_range(cmd, x + 1, y + 1, len - 1)

(* Whether the directory cmd[a, e) or one above it (the walk of workspace_lock) is the directory cmd[dir_at, dir_to) (fixture markers, keyword: check-pins-fixture) *)
fun reaches_dir {lc:agz}{a,e,dir_at,dir_to:nat | a <= e; e <= 4096; dir_at <= dir_to; dir_to <= 4096} .<e - a>.
  (cmd: !$A.borrow(byte, lc, 4096), a: int a, e: int e, dir_at: int dir_at, dir_to: int dir_to): bool =
  if e - a = dir_to - dir_at then
    (if same_range(cmd, a, dir_at, e - a) then true
    else let
      val p = parent_dir(cmd, a, e)
    in
      if p >= a then reaches_dir(cmd, a, p, dir_at, dir_to) else false
    end)
  else let
    val p = parent_dir(cmd, a, e)
  in
    if p >= a then reaches_dir(cmd, a, p, dir_at, dir_to) else false
  end

(* The end of the nearest directory at or above cmd[a, e) that holds a check-pins-fixture, or ~1 for none (the walk stops where workspace_lock's does; keyword: check-pins-fixture) *)
fun marker_dir {lc:agz}{a,e:nat | a <= e; e <= 4096} .<e - a>.
  (cmd: !$A.borrow(byte, lc, 4096), a: int a, e: int e): int =
  if file_in(cmd, a, e, "check-pins-fixture", 18) then e
  else let
    val p = parent_dir(cmd, a, e)
  in
    if p >= a then marker_dir(cmd, a, p) else ~1
  end

(* The end of the directory of the marker above the package.json cmd[file_at, file_to), or ~1 for none (keyword: check-pins-fixture) *)
fn marker_above {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t): int =
  if file_at < 0 then ~1
  else if file_to - 12 < file_at then ~1
  else if file_to - 12 > 4096 then ~1
  else marker_dir(cmd, file_at, file_to - 12)

(* Whether the package.json cmd[p, z) is at or below the directory cmd[dir_at, dir_to) *)
fn covers_package {lc:agz}{p,z,dir_at,dir_to:nat | z <= 4096; dir_at <= dir_to; dir_to <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), p: int p, z: int z, dir_at: int dir_at, dir_to: int dir_to): bool =
  if z - 12 < p then false
  else reaches_dir(cmd, p, z - 12, dir_at, dir_to)

(* Whether one of the arguments cmd[p, total) is a package.json at or below the directory cmd[dir_at, dir_to) (keyword: check-pins-fixture) *)
fun covered_among {lc:agz}{p,dir_at,dir_to:nat | p <= 4096; dir_at <= dir_to; dir_to <= 4096} .<4096 - p>.
  (cmd: !$A.borrow(byte, lc, 4096), p: int p, total: int, dir_at: int dir_at, dir_to: int dir_to): bool =
  if p >= total then false
  else let
    val z = find_nul(cmd, p)
  in
    if named_file(cmd, p, z, "package.json", 12) && covers_package(cmd, p, z, dir_at, dir_to) then true
    else if z + 1 > 4096 then false
    else covered_among(cmd, z + 1, total, dir_at, dir_to)
  end

(* Whether a marker covers the package.json cmd[file_at, file_to), its reason being printed as the exception of line 1; false for no marker, an unreadable one or one with no reason (the marker is a finding of its own; keyword: check-pins-fixture) *)
fn exempt_by_marker {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t): bool = let
  val dir_to = marker_above(cmd, file_at, file_to)
in
  if dir_to < 0 then false
  else let
    var path : $B.builder_v = $B.create()
    val () = copy_to_builder_v(cmd, file_at, dir_to, 4096, path)
    val () = bput_v(path, "check-pins-fixture")
    val () = put_char_v(path, 0)
    val @(path_a, path_len) = $B.into_arr(path)
    val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
    val exempt = (case+ read_whole_m(bv_p, path_len) of
      | ~whole_err(_) => false
      | ~whole_ok(ar, piece, m, nbytes) => let
          val @(fz, bv) = $A.freeze<byte>(piece)
          val stop = line_end(bv, 0, nbytes, m)
          val reason = skip_blank(bv, 0, stop, m)
          val reason_stop = trim_end(bv, reason, stop, m)
          val shown = (if reason_stop <= reason then false else let
              val () = print_accepted(bv, m, cmd, file_at, file_to, 1, reason, reason_stop)
            in true end): bool
          val () = $A.drop<byte>(fz, bv)
          val () = whole_free(ar, $A.thaw<byte>(fz))
        in shown end): bool
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in exempt end
end

(* Whether a lock file is beside the package.json cmd[file_at, file_to), or it is a member of a pnpm workspace whose root holds the lock *)
fn has_lock {lc:agz}
  (cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t): bool =
  lock_beside(cmd, file_at, file_to, "package-lock.json", 17) || lock_beside(cmd, file_at, file_to, "npm-shrinkwrap.json", 19)
  || lock_beside(cmd, file_at, file_to, "pnpm-lock.yaml", 14) || lock_beside(cmd, file_at, file_to, "yarn.lock", 9)
  || lock_beside(cmd, file_at, file_to, "bun.lock", 8)
  || (if file_at < 0 then false
    else if file_to - 12 < file_at then false
    else if file_to - 12 > 4096 then false
    else workspace_lock(cmd, file_at, file_to - 12))

(* The findings of the marker file bv[0, nbytes) named cmd[file_at, file_to): no reason on its first line, and no package.json among the files cmd[list_from, total) at or below its directory (keyword: check-pins-fixture) *)
fn check_marker {l:agz}{n:pos}{lc:agz}{nbytes:nat | nbytes <= n}{lf:int}
  (bv: !$A.borrow(byte, l, n), nbytes: int nbytes, n: int n,
   cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, list_from: int lf, total: int): int = let
  val stop = line_end(bv, 0, nbytes, n)
  val no_reason = (if has_text(bv, 0, stop, n) then 0 else let
      val () = print_finding(bv, n, cmd, file_at, file_to, 1, 18, 0, 0)
    in 1 end): int
  val dir_to = file_to - 18
  val unused = (if file_at < 0 then 0
    else if dir_to < file_at then 0
    else if dir_to > 4096 then 0
    else if list_from < 0 then 0
    else if list_from > 4096 then 0
    else if covered_among(cmd, list_from, total, file_at, dir_to) then 0
    else let
      val () = print_finding(bv, n, cmd, file_at, file_to, 1, 19, 0, 0)
    in 1 end): int
in no_reason + unused end

(* The number of findings of the file bv[0, nbytes) named cmd[file_at, file_to) *)
fn check_text {l:agz}{n:pos}{lc:agz}{nbytes:nat | nbytes <= n}{lf:int}
  (bv: !$A.borrow(byte, l, n), nbytes: int nbytes, n: int n,
   cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, ats2_named: bool,
   list_from: int lf, total: int): int =
  if named_file(cmd, file_at, file_to, "check-pins-fixture", 18) then
    check_marker(bv, nbytes, n, cmd, file_at, file_to, list_from, total)
  else if named_file(cmd, file_at, file_to, "package.json", 12) then
    (if exempt_by_marker(cmd, file_at, file_to) then 0 else let
      val @(found, dependencies) = package_lines(bv, 0, nbytes, n, cmd, file_at, file_to, 1, 0, 0, false)
    in
      if dependencies > 0 && ~has_lock(cmd, file_at, file_to) then let
        val () = print_finding(bv, n, cmd, file_at, file_to, 1, 17, 0, 0)
      in found + 1 end
      else found
    end)
  else if named_file(cmd, file_at, file_to, "ats2.bats", 9) then let
    val seen = ats2_lines(bv, 0, nbytes, n, 0)
    val missing_sha = (if seen = 1 || seen = 3 then 0 else let
        val () = print_finding(bv, n, cmd, file_at, file_to, 1, 13, 0, 0)
      in 1 end): int
    val missing_url = (if seen = 2 || seen = 3 then 0 else let
        val () = print_finding(bv, n, cmd, file_at, file_to, 1, 14, 0, 0)
      in 1 end): int
  in missing_sha + missing_url end
  else yaml_lines(bv, 0, nbytes, n, cmd, file_at, file_to, 1, ats2_named, @(0, 0, 0, 0, 0, 0))

(* The status of the file named cmd[file_at, file_to): 0 clean, 1 findings, 2 unreadable *)
fn check_file {lc:agz}{lf:int}
  (cmd: !$A.borrow(byte, lc, 4096), file_at: pos_t, file_to: pos_t, ats2_named: bool, list_from: int lf, total: int): int = let
  var path : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, file_at, file_to, 4096, path)
  val () = put_char_v(path, 0)
  val @(path_a, path_len) = $B.into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
  val status = (case+ read_whole_m(bv_p, path_len) of
    | ~whole_err(_) => let
        val () = prerr! ("error: bats check-pins: cannot read ")
        val () = prerr_seg(cmd, file_at, file_to, 4096)
        val () = prerr_newline()
      in 2 end
    | ~whole_ok(ar, piece, m, nbytes) => let
        val @(fz, bv) = $A.freeze<byte>(piece)
        val found = check_text(bv, nbytes, m, cmd, file_at, file_to, ats2_named, list_from, total)
        val () = $A.drop<byte>(fz, bv)
        val () = whole_free(ar, $A.thaw<byte>(fz))
      in (if found > 0 then 1 else 0) end): int
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in status end

(* The worst status of the files named by the arguments of cmd[p, total) *)
fun check_files {lc:agz}{p:nat | p <= 4096}{lf:int} .<4096 - p>.
  (cmd: !$A.borrow(byte, lc, 4096), p: int p, total: int, ats2_named: bool, list_from: int lf, worst: int): int =
  if p >= total then worst
  else let
    val z = find_nul(cmd, p)
    val status = check_file(cmd, p, z, ats2_named, list_from, total)
    val worse = (if status > worst then status else worst): int
  in
    if z + 1 > 4096 then worse
    else check_files(cmd, z + 1, total, ats2_named, list_from, worse)
  end

(* Where the arguments after check-pins start, or ~1 when argv[1] is not check-pins *)
fn arguments_at {l:agz}{t:nat | t <= 4096} (cmd: !$A.borrow(byte, l, 4096), total: int t)
  : [r:int | r == ~1 || (0 <= r && r <= 4096)] int r = let
  val a = find_nul(cmd, 0) + 1
in
  if a + 11 > 4096 then ~1
  else if a + 10 >= total then ~1
  else if read_byte(cmd, a, 4096) = 99 && read_byte(cmd, a + 1, 4096) = 104
    && read_byte(cmd, a + 2, 4096) = 101 && read_byte(cmd, a + 3, 4096) = 99
    && read_byte(cmd, a + 4, 4096) = 107 && read_byte(cmd, a + 5, 4096) = 45
    && read_byte(cmd, a + 6, 4096) = 112 && read_byte(cmd, a + 7, 4096) = 105
    && read_byte(cmd, a + 8, 4096) = 110 && read_byte(cmd, a + 9, 4096) = 115
    && read_byte(cmd, a + 10, 4096) = 0 then a + 11
  else ~1
end

fn usage_error (): void = let
  val () = prerr! ("usage: bats check-pins <file>... | --discover")
  val () = prerr_newline()
in set_exit_code(2) end

(* An argument for the process package, made of a literal (public: bats affected runs git so) *)


implement literal_arg (s) = let
  var b = $B.create()
  val () = bput_v(b, s)
in mk_arg(b) end

(* Whether the only argument, cmd[first, total), is --discover *)
fn sole_discover {lc:agz}{first:nat | first <= 4096}
  (cmd: !$A.borrow(byte, lc, 4096), first: int first, total: int): bool = let
  val z = find_nul(cmd, first)
in
  if z - first <> 10 then false
  else if z + 1 <> total then false
  else named_file(cmd, first, z, "--discover", 10)
end

(* The message and status of a git ls-files that did not give its list *)
fn git_failed (): int = let
  val () = prerr! ("error: bats check-pins --discover: git ls-files failed: is the current directory in a git repository?")
  val () = prerr_newline()
in 2 end

(* bats check-pins --discover: the files of CI inputs of the repository of the
   current directory (git ls-files, tracked or untracked and not ignored: a
   planted file is read, bats_modules/ and build/ are not), checked as if named.
   Its list is read to its end by run_cmd_capture_outcome and the first 4096 bytes
   are kept: a longer list is its own outcome (refused, never cut) and git's status
   is never the cause of it (capture area, bats#444). The status as check-pins: 0,
   1, or 2 for no file, a git that fails or a list too long *)
fn discover (): int = let
  val (nul_git | git_exec) = $P.path_of_string_proved("git")
  val @(fz_git, bv_git) = $A.barr_freeze(git_exec)
  val argv = $L.list_vt_cons(literal_arg("git"), $L.list_vt_cons(literal_arg("ls-files"),
    $L.list_vt_cons(literal_arg("-z"), $L.list_vt_cons(literal_arg("--cached"),
    $L.list_vt_cons(literal_arg("--others"), $L.list_vt_cons(literal_arg("--exclude-standard"),
    $L.list_vt_cons(literal_arg("--"),
    $L.list_vt_cons(literal_arg(":(glob).github/workflows/*.yml"),
    $L.list_vt_cons(literal_arg(":(glob).github/workflows/*.yaml"),
    $L.list_vt_cons(literal_arg(":(glob).github/actions/*/action.yml"),
    $L.list_vt_cons(literal_arg(":(glob).github/actions/*/action.yaml"),
    $L.list_vt_cons(literal_arg(":(glob)**/package.json"),
    $L.list_vt_cons(literal_arg(":(glob)**/ats2.bats"),
    $L.list_vt_cons(literal_arg(":(glob)**/check-pins-fixture"), $L.list_vt_nil()))))))))))))))
  val out = $A.alloc<byte>(4096)
  val outcome = run_cmd_capture_outcome(nul_git | bv_git, argv, out)
  val @(fz_out, bv_out) = $A.freeze<byte>(out)
  (* each outcome of the run is its own message (capture area, bats#444): git's output is read to its end, so a status is never the cause of a long list *)
  val status = (case+ outcome of
    | ~CaptureLonger(_, _, _) => let
        val () = prerr! ("error: bats check-pins --discover: the files are listed in more than 4096 bytes")
        val () = prerr_newline()
      in 2 end
    | ~CaptureFailed(_, _) => git_failed()
    | ~CaptureReadFailed(_, _) => git_failed()
    | ~CaptureWaitFailed(_, _, _) => git_failed()
    | ~CaptureNotRun(_) => git_failed()
    | ~CaptureFits(listed) =>
      if listed = 0 then let
        val () = prerr! ("error: bats check-pins --discover: the repository has no workflow, action, package.json or ats2.bats to check")
        val () = prerr_newline()
      in 2 end
      else check_files(bv_out, 0, listed, ats2_among(bv_out, 0, listed), 0, 0)): int
  val () = $A.drop<byte>(fz_out, bv_out)
  val () = $A.free<byte>($A.thaw<byte>(fz_out))
  val () = $A.cborrow_drop(fz_git, bv_git)
  val () = $A.barr_free($A.barr_thaw(fz_git))
in status end

(* Runs bats check-pins when that is the command given and answers true; false for any other command *)


implement pins_main () = let
  val buf = $A.alloc<byte>(4096)
  val read = $E.args_read(buf, 4096)
  val @(fz, cmd) = $A.freeze<byte>(buf)
  val handled = (case+ read of
    | ~$R.none() => false
    | ~$R.some(total) => let
        val first = arguments_at(cmd, total)
      in
        if first < 0 then false
        else let
          val () = (if total >= 4096 then let
              val () = prerr! ("error: bats check-pins: the command line is longer than 4095 bytes")
              val () = prerr_newline()
            in set_exit_code(2) end
            else if first >= total then usage_error()
            else if sole_discover(cmd, first, total) then set_exit_code(discover())
            else set_exit_code(check_files(cmd, first, total, ats2_among(cmd, first, total), first, 0)))
        in true end
      end): bool
  val () = $A.drop<byte>(fz, cmd)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
