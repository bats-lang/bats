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
   (a module that file staloads is not reached through the alias, E5). An implement is a hit when: the name is declared
   there, the package that declares it also implements that name (so a name
   it leaves for its dependents to implement, like promise's dispose, is an
   extension point and not a hit) with no instance, or with the same
   instance as the implement (the instance is the text of the <...> after the
   name with its blanks removed; a type spelled another way is not matched),
   and the implement, the binding, the declaration and that implement of the
   declarer are all live in one of the four builds (native or wasm, test or
   not: a #target or $UNITTEST block the emitter blanks, next_state, is not
   live), so a use the build loads nothing for creates no rejection. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "lexer.sats"

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
  (source_bytes: !$A.borrow(byte, l, n), source_length: int source_length)
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
  | {k:nat} ProjectFile of (package_number(np), listing, path_offset,
                            name_bytes (* path from the package's root *), file_facts(k))

#pub datavtype project_files(np:int, k:int) =
  | project_files_nil(np, 0) of ()
  | {j:nat} project_files_cons(np, j + 1) of (project_file(np), project_files(np, j))

(* The packages of the project: number 0 is the package itself (root
   empty); the others are the packages of ./bats_modules, each with its root
   (the directory between ./bats_modules/ and /src/, which is the name its
   '#use' lines give). np packages, numbered 0 .. np - 1 *)
#pub datavtype package_root(np:int) =
  | PackageRoot of (package_number(np), name_bytes)

#pub datavtype package_roots(np:int, k:int) =
  | package_roots_nil(np, 0) of ()
  | {j:nat} package_roots_cons(np, j + 1) of (package_root(np), package_roots(np, j))

(* The project: np packages and their files *)
#pub datavtype project(np:int) =
  | {k,j:nat} Project of (package_roots(np, k), project_files(np, j))

(* The project with the package itself alone *)
#pub fn project_new (): project(1)

#pub fun project_free {np:pos} (whole: project(np)): void

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
  | FileRef of (package_number(np), listing, path_offset)

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
  | ForeignHit of (file_ref(np) (* implementing file *), file_ref(np) (* declaring file *),
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
  (source_bytes: !$A.borrow(byte, l, n), source_length: int source_length,
   wanted: !$A.arr(byte, la, m), wanted_length: int m): [k:nat] implement_sites(k)
