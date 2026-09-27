









datavtype result(a:vt@ype, e:vt@ype) =
  | ok(a, e) of (a)
  | err(a, e) of (e)



fn{a:t@ype}{e:t@ype}
unwrap_or(r: result(a, e), default_val: a): a


fn{a:vt@ype}{e:vt@ype}
is_ok(r: !result(a, e)): bool


fn{a:vt@ype}{e:vt@ype}
is_err(r: !result(a, e)): bool


fn{a:t@ype}{e:t@ype}
discard(r: result(a, e)): void





datavtype option(a:vt@ype) =
  | some(a) of (a)
  | none(a) of ()

fn{a:t@ype}
option_unwrap_or(o: option(a), default_val: a): a

fn{a:vt@ype}
is_some(o: !option(a)): bool

fn{a:vt@ype}
is_none(o: !option(a)): bool

fn{a:t@ype}
option_discard(o: option(a)): void

































































































































