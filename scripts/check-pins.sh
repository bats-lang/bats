#!/bin/sh
# CI is pinned (bats-lang/repository-prototype#269): every `uses:` of a
# workflow or an action is a local path (./...) or a repository at a full
# commit, 40 lowercase hex digits, followed by a comment that says which
# version it is (`# v4`), so a pin can be read and a relock can move it. A
# branch, a tag, a short SHA or a docker image by name is a pin that moves.
# usage: scripts/check-pins.sh [file...]   (default: .github/workflows/*.yml
#        and .github/actions/*/action.yml)
set -eu
if [ $# -eq 0 ]; then
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
exit $status
