/*
	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
	Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
		https://spdx.org/licenses/Apache-2.0.html
	SPDX-License-Identifier: Apache-2.0

	What env.zig sees of libc, translated by build.zig.
*/

#include <stdlib.h>
#include <unistd.h>
#include <pwd.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <net/if.h>
#if defined(__linux__)
#include <netpacket/packet.h>
#elif defined(__APPLE__)
#include <net/if_dl.h>
/* unistd.h has getentropy on Linux only. */
#include <sys/random.h>
#endif
