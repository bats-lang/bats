#!/bin/sh
# CI is pinned (bats-lang/repository-prototype#269): every `uses:` of a
# workflow or an action is a local path (./...) or a repository at a full
# commit, 40 lowercase hex digits, followed by a comment that says which
# version it is (`# v4`), so a pin can be read and a relock can move it. A
# branch, a tag, a short SHA or a docker image by name is a pin that moves.
# usage: scripts/check-pins.sh [file...]   (default: .github/workflows/*.yml
#        and .github/actions/*/action.yml)
set -eu
defaults=no
if [ $# -eq 0 ]; then
  defaults=yes
  set -- .github/workflows/*.yml .github/actions/*/action.yml
fi
status=0
for file in "$@"; do
  [ -f "$file" ] || continue
  # every line with a `uses:` key (a step's `- uses:` too), the line number
  # first; a `uses:` in a comment or a block of text is not a key
  grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' "$file" | while IFS= read -r line; do
    number=${line%%:*}
    text=${line#*:}
    value=$(printf '%s\n' "$text" | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
    comment=$(printf '%s\n' "$text" | sed -nE 's/^[^#]*[[:space:]]#[[:space:]]*(.*)$/\1/p')
    case $value in
      ./*) continue ;;
    esac
    if ! printf '%s\n' "$value" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$'; then
      echo "$file:$number: uses '$value' is not pinned: name the repository at a full commit SHA (40 lowercase hex digits)"
      exit 1
    fi
    if [ -z "$comment" ]; then
      echo "$file:$number: uses '$value' has no comment saying which version the commit is (# v4)"
      exit 1
    fi
  done || status=1
done
# The ATS2 bats installs is pinned in src/ats2.bats alone (bats-lang/bats#283):
# a tarball of an https URL, checked by a SHA-256, and no workflow or action
# names a tarball or a digest of its own
if [ $defaults = yes ] && [ -f src/ats2.bats ]; then
  grep -qE '^#define ATS2_SHA256 "[0-9a-f]{64}"$' src/ats2.bats \
    || { echo "src/ats2.bats: ATS2_SHA256 is not a SHA-256 (64 lowercase hex digits)"; status=1; }
  grep -qE '^#define ATS2_URL "https://[^"]+\.tgz"$' src/ats2.bats \
    || { echo "src/ats2.bats: ATS2_URL is not an https tarball"; status=1; }
  if grep -nE 'ATS2-Postiats|[0-9a-f]{64}' "$@" /dev/null | grep -v 'uses:'; then
    echo "the ATS2 pin is in src/ats2.bats alone: a workflow or action names a tarball or a digest"; status=1
  fi
fi
exit $status
