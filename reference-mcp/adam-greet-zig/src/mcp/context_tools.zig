//! Context tool — multi-source synthesis. Implements §4.18, §1.1.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const types = @import("../types.zig");
const LocalBackend = @import("../backends/local.zig").LocalBackend;

const EmptyInput = struct {};

fn getMorningContextImpl(allocator: std.mem.Allocator, io: std.Io, _: EmptyInput) adam.Result(types.MorningContext) {
    _ = allocator;
    _ = io;
    return adam.Result(types.MorningContext).ok(.{
        .value = .{
            .weather = LocalBackend.getWeather(),
            .next_event = LocalBackend.getNextEvent(),
            .recent_music = LocalBackend.getRecentMusic(),
        },
        .mode_tag = LocalBackend.mode_tag,
    });
}

// PORT-NOTE [equivalent]: Python tools with no validated input simply
//   omit `@validates`. Zig pipelines all inputs through validates() so
//   the registration dispatcher has a uniform shape. EmptyInput is the
//   zero-field model — callers pass `{}` and parsing succeeds.
pub const GetMorningContext = adam.validates(EmptyInput, getMorningContextImpl);
