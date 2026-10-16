/* _bats_native_runtime.h -- the ATS2 C runtime's macros over libc */
#ifndef BATS_NATIVE_RUNTIME_H
#define BATS_NATIVE_RUNTIME_H
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef void atstype_void;
typedef void atsvoid_t0ype;
typedef int atstype_int;
typedef unsigned int atstype_uint;
typedef long int atstype_lint;
typedef unsigned long int atstype_ulint;
typedef long long int atstype_llint;
typedef unsigned long long int atstype_ullint;
typedef short int atstype_sint;
typedef unsigned short int atstype_usint;
typedef atstype_lint atstype_ssize;
typedef atstype_ulint atstype_size;
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
#define atstkind_type(tk) tk
#define atstkind_t0ype(tk) tk
#ifndef _ATSTYPE_VAR_SIZE_
#define _ATSTYPE_VAR_SIZE_ 0X10000
#endif
typedef struct { char _[_ATSTYPE_VAR_SIZE_]; } atstype_var[0];
#define atstyvar_type(a) atstype_var
#define atstybox_type(hit) atstype_boxed
#define atsrefarg0_type(hit) hit
#define atsrefarg1_type(hit) atstype_ref
#define atstyarr_type(hit) hit
#define atsbool_true 1
#define atsbool_false 0
#define atsptr_null ((void*)0)
#define the_atsptr_null ((void*)0)
#define ATSstruct struct
#define ATSextern() extern
#define ATSstatic() static
#define ATSinline() static inline
#define ATSdynload()
#define ATSdynloadflag_sta(flag)
#define ATSdynloadflag_ext(flag) extern int flag
#define ATSdynloadflag_init(flag) int flag = 0
#define ATSdynloadflag_minit(flag) int flag = 0
#define ATSdynloadset(flag) flag = 1
#define ATSdynloadfcall(dynloadfun) dynloadfun()
#define ATSassume(flag) void *flag = (void*)0
#define ATSdyncst_mac(d2c)
#define ATSdyncst_castfn(d2c)
#define ATSdyncst_extfun(d2c, targs, tres) extern tres d2c targs
#define ATSdyncst_stafun(d2c, targs, tres) static tres d2c targs
#define ATSdyncst_valimp(d2c, type) type d2c
#define ATSdyncst_valdec(d2c, type) extern type d2c
#define ATSif(x) if(x)
#define ATSthen()
#define ATSelse() else
#define ATSifthen(x) if(x)
#define ATSifnthen(x) if(!(x))
#define ATSreturn(x) return(x)
#define ATSreturn_void(x) return
#define ATSfunbody_beg()
#define ATSfunbody_end()
#define ATSPMVint(i) i
#define ATSPMVintrep(rep) (rep)
#define ATSPMVbool_true() atsbool_true
#define ATSPMVbool_false() atsbool_false
#define ATSPMVchar(c) (c)
#define ATSPMVstring(str) (str)
#define ATSPMVi0nt(tok) (tok)
#define ATSPMVempty()
#define ATSPMVextval(name) (name)
#define ATSPMVptrof(lval) (&(lval))
#define ATSPMVptrof_void(lval) ((void*)0)
#define ATSPMVrefarg0(val) (val)
#define ATSPMVrefarg1(ref) (ref)
#define ATSPMVsizeof(hit) (sizeof(hit))
#define ATSPMVfunlab(flab) (flab)
#define ATSPMVcastfn(d2c, hit, arg) ((hit)arg)
#define ATSPMVtyrep(rep) (rep)
#define ATStyclo() struct{ void *cfun; }
#define ATSfunclo_fun(pmv, targs, tres) ((tres(*)targs)(pmv))
#define ATSfunclo_clo(pmv, targs, tres) ((tres(*)targs)(((ATStyclo()*)pmv)->cfun))
#define ATSfuncall(fun, funarg) (fun)funarg
#define ATSextfcall(fun, funarg) (fun)funarg
#define ATSextmcall(obj, mtd, funarg) (obj->mtd)funarg
#define ATStmpdec(tmp, hit) hit tmp
#define ATStmpdec_void(tmp)
#define ATSstatmpdec(tmp, hit) static hit tmp
#define ATSstatmpdec_void(tmp)
#define ATSderef(pmv, hit) (*(hit*)pmv)
#define ATSCKnot(x) ((x)==0)
#define ATSCKiseqz(x) ((x)==0)
#define ATSCKisneqz(x) ((x)!=0)
#define ATSCKptriscons(x) (0 != (void*)(x))
#define ATSCKptrisnull(x) (0 == (void*)(x))
#define ATSINSlab(lab) lab
#define ATSINSgoto(lab) goto lab
#define ATSINSflab(flab) flab
#define ATSINSfgoto(flab) goto flab
#define ATSINSmove(tmp, val) (tmp = val)
#define ATSINSpmove(tmp, hit, val) (*(hit*)tmp = val)
#define ATSINSmove_void(tmp, command) command
#define ATSINSpmove_void(tmp, hit, command) command
#define ATSINSmove_nil(tmp) (tmp = ((void*)0))
#define ATSINSupdate_ptrinc(tmp, tyelt) (tmp = (tyelt*)(tmp) + 1)
#define ATSINSupdate_ptrdec(tmp, tyelt) (tmp = (tyelt*)(tmp) - 1)
#define ATSINSdeadcode_fail() /*deadcode*/
#define ATSSELfltrec(pmv, tyrec, lab) ((pmv).lab)
#define ATSSELcon(pmv, tycon, lab) (((tycon*)(pmv))->lab)
#define ATSSELarrptrind(pmv, tyelt, lab) (((tyelt*)pmv)lab)
#define ATSINSmove_con1_beg()
#define ATSINSmove_con1_new(tmp, tycon) (tmp = ATS_MALLOC(sizeof(tycon)))
#define ATSINSstore_con1_ofs(tmp, tycon, lab, val) (((tycon*)(tmp))->lab = val)
#define ATSINSmove_con1_end()
#define ATSINSfreecon(ptr) ATS_MFREE(ptr)
#define ATSSELrecsin(pmv, tyrec, lab) (pmv)
#define ATSINSstore_con1_tag(dst, tag) (((int*)(dst))[0] = (tag))
#define ATSINSmove_con0(dst, tag) ((dst) = (void*)(tag))
#define ATSCKpat_con0(p, tag) ((p) == (void*)(tag))
#define ATSCKpat_con1(p, tag) ((p) >= (void*)1024 && ((int*)(p))[0] == (tag))
#define ATSCKpat_int(pmv, pat) ((pmv) == pat)
#define ATSCKpat_bool(pmv, pat) ((pmv) == pat)
#define ATSCKpat_char(pmv, pat) ((pmv) == pat)
#define ATSCKpat_float(pmv, pat) ((pmv) == pat)
#define ATSINSmove_fltrec_beg()
#define ATSINSmove_fltrec_end()
#define ATSINSstore_fltrec_ofs(tmp, tyrec, lab, val) ((tmp).lab = val)
#define ATSINSload(tmp, pmv) (tmp = pmv)
#define ATSINSstore(pmv1, pmv2) (pmv1 = pmv2)
#define ATSINSxstore(tmp, pmv1, pmv2) (tmp = pmv1, pmv1 = pmv2, pmv2 = tmp)
#define ATStailcal_beg() do {
#define ATStailcal_end() } while(0) ;
#define ATSINSmove_tlcal(apy, tmp) (apy = tmp)
#define ATSINSargmove_tlcal(arg, apy) (arg = apy)
#define ATSbranch_beg()
#define ATSbranch_end() break ;
#define ATScaseof_beg() do {
#define ATScaseof_end() } while(0) ;
#define ATSextcode_beg()
#define ATSextcode_end()
#define atspre_g1uint2int_size_int(x) ((int)(x))
#define atspre_g0int_add_int(x, y) ((x) + (y))
#define atspre_g1int_mul_int(x, y) ((x) * (y))
#define atspre_g0int2uint_int_size(x) ((atstype_size)(x))
#define atspre_g0uint_mul_size(x, y) ((x) * (y))
#define atspre_add_ptr0_bsz(p, n) ((void*)((char*)(p) + (n)))
#define atspre_g1int2int_int_int(x) (x)
#define atspre_g1int_lt_int(x, y) ((x) < (y))
#define atspre_g1int_add_int(x, y) ((x) + (y))
#define atspre_char2int1(c) ((int)(c))
#define atspre_g0int2int_int_int(x) (x)
#define atspre_g0int_gt_int(x, y) ((x) > (y))
#define atspre_g1ofg0_int(x) (x)
#define atspre_g0ofg1_int(x) (x)
#define atspre_g1int_gt_int(x, y) ((x) > (y))
#define atspre_g1int_gte_int(x, y) ((x) >= (y))
#define atspre_g1int_lte_int(x, y) ((x) <= (y))
#define atspre_g1int_sub_int(x, y) ((x) - (y))
#define atspre_g1int_neg_int(x) (-(x))
#define atspre_g0int_gte_int(x, y) ((x) >= (y))
#define atspre_g0int_lte_int(x, y) ((x) <= (y))
#define atspre_g0int_eq_int(x, y) ((x) == (y))
#define atspre_g0int_mul_int(x, y) ((x) * (y))
#define atspre_g0int_sub_int(x, y) ((x) - (y))
#define atspre_g0int_neq_int(x, y) ((x) != (y))
#define atspre_g0int_lt_int(x, y) ((x) < (y))
#define atspre_g0int_div_int(x, y) ((x) / (y))
#define atspre_g0int_mod_int(x, y) ((x) % (y))
#define atspre_g1int_div_int(x, y) ((x) / (y))
#define atspre_g1int_eq_int(x, y) ((x) == (y))
#define atspre_g1int_neq_int(x, y) ((x) != (y))
#define atspre_g0int_nmod_int(x, y) ((x) % (y))
#define atspre_g1int_nmod_int(x, y) ((x) % (y))
#define atspre_g1int_mod_int(x, y) ((x) % (y))
#define atspre_neg_bool(b) ((b) ? 0 : 1)
#define atspre_neg_bool0 atspre_neg_bool
#define atspre_neg_bool1 atspre_neg_bool
#define atspre_g0int_asl_int(x, n) ((x) << (n))
#define atspre_g0int_asr_int(x, n) ((x) >> (n))
#define atspre_lor_int_int(x, y) ((x) | (y))
#define atspre_land_int_int(x, y) ((x) & (y))
#define atspre_byte2int0(b) ((int)(b))
#define atspre_int2byte0(i) ((atstype_byte)(i))
#define atspre_char2int0(c) ((int)(c))
#define atspre_int2char0(i) ((char)(i))
#define atspre_ptr_null() ((void*)0)
#define atspre_ptr_is_null(p) ((p) == 0)
#define atspre_ptr0_is_null atspre_ptr_is_null
#define atspre_ptr1_is_null atspre_ptr_is_null
#define atspre_ptr_isnot_null(p) ((p) != 0)
#define atspre_ptr0_isnot_null atspre_ptr_isnot_null
#define atspre_ptr1_isnot_null atspre_ptr_isnot_null
#define atspre_add_ptr1_bsz(p, n) ((void*)((char*)(p) + (n)))
#define atspre_g0int_neg_int(x) (-(x))
#define atspre_g1int_neg_int(x) (-(x))
#define atspre_g1int2uint_int_size(x) ((atstype_size)(x))
#define atspre_strlen strlen
#define atspre_g0int2uint_int_uint(x) ((unsigned int)(x))
#define atspre_g1int2uint_int_uint(x) ((unsigned int)(x))
#define atspre_g0uint2int_uint_int(x) ((int)(x))
#define atspre_g1uint2int_uint_int(x) ((int)(x))
#define atspre_g0uint_add_uint(x, y) ((x) + (y))
#define atspre_g0uint_sub_uint(x, y) ((x) - (y))
#define atspre_g0uint_mul_uint(x, y) ((x) * (y))
#define atspre_g0uint_div_uint(x, y) ((x) / (y))
#define atspre_g0uint_mod_uint(x, y) ((x) % (y))
#define atspre_g0uint_lt_uint(x, y) ((x) < (y))
#define atspre_g0uint_lte_uint(x, y) ((x) <= (y))
#define atspre_g0uint_gt_uint(x, y) ((x) > (y))
#define atspre_g0uint_gte_uint(x, y) ((x) >= (y))
#define atspre_g0uint_eq_uint(x, y) ((x) == (y))
#define atspre_g0uint_neq_uint(x, y) ((x) != (y))
#define atspre_g0uint_lsl_uint(x, n) ((x) << (n))
#define atspre_g0uint_lsr_uint(x, n) ((x) >> (n))
#define atspre_g0uint_lor_uint(x, y) ((x) | (y))
#define atspre_g0uint_land_uint(x, y) ((x) & (y))
#define atspre_g0uint_lxor_uint(x, y) ((x) ^ (y))
#define atspre_g0uint_lnot_uint(x) (~(x))
#define atspre_g1uint_add_uint(x, y) ((x) + (y))
#define atspre_g1uint_sub_uint(x, y) ((x) - (y))
#define atspre_g1uint_lt_uint(x, y) ((x) < (y))
#define atspre_g1uint_lte_uint(x, y) ((x) <= (y))
#define atspre_g1uint_gt_uint(x, y) ((x) > (y))
#define atspre_g1uint_gte_uint(x, y) ((x) >= (y))
#define atspre_g1uint_eq_uint(x, y) ((x) == (y))
#define atspre_g1uint_neq_uint(x, y) ((x) != (y))
#define atspre_eq_char0_char0(x, y) ((x) == (y))
#define atspre_neq_char0_char0(x, y) ((x) != (y))
#define atspre_eq_char1_char1(x, y) ((x) == (y))
#define atspre_neq_char1_char1(x, y) ((x) != (y))
#define atspre_lt_char0_char0(x, y) ((x) < (y))
#define atspre_gt_char0_char0(x, y) ((x) > (y))
#define ATS_MALLOC(sz) malloc(sz)
#define ATS_MFREE(ptr) free(ptr)
#define ATSINScloptr_make(tmp, sz) (tmp = ATS_MALLOC(sz))
#define ATSINScloptr_free(tmp) ATS_MFREE(tmp)
#define atspre_cloptr_free(p) ATS_MFREE(p)
#define atspre_ptr_alloc_tsz(tsz) ATS_MALLOC(tsz)
#define ATSclosurerize_beg(flab, tenvs, targs, tres)
#define ATSclosurerize_end()
#define ATSFCreturn(x) return(x)
#define ATSFCreturn_void(x) (x); return
#define ATSPMVcfunlab(knd, flab, env) (flab##__closurerize)env
extern void mainats_0_void(void);
#define ATSmainats_0_void(err) mainats_0_void()
#define atspre_g1int_min_int(x, y) ((x) < (y) ? (x) : (y))
#define atspre_g1uint_gte_size(x, y) ((x) >= (y))
#define atspre_g0uint_add_size(x, y) ((x) + (y))
#define atspre_eq_bool0_bool0(x, y) ((x) == (y))
#define atspre_print_string(s) fputs((s), stdout)
#define atspre_print_newline() (fputc('\n', stdout), fflush(stdout))
#define atspre_print_int(x) fprintf(stdout, "%d", (int)(x))
#define atspre_print_char(c) fputc((int)(c), stdout)
#define atspre_prerr_string(s) fputs((s), stderr)
#define atspre_prerr_newline() (fputc('\n', stderr), fflush(stderr))
#define atspre_prerr_int(x) fprintf(stderr, "%d", (int)(x))
#define atspre_prerr_char(c) fputc((int)(c), stderr)
#define atspre_exit_void(c) exit(c)
#endif
