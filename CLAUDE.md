# adam-mcp-zig — CLAUDE.md

## When to use this SDK

Building or modifying any MCP **written in Zig** for Adam's stack. Trigger phrases: "Zig MCP", "port to Zig", "wrap <engine> as an MCP" when the engine is in Zig (brain-zig, lsc, taichi-zig if/when it lands).

## When NOT to use this SDK

- Building an MCP in Python — use `adam-mcp-py` (`~/Projects/adam-mcp-sdk/`) instead.
- Wrapping the protocol layer alone without methodology — `mcp.zig` is the lightweight choice and runs on 0.15.2.
- A one-off tool for a single agent session with no external consumers — overhead isn't worth it. Just write a script.

## When to drop down to underlying APIs

Principle One. Specifically:

- The agent wants to send a raw JSON-RPC envelope unconstrained by tool contracts → call the MCP's `passthrough`-marked tool. Every MCP built with this SDK ships one.
- The agent wants to inspect what an AI-shaped tool's underlying API actually returned → use `Result.raw` on the wrapped tool's response.
- A tool's `Result.value` shape is wrong for the agent's task → the tool's surface is wrong. Rewrite the tool, don't pad the agent. See HOUSE_STYLE.md Principle Zero.

## Co-tools

Pairs well with:
- `~/Projects/adam-mcp-sdk/` — the Python sibling and source of truth for HOUSE_STYLE.md
- `mcp-author` skill in the Claude Code plugin pack (auto-activates on MCP-building phrases)
- `corpus-retrieval` — searching `zig-std` and `zig-projects` corpora when checking 0.16 stdlib idioms

## Build/run cheatsheet

```bash
cd ~/Projects/adam-mcp-zig
zig build              # SDK + CLI + reference MCP
zig build test         # 45 tests
./zig-out/bin/adam-mcp new <name> --target <path>   # scaffold
./zig-out/bin/adam-greet-zig    # reference MCP (stdio JSON-RPC)
```

## Editing the SDK itself

When modifying source in `src/`:
- Every Python feature that diverges from verbatim translation needs a `PORT-NOTE [<status>]` comment with one of `equivalent | dropped | deferred-B | n/a-language`. No silent drops during Phase A. (Phase A complete as of 2026-05-13 — but the discipline holds for any new code added.)
- Cross-link new public symbols to a HOUSE_STYLE.md rule via `Implements §X.Y` in the docstring.
- Run `zig build test` before committing. All 45 tests pass on stock Zig 0.16.0.

Stock Zig 0.16.0 is the default `zig`; the Espressif fork lives at `zig-esp` per `~/.zshrc`.
