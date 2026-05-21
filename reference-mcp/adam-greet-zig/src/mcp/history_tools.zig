//! History tools — stateful. Implements §4.19, §2.10.
//!
//! PORT-NOTE [deferred-B]: Python writes JSON history to
//!   `~/adam-greet-output/history.json` using `output_dir(...)`. The
//!   tool signature now threads `io` (v0.3.0), so the wiring is in
//!   place; the actual file-persistence implementation is still
//!   deferred to Phase B alongside per-request arena ownership.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const schema = @import("../schema.zig");

fn recordGreetingImpl(allocator: std.mem.Allocator, io: std.Io, input: schema.RecordGreetingInput) adam.Result(void) {
    _ = allocator;
    _ = io;
    _ = input;
    // PORT-NOTE [deferred-B]: file persistence still pending; io is now
    //   available via the threaded parameter.
    return adam.Result(void).ok(.{
        .mode_tag = "[LOCAL]",
    });
}

fn recentGreetingsImpl(allocator: std.mem.Allocator, io: std.Io, input: schema.RecentGreetingsInput) adam.Result([]const []const u8) {
    _ = allocator;
    _ = io;
    _ = input;
    // Phase A: returns empty list. Phase B will read from output_dir.
    return adam.Result([]const []const u8).ok(.{
        .value = &.{},
        .mode_tag = "[LOCAL]",
    });
}

pub const RecordGreeting = adam.validates(schema.RecordGreetingInput, recordGreetingImpl);
pub const RecentGreetings = adam.validates(schema.RecentGreetingsInput, recentGreetingsImpl);
