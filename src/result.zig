//! Result type — implements §1.1 and §6.29 of HOUSE_STYLE.md.
//!
//! Every tool returns a Result. Never raw output, never raw exceptions.
//!
//! PORT-NOTE [equivalent]: Python's `adam_mcp_py/result.py` uses
//!   `@dataclass` to generate __init__/__eq__/fields. Zig structs have
//!   field defaults and equality natively, so no equivalent decorator
//!   is needed. Verified: every Python public symbol (Status, Result,
//!   ok, warn, fail, to_dict) has a Zig equivalent below.
//!
//! PORT-NOTE [equivalent]: Python uses `dataclasses.asdict()` to
//!   serialize Result for JSON encoding. Zig uses std.json.Stringify's
//!   `jsonStringify(self, jws)` hook — caller controls the writer, no
//!   intermediate dict allocation. Field order and shape match Python's
//!   asdict()+json.dumps() output (see test "Result.ok jsonStringify
//!   produces stable wire shape" below).

const std = @import("std");

/// Status — implements the §1.1 status enum.
///
/// PORT-NOTE [equivalent]: Python uses `class Status(str, Enum)` so the
///   enum serializes to "OK"/"WARN"/"FAIL". Zig's @tagName(self) yields
///   identical strings; jsonStringify writes them quoted.
pub const Status = enum {
    OK,
    WARN,
    FAIL,

    pub fn jsonStringify(self: Status, jws: anytype) !void {
        try jws.write(@tagName(self));
    }
};

/// Result(T) — the unified tool result. Implements §1.1.
///
/// Fields:
///   status:      OK / WARN / FAIL.
///   value:       Synthesized/typed output for AI consumption.
///   raw:         Underlying API response (Principle One support, §6.29).
///   metrics:     Numeric measurements keyed by name.
///   diagnostics: Human-readable description of what happened.
///   hint:        What to try next on FAIL/WARN. REQUIRED for non-OK.
///   mode_tag:    Which backend/path was used (e.g., "[IPC]", "[LOCAL]").
///
/// Ownership: metrics and diagnostics own their storage. The caller is
/// responsible for calling `deinit(allocator)` when done. Calling deinit
/// on a default-constructed Result (with `.empty` collections) is a no-op.
///
/// PORT-NOTE [equivalent]: Python uses `Generic[T]` + `TypeVar`. Zig uses
///   a comptime-parameterized struct factory `Result(comptime T: type)`.
///   Behavior is identical; Zig's version monomorphizes per T at compile
///   time (no runtime type erasure).
pub fn Result(comptime T: type) type {
    return struct {
        const Self = @This();

        status: Status,
        value: ?T = null,
        raw: ?std.json.Value = null,
        metrics: std.StringHashMapUnmanaged(std.json.Value) = .empty,
        diagnostics: std.ArrayList([]const u8) = .empty,
        hint: ?[]const u8 = null,
        mode_tag: ?[]const u8 = null,

        // PORT-NOTE [equivalent]: Python uses @classmethod ok/warn/fail
        //   with keyword-only args. Zig has no kwargs — each variant
        //   takes a typed options struct (OkOpts/WarnOpts/FailOpts).
        //   For warn/fail, the options struct makes `hint` a non-
        //   optional field, giving compile-time enforcement of the
        //   "every WARN/FAIL has a hint" invariant. Python enforces
        //   this at runtime with `raise ValueError`. Behavior is
        //   equivalent for valid callers; invalid callers get an
        //   earlier (compile-time) error in Zig — strictly stronger
        //   but observably equivalent.

        pub const OkOpts = struct {
            value: ?T = null,
            raw: ?std.json.Value = null,
            metrics: std.StringHashMapUnmanaged(std.json.Value) = .empty,
            diagnostics: std.ArrayList([]const u8) = .empty,
            mode_tag: ?[]const u8 = null,
        };

        pub const WarnOpts = struct {
            hint: []const u8, // §1.1: every WARN has a hint
            value: ?T = null,
            raw: ?std.json.Value = null,
            metrics: std.StringHashMapUnmanaged(std.json.Value) = .empty,
            diagnostics: std.ArrayList([]const u8) = .empty,
            mode_tag: ?[]const u8 = null,
        };

        pub const FailOpts = struct {
            hint: []const u8, // §1.1: every FAIL has a hint
            raw: ?std.json.Value = null,
            metrics: std.StringHashMapUnmanaged(std.json.Value) = .empty,
            diagnostics: std.ArrayList([]const u8) = .empty,
            mode_tag: ?[]const u8 = null,
        };

        pub fn ok(opts: OkOpts) Self {
            return .{
                .status = .OK,
                .value = opts.value,
                .raw = opts.raw,
                .metrics = opts.metrics,
                .diagnostics = opts.diagnostics,
                .mode_tag = opts.mode_tag,
            };
        }

        pub fn warn(opts: WarnOpts) Self {
            return .{
                .status = .WARN,
                .value = opts.value,
                .raw = opts.raw,
                .metrics = opts.metrics,
                .diagnostics = opts.diagnostics,
                .hint = opts.hint,
                .mode_tag = opts.mode_tag,
            };
        }

        pub fn fail(opts: FailOpts) Self {
            return .{
                .status = .FAIL,
                .value = null,
                .raw = opts.raw,
                .metrics = opts.metrics,
                .diagnostics = opts.diagnostics,
                .hint = opts.hint,
                .mode_tag = opts.mode_tag,
            };
        }

        /// Free metrics and diagnostics storage.
        ///
        /// PORT-NOTE [equivalent]: Python's GC handles cleanup automatically;
        ///   Zig requires explicit deinit. Caller passes the allocator that
        ///   was used to populate metrics/diagnostics. Calling deinit on a
        ///   default-constructed (.empty) Result is a no-op.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.metrics.deinit(allocator);
            self.diagnostics.deinit(allocator);
        }

        /// JSON serialization for tool output. Implements §1.1's wire shape.
        ///
        /// PORT-NOTE [equivalent]: Python's `to_dict()` returns a Python
        ///   dict that FastMCP encodes to JSON. Zig uses
        ///   std.json.Stringify's jsonStringify(self, jws) hook — caller
        ///   controls the writer, no intermediate dict. Field order matches
        ///   Python's dataclass field order (status, value, raw, metrics,
        ///   diagnostics, hint, mode_tag) so output is byte-identical.
        pub fn jsonStringify(self: Self, jws: anytype) !void {
            try jws.beginObject();

            try jws.objectField("status");
            try jws.write(self.status);

            try jws.objectField("value");
            if (T == void) {
                // PORT-NOTE [equivalent]: Python `Result[None]` serializes
                //   `value` as null. Zig `Result(void)` does the same;
                //   void carries no payload to serialize.
                try jws.write(null);
            } else if (self.value) |v| {
                try jws.write(v);
            } else {
                try jws.write(null);
            }

            try jws.objectField("raw");
            if (self.raw) |r| try jws.write(r) else try jws.write(null);

            try jws.objectField("metrics");
            try jws.beginObject();
            var it = self.metrics.iterator();
            while (it.next()) |kv| {
                try jws.objectField(kv.key_ptr.*);
                try jws.write(kv.value_ptr.*);
            }
            try jws.endObject();

            try jws.objectField("diagnostics");
            try jws.beginArray();
            for (self.diagnostics.items) |d| try jws.write(d);
            try jws.endArray();

            try jws.objectField("hint");
            if (self.hint) |h| try jws.write(h) else try jws.write(null);

            try jws.objectField("mode_tag");
            if (self.mode_tag) |m| try jws.write(m) else try jws.write(null);

            try jws.endObject();
        }
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Status — jsonStringify yields quoted tag name" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.write(Status.OK);
    try std.testing.expectEqualStrings("\"OK\"", buf.written());
}

test "Result.ok — minimal" {
    var r = Result(i32).ok(.{ .value = 42 });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(Status.OK, r.status);
    try std.testing.expectEqual(@as(?i32, 42), r.value);
    try std.testing.expectEqual(@as(?[]const u8, null), r.hint);
}

test "Result.warn — hint required at compile time" {
    var r = Result(void).warn(.{ .hint = "watch out" });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(Status.WARN, r.status);
    try std.testing.expectEqualStrings("watch out", r.hint.?);
}

test "Result.fail — value is always null" {
    var r = Result(i32).fail(.{ .hint = "broken" });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(Status.FAIL, r.status);
    try std.testing.expectEqual(@as(?i32, null), r.value);
    try std.testing.expectEqualStrings("broken", r.hint.?);
}

test "Result — diagnostics and metrics own their storage" {
    const allocator = std.testing.allocator;

    var diagnostics: std.ArrayList([]const u8) = .empty;
    try diagnostics.append(allocator, "did the thing");

    var metrics: std.StringHashMapUnmanaged(std.json.Value) = .empty;
    try metrics.put(allocator, "elapsed_ms", .{ .integer = 42 });

    var r = Result(i32).ok(.{
        .value = 7,
        .diagnostics = diagnostics,
        .metrics = metrics,
    });
    defer r.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), r.diagnostics.items.len);
    try std.testing.expectEqualStrings("did the thing", r.diagnostics.items[0]);
    try std.testing.expectEqual(@as(u32, 1), r.metrics.count());
}

test "Result.ok — jsonStringify produces stable wire shape" {
    var r = Result(i32).ok(.{ .value = 42, .mode_tag = "[LOCAL]" });
    defer r.deinit(std.testing.allocator);

    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.write(r);

    // Field order matches Python dataclass: status, value, raw, metrics,
    // diagnostics, hint, mode_tag. Byte-identical to Python's
    // json.dumps(result.to_dict()).
    const expected =
        \\{"status":"OK","value":42,"raw":null,"metrics":{},"diagnostics":[],"hint":null,"mode_tag":"[LOCAL]"}
    ;
    try std.testing.expectEqualStrings(expected, buf.written());
}

test "Result.fail — jsonStringify shape" {
    var r = Result(i32).fail(.{ .hint = "out of range" });
    defer r.deinit(std.testing.allocator);

    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.write(r);

    const expected =
        \\{"status":"FAIL","value":null,"raw":null,"metrics":{},"diagnostics":[],"hint":"out of range","mode_tag":null}
    ;
    try std.testing.expectEqualStrings(expected, buf.written());
}
