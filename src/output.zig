//! Output directory helper — implements §2.10 of HOUSE_STYLE.md.
//!
//! Side effects from tools go to `<home>/<domain>-output/`. This module
//! makes that path discoverable and ensures it exists before tools
//! write to it. Cross-platform: HOME on POSIX, USERPROFILE on Windows.

const std = @import("std");

/// Return `<home>/<name>-output/`, creating it (and any missing parents)
/// if absent. Caller owns the returned slice and must free it.
///
/// `environ_map` provides the environment; in practice you pass
/// `init.environ_map` from `pub fn main(init: std.process.Init)`. This
/// is the 0.16-idiomatic path — there is no global env accessor.
///
/// PORT-NOTE [equivalent]: Python's `output_dir(name)` returns a
///   `pathlib.Path` and calls `mkdir(parents=True, exist_ok=True)`. Zig
///   returns the resolved path as `[]u8` (the caller owns the allocation)
///   and calls `std.Io.Dir.cwd().createDirPath(io, ...)` which is
///   similarly idempotent and creates parents.
///
/// PORT-NOTE [equivalent]: Python uses `Path.home()`, which reads `HOME`
///   on POSIX and `USERPROFILE` on Windows. Zig mirrors that via
///   `homeDir` below.
pub fn outputDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    name: []const u8,
) ![]u8 {
    const path = try outputDirPath(allocator, environ_map, name);
    errdefer allocator.free(path);
    try std.Io.Dir.cwd().createDirPath(io, path);
    return path;
}

/// Cross-platform user-home directory lookup.
///
/// On POSIX reads `HOME`. On Windows reads `USERPROFILE` (the documented
/// equivalent of `Path.home()`'s Windows behaviour). Caller owns the
/// returned slice.
///
/// `environ_map` should be `init.environ_map` from a Zig 0.16+ main.
/// 0.16 removed global env accessors; the environment is owned by Init.
pub fn homeDir(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
) ![]u8 {
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    const value = environ_map.get(var_name) orelse return error.HomeNotSet;
    return allocator.dupe(u8, value);
}

/// Resolve the home/<name>-output/ path without creating it.
fn outputDirPath(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    name: []const u8,
) ![]u8 {
    const home = try homeDir(allocator, environ_map);
    defer allocator.free(home);
    const dir_name = try std.fmt.allocPrint(allocator, "{s}-output", .{name});
    defer allocator.free(dir_name);
    return try std.fs.path.join(allocator, &.{ home, dir_name });
}

// =============================================================================
// Tests
// =============================================================================

/// Build an Environ.Map with HOME (POSIX) or USERPROFILE (Windows) set
/// to `fake_home`. Caller owns the returned map and must call deinit.
fn testEnv(allocator: std.mem.Allocator, fake_home: []const u8) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(allocator);
    errdefer map.deinit();
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    try map.put(var_name, fake_home);
    return map;
}

test "outputDirPath — formats <home>/<name>-output" {
    const allocator = std.testing.allocator;
    var env = try testEnv(allocator, "/tmp/test-home");
    defer env.deinit();

    const path = try outputDirPath(allocator, &env, "test-mcp");
    defer allocator.free(path);

    const expected = try std.fs.path.join(allocator, &.{ "/tmp/test-home", "test-mcp-output" });
    defer allocator.free(expected);

    try std.testing.expectEqualStrings(expected, path);
}

test "outputDirPath — name with hyphens preserved" {
    const allocator = std.testing.allocator;
    var env = try testEnv(allocator, "/tmp/test-home");
    defer env.deinit();

    const path = try outputDirPath(allocator, &env, "vulnerability-intelligence");
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, "vulnerability-intelligence-output"));
}

test "homeDir — returns error.HomeNotSet on empty env" {
    const allocator = std.testing.allocator;
    var env = std.process.Environ.Map.init(allocator);
    defer env.deinit();
    try std.testing.expectError(error.HomeNotSet, homeDir(allocator, &env));
}
