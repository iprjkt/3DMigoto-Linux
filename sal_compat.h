#pragma once

#if defined(__cplusplus)
#include <string>
#include <locale>
#endif

// SAL compatibility macros for MinGW-w64 GCC
#ifndef __in_range
#define __in_range(a, b)
#endif
#ifndef __out_ecount
#define __out_ecount(n)
#endif
#ifndef __out_ecount_opt
#define __out_ecount_opt(n)
#endif
#ifndef __out_ecount_part_opt
#define __out_ecount_part_opt(n, m)
#endif
#ifndef __out_ecount_full_opt
#define __out_ecount_full_opt(n)
#endif
#ifndef __in_ecount
#define __in_ecount(n)
#endif
#ifndef __in_ecount_opt
#define __in_ecount_opt(n)
#endif
#ifndef __in_bcount
#define __in_bcount(n)
#endif
#ifndef __in_bcount_opt
#define __in_bcount_opt(n)
#endif
#ifndef __out_bcount
#define __out_bcount(n)
#endif
#ifndef __out_bcount_opt
#define __out_bcount_opt(n)
#endif
#ifndef __out_bcount_part_opt
#define __out_bcount_part_opt(n, m)
#endif
#ifndef __out
#define __out
#endif
#ifndef __in
#define __in
#endif
#ifndef __inout
#define __inout
#endif
#ifndef __in_opt
#define __in_opt
#endif
#ifndef __out_opt
#define __out_opt
#endif
#ifndef __inout_opt
#define __inout_opt
#endif
#ifndef __in_z
#define __in_z
#endif
#ifndef __in_z_opt
#define __in_z_opt
#endif
#ifndef __out_z
#define __out_z
#endif
#ifndef __out_z_opt
#define __out_z_opt
#endif
#ifndef __inout_z
#define __inout_z
#endif
#ifndef __inout_z_opt
#define __inout_z_opt
#endif
#ifndef __in_xcount
#define __in_xcount(n)
#endif
#ifndef __in_xcount_opt
#define __in_xcount_opt(n)
#endif
#ifndef __out_xcount
#define __out_xcount(n)
#endif
#ifndef __out_xcount_opt
#define __out_xcount_opt(n)
#endif
#ifndef __inout_xcount
#define __inout_xcount(n)
#endif
#ifndef __inout_xcount_opt
#define __inout_xcount_opt(n)
#endif
