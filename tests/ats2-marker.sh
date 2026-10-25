# Sourced by a test that makes a toolchain of its own in a private HOME
# (bats-lang/bats#264): `. "$(dirname "$0")/../ats2-marker.sh"`. bats uses only
# a ~/.bats/ats2 that has the marker of the pin (src/ats2.bats), so
# `ats2_marker <home>` writes it into <home>/.bats/ats2, as bats ats2 install does.
ats2_marker() {
  ats2_marker_src=$(cd "$(dirname "$0")/../.." && pwd)/src/ats2.bats
  ats2_marker_name=$(sed -n 's/^#define ATS2_NAME "\(.*\)"$/\1/p' "$ats2_marker_src")
  ats2_marker_sha=$(sed -n 's/^#define ATS2_SHA256 "\(.*\)"$/\1/p' "$ats2_marker_src")
  mkdir -p "$1/.bats/ats2"
  printf '%s %s\n' "$ats2_marker_name" "$ats2_marker_sha" > "$1/.bats/ats2/.bats-ats2"
}
