staload "./with_env.sats"
staload "array/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "list/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* with_env -- bats with-env <env-file> <command> [args...] (bats-lang/bats#277).

   A shell that reads no profile gets a machine's bats settings
   (BATS_SLOTS, BATS_LOCK_DIR, BATS_CACHE_DIR, BATS_REPOSITORY, and whatever
   else the machine sets, such as pwa's PWA_TEST_SLOTS) from a file: the
   file's variables are added to this process's environment, each replacing
   that variable, and the command is run with them, with the arguments it
   was given, this process's standard streams, and its exit status becoming
   bats's own.

   The file is read as a dotenv file, not run (comparable tools: docker's
   --env-file and systemd's EnvironmentFile do not expand; dotenvx and
   Compose do, and direnv sources a shell):

     * a line is  NAME=VALUE  or  export NAME=VALUE,  NAME being letters,
       digits and underscores, not starting with a digit; blank lines, lines
       that start with # and lines of another shape are passed over;
     * a value is the rest of the line without the blanks around it, or that
       text in single quotes (taken literally) or double quotes; a quote with
       no match stays in the value, and a ` # comment` after an unquoted
       value is part of it;
     * in an unquoted or double-quoted value $NAME and ${NAME} stand for the
       variable of that name in this process's environment (the empty text
       when it is unset), so PATH=/opt/bin:$PATH works; nothing else is
       interpreted: no command substitution, no escapes (a backslash is a
       backslash, and \$ is a backslash and an expansion), no ~; a $ that
       starts neither form is a $;
     * a variable set on more than one line has its last value (found in one
       pass: a table of the names, so the time is that of the file);
     * the file is at most 64 KiB and sets at most 1024 variables, the
       command line at most 4095 bytes (counting the NUL after each
       argument, the program's name included);
     * a command name with no / is looked for in the directories of the PATH
       the command runs with, the file's when it sets one, as the shell does
       (the first file that is not a directory and has an execute bit; a directory, or a file
       without one, is passed over and remembered, so 126 and not 127 when
       nothing better is found).

   A usage error (no file, no command, an unreadable or too large file, more
   than 1024 variables, a value that cannot be made because it uses a
   variable whose name is over 255 bytes or whose value is over 64 KiB, an entry
   over 131071 bytes (Linux's MAX_ARG_STRLEN less the NUL), variables together
   over 1 MiB, a NUL byte in the file, a command line too long to be read whole) is status
   2; a command that is found nowhere is 127 and one that cannot be run 126
   (with the system's reason). The status of a command that a signal ended is
   1: the process package's child_wait says only that it did not exit. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"

(* The byte at p, whatever int p is, or 0 outside bv[0, n) *)
fn byte_at {l:agz}{n:pos} (bv: !$A.borrow(byte, l, n), p: int, n: int n): int =
  peek(bv, g1ofg0(p), n)

(* The first position at or after p of bv[0, n) that holds byte c, or the
   first one at or after lim, or n *)
fun find_byte {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n, lim: int, c: int)
  : [r:nat | p <= r; r <= n] int r =
  if p >= n then p
  else if p >= lim then p
  else if peek(bv, p, n) = c then p
  else find_byte(bv, p + 1, n, lim, c)

(* The first position at or after p, below lim, that holds no space or tab *)
fun skip_blank {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n, lim: int)
  : [r:nat | p <= r; r <= n] int r =
  if p >= n then p
  else if p >= lim then p
  else let
    val c = peek(bv, p, n)
  in
    if c = 32 then skip_blank(bv, p + 1, n, lim)
    else if c = 9 then skip_blank(bv, p + 1, n, lim)
    else p
  end

(* q less the blanks (space, tab, carriage return) that end bv[lo, q) *)
fun trim_end {l:agz}{n:pos}{q:nat | q <= n} .<q>.
  (bv: !$A.borrow(byte, l, n), lo: int, q: int q, n: int n)
  : [r:nat | r <= q] int r =
  if q <= 0 then q
  else if q <= lo then q
  else let
    val c = peek(bv, q - 1, n)
  in
    if c = 32 then trim_end(bv, lo, q - 1, n)
    else if c = 9 then trim_end(bv, lo, q - 1, n)
    else if c = 13 then trim_end(bv, lo, q - 1, n)
    else q
  end

fn is_name_start (c: int): bool =
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c = 95

fn is_name_char (c: int): bool =
  is_name_start(c) || (c >= 48 && c <= 57)

(* The end of the name that starts at p: the first position at or after p
   below lim that is not a name character *)
fun name_end {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n, lim: int)
  : [r:nat | p <= r; r <= n] int r =
  if p >= n then p
  else if p >= lim then p
  else if is_name_char(peek(bv, p, n)) then name_end(bv, p + 1, n, lim)
  else p

(* Whether bv[a, ae) and bv[b, be) are the same bytes *)
fun same_span {l:agz}{n:pos}{j:nat | j <= n} .<n - j>.
  (bv: !$A.borrow(byte, l, n), a: int, ae: int, b: int, be: int, j: int j, n: int n): bool =
  if ae - a <> be - b then false
  else if a + j >= ae then true
  else if j >= n then true
  else if byte_at(bv, a + j, n) <> byte_at(bv, b + j, n) then false
  else same_span(bv, a, ae, b, be, j + 1, n)

(* bv[a, b) appended to out *)
fun put_span {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, b: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): void =
  if p >= n then ()
  else if p >= b then ()
  else let
    val () = put_char_v(out, peek(bv, p, n))
  in put_span(bv, p + 1, b, n, out) end

(* bv[a, b) appended to out, whatever ints a and b are *)
fn put_range {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), a: int, b: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): void = let
  val a1 = g1ofg0(a)
in
  if a1 < 0 then ()
  else if a1 > n then ()
  else put_span(bv, a1, b, n, out)
end

(* bv[a, b) copied into name[j, 255), at most *)
fun copy_name {l:agz}{ln:agz}{n:pos}{j:nat | j <= 255} .<255 - j>.
  (bv: !$A.borrow(byte, l, n), a: int, b: int, n: int n,
   name: !$A.arr(byte, ln, 256), j: int j): int =
  if j >= 255 then j
  else if a + j >= b then j
  else let
    val () = poke_arr(name, j, 256, byte_at(bv, a + j, n))
  in copy_name(bv, a, b, n, name, j + 1) end

(* The bytes out holds *)
fn builder_size (out: !$B.builder_v >> $B.builder_v): int = $B.length(out)

(* The value of the variable whose NUL-terminated name is in name appended
   to out (nothing when it is unset); false when the value is over 64 KiB
   or would take out over 131071 bytes (Linux's MAX_ARG_STRLEN, 131072,
   less the NUL), in which case nothing is appended, so no value is ever
   cut short and a value is never copied past what exec accepts *)
fn put_variable_named {ln:agz}
  (name: !$A.arr(byte, ln, 256), out: !$B.builder_v >> $B.builder_v): bool = let
  val value = $A.alloc<byte>(65537)
  val got = $E.get_cstr(name, 256, value, 65537)
  val k = (case+ got of | ~$R.some(n) => n | ~$R.none() => 0): int
  val @(fz_v, bv_v) = $A.freeze<byte>(value)
  val ok = (k <= 65536 && k <= 131071 - builder_size(out)): bool
  val () = (if ok then copy_to_builder_v(bv_v, 0, k, 65537, out) else ())
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
in ok end

(* The value of the variable named bv[a, b) in this process's environment
   appended to out; nothing when it is unset. False, and nothing appended,
   when the name is over 255 bytes or the value over 64 KiB *)
fn put_variable {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), a: int, b: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): bool =
  if b - a > 255 then false
  else let
    val name = $A.alloc<byte>(256)
    val len = copy_name(bv, a, b, n, name, 0)
    val () = poke_arr(name, g1ofg0(len), 256, 0)
    val ok = put_variable_named(name, out)
  in $A.free<byte>(name); ok end

(* bv[p, b) appended to out with its $NAME and ${NAME} replaced by the
   environment's; false when one cannot be (see put_variable) *)
fun put_expanded {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, b: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): bool =
  if p >= n then true
  else if p >= b then true
  else let
    val c = peek(bv, p, n)
  in
    if c <> 36 then let
      val () = put_char_v(out, c)
    in put_expanded(bv, p + 1, b, n, out) end
    else let
      val c1 = peek(bv, p + 1, n)
    in
      if c1 = 123 then (
        if p + 2 > n then let
          val () = put_char_v(out, c)
        in put_expanded(bv, p + 1, b, n, out) end
        else let
          val close = find_byte(bv, p + 2, n, b, 125)
        in
          if close < b then let
            val ok = put_variable(bv, p + 2, close, n, out)
          in
            if ~ok then false
            else if close + 1 > n then true
            else put_expanded(bv, close + 1, b, n, out)
          end
          else let
            val () = put_char_v(out, c)
          in put_expanded(bv, p + 1, b, n, out) end
        end)
      else if is_name_start(c1) then let
        val ne = name_end(bv, p + 1, n, b)
        val ok = put_variable(bv, p + 1, ne, n, out)
      in
        if ok then put_expanded(bv, ne, b, n, out) else false
      end
      else let
        val () = put_char_v(out, c)
      in put_expanded(bv, p + 1, b, n, out) end
    end
  end

(* One line of the file that sets a variable: where its name is
   (bv[name_at, name_to)) and where its value starts *)
typedef assignment = @{found= bool, name_at= int, name_to= int, value_at= int}

fn no_assignment (): assignment =
  @{found= false, name_at= 0, name_to= 0, value_at= 0}

(* Whether bv[i, e) starts with export and a blank *)
fn exported {l:agz}{n:pos} (bv: !$A.borrow(byte, l, n), i: int, e: int, n: int n): bool =
  byte_at(bv, i, n) = 101 && byte_at(bv, i + 1, n) = 120 && byte_at(bv, i + 2, n) = 112
  && byte_at(bv, i + 3, n) = 111 && byte_at(bv, i + 4, n) = 114 && byte_at(bv, i + 5, n) = 116
  && (byte_at(bv, i + 6, n) = 32 || byte_at(bv, i + 6, n) = 9) && i + 6 < e

(* Where the name of a line starts, past an export *)
fn name_start_of {l:agz}{n:pos}{i:nat | i <= n}{e:nat | e <= n}
  (bv: !$A.borrow(byte, l, n), i: int i, e: int e, n: int n)
  : [r:nat | r <= n] int r =
  if exported(bv, i, e, n) then (if i + 7 <= n then skip_blank(bv, i + 7, n, e) else n)
  else i

(* The assignment on the line bv[s, e): optional blanks, optional
   export and a blank, a name, = *)
fn line_assignment {l:agz}{n:pos}{s:nat | s <= n}{e:nat | e <= n}
  (bv: !$A.borrow(byte, l, n), s: int s, e: int e, n: int n): assignment = let
  val i0 = skip_blank(bv, s, n, e)
in
  if i0 >= e then no_assignment()
  else if byte_at(bv, i0, n) = 35 then no_assignment()
  else let
    val i1 = name_start_of(bv, i0, e, n)
  in
    if i1 >= e then no_assignment()
    else if ~is_name_start(byte_at(bv, i1, n)) then no_assignment()
    else let
      val ne = name_end(bv, i1, n, e)
    in
      if ne >= e then no_assignment()
      else if byte_at(bv, ne, n) <> 61 then no_assignment()
      else @{found= true, name_at= i1, name_to= ne, value_at= ne + 1}
    end
  end
end

(* The value of the assignment on a line ending at e, appended to out:
   single quotes literally, double quotes and none expanded; false when an
   expansion cannot be made (see put_variable) *)
fn put_value {l:agz}{n:pos}{e:nat | e <= n}
  (bv: !$A.borrow(byte, l, n), value_at: int, e: int e, n: int n,
   out: !$B.builder_v >> $B.builder_v): bool =
  let
    val v = g1ofg0(value_at)
  in
  if v < 0 then true
  else if v > n then true
  else let
    val a = skip_blank(bv, v, n, e)
    val t = trim_end(bv, a, e, n)
  in
    if t - a >= 2 then (
      if peek(bv, a, n) = 39 && peek(bv, t - 1, n) = 39 then let
        val () = put_span(bv, a + 1, t - 1, n, out)
      in true end
      else if peek(bv, a, n) = 34 && peek(bv, t - 1, n) = 34 then
        put_expanded(bv, a + 1, t - 1, n, out)
      else put_expanded(bv, a, t, n, out))
    else put_expanded(bv, a, t, n, out)
  end
  end

(* put_value, whatever int e is *)
fn put_value_at {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), value_at: int, e: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): bool = let
  val e1 = g1ofg0(e)
in
  if e1 < 0 then true
  else if e1 > n then true
  else put_value(bv, value_at, e1, n, out)
end

(* Which line sets which variable, found in one pass over the file: a table
   of ints, an entry per variable (five ints at 5 * k: where its name is,
   where it ends, where the value of its last line starts, where that
   line ends, and the next entry of its bucket, counted from 1) and, after
   the 1024 entries, 1024 buckets holding the latest entry of each hash of
   a name, counted from 1 (0 is none). A line that sets a variable already
   in the table replaces that entry's value, so the time is that of the
   file and its chains, not of its lines squared. A file that sets more
   than 1024 variables is refused (the table_put that would add the 1025th
   answers 1025): an argument of the process package is an array of 512
   KiB, so a variable costs about 130 KiB of memory and a tenth of a
   millisecond, and a file of 64 KiB can name 7000 of them, which took 1 GB
   and 3 seconds. *)

fn table_get {lt:agz} (tab: !$A.arr(int, lt, 6144), p: int): int = let
  val p1 = g1ofg0(p)
in
  if p1 < 0 then 0
  else if p1 >= 6144 then 0
  else $A.get<int>(tab, p1)
end

fn table_set {lt:agz} (tab: !$A.arr(int, lt, 6144), p: int, v: int): void = let
  val p1 = g1ofg0(p)
in
  if p1 < 0 then ()
  else if p1 >= 6144 then ()
  else $A.set<int>(tab, p1, v)
end

(* The hash of bv[p, b), below 1024, h being the hash so far *)
fun hash_span {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, b: int, n: int n, h: int): int =
  if p >= n then h
  else if p >= b then h
  else hash_span(bv, p + 1, b, n, (h * 31 + peek(bv, p, n)) % 1024)

(* The hash of bv[a, b), whatever ints a and b are *)
fn hash_range {l:agz}{n:pos} (bv: !$A.borrow(byte, l, n), a: int, b: int, n: int n): int = let
  val a1 = g1ofg0(a)
in
  if a1 < 0 then 0
  else if a1 > n then 0
  else hash_span(bv, a1, b, n, 0)
end

(* The entry (counted from 1) from entry k on along its chain whose name is
   bv[a, b), or 0; at most fuel entries are looked at *)
fun chain_find {l:agz}{n:pos}{lt:agz}{f:nat} .<f>.
  (bv: !$A.borrow(byte, l, n), n: int n, tab: !$A.arr(int, lt, 6144), k: int,
   a: int, b: int, fuel: int f): int =
  if k <= 0 then 0
  else if fuel <= 0 then 0
  else let
    val base = 5 * (k - 1)
  in
    if same_span(bv, table_get(tab, base), table_get(tab, base + 1), a, b, 0, n) then k
    else chain_find(bv, n, tab, table_get(tab, base + 4), a, b, fuel - 1)
  end

(* The assignment x, on a line ending at e, put in the table that holds
   count entries: the number it holds then *)
fn table_put {l:agz}{n:pos}{lt:agz}
  (bv: !$A.borrow(byte, l, n), n: int n, tab: !$A.arr(int, lt, 6144), x: assignment, e: int, count: int): int = let
  val slot = 5120 + hash_range(bv, x.name_at, x.name_to, n)
  val head = table_get(tab, slot)
  val found = chain_find(bv, n, tab, head, x.name_at, x.name_to, 1100)
in
  if found > 0 then let
    val base = 5 * (found - 1)
    val () = table_set(tab, base + 2, x.value_at)
    val () = table_set(tab, base + 3, e)
  in count end
  else if count >= 1024 then 1025
  else let
    val base = 5 * count
    val () = table_set(tab, base, x.name_at)
    val () = table_set(tab, base + 1, x.name_to)
    val () = table_set(tab, base + 2, x.value_at)
    val () = table_set(tab, base + 3, e)
    val () = table_set(tab, base + 4, head)
    val () = table_set(tab, slot, count + 1)
  in count + 1 end
end

(* The lines of bv[s, size) put in the table that holds count entries: the
   number it holds then *)
fun table_fill {l:agz}{n:pos}{lt:agz}{s:nat | s <= n} .<n - s>.
  (bv: !$A.borrow(byte, l, n), s: int s, size: int, n: int n, tab: !$A.arr(int, lt, 6144), count: int): int =
  if s >= size then count
  else let
    val e = find_byte(bv, s, n, size, 10)
    val x = line_assignment(bv, s, e, n)
    val count2 = (if x.found then table_put(bv, n, tab, x, e, count) else count): int
  in
    if count2 > 1024 then count2
    else if e + 1 > n then count2
    else table_fill(bv, e + 1, size, n, tab, count2)
  end

(* Whether bv[a, b) is PATH *)
fn is_path_name {l:agz}{n:pos} (bv: !$A.borrow(byte, l, n), a: int, b: int, n: int n): bool =
  b - a = 4 && byte_at(bv, a, n) = 80 && byte_at(bv, a + 1, n) = 65
  && byte_at(bv, a + 2, n) = 84 && byte_at(bv, a + 3, n) = 72

(* Frees the entries *)
fun arguments_free {n:nat} .<n>. (xs: $L.list_vt($P.arg_entry, n)): void =
  case+ xs of
  | ~$L.list_vt_nil() => ()
  | ~$L.list_vt_cons(x, tl) => let
      val @(entry_a, _) = x
      val () = $A.free<byte>(entry_a)
    in arguments_free(tl) end

(* The NAME=VALUE entries of the table's first k entries, in order, consed
   onto acc, the variables expanded, budget bytes (a NUL counted after each
   entry) being what the entries together may take. When the value of an
   entry cannot be made (see put_variable), or the entry is over 131071
   bytes, or the entries would take more than the budget, the number of
   that entry and what has been made so far; else ~1. The value of PATH, when
   the file sets it, is also appended to path_out and the answer says so. *)
fun entries_make {l:agz}{n:pos}{lt:agz}{k:nat} .<k>.
  (bv: !$A.borrow(byte, l, n), n: int n, tab: !$A.arr(int, lt, 6144), k: int k,
   budget: int, acc: $L.listv($P.arg_entry), has_path: bool, path_out: !$B.builder_v >> $B.builder_v)
  : @(int, bool, $L.listv($P.arg_entry)) =
  if k <= 0 then @(~1, has_path, acc)
  else let
    val base = 5 * (k - 1)
    val name_at = table_get(tab, base)
    val name_to = table_get(tab, base + 1)
    val value_at = table_get(tab, base + 2)
    val line_end = table_get(tab, base + 3)
    var entry : $B.builder_v = $B.create()
    val () = put_range(bv, name_at, name_to, n, entry)
    val () = put_char_v(entry, 61)
    val made = put_value_at(bv, value_at, line_end, n, entry)
    val size = builder_size(entry)
    val fits = (size <= 131071 && size + 1 <= budget): bool
    val made_entry = mk_arg(entry)
  in
    if made && fits then let
      val is_path = is_path_name(bv, name_at, name_to, n)
      val () = (if is_path then let
          val _ = put_value_at(bv, value_at, line_end, n, path_out)
        in () end else ())
    in entries_make(bv, n, tab, k - 1, budget - size - 1, $L.list_vt_cons(made_entry, acc),
         (if is_path then true else has_path), path_out) end
    else let
      val @(made_a, _) = made_entry
      val () = $A.free<byte>(made_a)
    in @(k - 1, has_path, acc) end
  end

(* The NAME=VALUE entries of the table's first count entries; ~2 for a table
   that holds more than 1024 *)
fn entries_made {l:agz}{n:pos}{lt:agz}
  (bv: !$A.borrow(byte, l, n), n: int n, tab: !$A.arr(int, lt, 6144), count: int,
   has_path: bool, path_out: !$B.builder_v >> $B.builder_v)
  : @(int, bool, $L.listv($P.arg_entry)) = let
  val k = g1ofg0(count)
in
  if k < 0 then @(~1, has_path, $L.list_vt_nil())
  else if k > 1024 then @(~2, has_path, $L.list_vt_nil())
  else entries_make(bv, n, tab, k, 1048576, $L.list_vt_nil(), has_path, path_out)
end

(* The NUL-terminated arguments of bv[p, total) as entries, reversed onto acc *)
fun arguments {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (bv: !$A.borrow(byte, l, 4096), p: int p, total: int,
   acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if p >= total then acc
  else let
    val z = find_byte(bv, p, 4096, 4096, 0)
    var entry : $B.builder_v = $B.create()
    val () = put_span(bv, p, (if z < total then z else total), 4096, entry)
    val acc2 = $L.list_vt_cons(mk_arg(entry), acc)
  in
    if z + 1 > 4096 then acc2
    else arguments(bv, z + 1, total, acc2)
  end

fn usage_error (): void = let
  val () = prerr! ("usage: bats with-env <env-file> <command> [args...]")
  val () = prerr_newline()
in set_exit_code(2) end

fn error_about {l:agz}
  (bv: !$A.borrow(byte, l, 4096), at: int, to: int, before: string, after: string, status: int): void = let
  val () = prerr! ("error: ", before)
  val () = prerr_seg(bv, g1ofg0(at), to, 4096)
  val () = prerr! (after)
  val () = prerr_newline()
in set_exit_code(status) end

(* How the command is found *)
datatype resolution =
  | CommandFound
  | CommandNotFound
  | CommandNotAllowed
  | PathTooLong

(* Whether the NUL-terminated name in bv is a directory *)
fn is_directory {l:agz} (bv: !$A.borrow(byte, l, 524288)): bool =
  case+ $F.dir_open(bv, 524288) of
  | ~$R.ok(d) => let val () = $R.discard<int><$F.io_error>($F.dir_close(d)) in true end
  | ~$R.err(_) => false

(* Whether the NUL-terminated name in bv has an execute bit *)
fn is_executable {l:agz} (bv: !$A.borrow(byte, l, 524288)): bool =
  case+ $F.file_mode(bv, 524288) of
  | ~$R.ok(m) => let
      val m0 = g0ofg1(m)
    in (m0 / 64) % 2 + (m0 / 8) % 2 + m0 % 2 > 0 end
  | ~$R.err(_) => false

(* A resolution that names no file, with the name of one not used *)
fn without_file (r: resolution): [l:agz] @(resolution, $A.arr(byte, l, 524288)) = let
  val unused = $A.alloc<byte>(524288)
in @(r, unused) end

(* The command bv[command_at, command_to) in the directory bv_path[p, q)
   ("." when empty), as a NUL-terminated name, and 0 when there is no such
   file, 1 when there is one that cannot be run (a directory, no execute
   bit), 2 when there is one that can *)
fn try_candidate {lp:agz}{lc:agz}
  (bv_path: !$A.borrow(byte, lp, 524288), p: int, q: int,
   bv: !$A.borrow(byte, lc, 4096), command_at: int, command_to: int)
  : [l:agz] @(int, $A.arr(byte, l, 524288)) = let
  var candidate : $B.builder_v = $B.create()
  val () = (if q > p then put_range(bv_path, p, q, 524288, candidate)
    else put_char_v(candidate, 46))
  val () = put_char_v(candidate, 47)
  val () = put_range(bv, command_at, command_to, 4096, candidate)
  val () = put_char_v(candidate, 0)
  val @(candidate_a, _) = $B.to_arr(candidate)
  val @(fz_c, bv_c) = $A.freeze<byte>(candidate_a)
  val state = (if ~($F.file_exists(bv_c, 524288)) then 0
    else if is_directory(bv_c) then 1
    else if is_executable(bv_c) then 2
    else 1): int
  val () = $A.drop<byte>(fz_c, bv_c)
in @(state, $A.thaw<byte>(fz_c)) end

(* The first directory of the PATH text bv_path[p, plen), a segment of the
   colon separated list, that holds the command as a file that can be run,
   as execvp looks: the resolution and the NUL-terminated name. denied says
   that an earlier directory held a file that could not be run *)
fun search_path {lp:agz}{lc:agz}{p:nat | p <= 524288} .<524288 - p>.
  (bv_path: !$A.borrow(byte, lp, 524288), p: int p, plen: int,
   bv: !$A.borrow(byte, lc, 4096), command_at: int, command_to: int, denied: bool)
  : [l:agz] @(resolution, $A.arr(byte, l, 524288)) =
  if p > plen then without_file(if denied then CommandNotAllowed() else CommandNotFound())
  else let
    val q = find_byte(bv_path, p, 524288, plen, 58)
    val @(state, found_a) = try_candidate(bv_path, p, q, bv, command_at, command_to)
  in
    if state = 2 then @(CommandFound(), found_a)
    else let
      val () = $A.free<byte>(found_a)
      val denied2 = (denied || state = 1): bool
    in
      if q >= 524288 then without_file(if denied2 then CommandNotAllowed() else CommandNotFound())
      else if q >= plen then without_file(if denied2 then CommandNotAllowed() else CommandNotFound())
      else search_path(bv_path, q + 1, plen, bv, command_at, command_to, denied2)
    end
  end

(* The PATH of the environment appended to out; false when it is over 64 KiB *)
fn put_environment_path (out: !$B.builder_v >> $B.builder_v): bool = let
  val name = $A.alloc<byte>(256)
  val () = poke_arr(name, 0, 256, 80)
  val () = poke_arr(name, 1, 256, 65)
  val () = poke_arr(name, 2, 256, 84)
  val () = poke_arr(name, 3, 256, 72)
  val ok = put_variable_named(name, out)
in $A.free<byte>(name); ok end

(* Whether bv[at, to) has a / in it *)
fn has_slash {l:agz} (bv: !$A.borrow(byte, l, 4096), at: int, to: int): bool = let
  val a = g1ofg0(at)
in
  if a < 0 then false
  else if a > 4096 then false
  else find_byte(bv, a, 4096, to, 47) < to
end

(* Where the command bv[command_at, command_to) is: a command with a / in it
   is the file of that name, any other is looked for as the shell does, in
   the directories of the PATH the command will run with, which is the text
   path_a[0, plen) (the file's PATH when it sets one, else this process's;
   known says it could be had; empty, the directories execvp uses). The name
   is NUL-terminated. *)
fn resolve_command {l:agz}{lp:agz}
  (bv: !$A.borrow(byte, l, 4096), command_at: int, command_to: int,
   known: bool, path_a: $A.arr(byte, lp, 524288), plen: int)
  : [lr:agz] @(resolution, $A.arr(byte, lr, 524288)) =
  if command_to <= command_at then let
    val () = $A.free<byte>(path_a)
  in without_file(CommandNotFound()) end
  else if has_slash(bv, command_at, command_to) then let
    val () = $A.free<byte>(path_a)
    var direct : $B.builder_v = $B.create()
    val () = put_range(bv, command_at, command_to, 4096, direct)
    val () = put_char_v(direct, 0)
    val @(direct_a, _) = $B.to_arr(direct)
  in @(CommandFound(), direct_a) end
  else let
    val @(fz_t, bv_t) = $A.freeze<byte>(path_a)
    val found = (if known then search_path(bv_t, 0, plen, bv, command_at, command_to, false)
      else without_file(PathTooLong())): [lr:agz] @(resolution, $A.arr(byte, lr, 524288))
    val () = $A.drop<byte>(fz_t, bv_t)
    val () = $A.free<byte>($A.thaw<byte>(fz_t))
  in found end

(* "error: bats with-env: cannot run <command>: <why>" for the error code *)
fn cannot_run {l:agz}
  (bv: !$A.borrow(byte, l, 4096), at: int, to: int, code: int): void = let
  val () = prerr! ("error: bats with-env: cannot run ")
  val () = prerr_seg(bv, g1ofg0(at), to, 4096)
  val () = prerr! (": ")
  val why = $A.alloc<byte>(256)
  val k = $P.os_error_text(code, why, 256)
  val @(fz_w, bv_w) = $A.freeze<byte>(why)
  val () = prerr_seg(bv_w, 0, k, 256)
  val () = $A.drop<byte>(fz_w, bv_w)
  val () = $A.free<byte>($A.thaw<byte>(fz_w))
  val () = prerr_newline()
in set_exit_code(126) end

(* Runs the command bv[command_at, ...) with the entries of the environment
   file; search_a[0, search_len) is the PATH the command runs with *)
fn run_command {l:agz}{ls:agz}{ca:nat | ca <= 4096}{ct:nat | ct <= 4096}
  (bv: !$A.borrow(byte, l, 4096), command_at: int ca, command_to: int ct, total: int,
   extras: $L.listv($P.arg_entry), known: bool, search_a: $A.arr(byte, ls, 524288), search_len: int): void = let
  val @(resolved, path_a) = resolve_command(bv, command_at, command_to, known, search_a, search_len)
  val () = (case+ resolved of
    | CommandFound() => let
        val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
        var first : $B.builder_v = $B.create()
        val () = put_range(bv, command_at, command_to, 4096, first)
        val rest = (if command_to + 1 > 4096 then $L.list_vt_nil()
          else arguments(bv, command_to + 1, total, $L.list_vt_nil())): $L.listv($P.arg_entry)
        val argv = $L.list_vt_cons(mk_arg(first), rev_arg_list(rest, $L.list_vt_nil()))
        val spawned = spawn_child_with(bv_p, argv, extras, $P.inherit(), $P.inherit(), $P.inherit())
        val () = (case+ spawned of
          | ~$R.ok(sp) => let
              val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
              val () = $P.pipe_end_close(sin_p)
              val () = $P.pipe_end_close(sout_p)
              val () = $P.pipe_end_close(serr_p)
              val ec = (case+ $P.child_wait(child) of
                | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
            in set_exit_code(if ec >= 0 then ec else 1) end
          | ~$R.err(code) =>
              if code = 2 then
                error_about(bv, command_at, command_to, "bats with-env: ", ": command not found", 127)
              else cannot_run(bv, command_at, command_to, code)): void
        val () = $A.drop<byte>(fz_p, bv_p)
      in $A.free<byte>($A.thaw<byte>(fz_p)) end
    | CommandNotFound() => let
        val () = arguments_free(extras)
        val () = $A.free<byte>(path_a)
      in error_about(bv, command_at, command_to, "bats with-env: ", ": command not found", 127) end
    | CommandNotAllowed() => let
        val () = arguments_free(extras)
        val () = $A.free<byte>(path_a)
      in cannot_run(bv, command_at, command_to, 13) end
    | PathTooLong() => let
        val () = arguments_free(extras)
        val () = $A.free<byte>(path_a)
      in error_about(bv, 0, 0, "bats with-env: PATH is over 64 KiB, so a command cannot be looked for in it", "", 2) end): void
in () end

(* The file at the NUL-terminated name bv[at, to) read into a buffer of
   65537 bytes: its size, or ~1 when it cannot be read or is too large *)
fn read_env_file {l:agz}{lf:agz}
  (bv: !$A.borrow(byte, l, 4096), at: int, to: int,
   content: !$A.arr(byte, lf, 65537)): int = let
  var path : $B.builder_v = $B.create()
  val () = put_range(bv, at, to, 4096, path)
  val () = put_char_v(path, 0)
  val @(path_a, path_len) = $B.to_arr(path)
  val @(fz_p, bv_p) = $A.freeze<byte>(path_a)
  val size = (case+ $F.file_open(bv_p, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
    | ~$R.ok(fd) => let
        val k = (case+ $F.file_read(fd, content, 65537) of
          | ~$R.ok(k) => k | ~$R.err(_) => ~1): int
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in if k >= 65537 then ~1 else k end
    | ~$R.err(_) => ~1): int
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in size end

(* The number of the line of bv[0, size) that holds the first NUL byte, or 0 *)
fn nul_line {l:agz}{n:pos} (bv: !$A.borrow(byte, l, n), size: int, n: int n): int = let
  fun count {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
    (bv: !$A.borrow(byte, l, n), p: int p, upto: int, n: int n, seen: int): int =
    if p >= n then seen
    else if p >= upto then seen
    else count(bv, p + 1, upto, n, (if peek(bv, p, n) = 10 then seen + 1 else seen))
  val z = find_byte(bv, 0, n, size, 0)
in
  if z >= size then 0 else 1 + count(bv, 0, z, n, 0)
end

(* The name of entry bad of the table, appended to out; nothing for ~1 *)
fn bad_name_put {l:agz}{lt:agz}
  (bv: !$A.borrow(byte, l, 65537), tab: !$A.arr(int, lt, 6144), bad: int,
   out: !$B.builder_v >> $B.builder_v): void =
  if bad < 0 then ()
  else put_range(bv, table_get(tab, 5 * bad), table_get(tab, 5 * bad + 1), 65537, out)

(* Says that the value of the variable name, set in the file at
   bv[file_at, file_to), cannot be made *)
fn expansion_failed {l:agz}{ln:agz}
  (bv: !$A.borrow(byte, l, 4096), file_at: int, file_to: int,
   name_a: $A.arr(byte, ln, 524288), name_len: int): void = let
  val @(fz_n, bv_n) = $A.freeze<byte>(name_a)
  val () = prerr! ("error: bats with-env: the value of ")
  val () = prerr_seg(bv_n, 0, name_len, 524288)
  val () = prerr! (" in ")
  val () = prerr_seg(bv, g1ofg0(file_at), file_to, 4096)
  val () = prerr! (" cannot be made: it names a variable whose name is over 255 bytes or whose value is over 64 KiB, or it is over 131071 bytes itself, or the variables of the file together are over 1 MiB")
  val () = prerr_newline()
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
in set_exit_code(2) end

(* with-env's work, the command line being bv[0, total) *)
fn with_env_run {l:agz}
  (bv: !$A.borrow(byte, l, 4096), total: int): void = let
  val arg1_at = find_byte(bv, 0, 4096, 4096, 0) + 1
in
  if arg1_at > 4096 then usage_error()
  else let
    val file_at = find_byte(bv, arg1_at, 4096, 4096, 0) + 1
  in
    if file_at >= total then usage_error()
    else if file_at > 4096 then usage_error()
    else let
      val file_to = find_byte(bv, file_at, 4096, 4096, 0)
      val command_at = file_to + 1
    in
      if command_at >= total then usage_error()
      else if command_at > 4096 then usage_error()
      else let
        val command_to = find_byte(bv, command_at, 4096, 4096, 0)
        val content = $A.alloc<byte>(65537)
        val size = read_env_file(bv, file_at, file_to, content)
      in
        if size < 0 then let
          val () = $A.free<byte>(content)
        in error_about(bv, file_at, file_to, "bats with-env: cannot read the environment file ",
             " (it must be readable and at most 64 KiB)", 2) end
        else let
          val @(fz_c, bv_c) = $A.freeze<byte>(content)
          val tab = $A.alloc<int>(6144): [lt:agz] $A.arr(int, lt, 6144)
          val nul_at = nul_line(bv_c, size, 65537)
          val count = table_fill(bv_c, 0, (if nul_at > 0 then 0 else size), 65537, tab, 0)
          var path_text : $B.builder_v = $B.create()
          val @(bad, has_path, extras) = entries_made(bv_c, 65537, tab, count, false, path_text)
          val known = (if has_path then true else put_environment_path(path_text)): bool
          val () = (if builder_size(path_text) = 0 then bput_v(path_text, "/usr/bin:/bin") else ())
          val @(search_a, search_len) = $B.to_arr(path_text)
          var bad_name : $B.builder_v = $B.create()
          val () = bad_name_put(bv_c, tab, bad, bad_name)
          val @(bad_a, bad_len) = $B.to_arr(bad_name)
          val () = $A.drop<byte>(fz_c, bv_c)
          val () = $A.free<byte>($A.thaw<byte>(fz_c))
          val () = $A.free<int>(tab)
          val () = (if nul_at > 0 then let
              val () = arguments_free(extras)
              val () = $A.free<byte>(search_a)
              val () = $A.free<byte>(bad_a)
              val () = prerr! ("error: bats with-env: the environment file ")
              val () = prerr_seg(bv, g1ofg0(file_at), file_to, 4096)
              val () = prerr! (" has a NUL byte on line ", nul_at, "; it must be text")
              val () = prerr_newline()
            in set_exit_code(2) end
            else if bad = ~2 then let
              val () = arguments_free(extras)
              val () = $A.free<byte>(search_a)
              val () = $A.free<byte>(bad_a)
            in error_about(bv, file_at, file_to, "bats with-env: the environment file ",
                 " sets more than 1024 variables", 2) end
            else if bad >= 0 then let
              val () = arguments_free(extras)
              val () = $A.free<byte>(search_a)
            in expansion_failed(bv, file_at, file_to, bad_a, bad_len) end
            else let
              val () = $A.free<byte>(bad_a)
            in run_command(bv, command_at, command_to, total, extras, known, search_a, search_len) end): void
        in () end
      end
    end
  end
end

(* Whether argv[1] is with-env *)
fn names_with_env {l:agz} (bv: !$A.borrow(byte, l, 4096), total: int): bool = let
  val a = find_byte(bv, 0, 4096, 4096, 0) + 1
in
  a + 8 < total
  && peek(bv, a, 4096) = 119 && peek(bv, a + 1, 4096) = 105
  && peek(bv, a + 2, 4096) = 116 && peek(bv, a + 3, 4096) = 104
  && peek(bv, a + 4, 4096) = 45 && peek(bv, a + 5, 4096) = 101
  && peek(bv, a + 6, 4096) = 110 && peek(bv, a + 7, 4096) = 118
  && peek(bv, a + 8, 4096) = 0
end

(* Runs bats with-env when that is the command given and answers true;
   false for any other command, which is left to the caller *)


implement with_env_main () = let
  val buf = $A.alloc<byte>(4096)
  val read = $E.args_read(buf, 4096)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val handled = (case+ read of
    | ~$R.none() => false
    | ~$R.some(total) =>
        if names_with_env(bv, total) then let
          val () = (if total >= 4096 then
              error_about(bv, 0, 0, "bats with-env: the command line is longer than 4095 bytes", "", 2)
            else with_env_run(bv, total))
        in true end
        else false): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in handled end
