staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
staload R = "result/src/lib.sats"















abst@ype string_val = int
abst@ype int_val = int
abst@ype bool_val = int
abst@ype count_val = int


dataprop arg_kind(t@ype) =
  | kind_string(string_val)
  | kind_int(int_val)
  | kind_bool(bool_val)
  | kind_count(count_val)





typedef arg(a:t@ype) = [i:nat | i < 64] (arg_kind(a) | int i)













datavtype parser(int, int) =
  | {ls:agz}{lt:agz}{tp:nat | tp <= 8192}{ac:nat | ac <= 64}{gc:nat}
    parser_mk(tp, ac) of (
      $A.arr(int, ls, 1024),      (* specs: MAX_ARGS * SPEC_STRIDE *)
      $A.arr(byte, lt, 8192),     (* text buffer *)
      int ac, int tp, int gc, int, (* arg_count, text_pos, group_count, subcmd_count *)
      int, int, int, int          (* prog name_off, name_len, help_off, help_len *)
    )





datavtype parse_result =
  | {ls:agz}{lm:agz}{li:agz}{lb:agz}{lp:agz}{lt:agz}{lsp:agz}{ac:nat | ac <= 64}
    parse_result_mk of (
      $A.arr(byte, ls, 8192),     (* string values *)
      $A.arr(int, lm, 128),       (* string meta: off+len per arg *)
      $A.arr(int, li, 64),        (* int values *)
      $A.arr(int, lb, 64),        (* bool/count values *)
      $A.arr(int, lp, 64),        (* present flags *)
      int ac, int, $R.option(int), (* arg_count, text_pos, the subcommand chosen *)
      $A.arr(byte, lt, 8192),     (* spec text for help *)
      $A.arr(int, lsp, 1024)      (* spec data for help *)
    )





datavtype parse_error =
  (* A long option no spec names; carries the spec index of the option
     whose name is closest, when there is an option *)
  | err_unknown_long of ($R.option(int))
  | err_unknown_short of (int)
  (* An int argument outside its range; carries its spec index + 1 *)
  | err_range of (int)
  (* An int argument that is not a decimal int; carries its spec
     index + 1 *)
  | err_not_int of (int)
  (* More than one argument of an exclusive group; carries the group's
     index + 1 *)
  | err_exclusive of (int)
  (* A positional token named no subcommand, while subcommands are
     registered, none was given yet and no positional argument was left
     to take it; carries the token's number in argv (the program name
     is token 0). *)
  | err_choice of (int)
  (* String values did not fit the 8192-byte value buffer; carries the
     spec index + 1 of the value that overflowed. *)
  | err_too_long of (int)



datavtype int_range =
  | AnyInt
  | IntBetween of (int, int)








fn parser_new
  {lp:agz}{np:pos}{lh:agz}{nh:pos | np + nh <= 8192}
  (name: !$A.borrow(byte, lp, np), nlen: int np,
   help: !$A.borrow(byte, lh, nh), hlen: int nh): parser(np + nh, 0)

fn add_string
  {tp:nat | tp <= 8192}{ac:nat | ac < 64}{ln:agz}{nn:pos}{lh:agz}{nh:pos | tp + nn + nh <= 8192}
  (p: parser(tp, ac), name: !$A.borrow(byte, ln, nn), nlen: int nn,
   short_name: $R.option(int), help: !$A.borrow(byte, lh, nh), hlen: int nh,
   positional: bool): @(parser(tp + nn + nh, ac + 1), arg(string_val))

fn add_int
  {tp:nat | tp <= 8192}{ac:nat | ac < 64}{ln:agz}{nn:pos}{lh:agz}{nh:pos | tp + nn + nh <= 8192}
  (p: parser(tp, ac), name: !$A.borrow(byte, ln, nn), nlen: int nn,
   short_name: $R.option(int), help: !$A.borrow(byte, lh, nh), hlen: int nh,
   default_val: int, range: int_range): @(parser(tp + nn + nh, ac + 1), arg(int_val))

fn add_flag
  {tp:nat | tp <= 8192}{ac:nat | ac < 64}{ln:agz}{nn:pos}{lh:agz}{nh:pos | tp + nn + nh <= 8192}
  (p: parser(tp, ac), name: !$A.borrow(byte, ln, nn), nlen: int nn,
   short_name: $R.option(int), help: !$A.borrow(byte, lh, nh), hlen: int nh): @(parser(tp + nn + nh, ac + 1), arg(bool_val))

fn add_count
  {tp:nat | tp <= 8192}{ac:nat | ac < 64}{ln:agz}{nn:pos}{lh:agz}{nh:pos | tp + nn + nh <= 8192}
  (p: parser(tp, ac), name: !$A.borrow(byte, ln, nn), nlen: int nn,
   short_name: $R.option(int), help: !$A.borrow(byte, lh, nh), hlen: int nh): @(parser(tp + nn + nh, ac + 1), arg(count_val))




fn add_subcommand
  {tp:nat | tp <= 8192}{ac:nat | ac < 64}{ln:agz}{nn:pos}{lh:agz}{nh:pos | tp + nn + nh <= 8192}
  (p: parser(tp, ac), name: !$A.borrow(byte, ln, nn), nlen: int nn,
   help: !$A.borrow(byte, lh, nh), hlen: int nh): @(parser(tp + nn + nh, ac + 1), int)





fn parse
  {tp:nat | tp <= 8192}{ac:nat | ac <= 64}{la:agz}{na:pos}
  (p: parser(tp, ac), argv: !$A.borrow(byte, la, na), argv_len: int na,
   argc: int): $R.result(parse_result, parse_error)





fn get_string_len(r: !parse_result, h: arg(string_val)): int

fn get_string_copy
  {l:agz}{n:pos}
  (r: !parse_result, h: arg(string_val),
   buf: !$A.arr(byte, l, n), max_len: int n): int

fn get_int(r: !parse_result, h: arg(int_val)): int

fn get_bool(r: !parse_result, h: arg(bool_val)): bool

fn get_count(r: !parse_result, h: arg(count_val)): int

fn is_present {a:t@ype} (r: !parse_result, h: arg(a)): bool




fn get_subcmd(r: !parse_result): $R.option(int)





fn format_help
  {l:agz}{n:pos}
  (r: !parse_result, buf: !$A.arr(byte, l, n), max_len: int n): int

fn add_exclusive_group
  {tp:nat | tp <= 8192}{ac:nat | ac <= 64}
  (p: parser(tp, ac)): @(parser(tp, ac), int)

fn add_to_group
  {tp:nat | tp <= 8192}{ac:nat | ac <= 64}{a:t@ype}
  (p: parser(tp, ac), group_id: int, handle: arg(a)): parser(tp, ac)

fn parse_result_free(r: parse_result): void

fn parse_error_free(e: parse_error): void

fn parser_free {tp:nat | tp <= 8192}{ac:nat | ac <= 64} (p: parser(tp, ac)): void










































































































































































































































































































































































































































































































































































































































































































































































































































































































