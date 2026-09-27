







datatype list_t(t@ype, int) =
  | {a:t@ype} list_nil(a, 0) of ()
  | {a:t@ype}{n:nat} list_cons(a, n+1) of (a, list_t(a, n))

typedef list(a:t@ype) = [n:nat] list_t(a, n)





fun {a:t@ype} nil (): list_t(a, 0)

fun {a:t@ype} cons {n:nat}
  (x: a, xs: list_t(a, n)): list_t(a, n+1)









fun {a:t@ype} length {n:nat}
  (xs: list_t(a, n)): int(n)













fun {a:t@ype} reverse {n:nat}
  (xs: list_t(a, n)): list_t(a, n)













fun {a:t@ype} head {n:pos}
  (xs: list_t(a, n)): a

fun {a:t@ype} tail {n:pos}
  (xs: list_t(a, n)): list_t(a, n-1)











fun {a:t@ype}{b:t@ype} map {n:nat}
  (xs: list_t(a, n), f: a -<cloref1> b): list_t(b, n)









fun {a:t@ype}{b:t@ype} foldl {n:nat}
  (xs: list_t(a, n), init: b, f: (b, a) -<cloref1> b): b













fun {a:t@ype} append {m:nat}{n:nat}
  (xs: list_t(a, m), ys: list_t(a, n)): list_t(a, m+n)













fun {a:t@ype} is_nil {n:nat}
  (xs: list_t(a, n)): bool(n == 0)










datavtype list_vt(vt@ype+, int) =
  | {a:vt@ype} list_vt_nil(a, 0) of ()
  | {a:vt@ype}{n:nat} list_vt_cons(a, n+1) of (a, list_vt(a, n))

vtypedef listv(a:vt@ype) = [n:nat] list_vt(a, n)



































