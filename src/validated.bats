(* validated -- what validate_project has already judged (bats#296).

   Before check, build or test, validate_project lexes every .bats file of
   the project and of its dependencies for the safety rules, and a second
   time to look for an implement on a call cycle. On quire's set (158
   files, 4.7 MB) that was 23% of the instructions of a check in which
   nothing had changed, which ran no patsopt and no cc. A file that
   passed, and is the same file, passes again: the rules read nothing but
   the file, whether the package is unsafe, which packages are installed,
   and bats itself.

   Under build/.bats_valid/ a passing file leaves a record named after its
   path (with / as %): the 64 hex digits of its key. The key is the sha256
   of a text that holds everything the judgment read:

     bats-valid 1 file
     ctx <64 hex>        the context: bats's own inputs (the stamp's `bats`
                         line, so another bats never trusts what this one
                         left) and the listing of the .bats files of
                         ./bats_modules (which packages are installed)
     uns <0|1>           whether the package of the file is unsafe
     <path>
     <sha256 of the file>

   A file is skipped when its record holds the key it has now. A record
   is written only for a file that passed, after the file is hashed again
   and found the same as when it was keyed (a file that changed while it
   was lexed is not recorded as what it was), and only when nothing in the
   whole validation failed (a failed one leaves no build/ behind). The call-cycle check of a
   package is recorded the same way under `cycles <package>`, its key the
   sha256 of the context and of each file's path and sha256, in the order
   listed: it reads those files and nothing else. No time is read, and a
   record that is missing, short or garbled is not equal to a key, so the
   file is judged. --cold and BATS_COLD judge every file and write the
   records again. A record is the judgment of its key only: build/ being
   dropped for another bats loses the records, and the key names bats too. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use result as R
#use sha256 as SHA
#use str as S

staload "helpers.sats"
staload "_bats_inputs.sats"

(* The sha256 of the text, as 64 hex digits *)
fn key_of (text: $B.builder_v): [l:agz] $A.arr(byte, l, 64) = let
  val @(ta, tl) = $B.into_arr(text)
  val c = $SHA.init()
  val () = $SHA.update(c, ta, tl)
  val () = $A.free<byte>(ta)
  val digest = $A.alloc<byte>(64)
  val () = $SHA.finish(c, digest)
in digest end

(* The context of a judgment: bats's inputs and the listing of the .bats
   files of ./bats_modules (its first lm bytes: the NUL-separated paths) *)
#pub fn valid_context {l:agz}{n:pos}{lm:nat | lm <= n; lm <= 524288}
  (listing: !$A.arr(byte, l, n), lm: int lm)
  : [lk:agz] $A.arr(byte, lk, 64)

implement valid_context (listing, lm) = let
  var h : $B.builder_v = $B.create()
  val () = bput_v(h, "bats-valid 1\nbats ")
  val () = bput_v(h, bats_inputs_sha256())
  val () = put_char_v(h, 10)
  val @(ha, hl) = $B.into_arr(h)
  val c = $SHA.init()
  val () = $SHA.update(c, ha, hl)
  val () = $A.free<byte>(ha)
  val () = $SHA.update(c, listing, lm)
  val digest = $A.alloc<byte>(64)
  val () = $SHA.finish(c, digest)
in digest end

(* The path p[0, first NUL) with / as %, after the directory of the
   records, NUL-terminated: where the record named name is *)
fun mangle_name {l:agz}{n:pos}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (a: !$A.borrow(byte, l, n), i: int i, k: int, m: int m, out: !$B.builder_v >> $B.builder_v): void =
  if i >= m then ()
  else if i >= k then ()
  else let
    val c = byte2int0($A.read<byte>(a, i))
    val () = put_char_v(out, (if c = 47 then 37 else c))
  in mangle_name(a, i + 1, k, m, out) end

(* build/.bats_valid/<name with / as %>, NUL-terminated *)
#pub fn valid_slot (name: $B.builder_v)
  : [cap:pos | cap <= 524288][k:nat | k <= cap][l:agz] @($A.arr(byte, l, cap), int k)

implement valid_slot (name) = let
  var out : $B.builder_v = $B.create()
  val () = bput_v(out, "build/.bats_valid/")
  val @(na, nl) = $B.into_arr(name)
  val @(fz_n, bv_n) = $A.freeze<byte>(na)
  val () = mangle_name(bv_n, 0, nl, nl, out)
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
  val () = put_char_v(out, 0)
  val @(oa, ol) = $B.into_arr(out)
in @(oa, ol) end

(* The record of the file at the NUL-terminated path p *)
#pub fn valid_slot_of_path {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}
  (p: !$A.borrow(byte, lp, np), pm: int pm)
  : [cap:pos | cap <= 524288][k:nat | k <= cap][l:agz] @($A.arr(byte, l, cap), int k)

implement valid_slot_of_path (p, pm) = let
  var name : $B.builder_v = $B.create()
  val () = copy_to_builder_v(p, 0, find_null_bv_from(p, 0, pm), pm, name)
in valid_slot(name) end

(* Whether a[0, k) and b[0, k) hold the same bytes *)
fun same_key {la,lb:agz}{na,nb:pos}{k:nat | k <= na; k <= nb}{j:nat | j <= k} .<k - j>.
  (a: !$A.borrow(byte, la, na), b: !$A.borrow(byte, lb, nb), k: int k, j: int j): bool =
  if j >= k then true
  else if byte2int0($A.read<byte>(a, j)) = byte2int0($A.read<byte>(b, j)) then same_key(a, b, k, j + 1)
  else false

(* Whether the record at the NUL-terminated path slot holds exactly the
   64 digits of key *)
#pub fn valid_holds {ls,lk:agz}{ns:pos}{sm:nat | sm <= ns; sm <= 524288}
  (slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64)): bool

implement valid_holds (slot, sm, key) =
  case+ file_open_m(slot, sm, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val buf = $A.alloc<byte>(128)
      val n = (case+ $F.file_read(fd, buf, 128) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 128] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      val @(fz_b, bv_b) = $A.freeze<byte>(buf)
      val same = (if n = 64 then same_key(bv_b, key, 64, 0) else false): bool
      val () = $A.drop<byte>(fz_b, bv_b)
      val () = $A.free<byte>($A.thaw<byte>(fz_b))
    in same end

(* The digits of key as a text *)
fn key_text {lk:agz} (key: !$A.borrow(byte, lk, 64)): $B.builder_v = let
  var b : $B.builder_v = $B.create()
  val () = copy_to_builder_v(key, 0, 64, 64, b)
in b end

(* Makes build/ and build/.bats_valid/ when they are not there *)
fn make_directories (): void = let
  val @(b, b_len) = str_into_arr("build")
  val @(fz_b, bv_b) = $A.freeze<byte>(b)
  val () = $R.discard<int><$F.io_error>(file_mkdir_m(bv_b, b_len, 493))
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
  val @(v, v_len) = str_into_arr("build/.bats_valid")
  val @(fz_v, bv_v) = $A.freeze<byte>(v)
  val () = $R.discard<int><$F.io_error>(file_mkdir_m(bv_v, v_len, 493))
  val () = $A.drop<byte>(fz_v, bv_v)
in $A.free<byte>($A.thaw<byte>(fz_v)) end

(* Writes the 64 digits of key to the record at slot; the directories
   are made when the first write finds them missing *)
fn keep {ls,lk:agz}{ns:pos}{sm:nat | sm <= ns; sm <= 524288}
  (slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64)): void =
  case+ write_file_from_builder_m(slot, sm, key_text(key)) of
  | ~Wrote() => ()
  (* the directories are not there yet: made, and the write tried again *)
  | ~NotWritten($F.NotFound()) => let
      val () = make_directories()
      val () = (case+ write_settled(slot, sm, write_file_from_builder_m(slot, sm, key_text(key))) of
        | ~Settled() => ()
        (* said, and the build failed; the record is then none, which is a record to make again *)
        | ~Failed() => ())
    in end
  (* anything else is said, and the build fails *)
  | ~NotWritten(e) => let
      val () = (case+ write_settled(slot, sm, NotWritten(e)) of
        | ~Settled() => ()
        | ~Failed() => ())
    in end
  | ~WriteTooLarge() => let
      val () = (case+ write_settled(slot, sm, WriteTooLarge()) of
        | ~Settled() => ()
        | ~Failed() => ())
    in end

(* Whether a[0, 64) and b[0, 64) are the same key *)
fn same_keys {la,lb:agz} (a: !$A.borrow(byte, la, 64), b: !$A.borrow(byte, lb, 64)): bool =
  same_key(a, b, 64, 0)

(* ---- Recorded at the end ---- *)

(* A failed validation writes nothing (it leaves no build/ behind, as it
   never has): the records of what passed are kept in a text, each the
   path of its record, a NUL and the 64 digits of its key, and written
   when nothing failed *)

(* slot and key added to pend *)
fn pend_add {ls,lk:agz}{ns:pos}{sm:nat | sm <= ns}
  (slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64),
   pend: !$B.builder_v >> $B.builder_v): void = let
  val () = copy_to_builder_v(slot, 0, find_null_bv_from(slot, 0, sm), sm, pend)
  val () = put_char_v(pend, 0)
in copy_to_builder_v(key, 0, 64, 64, pend) end

(* The 64 bytes of src from `from` on, into key *)
fun key_from {lk:agz}{lf:agz}{np:pos}{pm:nat | pm <= np}{f:int}{i:nat | i <= 64} .<64 - i>.
  (src: !$A.borrow(byte, lf, np), pm: int pm, from: int f, key: !$A.arr(byte, lk, 64), i: int i): void =
  if i >= 64 then ()
  else let
    val () = $A.set<byte>(key, i, int2byte0(peek(src, from + i, pm)))
  in key_from(src, pm, from, key, i + 1) end

(* Writes the records of pend[off, len) *)
fun flush_entries {lf:agz}{np:pos}{pm:nat | pm <= np}{off:nat | off <= pm} .<pm - off>.
  (pend: !$A.borrow(byte, lf, np), pm: int pm, off: int off, len: int): void =
  if off >= len then ()
  else let
    val e = nul_in(pend, off, pm)
  in
    if e + 65 > len then ()
    else let
      var sb : $B.builder_v = $B.create()
      val () = copy_to_builder_v(pend, off, e + 1, pm, sb)
      val @(sa, sl) = $B.into_arr(sb)
      val @(fz_s, bv_s) = $A.freeze<byte>(sa)
      val key = $A.alloc<byte>(64)
      val () = key_from(pend, pm, e + 1, key, 0)
      val @(fz_k, bv_k) = $A.freeze<byte>(key)
      val () = keep(bv_s, sl, bv_k)
      val () = $A.drop<byte>(fz_k, bv_k)
      val () = $A.free<byte>($A.thaw<byte>(fz_k))
      val () = $A.drop<byte>(fz_s, bv_s)
      val () = $A.free<byte>($A.thaw<byte>(fz_s))
    in
      if e + 65 >= pm then () else flush_entries(pend, pm, e + 65, len)
    end
  end

(* Writes the records pend holds; nothing when it outgrew its builder *)
#pub fn valid_flush (pend: $B.builder_v): void

implement valid_flush (pend) = let
  val @(pa, pl) = $B.into_arr(pend)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val () = (if pl < 524288 then flush_entries(bv_p, pl, 0, pl) else ())
  val () = $A.drop<byte>(fz_p, bv_p)
in $A.free<byte>($A.thaw<byte>(fz_p)) end

(* ---- A file ---- *)

(* The key of the file at the NUL-terminated path p, judged under ctx and
   the package's unsafe flag; false (and a key that means nothing) when
   reuse is false (--cold), when the file cannot be read or when the text
   outgrew its builder *)
#pub fn valid_file_key {lx,lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}
  (ctx: !$A.borrow(byte, lx, 64), reuse: bool, p: !$A.borrow(byte, lp, np), pm: int pm, is_unsafe: bool)
  : @(bool, [lk:agz] $A.arr(byte, lk, 64))

implement valid_file_key (ctx, reuse, p, pm, is_unsafe) =
  if ~reuse then @(false, $A.alloc<byte>(64))
  else let
    var t : $B.builder_v = $B.create()
    val () = bput_v(t, "bats-valid 1 file\nctx ")
    val () = copy_to_builder_v(ctx, 0, 64, 64, t)
    val () = (if is_unsafe then bput_v(t, "\nuns 1\n") else bput_v(t, "\nuns 0\n"))
    val () = copy_to_builder_v(p, 0, find_null_bv_from(p, 0, pm), pm, t)
    val () = put_char_v(t, 10)
    val found = put_file_sha256_m(p, pm, t)
    val whole = ($B.length(t) < 524288): bool
  in @(found && whole, key_of(t)) end

(* Adds key to pend, to be recorded at slot when the whole validation has
   passed, for the file p, which passed, if p still has that key *)
#pub fn valid_file_pend {lx,lp,ls,lk:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}{ns:pos}{sm:nat | sm <= ns}
  (ctx: !$A.borrow(byte, lx, 64), p: !$A.borrow(byte, lp, np), pm: int pm, is_unsafe: bool,
   slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64),
   pend: !$B.builder_v >> $B.builder_v): void

implement valid_file_pend (ctx, p, pm, is_unsafe, slot, sm, key, pend) = let
  val @(usable, again) = valid_file_key(ctx, true, p, pm, is_unsafe)
  val @(fz_a, bv_a) = $A.freeze<byte>(again)
  val () = (if usable then (if same_keys(bv_a, key) then pend_add(slot, sm, key, pend) else ()) else ())
  val () = $A.drop<byte>(fz_a, bv_a)
in $A.free<byte>($A.thaw<byte>(fz_a)) end

(* ---- The files of a package ---- *)

(* t, with each path of the NUL-separated list files[off, len) and the
   sha256 of its file added, a line each; whether every file was read *)
fun group_text {lf:agz}{nf:pos}{fm:nat | fm <= nf; fm <= 524288}{off:nat | off <= fm} .<fm - off>.
  (files: !$A.borrow(byte, lf, nf), fm: int fm, off: int off, len: int, t: !$B.builder_v >> $B.builder_v, ok: bool): bool =
  if off >= len then ok
  else let
    val e = nul_in(files, off, fm)
    var pb : $B.builder_v = $B.create()
    val () = copy_to_builder_v(files, off, e + 1, fm, pb)
    val @(pa, pl) = $B.into_arr(pb)
    val @(fz_p, bv_p) = $A.freeze<byte>(pa)
    val () = copy_to_builder_v(files, off, e, fm, t)
    val () = put_char_v(t, 10)
    val found = put_file_sha256_m(bv_p, pl, t)
    val () = put_char_v(t, 10)
    val () = $A.drop<byte>(fz_p, bv_p)
    val () = $A.free<byte>($A.thaw<byte>(fz_p))
  in
    if e >= fm then ok && found
    else group_text(files, fm, e + 1, len, t, ok && found)
  end

(* The key of the files list[off, len) as a package, under ctx; as
   valid_file_key says *)
#pub fn valid_group_key {lx,lf:agz}{nf:pos}{fm:nat | fm <= nf; fm <= 524288}{off:nat | off <= fm}
  (ctx: !$A.borrow(byte, lx, 64), reuse: bool, files: !$A.borrow(byte, lf, nf), fm: int fm, off: int off, len: int)
  : @(bool, [lk:agz] $A.arr(byte, lk, 64))

implement valid_group_key (ctx, reuse, files, fm, off, len) =
  if ~reuse then @(false, $A.alloc<byte>(64))
  else let
    var t : $B.builder_v = $B.create()
    val () = bput_v(t, "bats-valid 1 cycles\nctx ")
    val () = copy_to_builder_v(ctx, 0, 64, 64, t)
    val () = put_char_v(t, 10)
    val read = group_text(files, fm, off, len, t, true)
    val whole = ($B.length(t) < 524288): bool
  in @(read && whole, key_of(t)) end

(* Adds key to pend for the package list[off, len), which passed, if it
   still has that key *)
#pub fn valid_group_pend {lx,lf,ls,lk:agz}{nf:pos}{fm:nat | fm <= nf; fm <= 524288}{off:nat | off <= fm}{ns:pos}{sm:nat | sm <= ns}
  (ctx: !$A.borrow(byte, lx, 64), files: !$A.borrow(byte, lf, nf), fm: int fm, off: int off, len: int,
   slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64),
   pend: !$B.builder_v >> $B.builder_v): void

implement valid_group_pend (ctx, files, fm, off, len, slot, sm, key, pend) = let
  val @(usable, again) = valid_group_key(ctx, true, files, fm, off, len)
  val @(fz_a, bv_a) = $A.freeze<byte>(again)
  val () = (if usable then (if same_keys(bv_a, key) then pend_add(slot, sm, key, pend) else ()) else ())
  val () = $A.drop<byte>(fz_a, bv_a)
in $A.free<byte>($A.thaw<byte>(fz_a)) end

(* ---- The #use packages of a file (bats#310) ----

   collect_uses (lock.bats) lexes every .bats file of a directory for its
   #use lines. resolve_deps does that for the project's src, each path
   dependency and each package of bats_modules, before every check, so a
   check in which nothing had changed still lexed them all (8% of one on
   quire's set). The names a file gives depend on its bytes and on bats's
   lexer, and on nothing else, so a file that was lexed leaves a record
   under build/.bats_valid/, named "uses " and the file's path:

     <64 hex>   the key: the sha256 of
                  bats-uses 1 file
                  bats <bats_inputs_sha256>
                  <path>
                  <sha256 of the file>
     <64 hex>   the sha256 of the body below
     <body>     the names the file's #use lines give, in order, each
                followed by a NUL. A package name holds no NUL (the lexer
                ends it at a space, a tab, a line feed or a NUL), so the
                NULs divide the names.

   A record is used only when the file has the key it has now and the body
   has the sha256 the record names, so a torn or garbled record is not used
   and the file is lexed again. A record is written only when the body fits
   under the builder's capacity with its header, so a body is never kept cut
   short, into a build/.bats_valid/ that is there (a record does not make
   build/: a validation that fails leaves none), and only when the file still
   has the key it was lexed under. No time is read. --cold lexes every file
   and writes the records again. *)

(* The key of the .bats file at the NUL-terminated path p, and whether the
   file could be read (only then is its record kept) *)
#pub fn uses_key {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288} (p: !$A.borrow(byte, lp, np), pm: int pm)
  : @(bool, [lk:agz] $A.arr(byte, lk, 64))

implement uses_key (p, pm) = let
  var t : $B.builder_v = $B.create()
  val () = bput_v(t, "bats-uses 1 file\nbats ")
  val () = bput_v(t, bats_inputs_sha256())
  val () = put_char_v(t, 10)
  val () = copy_to_builder_v(p, 0, find_null_bv_from(p, 0, pm), pm, t)
  val () = put_char_v(t, 10)
  val found = put_file_sha256_m(p, pm, t)
  val () = put_char_v(t, 10)
  val whole = ($B.length(t) < 524288): bool
in @(found && whole, key_of(t)) end

(* Whether the file at p still has the key it was keyed with: it is hashed
   again, so a file that changed while it was lexed is not recorded as what
   it was (the rule of the validated records, valid_file_pend) *)
#pub fn uses_same {lp,lk:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}
  (p: !$A.borrow(byte, lp, np), pm: int pm, key: !$A.borrow(byte, lk, 64)): bool

implement uses_same (p, pm, key) = let
  val @(usable, again) = uses_key(p, pm)
  val @(fz_a, bv_a) = $A.freeze<byte>(again)
  val same = (if usable then same_keys(bv_a, key) else false): bool
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
in same end

(* DESIGN CHECK (bats#421, overrides.md): the names of a file are kept as
   the 'uses' of a file are, by the same record format (uses_hit reads and
   uses_write writes it), under a key and a slot of their own *)

(* The key of the .bats file at the NUL-terminated path p for its names
   ('bats-facts 1 file'), as uses_key says *)
#pub fn facts_key {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288} (p: !$A.borrow(byte, lp, np), pm: int pm)
  : @(bool, [lk:agz] $A.arr(byte, lk, 64))

#pub fn facts_same {lp,lk:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288}
  (p: !$A.borrow(byte, lp, np), pm: int pm, key: !$A.borrow(byte, lk, 64)): bool

(* build/.bats_valid/facts <path>, NUL-terminated *)
#pub fn facts_slot {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288} (p: !$A.borrow(byte, lp, np), pm: int pm)
  : [cap:pos | cap <= 524288][k:nat | k <= cap][l:agz] @($A.arr(byte, l, cap), int k)

(* build/.bats_valid/uses <path>, NUL-terminated: where the record of the
   file at p is *)
#pub fn uses_slot {lp:agz}{np:pos}{pm:nat | pm <= np; pm <= 524288} (p: !$A.borrow(byte, lp, np), pm: int pm)
  : [cap:pos | cap <= 524288][k:nat | k <= cap][l:agz] @($A.arr(byte, l, cap), int k)

implement uses_slot (p, pm) = let
  var name : $B.builder_v = $B.create()
  val () = bput_v(name, "uses ")
  val () = copy_to_builder_v(p, 0, find_null_bv_from(p, 0, pm), pm, name)
in valid_slot(name) end

(* Whether the file (n bytes, of which the first 130 are its record's
   header) has the header that the key and the sha256 of its body make;
   with the body (which the caller uses only when it holds) *)
fn record_holds {lf,lk:agz}{m:pos}
  (file: !$A.borrow(byte, lf, m), size: int m, n: int, key: !$A.borrow(byte, lk, 64))
  : @(bool, $B.builder_v) =
  if n < 130 then @(false, $B.create())
  else let
    var body_copy : $B.builder_v = $B.create()
    val () = copy_to_builder_v(file, 130, n, size, body_copy)
    val digest = key_of(body_copy)
    val @(fd, bd) = $A.freeze<byte>(digest)
    var expected : $B.builder_v = $B.create()
    val () = copy_to_builder_v(key, 0, 64, 64, expected)
    val () = put_char_v(expected, 10)
    val () = copy_to_builder_v(bd, 0, 64, 64, expected)
    val () = put_char_v(expected, 10)
    val () = $A.drop<byte>(fd, bd)
    val () = $A.free<byte>($A.thaw<byte>(fd))
    var head : $B.builder_v = $B.create()
    val () = copy_to_builder_v(file, 0, 130, size, head)
    val @(expected_arr, el) = $B.into_arr(expected)
    val @(fe, expected_bytes) = $A.freeze<byte>(expected_arr)
    val @(head_arr, hl) = $B.into_arr(head)
    val @(fh, head_bytes) = $A.freeze<byte>(head_arr)
    val same = (if el = 130 then (if hl = 130 then same_key(expected_bytes, head_bytes, 130, 0) else false) else false): bool
    val () = $A.drop<byte>(fe, expected_bytes)
    val () = $A.free<byte>($A.thaw<byte>(fe))
    val () = $A.drop<byte>(fh, head_bytes)
    val () = $A.free<byte>($A.thaw<byte>(fh))
    val body = $B.create()
    val () = copy_to_builder_v(file, 130, n, size, body)
  in @(same, body) end

(* The body of the record at slot, when reuse is true and the record holds
   the key (record_holds); false with an empty body otherwise, and when the
   record cannot be read *)
#pub fn uses_hit {ls,lk:agz}{ns:pos}{sm:nat | sm <= ns; sm <= 524288}
  (reuse: bool, slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64))
  : @(bool, $B.builder_v)

implement uses_hit (reuse, slot, sm, key) =
  if ~reuse then @(false, $B.create())
  else case+ read_whole_m(slot, sm) of
  | ~whole_err(_) => @(false, $B.create())
  | ~whole_ok(ar, piece, m, n) => let
      val @(fz, bv) = $A.freeze<byte>(piece)
      val @(held, body) = record_holds(bv, m, n, key)
      val () = $A.drop<byte>(fz, bv)
      val () = whole_free(ar, $A.thaw<byte>(fz))
    in @(held, body) end

(* The record's text at slot, when build/.bats_valid/ is there (a check made
   it): a record never makes build/ (a failed validation leaves none), so
   the first check of a project writes none, and the next writes them *)
fn put_record {ls:agz}{ns:pos}{sm:nat | sm <= ns; sm <= 524288}
  (slot: !$A.borrow(byte, ls, ns), sm: int sm, text: $B.builder_v): void =
  case+ write_file_from_builder_m(slot, sm, text) of
  | ~Wrote() => ()
  (* no build/.bats_valid/: no record, by design (above) *)
  | ~NotWritten($F.NotFound()) => ()
  | ~NotWritten(e) => let
      val () = (case+ write_settled(slot, sm, NotWritten(e)) of
        | ~Settled() => ()
        | ~Failed() => ())
    in end
  | ~WriteTooLarge() => let
      val () = (case+ write_settled(slot, sm, WriteTooLarge()) of
        | ~Settled() => ()
        | ~Failed() => ())
    in end

(* Writes the record at slot for the key and the body (of len bytes), unless
   the body does not fit with its header under the builder's capacity *)
#pub fn uses_write {ls,lk,lb:agz}{ns:pos}{sm:nat | sm <= ns; sm <= 524288}{nb:pos}{len:nat | len <= nb}
  (slot: !$A.borrow(byte, ls, ns), sm: int sm, key: !$A.borrow(byte, lk, 64),
   body: !$A.borrow(byte, lb, nb), len: int len): void

implement uses_write (slot, sm, key, body, len) =
  if len >= 524288 - 130 then ()
  else let
    var body_copy : $B.builder_v = $B.create()
    val () = copy_to_builder_v(body, 0, len, len, body_copy)
    val digest = key_of(body_copy)
    val @(fd, bd) = $A.freeze<byte>(digest)
    var text : $B.builder_v = $B.create()
    val () = copy_to_builder_v(key, 0, 64, 64, text)
    val () = put_char_v(text, 10)
    val () = copy_to_builder_v(bd, 0, 64, 64, text)
    val () = put_char_v(text, 10)
    val () = copy_to_builder_v(body, 0, len, len, text)
    val () = $A.drop<byte>(fd, bd)
    val () = $A.free<byte>($A.thaw<byte>(fd))
    val () = put_record(slot, sm, text)
  in end
