---
paths:
  - src/helpers.bats
  - src/pins.bats
  - src/facts.bats
  - src/stamp.bats
  - src/setup.bats
  - src/ats2.bats
  - src/cache.bats
  - src/fixtures.bats
  - src/commands.bats
  - tests/capture-outcome/**
---

# Captured runs (capture)

`run_cmd_capture_outcome` (`src/helpers.bats`, bats#444) runs a child and keeps the first 4096 bytes of its stdout. The result is a linear `capture_outcome`, so a caller matches every constructor. No constructor holds a status of -1 (bats#448).

Why: bats#440 read git's file list with one 4096-byte read, closed the pipe while git was still writing, git died of SIGPIPE, and the exit status was reported as "git failed" whenever git lost the race. The new form reads stdout to its end (a read is repeated until 0 bytes, since a pipe gives what is there, not what the child will write), so bats never closes under a writer. The count is exact for any stream: it is mebibytes (at most 67108863) and a remainder under 1048576, and its lexicographic growth is the loop's termination metric, so there is no fuel; a stream of 64 TiB or more ends as `CaptureReadFailed` with `FileTooLarge` (a platform assumption, not a proof, that none is longer). The bytes are drained, only the first 4096 kept, so the child never gets SIGPIPE. Stderr goes to /dev/null: the old form read one chunk of it after stdout, which can block a child that writes more than a pipe holds.

Research (bats#444 comment): Rust `Command::output` and Python `capture_output` read everything and have no limit case; Go keeps a prefix and suffix of a long stderr and says so in the text; Node `execFile` `maxBuffer` makes it an error but terminates the child; `popen` leaves it to the caller. This form drains like Rust and makes the limit a constructor like Node, without killing the child.

The old `run_cmd_capture` stays one version beside the new form (repository-prototype#381; removal: bats#461).
