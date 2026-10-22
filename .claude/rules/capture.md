---
paths:
  - src/helpers.bats
  - tests/capture-outcome/**
---

# Captured runs (capture)

`run_cmd_capture_outcome` (`src/helpers.bats`, bats#444) runs a child and keeps the first 4096 bytes of its stdout. The result is a linear `capture_outcome`, so a caller matches every constructor: `CaptureFits(len)` (exit 0), `CaptureFailed(status, len)` (non-zero exit, output fits), `CaptureLonger(status, written)` (more than the buffer: the child's own status beside the bytes it wrote, so a status is never the cause of a truncation), `CaptureReadFailed(status, len, io_error)` (a read failed; the old form took it for the end of the output) and `CaptureNotRun(errno)`.

Why: bats#440 read git's file list with one 4096-byte read, closed the pipe while git was still writing, git died of SIGPIPE, and the exit status was reported as "git failed" whenever git lost the race. The new form reads stdout to its end (a read is repeated until 0 bytes, since a pipe gives what is there, not what the child will write), so bats never closes under a writer. It stops at 1 GiB (the loop's termination metric); past that `written` is a floor and the child may get SIGPIPE. Stderr goes to /dev/null: the old form read one chunk of it after stdout, which can block a child that writes more than a pipe holds.

Research (bats#444 comment): Rust `Command::output` and Python `capture_output` read everything and have no limit case; Go keeps a prefix and suffix of a long stderr and says so in the text; Node `execFile` `maxBuffer` makes it an error but terminates the child; `popen` leaves it to the caller. This form drains like Rust and makes the limit a constructor like Node, without killing the child.

`tests/capture-outcome/check.sh` builds a copy of the project with `driver.bats` as a second binary and plays real `sh` children (output in pieces with pauses, exactly 4096 and 4097 bytes, 300000 bytes, a non-zero exit with little and with much output, 300000 bytes of stderr), and checks a caller without `CaptureLonger` does not compile. The old `run_cmd_capture` stays one version beside the new form (repository-prototype#381; removal: bats#461); the driver calls it.
