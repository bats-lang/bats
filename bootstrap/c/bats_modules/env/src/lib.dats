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

static int _env_getenv(const char *name, void *buf, int max_len) {
  const char *val = getenv(name);
  if (!val) return -1;
  int len = (int)strlen(val);
  if (len > max_len) len = max_len;
  memcpy(buf, val, (unsigned int)len);
  return len;
}
#endif
%}


(* ============================================================
   Public API
   ============================================================ *)














(* ============================================================
   Implementation
   ============================================================ *)

implement get {ln}{nn}{l}{n} (name, name_len, buf, max_len) = let
  val cname = $A.alloc<byte>(name_len + 1)
  val () = $A.write_borrow(cname, 0, name, name_len)
  val () = $A.write_byte(cname, name_len, 0)
  val len =  $extfcall(int, "_env_getenv",
    $UNSAFE.castvwtp1{ptr}(cname),
    $UNSAFE.castvwtp1{ptr}(buf),
    max_len) 
  val () = $A.free<byte>(cname)
in
  if len >= 0 then $R.some(len)
  else $R.none()
end

implement get_cstr {ln}{nn}{l}{n} (name, buf, max_len) = let
  val len =  $extfcall(int, "_env_getenv",
    $UNSAFE.castvwtp1{ptr}(name),
    $UNSAFE.castvwtp1{ptr}(buf),
    max_len) 
in
  if len >= 0 then $R.some(len)
  else $R.none()
end
