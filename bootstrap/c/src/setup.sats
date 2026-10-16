staload A = "array/src/lib.sats"
staload B = "builder/src/lib.sats"
staload L = "list/src/lib.sats"
staload P = "process/src/lib.sats"
staload R = "result/src/lib.sats"


















staload "helpers.sats"

























































fn clone_repository {l1,l2:agz}
  (commit: !$A.borrow(byte, l1, 4096), clen: int,
   dir: !$A.borrow(byte, l2, 4096), dlen: int): bool


















fn record_commit {l1:agz}
  (commit: !$A.borrow(byte, l1, 4096), clen: int): bool













