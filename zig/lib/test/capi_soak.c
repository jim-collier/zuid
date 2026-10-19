/*
	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
	SPDX-License-Identifier: Apache-2.0

	The C soak test, in 2 modes. The malloc heap is read after round N and
	again after round 2N, and growth past the margin fails. The first rounds
	fill caches, which is why it's N against 2N and not 0 against N.

	- calls: one context, and each round is every component in every curated
	  base, the options, and the refusals. cicd.bash --leakcheck runs this
	  one under heaptrack.
	- contexts: each round is a whole context's life, zuid_new to zuid_free.
	  zuid_new compiles the wasm module, a few million mallocs that heaptrack
	  adds its own memory for, so this one runs plain.

	Run it with GLIBC_TUNABLES=glibc.malloc.tcache_count=0. The per-thread
	cache counts freed blocks as in use, and the reading wanders by about
	100 KB without it. Linux and glibc only, for mallinfo2. The Zig side
	allocates with mmap, which mallinfo2 doesn't see, so this watches
	Wasmtime's heap and the caller's.

	Syntax: capi_soak calls|contexts [rounds N] [margin in bytes]
*/

#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zuid.h>

#if defined(__SANITIZE_ADDRESS__)
#define SOAK_UNDER_ASAN 1
#elif defined(__has_feature)
#if __has_feature(address_sanitizer)
#define SOAK_UNDER_ASAN 1
#endif
#endif

/* The user, FQDN and MAC come off the machine, and a container with no passwd
   entry or network can't supply them. Those may get ZUID_ERR_ENV as well, so
   that refusal is soaked too. */
struct soak_format {
	const char *format;
	int machine;
};
static const struct soak_format formats[] = {
	{"%d", 0}, {"%h", 0}, {"%g", 0}, {"%r", 0}, {"%d%h%g%r", 0},
	{"%u", 1}, {"%f", 1}, {"%m", 1}, {"%d%h%u%f%m%g%r", 1},
};
static const char *const bases[] = {NULL, "16", "32w", "36", "64tt", "128tt", "256tt", "512tt", "1024tz", "2048tz"};

/* The refusals write error text into the context, which is its own path. A
   cap of 0 is the whole buffer. */
struct soak_refusal {
	const char *format;
	const char *base;
	size_t cap;
	int code;
};
static const struct soak_refusal refusals[] = {
	{"%d", "hexx", 0, ZUID_ERR_UNKNOWN_BASE},
	{"%d", "bytes", 0, ZUID_ERR_BASE_NOT_TEXT},
	{"%d", NULL, 4, ZUID_ERR_BUFFER},
	{"%q", NULL, 0, ZUID_ERR_BAD_FORMAT},
};

#define COUNT(a) (sizeof(a) / sizeof((a)[0]))

static size_t heapInUse(void) {
	struct mallinfo2 info = mallinfo2();
	return info.uordblks + info.hblkhd;
}

static int gen(zuid *z, const char *format, const char *base, char *out, size_t cap) {
	zuid_request req = {0};
	req.format = format;
	req.base = base;
	return zuid_generate(z, &req, out, cap);
}

/* Non-zero on anything the smoke test would call a failure, since a soak that
   stops generating stops measuring. */
static int calls(zuid *z) {
	char out[1024];
	int bad = 0;

	zuid_set_clock_ms(z, 1785585600000LL);
	for (size_t i = 0; i < COUNT(formats) * COUNT(bases); i++) {
		const struct soak_format *f = &formats[i / COUNT(bases)];
		const char *base = bases[i % COUNT(bases)];
		int code = gen(z, f->format, base, out, sizeof out);
		if (code != ZUID_OK && !(f->machine && code == ZUID_ERR_ENV)) {
			printf("  %s in %s: %s\n", f->format, base ? base : "62", zuid_last_error(z));
			bad = 1;
		}
	}

	zuid_request options = {0};
	options.format = "%h%g%r";
	options.salt = "pepper";
	options.precision = 1;
	options.hash_chars = 5;
	options.random_chars = 12;
	if (zuid_generate(z, &options, out, sizeof out) != ZUID_OK) bad = 1;
	options.no_hash = 1;
	if (zuid_generate(z, &options, out, sizeof out) != ZUID_OK) bad = 1;

	for (size_t i = 0; i < COUNT(refusals); i++) {
		const struct soak_refusal *r = &refusals[i];
		if (gen(z, r->format, r->base, out, r->cap ? r->cap : sizeof out) != r->code || zuid_last_error(z)[0] == '\0') {
			printf("  %s in %s: want code %d\n", r->format, r->base ? r->base : "62", r->code);
			bad = 1;
		}
	}
	zuid_set_clock_ms(z, 32503680000000000LL);
	if (gen(z, "%d", NULL, out, sizeof out) != ZUID_ERR_HORIZON) bad = 1;

	zuid_clear_clock(z);
	if (gen(z, "%d%h%g%r", NULL, out, sizeof out) != ZUID_OK) bad = 1;
	if (bad) printf("  a round failed\n");
	return bad;
}

static int contexts(void) {
	char out[256];
	zuid *z = zuid_new();
	if (!z) {
		printf("  zuid_new returned NULL\n");
		return 1;
	}
	int bad = gen(z, "%d%h%g%r", "2048tz", out, sizeof out) != ZUID_OK;
	bad |= gen(z, "%d", "hexx", out, sizeof out) != ZUID_ERR_UNKNOWN_BASE;
	zuid_free(z);
	if (bad) printf("  a round failed\n");
	return bad;
}

int main(int argc, char **argv) {
#ifdef SOAK_UNDER_ASAN
	printf("  skipped: ASan's allocator hides the heap from mallinfo2\n");
	return 77;
#endif
	int perCall = argc > 1 && strcmp(argv[1], "calls") == 0;
	if (argc < 2 || (!perCall && strcmp(argv[1], "contexts") != 0)) {
		printf("Syntax: capi_soak calls|contexts [rounds N] [margin in bytes]\n");
		return 2;
	}
	/* About 0.1 s a call round under heaptrack, and 0.7 s a context round. */
	long rounds = argc > 2 ? strtol(argv[2], NULL, 10) : (perCall ? 100 : 8);
	long margin = argc > 3 ? strtol(argv[3], NULL, 10) : 8192;
	if (rounds < 1 || margin < 0) {
		printf("Syntax: capi_soak calls|contexts [rounds N] [margin in bytes]\n");
		return 2;
	}

	zuid *z = NULL;
	if (perCall) {
		z = zuid_new();
		if (!z) {
			printf("  zuid_new returned NULL\n");
			return 1;
		}
	}
	size_t atN = 0;
	int bad = 0;
	for (long i = 1; i <= 2 * rounds && !bad; i++) {
		bad = perCall ? calls(z) : contexts();
		if (i == rounds) atN = heapInUse();
	}
	size_t at2N = heapInUse();
	zuid_free(z);
	if (bad) return 1;

	printf("  heap in use after round %ld: %zu bytes, after round %ld: %zu bytes\n", rounds, atN, 2 * rounds, at2N);
	if (at2N > atN && at2N - atN > (size_t)margin) {
		printf("  the heap grew %zu bytes, past the %ld byte margin\n", at2N - atN, margin);
		return 1;
	}
	return 0;
}
