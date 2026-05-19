# adam-mcp-zig — ROADMAP

## Phase A (2026-05-13) — shipped

- Core library (10 modules): result, status, validates, requires, passthrough, Workflow, Backend, output_dir, opts, protocol, base_server.
- Hand-rolled JSON-RPC 2.0 over stdio (initialize / ping / tools/list / tools/call).
- CLI: `adam-mcp new` (17-file scaffold) + `adam-mcp audit` (rule_id registry stub).
- Reference MCP `adam-greet-zig` with 7 tools exercising every wrapper.
- 45 passing tests on stock Zig 0.16.0.

## Phase B — open items

Each item corresponds to one or more `PORT-NOTE [deferred-B]` comments in source.

1. **Comptime JSONSchema generation from Zig structs** (validation.zig, protocol.zig). Walk `@typeInfo(InputT)` to emit the `inputSchema` field automatically; remove the hand-written schema strings from registration sites.
2. **Per-request arena allocator** (base_server.zig). Pass a fresh arena to each `dispatch(...)` call; free wholesale after writing the response. Cleans up tool-allocated strings inside `Result.value` without requiring `deinit` smarts.
3. **Richer validation diagnostics** (validation.zig). Replace `@errorName(err)` with per-field path info via either a `@typeInfo` walk before parsing or `std.json.Scanner` with `Diagnostics` tracking. Pydantic parity.
4. **`force` flag propagation** (base_server.zig). Pull `force` from MCP `tools/call` params and thread into `CallOpts.force` so `@requires` overrides work from the wire.
5. **Audit rule bodies** (cli/audit_rules.zig). Port the 9 Python rule checks: required files (already runnable via shell), passthrough-present, validates-usage, tool-file-naming, etc. Keep the §3.18 rule_id stability commitment intact.
6. **`adam-mcp upgrade` and `adam-mcp audit --self-check`** (cli/main.zig). Port the Python dependency-bump + cross-link integrity flows.
7. **`std.Io.Reader` EOF on pipes** (base_server.zig). Currently the stdio loop uses `std.posix.read` + `std.c.write` because the streaming Reader spins instead of returning `EndOfStream` on pipe close. Revisit when upstream Zig fixes this — switch back to the Io abstraction for proper async pluggability.
8. **`std.process.Environ` for env vars** (output.zig). Replace libc `getenv` with the typed Environ accessor threaded through BaseServer.
9. **Stateful tool file persistence** (reference-mcp/adam-greet-zig/src/mcp/history_tools.zig). `record_greeting` and `recent_greetings` are Phase A stubs — Phase B will write to `~/adam-greet-output/history.json` via `outputDir(...)` once io threading reaches tool functions.

## Phase C — public launch

Pre-launch checklist (independent of Phase B closure):

- [ ] README links, screenshots / sample session.
- [ ] HOUSE_STYLE.md cross-link from this repo (currently points at adam-mcp-sdk path).
- [ ] License + CONTRIBUTING.
- [ ] Ziggit + Show HN + Zig newsletter post with **taichi-mcp-zig** as the demo, this SDK as the framework, Lightpanda as the named comparator.
- [ ] Tag v0.1.0.

See `~/.claude/projects/-Users-adamsteen/memory/project_adam_mcp_sdk_zig_port_plan.md` for the launch sequencing.
