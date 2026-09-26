staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload B = "builder/src/lib.sats"
staload L = "list/src/lib.sats"
staload R = "result/src/lib.sats"
staload S = "str/src/lib.sats"
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


vtypedef arg_entry = [l:agz] @($A.arr(byte, l, 524288), int)





fn child_wait(c: child): $R.result(int, int)

fn child_try_wait(c: !child): $R.option(int)

fn child_pid(c: !child): int

fn pipe_end_close {b:bool} (p: pipe_end(b)): void

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


fn spawn_inherit_env
  {sin:bool}{sout:bool}{serr:bool}
  {lp:agz}
  (path: !$A.borrow(byte, lp, 524288),
   argv: $L.listv(arg_entry),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)












































































































































































