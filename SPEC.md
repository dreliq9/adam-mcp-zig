# adam-mcp-zig — SPEC

Versioned source of truth for what this SDK does. The cross-language methodology spec is `~/Projects/adam-mcp-sdk/HOUSE_STYLE.md` (CalVer 2026.05); this SPEC is the Zig-specific surface contract.

## Scope

`adam-mcp-zig` provides:

1. A typed `Result(T)` return convention for MCP tools.
2. Comptime wrapper types that publish tools onto a JSON-RPC server: `validates`, `requires`, `passthrough`, `Workflow`.
3. A vtable-based `Backend` abstraction with `mode_tag` transparency.
4. A `BaseServer` that hand-rolls JSON-RPC 2.0 over stdio targeting MCP 2024-11-05.
5. A CLI `adam-mcp` with `new` (scaffold) and `audit` (rule registry) subcommands.

Out of scope (handled elsewhere or deferred):
- HTTP transport for MCP. stdio only.
- Resources, prompts, sampling, roots from the MCP spec. Tools only.
- Hot-reload, daemonization, multi-tenant servers.
- Phase B items listed in `ROADMAP.md`.

## Tool authoring contract

Every public tool MUST:

1. Be expressed as a wrapper type (`pub const X = adam.validates(...)` or similar) — not a bare function. Wrappers carry metadata the dispatcher needs.
2. Return `Result(T)` for some Zig type `T`. Compile-time enforced.
3. Receive a `std.mem.Allocator` as its first parameter; any owned data goes into `Result.value` or `Result.diagnostics`.
4. Set `Result.mode_tag` when the MCP exposes more than one backend.
5. Provide a hint on every `WARN` and `FAIL` Result. Compile-time enforced.

Every MCP using this SDK MUST:

1. Have exactly one tool wrapped with `adam.passthrough(...)` — the documented escape hatch (§6.30).
2. Register tools through `BaseServer.registerTool(name, description, input_schema_json, ToolType)`.
3. Call `server.run(init.io)` from `pub fn main(init: std.process.Init)`.

## Result wire shape

Serialized form (byte-stable; verified by tests):

```
{"envelope_version":1,"status":"OK|WARN|FAIL","value":<T-or-null>,"raw":<json-or-null>,"metrics":{...},"diagnostics":[...],"hint":<str-or-null>,"mode_tag":<str-or-null>}
```

Field order is fixed at envelope_version → status → value → raw → metrics → diagnostics → hint → mode_tag, matching Python's dataclass field order so cross-language byte comparison is meaningful. `envelope_version` is first by design — parsers can short-circuit on version mismatch before reading the rest.

**The envelope is a wire format.** Once byte-equivalence with Python is contractual, `Result` is no longer just an in-process Zig struct — it is a serialization format. Field order is contractual. New top-level fields require an `envelope_version` bump and a CHANGELOG `### Breaking` entry, in lockstep with the Python side.

## MCP envelope

`tools/call` responses wrap the serialized Result inside MCP's content array:

```
{"jsonrpc":"2.0","id":<n>,"result":{"content":[{"type":"text","text":"<JSON-encoded Result>"}],"isError":<bool>}}
```

`isError` mirrors `Result.status == FAIL`. Clients that understand the convention re-parse `content[0].text` as JSON to recover the structured Result; clients that don't see it as a text blob.

## SDK versioning

CalVer-aligned with `HOUSE_STYLE.md`. Breaking changes require a `CHANGELOG.md ### Breaking` entry citing the rule_id (§3.18 stability). Public symbols in `src/root.zig` are the API surface; everything else is implementation detail.

## Out-of-scope explicitly

- **No `@dropped` PORT-NOTEs.** Every Python feature has either a Zig equivalent or a `[deferred-B]` follow-up. If a future Python feature genuinely shouldn't be ported, it requires explicit `DECISIONS.md` justification before the marker is allowed.
- **No silent JSON-RPC extensions.** Non-MCP-spec methods are not implemented. The wire is exactly the spec.
