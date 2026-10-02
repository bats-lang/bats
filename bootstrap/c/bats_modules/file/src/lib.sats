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











































































































































































































































































































































































































































































































































