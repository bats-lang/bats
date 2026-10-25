(* overrides -- an implement only of what its package can see another package declare (bats#421)

   DESIGN CHECK, round 2: declarations only, no bodies (overrides.md).

   A dependency's #pub template is meant to be instantiated by a
   dependent, not replaced by it: a dependent that writes
   'implement{} word32_rotr_inline ...' with another body of the same type
   passes patsopt, and the body it wrote runs at its own call sites. This
   finds those implements.

   Names, from the sources: a #pub declaration (fun, fn, fnx, prfun, prfn
   and the 'and' members of a group) declares one, an implement (also
   primplement, implmnt), qualified ($X.name) or not, implements one, and a
   '#use' line says which package a file loads.

   Visible set (the dats prelude, emitter.bats build_prelude: a file's
   dats is its own sats, then an unaliased staload of the lib.dats of each
   package its '#use' lines name, and a lib.dats loads what its own '#use'
   lines name, closure.bats): the packages an implementing package can see
   are the package itself and the closure of its '#use' lines over the
   packages of ./bats_modules, a transitive dependency included. An
   implement is rejected when the name is declared by a #pub of a package it
   sees other than the implementing package. The implementing package
   declaring the same name does not exempt it (its own sats comes first in
   the prelude, so a seen package's declaration can still be what the
   implement binds to). Two packages that do not #use each other are not
   seen by each other: neither is rejected for a name both declare. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "lexer.sats"

(* What a source file says about a name: it declares it (#pub), it
   implements it, or it loads the package of that name (#use) *)
#pub datatype name_role = DeclaresName | ImplementsName | UsesPackage

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

(* The names a file declares, implements and loads, each with its role *)
#pub datavtype file_names(int) =
  | file_names_nil(0) of ()
  | {k:nat} file_names_cons(k + 1) of (name_role, name_bytes, file_names(k))

#pub fun file_names_free {k:nat} (names: file_names(k)): void

(* The names of the source source_bytes[0, source_length), read from its spans:
   a function of the bytes, so the same source gives the same names *)
#pub fn names_of_source {l:agz}{n:pos}{source_length:nat | source_length <= n}
  (source_bytes: !$A.borrow(byte, l, n), source_length: int source_length)
  : [k:nat] file_names(k)

(* The names of the file at the NUL-terminated path path_bytes[0, path_length): the record
   'facts <path>' of build/.bats_valid/ when reuse is true and it holds the
   file's key (validated.bats), else names_of_source, recorded when the file
   still has the key it was read under; empty for a file that cannot be read *)
#pub fn names_of_file {lp:agz}{np:pos}{path_length:nat | path_length <= np; path_length <= 524288}
  (reuse: bool, path_bytes: !$A.borrow(byte, lp, np), path_length: int path_length)
  : [k:nat] file_names(k)

(* A name found in the project, with: its role, its bytes, its hash (over
   all of them), the package it is in, its listing and the offset of its
   file's path in that listing *)
#pub datavtype found_name(np:int) =
  | FoundName of (name_role, name_bytes, int (* hash *), package_number(np),
                  listing, path_offset)

#pub datavtype found_names(np:int, k:int) =
  | found_names_nil(np, 0) of ()
  | {j:nat} found_names_cons(np, j + 1) of (found_name(np), found_names(np, j))

(* The packages one package loads (its '#use' lines that name a package of
   the project), then the package itself first *)
#pub datavtype package_uses(np:int) =
  | package_uses_nil(np) of ()
  | package_uses_cons(np) of (package_number(np), package_uses(np))

(* A package of the project: its number, the name its '#use' lines give it
   (the directory under ./bats_modules; empty for the package itself), and
   the names of the packages it loads *)
#pub datavtype project_package(np:int) =
  | ProjectPackage of (package_number(np), name_bytes, found_names(np, 0))

(* What the project holds so far: the declared names in 64 lists by name
   hash, and the implemented names in one list *)
#pub datavtype declared_buckets(np:int, b:int) =
  | declared_buckets_nil(np, 0) of ()
  | {b0,j:nat} declared_buckets_cons(np, b0 + 1) of (found_names(np, j), declared_buckets(np, b0))

#pub datavtype project_names(np:int) =
  | {i:nat} ProjectNames of (declared_buckets(np, 64), found_names(np, i))

#pub fn project_names_new (): project_names(1)

#pub fun project_names_free {np:pos} (project: project_names(np)): void

(* project with the names of one file, which is in file_listing at
   file_offset and belongs to the package number owner; a '#use' of the
   file is recorded as an edge from the owner to the package of that name *)
#pub fn project_names_add {np:pos}{k:nat}
  (project: project_names(np), names: file_names(k), owner: package_number(np),
   file_listing: listing, file_offset: path_offset): project_names(np)

(* The packages package_number sees: itself and the closure of its '#use'
   lines (the visible set above), by number *)
#pub fn visible_packages {np:pos}
  (project: !project_names(np), observer: package_number(np)): package_uses(np)

#pub fun package_uses_free {np:int} (uses: package_uses(np)): void

(* An implement of a name that another package declares and the implementing
   package sees: the implementing file's package, listing and offset, the
   declaring file's package, listing and offset, and the name *)
#pub datavtype foreign_hit(np:int) =
  | ForeignHit of (package_number(np) (* implementing package *), listing, path_offset,
                   package_number(np) (* declaring package *), listing, path_offset,
                   name_bytes)

#pub datavtype foreign_hits(np:int, k:int) =
  | foreign_hits_nil(np, 0) of ()
  | {j:nat} foreign_hits_cons(np, j + 1) of (foreign_hit(np), foreign_hits(np, j))

#pub fun foreign_hits_free {np:int}{k:nat} (hits: foreign_hits(np, k)): void

(* The implements of project (taken) of a name that a package they see
   declares *)
#pub fn foreign_hits_of {np:pos} (project: project_names(np)): [k:nat] foreign_hits(np, k)

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
