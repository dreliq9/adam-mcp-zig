//! `adam-mcp new <name>` — scaffold a new Zig MCP project.
//!
//! PORT-NOTE [equivalent]: Python's cmd_new.py uses Jinja2 templates
//!   from `python/templates/_base/`. Zig embeds templates as comptime
//!   string constants in `templates.zig` and writes them through
//!   `std.fs.cwd().writeFile`. Same end result; no template directory
//!   to ship.

const std = @import("std");
const templates = @import("templates.zig");

pub fn scaffold(
    allocator: std.mem.Allocator,
    io: std.Io,
    name: []const u8,
    description: []const u8,
    target_dir: []const u8,
) !void {
    const name_snake = try toSnake(allocator, name);
    defer allocator.free(name_snake);
    const name_pascal = try toPascal(allocator, name);
    defer allocator.free(name_pascal);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, target_dir);

    var dir = try cwd.openDir(io, target_dir, .{});
    defer dir.close(io);

    for (templates.all_templates) |t| {
        const rel_path = try std.mem.replaceOwned(u8, allocator, t.rel_path, "{{name_snake}}", name_snake);
        defer allocator.free(rel_path);

        if (std.fs.path.dirname(rel_path)) |parent| {
            try dir.createDirPath(io, parent);
        }

        const rendered = try templates.render(
            allocator,
            t.contents,
            name,
            name_snake,
            name_pascal,
            description,
        );
        defer allocator.free(rendered);

        var file = try dir.createFile(io, rel_path, .{});
        defer file.close(io);
        var write_buf: [4096]u8 = undefined;
        var file_writer = file.writer(io, &write_buf);
        try file_writer.interface.writeAll(rendered);
        try file_writer.interface.flush();
    }
}

/// "Foo Bar-Baz" -> "foo_bar_baz"
pub fn toSnake(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, name.len);
    var i: usize = 0;
    var last_underscore = true; // skip leading underscores
    for (name) |c| {
        if ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9')) {
            out[i] = c;
            i += 1;
            last_underscore = false;
        } else if (c >= 'A' and c <= 'Z') {
            out[i] = c + 32;
            i += 1;
            last_underscore = false;
        } else {
            if (!last_underscore and i > 0) {
                out[i] = '_';
                i += 1;
                last_underscore = true;
            }
        }
    }
    // strip trailing underscore
    while (i > 0 and out[i - 1] == '_') : (i -= 1) {}
    return allocator.realloc(out, i);
}

/// "foo-bar baz" -> "FooBarBaz"
pub fn toPascal(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, name.len);
    var i: usize = 0;
    var capitalize_next = true;
    for (name) |c| {
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')) {
            if (capitalize_next) {
                if (c >= 'a' and c <= 'z') {
                    out[i] = c - 32;
                } else {
                    out[i] = c;
                }
                capitalize_next = false;
            } else {
                if (c >= 'A' and c <= 'Z') {
                    out[i] = c + 32;
                } else {
                    out[i] = c;
                }
            }
            i += 1;
        } else {
            capitalize_next = true;
        }
    }
    return allocator.realloc(out, i);
}

// =============================================================================
// Tests
// =============================================================================

test "toSnake — basic conversions" {
    const allocator = std.testing.allocator;
    {
        const s = try toSnake(allocator, "foo-bar");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("foo_bar", s);
    }
    {
        const s = try toSnake(allocator, "Foo Bar Baz");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("foo_bar_baz", s);
    }
    {
        const s = try toSnake(allocator, "vulnerability-intelligence");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("vulnerability_intelligence", s);
    }
}

test "toPascal — basic conversions" {
    const allocator = std.testing.allocator;
    {
        const s = try toPascal(allocator, "foo-bar");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("FooBar", s);
    }
    {
        const s = try toPascal(allocator, "adam-greet");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("AdamGreet", s);
    }
}
