













datavtype list_vt(vt@ype+, int) =
  | {a:vt@ype} list_vt_nil(a, 0) of ()
  | {a:vt@ype}{n:nat} list_vt_cons(a, n+1) of (a, list_vt(a, n))

vtypedef listv(a:vt@ype) = [n:nat] list_vt(a, n)





fun {a:vt@ype} nil (): list_vt(a, 0)

fun {a:vt@ype} cons {n:nat}
  (x: a, xs: list_vt(a, n)): list_vt(a, n+1)



fun {a:t@ype} free {n:nat}
  (xs: list_vt(a, n)): void

















fun {a:vt@ype} length {n:nat}
  (xs: !list_vt(a, n)): int(n)

fun {a:vt@ype} is_nil {n:nat}
  (xs: !list_vt(a, n)): bool(n == 0)


















fun {a:vt@ype} reverse {n:nat}
  (xs: list_vt(a, n)): list_vt(a, n)

















fun {a:t@ype} head {n:pos}
  (xs: !list_vt(a, n)): a


fun {a:t@ype} tail {n:pos}
  (xs: list_vt(a, n)): list_vt(a, n-1)
















fun {a:t@ype}{b:vt@ype} map {n:nat}
  (xs: !list_vt(a, n), f: &(a) -<clo1> b): list_vt(b, n)

fun {a:t@ype}{b:vt@ype} foldl {n:nat}
  (xs: !list_vt(a, n), init: b, f: &(b, a) -<clo1> b): b























fun {a:vt@ype} append {m:nat}{n:nat}
  (xs: list_vt(a, m), ys: list_vt(a, n)): list_vt(a, m+n)

















































































