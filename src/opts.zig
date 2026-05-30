//! Shared invocation options used by wrapper types (validates, requires,
//! passthrough, base_server). Implements parts of §1.3 (`force` override).
//!
//! PORT-NOTE [equivalent]: Python passes `force=True` as a kwarg through
//!   `*args, **kwargs` in each decorator's wrapper. Zig has no kwargs, so
//!   wrapper `call` functions take a `CallOpts` struct as their first
//!   argument. Each wrapper's call signature is uniform —
//!   `fn(opts: CallOpts, alloc, input) ReturnT` — so wrappers compose
//!   cleanly (requires-wraps-validates etc.).

const Context = @import("context.zig").Context;

/// Options passed to wrapper `call` functions. Each level may use or
/// forward the values.
pub const CallOpts = struct {
    /// When true, bypass any @requires precondition checks. §1.3 / §6.31.
    force: bool = false,
    /// Server-owned I/O context. Null for pure-compute tools and for
    /// in-process unit tests that call a wrapper directly. Threaded in by
    /// BaseServer.run(); see context.zig. PORT-NOTE [equivalent]: Python
    /// tools reach request context via FastMCP; Zig threads it explicitly.
    ctx: ?*Context = null,
};

const std = @import("std");

test "CallOpts — ctx defaults to null" {
    const opts = CallOpts{};
    try std.testing.expect(opts.ctx == null);
    try std.testing.expect(opts.force == false);
}
