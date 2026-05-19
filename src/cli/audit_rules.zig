//! Mechanical audit rules for `adam-mcp audit`. Implements parts of §3.18.
//!
//! PORT-NOTE [deferred-B]: Python's audit_rules.py implements 9 rules
//!   including filesystem walks (passthrough detection, validates
//!   param-name checks, tool file splits) plus schemas/spec_md_lint and
//!   schemas/llm_guide_lint. Phase A ships only the rule_id stability
//!   commitment (per §3.18) and a no-op runAll — the source-walk
//!   implementations need recursive directory traversal threading
//!   `std.Io` through every checker, which is a meaningful refactor.
//!   Phase B will port the rule bodies.
//!
//!   Stand-in justification: the SDK already enforces the most
//!   load-bearing rules at compile time. `validates(Model, fn)` makes
//!   §1.5's parameter-name issue impossible because the parameter type
//!   IS the Model. `passthrough(...)` exposes `adam_mcp_passthrough_marker`
//!   as a comptime decl, detectable by the registration system without
//!   text grep. So the Phase A audit-as-text-grep shipped in Python is
//!   partially redundant in Zig.

const std = @import("std");

pub const Severity = enum { OK, WARN, FAIL };

pub const Finding = struct {
    rule: []const u8,
    severity: Severity,
    message: []const u8,
    hint: []const u8,
};

pub const AuditRule = struct {
    rule_id: []const u8,
    spec_section: []const u8,
    severity_default: Severity,
    description: []const u8,
};

/// Stable rule_id registry. Once a rule_id appears here, its meaning is
/// frozen forever per §3.18. New rules use the next free number in
/// their chapter. Removal records go to DECISIONS.md; the rule_id is
/// reserved permanently (never reassigned).
pub const registry = [_]AuditRule{
    .{
        .rule_id = "§3.13",
        .spec_section = "HOUSE_STYLE.md §3.13–§3.17",
        .severity_default = .FAIL,
        .description = "Required project docs present (SPEC, LLM_GUIDE, CLAUDE, README, ...)",
    },
    .{
        .rule_id = "§6.30",
        .spec_section = "HOUSE_STYLE.md §6.30",
        .severity_default = .FAIL,
        .description = "MCP has a passthrough() escape-hatch tool",
    },
    .{
        .rule_id = "§1.2",
        .spec_section = "HOUSE_STYLE.md §1.2",
        .severity_default = .WARN,
        .description = "At least one validates() call exists",
    },
};

/// Phase A stub. Returns an empty findings list with a single WARN
/// pointing to ROADMAP. Phase B fills in actual rule bodies.
pub fn runAll(allocator: std.mem.Allocator, io: std.Io, project_root: []const u8) !std.ArrayList(Finding) {
    _ = io;
    _ = project_root;
    var findings: std.ArrayList(Finding) = .empty;
    try findings.append(allocator, .{
        .rule = "§audit-stub",
        .severity = .WARN,
        .message = "audit body is a Phase A stub — rule checks deferred to Phase B",
        .hint = "Track Phase B audit port via ROADMAP.md; SDK enforces most rules at compile time",
    });
    return findings;
}

// =============================================================================
// Tests
// =============================================================================

test "registry — rule_ids are unique" {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(std.testing.allocator);
    for (registry) |rule| {
        const r = try seen.getOrPut(std.testing.allocator, rule.rule_id);
        try std.testing.expect(!r.found_existing);
    }
}
