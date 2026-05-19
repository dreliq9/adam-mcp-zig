//! MCP wire types — JSON-RPC 2.0 envelope + MCP-specific tool messages.
//!
//! Targets MCP protocol version "2024-11-05" (the version Lightpanda and
//! the official SDKs ship). Phase A supports tools only; resources,
//! prompts, sampling, roots, and notifications are deferred to Phase B.
//!
//! PORT-NOTE [equivalent]: Python's BaseServer delegates to FastMCP for
//!   wire serialization. Zig hand-rolls the protocol because the SDK
//!   value is the contract layer — owning the wire lets Result.mode_tag,
//!   passthrough enforcement, etc. live at protocol level rather than
//!   above it. Lightpanda's `src/mcp/protocol.zig` is the public
//!   reference for this layout. See [[lightpanda-zig-mcp-comparator]].

const std = @import("std");

pub const protocol_version: []const u8 = "2024-11-05";

/// JSON-RPC 2.0 standard error codes.
pub const ErrorCode = struct {
    pub const parse_error: i32 = -32700;
    pub const invalid_request: i32 = -32600;
    pub const method_not_found: i32 = -32601;
    pub const invalid_params: i32 = -32602;
    pub const internal_error: i32 = -32603;
};

/// JSON-RPC request envelope. `id` is a std.json.Value because it may
/// be a number, string, or (rarely) null per the spec.
pub const Request = struct {
    jsonrpc: []const u8 = "2.0",
    id: std.json.Value,
    method: []const u8,
    params: ?std.json.Value = null,
};

/// JSON-RPC response envelope. Exactly one of `result` / `@"error"` set.
pub const Response = struct {
    jsonrpc: []const u8 = "2.0",
    id: std.json.Value,
    result: ?std.json.Value = null,
    err: ?ResponseError = null,

    pub fn jsonStringify(self: Response, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("jsonrpc");
        try jws.write(self.jsonrpc);
        try jws.objectField("id");
        try jws.write(self.id);
        if (self.result) |r| {
            try jws.objectField("result");
            try jws.write(r);
        } else if (self.err) |e| {
            try jws.objectField("error");
            try jws.write(e);
        }
        try jws.endObject();
    }
};

pub const ResponseError = struct {
    code: i32,
    message: []const u8,
    data: ?std.json.Value = null,
};

/// MCP tool descriptor returned in `tools/list`.
///
/// PORT-NOTE [deferred-B]: `inputSchema` is stored as a pre-rendered
///   JSON object string in Phase A. Phase B will generate it from the
///   tool's `adam_mcp_input_model` Zig struct via @typeInfo so authors
///   don't hand-write JSONSchema.
pub const ToolDescriptor = struct {
    name: []const u8,
    description: []const u8,
    /// Raw JSON-encoded JSONSchema object describing the tool's input.
    /// Must be valid JSON; embedded as-is into tools/list responses.
    inputSchemaJson: []const u8,

    pub fn jsonStringify(self: ToolDescriptor, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("name");
        try jws.write(self.name);
        try jws.objectField("description");
        try jws.write(self.description);
        // inputSchema is raw JSON — emit verbatim, not re-quoted as a
        // string. Use the raw-stream API.
        try jws.objectFieldRaw("\"inputSchema\"");
        try jws.beginWriteRaw();
        try jws.writer.writeAll(self.inputSchemaJson);
        jws.endWriteRaw();
        try jws.endObject();
    }
};

/// Result wrapper emitted to a `tools/call` response. The MCP spec wraps
/// tool output in a `content` array; we put the JSON-serialized
/// `Result(T)` as a single text content item.
///
/// PORT-NOTE [equivalent]: FastMCP performs this wrapping automatically
///   in Python. Zig hand-rolls it. Behavior on the wire is identical:
///   one `text` content item carrying a JSON string that the client
///   re-parses into an adam_mcp Result.
pub const ToolCallEnvelope = struct {
    content: []const ContentItem,
    isError: bool,
};

pub const ContentItem = struct {
    type: []const u8 = "text",
    text: []const u8,
};

// =============================================================================
// Tests
// =============================================================================

test "Response — result variant serializes without error field" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.write(Response{
        .id = .{ .integer = 1 },
        .result = .{ .string = "pong" },
    });
    try std.testing.expectEqualStrings(
        \\{"jsonrpc":"2.0","id":1,"result":"pong"}
    , buf.written());
}

test "Response — error variant serializes without result field" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.write(Response{
        .id = .{ .integer = 2 },
        .err = .{ .code = ErrorCode.method_not_found, .message = "no such method" },
    });
    try std.testing.expectEqualStrings(
        \\{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"no such method","data":null}}
    , buf.written());
}

test "ToolDescriptor — inputSchema embedded as raw JSON" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    var jws: std.json.Stringify = .{ .writer = &buf.writer };
    try jws.write(ToolDescriptor{
        .name = "echo",
        .description = "echo a string",
        .inputSchemaJson =
        \\{"type":"object","properties":{"s":{"type":"string"}},"required":["s"]}
        ,
    });
    try std.testing.expectEqualStrings(
        \\{"name":"echo","description":"echo a string","inputSchema":{"type":"object","properties":{"s":{"type":"string"}},"required":["s"]}}
    , buf.written());
}
