#!/bin/bash
# bats check-pins <file>... (bats-lang/bats#390): the inputs of CI that move
# under a passing commit are refused, each as file:line: and status 1; no
# file is status 2. A workflow or action: a uses: not at a full commit with a
# version comment, a *-latest runner label, a node, java or python version
# that is not exact, npm install, an npx of a package with no exact version,
# pnpm install without --frozen-lockfile, a curl or wget with no checksum
# check in its step; a package.json: a dependency that is not exact, or
# dependencies and no lock; src/ats2.bats: the ATS2 pin. A `# unpinned:
# <reason>` on the line or above it is a written exception, which is listed.
# usage: tests/check-pins/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$TMP/out" >&2; exit 1; }
sha=11d5960a326750d5838078e36cf38b85af677262
digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
ok() { # <name> <text of the file>
  printf '%s\n' "$2" > "$TMP/$1.yml"
  "$BATS" check-pins "$TMP/$1.yml" > "$TMP/out" 2>&1 || fail "$1 was refused"
  [ ! -s "$TMP/out" ] || fail "$1 passed with output"
  echo "ok   $1"
}
bad() { # <name> <text of the file> <what the message says> <the line it names>
  printf '%s\n' "$2" > "$TMP/$1.yml"
  if "$BATS" check-pins "$TMP/$1.yml" > "$TMP/out" 2>&1; then fail "$1 passed"; fi
  grep -q -- "$3" "$TMP/out" || fail "$1 was refused for another reason"
  grep -q "$1.yml:$4: " "$TMP/out" || fail "$1 does not name line $4"
  echo "ok   $1 (refused)"
}
steps() { printf 'jobs:\n  j:\n    steps:\n%s' "$1"; }
run() { steps "      - run: $1"; }
block() { steps "      - name: x
        run: |
$1"; }

# uses:
ok pinned "$(steps "      - uses: actions/checkout@$sha # v4")"
ok pinned-subpath "$(steps "      - uses: bats-lang/bats/.github/actions/setup@$sha # setup")"
ok pinned-workflow "    uses: bats-lang/repository-prototype/.github/workflows/relock-pins.yml@$sha # main"
ok local "$(steps "      - uses: ./.github/actions/setup")"
ok local-no-dash "        uses: ./local"
ok quoted "$(steps "      - uses: \"actions/checkout@$sha\" # v4")"
ok single-quoted "$(steps "      - uses: 'actions/checkout@$sha' # v4")"
ok crlf "$(steps "      - uses: actions/checkout@$sha # v4"$'\r')"
ok comment-text "$(steps "      # uses: actions/checkout@v4")"
ok other-key "$(steps "      - name: uses: actions/checkout@v4")"
ok key-in-text "$(steps "      - run: echo uses: x")"
ok two-pinned "$(steps "      - uses: actions/checkout@$sha # v4
      - uses: actions/setup-node@$sha # v4")"
ok empty ""
bad tag "$(steps "      - uses: actions/checkout@v4")" "not pinned" 4
bad branch "$(steps "      - uses: actions/checkout@main # main")" "not pinned" 4
bad short "$(steps "      - uses: actions/checkout@11d5960 # v4")" "not pinned" 4
bad upper "$(steps "      - uses: actions/checkout@11D5960A326750D5838078E36CF38B85AF677262 # v4")" "not pinned" 4
bad long "$(steps "      - uses: actions/checkout@${sha}0 # v4")" "not pinned" 4
bad not-hex "$(steps "      - uses: actions/checkout@${sha%?}g # v4")" "not pinned" 4
bad no-ref "$(steps "      - uses: actions/checkout # v4")" "not pinned" 4
bad no-owner "$(steps "      - uses: checkout@$sha # v4")" "not pinned" 4
bad docker "$(steps "      - uses: docker://alpine:3 # x")" "not pinned" 4
bad empty-value "$(steps "      - uses: # v4")" "not pinned" 4
bad no-comment "$(steps "      - uses: actions/checkout@$sha")" "no comment" 4
bad empty-comment "$(steps "      - uses: actions/checkout@$sha #")" "no comment" 4
bad blank-comment "$(steps "      - uses: actions/checkout@$sha #   ")" "no comment" 4
bad hash-in-value "$(steps "      - uses: actions/checkout@$sha#v4")" "not pinned" 4
bad second "$(steps "      - uses: ./local
      - uses: actions/setup-node@v4")" "not pinned" 5
bad workflow-tag "    uses: bats-lang/repository-prototype/.github/workflows/relock-pins.yml@main" "not pinned" 1

# runs-on and matrix.os
ok image "  j:
    runs-on: ubuntu-24.04"
ok image-quoted "  j:
    runs-on: 'ubuntu-24.04'"
ok image-expression "  j:
    runs-on: \${{ matrix.os }}"
ok image-matrix "    strategy:
      matrix:
        os: [ubuntu-24.04, macos-14]"
ok latest-comment "    runs-on: ubuntu-24.04 # not ubuntu-latest"
ok latest-comment-line "    # runs-on: ubuntu-latest
    runs-on: ubuntu-24.04"
ok latest-name "    name: ubuntu-latest checks
    latest: yes"
ok latest-longer "    runs-on: ubuntu-latest-x"
bad runs-on-latest "  j:
    runs-on: ubuntu-latest" "-latest label" 2
bad runs-on-macos "    runs-on: macos-latest" "-latest label" 1
bad runs-on-windows "    runs-on: windows-latest" "-latest label" 1
bad runs-on-quoted "    runs-on: \"ubuntu-latest\"" "-latest label" 1
bad runs-on-flow "    runs-on: [self-hosted, ubuntu-latest]" "-latest label" 1
bad runs-on-list "    runs-on:
      - ubuntu-24.04
      - ubuntu-latest" "-latest label" 3
bad matrix-os "      matrix:
        os: [ubuntu-24.04, ubuntu-latest]" "-latest label" 2
bad matrix-include "        include:
          - os: ubuntu-latest" "-latest label" 2
bad matrix-os-list "        os:
          - macos-latest" "-latest label" 2

# node-version, java-version, python-version
ok node-exact "      - uses: actions/setup-node@$sha # v4
        with:
          node-version: 22.23.3"
ok node-quoted "          node-version: \"22.23.3\""
ok java-exact "          java-version: '21.0.12+8.0.LTS'"
ok python-exact "          python-version: 3.12.1"
ok prerelease "          node-version: 23.0.0-rc.1"
ok node-file "          node-version-file: .nvmrc"
ok java-file "          java-version-file: .java-version"
ok version-expression "          node-version: \${{ inputs.node-version }}"
ok version-comment "          node-version: 22.23.3 # not >=18"
ok version-text "      - name: node-version: 22"
ok input-default "    inputs:
      node-version:
        description: the version
        default: \"22.23.3\"
    other: x"
ok input-no-default "    inputs:
      node-version:
        description: the version
    other: x"
ok default-elsewhere "    inputs:
      node-version:
        description: the version
      other:
        default: 22"
bad node-major "          node-version: 22" "exact version" 1
bad node-major-quoted "          node-version: \"22\"" "exact version" 1
bad node-minor "          node-version: 22.23" "exact version" 1
bad node-x "          node-version: 22.x" "exact version" 1
bad node-x-patch "          node-version: 22.23.x" "exact version" 1
bad node-lts "          node-version: lts/*" "exact version" 1
bad node-latest "          node-version: latest" "exact version" 1
bad node-range "          node-version: '>=20'" "exact version" 1
bad node-caret "          node-version: ^22.0.0" "exact version" 1
bad node-list "          node-version: [18, 20]" "exact version" 1
bad node-empty-suffix "          node-version: 22.23.3+" "exact version" 1
bad node-v "          node-version: v22.23.3" "exact version" 1
bad java-major "          java-version: 21" "exact version" 1
bad python-minor "          python-version: '3.12'" "exact version" 1
bad input-default-major "    inputs:
      node-version:
        description: the version
        default: \"22\"" "exact version" 4

# npm install, npx, pnpm install
ok npm-ci "$(run "npm ci")"
ok npm-ci-block "$(block "          npm ci")"
ok npm-echo "$(run "echo \"npm install\"")"
ok npm-comment "$(block "          # npm install")"
ok npm-name "      - name: npm install the packages"
ok npm-word "$(run "echo npm install")"
ok pnpm-frozen "$(run "pnpm install --frozen-lockfile")"
ok pnpm-frozen-flags "$(run "pnpm install --silent --frozen-lockfile")"
ok npx-exact "$(run "npx playwright@1.58.2 install")"
ok npx-scoped "$(run "npx --yes @scope/pkg@1.2.3 run")"
ok npx-word "$(run "echo npx playwright")"
ok npx-alone "$(run "npx")"
bad npm-install "$(run "npm install")" "use npm ci" 4
bad npm-i "$(run "npm i")" "use npm ci" 4
bad npm-install-package "$(run "npm install left-pad")" "use npm ci" 4
bad npm-install-block "$(block "          npm install")" "use npm ci" 6
bad npm-after-and "$(run "cd app && npm install")" "use npm ci" 4
bad npm-after-sudo "$(run "sudo npm install -g x")" "use npm ci" 4
bad npm-in-subshell "$(run "(npm install)")" "use npm ci" 4
bad npm-after-semicolon "$(run "cd app; npm install")" "use npm ci" 4
bad pnpm-install "$(run "pnpm install")" "frozen-lockfile" 4
bad pnpm-i "$(run "pnpm i")" "frozen-lockfile" 4
bad pnpm-block "$(block "          pnpm install --silent")" "frozen-lockfile" 6
bad npx-unpinned "$(run "npx playwright install")" "package@1.2.3" 4
bad npx-flag "$(run "npx -y serve")" "package@1.2.3" 4
bad npx-scoped-unpinned "$(run "npx @scope/pkg run")" "package@1.2.3" 4
bad npx-tag "$(run "npx serve@latest")" "package@1.2.3" 4
bad npx-range "$(run "npx serve@^14.0.0")" "package@1.2.3" 4

# curl and wget
ok apt "$(run "sudo apt-get install -y -q libgmp-dev lld")"
ok curl-checked "$(block "          curl -fsSLo tool.tgz https://example.com/tool.tgz
          echo \"$digest  tool.tgz\" | sha256sum -c")"
ok curl-checked-first "$(block "          sha256sum --version
          curl -fsSLo tool.tgz https://example.com/tool.tgz")"
ok wget-checked "$(block "          wget https://example.com/tool.tgz
          shasum -a 256 -c tool.sum")"
ok curl-one-line "$(run "curl -fsSLo t https://example.com/t && sha256sum -c t.sum")"
ok curl-word "$(run "echo curl is used")"
bad curl-unchecked "$(block "          curl -fsSLo tool.tgz https://example.com/tool.tgz")" "checksum" 6
bad wget-unchecked "$(block "          wget https://example.com/tool.tgz")" "checksum" 6
bad curl-pipe-shell "$(run "curl -fsSL https://example.com/install.sh | sh")" "checksum" 4
bad curl-other-step "$(steps "      - name: first
        run: |
          sha256sum -c a.sum
      - name: second
        run: |
          curl -fsSLo t https://example.com/t")" "checksum" 9
bad curl-after-step "$(steps "      - name: first
        run: |
          curl -fsSLo t https://example.com/t
      - name: second
        run: |
          sha256sum -c a.sum")" "checksum" 6

# exceptions
exception() { # <name> <text> <line> <reason>: accepted, listed, status 0
  printf '%s\n' "$2" > "$TMP/$1.yml"
  "$BATS" check-pins "$TMP/$1.yml" > "$TMP/out" 2> "$TMP/err" || { cat "$TMP/err" >&2; fail "$1 was refused"; }
  [ ! -s "$TMP/err" ] || { cat "$TMP/err" >&2; fail "$1 passed with errors"; }
  grep -q "$1.yml:$3: unpinned: $4\$" "$TMP/out" || fail "$1 does not list its exception"
  echo "ok   $1 (accepted, listed)"
}
exception exception-inline "$(run "npm install # unpinned: the lock is made here")" 4 "the lock is made here"
exception exception-above-run "$(steps "      # unpinned: the newest emulator
      - run: npm install")" 4 "the newest emulator"
exception exception-comment-between "$(steps "      # unpinned: the newest emulator
      # more about why
      - run: npm install")" 4 "the newest emulator"
exception exception-uses "$(steps "      # unpinned: pinned by the caller
      - uses: actions/checkout@v4")" 4 "pinned by the caller"
exception exception-uses-inline "$(steps "      - uses: actions/checkout@v4 # unpinned: a tag on purpose")" 4 "a tag on purpose"
exception exception-block "$(block "          # unpinned: the tool has no checksum
          curl -fsSLo t https://example.com/t")" 6 "the tool has no checksum"
bad exception-unused "$(run "npm ci # unpinned: nothing to exempt")" "exempts nothing" 4
bad exception-unused-above "$(steps "      # unpinned: nothing to exempt
      - run: npm ci")" "exempts nothing" 4
bad exception-unused-blank "$(steps "      # unpinned: nothing to exempt

      - run: npm install")" "exempts nothing" 4
bad exception-unused-last "$(steps "      # unpinned: nothing to exempt")" "exempts nothing" 4
bad exception-two-lines-above "$(steps "      # unpinned: only the next line
      - name: x
        run: npm install")" "use npm ci" 6
bad exception-no-reason "$(run "npm install # unpinned:")" "needs a reason" 4
bad exception-blank-reason "$(steps "      # unpinned:   
      - run: npm install")" "needs a reason" 4
bad exception-other-comment "$(run "npm install # because")" "use npm ci" 4
bad exception-spelled "$(run "npm install # unpinned reason")" "use npm ci" 4
printf '%s\n' "$(steps "      - run: npm install # unpinned: a
      - run: npm install # unpinned: b")" > "$TMP/two-exceptions.yml"
"$BATS" check-pins "$TMP/two-exceptions.yml" > "$TMP/out" 2>&1 || fail "two exceptions were refused"
grep -q "two-exceptions.yml:4: unpinned: a" "$TMP/out" || fail "the first exception is not listed"
grep -q "two-exceptions.yml:5: unpinned: b" "$TMP/out" || fail "the second exception is not listed"

# package.json
package() { # <name> <text of package.json> [lock file name]
  mkdir -p "$TMP/$1"
  printf '%s\n' "$2" > "$TMP/$1/package.json"
  if [ $# -ge 3 ]; then : > "$TMP/$1/$3"; fi
}
ok_package() { # <name> <text> [lock]
  package "$@"
  "$BATS" check-pins "$TMP/$1/package.json" > "$TMP/out" 2>&1 || fail "$1 was refused"
  [ ! -s "$TMP/out" ] || fail "$1 passed with output"
  echo "ok   $1"
}
bad_package() { # <name> <text> <lock or -> <what the message says> <line>
  package "$1" "$2"
  if [ "$3" != - ]; then : > "$TMP/$1/$3"; fi
  if "$BATS" check-pins "$TMP/$1/package.json" > "$TMP/out" 2>&1; then fail "$1 passed"; fi
  grep -q -- "$4" "$TMP/out" || fail "$1 was refused for another reason"
  grep -q "$1/package.json:$5: " "$TMP/out" || fail "$1 does not name line $5"
  echo "ok   $1 (refused)"
}
exact='{
  "name": "x",
  "devDependencies": {
    "jsdom": "24.1.3",
    "fake-indexeddb": "6.2.5"
  }
}'
ok_package pkg-exact "$exact" package-lock.json
ok_package pkg-pnpm-lock "$exact" pnpm-lock.yaml
ok_package pkg-yarn-lock "$exact" yarn.lock
ok_package pkg-no-dependencies '{
  "name": "x",
  "scripts": { "test": "vitest" }
}'
ok_package pkg-empty-section '{
  "devDependencies": {}
}'
ok_package pkg-prerelease '{
  "dependencies": {
    "a": "1.0.0-rc.1",
    "b": "2.0.0+build.5",
    "@scope/c": "3.4.5"
  }
}' package-lock.json
ok_package pkg-git-commit '{
  "dependencies": {
    "a": "github:owner/repo#0123456789abcdef0123456789abcdef01234567"
  }
}' package-lock.json
ok_package pkg-workspace '{
  "devDependencies": {
    "a": "workspace:*",
    "b": "workspace:^1.0.0"
  }
}' package-lock.json
ok_package pkg-peer-range '{
  "peerDependencies": {
    "@capacitor/core": ">=8"
  },
  "devDependencies": {
    "a": "1.0.0"
  }
}' package-lock.json
ok_package pkg-range-in-text '{
  "description": "needs ^1.0.0",
  "dependencies": {
    "a": "1.0.0"
  },
  "scripts": {
    "x": "npm install a@^1"
  }
}' package-lock.json
bad_package pkg-workspace-prefix '{
  "dependencies": {
    "a": "workspaces:*"
  }
}' package-lock.json "is not at an exact version" 3
bad_package pkg-caret '{
  "devDependencies": {
    "a": "^1.0.0"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-tilde '{
  "dependencies": {
    "a": "1.0.0",
    "b": "~1.2.3"
  }
}' package-lock.json "not at an exact version" 4
bad_package pkg-star '{
  "dependencies": {
    "a": "*"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-latest '{
  "dependencies": {
    "a": "latest"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-tag '{
  "optionalDependencies": {
    "a": "next"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-greater '{
  "dependencies": {
    "a": ">=1.0.0"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-or '{
  "dependencies": {
    "a": "1.0.0 || 2.0.0"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-minor '{
  "dependencies": {
    "a": "1.2"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-x-range '{
  "dependencies": {
    "a": "1.x"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-git-branch '{
  "dependencies": {
    "a": "github:owner/repo#main"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-git-short '{
  "dependencies": {
    "a": "github:owner/repo#0123456"
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-number '{
  "dependencies": {
    "a": 1
  }
}' package-lock.json "not at an exact version" 3
bad_package pkg-no-lock "$exact" - "no committed lock" 1
bad_package pkg-one-line '{
  "dependencies": { "a": "^1.0.0" }
}' package-lock.json "one to a line" 2
bad_package pkg-not-a-pair '{
  "dependencies": {
    a
  }
}' package-lock.json "one to a line" 3
mkdir -p "$TMP/pkg-two-sections"
printf '{\n  "dependencies": {\n    "a": "1.0.0"\n  },\n  "devDependencies": {\n    "b": "^2.0.0"\n  }\n}\n' > "$TMP/pkg-two-sections/package.json"
: > "$TMP/pkg-two-sections/package-lock.json"
"$BATS" check-pins "$TMP/pkg-two-sections/package.json" > "$TMP/out" 2>&1 && fail "pkg-two-sections passed"
grep -q "package.json:6: dependency \"b\": \"^2.0.0\"" "$TMP/out" || fail "the second section's dependency is not named"
echo "ok   pkg-two-sections (refused)"

# src/ats2.bats: the ATS2 pin, and no workflow naming it
mkdir -p "$TMP/ats2-ok/src" "$TMP/ats2-no-digest/src" "$TMP/ats2-bad-digest/src" "$TMP/ats2-http/src" "$TMP/ats2-no-tgz/src" "$TMP/ats2-empty/src"
printf '(* x *)\n#define ATS2_SHA256 "%s"\n#define ATS2_URL "https://example.com/ATS2-Postiats-gmp-0.4.2.tgz"\n' "$digest" > "$TMP/ats2-ok/src/ats2.bats"
printf '#define ATS2_URL "https://example.com/a.tgz"\n' > "$TMP/ats2-no-digest/src/ats2.bats"
printf '#define ATS2_SHA256 "%s0"\n#define ATS2_URL "https://example.com/a.tgz"\n' "$digest" > "$TMP/ats2-bad-digest/src/ats2.bats"
printf '#define ATS2_SHA256 "%s"\n#define ATS2_URL "http://example.com/a.tgz"\n' "$digest" > "$TMP/ats2-http/src/ats2.bats"
printf '#define ATS2_SHA256 "%s"\n#define ATS2_URL "https://example.com/a.zip"\n' "$digest" > "$TMP/ats2-no-tgz/src/ats2.bats"
: > "$TMP/ats2-empty/src/ats2.bats"
"$BATS" check-pins "$TMP/ats2-ok/src/ats2.bats" > "$TMP/out" 2>&1 || fail "a good ats2.bats was refused"
echo "ok   ats2-ok"
for name in no-digest:ATS2_SHA256 bad-digest:ATS2_SHA256 http:ATS2_URL no-tgz:ATS2_URL empty:ATS2_SHA256; do
  "$BATS" check-pins "$TMP/ats2-${name%%:*}/src/ats2.bats" > "$TMP/out" 2>&1 && fail "ats2-${name%%:*} passed"
  grep -q "${name##*:}" "$TMP/out" || fail "ats2-${name%%:*} was refused for another reason"
  echo "ok   ats2-${name%%:*} (refused)"
done
"$BATS" check-pins "$TMP/ats2-empty/src/ats2.bats" > "$TMP/out" 2>&1; grep -q ATS2_URL "$TMP/out" || fail "an empty ats2.bats does not miss the URL"
printf '%s\n' "$(steps "      - uses: actions/checkout@$sha # v4
      - run: echo $digest")" > "$TMP/names-digest.yml"
"$BATS" check-pins "$TMP/names-digest.yml" > "$TMP/out" 2>&1 || fail "a digest was refused when no ats2.bats was named"
"$BATS" check-pins "$TMP/names-digest.yml" "$TMP/ats2-ok/src/ats2.bats" > "$TMP/out" 2>&1 && fail "a digest in a workflow passed beside ats2.bats"
grep -q "names-digest.yml:5: .*alone" "$TMP/out" || fail "the digest is not named"
printf '%s\n' "$(steps "      - run: echo https://example.com/ATS2-Postiats-gmp-0.4.2.tgz")" > "$TMP/names-tarball.yml"
"$BATS" check-pins "$TMP/names-tarball.yml" "$TMP/ats2-ok/src/ats2.bats" > "$TMP/out" 2>&1 && fail "a tarball in a workflow passed beside ats2.bats"
printf '%s\n' "$(steps "      - uses: actions/checkout@$sha # v4")" > "$TMP/names-only-uses.yml"
"$BATS" check-pins "$TMP/names-only-uses.yml" "$TMP/ats2-ok/src/ats2.bats" > "$TMP/out" 2>&1 || fail "a pinned uses was refused beside ats2.bats"
echo "ok   ats2 in workflows"

# the message names the value, and every refused line is named
printf '%s\n' "$(steps "      - uses: a/b@v1
      - uses: c/d@v2 # x")" > "$TMP/two.yml"
"$BATS" check-pins "$TMP/two.yml" > "$TMP/out" 2>&1 && fail "two refused lines passed"
grep -q "two.yml:4: uses 'a/b@v1' is not pinned" "$TMP/out" || fail "the first value is not named"
grep -q "two.yml:5: uses 'c/d@v2' is not pinned" "$TMP/out" || fail "the second line is not named"
printf '%s\n' "$(run "npm install")" > "$TMP/named.yml"
"$BATS" check-pins "$TMP/named.yml" > "$TMP/out" 2>&1 && fail "npm install passed"
grep -q "named.yml:4: npm install installs" "$TMP/out" || fail "the command is not named"

# several files: the status is the worst, and a clean file after a refused one is still read
ok clean "$(steps "      - uses: actions/checkout@$sha # v4")"
"$BATS" check-pins "$TMP/tag.yml" "$TMP/clean.yml" > "$TMP/out" 2>&1; [ $? -eq 1 ] || fail "a refused file then a clean one is not 1"
"$BATS" check-pins "$TMP/clean.yml" "$TMP/clean.yml" > "$TMP/out" 2>&1 || fail "two clean files were refused"

# usage and unreadable files are 2
"$BATS" check-pins > "$TMP/out" 2>&1; [ $? -eq 2 ] || fail "no file is not 2"
grep -q "usage: bats check-pins <file>... | --discover" "$TMP/out" || fail "no file does not say the usage"
"$BATS" check-pins "$TMP/absent.yml" > "$TMP/out" 2>&1; [ $? -eq 2 ] || fail "an absent file is not 2"
grep -q "cannot read .*absent.yml" "$TMP/out" || fail "an absent file is not named"
"$BATS" check-pins "$TMP/absent.yml" "$TMP/tag.yml" > "$TMP/out" 2>&1; [ $? -eq 2 ] || fail "an absent file then a refused one is not 2"
grep -q "tag.yml:4: " "$TMP/out" || fail "the file after an absent one was not read"

# a file of many lines takes no time, and the last line without a newline is read
for i in $(seq 1 20000); do echo "      - run: echo $i"; done > "$TMP/long.yml"
printf '      - uses: a/b@v1' >> "$TMP/long.yml"
"$BATS" check-pins "$TMP/long.yml" > "$TMP/out" 2>&1; [ $? -eq 1 ] || fail "the last line without a newline was not read"
grep -q "long.yml:20001: " "$TMP/out" || fail "the long file's line is not numbered"
for i in $(seq 1 3000); do echo "      - run: echo curl $i"; done > "$TMP/long-steps.yml"
printf '      - run: curl x\n' >> "$TMP/long-steps.yml"
"$BATS" check-pins "$TMP/long-steps.yml" > "$TMP/out" 2>&1; [ $? -eq 1 ] || fail "a curl after many steps was not refused"

# --discover: the files git lists of the repository of the current directory
# (tracked, or untracked and not ignored), the one argument
G="$TMP/repo"
mkdir -p "$G/.github/workflows" "$G/.github/actions/x" "$G/build" "$G/sub"
(cd "$G" && git init -q . && git config user.email t@t && git config user.name t)
printf '%s\n' "$(steps "      - uses: actions/checkout@$sha # v4")" > "$G/.github/workflows/check.yml"
printf '%s\n' "$(steps "      - uses: ./local")" > "$G/.github/actions/x/action.yml"
printf '{\n  "name": "x"\n}\n' > "$G/sub/package.json"
printf '%s\n' "$(steps "      - uses: a/b@v1")" > "$G/build/ignored.yml"
printf 'build/\n' > "$G/.gitignore"
(cd "$G" && git add -A && git commit -q -m x)
discover() { (cd "$G" && "$BATS" check-pins --discover) > "$TMP/out" 2>&1; }
discover || fail "a clean repository was refused by --discover"
[ ! -s "$TMP/out" ] || fail "a clean repository passed --discover with output"
echo "ok   discover (clean)"
printf '%s\n' "$(steps "      - uses: actions/checkout@v4")" > "$G/.github/workflows/planted.yml"
discover; [ $? -eq 1 ] || fail "an untracked floating workflow passed --discover"
grep -q "^.github/workflows/planted.yml:4: uses 'actions/checkout@v4' is not pinned" "$TMP/out" || fail "the planted workflow is not named"
echo "ok   discover (untracked file refused)"
printf '.github/workflows/planted.yml\n' >> "$G/.gitignore"
discover || fail "an ignored workflow was read by --discover"
rm -f "$G/.github/workflows/planted.yml"
printf '%s\n' "$(steps "      - uses: a/b@v1")" > "$G/.github/actions/x/action.yaml"
discover; [ $? -eq 1 ] || fail "a floating action.yaml passed --discover"
grep -q "^.github/actions/x/action.yaml:4: " "$TMP/out" || fail "the action.yaml is not named"
rm -f "$G/.github/actions/x/action.yaml"
printf '{\n  "dependencies": {\n    "left-pad": "^1.0.0"\n  }\n}\n' > "$G/sub/package.json"
discover; [ $? -eq 1 ] || fail "a package.json with a range passed --discover"
grep -q "^sub/package.json:3: " "$TMP/out" || fail "the package.json is not named"
printf '{\n  "name": "x"\n}\n' > "$G/sub/package.json"
printf '#define ATS2_SHA256 "%s"\n' "$digest" > "$G/ats2.bats"
discover; [ $? -eq 1 ] || fail "an ats2.bats with no URL passed --discover"
grep -q "^ats2.bats:" "$TMP/out" || fail "the ats2.bats is not named"
rm -f "$G/ats2.bats"
echo "ok   discover (untracked, ignored, action.yaml, package.json, ats2.bats)"
# nothing to check, not a repository, a list too long: 2, never a pass
rm -f "$G/.github/workflows/check.yml" "$G/.github/actions/x/action.yml" "$G/sub/package.json"
(cd "$G" && git add -A) && discover; [ $? -eq 2 ] || fail "a repository with no pin file is not 2"
grep -q "has no workflow" "$TMP/out" || fail "an empty list does not say so"
mkdir "$TMP/not-a-repo"
(cd "$TMP/not-a-repo" && GIT_CEILING_DIRECTORIES="$TMP" "$BATS" check-pins --discover) > "$TMP/out" 2>&1; [ $? -eq 2 ] || fail "outside a repository is not 2"
grep -q "git repository" "$TMP/out" || fail "outside a repository does not say so"
for i in $(seq 1 200); do
  d="$G/directory-with-a-long-name-$i"; mkdir -p "$d"; printf '{\n  "name": "x"\n}\n' > "$d/package.json"
done
discover; [ $? -eq 2 ] || fail "a list over 4095 bytes is not 2"
grep -q "4095 bytes" "$TMP/out" || fail "a long list does not say so"
rm -rf "$G"/directory-with-a-long-name-*
echo "ok   discover (no file, no repository, too long)"
# a list git writes in pieces is read to its end (the floating file named in the second
# piece is checked), and a list too long for the buffer, whose writer ends on SIGPIPE
# when the pipe is closed unread, is the "too long" 2 and not a failure of git (git is a
# stub on the path)
mkdir -p "$TMP/stub"
printf '%s\n' "$(steps "      - uses: a/b@v1")" > "$G/late.yml"
printf '%s\n' "$(steps "      - uses: ./local")" > "$G/early.yml"
printf '#!/bin/sh\nprintf "early.yml\\0"\nsleep 1\nprintf "late.yml\\0"\n' > "$TMP/stub/git"
chmod +x "$TMP/stub/git"
(cd "$G" && PATH="$TMP/stub:$PATH" "$BATS" check-pins --discover) > "$TMP/out" 2>&1; [ $? -eq 1 ] || fail "a list written in two pieces was cut after the first"
grep -q "^late.yml:4: " "$TMP/out" || fail "the file of the second piece is not named"
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 8 ]; do head -c 600 /dev/zero | tr "\\0" "a"; printf "\\0"; sleep 0.2; i=$((i+1)); done\n' > "$TMP/stub/git"
(cd "$G" && PATH="$TMP/stub:$PATH" "$BATS" check-pins --discover) > "$TMP/out" 2>&1; [ $? -eq 2 ] || fail "a long list written in pieces is not 2"
grep -q "4095 bytes" "$TMP/out" || fail "a long list written in pieces does not say so"
rm -f "$G/late.yml" "$G/early.yml"
echo "ok   discover (a list written in pieces)"
# --discover beside a file, or twice, is a file name and unreadable: 2
"$BATS" check-pins --discover "$TMP/clean.yml" > "$TMP/out" 2>&1; [ $? -eq 2 ] || fail "--discover beside a file is not 2"
grep -q "cannot read --discover" "$TMP/out" || fail "--discover beside a file is not named"
echo "ok   discover (with a file)"

# this repository's own workflows and actions are clean
(cd "$(dirname "$0")/../.." && "$BATS" check-pins .github/workflows/*.yml .github/actions/*/action.yml src/ats2.bats > "$TMP/out" 2>&1) || fail "this repository's workflows are refused"
(cd "$(dirname "$0")/../.." && "$BATS" check-pins --discover > "$TMP/out" 2>&1) || fail "this repository is refused by --discover"
echo "check-pins: all passed"
