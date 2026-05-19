//! Greeting tools — atomic ops. Implements §2.7, §1.1, §1.2, §1.4.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const schema = @import("../schema.zig");
const LocalBackend = @import("../backends/local.zig").LocalBackend;

fn formalityPhrasing(f: u8) []const u8 {
    if (f <= 2) return "yo";
    if (f <= 6) return "hello";
    return "good morning";
}

fn composeGreetingImpl(allocator: std.mem.Allocator, input: schema.GreetingInput) adam.Result([]const u8) {
    const phrase = formalityPhrasing(input.formality);
    const greeting = std.fmt.allocPrint(allocator, "{s}, {s}", .{ phrase, input.name }) catch {
        return adam.Result([]const u8).fail(.{ .hint = "out of memory rendering greeting" });
    };
    return adam.Result([]const u8).ok(.{
        .value = greeting,
        .mode_tag = LocalBackend.mode_tag,
    });
}

fn composePersonalizedImpl(allocator: std.mem.Allocator, input: schema.PersonalizedGreetingInput) adam.Result([]const u8) {
    const greeting = std.fmt.allocPrint(allocator, "hello again, {s}", .{input.name}) catch {
        return adam.Result([]const u8).fail(.{ .hint = "out of memory" });
    };
    return adam.Result([]const u8).ok(.{
        .value = greeting,
        .mode_tag = LocalBackend.mode_tag,
    });
}

pub const ComposeGreeting = adam.validates(schema.GreetingInput, composeGreetingImpl);
pub const ComposePersonalizedGreeting = adam.validates(schema.PersonalizedGreetingInput, composePersonalizedImpl);
