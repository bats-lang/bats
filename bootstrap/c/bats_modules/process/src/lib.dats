staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
staload "builder/src/lib.dats"
staload "list/src/lib.dats"
staload "result/src/lib.dats"
staload "file/src/lib.dats"
(* process -- safe process spawning with linear child handles *)
(* Linear child must be waited on. Pipes are linear fds from file package. *)
(* Type-indexed: pipe_new in config guarantees fd in result. *)
(*
   IMPORTANT: The ONLY public spawn function is `spawn`.
   It takes byte-array borrows via listv(arg_entry).
   Do NOT add string-based wrappers, builder-based wrappers,
   or any other spawn variants. Callers build arg_entry lists
   themselves. No exceptions.
*)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload L = "list/src/lib.sats"
staload R = "result/src/lib.sats"
staload F = "file/src/lib.sats"

(* ============================================================
   C runtime (the entire unsafe surface)
   ============================================================ *)


%{#
#ifndef _PROCESS_RUNTIME_DEFINED
#define _PROCESS_RUNTIME_DEFINED
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

typedef struct {
  int pid;
  int stdin_parent_fd;
  int stdout_parent_fd;
  int stderr_parent_fd;
} _spawn_result_t;

extern char **environ;

/* execve, or, when file has no '/', execve of each PATH entry joined
   with file in turn, as execvp does: the Rust bats ran its tools by
   name through Command. Returns only if nothing could be executed. */
static void _exec_search(const char *file, char *const argv[], char *const envp[]) {
  const char *path;
  char buf[4096];
  size_t flen = strlen(file);
  if (strchr(file, '/')) { execve(file, argv, envp); return; }
  path = getenv("PATH");
  if (!path || !*path) path = "/usr/bin:/bin";
  for (;;) {
    const char *colon = strchr(path, ':');
    size_t len = colon ? (size_t)(colon - path) : strlen(path);
    if (len == 0) {
      if (flen + 1 <= sizeof buf) { memcpy(buf, file, flen + 1); execve(buf, argv, envp); }
    } else if (len + 1 + flen + 1 <= sizeof buf) {
      memcpy(buf, path, len); buf[len] = '/'; memcpy(buf + len + 1, file, flen + 1);
      execve(buf, argv, envp);
    }
    if (!colon) break;
    path = colon + 1;
  }
}

/* Global to pass result back (avoids returning struct by value issues) */
static _spawn_result_t _spawn_res;

static int _proc_spawn(
  const char *path,
  const char *argv_buf, int argv_count,
  const char *envp_buf, int envp_count,
  int stdin_mode, int stdin_fd,
  int stdout_mode, int stdout_fd,
  int stderr_mode, int stderr_fd
) {
  _spawn_res.pid = -1;
  _spawn_res.stdin_parent_fd = -1;
  _spawn_res.stdout_parent_fd = -1;
  _spawn_res.stderr_parent_fd = -1;

  int stdin_pipe[2] = {-1, -1};
  int stdout_pipe[2] = {-1, -1};
  int stderr_pipe[2] = {-1, -1};

  if (stdin_mode == 0) {
    if (pipe(stdin_pipe) < 0) return -(errno > 0 ? errno : 1);
  }
  if (stdout_mode == 0) {
    if (pipe(stdout_pipe) < 0) {
      int e = errno;
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      return -(e > 0 ? e : 1);
    }
  }
  if (stderr_mode == 0) {
    if (pipe(stderr_pipe) < 0) {
      int e = errno;
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
      return -(e > 0 ? e : 1);
    }
  }

  /* The child writes errno here when exec fails; close-on-exec, so a
     successful exec closes it and the parent reads nothing (as Rust's
     Command::spawn does) */
  int exec_err[2] = {-1, -1};
  if (pipe(exec_err) < 0
      || fcntl(exec_err[0], F_SETFD, FD_CLOEXEC) < 0
      || fcntl(exec_err[1], F_SETFD, FD_CLOEXEC) < 0) {
    int e = errno;
    if (exec_err[0] >= 0) { close(exec_err[0]); close(exec_err[1]); }
    if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
    if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
    if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
    return -(e > 0 ? e : 1);
  }

  /* envp_count >= 0: exactly the envp_count entries of envp_buf.
     envp_count = -(k + 1): the parent's environment, with the k
     NAME=VALUE entries of envp_buf added or replacing. */
  int inherit = envp_count < 0;
  int nlist = inherit ? -envp_count - 1 : envp_count;
  /* Sized by the counts: every argument and entry is passed */
  const char **argv_ptrs = (const char **)malloc(((size_t)(argv_count > 0 ? argv_count : 0) + 1) * sizeof(char *));
  const char **envp_ptrs = (const char **)malloc(((size_t)(nlist > 0 ? nlist : 0) + 1) * sizeof(char *));
  if (!argv_ptrs || !envp_ptrs) {
    free(argv_ptrs); free(envp_ptrs);
    close(exec_err[0]); close(exec_err[1]);
    if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
    if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
    if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
    return -ENOMEM;
  }
  int ai = 0;
  const char *p = argv_buf;
  int i;
  for (i = 0; i < argv_count; i++) {
    argv_ptrs[ai++] = p;
    p += strlen(p) + 1;
  }
  argv_ptrs[ai] = (const char *)0;
  int ei = 0;
  p = envp_buf;
  for (i = 0; i < nlist; i++) {
    envp_ptrs[ei++] = p;
    p += strlen(p) + 1;
  }
  envp_ptrs[ei] = (const char *)0;

  char **envv = (char **)0;
  if (inherit) {
    size_t n = 0, k = 0, j;
    int e;
    while (environ[n]) n++;
    envv = (char **)malloc((n + (size_t)ei + 1) * sizeof(char *));
    if (!envv) {
      free(argv_ptrs); free(envp_ptrs);
      close(exec_err[0]); close(exec_err[1]);
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
      if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
      return -ENOMEM;
    }
    for (j = 0; j < n; j++) {
      size_t len = strcspn(environ[j], "=");
      int replaced = 0;
      for (e = 0; e < ei; e++)
        if (strncmp(envp_ptrs[e], environ[j], len) == 0 && envp_ptrs[e][len] == '=') replaced = 1;
      if (!replaced) envv[k++] = environ[j];
    }
    for (e = 0; e < ei; e++) envv[k++] = (char *)envp_ptrs[e];
    envv[k] = (char *)0;
  }

  int pid = fork();
  if (pid < 0) {
    int e = errno;
    free(envv); free(argv_ptrs); free(envp_ptrs);
    close(exec_err[0]); close(exec_err[1]);
    if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
    if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
    if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
    return -(e > 0 ? e : 1);
  }

  if (pid == 0) {
    close(exec_err[0]);
    if (stdin_mode == 0) {
      dup2(stdin_pipe[0], 0); close(stdin_pipe[0]); close(stdin_pipe[1]);
    } else if (stdin_mode == 1) {
      if (stdin_fd != 0) { dup2(stdin_fd, 0); close(stdin_fd); }
    } else if (stdin_mode == 2) {
      int dn = open("/dev/null", O_RDONLY); if (dn >= 0) { dup2(dn, 0); close(dn); }
    }
    if (stdout_mode == 0) {
      dup2(stdout_pipe[1], 1); close(stdout_pipe[0]); close(stdout_pipe[1]);
    } else if (stdout_mode == 1) {
      if (stdout_fd != 1) { dup2(stdout_fd, 1); close(stdout_fd); }
    } else if (stdout_mode == 2) {
      int dn = open("/dev/null", O_WRONLY); if (dn >= 0) { dup2(dn, 1); close(dn); }
    }
    if (stderr_mode == 0) {
      dup2(stderr_pipe[1], 2); close(stderr_pipe[0]); close(stderr_pipe[1]);
    } else if (stderr_mode == 1) {
      if (stderr_fd != 2) { dup2(stderr_fd, 2); close(stderr_fd); }
    } else if (stderr_mode == 2) {
      int dn = open("/dev/null", O_WRONLY); if (dn >= 0) { dup2(dn, 2); close(dn); }
    }
    _exec_search(path, (char *const *)argv_ptrs,
           inherit ? envv : (char *const *)envp_ptrs);
    {
      int e = errno;
      ssize_t w;
      do { w = write(exec_err[1], &e, sizeof e); } while (w < 0 && errno == EINTR);
    }
    _exit(127);
  }

  free(envv); free(argv_ptrs); free(envp_ptrs);
  close(exec_err[1]);
  {
    int e = 0;
    ssize_t r;
    do { r = read(exec_err[0], &e, sizeof e); } while (r < 0 && errno == EINTR);
    close(exec_err[0]);
    if (r == (ssize_t)sizeof e) {
      int st;
      while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
      if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
      if (stdin_mode == 1) close(stdin_fd);
      if (stdout_mode == 1) close(stdout_fd);
      if (stderr_mode == 1) close(stderr_fd);
      return -(e > 0 ? e : 1);
    }
  }
  if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); _spawn_res.stdin_parent_fd = stdin_pipe[1]; }
  if (stdout_pipe[1] >= 0) { close(stdout_pipe[1]); _spawn_res.stdout_parent_fd = stdout_pipe[0]; }
  if (stderr_pipe[1] >= 0) { close(stderr_pipe[1]); _spawn_res.stderr_parent_fd = stderr_pipe[0]; }
  if (stdin_mode == 1) close(stdin_fd);
  if (stdout_mode == 1) close(stdout_fd);
  if (stderr_mode == 1) close(stderr_fd);
  _spawn_res.pid = pid;
  return pid;
}

/* strerror(code) copied into buf[0, max); its length */
static int _proc_error_text(int code, char *buf, int max) {
  const char *s = strerror(code);
  size_t n = s ? strlen(s) : 0;
  if (n > (size_t)max) n = (size_t)max;
  if (n) memcpy(buf, s, n);
  return (int)n;
}

static int _spawn_get_stdin_fd(void) { return _spawn_res.stdin_parent_fd; }
static int _spawn_get_stdout_fd(void) { return _spawn_res.stdout_parent_fd; }
static int _spawn_get_stderr_fd(void) { return _spawn_res.stderr_parent_fd; }

static int _proc_wait(int pid) {
  int status;
  if (waitpid(pid, &status, 0) < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
}

static int _proc_try_wait(int pid) {
  int status;
  int r = waitpid(pid, &status, WNOHANG);
  if (r == 0) return -2;
  if (r < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
}
#endif
%}


(* ============================================================
   Types
   ============================================================ *)




(* Type-level conditional: pipe_fd iff b=true *)




(* Stream config indexed by bool — pipe_new proves b=true.
   pipe_new: a new pipe, whose other end the parent gets.
   inherit_fd: the given fd, which the parent gives up.
   dev_null: /dev/null.
   inherit: the parent's own stream, shared and left open. *)






(* Spawn result indexed by which streams are piped *)








(* An argv/envp entry: owned array + content length. Consumed by spawn. *)


(* ============================================================
   Public API
   ============================================================ *)









(* The OS's description of error code (strerror), which Rust's io::Error
   shows before " (os error <code>)", copied into buf; its length *)



(* path: an executable's path, or a command name without '/', looked up
   on this process's PATH as execvp does. Fails with the errno (> 0) of
   what went wrong, including an exec that could not run (ENOENT for a
   command found nowhere), as Rust's Command::spawn does. *)











(* As spawn, with the parent's environment plus the NAME=VALUE entries
   of extra, each added or replacing that variable. *)











(* As spawn, with the parent's environment instead of an envp list. *)










(* ============================================================
   Internal helpers
   ============================================================ *)

(* Build pipe_end from config and raw fd.
   The config pattern match IS the proof that b matches reality. *)
fn _build_pipe_end {b:bool}
  (cfg_mode: int, rawfd: int, cfg: !stream_config(b)): pipe_end(b) =
  case+ cfg of
  | pipe_new() => pipe_fd($F.fd_mk(rawfd))
  | inherit_fd(_) => pipe_none()
  | dev_null() => pipe_none()
  | inherit() => pipe_none()

fn _cfg_mode {b:bool} (cfg: !stream_config(b)): int =
  case+ cfg of
  | pipe_new() => 0
  | inherit_fd(_) => 1
  | dev_null() => 2
  | inherit() => 3

fn _cfg_fd {b:bool} (cfg: !stream_config(b)): int =
  case+ cfg of
  | pipe_new() => ~1
  | inherit_fd(f) => let
      val+ @$F.fd_mk(rawfd) = f
      val r = rawfd
      prval () = fold@(f)
    in r end
  | dev_null() => ~1
  | inherit() => ~1

fn _consume_cfg {b:bool} (cfg: stream_config(b)): void =
  case+ cfg of
  | ~pipe_new() => ()
  | ~inherit_fd(f) => let val+ ~$F.fd_mk(_) = f in end
  | ~dev_null() => ()
  | ~inherit() => ()

(* The entries of xs, each NUL-terminated, in one builder, and their
   count; false when they do not all fit (the builder holds 524288
   bytes, and an entry's array 524288), which spawn reports as E2BIG
   rather than run the program on a cut-short list *)
fn _build_from_list(xs: $L.listv(arg_entry)): @($B.builder_v, int, bool) = let
  fun loop {n:nat} .<n>.
    (xs: $L.list_vt(arg_entry, n),
     b: !$B.builder_v >> $B.builder_v, count: int, fits: bool): @(int, bool) =
    case+ xs of
    | ~$L.list_vt_nil() => @(count, fits)
    | ~$L.list_vt_cons(@(arr, len), tl) => let
        val @(fz, bv) = $A.freeze<byte>(arr)
        (* bv[i, len) into b, whether it all fit; i < 524288 proves
           each read *)
        fun copy {lb:agz}{i:nat | i <= 524288} .<524288 - i>.
          (bv: !$A.borrow(byte, lb, 524288),
           b: !$B.builder_v >> $B.builder_v,
           i: int i, len: int): bool =
          if i >= len then true
          else if i >= 524288 then false
          else if $B.length(b) >= 524288 - 1 then false
          else let
            val () = $B.put_char(b, $AR.low_byte(byte2int0($A.read<byte>(bv, i))))
          in copy(bv, b, i + 1, len) end
        val all = copy(bv, b, 0, len)
        val room = $B.length(b) < 524288 - 1
        val () = (if room then $B.put_char(b, 0) else ())
        val () = $A.drop<byte>(fz, bv)
        val () = $A.free<byte>($A.thaw<byte>(fz))
      in loop(tl, b, count + 1, fits && all && room) end
  var b = $B.create()
  val @(count, fits) = loop(xs, b, 0, true)
in @(b, count, fits) end

(* E2BIG ("Argument list too long"), 7 on Linux, macOS and the BSDs *)
#define E2BIG 7

(* ============================================================
   Implementations
   ============================================================ *)

fn _spawn_raw
  {lp:agz}
  {la:agz}{na:pos}
  {le:agz}{ne:pos}
  {sin:bool}{sout:bool}{serr:bool}
  (path: !$A.borrow(byte, lp, 524288),
   argv: !$A.borrow(byte, la, na), argv_count: int,
   envp: !$A.borrow(byte, le, ne), envp_count: int,
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int) = let
  val sin_mode = _cfg_mode(stdin_cfg)
  val sin_fd = _cfg_fd(stdin_cfg)
  val sout_mode = _cfg_mode(stdout_cfg)
  val sout_fd = _cfg_fd(stdout_cfg)
  val serr_mode = _cfg_mode(stderr_cfg)
  val serr_fd = _cfg_fd(stderr_cfg)
  val pid =  $extfcall(int, "_proc_spawn",
    $UNSAFE.castvwtp1{ptr}(path),
    $UNSAFE.castvwtp1{ptr}(argv), argv_count,
    $UNSAFE.castvwtp1{ptr}(envp), envp_count,
    sin_mode, sin_fd, sout_mode, sout_fd, serr_mode, serr_fd) 
in
  if pid >= 0 then let
    val stdin_pfd =  $extfcall(int, "_spawn_get_stdin_fd") 
    val stdout_pfd =  $extfcall(int, "_spawn_get_stdout_fd") 
    val stderr_pfd =  $extfcall(int, "_spawn_get_stderr_fd") 
    val sin_end = _build_pipe_end(sin_mode, stdin_pfd, stdin_cfg)
    val sout_end = _build_pipe_end(sout_mode, stdout_pfd, stdout_cfg)
    val serr_end = _build_pipe_end(serr_mode, stderr_pfd, stderr_cfg)
    val () = _consume_cfg(stdin_cfg)
    val () = _consume_cfg(stdout_cfg)
    val () = _consume_cfg(stderr_cfg)
  in
    $R.ok(spawn_pipes_mk(child_mk(pid), sin_end, sout_end, serr_end))
  end
  else let
    val () = _consume_cfg(stdin_cfg)
    val () = _consume_cfg(stdout_cfg)
    val () = _consume_cfg(stderr_cfg)
  in $R.err(0 - pid) end
end

implement child_wait(c) = let
  val+ ~child_mk(pid) = c
  val status =  $extfcall(int, "_proc_wait", pid) 
in
  if status >= 0 then $R.ok(status)
  else $R.err(status)
end

implement child_try_wait(c) = let
  val+ @child_mk(pid) = c
  val status =  $extfcall(int, "_proc_try_wait", pid) 
  prval () = fold@(c)
in
  if status >= 0 then $R.some(status)
  else $R.none()
end

implement child_pid(c) = let
  val+ @child_mk(pid) = c
  val p = pid
  prval () = fold@(c)
in p end

implement os_error_text {l}{n} (code, buf, max) =
   $extfcall([k:nat | k <= n] int k, "_proc_error_text", code,
    $UNSAFE.castvwtp1{ptr}(buf), max) 

(* Static test: os_error_text's length indexes its buffer *)
fn _last_byte {l:agz}{n:pos}{k:nat | k <= n}
  (buf: !$A.arr(byte, l, n), k: int k): int =
  if k > 0 then byte2int0($A.get<byte>(buf, k - 1)) else 0

fn _test_os_error_text_bounded (): void = let
  val buf = $A.alloc<byte>(64)
  val k = os_error_text(2, buf, 64)
  val _ = _last_byte(buf, k)
in $A.free<byte>(buf) end

implement pipe_end_close {b} (p) =
  case+ p of
  | ~pipe_fd(f) => $R.discard<int><$F.io_error>($F.file_close(f))
  | ~pipe_none() => ()

(* E2BIG for an argument or environment list that does not fit;
   consumes the stream configurations as a spawn does *)
fn _too_big {sin,sout,serr:bool}
  (stdin_cfg: stream_config(sin), stdout_cfg: stream_config(sout), stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int) = let
  val () = _consume_cfg(stdin_cfg)
  val () = _consume_cfg(stdout_cfg)
  val () = _consume_cfg(stderr_cfg)
in $R.err(E2BIG) end

implement spawn {sin}{sout}{serr}{lp}
  (path, argv, envp, stdin_cfg, stdout_cfg, stderr_cfg) = let
  val @(argv_b, argc, argv_fits) = _build_from_list(argv)
  val @(argv_arr, _) = $B.to_arr(argv_b)
  val @(fz_a, bv_a) = $A.freeze<byte>(argv_arr)
  val @(envp_b, envp_c, envp_fits) = _build_from_list(envp)
  val @(envp_arr, _) = $B.to_arr(envp_b)
  val @(fz_e, bv_e) = $A.freeze<byte>(envp_arr)
  val r = (if argv_fits && envp_fits then
    _spawn_raw(path, bv_a, argc, bv_e, envp_c, stdin_cfg, stdout_cfg, stderr_cfg)
    else _too_big(stdin_cfg, stdout_cfg, stderr_cfg)): $R.result(spawn_pipes(sin, sout, serr), int)
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
  val () = $A.drop<byte>(fz_e, bv_e)
  val () = $A.free<byte>($A.thaw<byte>(fz_e))
in r end

implement spawn_inherit_env {sin}{sout}{serr}{lp}
  (path, argv, stdin_cfg, stdout_cfg, stderr_cfg) =
  spawn_inherit_env_with(path, argv, $L.list_vt_nil(), stdin_cfg, stdout_cfg, stderr_cfg)

implement spawn_inherit_env_with {sin}{sout}{serr}{lp}
  (path, argv, extra, stdin_cfg, stdout_cfg, stderr_cfg) = let
  val @(argv_b, argc, argv_fits) = _build_from_list(argv)
  val @(argv_arr, _) = $B.to_arr(argv_b)
  val @(fz_a, bv_a) = $A.freeze<byte>(argv_arr)
  val @(envp_b, extra_c, extra_fits) = _build_from_list(extra)
  val @(envp_arr, _) = $B.to_arr(envp_b)
  val @(fz_e, bv_e) = $A.freeze<byte>(envp_arr)
  val r = (if argv_fits && extra_fits then
    _spawn_raw(path, bv_a, argc, bv_e, ~(extra_c + 1), stdin_cfg, stdout_cfg, stderr_cfg)
    else _too_big(stdin_cfg, stdout_cfg, stderr_cfg)): $R.result(spawn_pipes(sin, sout, serr), int)
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
  val () = $A.drop<byte>(fz_e, bv_e)
  val () = $A.free<byte>($A.thaw<byte>(fz_e))
in r end
