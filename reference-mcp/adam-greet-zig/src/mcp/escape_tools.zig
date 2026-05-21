//! Escape-hatch tool — Principle One. Implements §6.30.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const schema = @import("../schema.zig");

fn rawGreetingImpl(allocator: std.mem.Allocator, io: std.Io, input: schema.RawGreetingInput) adam.Result([]const u8) {
    _ = allocator;
    _ = io;
    return adam.Result([]const u8).ok(.{
        .value = input.template,
        .mode_tag = "[LOCAL]",
    });
}

const _validated = adam.validates(schema.RawGreetingInput, rawGreetingImpl);
pub const ComposeRawGreeting = adam.passthrough(_validated);
