//! Guardrail wrapper — implements §1.3 and §6.31 of HOUSE_STYLE.md.
//!
//! `requires(precondition, fail_hint, severity, fn_impl)` returns a
//! wrapper that checks the precondition before invoking fn_impl. Default
//! severity is WARN (informational); FAIL only when the consequence is
//! genuinely destructive. The `force` field on CallOpts bypasses the
//! check.
//!
//! PORT-NOTE [equivalent]: Python's `@requires(...)` decorator wraps a
//!   function and accepts `force=True` as a kwarg. Zig has no kwargs —
//!   `force` lives on the `CallOpts` struct passed as the wrapper's
//!   first argument. Behavior is identical: when force is true OR the
//!   precondition returns true, fn_impl is invoked; otherwise a WARN or
//!   FAIL Result is returned with the fail_hint.
//!
//! PORT-NOTE [equivalent]: Python uses `precondition.__name__` in the
//!   diagnostic ("precondition failed: foo"). Zig function pointers have
//!   no __name__. We emit a generic "precondition failed" diagnostic;
//!   the actionable detail lives in fail_hint, which is required.
//!
//! PORT-NOTE [equivalent]: Python's @requires accepts functions of any
//!   arity via *args, **kwargs. Zig version constrains the wrapped
//!   function to `fn(Allocator, InputT) Result(OutputT)` (the same shape
//!   validates produces). Tools needing zero or multi-arg signatures
//!   refactor into struct-input shape — which is house-style anyway,
//!   since validates already enforces it.

const std = @import("std");
const Result = @import("result.zig").Result;
const CallOpts = @import("opts.zig").CallOpts;

pub const Severity = enum { WARN, FAIL };

/// Guard a tool with a precondition. Implements §1.3, §6.31.
///
/// `precondition` must be a `fn() bool`. `fail_hint` is the actionable
/// hint emitted when the precondition is not satisfied (and force is
/// not set). `severity` defaults to WARN; use FAIL only for genuinely
/// destructive operations per §1.3.
pub fn requires(
    comptime precondition: *const fn () bool,
    comptime fail_hint: []const u8,
    comptime severity: Severity,
    comptime fn_impl: anytype,
) type {
    const FnInfo = @typeInfo(@TypeOf(fn_impl)).@"fn";
    const ReturnT = FnInfo.return_type.?;
    const InputT = FnInfo.params[1].type.?;

    return struct {
        pub const adam_mcp_severity = severity;
        pub const adam_mcp_fail_hint: []const u8 = fail_hint;

        pub fn call(
            opts: CallOpts,
            allocator: std.mem.Allocator,
            input: InputT,
        ) ReturnT {
            if (opts.force or precondition()) {
                return fn_impl(allocator, input);
            }
            switch (severity) {
                .FAIL => return ReturnT.fail(.{ .hint = fail_hint }),
                .WARN => return ReturnT.warn(.{ .hint = fail_hint }),
            }
        }
    };
}

// =============================================================================
// Tests
// =============================================================================

const PassValue = struct { n: i32 };

fn always_true() bool {
    return true;
}

fn always_false() bool {
    return false;
}

fn impl_identity(allocator: std.mem.Allocator, in: PassValue) Result(i32) {
    _ = allocator;
    return Result(i32).ok(.{ .value = in.n });
}

test "requires — precondition true, inner is invoked" {
    const Wrapped = requires(always_true, "should not see this", .WARN, impl_identity);
    var r = Wrapped.call(.{}, std.testing.allocator, .{ .n = 42 });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?i32, 42), r.value);
}

test "requires — precondition false + severity WARN returns WARN with hint" {
    const Wrapped = requires(always_false, "do the X first", .WARN, impl_identity);
    var r = Wrapped.call(.{}, std.testing.allocator, .{ .n = 1 });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(.WARN, @as(@TypeOf(r.status), r.status));
    try std.testing.expectEqualStrings("do the X first", r.hint.?);
    try std.testing.expectEqual(@as(?i32, null), r.value);
}

test "requires — precondition false + severity FAIL returns FAIL with hint" {
    const Wrapped = requires(always_false, "destructive: locked", .FAIL, impl_identity);
    var r = Wrapped.call(.{}, std.testing.allocator, .{ .n = 1 });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(.FAIL, @as(@TypeOf(r.status), r.status));
    try std.testing.expectEqualStrings("destructive: locked", r.hint.?);
}

test "requires — force=true bypasses precondition" {
    const Wrapped = requires(always_false, "blocked", .FAIL, impl_identity);
    var r = Wrapped.call(.{ .force = true }, std.testing.allocator, .{ .n = 99 });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?i32, 99), r.value);
}

test "requires — exposes severity and fail_hint markers" {
    const Wrapped = requires(always_true, "x", .FAIL, impl_identity);
    try std.testing.expectEqual(Severity.FAIL, Wrapped.adam_mcp_severity);
    try std.testing.expectEqualStrings("x", Wrapped.adam_mcp_fail_hint);
}
