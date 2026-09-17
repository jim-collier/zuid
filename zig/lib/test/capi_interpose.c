/*
	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
	SPDX-License-Identifier: Apache-2.0

	The shared library used to export every symbol it contained, and only
	eleven of the 834 were ours. ELF resolves a library's own calls through the
	global scope, so a program defining any of the rest took over the calls
	libzuid makes internally - here by defining wasm_config_new, which is the
	first thing zuid_new reaches for.

	Linked against the shared library only. A pass means zuid_new worked and
	this file's wasm_config_new was never reached.
*/

#include <stdio.h>
#include <zuid.h>

static int hijacked = 0;

void *wasm_config_new(void);
void *wasm_config_new(void) {
	hijacked = 1;
	return 0;
}

int main(void) {
	zuid *z = zuid_new();
	if (hijacked) {
		printf("  the library called this program's wasm_config_new\n");
		return 1;
	}
	if (!z) {
		printf("  zuid_new returned NULL\n");
		return 1;
	}

	/* Far enough to have used the runtime, not just allocated the context. */
	char out[256];
	if (zuid_generate(z, "%d", "62", out, sizeof out) != ZUID_OK) {
		printf("  generate failed: %s\n", zuid_last_error(z));
		zuid_free(z);
		return 1;
	}
	zuid_free(z);
	return 0;
}
