//! Pluggable backend protocol — implements §2.6 of HOUSE_STYLE.md.
//!
//! When an MCP wraps an underlying engine that has multiple modes (IPC
//! vs file vs local vs web), expose them as `Backend` values and let
//! the tool layer call `detectBackend(...)` to pick the first available
//! one. The chosen backend's `mode_tag` is then set on Result.mode_tag
//! so the agent sees which path was used (§1.4).
//!
//! PORT-NOTE [equivalent]: Python uses `typing.Protocol` with
//!   `@runtime_checkable` to declare a structural interface. Zig has no
//!   Protocol — we use an explicit vtable struct with `mode_tag`,
//!   `available`, and a `callFn` function pointer. Backend
//!   implementations construct a `Backend` value whose `callFn` points
//!   to their concrete dispatch function and whose `ctx` points to
//!   their state. Behavior is identical; the vtable is more verbose at
//!   construction but cheaper at call sites (no isinstance check).
//!
//! PORT-NOTE [equivalent]: Python's BackendProtocol.call takes
//!   `payload: dict` and returns `dict`. Zig uses `std.json.Value` for
//!   both, which is the typed equivalent and matches the MCP wire
//!   format.

const std = @import("std");

/// Backend handle. Implements §2.6.
///
/// Fields:
///   mode_tag: short identifier set on Result.mode_tag when this
///             backend is chosen (e.g., "[LOCAL]", "[IPC]", "[FILE]").
///   available: true if this backend can serve requests right now.
///              May be evaluated at construction or refreshed by the
///              owning code between detectBackend calls.
///   ctx: opaque pointer to backend state (sockets, file handles, …).
///   callFn: dispatch function, receives ctx + payload, returns result
///           payload or error.
pub const Backend = struct {
    mode_tag: []const u8,
    available: bool,
    ctx: *anyopaque,
    callFn: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        payload: std.json.Value,
    ) anyerror!std.json.Value,

    pub fn call(
        self: *const Backend,
        allocator: std.mem.Allocator,
        payload: std.json.Value,
    ) anyerror!std.json.Value {
        return self.callFn(self.ctx, allocator, payload);
    }
};

/// Return a pointer to the first available backend, or null. Helper for §2.6.
///
/// PORT-NOTE [equivalent]: Python returns the backend value (or None).
///   Zig returns a `*const Backend` pointing into the caller's slice
///   to avoid copying. Caller must keep the slice alive for as long as
///   they hold the returned pointer. Semantics are identical: first
///   available wins, none → null.
pub fn detectBackend(backends: []const Backend) ?*const Backend {
    for (backends) |*b| {
        if (b.available) return b;
    }
    return null;
}

// =============================================================================
// Tests
// =============================================================================

fn unreachable_call(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    payload: std.json.Value,
) anyerror!std.json.Value {
    _ = ctx;
    _ = allocator;
    _ = payload;
    return error.UnreachableBackend;
}

fn echo_call(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    payload: std.json.Value,
) anyerror!std.json.Value {
    _ = ctx;
    _ = allocator;
    return payload;
}

test "detectBackend — empty slice returns null" {
    const result = detectBackend(&.{});
    try std.testing.expect(result == null);
}

test "detectBackend — returns first available" {
    var dummy: u8 = 0;
    const backends = [_]Backend{
        .{
            .mode_tag = "[IPC]",
            .available = false,
            .ctx = &dummy,
            .callFn = unreachable_call,
        },
        .{
            .mode_tag = "[LOCAL]",
            .available = true,
            .ctx = &dummy,
            .callFn = echo_call,
        },
        .{
            .mode_tag = "[WEB]",
            .available = true, // would also match but LOCAL wins
            .ctx = &dummy,
            .callFn = unreachable_call,
        },
    };
    const picked = detectBackend(&backends) orelse return error.NoBackend;
    try std.testing.expectEqualStrings("[LOCAL]", picked.mode_tag);
}

test "detectBackend — all unavailable returns null" {
    var dummy: u8 = 0;
    const backends = [_]Backend{
        .{ .mode_tag = "[A]", .available = false, .ctx = &dummy, .callFn = unreachable_call },
        .{ .mode_tag = "[B]", .available = false, .ctx = &dummy, .callFn = unreachable_call },
    };
    try std.testing.expect(detectBackend(&backends) == null);
}

test "Backend.call — dispatches to callFn" {
    var dummy: u8 = 0;
    const b = Backend{
        .mode_tag = "[ECHO]",
        .available = true,
        .ctx = &dummy,
        .callFn = echo_call,
    };
    const payload = std.json.Value{ .integer = 42 };
    const got = try b.call(std.testing.allocator, payload);
    try std.testing.expectEqual(@as(i64, 42), got.integer);
}
