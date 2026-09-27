staload "./lib.sats"
staload "array/src/lib.dats"
staload "result/src/lib.dats"
(* env -- safe environment variable access *)
(* Reads env vars into arrays. No mutation of the environment. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload R = "result/src/lib.sats"

(* ============================================================
   C runtime (the entire unsafe surface)
   ============================================================ *)


%{#
#ifndef _ENV_RUNTIME_DEFINED
#define _ENV_RUNTIME_DEFINED
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <crt_externs.h>
#elif defined(__FreeBSD__) || defined(__DragonFly__) || defined(__NetBSD__) || defined(__OpenBSD__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

static int _env_getenv(const char *name, void *buf, int max_len) {
  const char *val = getenv(name);
  if (!val) return -1;
  int len = (int)strlen(val);
  if (len > max_len) len = max_len;
  memcpy(buf, val, (unsigned int)len);
  return len;
}

/* The current directory's absolute path, truncated to max_len bytes;
   -1 when it cannot be determined. */
static int _env_cwd(void *buf, int max_len) {
  char tmp[4096];
  int len;
  if (!getcwd(tmp, sizeof tmp)) return -1;
  len = (int)strlen(tmp);
  if (len > max_len) len = max_len;
  memcpy(buf, tmp, (unsigned int)len);
  return len;
}

/* Whether standard error is a terminal. */
static int _env_stderr_tty(void) {
  return isatty(2) ? 1 : 0;
}

/* Copies argv[0..argc) into buf as NUL-terminated strings back to back,
   stopping at max_len bytes. Returns the byte count. */
static int _env_copy_argv(int argc, char **argv, char *buf, int max_len) {
  int i, k = 0;
  for (i = 0; i < argc && k < max_len; i++) {
    int len = (int)strlen(argv[i]) + 1;
    if (len > max_len - k) len = max_len - k;
    memcpy(buf + k, argv[i], (unsigned int)len);
    k += len;
  }
  return k;
}

/* The process's arguments in the format of Linux's /proc/self/cmdline
   (NUL-terminated strings back to back), truncated to max_len bytes;
   -1 when they cannot be read. */
static int _env_args(void *vbuf, int max_len) {
  char *buf = (char *)vbuf;
#if defined(__APPLE__)
  return _env_copy_argv(*_NSGetArgc(), *_NSGetArgv(), buf, max_len);
#elif defined(__OpenBSD__)
  int mib[4] = { CTL_KERN, KERN_PROC_ARGS, 0, KERN_PROC_ARGV };
  size_t sz = 0;
  char **argv;
  int argc = 0, k;
  mib[2] = (int)getpid();
  if (sysctl(mib, 4, NULL, &sz, NULL, 0) != 0) return -1;
  argv = (char **)malloc(sz);
  if (!argv) return -1;
  if (sysctl(mib, 4, argv, &sz, NULL, 0) != 0) { free(argv); return -1; }
  while (argv[argc]) argc++;
  k = _env_copy_argv(argc, argv, buf, max_len);
  free(argv);
  return k;
#elif defined(__FreeBSD__) || defined(__DragonFly__) || defined(__NetBSD__)
#if defined(__NetBSD__)
  int mib[4] = { CTL_KERN, KERN_PROC_ARGS, 0, KERN_PROC_ARGV };
  int pid_at = 2;
#else
  int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ARGS, 0 };
  int pid_at = 3;
#endif
  size_t sz = 0;
  char *all;
  mib[pid_at] = (int)getpid();
  if (sysctl(mib, 4, NULL, &sz, NULL, 0) != 0) return -1;
  all = (char *)malloc(sz);
  if (!all) return -1;
  if (sysctl(mib, 4, all, &sz, NULL, 0) != 0) { free(all); return -1; }
  if (sz > (size_t)max_len) sz = (size_t)max_len;
  memcpy(buf, all, sz);
  free(all);
  return (int)sz;
#else
  int fd = open("/proc/self/cmdline", O_RDONLY);
  int k = 0;
  if (fd < 0) return -1;
  while (k < max_len) {
    int n = (int)read(fd, buf + k, (unsigned int)(max_len - k));
    if (n <= 0) break;
    k += n;
  }
  close(fd);
  return k;
#endif
}
#endif
%}


(* ============================================================
   Public API
   ============================================================ *)








(* As get, with the name in an array of name_len bytes: the name is
   its bytes up to its first NUL, or all of them when it has none
   (getenv is handed a NUL-terminated copy, never the array itself).
   The value's length (copied to buf[0, k), truncated to max_len), or
   none when the variable is unset. *)







(* The process's arguments, argv[0] first, as NUL-terminated strings
   back to back in buf[0, k), truncated to max_len bytes; none when the
   system cannot supply them. *)





(* The current directory's absolute path in buf[0, k), truncated to
   max_len bytes; none when it cannot be determined. *)





(* Whether the process's standard error is a terminal (isatty). *)


(* ============================================================
   Implementation
   ============================================================ *)

implement get {ln}{nn}{l}{n} (name, name_len, buf, max_len) = let
  val cname = $A.alloc<byte>(name_len + 1)
  val () = $A.write_borrow(cname, 0, name, name_len)
  val () = $A.write_byte(cname, name_len, 0)
  val len =  $extfcall([k:int | k <= n] int k, "_env_getenv",
    $UNSAFE.castvwtp1{ptr}(cname),
    $UNSAFE.castvwtp1{ptr}(buf),
    max_len) 
  val () = $A.free<byte>(cname)
in
  if len >= 0 then $R.some(len)
  else $R.none()
end

(* Copies src[i, n) to dst[i, n). *)
fun _copy_from
  {ls,ld:agz}{n,m:nat | n <= m}{i:nat | i <= n} .<n - i>.
  (src: !$A.arr(byte, ls, n), dst: !$A.arr(byte, ld, m), n: int n, i: int i)
  : void =
  if i < n then let
    val () = $A.set<byte>(dst, i, $A.get<byte>(src, i))
  in _copy_from(src, dst, n, i + 1) end

implement get_cstr {ln}{nn}{l}{n} (name, name_len, buf, max_len) = let
  val cname = $A.alloc<byte>(name_len + 1)
  val () = _copy_from(name, cname, name_len, 0)
  val () = $A.write_byte(cname, name_len, 0)
  val len =  $extfcall([k:int | k <= n] int k, "_env_getenv",
    $UNSAFE.castvwtp1{ptr}(cname),
    $UNSAFE.castvwtp1{ptr}(buf),
    max_len) 
  val () = $A.free<byte>(cname)
in
  if len >= 0 then $R.some(len)
  else $R.none()
end

implement args_read {l}{n} (buf, max_len) = let
  val len =  $extfcall([k:int | k <= n] int k, "_env_args",
    $UNSAFE.castvwtp1{ptr}(buf), max_len) 
in
  if len >= 0 then $R.some(len)
  else $R.none()
end

implement cwd_read {l}{n} (buf, max_len) = let
  val len =  $extfcall([k:int | k <= n] int k, "_env_cwd",
    $UNSAFE.castvwtp1{ptr}(buf), max_len) 
in
  if len >= 0 then $R.some(len)
  else $R.none()
end

implement stderr_is_terminal () =
   $extfcall(int, "_env_stderr_tty")  = 1
