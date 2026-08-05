/*
	Copyright © 2026 Jim Collier
	Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
		https://spdx.org/licenses/Apache-2.0.html
	SPDX-License-Identifier: Apache-2.0

	zuid: short, sortable, privacy-preserving unique identifiers.

	A zuid context owns an embedded WebAssembly runtime hosting the upstream
	convert-base module, so creation is not free (tens of milliseconds);
	create one and keep it. Contexts are not thread-safe - one per thread,
	or serialize access.

	A freed context must not be used again, and must not be freed again -
	the same contract C's own free() carries. Every entry point rejects a
	pointer it can see is stale, but nothing can make that reliable once the
	memory is gone.

	Linking: the shared libzuid is self-contained. The static libzuid.a needs
	the Wasmtime C API archive alongside it, plus the usual system libraries:
	-lzuid -lwasmtime -lpthread -ldl -lm.
*/

#ifndef ZUID_H
#define ZUID_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct zuid zuid;

enum {
	ZUID_OK = 0,
	ZUID_ERR_UNKNOWN_BASE = 1,  /* base name resolves to nothing; zuid_last_error suggests near matches */
	ZUID_ERR_BAD_FORMAT = 2,    /* bare '%' at the end, or an unknown %x component */
	ZUID_ERR_RESERVED = 3,      /* no longer produced; every component is implemented */
	ZUID_ERR_CONVERT = 4,       /* base conversion failed; see zuid_last_error */
	ZUID_ERR_BUFFER = 5,        /* out_cap is too small for the identifier plus its NUL */
	ZUID_ERR_CLOCK = 6,         /* the clock predates the Unix epoch */
	ZUID_ERR_INTERNAL = 7,      /* the embedded runtime or module failed */
	ZUID_ERR_PRECISION = 8,     /* precision is not -1, 0, or 1 */
	ZUID_ERR_OPTION = 9,        /* a symbol count is outside 1..ZUID_MAX_COMPONENT_CHARS */
	ZUID_ERR_ENV = 10,          /* no host name, user, hardware address, random source, or clock */
	ZUID_ERR_BASE_DIGITS = 11,  /* no longer produced; every base can carry every component */
	ZUID_ERR_HORIZON = 12,      /* the clock is past the padding horizon, so %d no longer fits its width */
	ZUID_ERR_BASE_NOT_TEXT = 13 /* the base renders raw bytes rather than text */
};

/* Upper bound on zuid_set_hash_chars and zuid_set_random_chars. */
#define ZUID_MAX_COMPONENT_CHARS 64

/* NULL when the embedded runtime cannot start. */
zuid *zuid_new(void);
void zuid_free(zuid *z);

/*
	Renders one identifier into out, NUL-terminated. A NULL or empty format
	means "%d" (the time component); a NULL or empty base means base 62.
	Returns ZUID_OK or one of the codes above.

	Format components:
		%d  time, as the precision's unit count since the Unix epoch UTC
		%h  short host name, hashed by default
		%u  user name, hashed by default
		%f  fully-qualified name, hashed by default
		%m  hardware address of the lowest-numbered non-loopback interface
		    (Linux only so far)
		%g  a UUID v4, rendered as the 128-bit number it is
		%r  random symbols from a cryptographic source
		%%  a literal '%'

	Every component but an unhashed %h %u %f is a fixed number of symbols
	wide, so an identifier can be split by offset.

	At the default component widths, 256 bytes of out holds a format naming
	every component in any curated base. Raising zuid_set_hash_chars or
	zuid_set_random_chars, repeating a component, or including literal text
	all push that up; ZUID_ERR_BUFFER says when out was too small, and
	nothing is written past it.

	On any error out is left as an empty string rather than untouched.
*/
int zuid_generate(zuid *z, const char *format, const char *base, char *out, size_t out_cap);

/*
	Time precision for %d: -1 minute, 0 second, 1 millisecond. Default 0.
	Sticky on the context. Output width varies with precision, so identifiers
	of different precisions do not sort against each other.
*/
int zuid_set_precision(zuid *z, int precision);

/*
	Hashing for %h, %u, and %f. On by default: the name goes through SHA-256
	and only zuid_set_hash_chars symbols survive, so the identifier carries a
	fingerprint rather than the name. Turning it off emits the name itself,
	which is then the one component that is not fixed width.
*/
void zuid_set_hashing(zuid *z, int enabled);

/* Symbols kept from a hashed component. Default 8. */
int zuid_set_hash_chars(zuid *z, int chars);

/*
	Symbols %r emits. Default 6. Enough bytes are drawn to fill them, which
	is one per symbol up to base 256 and more above it.
*/
int zuid_set_random_chars(zuid *z, int chars);

/* Pins the clock to a fixed Unix-milliseconds instant, for reproducible output. */
void zuid_set_clock_ms(zuid *z, long long ms);
/* Back to the wall clock. */
void zuid_clear_clock(zuid *z);

/*
	Text of the most recent failure on the last zuid_generate call for z,
	empty if it succeeded. Owned by z; copy it out before the next zuid call.
*/
const char *zuid_last_error(const zuid *z);

/* The zuid library version. */
const char *zuid_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ZUID_H */
