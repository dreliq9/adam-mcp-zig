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
- A tool's `Result.value` shape is wrong for the agent's task → the tool's surface is wrong. Rewrite the tool, don't pad the agent. See [HOUSE_STYLE.md](./HOUSE_STYLE.md) Principle Zero.

## Co-tools

Pairs well with:
- `~/Projects/adam-mcp-sdk/` — the Python sibling; same methodology, Python-native examples
- `mcp-author` skill in the Claude Code plugin pack (auto-activates on MCP-building phrases)
- `corpus-retrieval` — searching `zig-std` and `zig-projects` corpora when checking 0.16 stdlib idioms

## Build/run cheatsheet — macOS / Linux

```bash
cd ~/Projects/adam-mcp-zig
zig build              # SDK + CLI + reference MCP
zig build test         # 48 tests
./zig-out/bin/adam-mcp new <name> --target <path>   # scaffold
./zig-out/bin/adam-greet-zig    # reference MCP (stdio JSON-RPC)
./tools/smoke_test.sh                     # end-to-end JSON-RPC smoke test
./tools/byte_equivalence_check.sh         # cross-language Zig vs Python check
```

## Build/run cheatsheet — Windows (native or cross-compile)

```powershell
# Native build on Windows (PowerShell):
cd $HOME\Projects\adam-mcp-zig
zig build
zig build test
.\zig-out\bin\adam-mcp.exe new <name> --target <path>
.\zig-out\bin\adam-greet-zig.exe
.\tools\smoke_test.ps1
.\tools\byte_equivalence_check.ps1
```

```bash
# Cross-compile from macOS/Linux:
zig build -Dtarget=x86_64-windows-gnu    # builds .exe artifacts under zig-out/bin/
file zig-out/bin/adam-mcp.exe            # PE32+ executable (console) x86-64
```

**Cross-platform notes (apply when editing src/):**
- Use `std.Io.File.stdin()` / `stdout()` via the supplied `io: std.Io` — never `std.posix.read`, `std.posix.STDIN_FILENO`, or `std.c.write`. Windows HANDLEs are `*anyopaque`, not file descriptors.
- For env vars, use `init.environ_map.get(name)`. There is no global env accessor in 0.16. `homeDir(allocator, env)` reads `HOME` on POSIX and `USERPROFILE` on Windows.
- For argv, use `init.minimal.args.toSlice(arena)` to get cross-platform WTF-8 strings — Windows native argv is `[]const u16`.
- Templates may use `/` as a path separator; Zig stdlib converts internally on Windows.

## Editing the SDK itself

When modifying source in `src/`:
- Every Python feature that diverges from verbatim translation needs a `PORT-NOTE [<status>]` comment with one of `equivalent | dropped | deferred-B | n/a-language`. No silent drops during Phase A. (Phase A complete as of 2026-05-13 — but the discipline holds for any new code added.)
- Cross-link new public symbols to a HOUSE_STYLE.md rule via `Implements §X.Y` in the docstring.
- Run `zig build test` before committing. All 48 tests pass on stock Zig 0.16.0 (native + Windows cross-compile both verified).

Stock Zig 0.16.0 is the default `zig`; the Espressif fork lives at `zig-esp` per `~/.zshrc`.
