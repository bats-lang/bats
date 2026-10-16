/* _bats_native_runtime.h -- the C runtime the emitted C is compiled against, over libc */
#ifndef BATS_NATIVE_RUNTIME_H
#define BATS_NATIVE_RUNTIME_H
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
/* Scalar and pointer types the emitted C names. */
typedef void atstype_void;
typedef void atsvoid_t0ype;
typedef int atstype_int;
typedef unsigned int atstype_uint;
typedef long atstype_lint;
typedef unsigned long atstype_ulint;
typedef long long atstype_llint;
typedef unsigned long long atstype_ullint;
typedef short atstype_sint;
typedef unsigned short atstype_usint;
typedef __PTRDIFF_TYPE__ atstype_ssize;
typedef __SIZE_TYPE__ atstype_size;
typedef int atstype_bool;
typedef unsigned char atstype_byte;
typedef char atstype_char;
typedef signed char atstype_schar;
typedef unsigned char atstype_uchar;
typedef char *atstype_string;
typedef char *atstype_stropt;
typedef char *atstype_strptr;
typedef void *atstype_ptr;
typedef void *atstype_ptrk;
typedef void *atstype_ref;
typedef void *atstype_boxed;
typedef void *atstype_datconptr;
typedef void *atstype_datcontyp;
typedef void *atstype_arrptr;
typedef void *atstype_funptr;
typedef void *atstype_cloptr;
/* The emitted C wraps each type in a kind and a role; both are transparent
   except where a reference argument or a boxed value is a pointer. */
#define atstkind_type(kind) kind
#define atstkind_t0ype(kind) kind
#define atstyvar_type(name) atstype_var
#define atstybox_type(ty) atstype_boxed
#define atsrefarg0_type(ty) ty
#define atsrefarg1_type(ty) atstype_ref
#define atstyarr_type(ty) ty
/* A type variable stands for a value of unknown size; no value of it is
   ever made, only pointed to, so a zero-length array of a large record. */
#ifndef _ATSTYPE_VAR_SIZE_
#define _ATSTYPE_VAR_SIZE_ 65536
#endif
typedef struct { char pad[_ATSTYPE_VAR_SIZE_]; } atstype_var[0];
#define atsbool_true 1
#define atsbool_false 0
#define atsptr_null ((void *)0)
#define the_atsptr_null atsptr_null
/* Storage classes and linkage of what is declared. */
#define ATSstruct struct
#define ATSextern() extern
#define ATSstatic() static
#define ATSinline() static inline
/* Loading a module's dynamic part once: a flag per module, set when its
   initialiser has run. */
#define ATSdynload()
#define ATSdynloadflag_sta(flagvar)
#define ATSdynloadflag_ext(flagvar) extern int flagvar
#define ATSdynloadflag_init(flagvar) int flagvar = 0
#define ATSdynloadflag_minit(flagvar) int flagvar = 0
#define ATSdynloadset(flagvar) (flagvar = 1)
#define ATSdynloadfcall(initfn) initfn()
#define ATSassume(sym) void *sym = atsptr_null
/* Declarations of constants the module uses but does not define. */
#define ATSdyncst_mac(name)
#define ATSdyncst_castfn(name)
#define ATSdyncst_extfun(name, params, result) extern result name params
#define ATSdyncst_stafun(name, params, result) static result name params
#define ATSdyncst_valimp(name, ty) ty name
#define ATSdyncst_valdec(name, ty) extern ty name
/* Control flow. */
#define ATSif(test) if (test)
#define ATSthen()
#define ATSelse() else
#define ATSifthen(test) if (test)
#define ATSifnthen(test) if (!(test))
#define ATSreturn(result) return (result)
#define ATSreturn_void(ignored) return
#define ATSfunbody_beg()
#define ATSfunbody_end()
#define ATSbranch_beg()
#define ATSbranch_end() break;
#define ATScaseof_beg() do {
#define ATScaseof_end() } while (0);
#define ATStailcal_beg() do {
#define ATStailcal_end() } while (0);
#define ATSextcode_beg()
#define ATSextcode_end()
#define ATSINSlab(target) target
#define ATSINSgoto(target) goto target
#define ATSINSflab(target) target
#define ATSINSfgoto(target) goto target
#define ATSINSdeadcode_fail() /* unreachable by the types */
/* Values: literals and conversions. */
#define ATSPMVint(literal) literal
#define ATSPMVintrep(literal) (literal)
#define ATSPMVi0nt(literal) (literal)
#define ATSPMVbool_true() atsbool_true
#define ATSPMVbool_false() atsbool_false
#define ATSPMVchar(literal) (literal)
#define ATSPMVstring(literal) (literal)
#define ATSPMVempty()
#define ATSPMVextval(sym) (sym)
#define ATSPMVptrof(place) (&(place))
#define ATSPMVptrof_void(place) atsptr_null
#define ATSPMVrefarg0(value) (value)
#define ATSPMVrefarg1(pointer) (pointer)
#define ATSPMVsizeof(ty) (sizeof(ty))
#define ATSPMVfunlab(label) (label)
#define ATSPMVcastfn(name, ty, operand) ((ty)(operand))
#define ATSPMVtyrep(repr) (repr)
/* A closure begins with the address of its code. */
#define ATStyclo() struct { void *cfun; }
#define ATSfunclo_fun(callee, params, result) ((result (*) params)(callee))
#define ATSfunclo_clo(callee, params, result) \
  ((result (*) params)(((ATStyclo() *)(callee))->cfun))
#define ATSfuncall(callee, args) (callee) args
#define ATSextfcall(callee, args) (callee) args
#define ATSextmcall(receiver, method, args) ((receiver)->method) args
/* Temporaries and what they hold. */
#define ATStmpdec(name, ty) ty name
#define ATStmpdec_void(name)
#define ATSstatmpdec(name, ty) static ty name
#define ATSstatmpdec_void(name)
#define ATSderef(place, ty) (*(ty *)place)
/* Tests on values and on patterns. */
#define ATSCKnot(test) (0 == (test))
#define ATSCKiseqz(operand) (0 == (operand))
#define ATSCKisneqz(operand) (0 != (operand))
#define ATSCKptrisnull(operand) (atsptr_null == (void *)(operand))
#define ATSCKptriscons(operand) (atsptr_null != (void *)(operand))
#define ATSCKpat_int(subject, literal) (literal == (subject))
#define ATSCKpat_bool(subject, literal) (literal == (subject))
#define ATSCKpat_char(subject, literal) (literal == (subject))
#define ATSCKpat_float(subject, literal) (literal == (subject))
/* Constructors without fields are small integers, those with fields point
   to a block whose first word is the tag; real blocks live above the
   small integers, at 1024 and up. */
#define ATSCKpat_con0(subject, tag) ((void *)(tag) == (void *)(subject))
#define ATSCKpat_con1(subject, tag) \
  ((void *)1024 <= (void *)(subject) && (tag) == *(int *)(subject))
/* Instructions. */
#define ATSINSmove(dest, value) (dest = (value))
#define ATSINSpmove(dest, ty, value) (*(ty *)(dest) = (value))
#define ATSINSmove_void(dest, call) call
#define ATSINSpmove_void(dest, ty, call) call
#define ATSINSmove_nil(dest) (dest = atsptr_null)
#define ATSINSload(dest, place) (dest = (place))
#define ATSINSstore(place, value) (place = (value))
#define ATSINSxstore(scratch, left, right) \
  (scratch = (left), left = (right), right = scratch)
#define ATSINSupdate_ptrinc(ptrvar, elty) (ptrvar = 1 + (elty *)(ptrvar))
#define ATSINSupdate_ptrdec(ptrvar, elty) (ptrvar = (elty *)(ptrvar) - 1)
#define ATSINSmove_tlcal(applied, source) (applied = (source))
#define ATSINSargmove_tlcal(param, applied) (param = (applied))
/* Fields of flat records and of constructor blocks. */
#define ATSSELfltrec(rec, recty, field) ((rec).field)
#define ATSSELrecsin(rec, recty, field) (rec)
#define ATSSELcon(block, conty, field) (((conty *)(block))->field)
#define ATSSELarrptrind(base, elty, index) (((elty *)base) index)
#define ATSINSmove_fltrec_beg()
#define ATSINSmove_fltrec_end()
#define ATSINSstore_fltrec_ofs(rec, recty, field, value) ((rec).field = (value))
#define ATSINSmove_con0(dest, tag) (dest = (void *)(tag))
#define ATSINSmove_con1_beg()
#define ATSINSmove_con1_new(dest, conty) (dest = (void *)ATS_MALLOC(sizeof(conty)))
#define ATSINSstore_con1_tag(block, tag) (*(int *)(block) = (tag))
#define ATSINSstore_con1_ofs(block, conty, field, value) \
  (((conty *)(block))->field = (value))
#define ATSINSmove_con1_end()
#define ATSINSfreecon(block) ATS_MFREE(block)
/* Closures are made and freed whole. */
#define ATSINScloptr_make(dest, nbytes) (dest = ATS_MALLOC(nbytes))
#define ATSINScloptr_free(clo) ATS_MFREE(clo)
#define ATSclosurerize_beg(label, envs, params, result)
#define ATSclosurerize_end()
#define ATSPMVcfunlab(kind, label, envargs) (label##__closurerize) envargs
#define ATSFCreturn(result) return (result)
#define ATSFCreturn_void(call) (call); return
extern void mainats_0_void(void);
#define ATSmainats_0_void(errcode) mainats_0_void()
/* The prelude's arithmetic, comparison and conversion functions the emitted
   C calls by name. Each is a typed inline function whose name says its
   signature (g0 and g1 are the unchecked and the checked flavour of the
   same operation; the C does not tell them apart). */
#define BATS_FN2(fname, result, operand, expr) \
  static inline result fname(operand lhs, operand rhs) { return expr; }
#define BATS_FN1(fname, result, operand, expr) \
  static inline result fname(operand val) { return expr; }

BATS_FN2(atspre_g0int_add_int, atstype_int, atstype_int, lhs + rhs)
BATS_FN2(atspre_g1int_add_int, atstype_int, atstype_int, lhs + rhs)
BATS_FN2(atspre_g0int_sub_int, atstype_int, atstype_int, lhs - rhs)
BATS_FN2(atspre_g1int_sub_int, atstype_int, atstype_int, lhs - rhs)
BATS_FN2(atspre_g0int_mul_int, atstype_int, atstype_int, lhs * rhs)
BATS_FN2(atspre_g1int_mul_int, atstype_int, atstype_int, lhs * rhs)
BATS_FN2(atspre_g0int_div_int, atstype_int, atstype_int, lhs / rhs)
BATS_FN2(atspre_g1int_div_int, atstype_int, atstype_int, lhs / rhs)
BATS_FN2(atspre_g0int_mod_int, atstype_int, atstype_int, lhs % rhs)
BATS_FN2(atspre_g1int_mod_int, atstype_int, atstype_int, lhs % rhs)
BATS_FN2(atspre_g0int_nmod_int, atstype_int, atstype_int, lhs % rhs)
BATS_FN2(atspre_g1int_nmod_int, atstype_int, atstype_int, lhs % rhs)
BATS_FN2(atspre_g1int_min_int, atstype_int, atstype_int, lhs < rhs ? lhs : rhs)
BATS_FN1(atspre_g0int_neg_int, atstype_int, atstype_int, 0 - val)
BATS_FN1(atspre_g1int_neg_int, atstype_int, atstype_int, 0 - val)
BATS_FN2(atspre_g0int_lt_int, atstype_bool, atstype_int, lhs < rhs)
BATS_FN2(atspre_g1int_lt_int, atstype_bool, atstype_int, lhs < rhs)
BATS_FN2(atspre_g0int_lte_int, atstype_bool, atstype_int, lhs <= rhs)
BATS_FN2(atspre_g1int_lte_int, atstype_bool, atstype_int, lhs <= rhs)
BATS_FN2(atspre_g0int_gt_int, atstype_bool, atstype_int, lhs > rhs)
BATS_FN2(atspre_g1int_gt_int, atstype_bool, atstype_int, lhs > rhs)
BATS_FN2(atspre_g0int_gte_int, atstype_bool, atstype_int, lhs >= rhs)
BATS_FN2(atspre_g1int_gte_int, atstype_bool, atstype_int, lhs >= rhs)
BATS_FN2(atspre_g0int_eq_int, atstype_bool, atstype_int, lhs == rhs)
BATS_FN2(atspre_g1int_eq_int, atstype_bool, atstype_int, lhs == rhs)
BATS_FN2(atspre_g0int_neq_int, atstype_bool, atstype_int, lhs != rhs)
BATS_FN2(atspre_g1int_neq_int, atstype_bool, atstype_int, lhs != rhs)
BATS_FN2(atspre_g0int_asl_int, atstype_int, atstype_int, lhs << rhs)
BATS_FN2(atspre_g0int_asr_int, atstype_int, atstype_int, lhs >> rhs)
BATS_FN2(atspre_lor_int_int, atstype_int, atstype_int, lhs | rhs)
BATS_FN2(atspre_land_int_int, atstype_int, atstype_int, lhs & rhs)
BATS_FN1(atspre_g0int2int_int_int, atstype_int, atstype_int, val)
BATS_FN1(atspre_g1int2int_int_int, atstype_int, atstype_int, val)
BATS_FN1(atspre_g1ofg0_int, atstype_int, atstype_int, val)
BATS_FN1(atspre_g0ofg1_int, atstype_int, atstype_int, val)

BATS_FN2(atspre_g0uint_add_uint, atstype_uint, atstype_uint, lhs + rhs)
BATS_FN2(atspre_g1uint_add_uint, atstype_uint, atstype_uint, lhs + rhs)
BATS_FN2(atspre_g0uint_sub_uint, atstype_uint, atstype_uint, lhs - rhs)
BATS_FN2(atspre_g1uint_sub_uint, atstype_uint, atstype_uint, lhs - rhs)
BATS_FN2(atspre_g0uint_mul_uint, atstype_uint, atstype_uint, lhs * rhs)
BATS_FN2(atspre_g0uint_div_uint, atstype_uint, atstype_uint, lhs / rhs)
BATS_FN2(atspre_g0uint_mod_uint, atstype_uint, atstype_uint, lhs % rhs)
BATS_FN2(atspre_g0uint_lt_uint, atstype_bool, atstype_uint, lhs < rhs)
BATS_FN2(atspre_g1uint_lt_uint, atstype_bool, atstype_uint, lhs < rhs)
BATS_FN2(atspre_g0uint_lte_uint, atstype_bool, atstype_uint, lhs <= rhs)
BATS_FN2(atspre_g1uint_lte_uint, atstype_bool, atstype_uint, lhs <= rhs)
BATS_FN2(atspre_g0uint_gt_uint, atstype_bool, atstype_uint, lhs > rhs)
BATS_FN2(atspre_g1uint_gt_uint, atstype_bool, atstype_uint, lhs > rhs)
BATS_FN2(atspre_g0uint_gte_uint, atstype_bool, atstype_uint, lhs >= rhs)
BATS_FN2(atspre_g1uint_gte_uint, atstype_bool, atstype_uint, lhs >= rhs)
BATS_FN2(atspre_g0uint_eq_uint, atstype_bool, atstype_uint, lhs == rhs)
BATS_FN2(atspre_g1uint_eq_uint, atstype_bool, atstype_uint, lhs == rhs)
BATS_FN2(atspre_g0uint_neq_uint, atstype_bool, atstype_uint, lhs != rhs)
BATS_FN2(atspre_g1uint_neq_uint, atstype_bool, atstype_uint, lhs != rhs)
BATS_FN2(atspre_g0uint_lsl_uint, atstype_uint, atstype_uint, lhs << rhs)
BATS_FN2(atspre_g0uint_lsr_uint, atstype_uint, atstype_uint, lhs >> rhs)
BATS_FN2(atspre_g0uint_lor_uint, atstype_uint, atstype_uint, lhs | rhs)
BATS_FN2(atspre_g0uint_land_uint, atstype_uint, atstype_uint, lhs & rhs)
BATS_FN2(atspre_g0uint_lxor_uint, atstype_uint, atstype_uint, lhs ^ rhs)
BATS_FN1(atspre_g0uint_lnot_uint, atstype_uint, atstype_uint, ~val)
BATS_FN1(atspre_g0int2uint_int_uint, atstype_uint, atstype_int, (atstype_uint)val)
BATS_FN1(atspre_g1int2uint_int_uint, atstype_uint, atstype_int, (atstype_uint)val)
BATS_FN1(atspre_g0uint2int_uint_int, atstype_int, atstype_uint, (atstype_int)val)
BATS_FN1(atspre_g1uint2int_uint_int, atstype_int, atstype_uint, (atstype_int)val)

BATS_FN2(atspre_g0uint_add_size, atstype_size, atstype_size, lhs + rhs)
BATS_FN2(atspre_g0uint_mul_size, atstype_size, atstype_size, lhs * rhs)
BATS_FN2(atspre_g1uint_gte_size, atstype_bool, atstype_size, lhs >= rhs)
BATS_FN1(atspre_g0int2uint_int_size, atstype_size, atstype_int, (atstype_size)val)
BATS_FN1(atspre_g1int2uint_int_size, atstype_size, atstype_int, (atstype_size)val)
BATS_FN1(atspre_g1uint2int_size_int, atstype_int, atstype_size, (atstype_int)val)

BATS_FN2(atspre_eq_char0_char0, atstype_bool, atstype_char, lhs == rhs)
BATS_FN2(atspre_eq_char1_char1, atstype_bool, atstype_char, lhs == rhs)
BATS_FN2(atspre_neq_char0_char0, atstype_bool, atstype_char, lhs != rhs)
BATS_FN2(atspre_neq_char1_char1, atstype_bool, atstype_char, lhs != rhs)
BATS_FN2(atspre_lt_char0_char0, atstype_bool, atstype_char, lhs < rhs)
BATS_FN2(atspre_gt_char0_char0, atstype_bool, atstype_char, lhs > rhs)
BATS_FN1(atspre_char2int0, atstype_int, atstype_char, (atstype_int)val)
BATS_FN1(atspre_char2int1, atstype_int, atstype_char, (atstype_int)val)
BATS_FN1(atspre_int2char0, atstype_char, atstype_int, (atstype_char)val)
BATS_FN1(atspre_byte2int0, atstype_int, atstype_byte, (atstype_int)val)
BATS_FN1(atspre_int2byte0, atstype_byte, atstype_int, (atstype_byte)val)
BATS_FN2(atspre_eq_bool0_bool0, atstype_bool, atstype_bool, lhs == rhs)
BATS_FN1(atspre_neg_bool, atstype_bool, atstype_bool, !val)
BATS_FN1(atspre_neg_bool0, atstype_bool, atstype_bool, !val)
BATS_FN1(atspre_neg_bool1, atstype_bool, atstype_bool, !val)

/* Pointers. */
static inline atstype_ptr atspre_ptr_null(void) { return atsptr_null; }
BATS_FN1(atspre_ptr_is_null, atstype_bool, atstype_ptr, atsptr_null == val)
BATS_FN1(atspre_ptr0_is_null, atstype_bool, atstype_ptr, atsptr_null == val)
BATS_FN1(atspre_ptr1_is_null, atstype_bool, atstype_ptr, atsptr_null == val)
BATS_FN1(atspre_ptr_isnot_null, atstype_bool, atstype_ptr, atsptr_null != val)
BATS_FN1(atspre_ptr0_isnot_null, atstype_bool, atstype_ptr, atsptr_null != val)
BATS_FN1(atspre_ptr1_isnot_null, atstype_bool, atstype_ptr, atsptr_null != val)
static inline atstype_ptr atspre_add_ptr0_bsz(atstype_ptr base, atstype_size nbytes)
{ return (char *)base + nbytes; }
static inline atstype_ptr atspre_add_ptr1_bsz(atstype_ptr base, atstype_size nbytes)
{ return (char *)base + nbytes; }
#undef BATS_FN1
#undef BATS_FN2

/* Memory: blocks are the C library's (wasm: the runtime's own). */
#define ATS_MALLOC(nbytes) malloc(nbytes)
#define ATS_MFREE(block) free(block)
#define atspre_cloptr_free(clo) ATS_MFREE(clo)
#define atspre_ptr_alloc_tsz(nbytes) ATS_MALLOC(nbytes)
#define atspre_strlen strlen
static inline void atspre_print_string(const char *text) { fputs(text, stdout); }
static inline void atspre_print_newline(void) { fputc(10, stdout); fflush(stdout); }
static inline void atspre_print_int(int number) { fprintf(stdout, "%d", number); }
static inline void atspre_print_char(int code) { fputc(code, stdout); }
static inline void atspre_prerr_string(const char *text) { fputs(text, stderr); }
static inline void atspre_prerr_newline(void) { fputc(10, stderr); fflush(stderr); }
static inline void atspre_prerr_int(int number) { fprintf(stderr, "%d", number); }
static inline void atspre_prerr_char(int code) { fputc(code, stderr); }
static inline void atspre_exit_void(int status) { exit(status); }
#endif
