//! `adam-mcp audit <path>` — mechanical conformance check.
//!
//! PORT-NOTE [equivalent]: Python's cmd_audit.py emits a Result-shaped
//!   dict via json.dumps. Zig writes the same JSON shape using
//!   std.json.Stringify. Exit code: 1 if any FAIL, 0 otherwise — same
//!   contract.

const std = @import("std");
const audit_rules = @import("audit_rules.zig");

pub fn auditProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    writer: *std.Io.Writer,
) !u8 {
    var findings = try audit_rules.runAll(allocator, io, project_root);
    defer findings.deinit(allocator);

    var fail_count: usize = 0;
    var warn_count: usize = 0;
    for (findings.items) |f| {
        switch (f.severity) {
            .FAIL => fail_count += 1,
            .WARN => warn_count += 1,
            .OK => {},
        }
    }

    const status_str: []const u8 = if (fail_count > 0) "FAIL" else if (warn_count > 0) "WARN" else "OK";

    var jws: std.json.Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
    try jws.beginObject();
    try jws.objectField("status");
    try jws.write(status_str);
    try jws.objectField("metrics");
    try jws.beginObject();
    try jws.objectField("findings");
    try jws.write(findings.items.len);
    try jws.objectField("fails");
    try jws.write(fail_count);
    try jws.objectField("warns");
    try jws.write(warn_count);
    try jws.endObject();
    try jws.objectField("findings");
    try jws.beginArray();
    for (findings.items) |f| {
        try jws.beginObject();
        try jws.objectField("rule");
        try jws.write(f.rule);
        try jws.objectField("severity");
        try jws.write(@tagName(f.severity));
        try jws.objectField("message");
        try jws.write(f.message);
        try jws.objectField("hint");
        try jws.write(f.hint);
        try jws.endObject();
    }
    try jws.endArray();
    try jws.endObject();
    try writer.writeByte('\n');

    return if (fail_count > 0) 1 else 0;
}
