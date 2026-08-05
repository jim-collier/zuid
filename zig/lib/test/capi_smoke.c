/*
	Copyright © 2026 Jim Collier
	SPDX-License-Identifier: Apache-2.0

	Compiled and run by cicd.bash against both link modes, with the system
	compiler rather than zig cc - the point is that a foreign toolchain can
	use the installed header and archives.

	Only the time component is pinned to an expected string. The rest come off
	whatever machine this runs on, so their widths are what gets checked.
*/

#include <stdio.h>
#include <string.h>
#include <zuid.h>

static int fails = 0;

static void want(const char *label, const char *got, const char *expected) {
	if (strcmp(got, expected) == 0) return;
	printf("  %s: got %s, want %s\n", label, got, expected);
	fails++;
}

static void wantLen(const char *label, const char *got, size_t expected) {
	if (strlen(got) == expected) return;
	printf("  %s: %s is %zu symbols, want %zu\n", label, got, strlen(got), expected);
	fails++;
}

static void wantCode(const char *label, int got, int expected) {
	if (got == expected) return;
	printf("  %s: got code %d, want %d\n", label, got, expected);
	fails++;
}

int main(void) {
	char out[256];
	zuid *z = zuid_new();
	if (!z) {
		printf("  zuid_new returned NULL\n");
		return 1;
	}

	/* A pinned clock is what makes the time component reproducible. */
	zuid_set_clock_ms(z, 946684800000LL);
	wantCode("generate", zuid_generate(z, NULL, NULL, out, sizeof out), ZUID_OK);
	want("time, defaults", out, "124Bxg");
	wantCode("generate 32w", zuid_generate(z, "%d", "32w", out, sizeof out), ZUID_OK);
	want("time, base 32w", out, "2r8pRr2");

	/* Derived widths, in base 62: hash 8, uuid 22, random 6. Every base gets
	   the width carrying the same strength, not the same symbol count. */
	wantCode("generate %h", zuid_generate(z, "%h", NULL, out, sizeof out), ZUID_OK);
	wantLen("host, hashed", out, 8);
	wantCode("generate %g", zuid_generate(z, "%g", NULL, out, sizeof out), ZUID_OK);
	wantLen("uuid v4", out, 22);
	wantCode("generate %r", zuid_generate(z, "%r", NULL, out, sizeof out), ZUID_OK);
	wantLen("random", out, 6);

	/* Bases whose digits are several bytes each. The clock is the only source
	   this API can pin, so %d is what gets an exact value; %h and %r just have
	   to work, since their widths are in symbols and strlen counts bytes. The
	   vectors cover those two in these bases from both implementations. */
	zuid_set_clock_ms(z, 1785585600000LL);
	wantCode("generate 512tt", zuid_generate(z, "%d", "512tt", out, sizeof out), ZUID_OK);
	want("time, base 512tt", out, "Dԋჰ𐀛");
	wantCode("generate 2048tz", zuid_generate(z, "%d", "2048tz", out, sizeof out), ZUID_OK);
	want("time, base 2048tz", out, "0主劸𐃃");
	wantCode("truncate in 512tt", zuid_generate(z, "%h%r", "512tt", out, sizeof out), ZUID_OK);

	wantCode("set hash chars", zuid_set_hash_chars(z, 5), ZUID_OK);
	wantCode("set random chars", zuid_set_random_chars(z, 12), ZUID_OK);
	wantCode("generate resized", zuid_generate(z, "%h%r", NULL, out, sizeof out), ZUID_OK);
	wantLen("resized components", out, 17);

	/* Zero puts both back on the base's derived default. */
	wantCode("hash chars 0", zuid_set_hash_chars(z, 0), ZUID_OK);
	wantCode("random chars 0", zuid_set_random_chars(z, 0), ZUID_OK);
	wantCode("generate defaulted", zuid_generate(z, "%h%r", NULL, out, sizeof out), ZUID_OK);
	wantLen("defaulted components", out, 14);

	/* Every rejection path the header documents. */
	wantCode("hash chars over cap", zuid_set_hash_chars(z, ZUID_MAX_COMPONENT_CHARS + 1), ZUID_ERR_OPTION);
	wantCode("random chars over cap", zuid_set_random_chars(z, ZUID_MAX_COMPONENT_CHARS + 1), ZUID_ERR_OPTION);
	/* Past what a SHA-256 fills in base 62, which is 43 symbols. */
	wantCode("hash past the digest", zuid_set_hash_chars(z, 44), ZUID_OK);
	wantCode("generate over-wide hash", zuid_generate(z, "%h", "62", out, sizeof out), ZUID_ERR_OPTION);
	wantCode("hash chars back to default", zuid_set_hash_chars(z, 0), ZUID_OK);
	wantCode("precision 2", zuid_set_precision(z, 2), ZUID_ERR_PRECISION);
	wantCode("unknown base", zuid_generate(z, "%d", "hexx", out, sizeof out), ZUID_ERR_UNKNOWN_BASE);
	if (strlen(zuid_last_error(z)) == 0) {
		printf("  unknown base: no error text\n");
		fails++;
	}
	wantCode("short buffer", zuid_generate(z, "%d", "62", out, 6), ZUID_ERR_BUFFER);

	zuid_free(z);
	if (fails) {
		printf("  %d check(s) failed\n", fails);
		return 1;
	}
	return 0;
}
