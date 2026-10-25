(* overrides -- an implement only of what the package declares itself (bats#421)

   DESIGN CHECK: declarations only, no bodies (overrides.md).

   A dependency's #pub template is meant to be instantiated by a
   dependent, not replaced by it: a dependent that writes
   'implement{} word32_rotr_inline ...' with another body of the same type
   passes patsopt, and the body it wrote runs at its own call sites (and at
   the call sites of any module that staloads both). This finds those
   implements.

   The names of a package are read from its sources: a #pub declaration
   (fun, fn, fnx, prfun, prfn, and the 'and' members of a group) declares
   a name, and an implement (also primplement) implements one, qualified
   ($X.name) or not. The project is the package itself (package 0) and each
   package of ./bats_modules (packages 1, 2, ... in the order of the
   listing, whose files are together). An implement is rejected when the
   name is declared by a #pub of another package of the project, wherever the
   package that declares it is among the dependencies, so a transitive
   override is found as a direct one is. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use str as S

staload "helpers.sats"
staload "lexer.sats"

(* What a source file says about a name: it declares it (#pub) or it
   implements it *)
#pub datatype name_role = DeclaresName | ImplementsName

(* Which of the two listings of the project a file is in: the package's
   own files, or those of ./bats_modules *)
#pub datatype listing = OwnListing | DependencyListing

(* The names a file declares and implements, each with its role and its
   bytes (the first 256 of them: two names that share them are taken as
   one, which can only add hits, as recursion.md says of call cycles) *)
#pub datavtype file_names(int) =
  | file_names_nil(0) of ()
  | {k:nat}{l:agz}{m:nat | m <= 256}
    file_names_cons(k + 1) of (name_role, $A.arr(byte, l, 256), int m, file_names(k))

#pub fun file_names_free {k:nat} (xs: file_names(k)): void

(* The names of the source src[0, sm), read from its spans: pure in the
   bytes, so the same source gives the same names *)
#pub fn names_of_source {l:agz}{n:pos}{sm:nat | sm <= n}
  (src: !$A.borrow(byte, l, n), sm: int sm): [k:nat] file_names(k)

(* The names of the file at the NUL-terminated path p: the record
   'facts <path>' of build/.bats_valid/ when reuse is true and it holds the
   file's key (validated.bats), else names_of_source, recorded when the file
   still has the key it was read under; empty for a file that cannot be read *)
#pub fn names_of_file {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}
  (reuse: bool, p: !$A.borrow(byte, lp, np), pm: int pm): [k:nat] file_names(k)

(* A name found in the project: its role, its bytes, its hash (the hash of
   recursion.md's name hash), the package it is in (0 for the package
   itself), and its file: the listing it is in and the offset of its path *)
#pub datavtype found_name =
  | {l:agz}{m:nat | m <= 256}
    FoundName of (name_role, $A.arr(byte, l, 256), int m, int, int, listing, int)

(* The names found so far: those declared are in BUCKETS lists by the hash
   of the name (an implement is compared only with the declared names that
   hash as it does), those implemented are in one list *)
#pub datavtype found_names(int) =
  | found_names_nil(0) of ()
  | {k:nat} found_names_cons(k + 1) of (found_name, found_names(k))

#pub datavtype name_buckets(int) =
  | name_buckets_nil(0) of ()
  | {b,k:nat} name_buckets_cons(b + 1) of (found_names(k), name_buckets(b))

#pub datavtype project_names =
  | {i:nat} ProjectNames of (name_buckets(64), found_names(i))

#pub fn project_names_new (): project_names

#pub fun project_names_free (pn: project_names): void

(* pn with the names of file, which is in listing at offset and belongs to
   the package number package *)
#pub fn project_names_add {k:nat}
  (pn: project_names, names: file_names(k), package: int, where: listing, offset: int): project_names

(* An implement of a name that another package declares: the implementing
   file (its package, listing and offset), the declaring file (its package,
   listing and offset) and the name *)
#pub datavtype foreign_hit =
  | {l:agz}{m:nat | m <= 256}
    ForeignHit of (int, listing, int, int, listing, int, $A.arr(byte, l, 256), int m)

#pub datavtype foreign_hits(int) =
  | foreign_hits_nil(0) of ()
  | {k:nat} foreign_hits_cons(k + 1) of (foreign_hit, foreign_hits(k))

#pub fun foreign_hits_free {k:nat} (xs: foreign_hits(k)): void

(* The implements of pn (taken) of a name that a different package declares *)
#pub fn foreign_hits_of (pn: project_names): [k:nat] foreign_hits(k)

(* The positions in the source src[0, sm) of the implements of the name
   a[0, m): the keyword's start, the name's start and end, for the error
   that points to each *)
#pub datavtype implement_site =
  | ImplementSite of (pos_t, pos_t, pos_t)

#pub datavtype implement_sites(int) =
  | implement_sites_nil(0) of ()
  | {k:nat} implement_sites_cons(k + 1) of (implement_site, implement_sites(k))

#pub fun implement_sites_free {k:nat} (xs: implement_sites(k)): void

#pub fn implement_sites_of {l,la:agz}{n:pos}{sm:nat | sm <= n}{m:nat | m <= 256}
  (src: !$A.borrow(byte, l, n), sm: int sm, a: !$A.arr(byte, la, 256), m: int m)
  : [k:nat] implement_sites(k)
