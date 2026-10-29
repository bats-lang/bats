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

`run_cmd_capture_outcome` (`src/helpers.bats`, bats#444) runs a child and keeps the first 4096 bytes of its stdout. The result is a linear `capture_outcome`, so a caller matches every constructor: `CaptureFits(len)` (exit 0), `CaptureFailed(status, len)` (non-zero exit, output fits), `CaptureLonger(status, mebibytes, remainder)` (more than the buffer: the child's own status beside the exact bytes it wrote, mebibytes * 1048576 + remainder, so a status is never the cause of a truncation), `CaptureReadFailed(len, io_error)` (a read failed; the old form took it for the end of the output; no status, since a child whose output was not read to its end is not known to have ended), `CaptureWaitFailed(len, mebibytes, remainder)` (the output was read to its end but `child_wait` gave no exit status; process's old `child_wait` answers a failed waitpid and a child ended by a signal alike, and `child_wait_outcome` (process#52) tells them apart but is not in the locked process, so the constructor says only that no status exists) and `CaptureNotRun(errno)`. No constructor holds a status of -1 (bats#448).

Why: bats#440 read git's file list with one 4096-byte read, closed the pipe while git was still writing, git died of SIGPIPE, and the exit status was reported as "git failed" whenever git lost the race. The new form reads stdout to its end (a read is repeated until 0 bytes, since a pipe gives what is there, not what the child will write), so bats never closes under a writer. The count is exact for any stream: it is mebibytes (at most 67108863) and a remainder under 1048576, and its lexicographic growth is the loop's termination metric, so there is no fuel; a stream of 64 TiB or more ends as `CaptureReadFailed` with `FileTooLarge` (a platform assumption, not a proof, that none is longer). The bytes are drained, only the first 4096 kept, so the child never gets SIGPIPE. Stderr goes to /dev/null: the old form read one chunk of it after stdout, which can block a child that writes more than a pipe holds.

Research (bats#444 comment): Rust `Command::output` and Python `capture_output` read everything and have no limit case; Go keeps a prefix and suffix of a long stderr and says so in the text; Node `execFile` `maxBuffer` makes it an error but terminates the child; `popen` leaves it to the caller. This form drains like Rust and makes the limit a constructor like Node, without killing the child.

`tests/capture-outcome/check.sh` builds a copy of the project with `driver.bats` as a second binary and plays real `sh` children (output in pieces with pauses, exactly 4096 and 4097 bytes, 300000 bytes, a non-zero exit with little and with much output, 300000 bytes of stderr), a child ended by SIGKILL (`CaptureWaitFailed`) and a child that writes 1 GiB and 5000 bytes (`past-1gib`, exact count), and checks a caller without `CaptureLonger` does not compile, by the error naming that constructor. The old `run_cmd_capture` stays one version beside the new form (repository-prototype#381; removal: bats#461); the driver calls it.

The callers (bats#444 done-when; all moved, each matches every constructor with `case+`; the old form has none left but its driver): `src/facts.bats` `sh_capture` (longer: failure, no bytes), `src/stamp.bats` `sh_capture` (longer: the child's status, first 4096 bytes), `src/setup.bats` `sh_exec` (same), `src/ats2.bats` `install_now` (longer: failure, a directory name is not that long), `src/cache.bats` `project_root` and `src/fixtures.bats` `make_work_dir` (only Fits has a directory name), `src/commands.bats` `git_dir_rc` (status), `git_tree_dirty` (longer is dirty) and `git_version` (`usable_len`: longer is no bytes), `src/helpers.bats` `disk_free_kib` (only Fits), `src/pins.bats` `discover` (the #440 reorder is gone: Longer is "more than 4096 bytes", the other failures are git's), and the two already on the new form (`src/affected.bats`, `tool_output`). Removal of the old form: bats#461.
