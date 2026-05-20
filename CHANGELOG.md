# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase B targets
See `ROADMAP.md`.

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
