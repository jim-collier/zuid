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
	ZUID_ERR_UNKNOWN_BASE = 1, /* base name resolves to nothing; zuid_last_error suggests near matches */
	ZUID_ERR_BAD_FORMAT = 2,   /* bare '%' at the end, or an unknown %x component */
	ZUID_ERR_RESERVED = 3,     /* %h %u %f %m %g %r are reserved by the spec, not implemented yet */
	ZUID_ERR_CONVERT = 4,      /* base conversion failed; see zuid_last_error */
	ZUID_ERR_BUFFER = 5,       /* out_cap is too small for the identifier plus its NUL */
	ZUID_ERR_CLOCK = 6,        /* the clock predates the Unix epoch */
	ZUID_ERR_INTERNAL = 7      /* the embedded runtime or module failed */
};

/* NULL when the embedded runtime cannot start. */
zuid *zuid_new(void);
void zuid_free(zuid *z);

/*
	Renders one identifier into out, NUL-terminated. A NULL or empty format
	means "%d" (the time component); a NULL or empty base means base 62.
	Returns ZUID_OK or one of the codes above. 64 bytes of out is plenty for
	any curated base.
*/
int zuid_generate(zuid *z, const char *format, const char *base, char *out, size_t out_cap);

/* Pins the clock to a fixed Unix-milliseconds instant, for reproducible output. */
void zuid_set_clock_ms(zuid *z, long long ms);
/* Back to the wall clock. */
void zuid_clear_clock(zuid *z);

/*
	Text of the most recent failure on z, empty if none. Owned by z; copy it
	out before the next zuid call.
*/
const char *zuid_last_error(const zuid *z);

/* The zuid library version. */
const char *zuid_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ZUID_H */
