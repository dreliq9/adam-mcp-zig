//! Workflow — implements §2.8 of HOUSE_STYLE.md.
//!
//! A higher-order tool that orchestrates atomic ops. Workflow definitions
//! live under `<package>/workflows/` per §2.8; the audit rule looks for
//! values of type Workflow to identify them.
//!
//! PORT-NOTE [equivalent]: Python's `workflows.py` defines
//!   `class Workflow(ABC)` with an `@abstractmethod` `run`. Zig has no
//!   ABC/abstract methods; the equivalent contract is structural — a
//!   Workflow value has a non-optional `name` field and a non-optional
//!   `runFn` function pointer, so any instance is guaranteed to satisfy
//!   the contract at construction time (analogous to Python failing at
//!   instantiation if `run` isn't overridden).
//!
//! PORT-NOTE [equivalent]: Python's `run(self, *args, **kwargs) -> Result`
//!   is fully polymorphic in arguments. Zig requires concrete types —
//!   we type-erase input/output through `std.json.Value`, which is the
//!   MCP wire format anyway. Workflows that want typed inputs parse at
//!   the top of `runFn` via `std.json.parseFromValue`. Behavior on the
//!   wire is identical.

const std = @import("std");
const Result = @import("result.zig").Result;

/// Workflow descriptor. Implements §2.8.
///
/// Fields:
///   name:  the workflow's identifier (matches audit lookup).
///   ctx:   opaque pointer to whatever state the workflow needs.
///   runFn: the function that orchestrates atomic ops.
pub const Workflow = struct {
    name: []const u8,
    runFn: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        input: std.json.Value,
    ) anyerror!Result(std.json.Value),
    ctx: *anyopaque,

    pub fn run(
        self: *const Workflow,
        allocator: std.mem.Allocator,
        input: std.json.Value,
    ) anyerror!Result(std.json.Value) {
        return self.runFn(self.ctx, allocator, input);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Workflow — basic run cycle, integer-doubling" {
    const allocator = std.testing.allocator;

    const impl = struct {
        fn run(
            ctx: *anyopaque,
            alloc: std.mem.Allocator,
            input: std.json.Value,
        ) anyerror!Result(std.json.Value) {
            _ = ctx;
            _ = alloc;
            const x = input.integer;
            return Result(std.json.Value).ok(.{
                .value = std.json.Value{ .integer = x * 2 },
            });
        }
    }.run;

    var dummy: u8 = 0;
    const wf = Workflow{
        .name = "double",
        .runFn = impl,
        .ctx = &dummy,
    };

    var r = try wf.run(allocator, std.json.Value{ .integer = 21 });
    defer r.deinit(allocator);

    try std.testing.expectEqualStrings("double", wf.name);
    try std.testing.expectEqual(@as(i64, 42), r.value.?.integer);
}

test "Workflow — runFn can return FAIL with hint" {
    const allocator = std.testing.allocator;

    const impl = struct {
        fn run(
            ctx: *anyopaque,
            alloc: std.mem.Allocator,
            input: std.json.Value,
        ) anyerror!Result(std.json.Value) {
            _ = ctx;
            _ = alloc;
            _ = input;
            return Result(std.json.Value).fail(.{
                .hint = "intentionally broken for test",
            });
        }
    }.run;

    var dummy: u8 = 0;
    const wf = Workflow{
        .name = "always_fails",
        .runFn = impl,
        .ctx = &dummy,
    };

    var r = try wf.run(allocator, std.json.Value{ .null = {} });
    defer r.deinit(allocator);

    try std.testing.expectEqualStrings(
        "intentionally broken for test",
        r.hint.?,
    );
}
