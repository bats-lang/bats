staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload R = "result/src/lib.sats"





















datatype access =
  | ReadOnly
  | WriteOnly
  | ReadWrite





datatype opening =
  | OpenExisting
  | CreateOrOpen
  | CreateOrTruncate
  | CreateOrAppend
  | TruncateExisting
  | AppendExisting




datatype io_error =
  | NotFound            (* ENOENT *)
  | PermissionDenied    (* EACCES, EPERM *)
  | AlreadyExists       (* EEXIST *)
  | NotADirectory       (* ENOTDIR *)
  | IsADirectory        (* EISDIR *)
  | DirectoryNotEmpty   (* ENOTEMPTY *)
  | ReadOnlyFilesystem  (* EROFS *)
  | FilesystemLoop      (* ELOOP *)
  | InvalidFilename     (* ENAMETOOLONG *)
  | InvalidInput        (* EINVAL *)
  | FileTooLarge        (* EFBIG, EOVERFLOW: a size or time past an int *)
  | StorageFull         (* ENOSPC, EDQUOT *)
  | TooManyOpenFiles    (* EMFILE, ENFILE *)
  | OutOfMemory         (* ENOMEM *)
  | ResourceBusy        (* EBUSY, ETXTBSY *)
  | BrokenPipe          (* EPIPE *)
  | WouldBlock          (* EAGAIN *)
  | BadDescriptor       (* EBADF *)
  | DeviceError         (* EIO *)
  | Unsupported         (* ENOTSUP *)
  | CrossesDevices      (* EXDEV *)
  | Unrecognized        (* any other errno *)


fn io_error_text (e: io_error): string





datavtype fd =
  | fd_mk of (int)





datavtype dir =
  | dir_mk of (ptr)



datavtype entries(int) =
  | {n:nat} entries_mk(n) of (ptr, int n)







fn file_open
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n,
   access: access, opening: opening, mode: int): $R.result(fd, io_error)



fn file_read
  {l:agz}{n:pos}{o:addr}
  (f: !fd, buf: !$A.arrx(byte, l, n, o), len: int n): $R.result([k:nat | k <= n] int k, io_error)



fn file_write
  {lb:agz}{n:pos}
  (f: !fd, buf: !$A.borrow(byte, lb, n), len: int n): $R.result(int n, io_error)

fn file_close(f: fd): $R.result(int, io_error)



fn file_size
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): $R.result([s:nat] int s, io_error)


fn fd_size(f: !fd): $R.result([s:nat] int s, io_error)




fn fd_copy(src: !fd, dst: !fd): $R.result([c:nat] int c, io_error)






datatype lock_kind =
  | LockShared
  | LockExclusive



datatype lock_wait =
  | LockWaits
  | LockFailsAtOnce











fn fd_lock(f: !fd, kind: lock_kind, wait: lock_wait): $R.result(int, io_error)


fn fd_unlock(f: !fd): $R.result(int, io_error)





fn dir_open
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): $R.result(dir, io_error)

fn dir_close(d: dir): $R.result(int, io_error)




fn dir_read
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): $R.result([k:nat] entries(k), io_error)

fn entries_count {n:int} (es: !entries(n)): int n




stadef ENTRY_NAME_MAX = 1024



fn entries_name
  {n:int}{i:nat | i < n}{l:agz}{m:int | m >= ENTRY_NAME_MAX}
  (es: !entries(n), i: int i, name_buf: !$A.arr(byte, l, m), max_len: int m): [k:nat | k < ENTRY_NAME_MAX] int k

fn entries_free {n:int} (es: entries(n)): void





fn file_chdir
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): $R.result(int, io_error)



fn file_mtime
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): $R.result(int, io_error)

fn file_exists
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): bool

fn file_mkdir
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n, mode: int): $R.result(int, io_error)



fn file_mode
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n): $R.result([m:nat | m <= 4095] int m, io_error)



fn file_chmod
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n, mode: int): $R.result(int, io_error)





stadef BUF_SIZE = 4096





datavtype buf_reader =
  | {lb:agz}{f,p:nat | p <= f; f <= BUF_SIZE}
    buf_reader_mk of (fd, $A.arr(byte, lb, BUF_SIZE), int f, int p)


fn buf_reader_create(f: fd): buf_reader


fun buf_read
  {l:agz}{n:pos}
  (r: !buf_reader, buf: !$A.arr(byte, l, n), len: int n): $R.option(int)


fun buf_read_line
  {l:agz}{n:pos}
  (r: !buf_reader, buf: !$A.arr(byte, l, n), max_len: int n): $R.option(int)


fn buf_reader_close(r: buf_reader): $R.result(int, io_error)








datavtype buf_writer =
  | {lb:agz}{p:nat | p < BUF_SIZE}
    buf_writer_mk of (fd, $A.arr(byte, lb, BUF_SIZE), int p)


fn buf_writer_create(f: fd): buf_writer


fn buf_write
  {lb:agz}{n:pos}
  (w: !buf_writer, data: !$A.borrow(byte, lb, n), len: int n): $R.result(int, io_error)


fn buf_write_byte(w: !buf_writer, b: int): $R.result(int, io_error)


fn buf_flush(w: !buf_writer): $R.result(int, io_error)


fn buf_writer_close(w: buf_writer): $R.result(int, io_error)



datavtype close_outcome =
  | Closed                                         (* flushed and closed *)
  | FlushFailed of (io_error)                      (* final write failed, closed *)
  | CloseFailed of (io_error)                      (* flushed, close failed *)
  | FlushAndCloseFailed of (io_error, io_error)    (* flush's, then close's *)


fn buf_writer_close_checked(w: buf_writer): close_outcome










absvtype content_writer(written: $A.cells)





absprop FILE_HOLDS(written: $A.cells)



fn content_create
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n, mode: int)
  : $R.result(content_writer($A.cnil()), io_error)



datavtype content_write_outcome($A.cells, $A.cells) =
  | {written,chunk,both:$A.cells}
    content_wrote(written, chunk) of ($A.APPEND(written, chunk, both) | content_writer(both))
  | {written,chunk:$A.cells}
    content_write_failed(written, chunk) of (io_error)


fn content_write_byte
  {written:$A.cells}{b:nat | b < 256}
  (cw: content_writer(written), b: int b)
  : content_write_outcome(written, $A.ccons(b, $A.cnil()))


fn content_write
  {written:$A.cells}{l:agz}{n:pos}{k:pos}{run_cells:$A.cells}
  (cw: content_writer(written), fz: !$A.cfrozen(l, n, k, run_cells),
   run: !$A.cborrow(l, n, run_cells), len: int n)
  : content_write_outcome(written, run_cells)


fn content_write_prefix
  {written:$A.cells}{l:agz}{n:pos}{k:pos}{run_cells,chunk:$A.cells}{m:pos | m <= n}
  (holds: $A.HOLDS(run_cells, chunk), size: $A.CLEN(chunk, m) |
   cw: content_writer(written), fz: !$A.cfrozen(l, n, k, run_cells),
   run: !$A.cborrow(l, n, run_cells), count: int m)
  : content_write_outcome(written, chunk)


datavtype content_flush_outcome($A.cells) =
  | {written:$A.cells} content_flushed(written) of (content_writer(written))
  | {written:$A.cells} content_flush_failed(written) of (io_error)

fn content_flush {written:$A.cells} (cw: content_writer(written))
  : content_flush_outcome(written)




datavtype content_close_outcome($A.cells) =
  | {written:$A.cells} content_closed(written) of (FILE_HOLDS(written) | int)
  | {written:$A.cells} content_close_failed(written) of (io_error)

fn content_close {written:$A.cells} (cw: content_writer(written))
  : content_close_outcome(written)








absvtype content_reader(consumed: $A.cells, start: int, limit: int)






absprop FILE_READ(consumed: $A.cells, start: int, limit: int)


stadef CONTENT_READ_ALL = 2147483647


fn content_reader_open_range
  {lb:agz}{n:pos | n < 1048576}{start,limit:nat}
  (path: !$A.borrow(byte, lb, n), path_len: int n, start: int start, limit: int limit)
  : $R.result(content_reader($A.cnil(), start, limit), io_error)


fn content_reader_open
  {lb:agz}{n:pos | n < 1048576}
  (path: !$A.borrow(byte, lb, n), path_len: int n)
  : $R.result(content_reader($A.cnil(), 0, CONTENT_READ_ALL), io_error)







datavtype content_read_outcome($A.cells, int, int, addr, int, $A.cells) =
  | {consumed,chunk,more,buf,buf2:$A.cells}{start,limit:nat}{l:agz}{n:pos}{k:pos | k <= n}
    content_read_some(consumed, start, limit, l, n, buf)
      of ($A.CLEN(chunk, k), $A.HOLDS(buf2, chunk), $A.APPEND(consumed, chunk, more) |
          content_reader(more, start, limit), $A.barr(l, n, buf2), int k)
  | {consumed,buf:$A.cells}{start,limit:nat}{l:agz}{n:pos}
    content_read_limit(consumed, start, limit, l, n, buf)
      of (FILE_READ(consumed, start, limit), $A.CLEN(consumed, limit) | $A.barr(l, n, buf))
  | {consumed,buf:$A.cells}{start,limit:nat}{l:agz}{n:pos}
    content_read_eof(consumed, start, limit, l, n, buf)
      of (FILE_READ(consumed, start, limit) | $A.barr(l, n, buf))
  | {consumed,buf:$A.cells}{start,limit:nat}{l:agz}{n:pos}
    content_read_failed(consumed, start, limit, l, n, buf) of (io_error, $A.barr(l, n, buf))

fn content_read
  {consumed,buf:$A.cells}{start,limit:nat}{l:agz}{n:pos}
  (cr: content_reader(consumed, start, limit), buf: $A.barr(l, n, buf), len: int n)
  : content_read_outcome(consumed, start, limit, l, n, buf)



fn content_reader_close {consumed:$A.cells}{start,limit:nat}
  (cr: content_reader(consumed, start, limit)): void












































































































































































































































































































































































































































































































































































































































































































































