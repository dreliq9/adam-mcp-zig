//! BaseServer — house-style MCP server. Implements parts of §1.1, §1.4,
//! §2.5, plus the JSON-RPC transport layer that lives in this SDK
//! (rather than a separate FastMCP dependency).
//!
//! Tools are registered at runtime via `registerTool(...)`. Each
//! registration takes a comptime ToolType — the wrapper produced by
//! `validates(...)`, `requires(...)`, or `passthrough(...)`, or a plain
//! struct with the same shape. The server synthesizes a type-erased
//! dispatcher that calls `ToolType.call(opts, allocator, json_value)`
//! and serializes the returned Result into the MCP `tools/call`
//! response envelope.
//!
//! PORT-NOTE [equivalent]: Python's BaseServer wraps FastMCP — the
//!   wire layer is somebody else's library. Zig BaseServer IS the wire
//!   layer (per locked decision 1: hand-roll JSON-RPC, see
//!   [[lightpanda-zig-mcp-comparator]]). The public surface
//!   (init/tool-registration/run) matches Python; the private
//!   handleMessage method is exposed for in-process testing without
//!   spinning up stdio.
//!
//! PORT-NOTE [equivalent]: Python's `_wrap_tool` catches Python
//!   exceptions and coerces non-Result returns to Result.fail. Zig's
//!   type system enforces Result return at compile time (the dispatcher
//!   requires `ToolType.call(...)` to produce a `Result(T)`), so
//!   non-Result returns are impossible. Tool errors that propagate
//!   through Zig error unions are caught in the dispatcher and
//!   converted to Result.fail, matching Python's behavior.
//!
//! PORT-NOTE [equivalent]: Python configures a stderr-only logging
//!   handler so the JSON-RPC stdout stream stays clean. Zig's
//!   `std.log` writes to stderr by default; we use it as-is. Same
//!   end result: stdout reserved for JSON-RPC, stderr for diagnostics.

const std = @import("std");

const Result = @import("result.zig").Result;
const Status = @import("result.zig").Status;
const CallOpts = @import("opts.zig").CallOpts;
const escape = @import("escape.zig");
const protocol = @import("protocol.zig");
const Context = @import("context.zig").Context;

const log = std.log.scoped(.adam_mcp);

/// Type-erased dispatcher: invokes a specific tool with parsed args and
/// writes a JSON-serialized Result to the provided Stringify writer.
/// Returns true if the result represents an error (Status.FAIL), used by
/// the caller to set `isError` in the tools/call envelope.
///
/// `io` is the std.Io vtable the tool will use for any blocking syscall
/// (file read, subprocess spawn, network). Required since Zig 0.16
/// removed direct stdlib I/O entry points.
const DispatchFn = *const fn (
    ctx: ?*Context,
    allocator: std.mem.Allocator,
    io: std.Io,
    args: std.json.Value,
    jws: *std.json.Stringify,
) anyerror!bool;

const RegisteredTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema_json: []const u8,
    is_passthrough: bool,
    dispatch: DispatchFn,
};

pub const BaseServer = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8 = "0.0.1",
    tools: std.ArrayList(RegisteredTool) = .empty,
    initialized: bool = false,
    /// Server-owned I/O context, published by `run()` for the loop's
    /// lifetime and forwarded to tools via dispatch. Null when the server
    /// is driven directly (e.g. `handleMessage` in tests). §2.10 / §4.19.
    ctx: ?*Context = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) BaseServer {
        return .{ .allocator = allocator, .name = name };
    }

    pub fn deinit(self: *BaseServer) void {
        self.tools.deinit(self.allocator);
    }

    /// Register a tool. `ToolType` must have a `call` declaration with
    /// signature `fn(CallOpts, Allocator, std.Io, std.json.Value) Result(T)`.
    /// The is_passthrough flag is detected automatically via §6.30's
    /// `adam_mcp_passthrough_marker` declaration.
    pub fn registerTool(
        self: *BaseServer,
        name: []const u8,
        description: []const u8,
        input_schema_json: []const u8,
        comptime ToolType: type,
    ) !void {
        try self.tools.append(self.allocator, .{
            .name = name,
            .description = description,
            .input_schema_json = input_schema_json,
            .is_passthrough = escape.isPassthrough(ToolType),
            .dispatch = makeDispatcher(ToolType),
        });
    }

    /// Synthesize a dispatcher for the given ToolType at comptime.
    ///
    /// PORT-NOTE [equivalent]: Per-request memory is freed via a per-call
    ///   arena allocated in handleToolsCall and passed to dispatch as the
    ///   tool allocator. Tool functions allocate freely (allocPrint,
    ///   parseFromValueLeaky-owned slices, Result.value, etc.); the Result
    ///   is serialized into the long-lived inner_buf before the arena is
    ///   dropped wholesale after the response is written. Matches Python's
    ///   GC-on-request-boundary semantics with deterministic release.
    ///   (Resolves the former deferred-B #5 per-call leak.)
    fn makeDispatcher(comptime ToolType: type) DispatchFn {
        return struct {
            fn dispatch(
                ctx: ?*Context,
                allocator: std.mem.Allocator,
                io: std.Io,
                args: std.json.Value,
                jws: *std.json.Stringify,
            ) anyerror!bool {
                // Combined: pass ctx (for local Context threading) + io (from remote std.Io 0.3.0)
                var result = ToolType.call(CallOpts{ .ctx = ctx }, allocator, io, args);
                defer result.deinit(allocator);
                try jws.write(result);
                return result.status == Status.FAIL;
            }
        }.dispatch;
    }

    /// Handle one JSON-RPC message (a single line of JSON). Returns the
    /// response bytes (caller owns), or null for notifications that
    /// don't expect a response. `io` is forwarded to tool dispatchers
    /// (only `tools/call` consumes it; initialize/list/ping are I/O-free).
    pub fn handleMessage(self: *BaseServer, allocator: std.mem.Allocator, io: std.Io, line: []const u8) !?[]u8 {
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch |err| {
            return try buildParseError(allocator, @errorName(err));
        };
        defer parsed.deinit();

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return try buildInvalidRequest(allocator, .{ .null = {} }, "request must be a JSON object"),
        };

        const id = obj.get("id") orelse std.json.Value{ .null = {} };
        const method_value = obj.get("method") orelse {
            return try buildInvalidRequest(allocator, id, "missing 'method' field");
        };
        const method = switch (method_value) {
            .string => |s| s,
            else => return try buildInvalidRequest(allocator, id, "'method' must be a string"),
        };
        const params = obj.get("params") orelse std.json.Value{ .null = {} };

        // Notifications have no id field — JSON-RPC says no response.
        const is_notification = obj.get("id") == null;

        if (std.mem.eql(u8, method, "initialize")) {
            return try self.handleInitialize(allocator, id);
        } else if (std.mem.eql(u8, method, "ping")) {
            return try buildEmptyResult(allocator, id);
        } else if (std.mem.eql(u8, method, "tools/list")) {
            return try self.handleToolsList(allocator, id);
        } else if (std.mem.eql(u8, method, "tools/call")) {
            return try self.handleToolsCall(allocator, io, id, params);
        } else if (std.mem.startsWith(u8, method, "notifications/")) {
            // Accept (and ignore) inbound notifications. Phase A only
            // emits them upward via the wire as a reply omission.
            return null;
        }

        if (is_notification) return null;
        return try buildMethodNotFound(allocator, id, method);
    }

    fn handleInitialize(self: *BaseServer, allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        var jws: std.json.Stringify = .{ .writer = &buf.writer };

        try jws.beginObject();
        try jws.objectField("jsonrpc");
        try jws.write("2.0");
        try jws.objectField("id");
        try jws.write(id);
        try jws.objectField("result");
        try jws.beginObject();
        try jws.objectField("protocolVersion");
        try jws.write(protocol.protocol_version);
        try jws.objectField("capabilities");
        try jws.beginObject();
        try jws.objectField("tools");
        try jws.beginObject();
        try jws.endObject();
        try jws.endObject();
        try jws.objectField("serverInfo");
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("version");
        try jws.write(self.version);
        try jws.endObject();
        try jws.endObject();
        try jws.endObject();

        self.initialized = true;
        return try allocator.dupe(u8, buf.written());
    }

    fn handleToolsList(self: *BaseServer, allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        var jws: std.json.Stringify = .{ .writer = &buf.writer };

        try jws.beginObject();
        try jws.objectField("jsonrpc");
        try jws.write("2.0");
        try jws.objectField("id");
        try jws.write(id);
        try jws.objectField("result");
        try jws.beginObject();
        try jws.objectField("tools");
        try jws.beginArray();
        for (self.tools.items) |t| {
            try jws.write(protocol.ToolDescriptor{
                .name = t.name,
                .description = t.description,
                .inputSchemaJson = t.input_schema_json,
            });
        }
        try jws.endArray();
        try jws.endObject();
        try jws.endObject();

        return try allocator.dupe(u8, buf.written());
    }

    fn handleToolsCall(self: *BaseServer, allocator: std.mem.Allocator, io: std.Io, id: std.json.Value, params: std.json.Value) ![]u8 {
        const params_obj = switch (params) {
            .object => |o| o,
            else => return try buildInvalidParams(allocator, id, "params must be an object"),
        };
        const name_val = params_obj.get("name") orelse {
            return try buildInvalidParams(allocator, id, "params.name is required");
        };
        const tool_name = switch (name_val) {
            .string => |s| s,
            else => return try buildInvalidParams(allocator, id, "params.name must be a string"),
        };
        const args = params_obj.get("arguments") orelse std.json.Value{ .null = {} };

        const tool = blk: for (self.tools.items) |t| {
            if (std.mem.eql(u8, t.name, tool_name)) break :blk t;
        } else {
            return try buildToolNotFound(allocator, id, tool_name);
        };

        // Serialize the Result into a JSON string buffer, then wrap into
        // the MCP tools/call envelope as a single text content item.
        //
        // Per-request arena: the tool allocates freely into `arena`; its
        // Result is serialized into inner_buf (long-lived allocator) inside
        // dispatch, then the arena is dropped wholesale. inner_buf MUST stay
        // on the long-lived `allocator` so the serialized JSON survives the
        // arena drop. Closes deferred-B #5 (per-call value leak).
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tool_alloc = arena.allocator();

        var inner_buf: std.Io.Writer.Allocating = .init(allocator);
        defer inner_buf.deinit();
        var inner_jws: std.json.Stringify = .{ .writer = &inner_buf.writer };

        // Combined: ctx (Context threading) + tool_alloc (arena for tool values) + io (std.Io plumbing)
        const is_error = tool.dispatch(self.ctx, tool_alloc, io, args, &inner_jws) catch |err| {
            log.warn("tool '{s}' dispatch error: {s}", .{ tool_name, @errorName(err) });
            return try buildInternalError(allocator, id, "tool dispatch failed");
        };

        var out_buf: std.Io.Writer.Allocating = .init(allocator);
        defer out_buf.deinit();
        var jws: std.json.Stringify = .{ .writer = &out_buf.writer };

        try jws.beginObject();
        try jws.objectField("jsonrpc");
        try jws.write("2.0");
        try jws.objectField("id");
        try jws.write(id);
        try jws.objectField("result");
        try jws.beginObject();
        try jws.objectField("content");
        try jws.beginArray();
        try jws.beginObject();
        try jws.objectField("type");
        try jws.write("text");
        try jws.objectField("text");
        try jws.write(inner_buf.written());
        try jws.endObject();
        try jws.endArray();
        try jws.objectField("isError");
        try jws.write(is_error);
        try jws.endObject();
        try jws.endObject();

        return try allocator.dupe(u8, out_buf.written());
    }

    /// Run the stdio JSON-RPC loop. Each line on stdin is one message;
    /// each response is written as a line on stdout. Errors and
    /// diagnostics go to stderr via std.log.
    ///
    /// Also builds the server Context (io + environ_map) and publishes it on
    /// self.ctx for the loop's lifetime so I/O tools can reach it.
    /// Implements §2.10 / §4.19 (server I/O context threading).
    ///
    /// PORT-NOTE [equivalent]: Python's BaseServer.run() delegates to
    ///   FastMCP, which does the stdio loop. Zig owns the loop here.
    ///
    /// PORT-NOTE [equivalent]: Uses `std.Io.File.stdin().readStreaming`
    ///   and `std.Io.File.stdout().writeStreamingAll` via the supplied
    ///   `io: std.Io`, so the loop is cross-platform (POSIX + Windows).
    ///   EOF is signalled by `error.EndOfStream` rather than `n == 0`,
    ///   which avoids the 0.15 Reader-on-pipe busy-loop bug noted in
    ///   pre-0.16 prototypes. The 4096-byte chunk size is unchanged.
    pub fn run(self: *BaseServer, io: std.Io, environ_map: *const std.process.Environ.Map) !void {
        var ctx = Context{ .io = io, .environ_map = environ_map };
        self.ctx = &ctx;
        defer self.ctx = null;

        const stdin = std.Io.File.stdin();
        const stdout = std.Io.File.stdout();

        var pending: std.ArrayList(u8) = .empty;
        defer pending.deinit(self.allocator);
        var chunk: [4096]u8 = undefined;

        while (true) {
            const n = stdin.readStreaming(io, &.{&chunk}) catch |err| switch (err) {
                error.EndOfStream => return,
                else => {
                    log.warn("stdin read failed: {s}", .{@errorName(err)});
                    return;
                },
            };
            if (n == 0) return; // defensive: vectored read returned no bytes
            try pending.appendSlice(self.allocator, chunk[0..n]);

            while (std.mem.indexOfScalar(u8, pending.items, '\n')) |nl| {
                const line = pending.items[0..nl];
                if (line.len > 0) {
                    if (self.handleMessage(self.allocator, io, line)) |maybe_response| {
                        if (maybe_response) |response| {
                            defer self.allocator.free(response);
                            stdout.writeStreamingAll(io, response) catch |err| {
                                log.warn("stdout write failed: {s}", .{@errorName(err)});
                                return;
                            };
                            stdout.writeStreamingAll(io, "\n") catch |err| {
                                log.warn("stdout write failed: {s}", .{@errorName(err)});
                                return;
                            };
                        }
                    } else |err| {
                        log.warn("handleMessage error: {s}", .{@errorName(err)});
                    }
                }
                const remaining_len = pending.items.len - nl - 1;
                std.mem.copyForwards(u8, pending.items[0..remaining_len], pending.items[nl + 1 ..]);
                pending.shrinkRetainingCapacity(remaining_len);
            }
        }
    }
};

// =============================================================================
// Error-response helpers
// =============================================================================

fn buildErrorResponse(
    allocator: std.mem.Allocator,
    id: std.json.Value,
    code: i32,
    message: []const u8,
) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.beginObject();
    try jws.objectField("jsonrpc");
    try jws.write("2.0");
    try jws.objectField("id");
    try jws.write(id);
    try jws.objectField("error");
    try jws.beginObject();
    try jws.objectField("code");
    try jws.write(code);
    try jws.objectField("message");
    try jws.write(message);
    try jws.endObject();
    try jws.endObject();
    return try allocator.dupe(u8, buf.written());
}

fn buildParseError(allocator: std.mem.Allocator, why: []const u8) ![]u8 {
    return buildErrorResponse(allocator, .{ .null = {} }, protocol.ErrorCode.parse_error, why);
}

fn buildInvalidRequest(allocator: std.mem.Allocator, id: std.json.Value, why: []const u8) ![]u8 {
    return buildErrorResponse(allocator, id, protocol.ErrorCode.invalid_request, why);
}

fn buildInvalidParams(allocator: std.mem.Allocator, id: std.json.Value, why: []const u8) ![]u8 {
    return buildErrorResponse(allocator, id, protocol.ErrorCode.invalid_params, why);
}

fn buildMethodNotFound(allocator: std.mem.Allocator, id: std.json.Value, method: []const u8) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "method '{s}' not found", .{method});
    defer allocator.free(msg);
    return buildErrorResponse(allocator, id, protocol.ErrorCode.method_not_found, msg);
}

fn buildToolNotFound(allocator: std.mem.Allocator, id: std.json.Value, tool_name: []const u8) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "tool '{s}' not registered", .{tool_name});
    defer allocator.free(msg);
    return buildErrorResponse(allocator, id, protocol.ErrorCode.invalid_params, msg);
}

fn buildInternalError(allocator: std.mem.Allocator, id: std.json.Value, why: []const u8) ![]u8 {
    return buildErrorResponse(allocator, id, protocol.ErrorCode.internal_error, why);
}

fn buildEmptyResult(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.beginObject();
    try jws.objectField("jsonrpc");
    try jws.write("2.0");
    try jws.objectField("id");
    try jws.write(id);
    try jws.objectField("result");
    try jws.beginObject();
    try jws.endObject();
    try jws.endObject();
    return try allocator.dupe(u8, buf.written());
}

// =============================================================================
// Tests
// =============================================================================

const TestEcho = struct {
    pub fn call(opts: CallOpts, allocator: std.mem.Allocator, io: std.Io, input: std.json.Value) Result(std.json.Value) {
        _ = opts;
        _ = allocator;
        _ = io;
        return Result(std.json.Value).ok(.{ .value = input, .mode_tag = "[LOCAL]" });
    }
};

const TestFail = struct {
    pub fn call(opts: CallOpts, allocator: std.mem.Allocator, io: std.Io, input: std.json.Value) Result(i32) {
        _ = opts;
        _ = allocator;
        _ = io;
        _ = input;
        return Result(i32).fail(.{ .hint = "intentional fail" });
    }
};

test "BaseServer.handleMessage — initialize returns protocol version + serverInfo" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    const line =
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"protocolVersion\":\"2024-11-05\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"name\":\"test-server\"") != null);
    try std.testing.expect(server.initialized);
}

test "BaseServer.handleMessage — ping returns empty result" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    const line =
        \\{"jsonrpc":"2.0","id":2,"method":"ping"}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expectEqualStrings(
        \\{"jsonrpc":"2.0","id":2,"result":{}}
    , response);
}

test "BaseServer — registerTool then tools/list shows the tool" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    try server.registerTool(
        "echo",
        "echo input back",
        \\{"type":"object","properties":{},"additionalProperties":true}
    ,
        TestEcho,
    );

    const line =
        \\{"jsonrpc":"2.0","id":3,"method":"tools/list"}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"name\":\"echo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"description\":\"echo input back\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"inputSchema\":{\"type\":\"object\"") != null);
}

test "BaseServer — tools/call dispatches and wraps Result in envelope" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    try server.registerTool("echo", "echo", "{}", TestEcho);

    const line =
        \\{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":42}}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    // Inner Result JSON is escaped inside the content.text string — search
    // for unique substrings that survive escaping.
    try std.testing.expect(std.mem.indexOf(u8, response, "\"isError\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "[LOCAL]") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\\\"value\\\":42") != null);
}

test "BaseServer — tools/call FAIL Result sets isError=true" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    try server.registerTool("brokenly", "always fails", "{}", TestFail);

    const line =
        \\{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"brokenly","arguments":{}}}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"isError\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "intentional fail") != null);
}

test "BaseServer — unknown method returns method_not_found" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    const line =
        \\{"jsonrpc":"2.0","id":6,"method":"bogus"}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"code\":-32601") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "bogus") != null);
}

test "BaseServer — parse error returns -32700" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    const response = (try server.handleMessage(allocator, io, "not json")).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"code\":-32700") != null);
}

test "BaseServer — notification (no id) returns null" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    const line =
        \\{"jsonrpc":"2.0","method":"notifications/initialized"}
    ;
    const response = try server.handleMessage(allocator, io, line);
    try std.testing.expect(response == null);
}

test "BaseServer — passthrough flag detected on registration" {
    const allocator = std.testing.allocator;
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    const Passthrough = escape.passthrough(struct {
        pub fn call(opts: CallOpts, alloc: std.mem.Allocator, io: std.Io, input: std.json.Value) Result(std.json.Value) {
            _ = opts;
            _ = alloc;
            _ = io;
            return Result(std.json.Value).ok(.{ .value = input });
        }
    });
    try server.registerTool("escape", "raw passthrough", "{}", Passthrough);

    try std.testing.expect(server.tools.items[0].is_passthrough);
}

const TestCtxTool = struct {
    const Input = struct {};
    fn impl(ctx: *Context, allocator: std.mem.Allocator, in: Input) Result([]const u8) {
        _ = in;
        const h = ctx.home(allocator) catch {
            return Result([]const u8).fail(.{ .hint = "no home" });
        };
        return Result([]const u8).ok(.{ .value = h, .mode_tag = "[LOCAL]" });
    }
    pub const Tool = @import("validation.zig").validates(Input, impl);
};

fn bsTestEnv(allocator: std.mem.Allocator, fake_home: []const u8) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(allocator);
    errdefer map.deinit();
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    try map.put(var_name, fake_home);
    return map;
}

test "BaseServer — tools/call threads ctx into a 3-arg I/O tool" {
    const allocator = std.testing.allocator;
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    var env = try bsTestEnv(allocator, "/tmp/bs-home");
    defer env.deinit();
    var ctx = Context{ .io = undefined, .environ_map = &env };
    server.ctx = &ctx; // inject directly (run() does this from io+env in production)

    try server.registerTool("whereami", "returns home dir", "{}", TestCtxTool.Tool);

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const line =
        \\{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"whereami","arguments":{}}}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"isError\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "/tmp/bs-home") != null);
}

test "BaseServer — 3-arg tool with no ctx set returns isError=true" {
    const allocator = std.testing.allocator;
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();
    // server.ctx left null

    try server.registerTool("whereami", "returns home dir", "{}", TestCtxTool.Tool);

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const line =
        \\{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"whereami","arguments":{}}}
    ;
    const response = (try server.handleMessage(allocator, io, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"isError\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "needs server I/O context") != null);
}

// A tool that allocates a sizeable value every call. Under std.testing.allocator
// (which detects leaks) this passes only if the dispatcher frees the allocation.
const TestAllocTool = struct {
    const Input = struct {};
    fn impl(allocator: std.mem.Allocator, io: std.Io, in: Input) Result([]const u8) {
        _ = io;
        _ = in;
        const blob = allocator.alloc(u8, 4096) catch {
            return Result([]const u8).fail(.{ .hint = "oom" });
        };
        @memset(blob, 'a');
        return Result([]const u8).ok(.{ .value = blob });
    }
    pub const Tool = @import("validation.zig").validates(Input, impl);
};

test "BaseServer — per-request arena frees tool value allocations" {
    const allocator = std.testing.allocator; // leak-checking allocator
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    try server.registerTool("blob", "allocates 4k", "{}", TestAllocTool.Tool);

    // Call several times; if value allocations leaked, testing.allocator fails.
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const line =
            \\{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"blob","arguments":{}}}
        ;
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        const response = (try server.handleMessage(allocator, io, line)).?;
        allocator.free(response);
    }
    // No explicit assert: the test passes iff std.testing.allocator reports no leak.
}
