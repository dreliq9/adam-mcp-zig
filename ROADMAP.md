# adam-mcp-zig — ROADMAP

## Phase A (2026-05-13) — shipped

- Core library (10 modules): result, status, validates, requires, passthrough, Workflow, Backend, output_dir, opts, protocol, base_server.
- Hand-rolled JSON-RPC 2.0 over stdio (initialize / ping / tools/list / tools/call).
- CLI: `adam-mcp new` (17-file scaffold) + `adam-mcp audit` (rule_id registry stub).
- Reference MCP `adam-greet-zig` with 7 tools exercising every wrapper.
- 45 passing tests on stock Zig 0.16.0.

## 0.1.0 (2026-05-20) — shipped

- Cross-language envelope contract synced with `adam-mcp-py` 0.3.0: `envelope_version: i32 = 1` reserved as the first wire field; `Raw` type alias; `ENVELOPE_VERSION` exported.
- Audit registry: §1.1 reserved (compile-time enforced via named-field struct literals; no Phase B runtime check needed).

## 0.2.0 (2026-05-20) — shipped

- **Windows is a first-class platform.** `zig build -Dtarget=x86_64-windows-gnu` produces working `adam-mcp.exe` and `adam-greet-zig.exe`. Native Windows `zig build` works via the same invocation.
- Closes Phase B item 7 (Io.Reader EOF). `BaseServer.run` now uses `std.Io.File.stdin/stdout` via the supplied `io: std.Io`, with `error.EndOfStream` for pipe close. Direct File operations don't have the 0.15 Reader-on-pipe spin bug.
- Closes Phase B item 8 (Environ). `homeDir(allocator, environ_map)` reads `HOME` on POSIX and `USERPROFILE` on Windows via `init.environ_map.get(...)`. Public export.
- PowerShell equivalents of the verification scripts: `tools/smoke_test.ps1`, `tools/byte_equivalence_check.ps1`.

## 0.3.0 (2026-05-21) — shipped

- **Tool callbacks now receive `std.Io`.** Wrapper-produced `call` signature is `fn(CallOpts, Allocator, Io, json.Value) Result(T)`; inner impl is `fn(Allocator, Io, Model) Result(T)`. Required because Zig 0.16 routes all blocking syscalls through `std.Io` (`std.fs.cwd()` and `std.process.Child.init` are gone). Surfaced the first time a downstream MCP tried to do real file/subprocess I/O from a tool callback.
- Closes the half of Phase B item 7 about tool-function io threading; the `record_greeting`/`recent_greetings` file-persistence work is now a pure file-persistence task (no signature blocker remaining).
- Wire format unchanged. Cross-language byte equivalence with `adam-mcp-py` preserved — io is `[n/a-language]` in the Python sibling.

## Phase B — remaining open items

Each item corresponds to one or more `PORT-NOTE [deferred-B]` comments in source.

1. **Comptime JSONSchema generation from Zig structs** (validation.zig, protocol.zig). Walk `@typeInfo(InputT)` to emit the `inputSchema` field automatically; remove the hand-written schema strings from registration sites.
2. ~~**Per-request arena allocator** (base_server.zig).~~ ✅ **Done (0.3.0)** — `handleToolsCall` passes a fresh arena to `dispatch(...)`, freed wholesale after the Result is serialized into the long-lived response buffer.
3. **Richer validation diagnostics** (validation.zig). Replace `@errorName(err)` with per-field path info via either a `@typeInfo` walk before parsing or `std.json.Scanner` with `Diagnostics` tracking. Pydantic parity.
4. **`force` flag propagation** (base_server.zig). Pull `force` from MCP `tools/call` params and thread into `CallOpts.force` so `@requires` overrides work from the wire.
5. **Audit rule bodies** (cli/audit_rules.zig). Port the Python rule checks: required files (already runnable via shell), passthrough-present, validates-usage, tool-file-naming, etc. Keep the §3.18 rule_id stability commitment intact.
6. **`adam-mcp upgrade` and `adam-mcp audit --self-check`** (cli/main.zig). Port the Python dependency-bump + cross-link integrity flows.
7. **Stateful tool file persistence** (reference-mcp/adam-greet-zig/src/mcp/history_tools.zig). `record_greeting` and `recent_greetings` are Phase A stubs — Phase B will write to `~/adam-greet-output/history.json` via `outputDir(...)`. **Unblocked as of 0.3.0** (combined std.Io + Context work): io now reaches tool functions through `Context` (3-arg impls) and per-request arenas; the stubs can be wired onto `Context.outputDir(...)`. (Only the actual file-write implementation remains.)

## Phase C — public launch

- [x] License (MIT, 2026-05-20).
- [x] CONTRIBUTING.md.
- [x] CI on linux/macos/windows (GitHub Actions).
- [x] HOUSE_STYLE.md cross-link points at the GitHub URL of the sibling repo.
- [x] Tag v0.2.0.
- [x] GitHub Release with cross-compiled artifacts.
- [ ] Zigistry submission.
- [ ] Ziggit + Show HN + Zig newsletter post. **taichi-mcp-zig** as the demo, this SDK as the framework, Lightpanda as the named comparator.
- [ ] MCP registry listing (if upstream catalog exists).

See `~/.claude/projects/-Users-adamsteen/memory/project_adam_mcp_sdk_zig_port_plan.md` for launch sequencing.
