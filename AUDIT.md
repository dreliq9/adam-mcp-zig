# adam-mcp-zig — AUDIT

Periodic SOTA snapshot. Implements §3.16. Re-run quarterly.

## 2026-05-13 — Phase A snapshot

### Current state

- v0.0.1 shipped 2026-05-13. ~2,200 LOC of Zig across 17 source files. 45 tests pass on stock Zig 0.16.0.
- Hand-rolled JSON-RPC 2.0 over stdio (initialize / ping / tools/list / tools/call). MCP protocol version 2024-11-05.
- Full PORT-NOTE inventory: 9 `[deferred-B]`, ~25 `[equivalent]`, 1 `[n/a-language]`, 0 `[dropped]`.

### Best-in-class comparison (Zig MCP ecosystem)

| Project | Language | Wire layer | Contract layer | Status |
|---|---|---|---|---|
| **adam-mcp-zig** | Zig 0.16 | hand-rolled | full (Result, validates, requires, passthrough, Backend, Workflow) | v0.0.1 (this) |
| Lightpanda native MCP | Zig 0.15.2 | hand-rolled | none (21 flat tools, hand-written schemas, no Result) | Production (in lightpanda-io/browser) |
| muhammad-fiaz/mcp.zig | Zig 0.15.2 | provided | none | v0.0.3, solo maintainer, 34★ |

`adam-mcp-zig` is the only Zig MCP SDK with a methodology layer; the rest are protocol-only or shallow per-endpoint wrappers.

### Best-in-class comparison (cross-language)

| Project | Language | Wire layer | Contract layer | Stability |
|---|---|---|---|---|
| modelcontextprotocol/typescript-sdk | TypeScript | provided | partial (Zod-based validation; no escape-hatch contract) | 1.x stable |
| modelcontextprotocol/python-sdk + FastMCP | Python | FastMCP | partial (Pydantic input validation; no Result contract) | 1.x stable |
| adam-mcp-py | Python | FastMCP | full (parent of this SDK) | v0.1.0, internal |

Cross-language, `adam-mcp-zig` and its Python parent are the only SDKs with full Principle-Zero + Principle-One contract layers. Other SDKs leave tool shape entirely to the author.

### Upgrade targets

Quarterly review questions:

1. **Has 0.16's `std.Io.Reader` EOF behavior stabilized?** If yes, switch `BaseServer.run` back from `posix.read`/`libc.write` to the Io abstraction (closes deferred-B #7).
2. **Is comptime JSONSchema generation viable in the current Zig version?** Phase B item #1 unblocks once `@typeInfo`-walking is well-tested in production code.
3. **Has MCP protocol moved past 2024-11-05?** Update `protocol_version` in `src/protocol.zig` if so.
4. **Has the methodology gap closed in the Zig ecosystem?** If another SDK ships a Result contract or escape-hatch enforcement, re-evaluate the positioning frame.
5. **Has Lightpanda adopted any methodology pattern?** If they add structured error returns or designated escape tools, the public-contrast story shifts.
