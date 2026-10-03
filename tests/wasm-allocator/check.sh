#!/bin/sh
# The wasm runtime's allocator (src/allocator.bats, bats-lang/bats#241),
# run: a block freed is reused by the next request its list serves, it
# comes back zeroed, a request over 1 MiB (a region, an arena's) reuses
# only a freed region of its very size in whole pages,
# allocating and freeing over and over does not grow the memory, free of
# null does nothing, and memmove copies overlapping ranges either way.
# usage: tests/wasm-allocator/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
d=$TMP/p; mkdir -p "$d/src"
printf '[package]\nname = "wa"\nkind = "lib"\nunsafe = true\n' > "$d/bats.toml"
cat > "$d/src/lib.bats" <<'B'
#include "share/atspre_staload.hats"

#target wasm begin

#define MiB 1048576

$UNSAFE begin
%{^
#ifdef __wasm__
static int wa_pages(void) { return (int)__builtin_wasm_memory_size(0); }
#else
static int wa_pages(void) { return 0; }
#endif
static void wa_fill(void *p, int n, int v) { unsigned char *q = p; while (n--) *q++ = (unsigned char)v; }
static int wa_is_zero(void *p, int n) { unsigned char *q = p; while (n--) if (*q++) return 0; return 1; }
static int wa_same(void *p, void *q) { return p == q; }
static int wa_byte(void *p, int i) { return ((unsigned char*)p)[i]; }
static void wa_count(void *p, int n) { unsigned char *q = p; int i; for (i = 0; i < n; i++) q[i] = (unsigned char)i; }
%}
extern fun malloc (n: int): ptr = "mac#malloc"
extern fun free (p: ptr): void = "mac#free"
extern fun memmove (d: ptr, s: ptr, n: int): ptr = "mac#memmove"
extern fun pages (): int = "mac#wa_pages"
extern fun fill (p: ptr, n: int, v: int): void = "mac#wa_fill"
extern fun is_zero (p: ptr, n: int): bool = "mac#wa_is_zero"
extern fun same (p: ptr, q: ptr): bool = "mac#wa_same"
extern fun byte_at (p: ptr, i: int): int = "mac#wa_byte"
extern fun count (p: ptr, n: int): void = "mac#wa_count"
extern fun offset (p: ptr, i: int): ptr = "mac#atspre_add_ptr1_bsz"
end

$UNITTEST.run(wasm) begin
fn test_bucket_reuse (): bool = let
  val p = malloc(20)
  val () = free(p)
  val q = malloc(30)
  val () = free(q)
in same(p, q) end

fn test_bucket_last_in_first_out (): bool = let
  val p1 = malloc(100)
  val p2 = malloc(100)
  val () = free(p1)
  val () = free(p2)
  val q2 = malloc(100)
  val q1 = malloc(100)
  val () = free(q1)
  val () = free(q2)
in ~same(p1, p2) && same(q2, p2) && same(q1, p1) end

fn test_zeroed (): bool = let
  val p = malloc(5000)
  val () = fill(p, 5000, 255)
  val () = free(p)
  val q = malloc(5000)
  val z = is_zero(q, 8192)
  val () = free(q)
  val b = malloc(2 * MiB)
  val () = fill(b, 2 * MiB, 7)
  val () = free(b)
  val c = malloc(2 * MiB)
  val zc = is_zero(c, 2 * MiB)
  val () = free(c)
in same(p, q) && z && same(b, c) && zc end

fn test_region_per_size (): bool = let
  val a = malloc(3 * MiB)
  val b = malloc(4 * MiB)
  val c = malloc(5 * MiB)
  val () = free(c)
  val () = free(a)
  val () = free(b)
  val b2 = malloc(4 * MiB)
  val a2 = malloc(3 * MiB)
  val c2 = malloc(5 * MiB)
  val () = free(a2)
  val () = free(b2)
  val () = free(c2)
in same(a2, a) && same(b2, b) && same(c2, c) end

fn test_region_exact (): bool = let
  val a = malloc(40 * MiB)
  val () = free(a)
  val smaller = malloc(25 * MiB)
  val same_pages = malloc(40 * MiB - 1000)
  val () = free(smaller)
  val () = free(same_pages)
in ~same(smaller, a) && same(same_pages, a) end

fn test_steady (): bool = let
  fun rounds {i:nat} .<i>. (i: int i, first: ptr): bool =
    if i = 0 then true
    else let
      val p = malloc(6 * MiB + 1000)
      val q = malloc(300)
      val r = malloc(2 * MiB + 8)
      val () = free(q)
      val () = free(p)
      val () = free(r)
    in if same(p, first) then rounds(i - 1, first) else false end
  val p0 = malloc(6 * MiB + 1000)
  val r0 = malloc(2 * MiB + 8)
  val () = free(p0)
  val () = free(r0)
  val before = pages()
  val same = rounds(500, p0)
in same && pages() = before end

fn test_free_null (): bool = let
  val () = free(the_null_ptr)
  val p = malloc(64)
  val () = free(p)
in true end

fn test_memmove_overlap (): bool = let
  val p = malloc(64)
  val () = count(p, 64)
  val _ = memmove(offset(p, 8), p, 32)
  val up = byte_at(p, 8) = 0 && byte_at(p, 39) = 31 && byte_at(p, 7) = 7
  val () = count(p, 64)
  val _ = memmove(p, offset(p, 8), 32)
  val down = byte_at(p, 0) = 8 && byte_at(p, 31) = 39 && byte_at(p, 32) = 32
  val () = free(p)
in up && down end
end

end
B
(cd "$d" && "$BATS" test --only wasm) > "$d/out" 2>&1 || { echo "FAIL: bats test"; cat "$d/out"; exit 1; }
grep -qF "8 passed, 0 failed" "$d/out" || { echo "FAIL: not every allocator test passed"; cat "$d/out"; exit 1; }
echo "wasm-allocator: ok"
