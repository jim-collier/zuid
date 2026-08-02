// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Library surface for Zig callers, the CLI included. C callers get the same
//! functionality through capi.zig and zuid.h instead.

pub const core = @import("core.zig");
pub const host = @import("host.zig");
pub const env = @import("env.zig");
pub const clock = @import("clock.zig");

pub const version = core.version;
