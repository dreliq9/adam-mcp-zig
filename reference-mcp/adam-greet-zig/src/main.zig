//! adam-greet-zig — reference MCP entrypoint.

const std = @import("std");
const adam = @import("adam_mcp_zig");
const lib = @import("adam_greet.zig");

pub fn main(init: std.process.Init) !void {
    var server = adam.BaseServer.init(init.gpa, "adam-greet");
    defer server.deinit();

    try lib.registerAll(&server);
    try server.run(init.io, &init.environ_map);
}
