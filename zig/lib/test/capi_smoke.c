/*
	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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

/* Most calls here name only a format and a base. */
static int gen(zuid *z, const char *format, const char *base, char *out, size_t cap) {
	zuid_request req = {0};
	req.format = format;
	req.base = base;
	return zuid_generate(z, &req, out, cap);
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
	wantCode("generate", zuid_generate(z, NULL, out, sizeof out), ZUID_OK);
	want("time, defaults", out, "124Bxg");
	wantCode("generate 32w", gen(z, "%d", "32w", out, sizeof out), ZUID_OK);
	want("time, base 32w", out, "2r8pRr2");

	/* Derived widths, in base 62: hash 8, uuid 22, random 6. Every base gets
	   the width carrying the same strength, not the same symbol count. */
	wantCode("generate %h", gen(z, "%h", NULL, out, sizeof out), ZUID_OK);
	wantLen("host, hashed", out, 8);
	wantCode("generate %g", gen(z, "%g", NULL, out, sizeof out), ZUID_OK);
	wantLen("uuid v4", out, 22);
	wantCode("generate %r", gen(z, "%r", NULL, out, sizeof out), ZUID_OK);
	wantLen("random", out, 6);

	/* Bases whose digits are several bytes each. The clock is the only source
	   this API can pin, so %d is what gets an exact value; %h and %r just have
	   to work, since their widths are in symbols and strlen counts bytes. The
	   vectors cover those two in these bases from both implementations. */
	zuid_set_clock_ms(z, 1785585600000LL);
	wantCode("generate 512tt", gen(z, "%d", "512tt", out, sizeof out), ZUID_OK);
	want("time, base 512tt", out, "Dԋჰ𐀛");
	wantCode("generate 2048tz", gen(z, "%d", "2048tz", out, sizeof out), ZUID_OK);
	want("time, base 2048tz", out, "0主劸𐃃");
	wantCode("truncate in 512tt", gen(z, "%h%r", "512tt", out, sizeof out), ZUID_OK);

	{
		zuid_request req = {0};
		req.format = "%h%r";
		req.hash_chars = 5;
		req.random_chars = 12;
		wantCode("generate resized", zuid_generate(z, &req, out, sizeof out), ZUID_OK);
		wantLen("resized components", out, 17);
	}

	/* Zero is the base's derived default, and nothing carried over. */
	wantCode("generate defaulted", gen(z, "%h%r", NULL, out, sizeof out), ZUID_OK);
	wantLen("defaulted components", out, 14);

	/* Only the hashed names read the salt. */
	{
		char salted[256], unsalted[256], over[ZUID_MAX_SALT_BYTES + 2];
		zuid_request req = {0};
		req.format = "%h";
		wantCode("generate unsalted", zuid_generate(z, &req, unsalted, sizeof unsalted), ZUID_OK);
		req.salt = "pepper";
		wantCode("generate salted", zuid_generate(z, &req, salted, sizeof salted), ZUID_OK);
		if (strcmp(salted, unsalted) == 0) {
			printf("  salted and unsalted host both came out %s\n", salted);
			fails++;
		}
		wantLen("salted host", salted, 8);
		memset(over, 's', sizeof over - 1);
		over[sizeof over - 1] = '\0';
		req.salt = over;
		wantCode("salt over cap", zuid_generate(z, &req, out, sizeof out), ZUID_ERR_OPTION);
	}

	/* Every rejection path the header documents. */
	{
		zuid_request req = {0};
		req.format = "%h";
		req.hash_chars = ZUID_MAX_COMPONENT_CHARS + 1;
		wantCode("hash chars over cap", zuid_generate(z, &req, out, sizeof out), ZUID_ERR_OPTION);
		/* Past what a SHA-256 fills in base 62, which is 43 symbols. */
		req.hash_chars = 44;
		wantCode("hash past the digest", zuid_generate(z, &req, out, sizeof out), ZUID_ERR_OPTION);
		req.format = "%r";
		req.random_chars = ZUID_MAX_COMPONENT_CHARS + 1;
		wantCode("random chars over cap", zuid_generate(z, &req, out, sizeof out), ZUID_ERR_OPTION);
	}
	{
		zuid_request req = {0};
		req.precision = 2;
		wantCode("precision 2", zuid_generate(z, &req, out, sizeof out), ZUID_ERR_PRECISION);
	}
	wantCode("null context", gen(NULL, "%d", "62", out, sizeof out), ZUID_ERR_CONTEXT);
	wantCode("unknown base", gen(z, "%d", "hexx", out, sizeof out), ZUID_ERR_UNKNOWN_BASE);
	if (strlen(zuid_last_error(z)) == 0) {
		printf("  unknown base: no error text\n");
		fails++;
	}
	wantCode("short buffer", gen(z, "%d", "62", out, 6), ZUID_ERR_BUFFER);

	/* The enum is an ABI compiled callers hold, so the codes get pinned from
	   out here too. ZUID_ERR_ENV is absent: it needs a machine that cannot
	   supply a component. */
	wantCode("unknown component", gen(z, "%q", "62", out, sizeof out), ZUID_ERR_BAD_FORMAT);
	wantCode("trailing percent", gen(z, "%d%", "62", out, sizeof out), ZUID_ERR_BAD_FORMAT);
	wantCode("raw-byte base", gen(z, "%d", "bytes", out, sizeof out), ZUID_ERR_BASE_NOT_TEXT);
	zuid_set_clock_ms(z, -1LL);
	wantCode("clock before epoch", gen(z, "%d", "62", out, sizeof out), ZUID_ERR_CLOCK);
	zuid_set_clock_ms(z, 32503680000000000LL);
	wantCode("past the horizon", gen(z, "%d", "62", out, sizeof out), ZUID_ERR_HORIZON);
	zuid_clear_clock(z);

	/* ZUID_ERR_BUFFER used to fire for a fixed 4096-byte buffer inside the
	   module, whatever out_cap said, and it never carried any text. */
	{
		static char big[65536];
		char many[401];
		for (size_t i = 0; i < 200; i++) { many[i * 2] = '%'; many[i * 2 + 1] = 'g'; }
		many[400] = '\0';
		wantCode("200 uuids", gen(z, many, "62", big, sizeof big), ZUID_OK);
		wantLen("200 uuids", big, 200 * 22);

		wantCode("short buffer text", gen(z, "%d", "62", big, 4), ZUID_ERR_BUFFER);
		if (strlen(zuid_last_error(z)) == 0) {
			printf("  short buffer: no error text\n");
			fails++;
		}
	}

	zuid_free(z);
	if (fails) {
		printf("  %d check(s) failed\n", fails);
		return 1;
	}
	return 0;
}
