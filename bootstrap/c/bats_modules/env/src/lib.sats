staload A = "array/src/lib.sats"
staload R = "result/src/lib.sats"


















fn get
  {ln:agz}{nn:pos | nn < 1048576}
  {l:agz}{n:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   buf: !$A.arr(byte, l, n), max_len: int n)
  : $R.option(int)

fn get_cstr
  {ln:agz}{nn:pos}
  {l:agz}{n:pos}
  (name: !$A.arr(byte, ln, nn), buf: !$A.arr(byte, l, n), max_len: int n)
  : $R.option(int)






















