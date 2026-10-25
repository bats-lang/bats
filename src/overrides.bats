(* overrides -- an implement only of what its file cannot see another package declare (bats#421)

   DESIGN CHECK, round 3: declarations only, no bodies (overrides.md).

   A dependency's #pub template is meant to be instantiated by a
   dependent, not replaced by it: a dependent that writes
   'implement{} word32_rotr_inline ...' with another body of the same type
   passes patsopt, and the body it wrote runs at its own call sites. This
   finds those implements.

   Names, from the sources: a #pub declaration (fun, fn, fnx, prfun, prfn
   and the 'and' members of a group) declares one, an implement (also
   primplement, implmnt), qualified ($X.name) or not, implements one, a
   '#use' line loads a package, and an unaliased 'staload "./m.bats"' loads
   a module of the file's package.

   What a file's dats loads, from the emitter (emit_one, build_prelude,
   emit_dep_stld): its own sats; for each '#use P', the lib.dats of P
   (unaliased; the sats gets the alias only, which opens nothing); for each
   unaliased staload "./m.bats", the sats of m (to the sats and the dats). A
   lib.dats loads what any dats loads: the sats of lib, the lib.dats of the
   packages lib.bats '#use's, the sats of the modules lib.bats staloads. A
   sats loads only what it staloads (its '#use' lines are aliased there). So
   from an implementing file F the files seen are, at DatsLevel, F, and the
   DatsLevel of the lib file of each package F '#use's and of each such lib
   file's own '#use' packages, and so on; and at SatsLevel, each module F or a
   lib file staloads, and the modules those staload. The #use lines of a
   dependency's other modules open nothing (closure.bats reads them to link,
   which is wider). An implement of F is rejected when the name is declared
   by a #pub of a seen file of a package other than F's. F's package
   declaring the name too does not exempt it (its sats comes first in the
   prelude, so a seen declaration can still be what the implement binds to).
   Two packages that do not load each other are not rejected for a name
   both declare. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "lexer.sats"

(* What a source file says about a name: it declares it (#pub), it
   implements it, it loads the package of that name (#use P: the name is P as
   written), or it loads the module of that path (an unaliased
   staload "./m.bats": the name is the path as written, ./m.bats) *)
#pub datatype name_role = DeclaresName | ImplementsName | UsesPackage | StaloadsModule

(* How much of a file a load opens: its dats (its sats, its #use packages'
   lib.dats and its staloaded modules) or its sats (its declarations and
   its staloaded modules) *)
#pub datatype load_level = DatsLevel | SatsLevel

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

(* A file of the project: its package, its listing, the offset of its path
   in that listing, its path from the package's root (src/lib.bats) and its
   names *)
#pub datavtype project_file(np:int) =
  | {k:nat} ProjectFile of (package_number(np), listing, path_offset,
                            name_bytes (* path from the package's root *), file_names(k))

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
   and the names given *)
#pub fn project_add_file {np:pos}{k:nat}
  (whole: project(np), owner: package_number(np), file_listing: listing, file_offset: path_offset,
   path_in_package: name_bytes, names: file_names(k)): project(np)

(* The package of a root, as a '#use' line gives it *)
#pub datavtype package_lookup(np:int) =
  | PackageFound(np) of package_number(np)
  | PackageMissing(np) of ()

#pub fn package_of_root {np:pos} (whole: !project(np), root: !name_bytes): package_lookup(np)

(* A file of the project named by its package, listing and offset *)
#pub datavtype file_ref(np:int) =
  | FileRef of (package_number(np), listing, path_offset)

(* A file seen and how much of it *)
#pub datavtype loaded_file(np:int) =
  | LoadedFile of (file_ref(np), load_level)

#pub datavtype loaded_files(np:int, k:int) =
  | loaded_files_nil(np, 0) of ()
  | {j:nat} loaded_files_cons(np, j + 1) of (loaded_file(np), loaded_files(np, j))

#pub fun loaded_files_free {np:int}{k:nat} (loaded: loaded_files(np, k)): void

(* The files seen from the file implementing (taken from whole's files by
   its ref), as the comment at the top says: each '#use' resolved with
   package_of_root to the lib file (src/lib.bats) of the package, each
   staload resolved against the directory of the file that has it. Each file
   is listed once per level, so the closure ends *)
#pub fn files_seen_from {np:pos} (whole: !project(np), implementing: !file_ref(np))
  : [k:nat] loaded_files(np, k)

(* An implement of a name that a seen file of another package declares:
   the implementing file, the declaring file and the name *)
#pub datavtype foreign_hit(np:int) =
  | ForeignHit of (file_ref(np) (* implementing file *), file_ref(np) (* declaring file *),
                   name_bytes (* the name *))

#pub datavtype foreign_hits(np:int, k:int) =
  | foreign_hits_nil(np, 0) of ()
  | {j:nat} foreign_hits_cons(np, j + 1) of (foreign_hit(np), foreign_hits(np, j))

#pub fun foreign_hits_free {np:int}{k:nat} (hits: foreign_hits(np, k)): void

(* The implements of whole (taken) of a name that a file they see declares in
   another package; the files are compared by their hash and then in full *)
#pub fn foreign_hits_of {np:pos} (whole: project(np)): [k:nat] foreign_hits(np, k)

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
