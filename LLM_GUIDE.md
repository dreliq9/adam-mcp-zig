# adam-mcp-zig — LLM_GUIDE

Agent-facing usage guide. If you (an LLM) are building an MCP using this SDK, read this end to end before writing tools.

## Overview

`adam-mcp-zig` is the methodology layer for MCPs written in Zig. The SDK gives you a `BaseServer` plus four comptime wrapper types — `validates`, `requires`, `passthrough`, and `Workflow` — that enforce the AI-shaped contract from `HOUSE_STYLE.md` (in `adam-mcp-sdk`).

Every tool returns a typed `Result(T)`. The wire layer is hand-rolled JSON-RPC 2.0 over stdio targeting MCP 2024-11-05.

## Critical workflow

The order that matters:

1. **Define your typed input model** as a plain Zig struct. No Pydantic equivalent — `std.json.parseFromValueLeaky` is what `validates(...)` uses under the hood.
2. **Write your tool function** with signature `fn(std.mem.Allocator, InputT) Result(OutputT)`. The allocator is passed in so the tool can produce owned strings; the InputT is the parsed model.
3. **Wrap with `adam.validates(InputT, fn)`** to publish the tool. The wrapper handles JSON-to-Model parsing, error mapping, and exposes a `call(opts, allocator, std.json.Value) -> Result(OutputT)` entry point that `BaseServer.registerTool` consumes.
4. **For destructive operations**, wrap again with `adam.requires(precondition, fail_hint, .FAIL or .WARN, validated_tool)`. The precondition is a `fn() bool`. The agent can override with `force=true` on `CallOpts`.
5. **For the escape hatch**, wrap with `adam.passthrough(validated_tool)`. Exactly one tool per MCP should carry this marker; the audit pass enforces it.
6. **Register** with `server.registerTool(name, description, input_schema_json, ToolType)`. The `input_schema_json` is a JSONSchema string published in `tools/list`. Phase B will generate this from the Zig struct automatically.
7. **Run** with `server.run(init.io)` from your `main(init: std.process.Init)`.

## Tool categories

Organize tool source files under `src/mcp/<area>_tools.zig`. Each file exports public `pub const Foo = adam.validates(...)` constants that the registration site references.

- `core_tools.zig` — atomic operations specific to your domain.
- `escape_tools.zig` — the `passthrough(...)` wrappers. One designated tool here.
- `workflow_tools.zig` — higher-order tools that compose multiple atomic ops.
- `context_tools.zig` — multi-source-synthesis tools (§4.18).

Reference: `reference-mcp/adam-greet-zig/src/mcp/` shows all four categories live.

## Parameter gotchas

- **`OkOpts.value`** is `?T`. When constructing a Result with no value (e.g., a record/write operation), use `Result(void).ok(.{ .mode_tag = "..." })` — the `T = void` case is special-cased to serialize `value: null`.
- **`WarnOpts.hint`** and **`FailOpts.hint`** are NON-optional. The compiler will reject `Result.fail(.{})` without a hint. This is intentional: every non-OK Result must tell the agent what to do next.
- **`Result.deinit(allocator)`** only frees `metrics` and `diagnostics`. Anything you allocate and store in `value` leaks per-call until Phase B's per-request arena lands. For Phase A this is a known cost; not a correctness issue.
- **`std.json.parseFromValueLeaky`** stores parsed strings as slices into the input JSON's arena. The slices stay valid for the duration of the tool call; don't try to free them.
- **Zero-input tools**: define `const EmptyInput = struct {};` and `adam.validates(EmptyInput, fn)`. The empty struct must be NAMED — anonymous `struct {}` literals in different declaration sites are different types and won't compile through `validates`.

## Failure → fix

| Status / hint | What it means | Fix |
|---|---|---|
| `FAIL` `"Fix input fields and retry. ..."` | `validates` parse error — input didn't match the Model | Check field names + types in input JSON |
| `FAIL` `"<precondition hint>"` from `requires` | precondition returned false | Satisfy the precondition or pass `force=true` |
| `FAIL` from compile-time wrapper rejection | tool function doesn't return `Result(T)` | Add return type annotation |
| MCP error `-32700` (parse_error) | request body isn't JSON | Check the JSON-RPC client |
| MCP error `-32601` (method_not_found) | unknown method name | Verify `initialize` / `ping` / `tools/list` / `tools/call` spelling |
| MCP error `-32602` (invalid_params) on `tools/call` | missing/wrong `name` field in params | Include `{"name": "<tool>", "arguments": {...}}` |

## Mode/path transparency

Every Result carries a `mode_tag` indicating which backend served it. Conventional values:

- `[LOCAL]` — in-process execution, no external dependency
- `[IPC]` — talking to a local daemon
- `[FILE]` — reading/writing the filesystem
- `[WEB]` — external network call
- `[CACHE]` — served from a cache
- `[PAPER]` / `[LIVE]` — for tools with paper-vs-real-money semantics (taichi-mcp-zig convention)

The wire layer doesn't enforce conventions; pick what makes sense for your domain.

## Escape hatches

When the agent's task doesn't fit any AI-shaped tool, drop down via the `passthrough`-marked tool. The reference MCP's `compose_raw_greeting` is the canonical example.

`Result.raw` is the second escape lane: even on a typed tool, you can stash the underlying API's raw response in `.raw` so the agent can inspect it without re-calling.

## Known Phase A limitations (PORT-NOTE [deferred-B])

Search the source for `PORT-NOTE \[deferred-B\]` to find every known follow-up. Highlights:

- Audit rule bodies are stubs (registry IDs are stable per §3.18); use `adam-mcp audit` for the structure, not the rule content.
- Tool-allocated strings inside `Result.value` leak per-call; Phase B per-request arena fixes this.
- `force` flag on MCP `tools/call` doesn't propagate into `CallOpts.force` yet.
- Tool input JSONSchemas are hand-written strings; Phase B generates them via `@typeInfo`.
- `std.Io.Reader` streaming has busted EOF on pipes in 0.16; `BaseServer.run` bypasses with `std.posix.read` + `std.c.write`.

None are correctness-breaking for a v0.0.1 reference MCP. The wire layer is solid; the contract layer is enforced at compile time.
