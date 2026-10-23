# Sourced by a test script in place of its own temp directory and trap
# (bats-lang/bats#478, keep-on-fail): `. "$(dirname "$0")/../keep-on-fail.sh"`.
# It sets TMP to a new absolute directory `bats-tmp.XXXXXX` under
# ${BATS_KEPT_DIR:-${TMPDIR:-/tmp}}; the name carries no word of the test's.
# The script exiting 0 removes it; exiting non-zero keeps it and ends stderr with
# `kept: <TMP> (<test>)`, so a failure leaves its files to read, says which test
# they are from, and CI can upload them.
# A script with its own teardown (an unmount) names a function in
# KEEP_ON_FAIL_TEARDOWN before sourcing; it runs first, on every exit.
# Detail: .claude/rules/keep-on-fail.md.

keep_on_fail_base=${BATS_KEPT_DIR:-${TMPDIR:-/tmp}}
mkdir -p "$keep_on_fail_base"
keep_on_fail_base=$(cd "$keep_on_fail_base" && pwd)
keep_on_fail_name=$(basename "$(dirname "$0")")
# keep-on-fail: the name is neutral, a test that matches words of bats's output meets the path
TMP=$(mktemp -d "$keep_on_fail_base/bats-tmp.XXXXXX")

keep_on_fail_exit() {
  keep_on_fail_status=$?
  if [ -n "${KEEP_ON_FAIL_TEARDOWN:-}" ]; then
    "$KEEP_ON_FAIL_TEARDOWN" || true
  fi
  if [ "$keep_on_fail_status" -eq 0 ]; then
    rm -rf "$TMP" || true
  else
    printf 'kept: %s (%s)\n' "$TMP" "$keep_on_fail_name" >&2
  fi
  exit "$keep_on_fail_status"
}
trap keep_on_fail_exit EXIT
