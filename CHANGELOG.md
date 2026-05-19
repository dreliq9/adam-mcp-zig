# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase B targets
See `ROADMAP.md`.

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
