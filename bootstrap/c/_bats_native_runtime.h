/* _bats_native_runtime.h -- the C runtime the emitted C is compiled against, over libc */
#ifndef BATS_NATIVE_RUNTIME_H
#define BATS_NATIVE_RUNTIME_H
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
/* Types the emitted C names, alphabetically. */
typedef void atsvoid_t0ype;
typedef void atstype_void;
typedef void *atstype_arrptr;
typedef int atstype_bool;
typedef void *atstype_boxed;
typedef unsigned char atstype_byte;
typedef char atstype_char;
typedef void *atstype_cloptr;
typedef void *atstype_datconptr;
typedef void *atstype_datcontyp;
typedef void *atstype_funptr;
typedef int atstype_int;
typedef long atstype_lint;
typedef long long atstype_llint;
typedef void *atstype_ptr;
typedef void *atstype_ptrk;
typedef void *atstype_ref;
typedef signed char atstype_schar;
typedef short atstype_sint;
typedef __SIZE_TYPE__ atstype_size;
typedef __PTRDIFF_TYPE__ atstype_ssize;
typedef char *atstype_string;
typedef char *atstype_stropt;
typedef char *atstype_strptr;
typedef unsigned char atstype_uchar;
typedef unsigned int atstype_uint;
typedef unsigned long atstype_ulint;
typedef unsigned long long atstype_ullint;
typedef unsigned short atstype_usint;
/* A type variable stands for a value of unknown size, which is only ever
   pointed to: a zero-length array of an opaque block. */
typedef struct { char opaque[1 << 16]; } atstype_var[0];
/* A cast spelt once, for the macros that cast an operand. */
#define BATS_CAST(ty, operand) ((ty)(operand))
/* Kinds and roles wrap a type; all are transparent but a reference argument and a boxed value, which are pointers. */
#define atsrefarg0_type(ty) ty
#define atsrefarg1_type(ty) atstype_ref
#define atstkind_t0ype(kind) kind
#define atstkind_type(kind) kind
#define atstyarr_type(ty) ty
#define atstybox_type(ty) atstype_boxed
#define atstyvar_type(name) atstype_var
/* Constants. */
#define atsbool_false 0
#define atsbool_true 1
#define atsptr_null ((atstype_ptr)0)
#define the_atsptr_null atsptr_null
/* Storage class and linkage of what is declared. */
#define ATSextern() extern
#define ATSinline() static __inline__
#define ATSstatic() static
#define ATSstruct struct
/* A module is loaded once: a flag per module, set when its initialiser has run. */
#define ATSassume(sym) void *sym = atsptr_null
#define ATSdynload()
#define ATSdynloadfcall(initfn) (initfn)()
#define ATSdynloadflag_ext(flagvar) extern int flagvar
#define ATSdynloadflag_init(flagvar) int flagvar
#define ATSdynloadflag_minit(flagvar) int flagvar
#define ATSdynloadflag_sta(flagvar)
#define ATSdynloadset(flagvar) (flagvar = 1)
/* Constants the module uses but does not define. */
#define ATSdyncst_castfn(name)
#define ATSdyncst_extfun(name, params, result) extern result name params
#define ATSdyncst_mac(name)
#define ATSdyncst_stafun(name, params, result) static result name params
#define ATSdyncst_valdec(name, ty) extern ty name
#define ATSdyncst_valimp(name, ty) ty name
/* Control flow. */
#define ATSINSdeadcode_fail() /* unreachable by the types */
#define ATSINSfgoto(target) goto target
#define ATSINSflab(target) target
#define ATSINSgoto(target) goto target
#define ATSINSlab(target) target
#define ATSbranch_beg()
#define ATSbranch_end() break;
#define ATScaseof_beg() for (;;) {
#define ATScaseof_end() break; }
#define ATSelse() else
#define ATSextcode_beg()
#define ATSextcode_end()
#define ATSfunbody_beg()
#define ATSfunbody_end()
#define ATSif(test) if (test)
#define ATSifnthen(test) if ((test) == 0)
#define ATSifthen(test) if (test)
#define ATSreturn(result) return (result)
#define ATSreturn_void(ignored) return
#define ATStailcal_beg() for (;;) {
#define ATStailcal_end() break; }
#define ATSthen()
/* Values: literals, conversions and the address of a place. */
#define ATSPMVbool_false() atsbool_false
#define ATSPMVbool_true() atsbool_true
#define ATSPMVcastfn(name, ty, operand) BATS_CAST(ty, operand)
#define ATSPMVchar(literal) (literal)
#define ATSPMVempty()
#define ATSPMVextval(sym) (sym)
#define ATSPMVfunlab(label) (label)
#define ATSPMVi0nt(literal) (literal)
#define ATSPMVint(literal) literal
#define ATSPMVintrep(literal) (literal)
#define ATSPMVptrof(place) (&(place))
#define ATSPMVptrof_void(place) atsptr_null
#define ATSPMVrefarg0(value) (value)
#define ATSPMVrefarg1(pointer) (pointer)
#define ATSPMVsizeof(ty) ((atstype_size)sizeof(ty))
#define ATSPMVstring(literal) (literal)
#define ATSPMVtyrep(repr) (repr)
/* Calls. A closure begins with the address of its code. */
#define ATSextfcall(callee, args) ((callee) args)
#define ATSextmcall(receiver, method, args) ((receiver)->method) args
#define ATSfuncall(callee, args) ((callee) args)
#define ATSfunclo_clo(callee, params, result) BATS_CAST(result (*) params, ((ATStyclo() *)(callee))->cfun)
#define ATSfunclo_fun(callee, params, result) BATS_CAST(result (*) params, callee)
#define ATStyclo() struct { void *cfun; }
/* Temporaries and dereferencing. */
#define ATSderef(place, ty) (((ty *)(place))[0])
#define ATSstatmpdec(name, ty) static ty name
#define ATSstatmpdec_void(name)
#define ATStmpdec(name, ty) ty name
#define ATStmpdec_void(name)
/* Tests on values and on patterns. A constructor without fields is a small integer; one with fields is a pointer to a block whose first word is the tag, and blocks lie at 1024 and above. */
#define ATSCKiseqz(operand) (0 == (operand))
#define ATSCKisneqz(operand) (0 != (operand))
#define ATSCKnot(test) (0 == (test))
#define ATSCKpat_bool(subject, literal) (literal == (subject))
#define ATSCKpat_char(subject, literal) (literal == (subject))
#define ATSCKpat_con0(subject, tag) ((void *)(tag) == (void *)(subject))
#define ATSCKpat_con1(subject, tag) ((void *)1024 <= (void *)(subject) && (tag) == *(int *)(subject))
#define ATSCKpat_float(subject, literal) (literal == (subject))
#define ATSCKpat_int(subject, literal) (literal == (subject))
#define ATSCKptriscons(operand) (atsptr_null != (void *)(operand))
#define ATSCKptrisnull(operand) (atsptr_null == (void *)(operand))
/* Instructions: moves, loads and stores. */
#define ATSINSargmove_tlcal(param, applied) (param = (applied))
#define ATSINSload(dest, place) (dest = (place))
#define ATSINSmove(dest, value) (dest = (value))
#define ATSINSmove_nil(dest) (dest = atsptr_null)
#define ATSINSmove_tlcal(applied, source) (applied = (source))
#define ATSINSmove_void(dest, call) call
#define ATSINSpmove(dest, ty, value) (*(ty *)(dest) = (value))
#define ATSINSpmove_void(dest, ty, call) call
#define ATSINSstore(place, value) (place = (value))
#define ATSINSupdate_ptrdec(ptrvar, elty) (ptrvar = (elty *)(ptrvar) + (-1))
#define ATSINSupdate_ptrinc(ptrvar, elty) (ptrvar = 1 + (elty *)(ptrvar))
#define ATSINSxstore(scratch, left, right) (scratch = (left), left = (right), right = scratch)
/* Fields of flat records, and of constructor blocks. */
#define ATSINSfreecon(block) ((void)ATS_MFREE(block))
#define ATSINSmove_con0(dest, tag) (dest = (void *)(tag))
#define ATSINSmove_con1_beg()
#define ATSINSmove_con1_end()
#define ATSINSmove_con1_new(dest, conty) (dest = (void *)ATS_MALLOC(sizeof(conty)))
#define ATSINSmove_fltrec_beg()
#define ATSINSmove_fltrec_end()
#define ATSINSstore_con1_ofs(block, conty, field, value) ((*(conty *)(block)).field = (value))
#define ATSINSstore_con1_tag(block, tag) (*(int *)(block) = (tag))
#define ATSINSstore_fltrec_ofs(rec, recty, field, value) ((rec).field = (value))
#define ATSSELarrptrind(base, elty, index) (BATS_CAST(elty *, base) index)
#define ATSSELcon(block, conty, field) ((*(conty *)(block)).field)
#define ATSSELfltrec(rec, recty, field) ((rec).field)
#define ATSSELrecsin(rec, recty, field) (rec)
/* Closures are made and freed whole; the program ends in its entry. */
#define ATSFCreturn(result) return (result)
#define ATSFCreturn_void(call) ((void)(call)); return
#define ATSINScloptr_free(clo) ATS_MFREE(clo)
#define ATSINScloptr_make(dest, nbytes) (dest = ATS_MALLOC(nbytes))
#define ATSPMVcfunlab(kind, label, envargs) ((label##__closurerize) envargs)
#define ATSclosurerize_beg(label, envs, params, result)
#define ATSclosurerize_end()
#define ATSmainats_0_void(errcode) mainats_0_void()
extern void mainats_0_void(void);
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
#define ATS_MALLOC(nbytes) bats_alloc(nbytes)
#define ATS_MFREE(block) free(block)
#define atspre_cloptr_free(clo) ATS_MFREE(clo)
#define atspre_ptr_alloc_tsz(nbytes) ATS_MALLOC(nbytes)
#define atspre_strlen strlen
static inline void *bats_alloc(size_t nbytes) { void *block = malloc(nbytes); if (block == NULL) { fputs("bats: out of memory\n", stderr); exit(1); } return block; }
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
