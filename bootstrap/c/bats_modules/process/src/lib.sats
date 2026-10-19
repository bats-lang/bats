staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload L = "list/src/lib.sats"
staload R = "result/src/lib.sats"
staload F = "file/src/lib.sats"






























datavtype child =
  | child_mk of (int)


datavtype pipe_end(b:bool) =
  | pipe_fd(true) of ($F.fd)
  | pipe_none(false) of ()






datavtype stream_config(b:bool) =
  | pipe_new(true) of ()
  | inherit_fd(false) of ($F.fd)
  | dev_null(false) of ()
  | inherit(false) of ()


datavtype spawn_pipes(sin:bool, sout:bool, serr:bool) =
  | spawn_pipes_mk(sin, sout, serr) of (
      child,
      pipe_end(sin),
      pipe_end(sout),
      pipe_end(serr)
    )


stadef ARG_ENTRY_MAX = 524288





stadef ARG_TOTAL_MAX = 524287






vtypedef arg_entry =
  [l:agz][cap:pos][n:nat | n <= cap; cap <= ARG_ENTRY_MAX]
  @($A.arr(byte, l, cap), int n)







dataprop NUL_AT($A.cells, int, int) =
  | {cs:$A.cells}{n:nat}{k:nat | k < n}
    NUL_mk(cs, n, k) of ($A.CLEN(cs, n), $A.NTH(cs, k, 0))





fn child_wait(c: child): $R.result(int, int)

fn child_try_wait(c: !child): $R.option(int)

fn child_pid(c: !child): int

fn pipe_end_close {b:bool} (p: pipe_end(b)): void



fn os_error_text {l:agz}{n:pos}
  (code: int, buf: !$A.arr(byte, l, n), max: int n): [k:nat | k <= n] int k










fn spawn
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}
  (path: !$A.borrow(byte, lp, 524288),
   argv: $L.listv(arg_entry),
   envp: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)






fn spawn_inherit_env_with
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}
  (path: !$A.borrow(byte, lp, 524288),
   argv: $L.listv(arg_entry),
   extra: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)





fn spawn_inherit_env
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}
  (path: !$A.borrow(byte, lp, 524288),
   argv: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)




fn path_of_string_proved {sn:nat | sn < $B.BUILDER_CAP} (s: string sn)
  : [l:agz][n:pos][cs:$A.cells][k:nat | k < n]
    (NUL_AT(cs, n, k) | $A.barr(l, n, cs))






fn spawn_proved
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}{np:pos}{cs:$A.cells}{k:nat | k < np}
  (nul: NUL_AT(cs, np, k) | path: !$A.cborrow(lp, np, cs),
   argv: $L.listv(arg_entry),
   envp: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)



fn spawn_inherit_env_with_proved
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}{np:pos}{cs:$A.cells}{k:nat | k < np}
  (nul: NUL_AT(cs, np, k) | path: !$A.cborrow(lp, np, cs),
   argv: $L.listv(arg_entry),
   extra: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)


fn spawn_inherit_env_proved
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}{np:pos}{cs:$A.cells}{k:nat | k < np}
  (nul: NUL_AT(cs, np, k) | path: !$A.cborrow(lp, np, cs),
   argv: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)



















































































































































































































































































































