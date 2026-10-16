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
       text in single quotes (taken literally) or double quotes;
     * in an unquoted or double-quoted value $NAME and ${NAME} stand for the
       variable of that name in this process's environment (the empty text
       when it is unset), so PATH=/opt/bin:$PATH works; nothing else is
       interpreted: no command substitution, no escapes, no ~;
     * a variable set on more than one line has its last value;
     * the file is at most 64 KiB, the command line at most 4095 bytes.

   A usage error (no file, no command, an unreadable or too large file, a
   command line too long to be read whole) is status 2; a command that is
   found nowhere is 127 and one that cannot be run 126. *)

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

(* The value of the variable named bv[a, b) in this process's environment
   appended to out; nothing when it is unset *)
fn put_variable {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), a: int, b: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): void = let
  val name = $A.alloc<byte>(256)
  val len = copy_name(bv, a, b, n, name, 0)
  val () = poke_arr(name, g1ofg0(len), 256, 0)
  val value = $A.alloc<byte>(65536)
  val got = $E.get_cstr(name, 256, value, 65536)
  val k = (case+ got of | ~$R.some(n) => n | ~$R.none() => 0): int
  val @(fz_v, bv_v) = $A.freeze<byte>(value)
  val () = copy_to_builder_v(bv_v, 0, k, 65536, out)
  val () = $A.drop<byte>(fz_v, bv_v)
  val () = $A.free<byte>($A.thaw<byte>(fz_v))
in $A.free<byte>(name) end

(* bv[p, b) appended to out with its $NAME and ${NAME} replaced by the
   environment's *)
fun put_expanded {l:agz}{n:pos}{p:nat | p <= n} .<n - p>.
  (bv: !$A.borrow(byte, l, n), p: int p, b: int, n: int n,
   out: !$B.builder_v >> $B.builder_v): void =
  if p >= n then ()
  else if p >= b then ()
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
            val () = put_variable(bv, p + 2, close, n, out)
          in
            if close + 1 > n then ()
            else put_expanded(bv, close + 1, b, n, out)
          end
          else let
            val () = put_char_v(out, c)
          in put_expanded(bv, p + 1, b, n, out) end
        end)
      else if is_name_start(c1) then let
        val ne = name_end(bv, p + 1, n, b)
        val () = put_variable(bv, p + 1, ne, n, out)
      in put_expanded(bv, ne, b, n, out) end
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
   single quotes literally, double quotes and none expanded *)
fn put_value {l:agz}{n:pos}{e:nat | e <= n}
  (bv: !$A.borrow(byte, l, n), value_at: int, e: int e, n: int n,
   out: !$B.builder_v >> $B.builder_v): void =
  let
    val v = g1ofg0(value_at)
  in
  if v < 0 then ()
  else if v > n then ()
  else let
    val a = skip_blank(bv, v, n, e)
    val t = trim_end(bv, a, e, n)
  in
    if t - a >= 2 then (
      if peek(bv, a, n) = 39 && peek(bv, t - 1, n) = 39 then
        put_span(bv, a + 1, t - 1, n, out)
      else if peek(bv, a, n) = 34 && peek(bv, t - 1, n) = 34 then
        put_expanded(bv, a + 1, t - 1, n, out)
      else put_expanded(bv, a, t, n, out))
    else put_expanded(bv, a, t, n, out)
  end
  end

(* Whether a line of bv[s, size) from s on sets the variable bv[a, b) *)
fun set_later {l:agz}{n:pos}{s:nat | s <= n} .<n - s>.
  (bv: !$A.borrow(byte, l, n), s: int s, size: int, n: int n, a: int, b: int): bool =
  if s >= size then false
  else let
    val e = find_byte(bv, s, n, size, 10)
    val x = line_assignment(bv, s, e, n)
  in
    if x.found && same_span(bv, x.name_at, x.name_to, a, b, 0, n) then true
    else if e + 1 > n then false
    else set_later(bv, e + 1, size, n, a, b)
  end

(* The NAME=VALUE entries of the lines of bv[s, size) that no later line
   overrides, consed onto acc (the last line's first) *)
fun file_entries {l:agz}{n:pos}{s:nat | s <= n} .<n - s>.
  (bv: !$A.borrow(byte, l, n), s: int s, size: int, n: int n,
   acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if s >= size then acc
  else let
    val e = find_byte(bv, s, n, size, 10)
    val x = line_assignment(bv, s, e, n)
    val overridden = (if e + 1 > n then false
      else set_later(bv, e + 1, size, n, x.name_at, x.name_to)): bool
    val keep = (if overridden then false else x.found): bool
    val acc2 = (if keep then let
        var entry : $B.builder_v = $B.create()
        val () = put_range(bv, x.name_at, x.name_to, n, entry)
        val () = put_char_v(entry, 61)
        val () = put_value(bv, x.value_at, e, n, entry)
      in $L.list_vt_cons(mk_arg(entry), acc) end
      else acc): $L.listv($P.arg_entry)
  in
    if e + 1 > n then acc2
    else file_entries(bv, e + 1, size, n, acc2)
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

(* Runs the command bv[command_at, ...) with the entries of the environment file *)
fn run_command {l:agz}{ca:nat | ca <= 4096}{ct:nat | ct <= 4096}
  (bv: !$A.borrow(byte, l, 4096), command_at: int ca, command_to: int ct, total: int,
   extras: $L.listv($P.arg_entry)): void = let
  var path : $B.builder_v = $B.create()
  val () = put_range(bv, command_at, command_to, 4096, path)
  val () = put_char_v(path, 0)
  val @(path_a, path_len) = $B.to_arr(path)
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
        else
          error_about(bv, command_at, command_to, "bats with-env: cannot run ", "", 126)): void
  val () = $A.drop<byte>(fz_p, bv_p)
in $A.free<byte>($A.thaw<byte>(fz_p)) end

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
          val extras = file_entries(bv_c, 0, size, 65537, $L.list_vt_nil())
          val () = $A.drop<byte>(fz_c, bv_c)
          val () = $A.free<byte>($A.thaw<byte>(fz_c))
        in run_command(bv, command_at, command_to, total, rev_arg_list(extras, $L.list_vt_nil())) end
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
