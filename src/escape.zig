//! Escape-hatch marker — implements §6.30 of HOUSE_STYLE.md.
//!
//! Every MCP must have exactly one @passthrough-marked tool. The audit
//! CLI enforces this; the marker mechanism here is how the audit
//! identifies the passthrough tool.
//!
//! PORT-NOTE [equivalent]: Python's `escape.py` uses
//!   `setattr(fn, "__adam_mcp_passthrough__", True)` to attach a marker
//!   directly to the function object, then reads it back with `getattr`.
//!   Zig functions have no per-function metadata — function pointers are
//!   addresses, not objects with attributes. The Zig analog wraps the
//!   function in a comptime struct type carrying both the function as a
//!   `pub const call = fn_impl;` declaration and a marker
//!   `pub const adam_mcp_passthrough_marker = true;`. `isPassthrough(T)`
//!   uses `@hasDecl` to detect the marker. Behaviorally identical: "this
//!   function is the documented escape hatch" travels with the value the
//!   registration system holds.

const std = @import("std");

/// Mark a function as the MCP's documented escape hatch. Implements §6.30.
///
/// Wraps the given function in a comptime type that carries:
///   - `call` — the function itself, callable as `Foo.call(args)`
///   - `adam_mcp_passthrough_marker` — the marker declaration
///
/// Usage:
///   const run_engine_script = passthrough(struct {
///       fn impl(input: ScriptInput) Result(ScriptOutput) { ... }
///   }.impl);
///
/// PORT-NOTE [equivalent]: Python's `@passthrough` decorator returns the
///   function unchanged after side-band attribute attachment. Zig returns
///   a wrapper type because comptime decls require a type. Caller code
///   reads it via `MyPassthrough.call(...)`. The audit rule §6.30 looks
///   for `isPassthrough(...)` returning true on registered tools.
pub fn passthrough(comptime fn_or_struct: anytype) type {
    const info = @typeInfo(@TypeOf(fn_or_struct));
    return struct {
        pub const adam_mcp_passthrough_marker = true;
        // PORT-NOTE [equivalent]: Python's @passthrough decorates a
        //   function directly. Zig callers may pass either a function
        //   value or a struct type with a `pub fn call` declaration
        //   (the shape produced by validates/requires). We detect via
        //   @typeInfo and route accordingly so passthrough composes
        //   with the other wrappers.
        pub const call = switch (info) {
            .@"fn" => fn_or_struct,
            else => fn_or_struct.call,
        };
    };
}

/// Return true if T was constructed by `passthrough(...)`. Helper for §6.30.
///
/// PORT-NOTE [equivalent]: Python's `is_passthrough(fn)` reads
///   `getattr(fn, "__adam_mcp_passthrough__", False)` at runtime. Zig's
///   check happens at comptime via `@hasDecl`, which is strictly stronger
///   (zero runtime cost, errors caught at compile time) but observably
///   the same: marked → true, unmarked → false.
pub fn isPassthrough(comptime T: type) bool {
    return @hasDecl(T, "adam_mcp_passthrough_marker");
}

// =============================================================================
// Tests
// =============================================================================

test "passthrough — marker is detected on wrapped function" {
    const Marked = passthrough(struct {
        fn impl(x: i32) i32 {
            return x * 2;
        }
    }.impl);
    try std.testing.expect(isPassthrough(Marked));
    try std.testing.expectEqual(@as(i32, 42), Marked.call(21));
}

test "isPassthrough — false for plain struct without marker" {
    const Plain = struct {
        fn impl(x: i32) i32 {
            return x;
        }
    };
    try std.testing.expect(!isPassthrough(Plain));
}

test "passthrough — call signature is preserved" {
    const Echo = passthrough(struct {
        fn impl(s: []const u8) []const u8 {
            return s;
        }
    }.impl);
    try std.testing.expect(isPassthrough(Echo));
    try std.testing.expectEqualStrings("hello", Echo.call("hello"));
}
