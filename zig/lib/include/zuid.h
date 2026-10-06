/*
	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
	Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
		https://spdx.org/licenses/Apache-2.0.html
	SPDX-License-Identifier: Apache-2.0

	zuid: short, sortable, privacy-preserving unique identifiers.

	A zuid context owns an embedded WebAssembly runtime hosting the upstream
	convert-base module, so creation is not free: expect around half a
	second, between compiling the module and the module building its base
	registry. Create one and keep it. Contexts are not thread-safe - one per
	thread, or serialize access.

	What an identifier looks like comes with each call, in a zuid_request,
	the same as the Go module's Request. The context keeps only the runtime
	and the machine's own values, so code sharing one cannot change what
	another part of the program gets.

	A freed context must not be used again, and must not be freed again -
	the same contract C's own free() carries. Every entry point rejects a
	pointer it can see is stale, but nothing can make that reliable once the
	memory is gone.

	Linking: the shared libzuid exports only these entry points and carries
	its own runtime, so -lzuid is the whole story. It carries an soname, so
	what a linked program records is libzuid.so.1; from 1.0.0 on, the major
	only changes if one of the entry points or error codes below does. The
	prereleases before it are not held to that. The static libzuid.a holds
	its own objects only, so it needs the Wasmtime C API archive next to it -
	the release puts libwasmtime.a in the same lib/ directory - plus the usual
	system libraries:
		-lzuid -lwasmtime -lpthread -ldl -lm
	On FreeBSD the Wasmtime archive also calls zstd, so the release puts
	libzstd.a in lib/ too:
		-lzuid -lwasmtime -lzstd -lpthread -lm
	On Windows the shared library is zuid.dll. MSVC and mingw both link it
	through its import library, zuid.lib, given as a file, since mingw's
	-lzuid finds the static library first. The static library is libzuid.a.
	It is a mingw archive, which MSVC cannot link, and it needs the mingw
	libwasmtime.a beside it plus these system libraries:
		-lzuid -lwasmtime -lws2_32 -liphlpapi -lbcrypt -ladvapi32 -luserenv
		-lole32 -lntdll
	On arm64 Windows, Wasmtime is a DLL. zuid.exe, zuid.dll and a program
	linked with libzuid.a all load wasmtime.dll, so it goes beside them.
	The line above still links libzuid.a there, since -lwasmtime finds
	wasmtime.lib, the import library for wasmtime.dll.
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
	ZUID_ERR_OPTION = 9,        /* a symbol count is outside 1..ZUID_MAX_COMPONENT_CHARS, a hashed
	                               component is wider than a SHA-256 fills in the base, or the salt
	                               is longer than ZUID_MAX_SALT_BYTES */
	ZUID_ERR_ENV = 10,          /* no host name, user, hardware address or random source, or the
	                               clock could not be read */
	ZUID_ERR_BASE_DIGITS = 11,  /* no longer produced; every base can carry every component */
	ZUID_ERR_HORIZON = 12,      /* the clock is past the padding horizon, so %d no longer fits its width */
	ZUID_ERR_BASE_NOT_TEXT = 13, /* the base renders raw bytes or control characters, not text */
	ZUID_ERR_CONTEXT = 14        /* z is NULL or already freed */
};

/* Upper bound on hash_chars and random_chars. */
#define ZUID_MAX_COMPONENT_CHARS 64

/* Upper bound on the salt, in bytes. */
#define ZUID_MAX_SALT_BYTES 256

/*
	One identifier's worth of choices. Zero is the default for every field,
	so start from {0} and set what differs, or pass NULL for all defaults.
	Strings are read during the call only, so the caller may free or reuse
	them afterwards.
*/
typedef struct zuid_request {
	/* NULL or "" means "%d", the time component. */
	const char *format;

	/* NULL or "" means base 62. */
	const char *base;

	/*
		Time precision for %d: -1 minute, 0 second, 1 millisecond. Output width
		varies with precision, so identifiers of different precisions do not
		sort against each other.
	*/
	int precision;

	/*
		Hashing for %h, %u, and %f is on by default: the name goes through
		SHA-256 and only hash_chars symbols survive, so the identifier carries a
		fingerprint rather than the name. Nonzero here emits the name itself,
		which is then the one component that is not fixed width.
	*/
	int no_hash;

	/*
		Symbols kept from a hashed component. Zero derives the width from the
		base so that every base carries the same fingerprint strength rather
		than the same symbol count - 12 symbols in base 16, 8 in 62, 5 in
		2048tz. A symbol is worth four bits in base 16 and eleven in 2048tz, so
		one fixed count would mean wildly different strength.

		More than a SHA-256 fills in the base is ZUID_ERR_OPTION: past that
		point the extra symbols are all padding, so the identifier grows without
		the fingerprint getting any stronger. The ceiling runs from 64 symbols
		in base 16 down to 24 in 2048tz, and zuid_last_error names it.
	*/
	int hash_chars;

	/*
		Symbols %r emits, derived from the base the same way when zero: 9 in
		base 16, 6 in 62, 4 in 2048tz. Enough bytes are drawn to fill them,
		which is one per symbol up to base 256 and more above it.

		Both widths are checked only when the format uses them, and outside
		1..ZUID_MAX_COMPONENT_CHARS is ZUID_ERR_OPTION.
	*/
	int random_chars;

	/*
		Secret mixed into %h, %u, and %f before hashing. NULL or "" hashes the
		name on its own.

		Host and user names come from a small space, so anyone holding
		identifiers can hash candidate names and compare. A salt closes that
		off, at the cost of being something every machine whose fingerprints
		are compared has to share: the same name under two salts gives two
		different components. Longer than ZUID_MAX_SALT_BYTES is
		ZUID_ERR_OPTION - SHA-256 works on 64-byte blocks, so a longer secret
		adds nothing.
	*/
	const char *salt;
} zuid_request;

/* NULL when the embedded runtime cannot start. */
zuid *zuid_new(void);
void zuid_free(zuid *z);

/*
	Renders one identifier into out, NUL-terminated, as req describes. NULL
	req means every default: "%d" in base 62 at second precision. Returns
	ZUID_OK or one of the codes above.

	Format components:
		%d  time, as the precision's unit count since the Unix epoch UTC
		%h  short host name, hashed by default
		%u  user name, hashed by default
		%f  fully-qualified name, hashed by default
		%m  hardware address of the lowest-numbered non-loopback interface
		%g  a UUID v4, rendered as the 128-bit number it is
		%r  random symbols from a cryptographic source
		%%  a literal '%'

	Every component but an unhashed %h %u %f is a fixed number of symbols
	wide, so an identifier can be split by offset.

	At the derived component widths, 256 bytes of out holds a format naming
	every component in any curated base. Raising hash_chars or random_chars,
	repeating a component, or including literal text all push that up;
	ZUID_ERR_BUFFER says when out was too small, and nothing is written past
	it.

	On any error out is left as an empty string rather than untouched.
*/
int zuid_generate(zuid *z, const zuid_request *req, char *out, size_t out_cap);

/* Pins the clock to a fixed Unix-milliseconds instant, for reproducible output. */
void zuid_set_clock_ms(zuid *z, long long ms);
/* Back to the wall clock. */
void zuid_clear_clock(zuid *z);

/*
	Text of the most recent failure on the last zuid_generate call for z,
	empty if it succeeded. Owned by z; copy it out before the next zuid call.
	Empty for a NULL or freed z.
*/
const char *zuid_last_error(const zuid *z);

/* The zuid library version. */
const char *zuid_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ZUID_H */
