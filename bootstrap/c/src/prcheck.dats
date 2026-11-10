staload "./prcheck.sats"
staload BATS_SELF = "./prcheck.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "list/src/lib.dats"
staload "result/src/lib.dats"
staload "str/src/lib.dats"
staload "toml/src/lib.dats"
(* prcheck -- bats prcheck --diff <file> --body <file> [--ticket <file>]: what reviews keep finding by hand, as one command (bats-lang/bats#424; keyword: prcheck) *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload L = "list/src/lib.sats"
staload R = "result/src/lib.sats"
staload S = "str/src/lib.sats"
staload T = "toml/src/lib.sats"

staload "helpers.sats"
staload "pins.sats"
staload "merge_proof.sats"

(* ------------------------------------------------------------------ *)
(* State of one run (keyword: prcheck). The checks that are on are the bits of g_on (bit k is check k), the checks that
   found something the bits of g_hits; the file of the diff being read is a span of the diff. *)

val g_on = ref<int>(0)
val g_hits = ref<int>(0)
val g_width = ref<int>(100)
val g_resolve = ref<bool>(false)

(* The resolver a test injects (keyword: prcheck tests): 0 asks gh as the command does, 1 answers that every #<n> is found, 2 that none is *)
val g_resolver = ref<int>(0)

(* Whether the pull request is from a relock/ branch: the daily relock has no ticket of its own, so checks 8 and 10 leave it alone (keyword: prcheck) *)
val g_exempt = ref<bool>(false)
val g_path_at = ref<pos_t>(~1)
val g_path_to = ref<pos_t>(0)
val g_kind = ref<int>(0)
val g_test = ref<bool>(false)
val g_deleted = ref<bool>(false)
val g_first_hunk = ref<bool>(false)
val g_in_hunk = ref<bool>(false)
val g_line = ref<int>(0)
val g_run_end = ref<int>(~10)
val g_run_len = ref<int>(0)
val g_block_end = ref<int>(~10)
val g_exhausted = ref<bool>(false)

(* 2 to the k for a check number 0 to 10 (1 for anything else) *)
fn pow2 (k: int): int =
  if k = 1 then 2 else if k = 2 then 4 else if k = 3 then 8 else if k = 4 then 16 else if k = 5 then 32
  else if k = 6 then 64 else if k = 7 then 128 else if k = 8 then 256 else if k = 9 then 512
  else if k = 10 then 1024 else 1

fn bit_loop (mask: int, k: int): bool = (mask / pow2(k)) mod 2 = 1

fn check_on (k: int): bool = bit_loop(!g_on, k)

fn hit (k: int): void =
  if bit_loop(!g_hits, k) then () else (!g_hits := !g_hits + pow2(k))

(* The flag f (1, 2, 4 or 8) of the flags a body sets *)
fn has_flag (flags: int, f: int): bool = (flags / f) mod 2 = 1

fn with_flag (flags: int, f: int): int = if has_flag(flags, f) then flags else flags + f

(* ------------------------------------------------------------------ *)
(* Bytes (keyword: prcheck). Positions are plain ints: peek reads 0 outside the first m bytes. *)

fn lower (b: int): int = if b >= 65 then (if b <= 90 then b + 32 else b) else b

fn is_digit (b: int): bool = b >= 48 && b <= 57

fn is_alpha (b: int): bool = (b >= 65 && b <= 90) || (b >= 97 && b <= 122)

fn is_alnum (b: int): bool = is_digit(b) || is_alpha(b)

fn is_word (b: int): bool = is_alnum(b) || b = 95

fn is_blank (b: int): bool = b = 32 || b = 9

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

(* The first position at or after p of bv[0, e) that holds no blank, or e (p itself past e) *)
fun skip_blank {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:int | p <= r; r <= max(p, e)] int r =
  if p >= e then p
  else if is_blank(peek(bv, p, e)) then skip_blank(bv, p + 1, e)
  else p

(* The first byte ch at or after p of bv[0, e), or e *)
fun char_end {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, ch: int): [r:int | p <= r; r <= max(p, e)] int r =
  if p >= e then p
  else if peek(bv, p, e) = ch then p
  else char_end(bv, p + 1, e, ch)

(* The end of the run of digits that starts at p *)
fun digits_end {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:int | p <= r; r <= max(p, e)] int r =
  if p >= e then p
  else if is_digit(peek(bv, p, e)) then digits_end(bv, p + 1, e)
  else p

(* The end of the run of letters that starts at p *)
fun alpha_end {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): [r:int | p <= r; r <= max(p, e)] int r =
  if p >= e then p
  else if is_alpha(peek(bv, p, e)) then alpha_end(bv, p + 1, e)
  else p

(* The number the digits from p make, at most 9 of them *)
fun number_of {l:agz}{n:pos}{e:nat | e <= n}{p:int}{k:nat | k <= 9} .<9 - k>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, k: int k, acc: int): int =
  if p >= e then acc
  else if k >= 9 then acc
  else if is_digit(peek(bv, p, e)) then number_of(bv, p + 1, e, k + 1, acc * 10 + (peek(bv, p, e) - 48))
  else acc

(* Whether bv[p, e) starts with the first sn bytes of s, from its byte i on *)
fun lit_here {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn, i: int i): bool =
  if i >= sn then true
  else if p + i >= e then false
  else if peek(bv, p + i, e) = char2int0(string_get_at(s, i)) then lit_here(bv, p, e, s, sn, i + 1)
  else false

(* As lit_here with a letter of bv read in lower case: s is in lower case *)
fun lit_ci {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat}{i:nat | i <= sn} .<sn - i>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn, i: int i): bool =
  if i >= sn then true
  else if p + i >= e then false
  else if lower(peek(bv, p + i, e)) = char2int0(string_get_at(s, i)) then lit_ci(bv, p, e, s, sn, i + 1)
  else false

(* The first position at or after p of bv[0, e) where the sn bytes of s are, or ~1 *)
fun find_sub {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn): [r:int | r == ~1 || (p <= r && r < e)] int r =
  if p >= e then ~1
  else if lit_here(bv, p, e, s, sn, 0) then p
  else find_sub(bv, p + 1, e, s, sn)

fn has_text {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn): bool =
  find_sub(bv, p, e, s, g1u2i(string1_length(s))) >= 0

(* Whether bv[p, e) holds the lower case text s in any case, as a word: no letter, digit or _ on either side *)
fun has_word_ci {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn): bool =
  if p >= e then false
  else if lit_ci(bv, p, e, s, sn, 0) && ~is_word(peek(bv, p - 1, e)) && ~is_word(peek(bv, p + sn, e)) then true
  else has_word_ci(bv, p + 1, e, s, sn)

(* Whether the word s is in bv[p, e) as a pointer: nothing but a stop (, . ; : ) or the end of the text follows it, as in
   "the lock below." and not as in "below the handles", where it says where a thing is *)
fun has_pointer_ci {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn, sn: int sn): bool =
  if p >= e then false
  else if lit_ci(bv, p, e, s, sn, 0) && ~is_word(peek(bv, p - 1, e)) && ~is_word(peek(bv, p + sn, e)) then let
    val q = skip_blank(bv, p + sn, e)
    val c = peek(bv, q, e)
  in
    if q >= e || c = 44 || c = 46 || c = 59 || c = 58 || c = 41 || c = 42 then true
    else has_pointer_ci(bv, p + 1, e, s, sn)
  end
  else has_pointer_ci(bv, p + 1, e, s, sn)

fn pointer_ci {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn): bool =
  has_pointer_ci(bv, p, e, s, g1u2i(string1_length(s)))

fn word_ci {l:agz}{n:pos}{e:nat | e <= n}{p:int}{sn:nat}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, s: string sn): bool =
  has_word_ci(bv, p, e, s, g1u2i(string1_length(s)))

(* Whether bv[a, b) is exactly the lower case text s, in any case *)
fn span_ci {l:agz}{n:pos}{e:nat | e <= n}{a,b:int}{sn:nat}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, e: int e, s: string sn): bool = let
  val len = g1u2i(string1_length(s))
in
  if b - a <> len then false else lit_ci(bv, a, e, s, len, 0)
end

(* Whether bv[a, e) starts with the lower case text s, in any case *)
fn starts_ci {l:agz}{n:pos}{e:nat | e <= n}{a:int}{sn:nat}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e, s: string sn): bool =
  lit_ci(bv, a, e, s, g1u2i(string1_length(s)), 0)

(* Whether bv[at, to) ends with the text s *)
fn ends_with {l:agz}{n:pos}{m:nat | m <= n}{at,to:int}{sn:nat}
  (bv: !$A.borrow(byte, l, n), at: int at, to: int to, m: int m, s: string sn): bool = let
  val len = g1u2i(string1_length(s))
in
  if to - at < len then false else lit_here(bv, to - len, m, s, len, 0)
end

(* ------------------------------------------------------------------ *)
(* Findings (keyword: prcheck): `check <k>: <path>:<line>: <why>` on stdout, and the check's bit set *)

fn found_in {l:agz}{n:pos}{m:nat | m <= n}{k:nat}
  (bv: !$A.borrow(byte, l, n), m: int m, k: int k, line: int, why: string): void = let
  val () = hit(k)
  val () = print! ("check ", k, ": ")
  val () = (if !g_path_at >= 0 then print_borrow(bv, !g_path_at, !g_path_to, m) else print! ("(diff)"))
  val () = print! (":", line, ": ", why)
in print_newline() end

fn found_text {k:nat} (k: int k, place: string, why: string): void = let
  val () = hit(k)
  val () = print! ("check ", k, ": ", place, ": ", why)
in print_newline() end

(* The one-line rule of check k: the text of its finding and of bats prcheck --checklist, one copy (keyword: prcheck checklist) *)
fn rule_of (k: int): [sn:nat] string sn =
  if k = 1 then "a comment goes on over more than one line: it is one line with its keyword"
  else if k = 2 then "a comment states the status of the code: it says what is true, in one line, with its keyword"
  else if k = 3 then "a comment names no CLAUDE.md, rule file, section or place above or below: it carries its reason and a keyword"
  else if k = 4 then "code of ours that is not bats (a script, sed or awk) needs a line Exhausted: <avenue> in the pull request body"
  else if k = 5 then "a symlink escapes the checkout and the review: none is added"
  else if k = 6 then "a workflow or action file has no floating pin (a runner, action or version that moves): check-pins reads it"
  else if k = 7 then "a test asserts no literal, sleeps for no fixed time and bounds no duration with a number"
  else if k = 8 then "This PR closes no ticket. Either it is not finished (finish it on this PR), or the ticket should be broken up first: file the pieces as tickets, then this PR fixes one of them. The body needs a line Fixes #<n>, or No ticket: <reason>."
  else if k = 9 then "the paths: of a rule file cover every file its added text names"
  else "each line of the ticket's Done when is a COMMAND:, MEASURE:, TEST: or SEARCH: line, and the body has a row in ## Done when results for each"

(* ------------------------------------------------------------------ *)
(* Checks 2 and 3: what an added comment or test message may not say (keyword: prcheck) *)

(* Whether bv[p, e) has a date: four digits, a dash, two digits, a dash, two digits *)
fun has_date {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): bool =
  if p + 10 > e then false
  else if is_digit(peek(bv, p, e)) && is_digit(peek(bv, p + 1, e)) && is_digit(peek(bv, p + 2, e))
    && is_digit(peek(bv, p + 3, e)) && peek(bv, p + 4, e) = 45 && is_digit(peek(bv, p + 5, e))
    && is_digit(peek(bv, p + 6, e)) && peek(bv, p + 7, e) = 45 && is_digit(peek(bv, p + 8, e))
    && is_digit(peek(bv, p + 9, e)) && ~is_digit(peek(bv, p - 1, e)) then true
  else has_date(bv, p + 1, e)

(* Whether bv[p, e) has a run id: the word run and five or more digits, or /runs/ *)
fun has_run_id {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): bool =
  if p >= e then false
  else if lit_ci(bv, p, e, "run ", 4, 0) && ~is_word(peek(bv, p - 1, e)) && digits_end(bv, p + 4, e) - (p + 4) >= 5 then true
  else if lit_here(bv, p, e, "/runs/", 6, 0) then true
  else has_run_id(bv, p + 1, e)

(* Whether the comment text bv[a, e) opens with a verdict word and a colon: "Flake:" *)
fn verdict_opener {l:agz}{n:pos}{e:nat | e <= n}{a:int}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e): bool = let
  val s = skip_blank(bv, a, e)
  val w = alpha_end(bv, s, e)
in
  if peek(bv, w, e) <> 58 then false
  else span_ci(bv, s, w, e, "flake") || span_ci(bv, s, w, e, "verdict") || span_ci(bv, s, w, e, "status")
    || span_ci(bv, s, w, e, "update") || span_ci(bv, s, w, e, "result") || span_ci(bv, s, w, e, "fixed")
    || span_ci(bv, s, w, e, "done")
end

(* The message of check 2 for the comment text bv[a, e), or "" when it has none *)
fn status_in {l:agz}{n:pos}{e:nat | e <= n}{a:int}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e): [sn:nat] string sn =
  if has_date(bv, a, e) then "a comment states a date: it says why, not when"
  else if has_run_id(bv, a, e) then "a comment names a run id: the run is not the reason"
  else if verdict_opener(bv, a, e) then "a comment opens with a verdict word (Flake:, Status:): it says why"
  else if word_ci(bv, a, e, "currently") || word_ci(bv, a, e, "temporarily") || word_ci(bv, a, e, "as of")
    || word_ci(bv, a, e, "for now") || word_ci(bv, a, e, "at the moment")
    then rule_of(2)
  else ""

(* The message of check 3 for the text bv[a, e), or "" when it names none of the places a comment may not *)
fn pointer_in {l:agz}{n:pos}{e:nat | e <= n}{a:int}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e): [sn:nat] string sn =
  if has_text(bv, a, e, "CLAUDE.md") then rule_of(3)
  else if has_text(bv, a, e, ".claude/rules") then rule_of(3)
  else if word_ci(bv, a, e, "section") then rule_of(3)
  else if pointer_ci(bv, a, e, "below") then rule_of(3)
  else if pointer_ci(bv, a, e, "above") then rule_of(3)
  else ""

(* ------------------------------------------------------------------ *)
(* Check 3: an issue or pull request that a comment names exists (keyword: prcheck) *)

(* The start of the name that ends before q: letters, digits and - _ . / (p is the lowest it may start) *)
fun name_start {l:agz}{n:pos}{e:nat | e <= n}{q:int} .<max(q, 0)>.
  (bv: !$A.borrow(byte, l, n), q: int q, e: int e): pos_t =
  if q <= 0 then 0
  else let
    val b = peek(bv, q - 1, e)
  in
    if is_alnum(b) || b = 45 || b = 95 || b = 46 || b = 47 then name_start(bv, q - 1, e) else q
  end

(* The path of gh's API for the issue or pull request: the name bv[ns, ne) is owner/repo, or repo (of the owner of --repo),
   or empty (the repository of --repo) *)
fn issue_path {l:agz}{n:pos}{e:nat | e <= n}{ns,ne:int}{lc:agz}
  (bv: !$A.borrow(byte, l, n), ns: int ns, ne: int ne, e: int e, num: int,
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: pos_t): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = bput_v(b, "repos/")
  val slash = char_end(bv, ns, e, 47)
  val owner_end = char_end(cmd, repo_at, 4096, 47)
  val () = (if ne <= ns then copy_to_builder_v(cmd, repo_at, repo_to, 4096, b)
    else if slash < ne then copy_to_builder_v(bv, ns, ne, e, b)
    else let
      val () = copy_to_builder_v(cmd, repo_at, owner_end, 4096, b)
      val () = put_char_v(b, 47)
    in copy_to_builder_v(bv, ns, ne, e, b) end)
  val () = bput_v(b, "/issues/")
  val () = put_int_v(b, num)
in b end

(* Whether gh finds the issue or pull request: one call of gh api *)
fn issue_exists (path: $B.builder_v): bool = let
  val out = $A.alloc<byte>(4096)
  val @(status, _) = tool_output("gh", word("api", word("--silent", $L.list_vt_cons(mk_arg(path), $L.list_vt_nil()))), out)
  val () = $A.free<byte>(out)
in status = 0 end

(* The number of the #<number> of bv[p, e) that gh does not find (one call each) *)
fun refs_in {l:agz}{n:pos}{e:nat | e <= n}{p:int}{lc:agz} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, cmd: !$A.borrow(byte, lc, 4096),
   repo_at: pos_t, repo_to: pos_t, missing: int): int =
  if p >= e then missing
  else if peek(bv, p, e) = 35 && is_digit(peek(bv, p + 1, e)) then let
    val d = digits_end(bv, p + 1, e)
    val ns = name_start(bv, p, e)
    val num = number_of(bv, p + 1, e, 0, 0)
    val exists = (if d - (p + 1) > 7 then false
      else if !g_resolver = 1 then true
      else if !g_resolver = 2 then false
      else issue_exists(issue_path(bv, ns, p, e, num, cmd, repo_at, repo_to)))
  in
    refs_in(bv, d, e, cmd, repo_at, repo_to, (if exists then missing else missing + 1))
  end
  else refs_in(bv, p + 1, e, cmd, repo_at, repo_to, missing)

(* ------------------------------------------------------------------ *)
(* Check 7: what a test asserts (keyword: prcheck) *)

(* The end of the literal that starts at a: digits, a quoted text, or true, false, null, undefined; a when there is none *)
fn literal_end {l:agz}{n:pos}{e:nat | e <= n}{a:int}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e): pos_t = let
  val c = peek(bv, a, e)
in
  if is_digit(c) then digits_end(bv, a, e)
  else if c = 34 || c = 39 || c = 96 then (let val q = char_end(bv, a + 1, e, c) in if q >= e then a else q + 1 end)
  else if is_alpha(c) then (let
      val w = alpha_end(bv, a, e)
    in
      if span_ci(bv, a, w, e, "true") || span_ci(bv, a, w, e, "false") || span_ci(bv, a, w, e, "null")
        || span_ci(bv, a, w, e, "undefined") then w else a
    end)
  else a
end

(* Whether bv[p, e) holds expect( and a literal as the whole argument: expect(true), expect(1), expect("a") *)
fun has_expect_literal {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): bool = let
  val q = find_sub(bv, p, e, "expect(", 7)
in
  if q < 0 then false
  else let
    val a = skip_blank(bv, q + 7, e)
    val b = literal_end(bv, a, e)
  in
    if b > a && peek(bv, skip_blank(bv, b, e), e) = 41 then true
    else has_expect_literal(bv, q + 1, e)
  end
end

(* Whether the line asserts a bound on a time with a number written in it *)
fn fixed_duration {l:agz}{n:pos}{e:nat | e <= n}{s:int}
  (bv: !$A.borrow(byte, l, n), s: int s, e: int e): bool = let
  val less = find_sub(bv, s, e, "toBeLessThan(", 13)
  val more = find_sub(bv, s, e, "toBeGreaterThan(", 16)
  val at = (if less >= 0 then less + 13 else if more >= 0 then more + 16 else ~1): pos_t
in
  if at < 0 then false
  else if ~is_digit(peek(bv, skip_blank(bv, at, e), e)) then false
  else has_text(bv, s, e, "Date.now") || has_text(bv, s, e, "performance.now") || word_ci(bv, s, e, "elapsed")
    || word_ci(bv, s, e, "duration") || word_ci(bv, s, e, "latency") || has_text(bv, s, e, "Time")
end

(* ------------------------------------------------------------------ *)
(* Check 9: a rule file's paths: cover the files its text names (keyword: prcheck) *)

(* Whether the glob gb[pi, pe) matches the path tb[ti, te): ** is any run, * any run without a /, anything else itself.
   gmatch reads the glob at pi and the text at ti; gtry lets the star before pi take the text from ti on. *)
fun gmatch {lg:agz}{ng:pos}{mg:nat | mg <= ng}{lt:agz}{nt:pos}{mt:nat | mt <= nt}{pi,pe,ti,te:nat | pi <= pe; ti <= te; pe <= mg; te <= mt} .<pe - pi, 0, te - ti>.
  (gb: !$A.borrow(byte, lg, ng), pi: int pi, pe: int pe, mg: int mg,
   tb: !$A.borrow(byte, lt, nt), ti: int ti, te: int te, mt: int mt): bool =
  if pi >= pe then ti >= te
  else if peek(gb, pi, mg) = 42 then
    (if pi + 1 < pe then
      (if peek(gb, pi + 1, mg) = 42 then gtry(gb, pi + 2, pe, mg, tb, ti, te, mt, true)
      else gtry(gb, pi + 1, pe, mg, tb, ti, te, mt, false))
    else gtry(gb, pi + 1, pe, mg, tb, ti, te, mt, false))
  else if ti < te then
    (if peek(gb, pi, mg) = peek(tb, ti, mt) then gmatch(gb, pi + 1, pe, mg, tb, ti + 1, te, mt) else false)
  else false

and gtry {lg:agz}{ng:pos}{mg:nat | mg <= ng}{lt:agz}{nt:pos}{mt:nat | mt <= nt}{pi,pe,ti,te:nat | pi <= pe; ti <= te; pe <= mg; te <= mt} .<pe - pi, 1, te - ti>.
  (gb: !$A.borrow(byte, lg, ng), pi: int pi, pe: int pe, mg: int mg,
   tb: !$A.borrow(byte, lt, nt), ti: int ti, te: int te, mt: int mt, deep: bool): bool =
  if gmatch(gb, pi, pe, mg, tb, ti, te, mt) then true
  else if ti >= te then false
  else if ~deep && peek(tb, ti, mt) = 47 then false
  else gtry(gb, pi, pe, mg, tb, ti + 1, te, mt, deep)

(* gmatch for a glob whose bounds are not known to be inside the file: false when they are not *)
fn glob_matches {lg:agz}{ng:pos}{mg:nat | mg <= ng}{lt:agz}{nt:pos}{mt:nat | mt <= nt}{first,last:int}{ts,te:nat | ts <= te; te <= mt}
  (gb: !$A.borrow(byte, lg, ng), first: int first, last: int last, mg: int mg,
   tb: !$A.borrow(byte, lt, nt), ts: int ts, te: int te, mt: int mt): bool =
  if first >= 0 then
    (if first <= last then (if last <= mg then gmatch(gb, first, last, mg, tb, ts, te, mt) else false) else false)
  else false

(* Whether a glob of the list under paths: in the front matter of the rule file gb[0, mg) matches the path tb[ts, te).
   A list item is a line "- glob" (quotes dropped); the list ends at the first line that is not one. *)
fun covered_by {lg:agz}{ng:pos}{mg:nat | mg <= ng}{p:nat | p <= mg}{lt:agz}{nt:pos}{mt:nat | mt <= nt}{ts,te:nat | ts <= te; te <= mt} .<mg - p>.
  (gb: !$A.borrow(byte, lg, ng), p: int p, mg: int mg,
   tb: !$A.borrow(byte, lt, nt), ts: int ts, te: int te, mt: int mt, inside: bool): bool =
  if p >= mg then false
  else let
    val e = line_end(gb, p, mg)
    val a = skip_blank(gb, p, e)
    val next = next_line(gb, p, mg)
  in
    if starts_ci(gb, a, e, "paths:") then covered_by(gb, next, mg, tb, ts, te, mt, true)
    else if inside && peek(gb, a, e) = 45 && is_blank(peek(gb, a + 1, e)) then let
      val gs = skip_blank(gb, a + 2, e)
      val q = peek(gb, gs, e)
      val quoted = (q = 34 || q = 39): bool
      val first = (if quoted then gs + 1 else gs): pos_t
      val last = (if quoted then char_end(gb, first, e, q) else e): pos_t
    in
      if glob_matches(gb, first, last, mg, tb, ts, te, mt) then true
      else covered_by(gb, next, mg, tb, ts, te, mt, inside)
    end
    else if inside && a < e then false
    else covered_by(gb, next, mg, tb, ts, te, mt, inside)
  end

(* Whether bv[p, b) holds only the characters of a path *)
fun path_chars_ok {l:agz}{n:pos}{m:nat | m <= n}{p,b:int} .<max(b - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, b: int b, m: int m): bool =
  if p >= b then true
  else let
    val c = peek(bv, p, m)
  in
    if is_alnum(c) || c = 45 || c = 95 || c = 46 || c = 47 || c = 64 then path_chars_ok(bv, p + 1, b, m) else false
  end

(* The position of the last / of bv[a, p), or ~1 *)
fun last_slash {l:agz}{n:pos}{m:nat | m <= n}{a:int}{p:int} .<max(p - a, 0)>.
  (bv: !$A.borrow(byte, l, n), a: int a, p: int p, m: int m): pos_t =
  if p <= a then ~1
  else if peek(bv, p - 1, m) = 47 then p - 1
  else last_slash(bv, a, p - 1, m)

(* Whether the backticked text bv[a, b) names a file or a directory: it starts with a lower case letter or a dot, has only the
   characters of a path, a / in it, and a dot in its last name or a / at its end *)
fn path_like_in {l:agz}{n:pos}{m:nat | m <= n}{a,b:nat | a <= b; b <= m}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, m: int m): bool =
  if b - a < 3 then false
  else if ~(peek(bv, a, m) = 46 || (peek(bv, a, m) >= 97 && peek(bv, a, m) <= 122)) then false
  else if ~path_chars_ok(bv, a, b, m) then false
  else if find_sub(bv, a, b, "..", 2) >= 0 then false
  else let
    val s = last_slash(bv, a, b, m)
  in
    if s < 0 then false
    else if s = b - 1 then true
    else find_sub(bv, s + 1, b, ".", 1) >= 0
  end

fn path_like {l:agz}{n:pos}{m:nat | m <= n}{a,b:int}
  (bv: !$A.borrow(byte, l, n), a: int a, b: int b, m: int m): bool =
  if a >= 0 then (if a <= b then (if b <= m then path_like_in(bv, a, b, m) else false) else false) else false

(* The paths between backticks on the added line bv[p, e) that no glob of the rule file rb[0, rm) covers, each said; how many *)
fun uncovered_in_line {l:agz}{n:pos}{m:nat | m <= n}{e:nat | e <= m}{p:nat | p <= e}{lr:agz}{nr:pos}{rm:nat | rm <= nr} .<e - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, m: int m, rb: !$A.borrow(byte, lr, nr), rm: int rm,
   at: pos_t, to: pos_t, line: int, count: int): int = let
  val q = char_end(bv, p, e, 96)
in
  if q >= e then count
  else let
    val r = char_end(bv, q + 1, e, 96)
  in
    if r >= e then count
    else if q + 1 <= r && path_like(bv, q + 1, r, m) && ~covered_by(rb, 0, rm, bv, q + 1, r, m, false) then let
      val () = hit(9)
      val () = print! ("check 9: ")
      val () = print_borrow(bv, at, to, m)
      val () = print! (":")
      val () = print! (line)
      val () = print! (": ", rule_of(9), ": the text names ")
      val () = print_borrow(bv, q + 1, r, m)
      val () = print! (", which no glob of paths: covers")
      val () = print_newline()
    in uncovered_in_line(bv, r + 1, e, m, rb, rm, at, to, line, count + 1) end
    else uncovered_in_line(bv, r + 1, e, m, rb, rm, at, to, line, count)
  end
end

(* Check 9 for the line bv[s, e) a diff adds to the rule file the diff header names at bv[at, to): its paths: are read from
   the working tree, and only the text a pull request adds is judged, so a rule file's older text is not charged to it *)
fn check_rule_line {l:agz}{n:pos}{m:nat | m <= n}{at,to:nat | at <= to; to <= m}{s:nat}{e:nat | s <= e; e <= m}
  (bv: !$A.borrow(byte, l, n), at: int at, to: int to, m: int m, s: int s, e: int e, line: int): void =
  if find_sub(bv, s, e, "`", 1) < 0 then ()
  else let
    var path : $B.builder_v = $B.create()
    val () = copy_to_builder_v(bv, at, to, m, path)
    val () = put_char_v(path, 0)
    val @(path_a, path_len) = $B.into_arr(path)
    val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
    val () = (case+ read_whole_m(bv_p, path_len) of
      | ~whole_err(_) => found_in(bv, m, 9, line, "the rule file cannot be read from the working tree")
      | ~whole_ok(ar, piece, size, length) => let
          val @(fz, rb) = $A.freeze<byte>(piece)
          val no_paths = (find_sub(rb, 0, length, "paths:", 6) < 0)
          val () = (if no_paths then found_in(bv, m, 9, line, "the rule file has no paths: list") else ())
          val _ = (if no_paths then 0 else uncovered_in_line(bv, s, e, m, rb, length, at, to, line, 0))
          val () = $A.drop<byte>(fz, rb)
          val () = whole_free(ar, $A.thaw<byte>(fz))
        in () end)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in () end

(* ------------------------------------------------------------------ *)
(* The added line (keyword: prcheck) *)

(* The kinds of file whose comments are read: 1 ATS and Bats (* *), 2 C and JavaScript // and the block comment, 3 # *)
fn kind_of_path {l:agz}{n:pos}{m:nat | m <= n}{at,to:int}
  (bv: !$A.borrow(byte, l, n), at: int at, to: int to, m: int m): int =
  if at < 0 then 0
  else if lit_here(bv, at, m, "bootstrap/c/", 12, 0) || lit_here(bv, at, m, "bats_modules/", 13, 0)
    || lit_here(bv, at, m, "build/", 6, 0) || lit_here(bv, at, m, "node_modules/", 13, 0) then 0
  else if ends_with(bv, at, to, m, ".bats") || ends_with(bv, at, to, m, ".sats") || ends_with(bv, at, to, m, ".dats")
    || ends_with(bv, at, to, m, ".ats") then 1
  else if ends_with(bv, at, to, m, ".js") || ends_with(bv, at, to, m, ".mjs") || ends_with(bv, at, to, m, ".ts")
    || ends_with(bv, at, to, m, ".java") || ends_with(bv, at, to, m, ".kt") || ends_with(bv, at, to, m, ".gradle")
    || ends_with(bv, at, to, m, ".c") || ends_with(bv, at, to, m, ".h") then 2
  else if ends_with(bv, at, to, m, ".py") || ends_with(bv, at, to, m, ".sh") || ends_with(bv, at, to, m, ".yml")
    || ends_with(bv, at, to, m, ".yaml") || ends_with(bv, at, to, m, ".toml") || ends_with(bv, at, to, m, ".bash") then 3
  else 0

(* Whether the path bv[at, to) is a test: under tests/, a .spec. or .test. file, or named test_ or _test *)
fn test_path_in {l:agz}{n:pos}{m:nat | m <= n}{at,to:nat | at <= to; to <= m}
  (bv: !$A.borrow(byte, l, n), at: int at, to: int to, m: int m): bool =
  lit_here(bv, at, m, "tests/", 6, 0) || find_sub(bv, at, to, "/tests/", 7) >= 0 || find_sub(bv, at, to, ".spec.", 6) >= 0
    || find_sub(bv, at, to, ".test.", 6) >= 0 || find_sub(bv, at, to, "_test", 5) >= 0 || find_sub(bv, at, to, "test_", 5) >= 0

fn test_path {l:agz}{n:pos}{m:nat | m <= n}{at,to:int}
  (bv: !$A.borrow(byte, l, n), at: int at, to: int to, m: int m): bool =
  if at >= 0 then (if at <= to then (if to <= m then test_path_in(bv, at, to, m) else false) else false) else false

(* The position of the first // at or after p that starts a comment (the line start s or a blank before it), or ~1 *)
fun find_line_comment {l:agz}{n:pos}{e:nat | e <= n}{s,p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), s: int s, p: int p, e: int e): pos_t =
  if p >= e then ~1
  else if lit_here(bv, p, e, "//", 2, 0) && (p = s || is_blank(peek(bv, p - 1, e))) then p
  else find_line_comment(bv, s, p + 1, e)

(* Where the comment of the added line bv[s, e) starts, or ~1 for none *)
fn comment_start {l:agz}{n:pos}{e:nat | e <= n}{s:int}
  (bv: !$A.borrow(byte, l, n), s: int s, e: int e, kind: int): pos_t =
  if kind = 1 then find_sub(bv, s, e, "(*", 2)
  else if kind = 2 then (let
      val q = find_line_comment(bv, s, s, e)
    in if q >= 0 then q else find_sub(bv, s, e, "/*", 2) end)
  else if kind = 3 then (let
      val b = skip_blank(bv, s, e)
    in if b < e && peek(bv, b, e) = 35 && peek(bv, b + 1, e) <> 33 then b else ~1 end)
  else ~1

(* Check 1 for the comment at cs of the added line bv[s, e): one line, within the width *)
fn comment_shape {l:agz}{n:pos}{m:nat | m <= n}{s:int}{e:nat | s <= e; e <= m}{cs:int}
  (bv: !$A.borrow(byte, l, n), m: int m, s: int s, e: int e, cs: int cs, kind: int, line: int): void = let
  val line_style = (kind = 3 || (kind = 2 && lit_here(bv, cs, e, "//", 2, 0))): bool
  val only = (skip_blank(bv, s, e) = cs): bool
  val unclosed = (if line_style then false
    else if kind = 1 then find_sub(bv, cs + 2, e, "*)", 2) < 0
    else find_sub(bv, cs + 2, e, "*/", 2) < 0): bool
  val () = (if unclosed then found_in(bv, m, 1, line, rule_of(1)) else ())
  val () = (if line_style && only then
      (if !g_run_end = line - 1 then let
          val () = (!g_run_len := !g_run_len + 1)
        in (if !g_run_len = 2 then found_in(bv, m, 1, line, rule_of(1)) else ()) end
      else (!g_run_len := 1))
    else ())
  val () = (if line_style && only then (!g_run_end := line) else ())
  val width = (if only then e - s else e - cs): int
in
  if width > !g_width then found_in(bv, m, 1, line, "a comment is longer than the width of the repository") else ()
end

(* Checks 2 and 3 for the text bv[a, e) of a comment or a test message *)
fn text_checks {l:agz}{n:pos}{m:nat | m <= n}{a:int}{e:nat | e <= m}{lc:agz}
  (bv: !$A.borrow(byte, l, n), m: int m, a: int a, e: int e, line: int,
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: pos_t): void = let
  val () = (if check_on(2) then let
      val why = status_in(bv, a, e)
    in (if string_isnot_empty(why) then found_in(bv, m, 2, line, why) else ()) end else ())
  val () = (if check_on(3) then let
      val why = pointer_in(bv, a, e)
      val () = (if string_isnot_empty(why) then found_in(bv, m, 3, line, why) else ())
    in (if !g_resolve && refs_in(bv, a, e, cmd, repo_at, repo_to, 0) > 0 then
        found_in(bv, m, 3, line, "names an issue or pull request that does not exist") else ()) end else ())
in () end

(* The checks on the added line bv[s, e) of the file the diff header named *)
fn added_line {l:agz}{n:pos}{m:nat | m <= n}{s:nat}{e:nat | s <= e; e <= m}{lc:agz}
  (bv: !$A.borrow(byte, l, n), m: int m, s: int s, e: int e, line: int,
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: pos_t): void = let
  val kind = !g_kind
  val in_block = (!g_block_end = line - 1): bool
  val cs = (if in_block then ~1 else comment_start(bv, s, e, kind)): pos_t
  val () = (if cs >= 0 && check_on(1) then comment_shape(bv, m, s, e, cs, kind, line) else ())
  val ts = (if cs >= 0 then (if kind = 3 then cs + 1 else cs + 2) else e): pos_t
  val () = (if cs >= 0 && ts <= e then text_checks(bv, m, ts, e, line, cmd, repo_at, repo_to) else ())
  (* the later lines of a block comment that went on over lines are comment text too *)
  val () = (if cs >= 0 && ~(kind = 3) && ~(kind = 2 && lit_here(bv, cs, e, "//", 2, 0))
      && find_sub(bv, cs + 2, e, (if kind = 1 then "*)" else "*/"), 2) < 0 then (!g_block_end := line) else ())
  val () = (if in_block then let
      val closer = (if kind = 1 then find_sub(bv, s, e, "*)", 2) else find_sub(bv, s, e, "*/", 2)): pos_t
      val () = (if closer >= 0 then (!g_block_end := ~10) else (!g_block_end := line))
      val () = text_checks(bv, m, s, e, line, cmd, repo_at, repo_to)
    in (if check_on(1) && e - s > !g_width then
        found_in(bv, m, 1, line, "a comment is longer than the width of the repository") else ()) end else ())
  (* a test message: the text of the first string literal of a line of a test *)
  val () = (if !g_test then let
      val q1 = char_end(bv, s, e, 34)
      val q2 = char_end(bv, q1 + 1, e, 34)
    in
      if q1 < e then (if q2 < e then text_checks(bv, m, q1 + 1, q2, line, cmd, repo_at, repo_to) else ()) else ()
    end else ())
  (* check 9: the paths a rule file's added text names *)
  val at = !g_path_at
  val to = !g_path_to
  val () = (if check_on(9) then
      (if at >= 0 then
        (if at <= to then
          (if to <= m then
            (if find_sub(bv, at, to, ".claude/rules/", 14) >= 0 then
              (if ends_with(bv, at, to, m, ".md") then check_rule_line(bv, at, to, m, s, e, line) else ())
            else ())
          else ())
        else ())
      else ())
    else ())
  (* check 4: sed and awk in a script or workflow *)
  val () = (if check_on(4) && ~(!g_exhausted) && kind = 3 && (word_ci(bv, s, e, "sed") || word_ci(bv, s, e, "awk")) then
      found_in(bv, m, 4, line, rule_of(4))
    else ())
  (* check 7: what a test asserts *)
  val () = (if !g_test && check_on(7) && kind = 2 then let
      val () = (if has_expect_literal(bv, s, e) then found_in(bv, m, 7, line, rule_of(7)) else ())
      val () = (if has_text(bv, s, e, "waitForTimeout") then found_in(bv, m, 7, line, rule_of(7)) else ())
      val () = (if fixed_duration(bv, s, e) then found_in(bv, m, 7, line, rule_of(7)) else ())
    in () end else ())
in () end

(* ------------------------------------------------------------------ *)
(* The diff (keyword: prcheck): git diff -U0 --no-renames; the lines of a file are between its diff --git line and the next *)

(* The start of the path of "diff --git a/X b/X" bv[p, e): after the last " b/", or ~1 *)
fun last_b_path {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, best: pos_t): pos_t =
  if p >= e then best
  else if lit_here(bv, p, e, " b/", 3, 0) then last_b_path(bv, p + 1, e, p + 3)
  else last_b_path(bv, p + 1, e, best)

(* The new start of the hunk header bv[p, e): the number after the + *)
fn hunk_start {l:agz}{n:pos}{e:nat | e <= n}{p:int}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): int = let
  val plus = char_end(bv, p, e, 43)
in
  if plus >= e then 0 else number_of(bv, plus + 1, e, 0, 0)
end

(* Whether the path bv[at, to) is a workflow or an action file *)
fn workflow_path {l:agz}{n:pos}{m:nat | m <= n}{at,to:nat | at <= to; to <= m}
  (bv: !$A.borrow(byte, l, n), at: int at, to: int to, m: int m): bool =
  (find_sub(bv, at, to, ".github/workflows/", 18) >= 0 && (ends_with(bv, at, to, m, ".yml") || ends_with(bv, at, to, m, ".yaml")))
    || ends_with(bv, at, to, m, "/action.yml") || ends_with(bv, at, to, m, "/action.yaml")

(* The file-level checks, at the first hunk of a file that is not deleted *)
fn first_hunk {l:agz}{n:pos}{m:nat | m <= n}
  (bv: !$A.borrow(byte, l, n), m: int m): void = let
  val at = !g_path_at
  val to = !g_path_to
in
  if at < 0 then ()
  else if at > to then ()
  else if to > m then ()
  else let
    (* check 6: check-pins reads the whole file in the working tree *)
    val () = (if check_on(6) && workflow_path(bv, at, to, m) then
        (if pins_findings_in_path(bv, at, to, m) <> 0 then found_in(bv, m, 6, 0, rule_of(6)) else ())
      else ())
  in () end
end

(* A line outside a hunk: the header lines of a file, and the header of a hunk *)
fn header_line {l:agz}{n:pos}{m:nat | m <= n}{p:int}{e:nat | e <= m}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e, m: int m): void =
  if lit_here(bv, p, e, "diff --git ", 11, 0) then let
    val b = last_b_path(bv, p, e, ~1)
    val () = (!g_path_at := b)
    val () = (!g_path_to := e)
    val () = (!g_deleted := false)
    val () = (!g_first_hunk := true)
    val () = (!g_in_hunk := false)
    val () = (!g_run_end := ~10)
    val () = (!g_run_len := 0)
    val () = (!g_block_end := ~10)
    val () = (!g_kind := kind_of_path(bv, b, e, m))
    val () = (!g_test := test_path(bv, b, e, m))
  in () end
  else if lit_here(bv, p, e, "new file mode ", 14, 0) then let
    val () = (if lit_here(bv, p, e, "new file mode 120000", 20, 0) then
        (if check_on(5) then found_in(bv, m, 5, 0, rule_of(5)) else ())
      else ())
    val at = !g_path_at
    val to = !g_path_to
  in
    if check_on(4) && ~(!g_exhausted) && at >= 0
      && (ends_with(bv, at, to, m, ".sh") || ends_with(bv, at, to, m, ".py")
        || ends_with(bv, at, to, m, ".awk") || ends_with(bv, at, to, m, ".sed")) then
      found_in(bv, m, 4, 0, rule_of(4))
    else ()
  end
  else if lit_here(bv, p, e, "new mode 120000", 15, 0) then
    (if check_on(5) then found_in(bv, m, 5, 0, rule_of(5)) else ())
  else if lit_here(bv, p, e, "deleted file mode ", 18, 0) then (!g_deleted := true)
  else if lit_here(bv, p, e, "@@ ", 3, 0) then let
    val start = hunk_start(bv, p, e)
    val () = (!g_line := start)
    val () = (!g_in_hunk := true)
  in
    if !g_first_hunk then let
      val () = (!g_first_hunk := false)
    in (if start > 0 && ~(!g_deleted) then first_hunk(bv, m) else ()) end
    else ()
  end
  else ()

fun diff_lines {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m}{lc:agz} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: pos_t): void =
  if p >= m then ()
  else let
    val e = line_end(bv, p, m)
    val c = peek(bv, p, m)
    val () = (if lit_here(bv, p, e, "diff --git ", 11, 0) || lit_here(bv, p, e, "@@ ", 3, 0) || ~(!g_in_hunk) then header_line(bv, p, e, m)
      else if c = 43 then let
          val () = (if p + 1 <= e then added_line(bv, m, p + 1, e, !g_line, cmd, repo_at, repo_to) else ())
        in (!g_line := !g_line + 1) end
      else if c = 32 then (!g_line := !g_line + 1)
      else ())
  in
    if e >= m then () else diff_lines(bv, e + 1, m, cmd, repo_at, repo_to)
  end

(* ------------------------------------------------------------------ *)
(* The pull request body (keyword: prcheck): checks 8 and 10, and the line Exhausted: *)

(* Whether the line text bv[a, e) is a closing line: Fixes, Closes or Resolves (and the other forms GitHub knows), an optional
   colon, and a token that ends in #<number> *)
fn closing_line {l:agz}{n:pos}{e:nat | e <= n}{a:int}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e): bool = let
  val w = alpha_end(bv, a, e)
  val known = (span_ci(bv, a, w, e, "fixes") || span_ci(bv, a, w, e, "closes") || span_ci(bv, a, w, e, "resolves")
    || span_ci(bv, a, w, e, "fix") || span_ci(bv, a, w, e, "close") || span_ci(bv, a, w, e, "resolve")
    || span_ci(bv, a, w, e, "fixed") || span_ci(bv, a, w, e, "closed") || span_ci(bv, a, w, e, "resolved")): bool
in
  if ~known then false
  else let
    val c = (if peek(bv, w, e) = 58 then w + 1 else w): pos_t
    val t = skip_blank(bv, c, e)
    val hash = char_end(bv, t, e, 35)
    val d = digits_end(bv, hash + 1, e)
  in
    if hash >= e then false
    else if d = hash + 1 then false
    else if char_end(bv, t, e, 32) < hash then false
    else ~is_word(peek(bv, d, e))
  end
end

(* The start of the text of a body line, after blanks and the marks of a list or a quote *)
fun line_text_start {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): pos_t =
  if p >= e then p
  else let
    val c = peek(bv, p, e)
  in
    if is_blank(c) || c = 45 || c = 42 || c = 62 then line_text_start(bv, p + 1, e) else p
  end

(* What a body line says: 1 a closing line, 2 No ticket: with a reason, 4 Exhausted: with an avenue, 0 nothing *)
fn body_line_flag {l:agz}{n:pos}{e:nat | e <= n}{p:int}
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): int = let
  val a = line_text_start(bv, p, e)
in
  if closing_line(bv, a, e) then 1
  else if starts_ci(bv, a, e, "no ticket:") && skip_blank(bv, a + 10, e) < e then 2
  else if starts_ci(bv, a, e, "exhausted:") && skip_blank(bv, a + 10, e) < e then 4
  else 0
end

fun body_flags {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, flags: int): int =
  if p >= m then flags
  else let
    val e = line_end(bv, p, m)
    val f = body_line_flag(bv, p, e)
    val flags2 = (if f = 0 then flags else with_flag(flags, f)): int
  in
    if e >= m then flags2 else body_flags(bv, e + 1, m, flags2)
  end

(* ------------------------------------------------------------------ *)
(* Check 10: the ticket's Done when and the body's results (keyword: prcheck) *)

(* The start of the line after the first line of bv[p, m) that starts with the lower case heading, or ~1 *)
fun section_start {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m}{hn:nat} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, heading: string hn): [r:int | ~1 <= r; r <= m] int r =
  if p >= m then ~1
  else let
    val e = line_end(bv, p, m)
  in
    if starts_ci(bv, p, e, heading) then (if e >= m then m else e + 1)
    else if e >= m then ~1
    else section_start(bv, e + 1, m, heading)
  end

(* The start of the text of the list item at the line bv[a, e) (a number and a dot, or a - or * mark), or ~1 for a line that is no item *)
fn item_text {l:agz}{n:pos}{e:nat | e <= n}{a:int}
  (bv: !$A.borrow(byte, l, n), a: int a, e: int e): pos_t = let
  val d = digits_end(bv, a, e)
in
  if d > a && peek(bv, d, e) = 46 && is_blank(peek(bv, d + 1, e)) then skip_blank(bv, d + 1, e)
  else if (peek(bv, a, e) = 45 || peek(bv, a, e) = 42) && is_blank(peek(bv, a + 1, e)) then skip_blank(bv, a + 2, e)
  else ~1
end

fun has_digit {l:agz}{n:pos}{e:nat | e <= n}{p:int} .<max(e - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, e: int e): bool =
  if p >= e then false
  else if is_digit(peek(bv, p, e)) then true
  else has_digit(bv, p + 1, e)

(* Whether the item text bv[t, e) is one of the four forms, with what the form needs: COMMAND: a command in backticks,
   MEASURE: a number, TEST: a name, SEARCH: git grep -n *)
fn item_form_ok {l:agz}{n:pos}{e:nat | e <= n}{t:int}
  (bv: !$A.borrow(byte, l, n), t: int t, e: int e): bool = let
  val w = alpha_end(bv, t, e)
in
  if peek(bv, w, e) <> 58 then false
  else if span_ci(bv, t, w, e, "command") then char_end(bv, w, e, 96) < e
  else if span_ci(bv, t, w, e, "measure") then has_digit(bv, w, e)
  else if span_ci(bv, t, w, e, "test") then skip_blank(bv, w + 1, e) < e
  else if span_ci(bv, t, w, e, "search") then has_text(bv, w, e, "git grep -n")
  else false
end

(* The items of the section bv[p, m) (it ends at the next heading): how many, and how many are not one of the four forms *)
fun section_items {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, items: int, bad: int): @(int, int) =
  if p >= m then @(items, bad)
  else let
    val e = line_end(bv, p, m)
    val a = skip_blank(bv, p, e)
  in
    if peek(bv, a, e) = 35 then @(items, bad)
    else let
      val t = item_text(bv, a, e)
      val items2 = (if t >= 0 then items + 1 else items): int
      val bad2 = (if t >= 0 && ~item_form_ok(bv, t, e) then bad + 1 else bad): int
    in
      if e >= m then @(items2, bad2) else section_items(bv, e + 1, m, items2, bad2)
    end
  end

(* The rows of the results section bv[p, m): the lines that start with a number, after a | or blanks *)
fun section_rows {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, rows: int): int =
  if p >= m then rows
  else let
    val e = line_end(bv, p, m)
    val a = skip_blank(bv, p, e)
    val b = (if peek(bv, a, e) = 124 then skip_blank(bv, a + 1, e) else a): pos_t
  in
    if peek(bv, a, e) = 35 then rows
    else let
      val rows2 = (if is_digit(peek(bv, b, e)) then rows + 1 else rows): int
    in
      if e >= m then rows2 else section_rows(bv, e + 1, m, rows2)
    end
  end

(* Check 10 for the ticket bv_t[0, tm) and the body bv_b[0, bm) *)
fn check_done_when {lb,lt:agz}{nb,nt:pos}{bm:nat | bm <= nb}{tm:nat | tm <= nt}
  (bv_b: !$A.borrow(byte, lb, nb), bm: int bm, bv_t: !$A.borrow(byte, lt, nt), tm: int tm): void = let
  val s = section_start(bv_t, 0, tm, "## done when")
in
  if s < 0 then found_text(10, "ticket", "the ticket has no ## Done when section")
  else let
    val @(items, bad) = section_items(bv_t, s, tm, 0, 0)
    val () = (if items = 0 then found_text(10, "ticket", "the Done when has no list items") else ())
    val () = (if bad > 0 then found_text(10, "ticket", rule_of(10)) else ())
    val r = section_start(bv_b, 0, bm, "## done when results")
  in
    if r < 0 then found_text(10, "body", "the pull request body has no ## Done when results section")
    else if section_rows(bv_b, r, bm, 0) < items then found_text(10, "body", rule_of(10))
    else ()
  end
end

(* ------------------------------------------------------------------ *)
(* All of it (keyword: prcheck) *)

(* A fresh run: no file, no hit *)
fn reset_run (): void = let
  val () = (!g_hits := 0)
  val () = (!g_path_at := ~1)
  val () = (!g_kind := 0)
  val () = (!g_test := false)
  val () = (!g_in_hunk := false)
  val () = (!g_run_end := ~10)
  val () = (!g_run_len := 0)
  val () = (!g_block_end := ~10)
  val () = (!g_exhausted := false)
in () end

(* Runs the checks that are on over the diff bv_d[0, dm), the body bv_b[0, bm) and the ticket bv_t[0, tm); the bits of the checks that found something *)
fn run_checks {ld,lb,lt,lc:agz}{nd,nb,nt:pos}{dm:nat | dm <= nd}{bm:nat | bm <= nb}{tm:nat | tm <= nt}
  (bv_d: !$A.borrow(byte, ld, nd), dm: int dm, bv_b: !$A.borrow(byte, lb, nb), bm: int bm,
   bv_t: !$A.borrow(byte, lt, nt), tm: int tm, has_ticket: bool,
   cmd: !$A.borrow(byte, lc, 4096), repo_at: pos_t, repo_to: pos_t): int = let
  val () = reset_run()
  val flags = body_flags(bv_b, 0, bm, 0)
  val closing = has_flag(flags, 1)
  val no_ticket = has_flag(flags, 2)
  val () = (!g_exhausted := has_flag(flags, 4))
  val () = (if check_on(8) && ~closing && ~no_ticket && ~(!g_exempt) then
      found_text(8, "body", rule_of(8))
    else ())
  val () = (if check_on(10) && ~no_ticket && ~(!g_exempt) then
      (if has_ticket then check_done_when(bv_b, bm, bv_t, tm)
      else found_text(10, "ticket", "the pull request closes a ticket and the ticket text is not given (--ticket)"))
    else ())
  val () = diff_lines(bv_d, 0, dm, cmd, repo_at, repo_to)
in !g_hits end

(* ------------------------------------------------------------------ *)
(* The command line (keyword: prcheck) *)

val g_diff_at = ref<pos_t>(~1)
val g_diff_to = ref<pos_t>(0)
val g_body_at = ref<pos_t>(~1)
val g_body_to = ref<pos_t>(0)
val g_ticket_at = ref<pos_t>(~1)
val g_ticket_to = ref<pos_t>(0)
val g_repo_at = ref<pos_t>(~1)
val g_repo_to = ref<pos_t>(0)
val g_checks_given = ref<bool>(false)
val g_width_given = ref<bool>(false)
val g_checklist = ref<bool>(false)
val g_review_at = ref<pos_t>(~1)
val g_review_to = ref<pos_t>(0)

fn usage_error (): void = let
  val () = prerr! ("usage: bats prcheck --diff <file> --body <file> [--ticket <file>] [--checks \"1 2 ..\"] [--width <n>] [--repo <owner/name>] [--branch <name>] [--resolve]")
  val () = prerr_newline()
  val () = prerr! ("       bats prcheck --checklist [--checks \"1 2 ..\"]: print one line, <n>. <the rule>, for each check that is on; no --diff, --body, --ticket or --resolve")
  val () = prerr_newline()
  val () = prerr! ("       bats prcheck --review <file> [--checks \"1 2 ..\"]: exit 1 unless the review has Reviewer: and Cost: lines and, for each check that is on, the line <n>. <the rule>: checked, ok")
  val () = prerr_newline()
  val () = prerr! ("  --diff: git diff -U0 --no-renames <base>...<head> (without the generated bootstrap/c); --body: the pull request body;")
  val () = prerr_newline()
  val () = prerr! ("  --ticket: the body of the ticket the pull request fixes; --checks: the checks that are on (bats.toml [prcheck] checks);")
  val () = prerr_newline()
  val () = prerr! ("  --width: the width of a comment (bats.toml [prcheck] width, 100); --resolve: look up each #<n> of a comment or test message")
  val () = prerr_newline()
  val () = prerr! ("  with gh api (one call each; needs --repo). Run at the root of the checkout of the head. Exit 0 when no check found anything, 1 when one did, 2 for a usage error.")
  val () = prerr_newline()
in set_exit_code(2) end

fn unreadable (what: string): void = let
  val () = prerr! ("error: bats prcheck: cannot read the file of ", what)
  val () = prerr_newline()
in set_exit_code(2) end

fn flag_is {lc:agz}{at,to:int}{sn:nat}(cmd: !$A.borrow(byte, lc, 4096), at: int at, to: int to, s: string sn): bool = let
  val len = g1u2i(string1_length(s))
in
  if to - at <> len then false else named_file(cmd, at, to, s, len)
end

(* The checks "1 2 10" of bv[p, to) as bits; false for a number that is not a check *)
fun parse_checks {l:agz}{n:pos}{to:nat | to <= n}{p:int} .<max(to - p, 0)>.
  (bv: !$A.borrow(byte, l, n), p: int p, to: int to, cur: int, mask: int): @(bool, int) =
  if p >= to then
    (if cur = 0 then @(true, mask) else if cur > 10 then @(false, mask)
    else @(true, (if bit_loop(mask, cur) then mask else mask + pow2(cur))))
  else let
    val c = peek(bv, p, to)
  in
    if is_digit(c) then parse_checks(bv, p + 1, to, (if cur > 99 then 99 else cur * 10 + (c - 48)), mask)
    else if cur = 0 then parse_checks(bv, p + 1, to, 0, mask)
    else if cur > 10 then @(false, mask)
    else parse_checks(bv, p + 1, to, 0, (if bit_loop(mask, cur) then mask else mask + pow2(cur)))
  end

fun options {lc:agz}{p:nat | p <= 4096} .<4096 - p>.
  (cmd: !$A.borrow(byte, lc, 4096), p: int p, total: int): bool =
  if p >= total then true
  else let
    val z = find_nul(cmd, p)
  in
    if z + 1 > 4096 then false
    else if flag_is(cmd, p, z, "--resolve") then let
      val () = (!g_resolve := true)
    in options(cmd, z + 1, total) end
    else if flag_is(cmd, p, z, "--checklist") then let
      val () = (!g_checklist := true)
    in options(cmd, z + 1, total) end
    else let
      val value_at = z + 1
      val value_to = find_nul(cmd, value_at)
    in
      if value_to + 1 > 4096 then false
      else if value_to = value_at then false
      else if flag_is(cmd, p, z, "--diff") then
        (if !g_diff_at >= 0 then false else let
          val () = (!g_diff_at := value_at)
          val () = (!g_diff_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--body") then
        (if !g_body_at >= 0 then false else let
          val () = (!g_body_at := value_at)
          val () = (!g_body_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--ticket") then
        (if !g_ticket_at >= 0 then false else let
          val () = (!g_ticket_at := value_at)
          val () = (!g_ticket_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--review") then
        (if !g_review_at >= 0 then false else let
          val () = (!g_review_at := value_at)
          val () = (!g_review_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--branch") then let
        val () = (if lit_here(cmd, value_at, value_to, "relock/", 7, 0) then (!g_exempt := true) else ())
      in options(cmd, value_to + 1, total) end
      else if flag_is(cmd, p, z, "--repo") then
        (if !g_repo_at >= 0 then false else let
          val () = (!g_repo_at := value_at)
          val () = (!g_repo_to := value_to)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--width") then
        (if !g_width_given then false
        else if digits_end(cmd, value_at, value_to) <> value_to then false
        else let
          val () = (!g_width := number_of(cmd, value_at, value_to, 0, 0))
          val () = (!g_width_given := true)
        in options(cmd, value_to + 1, total) end)
      else if flag_is(cmd, p, z, "--checks") then
        (if !g_checks_given then false
        else let
          val @(ok, mask) = parse_checks(cmd, value_at, value_to, 0, 0)
        in
          if ~ok then false
          else let
            val () = (!g_on := mask)
            val () = (!g_checks_given := true)
          in options(cmd, value_to + 1, total) end
        end)
      else false
    end
  end

(* The [prcheck] value of key in bats.toml: its length in vbuf, or ~1 when the file or the key is not there *)
fn config_value {lk:agz}{nk:pos}{lv:agz}
  (key: !$A.borrow(byte, lk, nk), klen: int nk, vbuf: !$A.arr(byte, lv, 256)): [k:int | ~1 <= k; k <= 256] int k =
  (case+ read_manifest() of
  | ~$R.ok(doc) => let
      var sec_c = @[char][7]('p', 'r', 'c', 'h', 'e', 'c', 'k')
      val @(fz_s, bv_s) = $A.freeze<byte>($S.from_char_array(sec_c, 7))
      val vr = $T.get(doc, bv_s, 7, key, klen, vbuf, 256)
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
      val () = $T.toml_free(doc)
    in
      (case+ vr of
      | ~$R.some(k) => k
      | ~$R.none() => ~1)
    end
  | ~$R.err(f) => let val () = toml_failure_free(f) in ~1 end)

(* The checks and the width of bats.toml, for those the command line did not give *)
fn config_checks (): void = let
  var key_c = @[char][6]('c', 'h', 'e', 'c', 'k', 's')
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 6))
  val vbuf = $A.alloc<byte>(256)
  val n = config_value(bv_k, 6, vbuf)
  val @(fz_v, bv_v) = $A.freeze<byte>(vbuf)
  val () = (if n >= 0 then let
      val @(ok, mask) = parse_checks(bv_v, 0, n, 0, 0)
    in (if ok then (!g_on := mask) else ()) end else ())
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
in () end

fn config_width (): void = let
  var key_c = @[char][5]('w', 'i', 'd', 't', 'h')
  val @(fz_k, bv_k) = $A.freeze<byte>($S.from_char_array(key_c, 5))
  val vbuf = $A.alloc<byte>(256)
  val n = config_value(bv_k, 5, vbuf)
  val @(fz_v, bv_v) = $A.freeze<byte>(vbuf)
  val () = (if n >= 1 then (if digits_end(bv_v, 0, n) = n then (!g_width := number_of(bv_v, 0, n, 0, 0)) else ()) else ())
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
in () end

(* The file the command line names at cmd[at, to), read whole *)
fn read_span {lc:agz}(cmd: !$A.borrow(byte, lc, 4096), at: pos_t, to: pos_t): whole_file = let
  var path : $B.builder_v = $B.create()
  val () = copy_to_builder_v(cmd, at, to, 4096, path)
  val () = put_char_v(path, 0)
  val @(path_a, path_len) = $B.into_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
  val whole = read_whole_m(bv_p, path_len)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in whole end

(* The ticket file, or the body again when none is named (it is then not read) *)
fn read_ticket {lc:agz}(cmd: !$A.borrow(byte, lc, 4096)): whole_file =
  if !g_ticket_at >= 0 then read_span(cmd, !g_ticket_at, !g_ticket_to) else read_span(cmd, !g_body_at, !g_body_to)

fn no_checks (): void = let
  val () = prerr! ("error: bats prcheck: no check is on: give --checks or set checks in the [prcheck] table of bats.toml")
  val () = prerr_newline()
in set_exit_code(2) end

(* --checklist (keyword: prcheck checklist): a line <n>. <rule> for each check that is on, from check k up to 10 *)
fun checklist_from {k:nat | k <= 11} .<11 - k>. (k: int k): void =
  if k >= 11 then ()
  else let
    val () = (if check_on(k) then println! (k, ". ", rule_of(k)) else ())
  in checklist_from(k + 1) end

(* The exit code of --checklist for the checks that are on: 2 when a file option came with it (given) or no check is on *)
fn checklist_code (on: int, given: bool): int = if given then 2 else if on = 0 then 2 else 0

(* ------------------------------------------------------------------ *)
(* --review (keyword: prcheck review): the check a review is run through before it is posted. The review has a line
   <n>. <the rule> then ": checked, ok" or ": <the finding>" for each check that is on, a Reviewer: line naming the model and
   a Cost: line (tokens and minutes); the rule is the text of --checklist now, so a review made from an older list is stale. *)

val g_review_bad = ref<int>(0)

(* The start of the first line of bv[p, m) that is the line of check k: the number as it is written (1 is not 01 or 10), a dot, a blank *)
fun review_line {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, k: int): [r:int | ~1 <= r; r < m] int r = let
  val e = line_end(bv, p, m)
  val d = digits_end(bv, p, e)
  val width = (if k >= 10 then 2 else 1): int
in
  if p >= m then ~1
  else if d - p = width && number_of(bv, p, e, 0, 0) = k && peek(bv, d, e) = 46 && peek(bv, d + 1, e) = 32 then p
  else if e >= m then ~1
  else review_line(bv, e + 1, m, k)
end

(* Whether a line of bv[p, m) starts with the sn bytes of s and has text after them *)
fun review_key {l:agz}{n:pos}{m:nat | m <= n}{p:nat | p <= m}{sn:nat} .<m - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, m: int m, s: string sn, sn: int sn): bool = let
  val e = line_end(bv, p, m)
in
  if p >= m then false
  else if lit_here(bv, p, e, s, sn, 0) && skip_blank(bv, p + sn, e) < e then true
  else if e >= m then false
  else review_key(bv, e + 1, m, s, sn)
end

(* The end of bv[a, q) without the blanks and carriage returns at its end *)
fun trim_end {l:agz}{n:pos}{e:nat | e <= n}{a:int}{q:nat | q <= e} .<q>.
  (bv: !$A.borrow(byte, l, n), a: int a, q: int q, e: int e): [r:int] int r =
  if q <= 0 then q
  else if q <= a then q
  else if is_blank(peek(bv, q - 1, e)) || peek(bv, q - 1, e) = 13 then trim_end(bv, a, q - 1, e)
  else q

fn review_missing (what: string): void = let
  val () = (!g_review_bad := !g_review_bad + 1)
  val () = print! ("review: no line ", what)
in print_newline() end

(* Where the rule starts on the line of check k that starts at p: after the number, the dot and the blank *)
fn after_number {p:int} (p: int p, k: int): [x:int] int x = if k >= 10 then p + 4 else p + 3

(* The length of s as an int of that value *)
fn text_len {sn:nat} (s: string sn): int sn = g1u2i(string1_length(s))

(* The position after the rule of check k when bv[q, e) starts with it, else ~1 *)
fn rule_end {l:agz}{n:pos}{e:nat | e <= n}{q:int}
  (bv: !$A.borrow(byte, l, n), q: int q, e: int e, k: int): [r:int] int r = let
  val r = rule_of(k)
  val len = text_len(r)
in
  if lit_here(bv, q, e, r, len, 0) then q + len else ~1
end

(* The line of check k in the review: ok, or a finding said on stdout *)
fn review_entry {l:agz}{n:pos}{m:nat | m <= n}
  (bv: !$A.borrow(byte, l, n), m: int m, k: int): void = let
  val p = review_line(bv, 0, m, k)
in
  if p < 0 then let
    val () = (!g_review_bad := !g_review_bad + 1)
    val () = print! ("check ", k, ": review: no line for it")
  in print_newline() end
  else let
    val e = line_end(bv, p, m)
    val q = after_number(p, k)
    val re = rule_end(bv, q, e, k)
  in
    if re < 0 || ~(peek(bv, re, e) = 58 && peek(bv, re + 1, e) = 32) then let
      val () = (!g_review_bad := !g_review_bad + 1)
      val () = print! ("check ", k, ": review: the line is not the rule as the list has it now (a stale list)")
    in print_newline() end
    else let
      val a = re + 2
      val b = trim_end(bv, a, e, e)
    in
      if b - a = 11 && lit_here(bv, a, e, "checked, ok", 11, 0) then ()
      else let
        val () = (!g_review_bad := !g_review_bad + 1)
        val () = print! ("check ", k, ": review: a finding in place of checked, ok: ")
        val () = (if b > a then print_borrow(bv, a, b, m) else ())
      in print_newline() end
    end
  end
end

fun review_entries {l:agz}{n:pos}{m:nat | m <= n}{k:nat | k <= 11} .<11 - k>.
  (bv: !$A.borrow(byte, l, n), m: int m, k: int k): void =
  if k >= 11 then ()
  else let
    val () = (if check_on(k) then review_entry(bv, m, k) else ())
  in review_entries(bv, m, k + 1) end

(* The number of findings of the review bv[0, m): 0 when it has a line for each check that is on, all ok *)
fn review_run {l:agz}{n:pos}{m:nat | m <= n}
  (bv: !$A.borrow(byte, l, n), m: int m): int = let
  val () = (!g_review_bad := 0)
  val () = (if review_key(bv, 0, m, "Reviewer:", 9) then () else review_missing("Reviewer: <the model>"))
  val () = (if review_key(bv, 0, m, "Cost:", 5) then () else review_missing("Cost: <tokens and minutes>"))
  val () = review_entries(bv, m, 1)
in !g_review_bad end

(* The exit code of --review for the checks that are on: 2 when another mode's option came with it (given) or no check is on *)
fn review_code (on: int, given: bool): int = if given then 2 else if on = 0 then 2 else 0

fn run_review {lc:agz}(cmd: !$A.borrow(byte, lc, 4096)): void =
  (case+ read_span(cmd, !g_review_at, !g_review_to) of
  | ~whole_err(_) => unreadable("--review")
  | ~whole_ok(ar, piece, size, len) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val bad = review_run(bv, len)
      val () = (if bad = 0 then println! ("bats prcheck: review ok") else set_exit_code(1))
      val () = $A.drop<byte>(fz, bv)
    in whole_free(ar, $A.thaw<byte>(fz)) end)

(* Reads the files the command names and runs the checks *)
fn run_prcheck{lc:agz}(cmd: !$A.borrow(byte, lc, 4096)): void = let
  val () = (if ~(!g_checks_given) then config_checks() else ())
  val () = (if ~(!g_width_given) then config_width() else ())
  val given = (!g_diff_at >= 0 || !g_body_at >= 0 || !g_ticket_at >= 0 || !g_resolve): bool
in
  if !g_review_at >= 0 then
    (if review_code(!g_on, given || !g_checklist) = 0 then run_review(cmd)
    else if given || !g_checklist then usage_error()
    else no_checks())
  else if !g_checklist then
    (if checklist_code(!g_on, given) = 0 then checklist_from(1)
    else if given then usage_error()
    else no_checks())
  else if !g_diff_at < 0 || !g_body_at < 0 then usage_error()
  else if !g_resolve && !g_repo_at < 0 then usage_error()
  else if !g_on = 0 then no_checks()
  else
    (case+ read_span(cmd, !g_diff_at, !g_diff_to) of
    | ~whole_err(_) => unreadable("--diff")
    | ~whole_ok(ar_d, piece_d, size_d, len_d) =>
      (case+ read_span(cmd, !g_body_at, !g_body_to) of
      | ~whole_err(_) => let
          val () = unreadable("--body")
        in whole_free(ar_d, piece_d) end
      | ~whole_ok(ar_b, piece_b, size_b, len_b) =>
        (case+ read_ticket(cmd) of
        | ~whole_err(_) => let
            val () = unreadable("--ticket")
            val () = whole_free(ar_d, piece_d)
          in whole_free(ar_b, piece_b) end
        | ~whole_ok(ar_t, piece_t, size_t, len_t) => let
            val @(fz_d, bv_d) = $A.freeze<byte>(piece_d)
            val @(fz_b, bv_b) = $A.freeze<byte>(piece_b)
            val @(fz_t, bv_t) = $A.freeze<byte>(piece_t)
            val mask = run_checks(bv_d, len_d, bv_b, len_b, bv_t, len_t, !g_ticket_at >= 0, cmd, !g_repo_at, !g_repo_to)
            val () = (if mask = 0 then println! ("bats prcheck: ok") else set_exit_code(1))
            val () = $A.drop<byte>(fz_d, bv_d)
            val () = $A.drop<byte>(fz_b, bv_b)
            val () = $A.drop<byte>(fz_t, bv_t)
            val () = whole_free(ar_d, $A.thaw<byte>(fz_d))
            val () = whole_free(ar_b, $A.thaw<byte>(fz_b))
          in whole_free(ar_t, $A.thaw<byte>(fz_t)) end)))
end

(* Where the arguments start, or ~1 when argv[1] is not prcheck *)
fn arguments_at {l:agz}
  (cmd: !$A.borrow(byte, l, 4096)): [r:int | r == ~1 || (0 <= r && r <= 4096)] int r = let
  val a = find_nul(cmd, 0) + 1
in
  if a > 4096 then ~1
  else let
    val z = find_nul(cmd, a)
  in
    if z - a <> 7 then ~1
    else if z + 1 > 4096 then ~1
    else if named_file(cmd, a, z, "prcheck", 7) then z + 1
    else ~1
  end
end

(* Runs the command when it is the one given (keyword: prcheck) *)


implement prcheck_main () = let
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
              val () = prerr! ("error: bats prcheck: the command line is longer than 4095 bytes")
              val () = prerr_newline()
            in set_exit_code(2) end
            else if first >= total then usage_error()
            else if options(cmd, first, total) then run_prcheck(cmd)
            else usage_error())
        in true end
      end): bool
  val () = $A.drop<byte>(fz, cmd)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end

(* ------------------------------------------------------------------ *)
(* What the tests of prcheck_tests.bats call (keyword: prcheck tests): they live in a module of their own that does not
   staload helpers.sats, since a module with tests that does sees two declarations of __bats_test and the compiler that
   builds this tree (the seed) binds the implementation to the later one (keyword: test dispatch). *)

(* The checks of the set checks run over a diff, a body and a ticket held in memory (exempt: as a relock branch is);
   the answer is the checks that found something *)



(* The same with the references of comments looked up (--resolve) by an injected resolver that finds every #<n> (found) or none *)



fn fixture_run {a,b,c:nat | a < 4096; b < 4096; c < 4096}
  (diff: string a, body: string b, ticket: string c, checks: int, exempt: bool, resolver: int): int = let
  val @(fz_d, bv_d) = $A.freeze<byte>(str_to_arr4096(diff))
  val @(fz_b, bv_b) = $A.freeze<byte>(str_to_arr4096(body))
  val @(fz_t, bv_t) = $A.freeze<byte>(str_to_arr4096(ticket))
  val @(fz_c, bv_c) = $A.freeze<byte>(str_to_arr4096(""))
  val () = (!g_on := checks)
  val () = (!g_exempt := exempt)
  val () = (!g_resolve := (resolver > 0))
  val () = (!g_resolver := resolver)
  val () = (!g_width := 100)
  val hits = run_checks(bv_d, g1u2i(string1_length(diff)), bv_b, g1u2i(string1_length(body)),
    bv_t, g1u2i(string1_length(ticket)), true, bv_c, ~1, 0)
  val () = (!g_resolver := 0)
  val () = $A.drop<byte>(fz_d, bv_d)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.drop<byte>(fz_t, bv_t)
  val () = $A.drop<byte>(fz_c, bv_c)
  val () = $A.free<byte>($A.thaw<byte>(fz_d))
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
  val () = $A.free<byte>($A.thaw<byte>(fz_t))
  val () = $A.free<byte>($A.thaw<byte>(fz_c))
in hits end

implement prcheck_fixture (diff, body, ticket, checks, exempt) = fixture_run(diff, body, ticket, checks, exempt, 0)

implement prcheck_fixture_resolved (diff, body, ticket, checks, found) =
  fixture_run(diff, body, ticket, checks, false, (if found then 1 else 2))

(* Whether the rule of check k is exactly text (keyword: prcheck checklist) *)


fun same_text {n,m:nat}{i:nat | i <= n} .<n - i>.
  (a: string n, b: string m, n: int n, m: int m, i: int i): bool =
  if i >= n then true
  else if i >= m then false
  else if char2int0(string_get_at(a, i)) = char2int0(string_get_at(b, i)) then same_text(a, b, n, m, i + 1)
  else false

implement prcheck_rule_is (k, text) = let
  val r = rule_of(k)
  val n = g1u2i(string1_length(r))
  val m = g1u2i(string1_length(text))
in
  if n = m then same_text(r, text, n, m, 0) else false
end

(* What --checklist does for the checks (a bit for each, as --checks gives them): the exit code, the lines on stdout *)


implement prcheck_checklist_fixture (checks, given) = let
  val () = (!g_on := checks)
  val code = checklist_code(checks, given)
  val () = (if code = 0 then checklist_from(1) else ())
in code end

(* What --review does for a review held in memory with the checks (a bit for each): 0 when it is complete and all ok, else 1 *)


implement prcheck_review_fixture (review, checks) = let
  val @(fz, bv) = $A.freeze<byte>(str_to_arr4096(review))
  val () = (!g_on := checks)
  val bad = review_run(bv, g1u2i(string1_length(review)))
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in if bad = 0 then 0 else 1 end

(* The mask of the checks the text names ("1 2 10"), or ~1 when it names a number that is no check *)


implement prcheck_checks_fixture (text) = let
  val @(fz, bv) = $A.freeze<byte>(str_to_arr4096(text))
  val @(ok, mask) = parse_checks(bv, 0, g1u2i(string1_length(text)), 0, 0)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in if ok then mask else ~1 end

(* The file at path (and the directory dir) with the text, in the working tree *)


implement prcheck_plant (dir, path, text) = let
  var dir_b : $B.builder_v = $B.create()
  val () = bput_v(dir_b, dir)
  val _ = run_mkdir(dir_b)
  val @(pa, pl) = str_into_arr(path)
  val @(fz, bv) = $A.freeze<byte>(pa)
  var text_b : $B.builder_v = $B.create()
  val () = bput_v(text_b, text)
  val written = (case+ write_file_from_builder_m(bv, pl, text_b) of
    | ~Wrote() => true
    | ~NotWritten(_) => false
    | ~WriteTooLarge() => false): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in written end
