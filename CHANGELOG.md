# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase B targets
See `ROADMAP.md`.

## [0.3.0] — 2026-05-21 (integrated std.Io + Context/arena work)

### Breaking
- **Tool callback signature widened to `fn(Allocator, Io, Model) Result(T)`.** Wrappers — `validates`, `requires`, and (transitively) `passthrough` — pass `std.Io` as the second positional argument to the inner impl. Required because Zig 0.16 routes every blocking syscall (file read, subprocess spawn, network) through `std.Io`; `std.fs.cwd()` and `std.process.Child.init` no longer exist. Tools that don't perform I/O take `io` as a `_ = io;` no-op so the dispatch shape is uniform.
- **`BaseServer.handleMessage(allocator, io, line)` and `handleToolsCall(allocator, io, id, params)` add an `io` parameter.** `BaseServer.run(io, environ_map)` forwards it down automatically. Direct test-mode callers must update.
- **`DispatchFn` widened to take `io`.** Internal type.

### Added
- `Context` (io + environ_map) threaded into tool dispatch via `CallOpts.ctx`; built and published by `BaseServer.run()` for the loop lifetime.
- `validates` comptime-detects 3-arg I/O impls `fn(*Context, Allocator, Model)` and forwards the context (FAIL + hint when absent); pure-compute impls unchanged.
- Per-request arena in `handleToolsCall` frees tool `value` allocations after the Result is serialized (closes deferred-B #5).

### Changed
- `BaseServer.run` now takes `(io, environ_map)`. Scaffolds and reference updated.

### Notes
- Wire format / Result envelope / cross-language byte equivalence with Python unchanged (`io` and `Context` are Zig-internal plumbing).
- 48 tests pass on stock Zig 0.16.0.
- Reference `adam-greet-zig` updated; history_tools io-blocking note resolved (only pure file-persistence remains for stateful tools).

## [0.2.0] — 2026-05-20

### Added
- **Windows is now a first-class platform.** Cross-compile via `zig build -Dtarget=x86_64-windows-gnu` produces working `.exe` artifacts. Native Windows builds work via the same `zig build` invocation. Both `adam-mcp.exe` (CLI) and `adam-greet-zig.exe` (reference MCP) are verified.
- `tools/smoke_test.ps1` — PowerShell equivalent of `tools/smoke_test.sh`. Same JSON-RPC verification flow, MCP-conformant initialize handshake (FastMCP requires it).
- `tools/byte_equivalence_check.ps1` — PowerShell equivalent of the cross-language Zig-vs-Python check.
- `adam_mcp_zig.homeDir(allocator, environ_map)` — cross-platform user-home lookup. Reads `HOME` on POSIX, `USERPROFILE` on Windows. Public export.
- SPEC.md "Platform support" section codifies the cross-platform invariants for stdio, env vars, and argv.

### Changed
- `BaseServer.run(io)` no longer bypasses the Io vtable. Replaced the POSIX-only `std.posix.read` + `std.c.write` pair with cross-platform `std.Io.File.stdin().readStreaming(io, ...)` + `std.Io.File.stdout().writeStreamingAll(io, ...)`. The `io` parameter is now actually used; EOF is signalled via `error.EndOfStream`.
- `outputDir(allocator, io, environ_map, name)` — signature now takes `environ_map: *const std.process.Environ.Map` as third arg. Required for cross-platform home-dir lookup; 0.16 removed global env accessors. **Breaking** for the signature, but no production callers existed in 0.1.0 (the reference MCP only mentions it in a doc comment).
- `adam-mcp` CLI parses args via `init.minimal.args.toSlice(arena)` instead of indexing `args.vector` directly. Avoids the Windows-native UTF-16 argv format.

### Notes
- 48 passing tests on stock Zig 0.16.0 (was 47 in 0.1.0 — added a `homeDir` error-path test).
- Cross-compile verified on macOS host: `file zig-out/bin/adam-mcp.exe` → `PE32+ executable (console) x86-64, for MS Windows`.
- Runtime verification on a Windows host is deferred to the user; macOS dev box has no Wine installation.

## [0.1.0] — 2026-05-20

### Breaking
- **§1.1** — `Result` envelope shape changed to match the cross-language contract. `envelope_version: i32 = 1` added as the **first** field, before `status`. Canonical wire order is now `(envelope_version, status, value, raw, metrics, diagnostics, hint, mode_tag)`. Migration: callers using struct-literal `.{ .status = .OK, .value = X }` or factory methods `Result(T).ok(.{ .value = X })` are unaffected — `envelope_version` defaults to `1`. Tests that assert exact JSON byte-equivalence must include `"envelope_version":1` as the first key (see `src/result.zig` tests for the canonical fixture).

### Added
- `adam_mcp_zig.Raw` — type alias for `std.json.Value`. Mirrors Python's `Raw = Any`. Self-documenting annotation for the §1.1 strict-typing exception on `Result.raw`. An MCP that wants stricter typing can decode `Raw` into a project-specific struct without changing the envelope contract.
- `adam_mcp_zig.ENVELOPE_VERSION` — `i32` constant for parsers verifying wire-format compatibility.
- SPEC.md "Result wire shape" updated; new "envelope is a wire format" note codifies that field order is contractual.
- Audit registry: §1.1 reserved with a compile-time-enforced description (Zig's named-field struct literals make positional construction impossible, so the Python audit rule's role is filled by the type system here).

### Notes
- Mirrors `adam-mcp-py` 0.3.0. Cross-language byte equivalence with Python is now: `envelope_version` first, identical field order, identical default values.
- 47 passing tests on stock Zig 0.16.0 (was 45 in 0.0.1 — added envelope_version default test and Raw alias identity test).

## [0.0.1] — 2026-05-13

### Added
- Core library (10 modules): `Result`/`Status` (§1.1, §6.29), `validates` (§1.2), `requires` (§1.3, §6.31), `passthrough`/`isPassthrough` (§6.30), `Backend`/`detectBackend` (§2.6), `Workflow` (§2.8), `outputDir` (§2.10), `CallOpts`, MCP protocol types, and `BaseServer` with hand-rolled JSON-RPC 2.0 stdio loop.
- CLI `adam-mcp` with `new` (17-file project scaffold) and `audit` (stub with stable §3.18 rule_id registry).
- Reference MCP `adam-greet-zig` with 7 tools exercising validates/requires/passthrough/workflow/backend.
- 45 passing tests on stock Zig 0.16.0.
- End-to-end stdio JSON-RPC verified against the reference MCP (initialize, tools/list, tools/call).

### Notes
- Targets MCP protocol version `2024-11-05`.
- Stock Zig 0.16.0 is the supported toolchain; Espressif fork (`zig-esp`) is for ESP32 firmware only.
- 9 `[deferred-B]` PORT-NOTE follow-ups; zero `[dropped]` markers across the codebase.
