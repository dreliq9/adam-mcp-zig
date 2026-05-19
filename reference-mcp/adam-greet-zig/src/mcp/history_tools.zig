//! History tools — stateful. Implements §4.19, §2.10.
//!
//! PORT-NOTE [deferred-B]: Python writes JSON history to
//!   `~/adam-greet-output/history.json` using `output_dir(...)`. The
//!   Zig equivalent would call `adam.outputDir(allocator, io, "adam-greet")`
//!   — but the current tool signature `fn(Allocator, InputT) Result(T)`
//!   doesn't thread `io` through. Phase A returns a stub that doesn't
//!   persist; Phase B will widen the tool signature or wire io via a
//!   server-attached context so stateful tools work end-to-end.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const schema = @import("../schema.zig");

fn recordGreetingImpl(allocator: std.mem.Allocator, input: schema.RecordGreetingInput) adam.Result(void) {
    _ = allocator;
    _ = input;
    // PORT-NOTE [deferred-B]: file persistence pending io threading.
    return adam.Result(void).ok(.{
        .mode_tag = "[LOCAL]",
    });
}

fn recentGreetingsImpl(allocator: std.mem.Allocator, input: schema.RecentGreetingsInput) adam.Result([]const []const u8) {
    _ = allocator;
    _ = input;
    // Phase A: returns empty list. Phase B will read from output_dir.
    return adam.Result([]const []const u8).ok(.{
        .value = &.{},
        .mode_tag = "[LOCAL]",
    });
}

pub const RecordGreeting = adam.validates(schema.RecordGreetingInput, recordGreetingImpl);
pub const RecentGreetings = adam.validates(schema.RecentGreetingsInput, recentGreetingsImpl);
