//! adam_mcp_zig — primitives for the Adam MCP house style.
//!
//! Public API. See HOUSE_STYLE.md (in adam-mcp-sdk) for the rules each
//! symbol implements.
//!
//! PORT-NOTE [equivalent]: Python's `adam_mcp_py/__init__.py` re-exports
//!   ENVELOPE_VERSION, Raw, Result, Status, validates, requires,
//!   BackendProtocol, detect_backend, Workflow, output_dir, passthrough,
//!   is_passthrough, BaseServer. This Zig root.zig mirrors that surface;
//!   each symbol resolves to its own module file. Phase A coverage
//!   tracked in ROADMAP.md.

const result_mod = @import("result.zig");
const escape_mod = @import("escape.zig");
const workflows_mod = @import("workflows.zig");
const output_mod = @import("output.zig");
const validation_mod = @import("validation.zig");
const guardrails_mod = @import("guardrails.zig");
const backend_mod = @import("backend.zig");
const opts_mod = @import("opts.zig");
const protocol_mod = @import("protocol.zig");
const base_server_mod = @import("base_server.zig");

pub const Result = result_mod.Result;
pub const Status = result_mod.Status;
pub const Raw = result_mod.Raw;
pub const ENVELOPE_VERSION = result_mod.ENVELOPE_VERSION;

pub const passthrough = escape_mod.passthrough;
pub const isPassthrough = escape_mod.isPassthrough;

pub const Workflow = workflows_mod.Workflow;

pub const outputDir = output_mod.outputDir;
pub const homeDir = output_mod.homeDir;

pub const validates = validation_mod.validates;
pub const requires = guardrails_mod.requires;
pub const Severity = guardrails_mod.Severity;
pub const Backend = backend_mod.Backend;
pub const detectBackend = backend_mod.detectBackend;
pub const CallOpts = opts_mod.CallOpts;

pub const BaseServer = base_server_mod.BaseServer;
pub const protocol = protocol_mod;

test {
    _ = result_mod;
    _ = escape_mod;
    _ = workflows_mod;
    _ = output_mod;
    _ = validation_mod;
    _ = guardrails_mod;
    _ = backend_mod;
    _ = opts_mod;
    _ = protocol_mod;
    _ = base_server_mod;
}
