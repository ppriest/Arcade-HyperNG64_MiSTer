// SPDX-License-Identifier: GPL-3.0-or-later
// The few MAME definitions the ported files use (PROVENANCE.md).
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstring>

typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int8_t   s8;
typedef int16_t  s16;
typedef int32_t  s32;
typedef int64_t  s64;
typedef uint32_t offs_t;

template <typename T> constexpr T BIT(T x, int n) { return (x >> n) & T(1); }

// x86-64 and armhf are both little-endian
#define NATIVE_ENDIAN_VALUE_LE_BE(le, be) (le)

enum { CLEAR_LINE = 0, ASSERT_LINE = 1 };

// MAME's logerror, to stderr when HNG64SND_LOG is set
void logerror(const char *fmt, ...)
#if defined(__GNUC__)
	__attribute__((format(printf, 1, 2)))
#endif
	;
