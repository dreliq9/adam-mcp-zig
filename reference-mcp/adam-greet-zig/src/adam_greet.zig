//! adam-greet-zig — library entrypoint. Implements §2.5 (three-layer).
//!
//! Registers every tool category onto a BaseServer. Tools demonstrate
//! every SDK contract: validates, requires, passthrough, workflow,
//! backend.

const std = @import("std");
const adam = @import("adam_mcp_zig");

const greeting_tools = @import("mcp/greeting_tools.zig");
const context_tools = @import("mcp/context_tools.zig");
const history_tools = @import("mcp/history_tools.zig");
const escape_tools = @import("mcp/escape_tools.zig");
const workflow_tools = @import("mcp/workflow_tools.zig");

pub fn registerAll(server: *adam.BaseServer) !void {
    try server.registerTool(
        "compose_greeting",
        "Compose a single greeting line. Takes name + formality (0-10), returns prose.",
        \\{"type":"object","properties":{"name":{"type":"string"},"formality":{"type":"integer","minimum":0,"maximum":10,"default":5}},"required":["name"]}
    ,
        greeting_tools.ComposeGreeting,
    );

    try server.registerTool(
        "compose_personalized_greeting",
        "Compose a greeting using whatever the server remembers.",
        \\{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
    ,
        greeting_tools.ComposePersonalizedGreeting,
    );

    try server.registerTool(
        "get_morning_context",
        "Bundle weather + calendar + music into one AI-parseable result.",
        \\{"type":"object","properties":{},"additionalProperties":false}
    ,
        context_tools.GetMorningContext,
    );

    try server.registerTool(
        "record_greeting",
        "Persist a greeting to history (Phase A stub — see PORT-NOTE in history_tools.zig).",
        \\{"type":"object","properties":{"greeting":{"type":"string"}},"required":["greeting"]}
    ,
        history_tools.RecordGreeting,
    );

    try server.registerTool(
        "recent_greetings",
        "Return the N most recent greetings.",
        \\{"type":"object","properties":{"n":{"type":"integer","minimum":1,"maximum":100,"default":5}}}
    ,
        history_tools.RecentGreetings,
    );

    try server.registerTool(
        "morning_briefing",
        "AI-shaped composition: weather + calendar + greeting in one tool.",
        \\{"type":"object","properties":{"name":{"type":"string"},"force":{"type":"boolean","default":false}},"required":["name"]}
    ,
        workflow_tools.MorningBriefing,
    );

    try server.registerTool(
        "compose_raw_greeting",
        "Escape hatch (§6.30): render template as-is, no synthesis logic.",
        \\{"type":"object","properties":{"template":{"type":"string"}},"required":["template"]}
    ,
        escape_tools.ComposeRawGreeting,
    );
}
