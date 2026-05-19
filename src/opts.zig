//! Shared invocation options used by wrapper types (validates, requires,
//! passthrough, base_server). Implements parts of §1.3 (`force` override).
//!
//! PORT-NOTE [equivalent]: Python passes `force=True` as a kwarg through
//!   `*args, **kwargs` in each decorator's wrapper. Zig has no kwargs, so
//!   wrapper `call` functions take a `CallOpts` struct as their first
//!   argument. Each wrapper's call signature is uniform —
//!   `fn(opts: CallOpts, alloc, input) ReturnT` — so wrappers compose
//!   cleanly (requires-wraps-validates etc.).

/// Options passed to wrapper `call` functions. Each level may use or
/// forward the values.
pub const CallOpts = struct {
    /// When true, bypass any @requires precondition checks. §1.3 / §6.31.
    force: bool = false,
};
