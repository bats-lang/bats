#!/bin/sh
# The prelude's own non-linear builders are rejected outside $UNSAFE
# too, each with a message naming its linear form: the constructors of
# list, option and stream_con (list_cons, list_nil, Some, None,
# stream_cons, stream_nil) and their macros (nil, cons, ::), the
# functions whose result is a non-linear list, option or stream built
# from something that is not one (list_append, option_of_option_vt,
# stream_make_nil, ...), $delay, and libats/ML (list0, Some0, a staload
# or include of it). Their _vt forms, result's option, a package's own
# nil and cons, a qualified name and the arrow =<fun> stay allowed.
# usage: tests/prelude-builders/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <body> [dependency]
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "pb%s"\nkind = "lib"\nunsafe = false\n' "$n" > "$d/bats.toml"
  if [ -n "${2:-}" ]; then printf '\n[dependencies]\n"%s" = ""\n' "$2" >> "$d/bats.toml"; fi
  printf '#include "share/atspre_staload.hats"\n%s\n' "$1" > "$d/src/lib.bats"
}
reject() { # <expected message part> <body>
  lib "$2"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
    echo "FAIL: accepted: $2"; exit 1
  fi
  grep -qF -- "$1" "$d/log" || { echo "FAIL: rejected, but not with '$1': $2"; grep error "$d/log" | head -3; exit 1; }
}
accept() { # <body> [dependency]
  lib "$1" "${2:-}"
  if [ -n "${2:-}" ]; then (cd "$d" && "$BATS" lock --repository "$REPO") > "$d/lock.log" 2>&1; fi
  (cd "$d" && "$BATS" check --repository "$REPO") > "$d/log" 2>&1 ||
    { echo "FAIL: rejected: $1"; grep -A3 error "$d/log" | head -8; exit 1; }
}
list="builds the prelude's non-linear list"
option="builds the prelude's non-linear option"
stream="builds the prelude's non-linear lazy stream"
reject "'list_cons' is not allowed outside \$UNSAFE; it $list" 'val xs = list_cons(1, list_vt2t(list_vt_nil{int}()))'
reject "'list_nil' is not allowed outside \$UNSAFE; it $list" 'val xs = list_nil{int}()'
reject "use list_vt" 'val xs = list_nil{int}()'
reject "'cons' is not allowed outside \$UNSAFE; it $list" 'fn one (x: int): List0(int) = cons(x, list_vt2t(list_vt_nil()))'
reject "'nil' is not allowed outside \$UNSAFE; it $list" 'fn none (): List0(int) = nil()'
reject "'::' is not allowed outside \$UNSAFE" 'fn one (x: int, xs: List0(int)): List0(int) = x :: xs'
reject "'list_append' is not allowed outside \$UNSAFE; it $list" 'fn both (xs: List0(int), ys: List0(int)): List0(int) = list_append(xs, ys)'
reject "'list_vt2t' is not allowed outside \$UNSAFE; it $list" 'fn kept (xs: List0_vt(int)): List0(int) = list_vt2t(xs)'
reject "'list_of_list_vt' is not allowed outside \$UNSAFE; it $list" 'fn kept (xs: List0_vt(int)): List0(int) = list_of_list_vt(xs)'
reject "'list_tuple_2' is not allowed outside \$UNSAFE; it $list" 'val xs = list_tuple_2<int>(1, 2)'
reject "'Some' is not allowed outside \$UNSAFE; it $option" 'val o = Some(1)'
reject "'None' is not allowed outside \$UNSAFE; it $option" 'val o = None{int}()'
reject "use option_vt" 'val o = Some(1)'
reject "'option_of_option_vt' is not allowed outside \$UNSAFE; it $option" 'fn kept (o: Option_vt(int)): Option(int) = option_of_option_vt(o)'
reject "'stream_make_nil' is not allowed outside \$UNSAFE; it $stream" 'val s = stream_make_nil<int>()'
reject "'stream_cons' is not allowed outside \$UNSAFE; it $stream" 'fn tail (s: stream(int)): stream_con(int) = stream_cons(1, s)'
reject "'\$delay' is not allowed outside \$UNSAFE" 'val s = $delay(stream_nil{int}())'
reject "'list0_cons' is not allowed outside \$UNSAFE; it $list" 'fn f (): void = let val _ = list0_cons in end'
reject "'Some0' is not allowed outside \$UNSAFE; it $option" 'fn f (): void = let val _ = Some0 in end'
reject "libats/ML is not allowed outside \$UNSAFE" 'staload "libats/ML/SATS/basis.sats"'
reject "libats/ML is not allowed outside \$UNSAFE" '#include "share/HATS/atspre_staload_libats_ML.hats"'
reject "'list_cons' is not allowed outside \$UNSAFE" '#pub fn rebuild (xs: List0(int)): List0(int)
implement rebuild (xs) = case+ xs of list_cons(x, rest) => list_cons(x, rest) | list_nil() => xs'
accept 'fn freed (): void = list_vt_free<int>(list_vt_cons(1, list_vt_nil()))
fn option_freed (): void = case+ Some_vt(1) of ~Some_vt(_) => () | ~None_vt() => ()
fn plain (f: (int) -<fun> int): int = f(1)
fn plain_one (): int = plain(lam (x: int): int =<fun> x + 1)
val nil_count = 0
val cons_list = 1
val None_seen = false
val Somebody = 2
datavtype stream_config = Piped | Inherited
fn config_freed (c: stream_config): void = case+ c of ~Piped() => () | ~Inherited() => ()
(* list_cons(1, nil()), Some(1), x :: xs, $delay(1), staload "libats/ML/SATS/basis.sats" *)
val s = "list_cons nil cons Some None :: $delay libats/ML"'
accept '#use result as R
fn freed (): void = case+ $R.some{int}(1) of ~$R.some(_) => () | ~$R.none() => ()
fn nothing (): void = case+ $R.none{int}() of ~$R.some(_) => () | ~$R.none() => ()' result
accept '(* A package that makes its own nil and cons (as the list package
   does, over list_vt) uses them, not the prelude macros *)
#pub fun {a:vt@ype} nil (): list_vt(a, 0)
#pub fun {a:vt@ype} cons {n:nat} (x: a, xs: list_vt(a, n)): list_vt(a, n + 1)
implement {a} nil () = list_vt_nil()
implement {a} cons (x, xs) = list_vt_cons(x, xs)
fn two (): void = list_vt_free<int>(cons<int>(1, cons<int>(2, nil<int>())))'
accept '(* A linear type of its own named cons, as the compiler has *)
datavtype cons(int) =
  | cons_end(0) of ()
  | {n:nat} cons_more(n + 1) of (int, cons(n))
fun cons_free {n:nat} .<n>. (cs: cons(n)): void =
  case+ cs of ~cons_end() => () | ~cons_more(_, rest) => cons_free(rest)'
echo "prelude-builders: ok"
