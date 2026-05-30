//! Server-owned I/O context threaded into tool dispatch.
//! Implements §2.10 (predictable output location) as the dispatch-threading
//! wrapper over output.zig's outputDir/homeDir; closes deferred-B #8
//! (io/output-dir threading) of the Zig port plan.
//!
//! PORT-NOTE [n/a-language]: No Python counterpart — Python tools reach
//!   request context via FastMCP; Context is the Zig-native equivalent that
//!   carries the same capability through explicit threading.

const std = @import("std");
const output = @import("output.zig");

pub const Context = struct {
    io: std.Io,
    environ_map: *const std.process.Environ.Map,

    /// `<home>/<name>-output/`, created if absent. Caller owns the slice.
    pub fn outputDir(self: *const Context, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        return output.outputDir(allocator, self.io, self.environ_map, name);
    }

    /// Cross-platform home dir. Caller owns the slice.
    pub fn home(self: *const Context, allocator: std.mem.Allocator) ![]u8 {
        return output.homeDir(allocator, self.environ_map);
    }
};

// =============================================================================
// Tests
// =============================================================================

fn testEnv(allocator: std.mem.Allocator, fake_home: []const u8) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(allocator);
    errdefer map.deinit();
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    try map.put(var_name, fake_home);
    return map;
}

test "Context.home — delegates to homeDir using the env map" {
    const allocator = std.testing.allocator;
    var env = try testEnv(allocator, "/tmp/ctx-home");
    defer env.deinit();

    // io is unused by home(); a zeroed std.Io is never dereferenced on this path.
    const ctx = Context{ .io = undefined, .environ_map = &env };
    const h = try ctx.home(allocator);
    defer allocator.free(h);

    try std.testing.expectEqualStrings("/tmp/ctx-home", h);
}
