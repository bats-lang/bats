(* overrides -- no implement that replaces what another package implements (bats#421)

   DESIGN CHECK, round 4: declarations only, no bodies (overrides.md).

   A dependency's #pub template is meant to be instantiated by a
   dependent, not replaced by it: 'implement{} $A.word32_rotr_inline ...'
   with another body of the same type passes patsopt, and the body it wrote
   runs at its own call sites (the arith and array repros of bats#421). This
   finds those implements.

   What the build does (experiment, overrides.md): the dats of a file loads a
   dependency's lib.dats without an alias, and that opens none of its names,
   so a bare 'implement{} name' binds only to a declaration of the file's own
   package, never to a dependency's (a dependent may declare and implement a
   name its dependency declares too). What reaches a dependency's name is a
   qualified implement, 'implement{} $A.name', with A bound in the same file
   by '#use P as A' (the sats of the lib file of P), or by 'staload A =
   "<root>/src/m.sats"', or an unaliased staload of a file of another
   package, which opens that file's names unqualified.

   Names declared there are the #pub declarations of the target file alone
   (a module that file staloads is not reached through the alias, E5).

   An implement is a hit when the name is declared there, and the package
   that declares it also implements that name (so a name it leaves for its
   dependents to implement, like promise's dispose, is an extension point
   and not a hit) with no instance, or with the same instance as the implement
   (the instance is the text of the <...> after the name with its blanks
   removed; a type spelled another way is not matched).

   The implement, the binding, the declaration and that implement of the
   declarer must also be live in one build of the four (native or wasm, test
   or not): a #target or $UNITTEST block that the emitter blanks (next_state)
   holds no live fact, so a use the build loads nothing for creates no
   rejection. *)

#include "share/atspre_staload.hats"

#use arith as AR
#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "lexer.sats"
staload "validated.sats"

(* Which of the two listings of the project a file is in: the package's
   own files, or those of ./bats_modules *)
#pub datatype listing = OwnListing | DependencyListing

(* The offset of a path in a NUL-separated file list of at most 524288
   bytes (what recursion.bats's cycle_hits carries), so the driver indexes
   the list with a bound proved by the type *)
#pub typedef path_offset = spos(524288)

(* The number of a package among the np of the project: 0 is the package
   itself, 1 and on the packages of ./bats_modules in the order of the
   listing (their files are together) *)
#pub typedef package_number(np:int) = [i:nat | i < np] int i

(* The bytes of a name, in full: a name of m bytes, 1 <= m <= 524288, the
   most a source of the listing can hold. Names are compared in full, since
   a hit is a hard error and a shared prefix must not cause one *)
#pub datavtype name_bytes =
  | {l:agz}{m:pos | m <= 524288} NameBytes of ($A.arr(byte, l, m), int m)

(* The builds a fact is live in: a #target or $UNITTEST block the emitter
   blanks for a build (next_state) holds no live fact there *)
#pub typedef variants_live = @{native= bool, native_test= bool, wasm= bool, wasm_test= bool}

(* The builds both of a and b are live in *)
#pub fn variants_meet (a: variants_live, b: variants_live): variants_live

(* Whether any build is live *)
#pub fn variants_any (live: variants_live): bool

(* A qualifier of an implement's name: none ('implement{} name') or an alias
   ('implement{} $A.name') *)
#pub datavtype qualifier =
  | Unqualified of ()
  | QualifiedBy of name_bytes

(* The instance of an implement's name: the text of the <...> after it with
   its blanks removed, or none for the template itself *)
#pub datavtype instance_text =
  | NoInstance of ()
  | InstanceText of name_bytes

(* A name that may not be there: none when the bytes are empty or hold a NUL *)
#pub datavtype maybe_name =
  | NameAbsent of ()
  | NameHere of name_bytes

#pub fn name_bytes_free (name: name_bytes): void

(* The name made of the bytes source_bytes[s, e), the blanks left out when
   squeeze *)
#pub fn name_of_range {l:agz}{n:pos}{mb:nat | mb <= n}{s,e:nat | s <= mb; e <= mb}
  (source_bytes: !$A.borrow(byte, l, n), source_size: int mb, s: int s, e: int e, squeeze: bool): maybe_name

(* A name's bytes appended to a builder *)
#pub fn put_name_bytes (name: !name_bytes, out: !$B.builder_v >> $B.builder_v): void

(* What a file says: its facts, each live in some builds *)
#pub datavtype file_fact =
  | DeclaresName of (variants_live, name_bytes) (* a #pub fun, fn, fnx, prfun or prfn, or an 'and' of its group *)
  | ImplementsName of (variants_live, qualifier, name_bytes, instance_text) (* implement, primplement, implmnt *)
  | UsesPackage of (variants_live, name_bytes (* the root *), name_bytes (* the alias *)) (* #use P as A *)
  | AliasesFile of (variants_live, name_bytes (* the alias *), name_bytes (* the path as written *)) (* staload A = "path" *)
  | StaloadsFile of (variants_live, name_bytes (* the path as written *)) (* an unaliased staload "path" *)

#pub datavtype file_facts(int) =
  | file_facts_nil(0) of ()
  | {k:nat} file_facts_cons(k + 1) of (file_fact, file_facts(k))

#pub fun file_facts_free {k:nat} (facts: file_facts(k)): void

(* The facts of the source source_bytes[0, source_length), read from its spans:
   a function of the bytes, so the same source gives the same facts *)
#pub fn facts_of_source {l:agz}{n:pos}{source_length:nat | source_length <= n}
  (source_bytes: !$A.borrow(byte, l, n), source_length: int source_length, source_size: int n)
  : [k:nat] file_facts(k)

(* The facts of the file at the NUL-terminated path path_bytes[0, path_length): the record
   'facts <path>' of build/.bats_valid/ when reuse is true and it holds the
   file's key (validated.bats), else facts_of_source, recorded when the file
   still has the key it was read under; empty for a file that cannot be read *)
#pub fn facts_of_file {lp:agz}{np:pos}{path_length:nat | path_length <= np; path_length <= 524288}
  (reuse: bool, path_bytes: !$A.borrow(byte, lp, np), path_length: int path_length)
  : [k:nat] file_facts(k)

(* A file of the project: its package, its listing, the offset of its path
   in that listing, its path from the package's root (src/lib.bats) and its
   facts *)
#pub datavtype project_file(np:int) =
  | {k:nat} ProjectFile(np) of (package_number(np), listing, path_offset,
                            name_bytes (* path from the package's root *), file_facts(k))

#pub datavtype project_files(np:int, k:int) =
  | project_files_nil(np, 0) of ()
  | {j:nat} project_files_cons(np, j + 1) of (project_file(np), project_files(np, j))

(* The packages of the project: number 0 is the package itself (root
   empty); the others are the packages of ./bats_modules, each with its root
   (the directory between ./bats_modules/ and /src/, which is the name its
   '#use' lines give). np packages, numbered 0 .. np - 1 *)
#pub datavtype package_root(np:int) =
  | PackageRoot(np) of (package_number(np), name_bytes)

#pub datavtype package_roots(np:int, k:int) =
  | package_roots_nil(np, 0) of ()
  | {j:nat} package_roots_cons(np, j + 1) of (package_root(np), package_roots(np, j))

(* The project: np packages and their files *)
#pub datavtype project(np:int) =
  | {j:nat} Project(np) of (package_roots(np, np), project_files(np, j))

(* The project with the package itself alone *)
#pub fn project_new (): project(1)

#pub fun project_free {np:pos} (whole: project(np)): void

(* The number of packages of the project *)
#pub fn project_package_count {np:pos} (whole: !project(np)): int np

(* whole with a package of ./bats_modules of the given root added; its
   number is the np the project had *)
#pub fn project_add_package {np:pos} (whole: project(np), root: name_bytes): project(np + 1)

(* whole with one file added, which belongs to the package number owner, is
   in file_listing at file_offset, and has the path from its package's root
   and the facts given *)
#pub fn project_add_file {np:pos}{k:nat}
  (whole: project(np), owner: package_number(np), file_listing: listing, file_offset: path_offset,
   path_in_package: name_bytes, facts: file_facts(k)): project(np)

(* The package of a root, as a '#use' line gives it *)
#pub datavtype package_lookup(np:int) =
  | PackageFound(np) of package_number(np)
  | PackageMissing(np) of ()

#pub fn package_of_root {np:pos} (whole: !project(np), root: !name_bytes): package_lookup(np)

(* The root of a package (empty for the package itself), for the message
   that names the declaring package *)
#pub fn root_of_package {np:pos} (whole: !project(np), package: package_number(np)): name_bytes

(* A file of the project named by its package, listing and offset *)
#pub datavtype file_ref(np:int) =
  | FileRef(np) of (package_number(np), listing, path_offset)

#pub datavtype file_refs(np:int, k:int) =
  | file_refs_nil(np, 0) of ()
  | {j:nat} file_refs_cons(np, j + 1) of (file_ref(np), file_refs(np, j))

#pub fun file_refs_free {np:int}{k:nat} (refs: file_refs(np, k)): void

(* The files whose #pub declarations a name written in the file by reaches,
   with the qualifier given: for QualifiedBy A, the one file A is bound to in
   by (the lib file of P for '#use P as A', or the file of 'staload A =
   "root/src/m.sats"'); for Unqualified, the files of the unaliased staloads
   of by that leave its package. Only those files: a module that file
   staloads is not reached (E5 of the experiment), so there is no walk to
   end. A binding or a path with no file in the project reaches none *)
#pub fn files_reached {np:pos} (whole: !project(np), by: !file_ref(np), through: !qualifier)
  : [k:nat] file_refs(np, k)

(* An implement that replaces what another package implements: the
   implementing file, the declaring file and the name *)
#pub datavtype foreign_hit(np:int) =
  | ForeignHit(np) of (file_ref(np) (* implementing file *), file_ref(np) (* declaring file *),
                   name_bytes (* the name *))

#pub datavtype foreign_hits(np:int, k:int) =
  | foreign_hits_nil(np, 0) of ()
  | {j:nat} foreign_hits_cons(np, j + 1) of (foreign_hit(np), foreign_hits(np, j))

#pub fun foreign_hits_free {np:int}{k:nat} (hits: foreign_hits(np, k)): void

(* The hits of whole, as the comment at the top says (borrowed: the message
   asks root_of_package for the declaring package's name) *)
#pub fn foreign_hits_of {np:pos} (whole: !project(np)): [k:nat] foreign_hits(np, k)

(* Where an implement of a name is in a source: the keyword's start, the
   name's start and end, for the error that points to each *)
#pub datavtype implement_site =
  | ImplementSite of (pos_t (* keyword start *), pos_t (* name start *), pos_t (* name end *))

#pub datavtype implement_sites(int) =
  | implement_sites_nil(0) of ()
  | {k:nat} implement_sites_cons(k + 1) of (implement_site, implement_sites(k))

#pub fun implement_sites_free {k:nat} (sites: implement_sites(k)): void

#pub fn implement_sites_of {l,la:agz}{n:pos}{source_length:nat | source_length <= n}{m:pos | m <= 524288}
  (source_bytes: !$A.borrow(byte, l, n), source_length: int source_length, source_size: int n,
   wanted: !$A.arr(byte, la, m), wanted_length: int m): [k:nat] implement_sites(k)

(* ============================================================
   Builds: which of the four a fact is live in
   ============================================================ *)

implement variants_meet (a, b) =
  @{native= a.native && b.native, native_test= a.native_test && b.native_test,
    wasm= a.wasm && b.wasm, wasm_test= a.wasm_test && b.wasm_test}

implement variants_any (live) = live.native || live.native_test || live.wasm || live.wasm_test

(* The blanking state of a source in each of the four builds (the emitter's
   ts: above 0 inside a block it blanks) *)
typedef block_states = @{native= int, native_test= int, wasm= int, wasm_test= int}

fn states_start (): block_states = @{native= 0, native_test= 0, wasm= 0, wasm_test= 0}

fn states_live (st: block_states): variants_live =
  @{native= st.native <= 0, native_test= st.native_test <= 0, wasm= st.wasm <= 0, wasm_test= st.wasm_test <= 0}

(* The state after sp in one build whose target is target and which is a test
   build when testing: the emitter's next_state *)
fn state_next {n:int} (sp: !span(n), ts: int, build_target: target, testing: bool): int =
  case+ sp of
  | STargetBegin(_, _, t) =>
    if ts > 0 then ts + 1 else if same_target(t, build_target) then 0 else 1
  | SUnittestBegin(_, _, _, _) => (if ts > 0 then ts + 1 else if testing then 0 else 1)
  | STargetEnd(_, _) => (if ts > 0 then ts - 1 else 0)
  | SUnittestEnd(_, _) => (if ts > 0 then ts - 1 else 0)
  | _ => ts

fn states_next {n:int} (sp: !span(n), st: block_states): block_states =
  @{native= state_next(sp, st.native, Native(), false),
    native_test= state_next(sp, st.native_test, Native(), true),
    wasm= state_next(sp, st.wasm, Wasm(), false),
    wasm_test= state_next(sp, st.wasm_test, Wasm(), true)}

(* ============================================================
   Names
   ============================================================ *)

implement name_bytes_free (name) = let
  val+ ~NameBytes(a, _) = name
in $A.free<byte>(a) end

implement file_facts_free {k} (facts) = let
  fun loop {k:nat} .<k>. (facts: file_facts(k)): void =
    case+ facts of
    | ~file_facts_nil() => ()
    | ~file_facts_cons(f, tl) => let
        val () = (case+ f of
          | ~DeclaresName(_, name) => name_bytes_free(name)
          | ~ImplementsName(_, q, name, inst) => let
              val () = (case+ q of ~Unqualified() => () | ~QualifiedBy(a) => name_bytes_free(a))
              val () = name_bytes_free(name)
            in (case+ inst of ~NoInstance() => () | ~InstanceText(t) => name_bytes_free(t)) end
          | ~UsesPackage(_, root, alias) => let
              val () = name_bytes_free(root)
            in name_bytes_free(alias) end
          | ~AliasesFile(_, alias, path) => let
              val () = name_bytes_free(alias)
            in name_bytes_free(path) end
          | ~StaloadsFile(_, path) => name_bytes_free(path)): void
      in loop(tl) end
in loop(facts) end

(* Whether two names hold the same bytes *)
fun bytes_equal {la,lb:agz}{ma,mb:pos}{i:nat | i <= ma} .<ma - i>.
  (a: !$A.arr(byte, la, ma), ma: int ma, b: !$A.arr(byte, lb, mb), mb: int mb, i: int i): bool =
  if ma <> mb then false
  else if i >= ma then true
  else if i >= mb then false
  else if byte2int0($A.get<byte>(a, i)) = byte2int0($A.get<byte>(b, i)) then bytes_equal(a, ma, b, mb, i + 1)
  else false

fn name_equal (a: !name_bytes, b: !name_bytes): bool = let
  val+ @NameBytes(xa, xm) = a
  val+ @NameBytes(xb, ym) = b
  val r = bytes_equal(xa, xm, xb, ym, 0)
  prval () = fold@(a)
  prval () = fold@(b)
in r end


fun count_kept {l:agz}{n:pos}{mb:nat | mb <= n}{p:nat | p <= n}{e:nat | e <= mb}{kept:int} .<n - p>.
  (bv: !$A.borrow(byte, l, n), mx: int mb, p: int p, e: int e, squeeze: bool, kept: int kept): [r:int] int r =
  if p >= e then kept
  else let
    val c = byte2int0($A.read<byte>(bv, p))
  in
    if c = 0 then ~1
    else if squeeze && (c = 32 || c = 9 || c = 10 || c = 13) then count_kept(bv, mx, p + 1, e, squeeze, kept)
    else count_kept(bv, mx, p + 1, e, squeeze, kept + 1)
  end

(* The kept bytes of src[p, e) written from index i of a *)
fun fill_kept {l:agz}{n:pos}{mb:nat | mb <= n}{p:nat | p <= n}{e:nat | e <= mb}{la:agz}{z:pos}{i:nat | i <= z} .<n - p>.
  (bv: !$A.borrow(byte, l, n), mx: int mb, p: int p, e: int e, squeeze: bool,
   a: !$A.arr(byte, la, z), z: int z, i: int i): void =
  if p >= e then ()
  else if i >= z then ()
  else let
    val b = $A.read<byte>(bv, p)
    val c = byte2int0(b)
  in
    if squeeze && (c = 32 || c = 9 || c = 10 || c = 13) then fill_kept(bv, mx, p + 1, e, squeeze, a, z, i)
    else let
      val () = $A.set<byte>(a, i, b)
    in fill_kept(bv, mx, p + 1, e, squeeze, a, z, i + 1) end
  end

implement name_of_range (bv, mx, s, e, squeeze) = let
  val c = count_kept(bv, mx, s, e, squeeze, 0)
  val size = (if c >= 1 then (if c > 524288 then 524288 else c) else 0): [z:nat | z <= 524288] int z
in
  if size >= 1 then let
    val a = $A.alloc<byte>(size)
    val () = fill_kept(bv, mx, s, e, squeeze, a, size, 0)
  in NameHere(NameBytes(a, size)) end
  else NameAbsent()
end

(* ============================================================
   Reading the facts of a source
   ============================================================ *)

typedef range(n:int) = @(spos(n), spos(n))

(* What a span says, as ranges of the source: a #pub name, an implement
   (its keyword, qualifying alias, name and instance; an alias or instance
   that is not there is the empty range), a #use (package, alias), a
   staload with an alias (alias, path) and one without (path) *)
datavtype raw_fact(n:int) =
  | RawDeclares(n) of (variants_live, range(n))
  | RawImplements(n) of (variants_live, range(n), range(n), range(n), range(n))
  | RawUses(n) of (variants_live, range(n), range(n))
  | RawAliases(n) of (variants_live, range(n), range(n))
  | RawStaloads(n) of (variants_live, range(n))

datavtype raw_facts(n:int, k:int) =
  | raw_facts_nil(n, 0) of ()
  | {k:nat} raw_facts_cons(n, k + 1) of (raw_fact(n), raw_facts(n, k))

fun raw_facts_free {n:int}{k:nat} .<k>. (xs: raw_facts(n, k)): void =
  case+ xs of
  | ~raw_facts_nil() => ()
  | ~raw_facts_cons(f, tl) => let
      val () = (case+ f of
        | ~RawDeclares(_, _) => () | ~RawImplements(_, _, _, _, _) => ()
        | ~RawUses(_, _, _) => () | ~RawAliases(_, _, _) => () | ~RawStaloads(_, _) => ())
    in raw_facts_free(tl) end

fn is_ident_first (c: int): bool = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c = 95

(* The end of the identifier that starts at p, within [p, e) *)
fun ident_stop {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val c = byte2int0($A.read<byte>(bv, p))
  in if is_ident_byte(c) || c = 39 then ident_stop(bv, mx, p + 1, e) else p end

(* The first position of [p, e) past blanks and {...} groups *)
fun head_skip {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e, depth: int): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val c = byte2int0($A.read<byte>(bv, p))
  in
    if c = 123 then head_skip(bv, mx, p + 1, e, depth + 1)
    else if c = 125 then head_skip(bv, mx, p + 1, e, (if depth > 0 then depth - 1 else 0))
    else if depth > 0 then head_skip(bv, mx, p + 1, e, depth)
    else if c = 32 || c = 9 || c = 10 || c = 13 then head_skip(bv, mx, p + 1, e, depth)
    else p
  end

(* The first position of [p, e) past blanks *)
fun blank_skip {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val c = byte2int0($A.read<byte>(bv, p))
  in if c = 32 || c = 9 || c = 10 || c = 13 then blank_skip(bv, mx, p + 1, e) else p end

(* src[p, q) spells the word lit[0, k) *)
fn word_spells {l:agz}{n:pos}{m:nat | m <= n}{p,q:nat | p <= q; q <= m}{k:pos | k <= 16}
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, q: int q, lit: &(@[char][k]), k: int k): bool =
  if q - p <> k then false else lit_at(bv, p, mx, lit, k)

(* Whether src[p, q) is a word that begins an implement: implement,
   primplement, implmnt or primplmnt *)
fn implement_word {l:agz}{n:pos}{m:nat | m <= n}{p,q:nat | p <= q; q <= m}
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, q: int q): bool = let
  var w1 = @[char][9]('i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
  var w2 = @[char][11]('p', 'r', 'i', 'm', 'p', 'l', 'e', 'm', 'e', 'n', 't')
  var w3 = @[char][7]('i', 'm', 'p', 'l', 'm', 'n', 't')
  var w4 = @[char][9]('p', 'r', 'i', 'm', 'p', 'l', 'm', 'n', 't')
in word_spells(bv, mx, p, q, w1, 9) || word_spells(bv, mx, p, q, w2, 11)
   || word_spells(bv, mx, p, q, w3, 7) || word_spells(bv, mx, p, q, w4, 9) end

(* The position past the '>' that closes the '<' at p (within [p, e)), or
   p when none does *)
fun angle_end {l:agz}{n:pos}{m:nat | m <= n}{q,e:nat | q <= e; e <= m} .<e - q>.
  (bv: !$A.borrow(byte, l, n), mx: int m, q: int q, e: int e, depth: int): [r:nat | r <= e] int r =
  if q >= e then 0
  else let
    val c = byte2int0($A.read<byte>(bv, q))
  in
    if c = 60 then angle_end(bv, mx, q + 1, e, depth + 1)
    else if c = 62 then (if depth <= 1 then q + 1 else angle_end(bv, mx, q + 1, e, depth - 1))
    else angle_end(bv, mx, q + 1, e, depth)
  end

(* The instance after a name that ends at ne within [ne, e): the text
   between the '<' (after blanks) and its '>', as a range; the empty range
   at ne when none *)
fn instance_after {l:agz}{n:pos}{m:nat | m <= n}{ne,e:nat | ne <= e; e <= m}
  (bv: !$A.borrow(byte, l, n), mx: int m, ne: int ne, e: int e): range(n) = let
  val p = blank_skip(bv, mx, ne, e)
in
  if p < e then
    (if byte2int0($A.read<byte>(bv, p)) = 60 then let
       val q = angle_end(bv, mx, p + 1, e, 1)
     in if q > p + 2 then @(p + 1, q - 1) else @(ne, ne) end
     else @(ne, ne))
  else @(ne, ne)
end

(* The facts of the code src[p, e) with live builds live: the implements
   whose names are in it. Whether the code ends where a name is awaited (an
   implement keyword, then blanks and braces), with the keyword's range *)
fun scan_code {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m}{k:nat} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e, live: variants_live,
   acc: raw_facts(n, k), awaiting: range(n), waiting: bool)
  : [k2:nat] @(raw_facts(n, k2), bool, range(n)) =
  if p >= e then @(acc, waiting, awaiting)
  else let
    val c = byte2int0($A.read<byte>(bv, p))
  in
    if ~is_ident_first(c) then scan_code(bv, mx, p + 1, e, live, acc, awaiting, false)
    else let
      val q = ident_stop(bv, mx, p + 1, e)
      val before = (if p = 0 then 0 else byte2int0($A.read<byte>(bv, p - 1))): int
      val joined = (p > 0) && (is_ident_byte(before) || before = 39 || before = 46 || before = 36)
    in
      if joined then scan_code(bv, mx, q, e, live, acc, awaiting, false)
      else if implement_word(bv, mx, p, q) then let
        val ns = head_skip(bv, mx, q, e, 0)
      in
        if ns >= e then @(acc, true, @(p, q))
        else if is_ident_first(byte2int0($A.read<byte>(bv, ns))) then let
          val ne = ident_stop(bv, mx, ns + 1, e)
          val inst = instance_after(bv, mx, ne, e)
          val f = RawImplements(live, @(p, q), @(ns, ns), @(ns, ne), inst)
        in scan_code(bv, mx, ne, e, live, raw_facts_cons(f, acc), awaiting, false) end
        else scan_code(bv, mx, q, e, live, acc, awaiting, false)
      end
      else scan_code(bv, mx, q, e, live, acc, awaiting, false)
    end
  end

(* p + 2, or e when that is past e *)
fn after_two {p,e:nat | p < e} (p: int p, e: int e): [q:nat | p < q; q <= e] int q =
  if p + 2 <= e then p + 2 else e

(* The position past the quote that closes the string whose contents start at p *)
fun string_past {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else let
    val b = byte2int0($A.read<byte>(bv, p))
  in
    if b = 92 then (if p + 2 <= e then string_past(bv, mx, p + 2, e) else e)
    else if b = 34 then p + 1
    else string_past(bv, mx, p + 1, e)
  end

(* The end of the line that p is in, within [p, e) *)
fun line_end {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e): [q:nat | p <= q; q <= e] int q =
  if p >= e then p
  else if byte2int0($A.read<byte>(bv, p)) = 10 then p
  else line_end(bv, mx, p + 1, e)

(* The names a #pub declaration src[p, e) declares, as ranges: the one after
   its first word when that is fun, fn, fnx, prfun or prfn, and the one after
   each 'and' word of its group. Comments and strings are skipped; inside
   a comment depth is counted *)
fun pub_names {l:agz}{n:pos}{m:nat | m <= n}{p,e:nat | p <= e; e <= m}{k:nat} .<e - p>.
  (bv: !$A.borrow(byte, l, n), mx: int m, p: int p, e: int e, live: variants_live,
   comment: int, acc: raw_facts(n, k)): [k2:nat] raw_facts(n, k2) =
  if p >= e then acc
  else let
    val c = byte2int0($A.read<byte>(bv, p))
    val d = (if p + 1 < e then byte2int0($A.read<byte>(bv, p + 1)) else 0): int
  in
    if c = 40 && d = 42 then pub_names(bv, mx, after_two(p, e), e, live, comment + 1, acc)
    else if comment > 0 && c = 42 && d = 41 then pub_names(bv, mx, after_two(p, e), e, live, comment - 1, acc)
    else if comment > 0 then pub_names(bv, mx, p + 1, e, live, comment, acc)
    else if c = 34 then pub_names(bv, mx, string_past(bv, mx, p + 1, e), e, live, comment, acc)
    else if c = 47 && d = 47 then pub_names(bv, mx, line_end(bv, mx, after_two(p, e), e), e, live, comment, acc)
    else if ~is_ident_first(c) then pub_names(bv, mx, p + 1, e, live, comment, acc)
    else let
      val q = ident_stop(bv, mx, p + 1, e)
      val before = (if p = 0 then 0 else byte2int0($A.read<byte>(bv, p - 1))): int
      val joined = (p > 0) && (is_ident_byte(before) || before = 39 || before = 46 || before = 36)
      var and_w = @[char][3]('a', 'n', 'd')
    in
      if ~joined && word_spells(bv, mx, p, q, and_w, 3) then let
        val ns = head_skip(bv, mx, q, e, 0)
      in
        if ns >= e then pub_names(bv, mx, q, e, live, comment, acc)
        else if ~is_ident_first(byte2int0($A.read<byte>(bv, ns))) then pub_names(bv, mx, q, e, live, comment, acc)
        else let
          val ne = ident_stop(bv, mx, ns + 1, e)
        in pub_names(bv, mx, ne, e, live, comment, raw_facts_cons(RawDeclares(live, @(ns, ne)), acc)) end
      end
      else pub_names(bv, mx, q, e, live, comment, acc)
    end
  end

(* The first name of a #pub declaration whose contents start at cs: after its
   first word when that is one of fun, fn, fnx, prfun, prfn *)
fn pub_first {l:agz}{n:pos}{m:nat | m <= n}{cs,e:nat | cs <= e; e <= m}{k:nat}
  (bv: !$A.borrow(byte, l, n), mx: int m, cs: int cs, e: int e, live: variants_live, acc: raw_facts(n, k))
  : [k2:nat] raw_facts(n, k2) = let
  val q = ident_stop(bv, mx, cs, e)
  var w_fun = @[char][3]('f', 'u', 'n')
  var w_fn = @[char][2]('f', 'n')
  var w_fnx = @[char][3]('f', 'n', 'x')
  var w_prfun = @[char][5]('p', 'r', 'f', 'u', 'n')
  var w_prfn = @[char][4]('p', 'r', 'f', 'n')
  val declares = word_spells(bv, mx, cs, q, w_fun, 3) || word_spells(bv, mx, cs, q, w_fn, 2)
                 || word_spells(bv, mx, cs, q, w_fnx, 3) || word_spells(bv, mx, cs, q, w_prfun, 5)
                 || word_spells(bv, mx, cs, q, w_prfn, 4)
in
  if ~declares then acc
  else let
    val ns = head_skip(bv, mx, q, e, 0)
    val first = (if ns < e then (if is_ident_first(byte2int0($A.read<byte>(bv, ns))) then
                   RawDeclares(live, @(ns, ident_stop(bv, mx, ns + 1, e)))
                 else RawDeclares(live, @(ns, ns))) else RawDeclares(live, @(ns, ns))): raw_fact(n)
    val rest = pub_names(bv, mx, q, e, live, 0, acc)
  in raw_facts_cons(first, rest) end
end

(* The path of the string literal at q (a quote) within [q, e): its contents
   as a range; the empty range at q when there is none *)
fn string_contents {l:agz}{n:pos}{m:nat | m <= n}{q,e:nat | q <= e; e <= m}
  (bv: !$A.borrow(byte, l, n), mx: int m, q: int q, e: int e): range(n) =
  if q < e then
    (if byte2int0($A.read<byte>(bv, q)) = 34 then let
       val close = string_past(bv, mx, q + 1, e)
     in if close >= q + 2 then @(q + 1, close - 1) else @(q, q) end
     else @(q, q))
  else @(q, q)

(* The fact of the staload line src[s, e): 'staload "path"' loads without an
   alias, 'staload A = "path"' with one *)
fn staload_fact {l:agz}{n:pos}{m:nat | m <= n}{s,e:nat | s <= m; e <= m}{k:nat}
  (bv: !$A.borrow(byte, l, n), mx: int m, s: int s, e: int e, live: variants_live, acc: raw_facts(n, k))
  : [k2:nat] raw_facts(n, k2) =
  if s + 7 > e then acc
  else let
    val p = blank_skip(bv, mx, s + 7, e)
  in
    if p >= e then acc
    else if byte2int0($A.read<byte>(bv, p)) = 34 then let
      val path = string_contents(bv, mx, p, e)
    in raw_facts_cons(RawStaloads(live, path), acc) end
    else if is_ident_first(byte2int0($A.read<byte>(bv, p))) then let
      val ae = ident_stop(bv, mx, p + 1, e)
      val eq = blank_skip(bv, mx, ae, e)
    in
      if eq >= e then acc
      else if byte2int0($A.read<byte>(bv, eq)) = 61 then let
        val q = blank_skip(bv, mx, eq + 1, e)
        val path = string_contents(bv, mx, q, e)
      in raw_facts_cons(RawAliases(live, @(p, ae), path), acc) end
      else acc
    end
    else acc
  end

(* What one span adds to the facts: acc, whether the span ends where an
   implement's name is awaited, and the keyword's range. next is the span
   after it, where a qualified implement's instance starts *)
fn scan_one {l:agz}{n:pos}{k,j:nat}
  (bv: !$A.borrow(byte, l, n), mx: int n, sp: !span(n), next: !spans(n, j), live: variants_live,
   waiting: bool, awaiting: range(n), acc: raw_facts(n, k))
  : [k2:nat] @(raw_facts(n, k2), bool, range(n)) =
  case+ sp of
  | SPass(s, e, verbatim) =>
    if verbatim then @(acc, false, awaiting)
    else scan_code(bv, mx, s, e, live, acc, awaiting, false)
  | SUse(_, _, _, ps, pe, as0, ae) =>
    @(raw_facts_cons(RawUses(live, @(ps, pe), @(as0, ae)), acc), false, awaiting)
  | SPub(_, e, restricted, cs) =>
    if restricted then @(acc, false, awaiting)
    else let val acc2 = pub_first(bv, mx, cs, e, live, acc) in @(acc2, false, awaiting) end
  | SStaload(s, e) => let val acc2 = staload_fact(bv, mx, s, e, live, acc) in @(acc2, false, awaiting) end
  | SQual(_, _, as0, ae, ms, me) =>
    if waiting then let
      val inst = (case+ next of
        | spans_cons(nx, _) => (case+ nx of
            | SPass(s2, e2, v2) => (if v2 then @(ms, ms) else instance_after(bv, mx, s2, e2))
            | _ => @(ms, ms))
        | spans_nil() => @(ms, ms)): range(n)
      val f = RawImplements(live, awaiting, @(as0, ae), @(ms, me), inst)
    in @(raw_facts_cons(f, acc), false, awaiting) end
    else @(acc, false, awaiting)
  | _ => @(acc, false, awaiting)

fun scan_spans {l:agz}{n:pos}{k,j:nat} .<j>.
  (bv: !$A.borrow(byte, l, n), mx: int n, xs: !spans(n, j), states: block_states,
   waiting: bool, awaiting: range(n), acc: raw_facts(n, k)): [k2:nat] raw_facts(n, k2) =
  case+ xs of
  | spans_nil() => acc
  | spans_cons(sp, tl) => let
      val @(acc2, waiting2, awaiting2) = scan_one(bv, mx, sp, tl, states_live(states), waiting, awaiting, acc)
    in scan_spans(bv, mx, tl, states_next(sp, states), waiting2, awaiting2, acc2) end

(* The name src[r] holds, with its blanks kept *)
fn name_in {l:agz}{n:pos} (bv: !$A.borrow(byte, l, n), mx: int n, r: range(n)): maybe_name =
  name_of_range(bv, mx, r.0, r.1, false)

(* The fact xs makes when its names are there, added to acc *)
fn materialize {l:agz}{n:pos}{k:nat}
  (bv: !$A.borrow(byte, l, n), mx: int n, f: raw_fact(n), acc: file_facts(k)): [k2:nat] file_facts(k2) =
  case+ f of
  | ~RawDeclares(live, r) => (case+ name_in(bv, mx, r) of
      | ~NameAbsent() => acc
      | ~NameHere(name) => file_facts_cons(DeclaresName(live, name), acc))
  | ~RawImplements(live, _, alias, name, inst) => (case+ name_in(bv, mx, name) of
      | ~NameAbsent() => acc
      | ~NameHere(nm) => let
          val q = (case+ name_in(bv, mx, alias) of
            | ~NameAbsent() => Unqualified()
            | ~NameHere(a) => QualifiedBy(a)): qualifier
          val i = (case+ name_of_range(bv, mx, inst.0, inst.1, true) of
            | ~NameAbsent() => NoInstance()
            | ~NameHere(t) => InstanceText(t)): instance_text
        in file_facts_cons(ImplementsName(live, q, nm, i), acc) end)
  | ~RawUses(live, pkg, alias) => (case+ name_in(bv, mx, pkg) of
      | ~NameAbsent() => acc
      | ~NameHere(root) => (case+ name_in(bv, mx, alias) of
          | ~NameAbsent() => let val () = name_bytes_free(root) in acc end
          | ~NameHere(a) => file_facts_cons(UsesPackage(live, root, a), acc)))
  | ~RawAliases(live, alias, path) => (case+ name_in(bv, mx, alias) of
      | ~NameAbsent() => acc
      | ~NameHere(a) => (case+ name_in(bv, mx, path) of
          | ~NameAbsent() => let val () = name_bytes_free(a) in acc end
          | ~NameHere(p) => file_facts_cons(AliasesFile(live, a, p), acc)))
  | ~RawStaloads(live, path) => (case+ name_in(bv, mx, path) of
      | ~NameAbsent() => acc
      | ~NameHere(p) => file_facts_cons(StaloadsFile(live, p), acc))

fun materialize_all {l:agz}{n:pos}{j,k:nat} .<j>.
  (bv: !$A.borrow(byte, l, n), mx: int n, xs: raw_facts(n, j), acc: file_facts(k)): [k2:nat] file_facts(k2) =
  case+ xs of
  | ~raw_facts_nil() => acc
  | ~raw_facts_cons(f, tl) => materialize_all(bv, mx, tl, materialize(bv, mx, f, acc))

implement facts_of_source (source_bytes, source_length, source_size) = let
  val xs = lex_spans(source_bytes, source_length, source_size)
  val raws = scan_spans(source_bytes, source_size, xs, states_start(), false, @(0, 0), raw_facts_nil())
  val () = spans_free(xs)
in materialize_all(source_bytes, source_size, raws, file_facts_nil()) end

implement implement_sites_free {k} (sites) = let
  fun loop {k:nat} .<k>. (sites: implement_sites(k)): void =
    case+ sites of
    | ~implement_sites_nil() => ()
    | ~implement_sites_cons(~ImplementSite(_, _, _), tl) => loop(tl)
in loop(sites) end

(* Whether src[s, s + m) holds the m bytes of a *)
fun range_holds {l:agz}{n:pos}{la:agz}{m:pos}{s:nat | s + m <= n}{i:nat | i <= m} .<m - i>.
  (bv: !$A.borrow(byte, l, n), mx: int n, s: int s, a: !$A.arr(byte, la, m), m: int m, i: int i): bool =
  if i >= m then true
  else if byte2int0($A.read<byte>(bv, s + i)) = byte2int0($A.get<byte>(a, i)) then range_holds(bv, mx, s, a, m, i + 1)
  else false

fun sites_in {l:agz}{n:pos}{la:agz}{m:pos}{j,k:nat} .<j>.
  (bv: !$A.borrow(byte, l, n), mx: int n, xs: raw_facts(n, j), a: !$A.arr(byte, la, m), m: int m,
   acc: implement_sites(k)): [k2:nat] implement_sites(k2) =
  case+ xs of
  | ~raw_facts_nil() => acc
  | ~raw_facts_cons(f, tl) => let
      val acc2 = (case+ f of
        | ~RawImplements(live, kw, _, name, _) => let
            val @(kw_start, _) = kw
            val @(name_start, name_end) = name
          in
            if ~variants_any(live) then acc
            else if name_end - name_start <> m then acc
            else if name_start + m > mx then acc
            else if range_holds(bv, mx, name_start, a, m, 0)
            then implement_sites_cons(ImplementSite(kw_start, name_start, name_end), acc)
            else acc
          end
        | ~RawDeclares(_, _) => acc | ~RawUses(_, _, _) => acc
        | ~RawAliases(_, _, _) => acc | ~RawStaloads(_, _) => acc): [k2:nat] implement_sites(k2)
    in sites_in(bv, mx, tl, a, m, acc2) end

implement implement_sites_of (source_bytes, source_length, source_size, wanted, wanted_length) = let
  val xs = lex_spans(source_bytes, source_length, source_size)
  val raws = scan_spans(source_bytes, source_size, xs, states_start(), false, @(0, 0), raw_facts_nil())
  val () = spans_free(xs)
in sites_in(source_bytes, source_size, raws, wanted, wanted_length, implement_sites_nil()) end

(* ============================================================
   The record of a file's facts (validated.bats, the 'facts' records)
   ============================================================ *)

(* The builds a fact is live in, as the byte a record keeps them in: the
   sum of 1 (native), 2 (native test), 4 (wasm) and 8 (wasm test), plus 'a' *)
fn bit_of (on: bool, value: int): int = if on then value else 0

fn live_byte (live: variants_live): int =
  97 + bit_of(live.native, 1) + bit_of(live.native_test, 2) + bit_of(live.wasm, 4) + bit_of(live.wasm_test, 8)

fn byte_live (b: int): variants_live = let
  val v = b - 97
in
  @{native= (v >= 0 && v < 16) && (v % 2 = 1), native_test= (v >= 0 && v < 16) && ((v / 2) % 2 = 1),
    wasm= (v >= 0 && v < 16) && ((v / 4) % 2 = 1), wasm_test= (v >= 0 && v < 16) && ((v / 8) % 2 = 1)}
end

fun put_bytes_nul {la:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (a: !$A.arr(byte, la, m), m: int m, i: int i, out: !$B.builder_v >> $B.builder_v): void =
  if i >= m then put_char_v(out, 0)
  else let
    val () = put_char_v(out, byte2int0($A.get<byte>(a, i)))
  in put_bytes_nul(a, m, i + 1, out) end

fn put_name_nul (name: !name_bytes, out: !$B.builder_v >> $B.builder_v): void = let
  val+ @NameBytes(a, m) = name
  val () = put_bytes_nul(a, m, 0, out)
  prval () = fold@(name)
in end

implement put_name_bytes (name, out) = let
  val+ @NameBytes(a, m) = name
  fun loop {la:agz}{m:pos}{i:nat | i <= m} .<m - i>.
    (a: !$A.arr(byte, la, m), m: int m, i: int i, out: !$B.builder_v >> $B.builder_v): void =
    if i >= m then ()
    else let
      val () = put_char_v(out, byte2int0($A.get<byte>(a, i)))
    in loop(a, m, i + 1, out) end
  val () = loop(a, m, 0, out)
  prval () = fold@(name)
in end

fn put_empty_nul (out: !$B.builder_v >> $B.builder_v): void = put_char_v(out, 0)

fn put_implement (live: variants_live, q: !qualifier, name: !name_bytes, inst: !instance_text,
                  out: !$B.builder_v >> $B.builder_v): void = let
  val () = put_char_v(out, 73)
  val () = put_char_v(out, live_byte(live))
  val () = (case+ q of Unqualified() => put_empty_nul(out) | QualifiedBy(a) => put_name_nul(a, out))
  val () = put_name_nul(name, out)
in (case+ inst of NoInstance() => put_empty_nul(out) | InstanceText(t) => put_name_nul(t, out)) end

(* The record body of the facts: for each, its tag, its builds and its
   fields, each field NUL-ended *)
fn put_fact (f: !file_fact, out: !$B.builder_v >> $B.builder_v): void =
  case+ f of
  | DeclaresName(live, name) => let
      val () = put_char_v(out, 68)
      val () = put_char_v(out, live_byte(live))
    in put_name_nul(name, out) end
  | ImplementsName(live, q, name, inst) => put_implement(live, q, name, inst, out)
  | UsesPackage(live, root, alias) => let
      val () = put_char_v(out, 85)
      val () = put_char_v(out, live_byte(live))
      val () = put_name_nul(root, out)
    in put_name_nul(alias, out) end
  | AliasesFile(live, alias, path) => let
      val () = put_char_v(out, 65)
      val () = put_char_v(out, live_byte(live))
      val () = put_name_nul(alias, out)
    in put_name_nul(path, out) end
  | StaloadsFile(live, path) => let
      val () = put_char_v(out, 83)
      val () = put_char_v(out, live_byte(live))
    in put_name_nul(path, out) end

fun put_facts {k:nat} .<k>. (facts: !file_facts(k), out: !$B.builder_v >> $B.builder_v): void =
  case+ facts of
  | file_facts_nil() => ()
  | file_facts_cons(f, tl) => let
      val () = put_fact(f, out)
    in put_facts(tl, out) end

(* What a record's tag byte stands for *)
datatype fact_tag = TagDeclares | TagImplements | TagUses | TagAliases | TagStaloads | TagUnknown

fn tag_of (b: int): fact_tag =
  if b = 68 then TagDeclares() else if b = 73 then TagImplements()
  else if b = 85 then TagUses() else if b = 65 then TagAliases()
  else if b = 83 then TagStaloads() else TagUnknown()

fn free_maybe (f: maybe_name): void =
  case+ f of ~NameAbsent() => () | ~NameHere(a) => name_bytes_free(a)

(* The field of the record body bv[0, len) that starts at off: its bytes
   (none when empty) and where the next field starts, which is past off; no
   field when it has no NUL *)
datavtype field_result(off:int, len:int) =
  | FieldMissing(off, len) of ()
  | {nx:nat | off < nx; nx <= len} FieldHere(off, len) of (maybe_name, int nx)

fn field_at {l:agz}{n:pos}{m:nat | m <= n}{len:nat | len <= m}{off:nat | off <= len}
  (bv: !$A.borrow(byte, l, n), mx: int m, len: int len, off: int off): field_result(off, len) = let
  val e = nul_in(bv, off, len)
in
  if e >= len then FieldMissing()
  else FieldHere(name_of_range(bv, mx, off, e, false), e + 1)
end

(* The qualifier a field is *)
fn qualifier_of (f: maybe_name): qualifier =
  case+ f of ~NameAbsent() => Unqualified() | ~NameHere(a) => QualifiedBy(a)

fn instance_of (f: maybe_name): instance_text =
  case+ f of ~NameAbsent() => NoInstance() | ~NameHere(t) => InstanceText(t)

(* The facts of the record body bv[0, len) from off, added to acc in order
   read; false when the rest is not a body of facts *)
fun parse_facts {l:agz}{n:pos}{m:nat | m <= n}{len:nat | len <= m}{off:nat | off <= len}{k:nat} .<len - off>.
  (bv: !$A.borrow(byte, l, n), mx: int m, len: int len, off: int off, acc: file_facts(k))
  : [k2:nat] @(bool, file_facts(k2)) =
  if off + 2 > len then @(off = len, acc)
  else let
    val fact_kind = tag_of(byte2int0($A.read<byte>(bv, off)))
    val live = byte_live(byte2int0($A.read<byte>(bv, off + 1)))
    val start = off + 2
  in
    case+ fact_kind of
    | TagUnknown() => @(false, acc)
    | TagDeclares() => (case+ field_at(bv, mx, len, start) of
        | ~FieldMissing() => @(false, acc)
        | ~FieldHere(f1, n1) => (case+ f1 of
            | ~NameAbsent() => @(false, acc)
            | ~NameHere(name) => parse_facts(bv, mx, len, n1, file_facts_cons(DeclaresName(live, name), acc))))
    | TagStaloads() => (case+ field_at(bv, mx, len, start) of
        | ~FieldMissing() => @(false, acc)
        | ~FieldHere(f1, n1) => (case+ f1 of
            | ~NameAbsent() => @(false, acc)
            | ~NameHere(name) => parse_facts(bv, mx, len, n1, file_facts_cons(StaloadsFile(live, name), acc))))
    | TagUses() => (case+ field_at(bv, mx, len, start) of
        | ~FieldMissing() => @(false, acc)
        | ~FieldHere(f1, n1) => (case+ f1 of
            | ~NameAbsent() => @(false, acc)
            | ~NameHere(a) => (case+ field_at(bv, mx, len, n1) of
                | ~FieldMissing() => let val () = name_bytes_free(a) in @(false, acc) end
                | ~FieldHere(f2, n2) => (case+ f2 of
                    | ~NameAbsent() => let val () = name_bytes_free(a) in @(false, acc) end
                    | ~NameHere(b) => parse_facts(bv, mx, len, n2, file_facts_cons(UsesPackage(live, a, b), acc))))))
    | TagAliases() => (case+ field_at(bv, mx, len, start) of
        | ~FieldMissing() => @(false, acc)
        | ~FieldHere(f1, n1) => (case+ f1 of
            | ~NameAbsent() => @(false, acc)
            | ~NameHere(a) => (case+ field_at(bv, mx, len, n1) of
                | ~FieldMissing() => let val () = name_bytes_free(a) in @(false, acc) end
                | ~FieldHere(f2, n2) => (case+ f2 of
                    | ~NameAbsent() => let val () = name_bytes_free(a) in @(false, acc) end
                    | ~NameHere(b) => parse_facts(bv, mx, len, n2, file_facts_cons(AliasesFile(live, a, b), acc))))))
    | TagImplements() => (case+ field_at(bv, mx, len, start) of
        | ~FieldMissing() => @(false, acc)
        | ~FieldHere(f1, n1) => (case+ field_at(bv, mx, len, n1) of
            | ~FieldMissing() => let val () = free_maybe(f1) in @(false, acc) end
            | ~FieldHere(f2, n2) => (case+ field_at(bv, mx, len, n2) of
                | ~FieldMissing() => let val () = free_maybe(f1) val () = free_maybe(f2) in @(false, acc) end
                | ~FieldHere(f3, n3) => (case+ f2 of
                    | ~NameAbsent() => let val () = free_maybe(f1) val () = free_maybe(f3) in @(false, acc) end
                    | ~NameHere(nm) =>
                      parse_facts(bv, mx, len, n3,
                        file_facts_cons(ImplementsName(live, qualifier_of(f1), nm, instance_of(f3)), acc))))))
  end

(* The facts of the held record body, when it is a body of facts *)
fn facts_of_held (body: $B.builder_v): [k:nat] @(bool, file_facts(k)) = let
  val @(ba, bl) = $B.into_arr(body)
  val @(fz_b, bv_b) = $A.freeze<byte>(ba)
  val @(ok, facts) = parse_facts(bv_b, bl, bl, 0, file_facts_nil())
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in @(ok, facts) end

(* The facts of the file at the NUL-terminated path, read and lexed; they are
   recorded at slot under key when usable and the file still has that key *)
fn lex_facts {lp,lk,ls:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}{ns:pos}{sm:nat | sm <= ns; sm <= 524288}
  (p: !$A.borrow(byte, lp, np), pm: int pm, usable: bool, key: !$A.borrow(byte, lk, 64),
   slot: !$A.borrow(byte, ls, ns), sm: int sm): [k:nat] file_facts(k) =
  case+ read_whole_m(p, pm) of
  | ~whole_ok(ar, piece, m1, nbytes) => let
      val @(fz_src, bv_src) = $A.freeze<byte>(piece)
      val facts = facts_of_source(bv_src, nbytes, m1)
      var body : $B.builder_v = $B.create()
      val () = put_facts(facts, body)
      val @(ba, bl) = $B.into_arr(body)
      val @(fz_b, bv_b) = $A.freeze<byte>(ba)
      val () = (if usable then (if facts_same(p, pm, key) then uses_write(slot, sm, key, bv_b, bl) else ()) else ())
      val () = $A.drop<byte>(fz_b, bv_b)
      val () = $A.free<byte>($A.thaw<byte>(fz_b))
      val () = $A.drop<byte>(fz_src, bv_src)
      val () = whole_free(ar, $A.thaw<byte>(fz_src))
    in facts end
  | ~whole_err(_) => file_facts_nil()

implement facts_of_file (reuse, path_bytes, path_length) = let
  val @(usable, key) = facts_key(path_bytes, path_length)
  val @(slot, sm) = facts_slot(path_bytes, path_length)
  val @(fz_k, bv_k) = $A.freeze<byte>(key)
  val @(fz_s, bv_s) = $A.freeze<byte>(slot)
  val @(held, body) = uses_hit(reuse && usable, bv_s, sm, bv_k)
  val @(parsed, facts) = (if held then facts_of_held(body)
                          else let val () = $B.builder_free(body) in @(false, file_facts_nil()) end): [k:nat] @(bool, file_facts(k))
  val result = (if parsed then facts
    else let
      val () = file_facts_free(facts)
      val () = (if is_verbose() then let
          val () = print! ("  ~ facts lexed ")
          val () = print_borrow(path_bytes, 0, find_null_bv_from(path_bytes, 0, path_length), path_length)
        in print_newline() end else ())
    in lex_facts(path_bytes, path_length, usable, bv_k, bv_s, sm) end): [k:nat] file_facts(k)
  val () = $A.drop<byte>(fz_s, bv_s)
  val () = $A.free<byte>($A.thaw<byte>(fz_s))
  val () = $A.drop<byte>(fz_k, bv_k)
  val () = $A.free<byte>($A.thaw<byte>(fz_k))
in result end

(* ============================================================
   The project
   ============================================================ *)

fn listing_same (a: listing, b: listing): bool =
  case+ (a, b) of
  | (OwnListing(), OwnListing()) => true
  | (DependencyListing(), DependencyListing()) => true
  | (_, _) => false

fun copy_bytes {la,lb:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (src: !$A.arr(byte, la, m), dst: !$A.arr(byte, lb, m), m: int m, i: int i): void =
  if i >= m then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in copy_bytes(src, dst, m, i + 1) end

fn name_copy (name: !name_bytes): name_bytes = let
  val+ @NameBytes(a, m) = name
  val b = $A.alloc<byte>(m)
  val () = copy_bytes(a, b, m, 0)
  val size = m
  prval () = fold@(name)
in NameBytes(b, size) end

fn lib_path_name (): name_bytes = let
  var chars = @[char][12]('s', 'r', 'c', '/', 'l', 'i', 'b', '.', 'b', 'a', 't', 's')
  val a = $S.from_char_array(chars, 12)
in NameBytes(a, 12) end

fn dot_name (): name_bytes = let
  var chars = @[char][1]('.')
  val a = $S.from_char_array(chars, 1)
in NameBytes(a, 1) end

implement project_new () =
  Project(package_roots_cons(PackageRoot(0, dot_name()), package_roots_nil()), project_files_nil())

fun roots_free {np:int}{k:nat} .<k>. (xs: package_roots(np, k)): void =
  case+ xs of
  | ~package_roots_nil() => ()
  | ~package_roots_cons(~PackageRoot(_, name), tl) => let
      val () = name_bytes_free(name)
    in roots_free(tl) end

fun files_free {np:int}{k:nat} .<k>. (xs: project_files(np, k)): void =
  case+ xs of
  | ~project_files_nil() => ()
  | ~project_files_cons(~ProjectFile(_, _, _, path, facts), tl) => let
      val () = name_bytes_free(path)
      val () = file_facts_free(facts)
    in files_free(tl) end

implement project_free {np} (whole) = let
  val+ ~Project(roots, files) = whole
  val () = roots_free(roots)
in files_free(files) end

(* roots, with each package number allowed np + 1 packages; the order
   reversed onto acc *)
fun roots_widen {np:pos}{k,j:nat} .<k>.
  (xs: package_roots(np, k), acc: package_roots(np + 1, j)): package_roots(np + 1, j + k) =
  case+ xs of
  | ~package_roots_nil() => acc
  | ~package_roots_cons(~PackageRoot(i, name), tl) =>
    roots_widen(tl, package_roots_cons(PackageRoot(i, name), acc))

fun files_widen {np:pos}{k,j:nat} .<k>.
  (xs: project_files(np, k), acc: project_files(np + 1, j)): [j2:nat] project_files(np + 1, j2) =
  case+ xs of
  | ~project_files_nil() => acc
  | ~project_files_cons(~ProjectFile(owner, lst, off, path, facts), tl) =>
    files_widen(tl, project_files_cons(ProjectFile(owner, lst, off, path, facts), acc))

fun roots_count {np:int}{k,i:nat} .<k>. (xs: !package_roots(np, k), n: int i): int (i + k) =
  case+ xs of
  | package_roots_nil() => n
  | package_roots_cons(_, tl) => roots_count(tl, n + 1)

implement project_package_count {np} (whole) = let
  val+ @Project(roots, _) = whole
  val count = roots_count(roots, 0)
  prval () = fold@(whole)
in count end

implement project_add_package {np} (whole, root) = let
  val+ ~Project(roots, files) = whole
  val number = roots_count(roots, 0)
  val roots2 = roots_widen(roots, package_roots_nil())
in Project(package_roots_cons(PackageRoot(number, root), roots2), files_widen(files, project_files_nil())) end

implement project_add_file {np}{k} (whole, owner, file_listing, file_offset, path_in_package, facts) = let
  val+ ~Project(roots, files) = whole
in Project(roots, project_files_cons(ProjectFile(owner, file_listing, file_offset, path_in_package, facts), files)) end

fun lookup_root {np:int}{k:nat} .<k>. (xs: !package_roots(np, k), root: !name_bytes): package_lookup(np) =
  case+ xs of
  | package_roots_nil() => PackageMissing()
  | package_roots_cons(r, tl) => (case+ r of
      | PackageRoot(i, name) => if name_equal(name, root) then PackageFound(i) else lookup_root(tl, root))

implement package_of_root {np} (whole, root) = let
  val+ @Project(roots, _) = whole
  val r = lookup_root(roots, root)
  prval () = fold@(whole)
in r end

fun root_named {np:int}{k:nat} .<k>. (xs: !package_roots(np, k), package: int): name_bytes =
  case+ xs of
  | package_roots_nil() => dot_name()
  | package_roots_cons(r, tl) => (case+ r of
      | PackageRoot(i, name) => if i = package then name_copy(name) else root_named(tl, package))

implement root_of_package {np} (whole, package) = let
  val+ @Project(roots, _) = whole
  val r = root_named(roots, package)
  prval () = fold@(whole)
in r end

implement file_refs_free {np}{k} (refs) = let
  fun loop {k:nat} .<k>. (refs: file_refs(np, k)): void =
    case+ refs of
    | ~file_refs_nil() => ()
    | ~file_refs_cons(~FileRef(_, _, _), tl) => loop(tl)
in loop(refs) end

implement foreign_hits_free {np}{k} (hits) = let
  fun loop {k:nat} .<k>. (hits: foreign_hits(np, k)): void =
    case+ hits of
    | ~foreign_hits_nil() => ()
    | ~foreign_hits_cons(~ForeignHit(~FileRef(_, _, _), ~FileRef(_, _, _), name), tl) => let
        val () = name_bytes_free(name)
      in loop(tl) end
in loop(hits) end

(* The index of the first "/src/" in a[i, m), else ~1 *)
fun src_marker {la:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (a: !$A.arr(byte, la, m), m: int m, i: int i): [r:int] int r =
  if i + 5 > m then ~1
  else if byte2int0($A.get<byte>(a, i)) = 47 && byte2int0($A.get<byte>(a, i + 1)) = 115
       && byte2int0($A.get<byte>(a, i + 2)) = 114 && byte2int0($A.get<byte>(a, i + 3)) = 99
       && byte2int0($A.get<byte>(a, i + 4)) = 47 then i
  else src_marker(a, m, i + 1)

fun slice_copy {la,lb:agz}{m,z:pos}{from:nat | from + z <= m}{i:nat | i <= z} .<z - i>.
  (a: !$A.arr(byte, la, m), dst: !$A.arr(byte, lb, z), from: int from, z: int z, i: int i): void =
  if i >= z then ()
  else let
    val () = $A.set<byte>(dst, i, $A.get<byte>(a, from + i))
  in slice_copy(a, dst, from, z, i + 1) end

(* The bytes of the name before the first "/src/", which are the root of the package a path names *)
fn root_before_src (path: !name_bytes): maybe_name = let
  val+ @NameBytes(a, m) = path
  val idx = src_marker(a, m, 0)
  val r = (if idx >= 1 then let
      val z = idx
    in (if z <= m then let
          val b = $A.alloc<byte>(z)
          val () = slice_copy(a, b, 0, z, 0)
        in NameHere(NameBytes(b, z)) end
        else NameAbsent()) end
      else NameAbsent()): maybe_name
  prval () = fold@(path)
in r end

(* Where the path after the root starts (past the slash before src/), or ~1 *)
fn src_start (path: !name_bytes): [r:int] int r = let
  val+ @NameBytes(a, m) = path
  val idx = src_marker(a, m, 0)
  prval () = fold@(path)
in if idx >= 0 then idx + 1 else ~1 end

(* Whether the file's path from its package's root is text[from, end), the
   extension .sats standing for .bats *)
fun same_tail {la,lb:agz}{m,z:pos}{from:nat}{i:nat | i <= m} .<m - i>.
  (a: !$A.arr(byte, la, m), m: int m, b: !$A.arr(byte, lb, z), z: int z, from: int from, i: int i): bool =
  if i >= m then true
  else if from + i >= z then false
  else let
    val x = byte2int0($A.get<byte>(a, i))
    val y = byte2int0($A.get<byte>(b, from + i))
  in
    if x = y || (i + 4 = m && x = 98 && y = 115) then same_tail(a, m, b, z, from, i + 1) else false
  end

fn path_is {from:int} (file_path: !name_bytes, text: !name_bytes, from: int from): bool = let
  val+ @NameBytes(a, m) = file_path
  val+ @NameBytes(b, z) = text
  val r = (if from < 0 then false else if z - from <> m then false else same_tail(a, m, b, z, from, 0)): bool
  prval () = fold@(file_path)
  prval () = fold@(text)
in r end

datavtype found_file(np:int) =
  | NoFile(np) of ()
  | FoundFile(np) of file_ref(np)

(* The file of the package number pkg whose path from the root is text[from, end) *)
fun find_file {np:int}{k:nat}{from:int} .<k>.
  (files: !project_files(np, k), pkg: int, text: !name_bytes, from: int from): found_file(np) =
  case+ files of
  | project_files_nil() => NoFile()
  | project_files_cons(f, tl) => (case+ f of
      | ProjectFile(owner, lst, off, path, _) =>
        if owner = pkg && path_is(path, text, from) then FoundFile(FileRef(owner, lst, off))
        else find_file(tl, pkg, text, from))

(* The file a path as written in a staload names: the file of the package
   whose root comes before its /src/ *)
fn resolve_text {np:int}{k,j:nat}
  (roots: !package_roots(np, k), files: !project_files(np, j), text: !name_bytes): found_file(np) =
  case+ root_before_src(text) of
  | ~NameAbsent() => NoFile()
  | ~NameHere(root) => let
      val found = lookup_root(roots, root)
      val () = name_bytes_free(root)
    in
      case+ found of
      | ~PackageMissing() => NoFile()
      | ~PackageFound(pkg) => find_file(files, pkg, text, src_start(text))
    end

(* The lib file of the package whose root a #use gives *)
fn resolve_use {np:int}{k,j:nat}
  (roots: !package_roots(np, k), files: !project_files(np, j), root: !name_bytes): found_file(np) =
  case+ lookup_root(roots, root) of
  | ~PackageMissing() => NoFile()
  | ~PackageFound(pkg) => let
      val lib = lib_path_name()
      val r = find_file(files, pkg, lib, 0)
      val () = name_bytes_free(lib)
    in r end

fn add_found {np:int}{j:nat} (f: found_file(np), acc: file_refs(np, j)): [j2:nat] file_refs(np, j2) =
  case+ f of
  | ~NoFile() => acc
  | ~FoundFile(r) => file_refs_cons(r, acc)

fn variants_union (a: variants_live, b: variants_live): variants_live =
  @{native= a.native || b.native, native_test= a.native_test || b.native_test,
    wasm= a.wasm || b.wasm, wasm_test= a.wasm_test || b.wasm_test}

(* A way a file reaches another: '#use root as alias', 'staload alias =
   "path"' or an unaliased staload "path". Copies of the facts, so that the
   lists of the project need not be borrowed twice *)
datavtype binding =
  | BindUse of (variants_live, name_bytes (* alias *), name_bytes (* root *))
  | BindAlias of (variants_live, name_bytes (* alias *), name_bytes (* path *))
  | BindOpen of (variants_live, name_bytes (* path *))

datavtype bindings(k:int) =
  | bindings_nil(0) of ()
  | {j:nat} bindings_cons(j + 1) of (binding, bindings(j))

fun bindings_free {k:nat} .<k>. (bs: bindings(k)): void =
  case+ bs of
  | ~bindings_nil() => ()
  | ~bindings_cons(b, tl) => let
      val () = (case+ b of
        | ~BindUse(_, a, r) => let val () = name_bytes_free(a) in name_bytes_free(r) end
        | ~BindAlias(_, a, p) => let val () = name_bytes_free(a) in name_bytes_free(p) end
        | ~BindOpen(_, p) => name_bytes_free(p))
    in bindings_free(tl) end

(* The bindings the facts of one file make *)
fun file_bindings {k,j:nat} .<k>. (facts: !file_facts(k), acc: bindings(j)): [j2:nat] bindings(j2) =
  case+ facts of
  | file_facts_nil() => acc
  | file_facts_cons(f, tl) => let
      val acc2 = (case+ f of
        | UsesPackage(live, root, alias) => bindings_cons(BindUse(live, name_copy(alias), name_copy(root)), acc)
        | AliasesFile(live, alias, path) => bindings_cons(BindAlias(live, name_copy(alias), name_copy(path)), acc)
        | StaloadsFile(live, path) => bindings_cons(BindOpen(live, name_copy(path)), acc)
        | DeclaresName(_, _) => acc | ImplementsName(_, _, _, _) => acc): [j2:nat] bindings(j2)
    in file_bindings(tl, acc2) end

(* The bindings of the file (own, lst, off) of the files scan *)
fun bindings_of_file {np:int}{k:nat} .<k>.
  (scan: !project_files(np, k), own: int, lst: listing, off: int): [j:nat] bindings(j) =
  case+ scan of
  | project_files_nil() => bindings_nil()
  | project_files_cons(f, tl) => (case+ f of
      | ProjectFile(owner, l2, o2, _, facts) =>
        if owner = own && listing_same(l2, lst) && o2 = off then file_bindings(facts, bindings_nil())
        else bindings_of_file(tl, own, lst, off))

(* The bindings of all that a name with the qualifier through reaches (a
   copy), and the builds they are live in, added to the builds in live *)
fun select_bindings {k,j:nat} .<k>.
  (all: !bindings(k), through: !qualifier, live: variants_live, acc: bindings(j))
  : [j2:nat] @(bindings(j2), variants_live) =
  case+ all of
  | bindings_nil() => @(acc, live)
  | bindings_cons(b, tl) => (case+ b of
      | BindUse(l, alias, root) => (case+ through of
          | QualifiedBy(a) => if name_equal(alias, a)
              then select_bindings(tl, through, variants_union(live, l), bindings_cons(BindUse(l, name_copy(alias), name_copy(root)), acc))
              else select_bindings(tl, through, live, acc)
          | Unqualified() => select_bindings(tl, through, live, acc))
      | BindAlias(l, alias, path) => (case+ through of
          | QualifiedBy(a) => if name_equal(alias, a)
              then select_bindings(tl, through, variants_union(live, l), bindings_cons(BindAlias(l, name_copy(alias), name_copy(path)), acc))
              else select_bindings(tl, through, live, acc)
          | Unqualified() => select_bindings(tl, through, live, acc))
      | BindOpen(l, path) => (case+ through of
          | Unqualified() => select_bindings(tl, through, variants_union(live, l), bindings_cons(BindOpen(l, name_copy(path)), acc))
          | QualifiedBy(_) => select_bindings(tl, through, live, acc)))

(* The files the bindings bs reach, added to acc *)
fun resolve_bindings {np:int}{kr,kf,k,j:nat} .<k>.
  (roots: !package_roots(np, kr), files: !project_files(np, kf), bs: !bindings(k), acc: file_refs(np, j))
  : [j2:nat] file_refs(np, j2) =
  case+ bs of
  | bindings_nil() => acc
  | bindings_cons(b, tl) => let
      val acc2 = (case+ b of
        | BindUse(_, _, root) => add_found(resolve_use(roots, files, root), acc)
        | BindAlias(_, _, path) => add_found(resolve_text(roots, files, path), acc)
        | BindOpen(_, path) => add_found(resolve_text(roots, files, path), acc)): [j2:nat] file_refs(np, j2)
    in resolve_bindings(roots, files, tl, acc2) end

implement files_reached {np} (whole, by, through) = let
  val+ @Project(roots, files) = whole
  val+ FileRef(own, lst, off) = by
  val all = bindings_of_file(files, own, lst, off)
  val @(selected, _) = select_bindings(all, through, @{native= false, native_test= false, wasm= false, wasm_test= false}, bindings_nil())
  val refs = resolve_bindings(roots, files, selected, file_refs_nil())
  val () = bindings_free(all)
  val () = bindings_free(selected)
  prval () = fold@(whole)
in refs end

(* Whether the implement of a package with instance inst is a replacement of
   an implement whose instance is other: other is the template itself, or
   the same instance *)
fn replaces (other: !instance_text, inst: !instance_text): bool =
  case+ other of
  | NoInstance() => true
  | InstanceText(t2) => (case+ inst of
      | NoInstance() => false
      | InstanceText(t1) => name_equal(t1, t2))

fun implements_in_facts {k:nat} .<k>.
  (facts: !file_facts(k), name: !name_bytes, inst: !instance_text, common: variants_live): bool =
  case+ facts of
  | file_facts_nil() => false
  | file_facts_cons(f, tl) => let
      val here = (case+ f of
        | ImplementsName(live, q, nm, other) => (case+ q of
            | Unqualified() => name_equal(nm, name) && variants_any(variants_meet(common, live)) && replaces(other, inst)
            | QualifiedBy(_) => false)
        | DeclaresName(_, _) => false | UsesPackage(_, _, _) => false
        | AliasesFile(_, _, _) => false | StaloadsFile(_, _) => false): bool
    in if here then true else implements_in_facts(tl, name, inst, common) end

(* Whether a file of the package number pkg implements name with a
   replaced instance in a build of common *)
fun package_implements {np:int}{k:nat} .<k>.
  (files: !project_files(np, k), pkg: int, name: !name_bytes, inst: !instance_text, common: variants_live): bool =
  case+ files of
  | project_files_nil() => false
  | project_files_cons(f, tl) => let
      val here = (case+ f of
        | ProjectFile(owner, _, _, _, facts) => owner = pkg && implements_in_facts(facts, name, inst, common)): bool
    in if here then true else package_implements(tl, pkg, name, inst, common) end


(* ============================================================
   The hits
   ============================================================ *)

(* An implement with the bindings that reach its name, and the builds it and
   they are live in; what one pass over the files collects, so that the
   answers need no list borrowed twice *)
datavtype query(np:int) =
  | {j:nat} Query(np) of (package_number(np), listing, path_offset, variants_live,
                          name_bytes, instance_text, bindings(j))

datavtype queries(np:int, k:int) =
  | queries_nil(np, 0) of ()
  | {j:nat} queries_cons(np, j + 1) of (query(np), queries(np, j))

fun queries_free {np:int}{k:nat} .<k>. (qs: queries(np, k)): void =
  case+ qs of
  | ~queries_nil() => ()
  | ~queries_cons(~Query(_, _, _, _, name, inst, bs), tl) => let
      val () = name_bytes_free(name)
      val () = (case+ inst of ~NoInstance() => () | ~InstanceText(t) => name_bytes_free(t))
      val () = bindings_free(bs)
    in queries_free(tl) end

fn instance_copy (inst: !instance_text): instance_text =
  case+ inst of
  | NoInstance() => NoInstance()
  | InstanceText(t) => InstanceText(name_copy(t))

fn qualifier_copy (q: !qualifier): qualifier =
  case+ q of
  | Unqualified() => Unqualified()
  | QualifiedBy(a) => QualifiedBy(name_copy(a))

(* The queries of the implements among the facts of the file (owner, lst,
   off), whose bindings are all *)
fun queries_of_facts {np:int}{k,kb,j:nat} .<k>.
  (facts: !file_facts(k), all: !bindings(kb), owner: package_number(np), lst: listing, off: path_offset,
   acc: queries(np, j)): [j2:nat] queries(np, j2) =
  case+ facts of
  | file_facts_nil() => acc
  | file_facts_cons(f, tl) => let
      val acc2 = (case+ f of
        | ImplementsName(live, q, name, inst) =>
          if variants_any(live) then let
            val @(selected, bound) = select_bindings(all, q, @{native= false, native_test= false, wasm= false, wasm_test= false}, bindings_nil())
            val common = variants_meet(live, bound)
          in
            if variants_any(common)
            then queries_cons(Query(owner, lst, off, common, name_copy(name), instance_copy(inst), selected), acc)
            else let val () = bindings_free(selected) in acc end
          end
          else acc
        | DeclaresName(_, _) => acc | UsesPackage(_, _, _) => acc
        | AliasesFile(_, _, _) => acc | StaloadsFile(_, _) => acc): [j2:nat] queries(np, j2)
    in queries_of_facts(tl, all, owner, lst, off, acc2) end

fun queries_of_files {np:int}{k,j:nat} .<k>.
  (scan: !project_files(np, k), acc: queries(np, j)): [j2:nat] queries(np, j2) =
  case+ scan of
  | project_files_nil() => acc
  | project_files_cons(f, tl) => (case+ f of
      | ProjectFile(owner, lst, off, _, facts) => let
          val all = file_bindings(facts, bindings_nil())
          val acc2 = queries_of_facts(facts, all, owner, lst, off, acc)
          val () = bindings_free(all)
        in queries_of_files(tl, acc2) end)

(* The builds in which the facts declare name, added to acc *)
fun declared_in_facts {k:nat} .<k>. (facts: !file_facts(k), name: !name_bytes, acc: variants_live): variants_live =
  case+ facts of
  | file_facts_nil() => acc
  | file_facts_cons(f, tl) => let
      val acc2 = (case+ f of
        | DeclaresName(live, nm) => if name_equal(nm, name) then variants_union(acc, live) else acc
        | ImplementsName(_, _, _, _) => acc | UsesPackage(_, _, _) => acc
        | AliasesFile(_, _, _) => acc | StaloadsFile(_, _) => acc): variants_live
    in declared_in_facts(tl, name, acc2) end

(* The builds in which the file (target, lst, off) declares name *)
fun declared_live {np:int}{k:nat} .<k>.
  (scan: !project_files(np, k), target: int, lst: listing, off: int, name: !name_bytes, acc: variants_live): variants_live =
  case+ scan of
  | project_files_nil() => acc
  | project_files_cons(f, tl) => (case+ f of
      | ProjectFile(owner, l2, o2, _, facts) =>
        if owner = target && listing_same(l2, lst) && o2 = off then declared_in_facts(facts, name, acc)
        else declared_live(tl, target, lst, off, name, acc))

(* hits, with the replacements that the query makes of what the files it
   reaches declare *)
fun answer_refs {np:int}{kf,k,h:nat} .<k>.
  (refs: !file_refs(np, k), files: !project_files(np, kf), owner: package_number(np), lst: listing, off: path_offset,
   common: variants_live, name: !name_bytes, inst: !instance_text, acc: foreign_hits(np, h))
  : [h2:nat] foreign_hits(np, h2) =
  case+ refs of
  | file_refs_nil() => acc
  | file_refs_cons(r, tl) => let
      val acc2 = (case+ r of
        | FileRef(target, tlst, toff) =>
          if target = owner then acc
          else let
            val declared = declared_live(files, target, tlst, toff, name, @{native= false, native_test= false, wasm= false, wasm_test= false})
            val both = variants_meet(common, declared)
          in
            if variants_any(both) && package_implements(files, target, name, inst, both)
            then foreign_hits_cons(ForeignHit(FileRef(owner, lst, off), FileRef(target, tlst, toff), name_copy(name)), acc)
            else acc
          end): [h2:nat] foreign_hits(np, h2)
    in answer_refs(tl, files, owner, lst, off, common, name, inst, acc2) end

fun answer_queries {np:int}{kr,kf,k,h:nat} .<k>.
  (qs: !queries(np, k), roots: !package_roots(np, kr), files: !project_files(np, kf), acc: foreign_hits(np, h))
  : [h2:nat] foreign_hits(np, h2) =
  case+ qs of
  | queries_nil() => acc
  | queries_cons(q, tl) => let
      val acc2 = (case+ q of
        | Query(owner, lst, off, common, name, inst, bs) => let
            val refs = resolve_bindings(roots, files, bs, file_refs_nil())
            val hits = answer_refs(refs, files, owner, lst, off, common, name, inst, acc)
            val () = file_refs_free(refs)
          in hits end): [h2:nat] foreign_hits(np, h2)
    in answer_queries(tl, roots, files, acc2) end

implement foreign_hits_of {np} (whole) = let
  val+ @Project(roots, files) = whole
  val qs = queries_of_files(files, queries_nil())
  val hits = answer_queries(qs, roots, files, foreign_hits_nil())
  val () = queries_free(qs)
  prval () = fold@(whole)
in hits end
