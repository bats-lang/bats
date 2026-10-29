staload "./bats.sats"
staload "argparse/src/lib.dats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "env/src/lib.dats"
staload "file/src/lib.dats"
staload "str/src/lib.dats"
staload "process/src/lib.dats"
staload "result/src/lib.dats"
(* bats -- bats compiler entry point *)

#include "share/atspre_staload.hats"

staload AP = "argparse/src/lib.sats"
staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload E = "env/src/lib.sats"
staload F = "file/src/lib.sats"
staload S = "str/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"

staload "helpers.sats"
staload "lexer.sats"
staload "build.sats"
staload "commands.sats"
staload "lock.sats"
staload "ats2.sats"
staload "setup.sats"
staload "with_env.sats"
staload "fixtures.sats"
staload "pins.sats"
staload "affected.sats"
staload "merge_proof.sats"
staload "_bats_inputs.sats"

(* The subcommands *)
datatype command =
  | Build | Check | Clean | Lock | Run | Init | Test | Tree
  | Upload | Add | Remove | Completions | Ats2 | CloneRepository | RecordCommit | Version | UnknownCommand

(* The command the command buffer names, told apart as the Rust bats did:
   by its length and first bytes *)
fn dispatch_cmd {l:agz}
  (buf: !$A.arr(byte, l, 32), len: int): command = let
  val b0 = byte2int0($A.get<byte>(buf, 0))
  val b1 = byte2int0($A.get<byte>(buf, 1))
in
  if len = 5 then
    (if $AR.eq_int_int(b0, 98) then Build()
    else if $AR.eq_int_int(b0, 99) then
      (if $AR.eq_int_int(b1, 104) then Check() else Clean())
    else UnknownCommand()): command
  else if len = 4 then
    (if $AR.eq_int_int(b0, 108) then Lock()
    else if $AR.eq_int_int(b0, 105) then Init()
    else if peek_arr(buf, 0, 32) = 97 && peek_arr(buf, 1, 32) = 116 && peek_arr(buf, 2, 32) = 115 && peek_arr(buf, 3, 32) = 50 && peek_arr(buf, 4, 32) = 0 then Ats2()
    else if $AR.eq_int_int(b0, 116) then
      (if $AR.eq_int_int(b1, 101) then Test() else Tree())
    else UnknownCommand()): command
  else if len = 3 then
    (if $AR.eq_int_int(b0, 114) then Run()
    else if $AR.eq_int_int(b0, 97) then Add()
    else UnknownCommand()): command
  else if len = 6 then
    (if $AR.eq_int_int(b0, 117) then Upload()
    else if $AR.eq_int_int(b0, 114) then Remove()
    else UnknownCommand()): command
  else if len = 11 then Completions()
  else if len = 16 then (if peek_arr(buf, 0, 32) = 99 && peek_arr(buf, 1, 32) = 108 && peek_arr(buf, 2, 32) = 111 && peek_arr(buf, 3, 32) = 110 && peek_arr(buf, 4, 32) = 101 && peek_arr(buf, 5, 32) = 45 && peek_arr(buf, 6, 32) = 114 && peek_arr(buf, 7, 32) = 101 && peek_arr(buf, 8, 32) = 112 && peek_arr(buf, 9, 32) = 111 && peek_arr(buf, 10, 32) = 115 && peek_arr(buf, 11, 32) = 105 && peek_arr(buf, 12, 32) = 116 && peek_arr(buf, 13, 32) = 111 && peek_arr(buf, 14, 32) = 114 && peek_arr(buf, 15, 32) = 121 && peek_arr(buf, 16, 32) = 0 then CloneRepository() else UnknownCommand())
  else if len = 13 then (if peek_arr(buf, 0, 32) = 114 && peek_arr(buf, 1, 32) = 101 && peek_arr(buf, 2, 32) = 99 && peek_arr(buf, 3, 32) = 111 && peek_arr(buf, 4, 32) = 114 && peek_arr(buf, 5, 32) = 100 && peek_arr(buf, 6, 32) = 45 && peek_arr(buf, 7, 32) = 99 && peek_arr(buf, 8, 32) = 111 && peek_arr(buf, 9, 32) = 109 && peek_arr(buf, 10, 32) = 109 && peek_arr(buf, 11, 32) = 105 && peek_arr(buf, 12, 32) = 116 && peek_arr(buf, 13, 32) = 0 then RecordCommit() else UnknownCommand())
  else if len = 7 then Version()
  else UnknownCommand()
end

(* Whether the command writes build/, dist/ or bats_modules/, and so
   holds the project's lock (run takes it itself) *)
fn locks_project (c: command): bool =
  case+ c of
  | Build() => true | Check() => true | Clean() => true | Lock() => true
  | Test() => true | Tree() => true | Upload() => true | Add() => true
  | Remove() => true
  | Run() => false | Init() => false | Completions() => false | Ats2() => false | CloneRepository() => false | RecordCommit() => false
  | Version() => false | UnknownCommand() => false

(* The commands that hold a machine slot while they work, with BATS_SLOTS
   set (bats-lang/bats#252): those that run patsopt and cc (run takes its
   own, for its build) *)
fn heavy_of (c: command): heavy_command =
  case+ c of
  | Check() => HeavyCheck() | Build() => HeavyBuild() | Test() => HeavyTest()
  | Run() => NotHeavy() | Clean() => NotHeavy() | Lock() => NotHeavy()
  | Tree() => NotHeavy() | Upload() => NotHeavy() | Add() => NotHeavy()
  | Remove() => NotHeavy() | Init() => NotHeavy() | Completions() => NotHeavy()
  | Ats2() => NotHeavy() | CloneRepository() => NotHeavy() | RecordCommit() => NotHeavy()
  | Version() => NotHeavy() | UnknownCommand() => NotHeavy()

(* Print usage matching Rust bats format *)
fn print_usage(): void = let
  val () = println! ("usage: bats [--run-in <dir>] [--quiet] <command>")
  val () = println! ("")
  val () = println! ("commands:")
  val () = println! ("  init binary [--claude]       Create a new binary project (src/bin/<name>.bats)")
  val () = println! ("  init library [--claude]      Create a new library project (src/lib.bats)")
  val () = println! ("  add <package> --repository <dir>")
  val () = println! ("                               Add a dependency")
  val () = println! ("  remove <package> --repository <dir>")
  val () = println! ("                               Remove a dependency")
  val () = println! ("  lock [--dev] [--dry-run] --repository <dir>")
  val () = println! ("                               Generate bats.lock")
  val () = println! ("  build [--only debug|release|native|wasm] [-j|--jobs <n>|cores] [--repository <dir>]")
  val () = println! ("                               Build the project")
  val () = println! ("  run [--only debug|release] [--bin <name>] [--repository <dir>] [-- args...]")
  val () = println! ("                               Build and run a binary")
  val () = println! ("  test [--only native|wasm] [--filter <name>] [--repository <dir>]")
  val () = println! ("                               Run tests")
  val () = println! ("  check [--cold] [-j|--jobs <n>|cores] [--repository <dir>]")
  val () = println! ("                               Type-check the project (no linking); --cold (or BATS_COLD) checks every module again")
  val () = println! ("  tree [--repository <dir>]    Show dependency tree")
  val () = println! ("  upload --repository <dir>    Package and upload a library")
  val () = println! ("  clean                        Remove generated artifacts")
  val () = println! ("  ats2 install [--force]       Install the pinned ATS2 (patsopt) into ~/.bats/ats2; --force replaces what is there")
  val () = println! ("  ats2 marker                  Print the marker text of the pinned ATS2 (the pin's name and SHA-256)")
  val () = println! ("  clone-repository <commit> --repository <dir>")
  val () = println! ("                               Clone the package repository at a full commit; prints BATS_REPOSITORY=<dir>")
  val () = println! ("  record-commit <commit>       Check the commit is in this repository; prints BATS_COMMIT=<commit>")
  val () = println! ("  check-pins <file>...         Fail the CI inputs that move: uses:, -latest images, versions, npm, curl (a moving input turns a passing commit red later; keyword: inputs of CI that move)")
  val () = println! ("  affected <base> <head>       Print inert=true when only markdown files outside tests/ and bootstrap/ changed between two revisions (keyword: affected rule)")
  val () = println! ("  merge-proof <reviewed-sha> <head> [--repository <dir>]")
  val () = println! ("                               Print OK when the head is the reviewed head plus a merge of main (keyword: merge-proof)")
  val () = println! ("  completions <shell>          Generate shell completions (bash, zsh, fish)")
  val () = println! ("  fixtures <dir> [--only <member>]... [--bless] [--cold] [--work <dir>] [--memo <dir>] [--prune] [--repository <dir>] [--list-affected <path>...]")
  val () = println! ("                               Run the accept and reject fixtures of <dir> against a copy of the project;")
  val () = println! ("                               --bless writes each reject's expect from its observed error (read it in the PR diff)")
  val () = println! ("  with-env <env-file> <command> [args...]")
  val () = println! ("                               Run a command with the variables of a dotenv file")
in end

(* Copies src[s + i, e) to dst[i..], for bats run's arguments after
   "--"; returns the byte count. *)
fun copy_extra {l1,l2:agz}{i:nat | i <= 4096} .<4096 - i>.
  (src: !$A.arr(byte, l1, 4096), dst: !$A.arr(byte, l2, 4096),
   s: pos_t, e: int, i: int i): int =
  if i >= 4096 then i
  else if s + i >= e then i
  else let
    val () = $A.set<byte>(dst, i, int2byte0(peek_arr(src, s + i, 4096)))
  in copy_extra(src, dst, s, e, i + 1) end

(* Find the position of "--" separator in the argument buffer. *)
fun find_dashdash {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int): pos_t =
  if pos >= len then ~1
  else if pos >= 4096 then ~1
  else if peek_arr(buf, pos, 4096) = 45 && peek_arr(buf, pos + 1, 4096) = 45
          && peek_arr(buf, pos + 2, 4096) = 0 then pos
  else let
    val next = $S.find_null_at(buf, pos, 4096)
  in
    if next >= 4096 then ~1
    else find_dashdash(buf, next + 1, len)
  end

(* The values the repeated --only options named *)
typedef only_named = @{debug= bool, release= bool, native= bool, wasm= bool}

(* The profiles a build makes: one when --only names it alone, both when
   it names both or neither *)
datatype profiles = DebugOnly | ReleaseOnly | BothProfiles

(* The targets a build makes, likewise *)
datatype targets = NativeOnly | WasmOnly | BothTargets

fn profiles_of (named: only_named): profiles =
  if named.debug && ~named.release then DebugOnly()
  else if named.release && ~named.debug then ReleaseOnly()
  else BothProfiles()

fn targets_of (named: only_named): targets =
  if named.native && ~named.wasm then NativeOnly()
  else if named.wasm && ~named.native then WasmOnly()
  else BothTargets()

fn makes_debug (p: profiles): bool = case+ p of ReleaseOnly() => false | _ => true
fn makes_release (p: profiles): bool = case+ p of DebugOnly() => false | _ => true
fn makes_native (t: targets): bool = case+ t of WasmOnly() => false | _ => true
fn makes_wasm (t: targets): bool = case+ t of NativeOnly() => false | _ => true

(* The value of --only at v0 (its first byte) added to named *)
fn only_add (named: only_named, v0: int): only_named =
  if $AR.eq_int_int(v0, 100) then @{debug= true, release= named.release, native= named.native, wasm= named.wasm}
  else if $AR.eq_int_int(v0, 114) then @{debug= named.debug, release= true, native= named.native, wasm= named.wasm}
  else if $AR.eq_int_int(v0, 110) then @{debug= named.debug, release= named.release, native= true, wasm= named.wasm}
  else if $AR.eq_int_int(v0, 119) then @{debug= named.debug, release= named.release, native= named.native, wasm= true}
  else named

(* Scan --only values: read all repeated --only tokens from cmdline. *)
fun scan_only {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int, named: only_named): only_named =
  if pos >= len then named
  else if pos >= 4096 then named
  (* "--only" : 45,45,111,110,108,121 *)
  else if peek_arr(buf, pos, 4096) = 45 && peek_arr(buf, pos + 1, 4096) = 45
          && peek_arr(buf, pos + 2, 4096) = 111 && peek_arr(buf, pos + 3, 4096) = 110
          && peek_arr(buf, pos + 4, 4096) = 108 && peek_arr(buf, pos + 5, 4096) = 121 then let
    val next = $S.find_null_at(buf, min(pos + 6, 4096), 4096)
    val val_start = next + 1
  in
    if val_start >= len then named
    else if val_start >= 4096 then named
    else let
      val v0 = peek_arr(buf, val_start, 4096)
      val vend = $S.find_null_at(buf, val_start, 4096)
      val new_named = only_add(named, v0)
    in
      if vend >= 4096 then new_named
      else scan_only(buf, vend + 1, len, new_named)
    end
  end
  else let
    val next = $S.find_null_at(buf, pos, 4096)
  in
    if next >= 4096 then named
    else scan_only(buf, next + 1, len, named)
  end

(* The words of the command line that are neither options nor an option's
   value: the command and its arguments. An option that takes a value is one
   of --repository, --run-in, --only, --bin, --to-c, --filter and --jobs (-j). *)
fun count_positionals {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int, count: int): int =
  if pos >= len then count
  else if pos >= 4096 then count
  else let
    val next = $S.find_null_at(buf, pos, 4096)
    val dash = peek_arr(buf, pos, 4096) = 45
    val c1 = peek_arr(buf, min(pos + 1, 4095), 4096)
    val c2 = peek_arr(buf, min(pos + 2, 4095), 4096)
    val c3 = peek_arr(buf, min(pos + 3, 4095), 4096)
    val valued = dash && ((c1 = 45
      && ((c2 = 114 && (c3 = 101 || c3 = 117)) || c2 = 111 || c2 = 98 || c2 = 116 || (c2 = 102 && c3 = 105)
          || (c2 = 106 && c3 = 111))) || (c1 = 106 && c2 = 0))
  in
    if next >= 4096 then (if dash then count else count + 1)
    else if valued then let
      val vstart = next + 1
    in
      if vstart >= len then count
      else if vstart >= 4096 then count
      else let
        val vend = $S.find_null_at(buf, vstart, 4096)
      in
        if vend >= 4096 then count
        else count_positionals(buf, vend + 1, len, count)
      end
    end
    else count_positionals(buf, next + 1, len, (if dash then count else count + 1))
  end

(* Where the command word starts: the first word that is neither an option
   nor an option's value (the options are those count_positionals knows);
   ~1 when there is none *)
fun first_positional {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int): [r:int] int r =
  if pos >= len then ~1
  else if pos >= 4096 then ~1
  else let
    val next = $S.find_null_at(buf, pos, 4096)
    val dash = peek_arr(buf, pos, 4096) = 45
    val c1 = peek_arr(buf, min(pos + 1, 4095), 4096)
    val c2 = peek_arr(buf, min(pos + 2, 4095), 4096)
    val c3 = peek_arr(buf, min(pos + 3, 4095), 4096)
    val valued = dash && ((c1 = 45
      && ((c2 = 114 && (c3 = 101 || c3 = 117)) || c2 = 111 || c2 = 98 || c2 = 116 || (c2 = 102 && c3 = 105)
          || (c2 = 106 && c3 = 111))) || (c1 = 106 && c2 = 0))
  in
    if ~dash then pos
    else if next >= 4096 then ~1
    else if valued then let
      val vstart = next + 1
    in
      if vstart >= len then ~1
      else if vstart >= 4096 then ~1
      else let
        val vend = $S.find_null_at(buf, vstart, 4096)
      in
        if vend >= 4096 then ~1
        else first_positional(buf, vend + 1, len)
      end
    end
    else first_positional(buf, next + 1, len)
  end

(* Where the command word starts: the second word of the command line (the
   first is the program), skipping options *)
fn command_word {l:agz} (buf: !$A.arr(byte, l, 4096), len: int): [r:int] int r = let
  val program = first_positional(buf, 0, len)
in
  if program < 0 then ~1
  else if program >= 4096 then ~1
  else let
    val nx = $S.find_null_at(buf, program, 4096)
  in
    if nx >= 4096 then ~1 else first_positional(buf, nx + 1, len)
  end
end

(* How many arguments are exactly --force (ats2 install --force takes one; any other use is a usage error) *)
fun count_force {l:agz}{p:nat | p <= 4096} .<4096 - p>.
  (buf: !$A.arr(byte, l, 4096), pos: int p, len: int, count: int): int =
  if pos >= len then count
  else if pos >= 4096 then count
  else let
    val next = $S.find_null_at(buf, pos, 4096)
    val is_force = next = pos + 7 && peek_arr(buf, pos, 4096) = 45 && peek_arr(buf, pos + 1, 4096) = 45
      && peek_arr(buf, pos + 2, 4096) = 102 && peek_arr(buf, pos + 3, 4096) = 111
      && peek_arr(buf, pos + 4, 4096) = 114 && peek_arr(buf, pos + 5, 4096) = 99
      && peek_arr(buf, pos + 6, 4096) = 101
  in
    if next >= 4096 then count
    else count_force(buf, next + 1, len, (if is_force then count + 1 else count))
  end

(* Whether the command word at p0 is one of the commands setup runs
   (ats2, clone-repository, record-commit), whose misuse is an error *)
fn is_setup_word {l:agz}{q:int} (buf: !$A.arr(byte, l, 4096), p0: int q): bool =
  if p0 < 0 then false
  else if p0 > 4000 then false
  else ((peek_arr(buf, p0 + 0, 4096) = 97 && peek_arr(buf, p0 + 1, 4096) = 116 && peek_arr(buf, p0 + 2, 4096) = 115 && peek_arr(buf, p0 + 3, 4096) = 50 && peek_arr(buf, p0 + 4, 4096) = 0) || (peek_arr(buf, p0 + 0, 4096) = 99 && peek_arr(buf, p0 + 1, 4096) = 108 && peek_arr(buf, p0 + 2, 4096) = 111 && peek_arr(buf, p0 + 3, 4096) = 110 && peek_arr(buf, p0 + 4, 4096) = 101 && peek_arr(buf, p0 + 5, 4096) = 45 && peek_arr(buf, p0 + 6, 4096) = 114 && peek_arr(buf, p0 + 7, 4096) = 101 && peek_arr(buf, p0 + 8, 4096) = 112 && peek_arr(buf, p0 + 9, 4096) = 111 && peek_arr(buf, p0 + 10, 4096) = 115 && peek_arr(buf, p0 + 11, 4096) = 105 && peek_arr(buf, p0 + 12, 4096) = 116 && peek_arr(buf, p0 + 13, 4096) = 111 && peek_arr(buf, p0 + 14, 4096) = 114 && peek_arr(buf, p0 + 15, 4096) = 121 && peek_arr(buf, p0 + 16, 4096) = 0) || (peek_arr(buf, p0 + 0, 4096) = 114 && peek_arr(buf, p0 + 1, 4096) = 101 && peek_arr(buf, p0 + 2, 4096) = 99 && peek_arr(buf, p0 + 3, 4096) = 111 && peek_arr(buf, p0 + 4, 4096) = 114 && peek_arr(buf, p0 + 5, 4096) = 100 && peek_arr(buf, p0 + 6, 4096) = 45 && peek_arr(buf, p0 + 7, 4096) = 99 && peek_arr(buf, p0 + 8, 4096) = 111 && peek_arr(buf, p0 + 9, 4096) = 109 && peek_arr(buf, p0 + 10, 4096) = 109 && peek_arr(buf, p0 + 11, 4096) = 105 && peek_arr(buf, p0 + 12, 4096) = 116 && peek_arr(buf, p0 + 13, 4096) = 0))

(* The value of a string option copied to buf, and its length; 0 when
   the option was not given. *)
fn opt_string_copy {l:agz}{n:pos}
  (r: !$AP.parse_result, h: $AP.arg($AP.string_val), buf: !$A.arr(byte, l, n), n: int n): int =
  if $AP.is_present(r, h) then $AP.get_string_copy(r, h, buf, n) else 0

(* BATS_REPOSITORY copied to buf, and its length: 0 when it is not set
   (or is longer than buf holds) *)
fn repository_from_env {l:agz} (buf: !$A.arr(byte, l, 4096)): int = let
  var name_c = @[char][15]('B', 'A', 'T', 'S', '_', 'R', 'E', 'P', 'O', 'S', 'I', 'T', 'O', 'R', 'Y')
  val name = $S.from_char_array(name_c, 15)
  val @(fz_n, bv_n) = $A.freeze<byte>(name)
  val got = $E.get(bv_n, 15, buf, 4096)
  val () = $A.drop<byte>(fz_n, bv_n)
  val () = $A.free<byte>($A.thaw<byte>(fz_n))
in case+ got of | ~$R.some(n) => (if n < 4096 then n else 0) | ~$R.none() => 0 end

(* The repository's length in buf: --repository's (flag_len), else
   BATS_REPOSITORY's *)
fn repository_len {l:agz} (buf: !$A.arr(byte, l, 4096), flag_len: int): int =
  if flag_len > 0 then flag_len else repository_from_env(buf)

(* ============================================================
   Main: read argv (args_read: NUL-separated), dispatch
   ============================================================ *)

(* Whether the project is a binary package, which build and run need;
   false after printing the error (Rust: cmd_build's config::load, then
   build::build's kind check) *)
fn bin_package (): bool =
  case+ project_kind() of
  | ~$R.none() => false
  | ~$R.some(Binary()) => true
  | ~$R.some(Library()) => let
      val () = prerr! ("error: 'bats build' is only for binary packages (kind = \"bin\")\n")
      val () = set_build_err()
    in false end

(* Whether bats.toml reads as a package of a known kind; false after
   printing the error *)
fn project_known (): bool =
  case+ project_kind() of
  | ~$R.none() => false
  | ~$R.some(_) => true

(* --force outside ats2 install, or given twice, is a usage error *)
fn force_misuse (cmd: command, count: int, present: bool): bool =
  case+ cmd of
  | Ats2() => count > 1
  | _ => present || count > 0

fn bats_main (): void = let
  val cl_buf = $A.alloc<byte>(4096)
  val cl_read = $E.args_read(cl_buf, 4096)
in
      case+ cl_read of
      | ~$R.some(cl_n) => let
          val dd_pos = find_dashdash(cl_buf, 0, cl_n)
          (* The arguments after "--\0", NUL-terminated, for bats run *)
          val extra_buf = $A.alloc<byte>(4096)
          val extra_end = (if dd_pos >= 0 then cl_n else 0): int
          val extra_len = copy_extra(cl_buf, extra_buf, dd_pos + 3, extra_end, 0)
          val effective_len = (if dd_pos >= 0 then dd_pos else cl_n): int
          val argc = count_argc(cl_buf, effective_len)
          val positionals = count_positionals(cl_buf, 0, effective_len, 0)
          val force_count = count_force(cl_buf, 0, effective_len, 0)
          val setup_word = is_setup_word(cl_buf, command_word(cl_buf, effective_len))
          val named_only = scan_only(cl_buf, 0, effective_len,
            @{debug= false, release= false, native= false, wasm= false})
          val @(fz_cb, bv_cb) = $A.freeze<byte>(cl_buf)
          var pna_c = @[char][4]('b', 'a', 't', 's')
          val pna = $S.from_char_array(pna_c, 4)
          val pnl = 4
          val @(fzpn, bvpn) = $A.freeze<byte>(pna)
          var pha_c = @[char][15]('b', 'a', 't', 's', ' ', 'b', 'u', 'i', 'l', 'd', ' ', 't', 'o', 'o', 'l')
          val pha = $S.from_char_array(pha_c, 15)
          val phl = 15
          val @(fzph, bvph) = $A.freeze<byte>(pha)
          val p = $AP.parser_new(bvpn, pnl, bvph, phl)
          val () = $A.drop<byte>(fzpn, bvpn)
          val () = $A.free<byte>($A.thaw<byte>(fzpn))
          val () = $A.drop<byte>(fzph, bvph)
          val () = $A.free<byte>($A.thaw<byte>(fzph))
          var apn0 = @[char][7]('v', 'e', 'r', 'b', 'o', 's', 'e')
          var aph0 = @[char][14]('v', 'e', 'r', 'b', 'o', 's', 'e', ' ', 'o', 'u', 't', 'p', 'u', 't')
          val @(p, h_verbose) = ap_flag(p, apn0, 7, $R.some(118), aph0, 14)
          var apn1 = @[char][5]('q', 'u', 'i', 'e', 't')
          var aph1 = @[char][12]('q', 'u', 'i', 'e', 't', ' ', 'o', 'u', 't', 'p', 'u', 't')
          val @(p, h_quiet) = ap_flag(p, apn1, 5, $R.some(113), aph1, 12)
          var apn2 = @[char][6]('r', 'u', 'n', '-', 'i', 'n')
          var aph2 = @[char][16]('r', 'u', 'n', ' ', 'i', 'n', ' ', 'd', 'i', 'r', 'e', 'c', 't', 'o', 'r', 'y')
          val @(p, h_run_in) = ap_string_opt(p, apn2, 6, $R.none(), aph2, 16)
          var apn3 = @[char][10]('r', 'e', 'p', 'o', 's', 'i', 't', 'o', 'r', 'y')
          var aph3 = @[char][18]('p', 'a', 'c', 'k', 'a', 'g', 'e', ' ', 'r', 'e', 'p', 'o', 's', 'i', 't', 'o', 'r', 'y')
          val @(p, h_repository) = ap_string_opt(p, apn3, 10, $R.none(), aph3, 18)
          var apn4 = @[char][4]('o', 'n', 'l', 'y')
          var aph4 = @[char][12]('b', 'u', 'i', 'l', 'd', ' ', 't', 'a', 'r', 'g', 'e', 't')
          val @(p, h_only) = ap_string_opt(p, apn4, 4, $R.none(), aph4, 12)
          var apn5 = @[char][3]('b', 'i', 'n')
          var aph5 = @[char][11]('b', 'i', 'n', 'a', 'r', 'y', ' ', 'n', 'a', 'm', 'e')
          val @(p, h_bin) = ap_string_opt(p, apn5, 3, $R.none(), aph5, 11)
          var apn6 = @[char][4]('t', 'o', '-', 'c')
          var aph6 = @[char][27]('o', 'u', 't', 'p', 'u', 't', ' ', 'C', ' ', 'f', 'i', 'l', 'e', 's', ' ', 't', 'o', ' ', 'd', 'i', 'r', 'e', 'c', 't', 'o', 'r', 'y')
          val @(p, h_to_c) = ap_string_opt(p, apn6, 4, $R.none(), aph6, 27)
          var apn7 = @[char][6]('c', 'l', 'a', 'u', 'd', 'e')
          var aph7 = @[char][19]('c', 'r', 'e', 'a', 't', 'e', ' ', 'c', 'l', 'a', 'u', 'd', 'e', ' ', 'r', 'u', 'l', 'e', 's')
          val @(p, h_claude) = ap_flag(p, apn7, 6, $R.none(), aph7, 19)
          var apn8 = @[char][3]('d', 'e', 'v')
          var aph8 = @[char][24]('i', 'n', 'c', 'l', 'u', 'd', 'e', ' ', 'd', 'e', 'v', ' ', 'd', 'e', 'p', 'e', 'n', 'd', 'e', 'n', 'c', 'i', 'e', 's')
          val @(p, h_dev) = ap_flag(p, apn8, 3, $R.none(), aph8, 24)
          var apn9 = @[char][7]('d', 'r', 'y', '-', 'r', 'u', 'n')
          var aph9 = @[char][12]('d', 'r', 'y', ' ', 'r', 'u', 'n', ' ', 'm', 'o', 'd', 'e')
          val @(p, h_dry_run) = ap_flag(p, apn9, 7, $R.none(), aph9, 12)
          var apn16 = @[char][4]('j', 'o', 'b', 's')
          var aph16 = @[char][17]('p', 'a', 'r', 'a', 'l', 'l', 'e', 'l', ' ', 'c', 'o', 'm', 'p', 'i', 'l', 'e', 's')
          val @(p, h_jobs) = ap_string_opt(p, apn16, 4, $R.some(106), aph16, 17)
          var apn15 = @[char][5]('f', 'o', 'r', 'c', 'e')
          var aph15 = @[char][12]('r', 'e', 'p', 'l', 'a', 'c', 'e', ' ', 'A', 'T', 'S', '2')
          val @(p, h_force) = ap_flag(p, apn15, 5, $R.none(), aph15, 12)
          var apn14 = @[char][4]('c', 'o', 'l', 'd')
          var aph14 = @[char][21]('i', 'g', 'n', 'o', 'r', 'e', ' ', 't', 'h', 'e', ' ', 'c', 'h', 'e', 'c', 'k', ' ', 'm', 'e', 'm', 'o')
          val @(p, h_cold) = ap_flag(p, apn14, 4, $R.none(), aph14, 21)
          var apn10 = @[char][4]('h', 'e', 'l', 'p')
          var aph10 = @[char][9]('s', 'h', 'o', 'w', ' ', 'h', 'e', 'l', 'p')
          val @(p, h_help) = ap_flag(p, apn10, 4, $R.some(104), aph10, 9)
          var apn11 = @[char][6]('f', 'i', 'l', 't', 'e', 'r')
          var aph11 = @[char][11]('t', 'e', 's', 't', ' ', 'f', 'i', 'l', 't', 'e', 'r')
          val @(p, h_filter) = ap_string_opt(p, apn11, 6, $R.none(), aph11, 11)
          var apn12 = @[char][7]('c', 'o', 'm', 'm', 'a', 'n', 'd')
          var aph12 = @[char][10]('s', 'u', 'b', 'c', 'o', 'm', 'm', 'a', 'n', 'd')
          val @(p, h_cmd) = ap_string_pos(p, apn12, 7, aph12, 10)
          var apn13 = @[char][8]('a', 'r', 'g', 'u', 'm', 'e', 'n', 't')
          var aph13 = @[char][19]('s', 'u', 'b', 'c', 'o', 'm', 'm', 'a', 'n', 'd', ' ', 'a', 'r', 'g', 'u', 'm', 'e', 'n', 't')
          val @(p, h_arg) = ap_string_pos(p, apn13, 8, aph13, 19)
          val result = $AP.parse(p, bv_cb, 4096, argc)
          val () = $A.drop<byte>(fz_cb, bv_cb)
          val () = $A.free<byte>($A.thaw<byte>(fz_cb))
        in
          case+ result of
          | ~$R.ok(r) => let
              val want_help = $AP.get_bool(r, h_help)
            in
              if want_help then let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(extra_buf)
              in print_usage() end
              else let
              val () = (if $AP.get_bool(r, h_verbose) then set_verbose(true) else ())
              val () = (if $AP.get_bool(r, h_quiet) then set_quiet(true) else ())
              val () = (if $AP.get_bool(r, h_cold) then set_cold(true) else ())
              (* Handle --run-in *)
              val () = (if $AP.is_present(r, h_run_in) then let
                val ri_buf = $A.alloc<byte>(4096)
                val _ = $AP.get_string_copy(r, h_run_in, ri_buf, 4096)
                val @(fz_ri, bv_ri) = $A.freeze<byte>(ri_buf)
                val chdr = $F.file_chdir(bv_ri, 4096)
                val () = $R.discard<int><$F.io_error>(chdr)
                val () = $A.drop<byte>(fz_ri, bv_ri)
                val () = $A.free<byte>($A.thaw<byte>(fz_ri))
              in end else ())
              (* --repository: passed to the commands that use it; length 0
                 when absent *)
              val repo_buf = $A.alloc<byte>(4096)
              val repo_flag_len = opt_string_copy(r, h_repository, repo_buf, 4096)
              (* without --repository, BATS_REPOSITORY names it (bats-lang/bats#250) *)
              val repo_len = repository_len(repo_buf, repo_flag_len)
              val @(fz_repo, bv_repo) = $A.freeze<byte>(repo_buf)
              val @(fz_extra, bv_extra) = $A.freeze<byte>(extra_buf)
              (* --to-c: passed to do_build; length 0 when absent *)
              val tc_buf = $A.alloc<byte>(4096)
              val tc_len = opt_string_copy(r, h_to_c, tc_buf, 4096)
              val () = (if tc_len > 0 then set_to_c(true) else ())
              val @(fz_tc, bv_tc) = $A.freeze<byte>(tc_buf)
              (* Get command *)
              val cmd_buf = $A.alloc<byte>(32)
              val cmd_len = $AP.get_string_copy(r, h_cmd, cmd_buf, 32)
              val chosen_command = dispatch_cmd(cmd_buf, cmd_len)
              val () = $A.free<byte>(cmd_buf)
              val arg_buf = $A.alloc<byte>(4096)
              val arg_len = $AP.get_string_copy(r, h_arg, arg_buf, 4096)
              (* The project's lock, for the commands that write
                 build/, dist/ or bats_modules/ (run takes its own, and
                 releases it before the program runs) *)
              (* build-jobs: --jobs is a number from 1 or the word cores, else nothing is run *)
              val jobs_buf = $A.alloc<byte>(4096)
              val jobs_len = opt_string_copy(r, h_jobs, jobs_buf, 4096)
              val jobs_taken = jobs_option(jobs_buf, jobs_len)
              val jobs_ok = (if $AP.is_present(r, h_jobs) then jobs_taken else true): bool
              val () = $A.free<byte>(jobs_buf)
              val lk = (if ~jobs_ok then ProjectUnlocked(SlotNone())
                else if locks_project(chosen_command) then project_lock_take(heavy_of(chosen_command))
                else ProjectUnlocked(SlotNone())): project_lock
            in let val () = (
              (* machine-slots: a refused slot runs nothing (bats#464) *)
              if project_lock_refused(lk) then let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val () = set_build_err()
              in end else if ~jobs_ok then let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val () = prerr! ("error: --jobs takes a number from 1 or the word cores\n")
                val () = set_build_err()
              in end else if force_misuse(chosen_command, force_count, $AP.get_bool(r, h_force)) then let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val () = prerr! ("error: --force is accepted once, and only by ats2 install\nusage: bats ats2 install [--force]\n")
                val () = set_build_err()
              in end else (
              case+ chosen_command of
              | Build() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val profile_choice = profiles_of(named_only)
                val target_choice = targets_of(named_only)
              in
                (* Rust: cmd_build's config::load, then build's kind
                   check, then resolve_deps, once before the builds *)
                if ~bin_package() then ()
                else if ~resolve_deps(bv_repo, repo_len) then ()
                else if ~validate_project() then ()
                else let
                  (* The matrix: an axis --only does not name keeps all
                     its values (debug and release; native and wasm) *)
                  val dbg = makes_debug(profile_choice)
                  val rls = makes_release(profile_choice)
                  val nat = makes_native(target_choice)
                  val wsm = makes_wasm(target_choice)
                  val () = (if nat then (if dbg then do_build(Debug(), Native(), bv_tc, tc_len) else ()) else ())
                  val () = (if nat then (if rls then do_build(Release(), Native(), bv_tc, tc_len) else ()) else ())
                  val () = (if wsm then (if dbg then do_build(Debug(), Wasm(), bv_tc, tc_len) else ()) else ())
                  val () = (if named_only.wasm then
                    if is_to_c() then
                      println! ("error: --to-c wasm is not yet implemented without shell")
                    else ()
                  else ())
                in (if wsm then (if rls then do_build(Release(), Wasm(), bv_tc, tc_len) else ()) else ()) end
              end
              | Check() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              (* Rust: cmd_check's config::load, then resolve_deps *)
              in if ~project_known() then () else if ~resolve_deps(bv_repo, repo_len) then () else if validate_project() then do_check() else () end
              | Clean() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_clean() end
              | Lock() => let
                val lk_dev = $AP.is_present(r, h_dev)
                val lk_dry = $AP.is_present(r, h_dry_run)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_lock(lk_dev, lk_dry, bv_repo, repo_len) end
              | Run() => let
                val bin_buf = $A.alloc<byte>(256)
                val bin_len = opt_string_copy(r, h_bin, bin_buf, 256)
                (* The profile --only names for bats run: release when it
                   is "release", else debug *)
                fn check_only_release {l2:agz}
                  (buf: !$A.arr(byte, l2, 32), olen: int): profile =
                  if olen = 7 then let
                    val b0 = byte2int0($A.get<byte>(buf, 0))
                  in (if $AR.eq_int_int(b0, 114) then Release() else Debug()): profile end
                  else Debug()
                val run_profile = (let
                  val ob2 = $A.alloc<byte>(32)
                  val ol2 = $AP.get_string_copy(r, h_only, ob2, 32)
                  val chosen_profile = check_only_release(ob2, ol2)
                  val () = $A.free<byte>(ob2)
                in chosen_profile end): profile
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val @(fz_bin, bv_bin) = $A.freeze<byte>(bin_buf)
                val run_lock = project_lock_take(HeavyRun())
                val () = (if project_lock_refused(run_lock) then let
                    val () = set_build_err()
                  in project_lock_release(run_lock) end
                  else if ~bin_package() then project_lock_release(run_lock)
                  else if ~resolve_deps(bv_repo, repo_len) then project_lock_release(run_lock)
                  else if validate_project() then
                  do_run(run_profile, bv_bin, bin_len, bv_extra, extra_len, run_lock)
                  else project_lock_release(run_lock))
                val () = $A.drop<byte>(fz_bin, bv_bin)
              in $A.free<byte>($A.thaw<byte>(fz_bin)) end
              | Init() => let
                val init_claude = $AP.get_bool(r, h_claude)
                val () = $AP.parse_result_free(r)
              in
                if arg_len > 0 then let
                  val @(fz_ia, bv_ia) = $A.freeze<byte>(arg_buf)
                  val () = do_init(bv_ia, arg_len, init_claude)
                  val () = $A.drop<byte>(fz_ia, bv_ia)
                in $A.free<byte>($A.thaw<byte>(fz_ia)) end
                else let
                  val () = $A.free<byte>(arg_buf)
                  val () = prerr! ("error: specify 'binary' or 'library'\nusage: bats init binary [--claude]\n       bats init library [--claude]")
                  val () = prerr_newline()
                in set_build_err() end
              end
              | Test() => let
                (* --filter: a substring of the test names to run *)
                val flt_buf = $A.alloc<byte>(4096)
                val flt_len = opt_string_copy(r, h_filter, flt_buf, 4096)
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
                val @(fz_flt, bv_flt) = $A.freeze<byte>(flt_buf)
                (* --only native|wasm: one target's tests; both without it *)
                val test_targets = targets_of(named_only)
                val () = (if ~project_known() then ()
                  else if ~resolve_deps(bv_repo, repo_len) then ()
                  else if validate_project() then
                    do_test(bv_flt, flt_len, makes_native(test_targets), makes_wasm(test_targets))
                  else ())
                val () = $A.drop<byte>(fz_flt, bv_flt)
              in $A.free<byte>($A.thaw<byte>(fz_flt)) end
              | Tree() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_tree() end
              | Upload() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in do_upload(bv_repo, repo_len) end
              | Add() => let
                val () = $AP.parse_result_free(r)
              in
                if arg_len > 0 then let
                  val @(fz_ab, bv_ab) = $A.freeze<byte>(arg_buf)
                  val () = do_add(bv_ab, 0, arg_len, 4096)
                  val () = $A.drop<byte>(fz_ab, bv_ab)
                  val () = $A.free<byte>($A.thaw<byte>(fz_ab))
                in end
                else let
                  val () = $A.free<byte>(arg_buf)
                in println! ("error: specify a package name\nusage: bats add <package>") end
              end
              | Remove() => let
                val () = $AP.parse_result_free(r)
              in
                if arg_len > 0 then let
                  val @(fz_rb, bv_rb) = $A.freeze<byte>(arg_buf)
                  val () = do_remove(bv_rb, 0, arg_len, 4096)
                  val () = $A.drop<byte>(fz_rb, bv_rb)
                  val () = $A.free<byte>($A.thaw<byte>(fz_rb))
                in end
                else let
                  val () = $A.free<byte>(arg_buf)
                in println! ("error: specify a package name\nusage: bats remove <package>") end
              end
              | Completions() => let
                val () = $AP.parse_result_free(r)
                (* The shell the argument names, by its first byte *)
                fn check_shell_arg {l2:agz}
                  (buf: !$A.arr(byte, l2, 4096), alen: int): $R.option(shell) =
                  if alen <= 0 then $R.none()
                  else let val b0 = byte2int0($A.get<byte>(buf, 0)) in
                    if $AR.eq_int_int(b0, 98) then $R.some(Bash())
                    else if $AR.eq_int_int(b0, 122) then $R.some(Zsh())
                    else if $AR.eq_int_int(b0, 102) then $R.some(Fish())
                    else $R.none()
                  end
                val named_shell = check_shell_arg(arg_buf, arg_len)
                val () = $A.free<byte>(arg_buf)
              in
                case+ named_shell of
                | ~$R.some(target) => do_completions(target)
                | ~$R.none() => println! ("error: specify a shell (bash, zsh, fish)\nusage: bats completions bash|zsh|fish")
              end
              | Ats2() => let
                val with_force = $AP.get_bool(r, h_force)
                val () = $AP.parse_result_free(r)
                (* the one subcommand: install *)
                fn is_install_arg {l2:agz} (buf: !$A.arr(byte, l2, 4096), alen: int): bool =
                  alen = 7 && peek_arr(buf, 0, 4096) = 105 && peek_arr(buf, 1, 4096) = 110
                  && peek_arr(buf, 2, 4096) = 115 && peek_arr(buf, 3, 4096) = 116
                  && peek_arr(buf, 4, 4096) = 97 && peek_arr(buf, 5, 4096) = 108
                  && peek_arr(buf, 6, 4096) = 108
                fn is_marker_arg {l2:agz} (buf: !$A.arr(byte, l2, 4096), alen: int): bool =
                  alen = 6 && peek_arr(buf, 0, 4096) = 109 && peek_arr(buf, 1, 4096) = 97
                  && peek_arr(buf, 2, 4096) = 114 && peek_arr(buf, 3, 4096) = 107
                  && peek_arr(buf, 4, 4096) = 101 && peek_arr(buf, 5, 4096) = 114
                val install = is_install_arg(arg_buf, arg_len)
                val marker = is_marker_arg(arg_buf, arg_len)
                val () = $A.free<byte>(arg_buf)
              in
                if positionals > 3 || extra_len > 0 then let
                  val () = prerr! ("error: unexpected extra argument\nusage: bats ats2 install [--force]\n")
                in set_build_err() end
                else if marker then (if with_force then let
                    val () = prerr! ("error: --force is accepted once, and only by ats2 install\nusage: bats ats2 install [--force]\n")
                  in set_build_err() end
                  else ats2_print_marker())
                else if install then (if (if with_force then ats2_install_force() else ats2_ensure(Say())) then () else set_build_err())
                else let
                  val () = prerr! ("error: specify 'install' or 'marker'\nusage: bats ats2 install [--force]\n       bats ats2 marker\n")
                in set_build_err() end
              end
              | CloneRepository() => let
                val () = $AP.parse_result_free(r)
                val @(fz_cm, bv_cm) = $A.freeze<byte>(arg_buf)
                val () = (if positionals > 3 || extra_len > 0 then let val () = prerr! ("error: unexpected extra argument\nusage: bats clone-repository <commit> --repository <dir>\n") in set_build_err() end
                  else if clone_repository(bv_cm, arg_len, bv_repo, repo_len) then () else set_build_err())
                val () = $A.drop<byte>(fz_cm, bv_cm)
              in $A.free<byte>($A.thaw<byte>(fz_cm)) end
              | RecordCommit() => let
                val () = $AP.parse_result_free(r)
                val @(fz_cm, bv_cm) = $A.freeze<byte>(arg_buf)
                val () = (if positionals > 3 || extra_len > 0 then let val () = prerr! ("error: unexpected extra argument\nusage: bats record-commit <commit>\n") in set_build_err() end
                  else if record_commit(bv_cm, arg_len) then () else set_build_err())
                val () = $A.drop<byte>(fz_cm, bv_cm)
              in $A.free<byte>($A.thaw<byte>(fz_cm)) end
              | Version() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in println! ("bats 0.1.0") end
              | UnknownCommand() => let
                val () = $AP.parse_result_free(r)
                val () = $A.free<byte>(arg_buf)
              in println! ("usage: bats <init|lock|add|remove|build|run|test|check|tree|upload|clean|ats2|clone-repository|record-commit|completions> [--only debug|release]") end))
              val () = project_lock_release(lk)
              val () = $A.drop<byte>(fz_repo, bv_repo)
              val () = $A.free<byte>($A.thaw<byte>(fz_repo))
              val () = $A.drop<byte>(fz_extra, bv_extra)
              val () = $A.free<byte>($A.thaw<byte>(fz_extra))
              val () = $A.drop<byte>(fz_tc, bv_tc)
              val () = $A.free<byte>($A.thaw<byte>(fz_tc))
            in end
            end end
          | ~$R.err(e) => let
              val () = $AP.parse_error_free(e)
              val () = $A.free<byte>(extra_buf)
              val () = print_usage()
            in (if setup_word then set_build_err() else ()) end
        end
      | ~$R.none() => let
          val () = $A.free<byte>(cl_buf)
        in println! ("Cannot read the command line") end
end

(* Exit non-zero when any command recorded an error, so CI and scripts
   can rely on the exit status. *)
implement __BATS_main0 () = let
  (* bats with-env runs the command it is given; argv[1] is read before
     bats's own arguments are, so the command's own flags (--help, --) are
     its alone *)
  val () = (if with_env_main () then () else if fixtures_main () then () else if pins_main () then () else if affected_main () then () else if merge_proof_main () then () else bats_main ())
in
  if has_build_err () then exit_void (if get_cap_exit () <> 0 then get_cap_exit () else 1)
  else if get_exit_code () <> 0 then exit_void (get_exit_code ())
  else ()
end
