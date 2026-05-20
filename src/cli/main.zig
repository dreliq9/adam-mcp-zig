//! `adam-mcp` CLI entrypoint. Implements `new`, `audit`.
//!
//! PORT-NOTE [equivalent]: Python uses Typer for arg parsing. Zig uses
//!   hand-rolled argv parsing — the surface is small (2 commands) and
//!   adding a dep just for this isn't worth it. Error UX matches
//!   Python: missing args print usage and exit 1.
//!
//! PORT-NOTE [deferred-B]: Python CLI also exposes `upgrade` and
//!   `audit --self-check`. Both deferred to Phase B — `upgrade` needs
//!   a dependency-bump system that doesn't exist yet in Zig, and
//!   `--self-check` requires markdown parsing of HOUSE_STYLE.md cross-
//!   links.

const std = @import("std");

const cmd_new = @import("cmd_new.zig");
const cmd_audit = @import("cmd_audit.zig");
const templates = @import("templates.zig");
const audit_rules = @import("audit_rules.zig");

const usage_text =
    \\adam-mcp — scaffolding and audit for Adam-style MCPs.
    \\
    \\Usage:
    \\  adam-mcp new <name> [--description "..."] [--target <path>]
    \\  adam-mcp audit [<path>]
    \\
    \\Commands:
    \\  new       Scaffold a new MCP project from the _base template.
    \\  audit     Mechanical conformance check vs HOUSE_STYLE.md.
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    // Args.toSlice gives cross-platform WTF-8 strings on Windows and
    // opaque bytes on POSIX. Avoids Windows's UTF-16 native argv.
    // PORT-NOTE [equivalent]: 0.16 dropped global argv access; Args is
    //   owned by Init and reached via init.minimal.args.
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buf: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    defer stdout.interface.flush() catch {};

    var stderr_buf: [4 * 1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buf);
    defer stderr.interface.flush() catch {};

    if (args.len < 2) {
        try stderr.interface.writeAll(usage_text);
        return 1;
    }

    const sub = args[1];

    if (std.mem.eql(u8, sub, "new")) {
        return try runNew(gpa, io, init.environ_map, args[2..], &stderr.interface);
    } else if (std.mem.eql(u8, sub, "audit")) {
        return try runAudit(gpa, io, args[2..], &stdout.interface, &stderr.interface);
    } else if (std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
        try stdout.interface.writeAll(usage_text);
        return 0;
    } else {
        try stderr.interface.print("unknown subcommand: {s}\n\n", .{sub});
        try stderr.interface.writeAll(usage_text);
        return 1;
    }
}

fn runNew(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stderr: *std.Io.Writer,
) !u8 {
    if (args.len < 1) {
        try stderr.writeAll("adam-mcp new: missing <name>\n");
        return 1;
    }
    const name: []const u8 = args[0];
    var description: []const u8 = "New MCP";
    var target: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg: []const u8 = args[i];
        if (std.mem.eql(u8, arg, "--description")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("--description requires a value\n");
                return 1;
            }
            description = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--target")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("--target requires a value\n");
                return 1;
            }
            target = args[i + 1];
            i += 1;
        }
    }

    const name_snake = try cmd_new.toSnake(gpa, name);
    defer gpa.free(name_snake);

    const target_dir = target orelse blk: {
        const home = try @import("adam_mcp_zig").homeDir(gpa, environ_map);
        defer gpa.free(home);
        break :blk try std.fs.path.join(gpa, &.{ home, "Projects", name });
    };
    defer if (target == null) gpa.free(target_dir);

    cmd_new.scaffold(gpa, io, name, description, target_dir) catch |err| {
        try stderr.print("scaffold failed: {s}\n", .{@errorName(err)});
        return 1;
    };

    try stderr.print("OK: scaffolded {s} at {s}\n", .{ name, target_dir });
    try stderr.print("hint: cd {s} && zig build test\n", .{target_dir});
    return 0;
}

fn runAudit(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    _ = stderr;
    var path: []const u8 = ".";
    for (args) |arg| {
        if (arg.len > 0 and arg[0] != '-') {
            path = arg;
            break;
        }
    }
    return try cmd_audit.auditProject(gpa, io, path, stdout);
}

// =============================================================================
// Tests
// =============================================================================

test {
    _ = cmd_new;
    _ = cmd_audit;
    _ = templates;
    _ = audit_rules;
}
