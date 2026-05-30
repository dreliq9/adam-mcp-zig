//! Template content for `adam-mcp new`. Implements §2.5 (three-layer
//! scaffold) + §3.13–§3.17 (required docs).
//!
//! PORT-NOTE [equivalent]: Python uses Jinja2 templates in
//!   `python/templates/_base/` with `{{name}}`/`{{name_snake}}`
//!   substitutions. Zig embeds template content as comptime string
//!   constants and renders via std.mem.replace. Trade-off: no
//!   filesystem template directory to ship, but template content
//!   lives in source. For Phase A the embedded approach is simpler
//!   and faster to ship.

const std = @import("std");

pub const TemplateFile = struct {
    /// Path relative to project root. `{{name_snake}}` is substituted
    /// at render time so directory names follow the package.
    rel_path: []const u8,
    contents: []const u8,
};

pub const all_templates = [_]TemplateFile{
    .{
        .rel_path = "README.md",
        .contents = readme_md,
    },
    .{
        .rel_path = "SPEC.md",
        .contents = spec_md,
    },
    .{
        .rel_path = "LLM_GUIDE.md",
        .contents = llm_guide_md,
    },
    .{
        .rel_path = "CLAUDE.md",
        .contents = claude_md,
    },
    .{
        .rel_path = "CHANGELOG.md",
        .contents = changelog_md,
    },
    .{
        .rel_path = "ROADMAP.md",
        .contents = roadmap_md,
    },
    .{
        .rel_path = "DECISIONS.md",
        .contents = decisions_md,
    },
    .{
        .rel_path = "AUDIT.md",
        .contents = audit_md,
    },
    .{
        .rel_path = "server.json",
        .contents = server_json,
    },
    .{
        .rel_path = "build.zig",
        .contents = build_zig,
    },
    .{
        .rel_path = "build.zig.zon",
        .contents = build_zig_zon,
    },
    .{
        .rel_path = "src/main.zig",
        .contents = main_zig,
    },
    .{
        .rel_path = "src/{{name_snake}}.zig",
        .contents = lib_zig,
    },
    .{
        .rel_path = "src/schema.zig",
        .contents = schema_zig,
    },
    .{
        .rel_path = "src/types.zig",
        .contents = types_zig,
    },
    .{
        .rel_path = "src/mcp/core_tools.zig",
        .contents = core_tools_zig,
    },
    .{
        .rel_path = "src/mcp/escape_tools.zig",
        .contents = escape_tools_zig,
    },
};

/// Substitute {{name}}, {{name_snake}}, {{name_pascal}}, {{description}}
/// in a template body. Caller owns the returned slice.
pub fn render(
    allocator: std.mem.Allocator,
    template: []const u8,
    name: []const u8,
    name_snake: []const u8,
    name_pascal: []const u8,
    description: []const u8,
) ![]u8 {
    var out = try allocator.dupe(u8, template);
    out = try replaceAll(allocator, out, "{{name_snake}}", name_snake);
    out = try replaceAll(allocator, out, "{{name_pascal}}", name_pascal);
    out = try replaceAll(allocator, out, "{{name}}", name);
    out = try replaceAll(allocator, out, "{{description}}", description);
    return out;
}

fn replaceAll(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    const occurrences = std.mem.count(u8, input, needle);
    if (occurrences == 0) return input;
    const size = input.len + occurrences * replacement.len - occurrences * needle.len;
    const out = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, input, needle, replacement, out);
    allocator.free(input);
    return out;
}

// =============================================================================
// Template bodies
// =============================================================================

const readme_md =
    \\# {{name}}
    \\
    \\{{description}}
    \\
    \\Built on `adam-mcp-zig`. See HOUSE_STYLE.md (in the SDK repo).
    \\
    \\## Quickstart
    \\
    \\```
    \\zig build
    \\./zig-out/bin/{{name_snake}}
    \\```
    \\
;

const spec_md =
    \\# {{name}} — SPEC
    \\
    \\Source of truth for what this MCP does. Implements §3.13.
    \\
    \\## Overview
    \\
    \\{{description}}
    \\
    \\## Tools
    \\
    \\| Name | Description | Input | Output |
    \\|------|-------------|-------|--------|
    \\| core_action | Atomic action | CoreInput | CoreOutput |
    \\| {{name_snake}}_passthrough | Raw escape hatch | RawInput | Raw |
    \\
    \\## Out of scope
    \\
    \\- Add scope boundaries here.
    \\
;

const llm_guide_md =
    \\# {{name}} — LLM_GUIDE
    \\
    \\Agent-facing usage guide. Implements §3.14.
    \\
    \\## Overview
    \\
    \\{{description}}
    \\
    \\## Critical workflow
    \\
    \\1. Call `core_action(...)` for the common case.
    \\2. Drop to `{{name_snake}}_passthrough` only when the AI-shaped tool
    \\   doesn't fit.
    \\
    \\## Tool categories
    \\
    \\- `core_tools` — atomic operations.
    \\- `escape_tools` — Principle One escape hatch.
    \\
    \\## Parameter gotchas
    \\
    \\- (Add input validation gotchas here.)
    \\
    \\## Failure → fix
    \\
    \\- FAIL with hint "missing field X" → include X in input.
    \\
    \\## Mode/path transparency
    \\
    \\- `mode_tag` values: `[LOCAL]` (default).
    \\
    \\## Escape hatches
    \\
    \\- `{{name_snake}}_passthrough(template)` — returns input as raw value.
    \\
;

const claude_md =
    \\# {{name}} — CLAUDE.md
    \\
    \\## When to use this MCP
    \\
    \\{{description}}
    \\
    \\Trigger phrases: (fill in)
    \\
    \\## When NOT to use this MCP
    \\
    \\- (List boundaries here.)
    \\
    \\## When to drop down to underlying APIs
    \\
    \\Use `{{name_snake}}_passthrough` for cases the AI-shaped tools don't
    \\cover. Principle One in practice.
    \\
    \\## Co-tools
    \\
    \\- (Other MCPs/skills that pair well.)
    \\
;

const changelog_md =
    \\# Changelog
    \\
    \\All notable changes to this project will be documented in this file.
    \\
    \\## [Unreleased]
    \\
    \\### Added
    \\- Initial scaffold via `adam-mcp new {{name}}`.
    \\
;

const roadmap_md =
    \\# {{name}} — ROADMAP
    \\
    \\## v0.1
    \\
    \\- [ ] Wire `core_action` to a real backend.
    \\- [ ] Replace passthrough stub with the real raw API.
    \\
    \\## v0.2
    \\
    \\- [ ] Add workflows.
    \\
;

const decisions_md =
    \\# {{name}} — DECISIONS
    \\
    \\Architectural decision log. Implements §3.17.
    \\
    \\## 2026-XX-XX — Scaffolded with adam-mcp-zig
    \\
    \\Decision: use adam-mcp-zig SDK and follow HOUSE_STYLE.md.
    \\Why: AI-shaped tool surface + escape-hatch contract.
    \\
;

const audit_md =
    \\# {{name}} — AUDIT
    \\
    \\Periodic SOTA survey. Implements §3.16. Re-run quarterly.
    \\
    \\## Current state (vTBD)
    \\
    \\- Scaffolded. No tools wired yet.
    \\
    \\## Best-in-class comparison
    \\
    \\- TBD.
    \\
;

const server_json =
    \\{
    \\  "name": "{{name}}",
    \\  "description": "{{description}}",
    \\  "version": "0.0.1",
    \\  "command": "./zig-out/bin/{{name_snake}}",
    \\  "args": []
    \\}
    \\
;

const build_zig =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    const adam_mcp_zig = b.dependency("adam_mcp_zig", .{
    \\        .target = target,
    \\    }).module("adam_mcp_zig");
    \\
    \\    const exe = b.addExecutable(.{
    \\        .name = "{{name_snake}}",
    \\        .root_module = b.createModule(.{
    \\            .root_source_file = b.path("src/main.zig"),
    \\            .target = target,
    \\            .optimize = optimize,
    \\            .imports = &.{
    \\                .{ .name = "adam_mcp_zig", .module = adam_mcp_zig },
    \\            },
    \\        }),
    \\    });
    \\    b.installArtifact(exe);
    \\}
    \\
;

const build_zig_zon =
    \\.{
    \\    .name = .{{name_snake}},
    \\    .version = "0.0.1",
    \\    .fingerprint = 0x0,
    \\    .minimum_zig_version = "0.16.0",
    \\    .dependencies = .{
    \\        .adam_mcp_zig = .{ .path = "../adam-mcp-zig" },
    \\    },
    \\    .paths = .{ "build.zig", "build.zig.zon", "src" },
    \\}
    \\
;

const main_zig =
    \\const std = @import("std");
    \\const adam = @import("adam_mcp_zig");
    \\const lib = @import("{{name_snake}}.zig");
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    var server = adam.BaseServer.init(init.gpa, "{{name}}");
    \\    defer server.deinit();
    \\    try lib.registerAll(&server);
    \\    try server.run(init.io, &init.environ_map);
    \\}
    \\
;

const lib_zig =
    \\//! {{name_pascal}} — library entrypoint. Registers tools onto a
    \\//! BaseServer.
    \\
    \\const std = @import("std");
    \\const adam = @import("adam_mcp_zig");
    \\const core_tools = @import("mcp/core_tools.zig");
    \\const escape_tools = @import("mcp/escape_tools.zig");
    \\
    \\pub fn registerAll(server: *adam.BaseServer) !void {
    \\    try server.registerTool(
    \\        "core_action",
    \\        "Atomic action — fill in.",
    \\        \\\\{"type":"object","properties":{"input":{"type":"string"}},"required":["input"]}
    \\    ,
    \\        core_tools.CoreAction,
    \\    );
    \\    try server.registerTool(
    \\        "{{name_snake}}_passthrough",
    \\        "Raw escape hatch. Implements §6.30.",
    \\        \\\\{"type":"object","properties":{"template":{"type":"string"}},"required":["template"]}
    \\    ,
    \\        escape_tools.Passthrough,
    \\    );
    \\}
    \\
;

const schema_zig =
    \\//! Tool input schemas. Implements §2.9.
    \\
    \\pub const CoreInput = struct {
    \\    input: []const u8,
    \\};
    \\
    \\pub const RawInput = struct {
    \\    template: []const u8,
    \\};
    \\
;

const types_zig =
    \\//! Domain types. Implements §2.9.
    \\
    \\pub const CoreOutput = struct {
    \\    echoed: []const u8,
    \\};
    \\
;

const core_tools_zig =
    \\//! Core atomic tools. Implements §2.7.
    \\
    \\const std = @import("std");
    \\const adam = @import("adam_mcp_zig");
    \\const schema = @import("../schema.zig");
    \\const types = @import("../types.zig");
    \\
    \\fn coreImpl(allocator: std.mem.Allocator, input: schema.CoreInput) adam.Result(types.CoreOutput) {
    \\    _ = allocator;
    \\    return adam.Result(types.CoreOutput).ok(.{
    \\        .value = .{ .echoed = input.input },
    \\        .mode_tag = "[LOCAL]",
    \\    });
    \\}
    \\
    \\pub const CoreAction = adam.validates(schema.CoreInput, coreImpl);
    \\
;

const escape_tools_zig =
    \\//! Escape-hatch tool — Principle One. Implements §6.30.
    \\
    \\const std = @import("std");
    \\const adam = @import("adam_mcp_zig");
    \\const schema = @import("../schema.zig");
    \\
    \\fn rawImpl(allocator: std.mem.Allocator, input: schema.RawInput) adam.Result([]const u8) {
    \\    _ = allocator;
    \\    return adam.Result([]const u8).ok(.{
    \\        .value = input.template,
    \\        .mode_tag = "[LOCAL]",
    \\    });
    \\}
    \\
    \\const _validated = adam.validates(schema.RawInput, rawImpl);
    \\pub const Passthrough = adam.passthrough(_validated);
    \\
;

// =============================================================================
// Tests
// =============================================================================

test "render — substitutes placeholders" {
    const allocator = std.testing.allocator;
    const rendered = try render(allocator, "Hello {{name}} ({{name_snake}})!", "Foo Bar", "foo_bar", "FooBar", "x");
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello Foo Bar (foo_bar)!", rendered);
}

test "render — no substitutions returns content unchanged" {
    const allocator = std.testing.allocator;
    const rendered = try render(allocator, "static content", "x", "x", "X", "x");
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("static content", rendered);
}
