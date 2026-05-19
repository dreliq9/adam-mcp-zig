//! Output directory helper — implements §2.10 of HOUSE_STYLE.md.
//!
//! Side effects from tools go to `~/<domain>-output/`. This module makes
//! that path discoverable and ensures it exists before tools write to it.

const std = @import("std");

/// Return `$HOME/<name>-output/`, creating it (and any missing parents)
/// if absent. Caller owns the returned slice and must free it.
///
/// PORT-NOTE [equivalent]: Python's `output_dir(name)` returns a
///   `pathlib.Path` and calls `mkdir(parents=True, exist_ok=True)`. Zig
///   returns the resolved path as `[]u8` (the caller owns the allocation)
///   and calls `std.Io.Dir.cwd().makePath(io, ...)` which is similarly
///   idempotent and creates parents. Same behavior, Zig-native return
///   type. Requires an Io because 0.16-stock stripped `std.fs.cwd()` in
///   favour of the async-pluggable `std.Io.Dir` API.
///
/// PORT-NOTE [equivalent]: Python uses `Path.home()`, which reads `HOME`
///   on POSIX and falls back to `pwd`-style lookup. Zig reads `HOME` via
///   libc's `getenv` (`std.c.getenv`), the simplest portable path on
///   macOS/Linux. Returns `error.HomeNotSet` if HOME is missing.
///   PORT-NOTE [deferred-B]: Phase B will plumb `std.process.Environ`
///   through BaseServer so tools don't reach for libc directly.
pub fn outputDir(allocator: std.mem.Allocator, io: std.Io, name: []const u8) ![]u8 {
    const path = try outputDirPath(allocator, name);
    errdefer allocator.free(path);
    try std.Io.Dir.cwd().createDirPath(io, path);
    return path;
}

/// Resolve the `$HOME/<name>-output/` path without creating it.
///
/// PORT-NOTE [n/a-language]: Python returns one pathlib.Path that the
///   caller can stringify or pass to mkdir. Zig separates path
///   resolution from directory creation because Zig's filesystem ops
///   take string paths and explicit allocator-owned strings. This
///   private helper exists so tests can verify path formation without
///   mutating $HOME. Not part of the public 1:1 surface.
fn outputDirPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const home_z = std.c.getenv("HOME") orelse return error.HomeNotSet;
    const home = std.mem.span(home_z);
    const dir_name = try std.fmt.allocPrint(allocator, "{s}-output", .{name});
    defer allocator.free(dir_name);
    return try std.fs.path.join(allocator, &.{ home, dir_name });
}

// =============================================================================
// Tests
// =============================================================================

test "outputDirPath — formats $HOME/<name>-output" {
    const allocator = std.testing.allocator;
    const path = try outputDirPath(allocator, "test-mcp");
    defer allocator.free(path);

    const home_z = std.c.getenv("HOME") orelse return error.HomeNotSet;
    const home = std.mem.span(home_z);
    const expected = try std.fs.path.join(allocator, &.{ home, "test-mcp-output" });
    defer allocator.free(expected);

    try std.testing.expectEqualStrings(expected, path);
}

test "outputDirPath — name with hyphens preserved" {
    const allocator = std.testing.allocator;
    const path = try outputDirPath(allocator, "vulnerability-intelligence");
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, "vulnerability-intelligence-output"));
}
