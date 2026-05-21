//! Workflow tools — atomic exposure of higher-order compositions.
//! Implements §2.8, §4.20.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const schema = @import("../schema.zig");
const LocalBackend = @import("../backends/local.zig").LocalBackend;

fn morningBriefingImpl(allocator: std.mem.Allocator, io: std.Io, input: schema.MorningBriefingInput) adam.Result([]const u8) {
    _ = io;
    const weather = LocalBackend.getWeather();
    const next_event = LocalBackend.getNextEvent();

    const briefing = if (next_event) |ev|
        std.fmt.allocPrint(allocator, "Good morning, {s}. It's {d}°C and {s}. Up next: {s}", .{ input.name, weather.temperature_c, weather.condition, ev.title }) catch {
            return adam.Result([]const u8).fail(.{ .hint = "out of memory rendering briefing" });
        }
    else
        std.fmt.allocPrint(allocator, "Good morning, {s}. It's {d}°C and {s}. Nothing on the calendar.", .{ input.name, weather.temperature_c, weather.condition }) catch {
            return adam.Result([]const u8).fail(.{ .hint = "out of memory rendering briefing" });
        };

    var metrics: std.StringHashMapUnmanaged(std.json.Value) = .empty;
    metrics.put(allocator, "steps", .{ .integer = 4 }) catch {};

    return adam.Result([]const u8).ok(.{
        .value = briefing,
        .metrics = metrics,
        .mode_tag = LocalBackend.mode_tag,
    });
}

pub const MorningBriefing = adam.validates(schema.MorningBriefingInput, morningBriefingImpl);
