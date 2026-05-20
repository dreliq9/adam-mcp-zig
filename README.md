## adam-mcp-zig

A methodology-first MCP (Model Context Protocol) SDK for **Zig 0.16**. Hand-rolled JSON-RPC. Comptime type-checking. AI-shaped tool surface by default. Escape hatches always available.

**Status:** v0.2.0 (2026-05-20). 48 passing tests. End-to-end stdio loop verified. Windows is a first-class target — cross-compile via `zig build -Dtarget=x86_64-windows-gnu`.

> **Pre-1.0.** The public API in `src/root.zig` may break between minor versions. SemVer guarantees kick in at v1.0. Pin exact versions in `build.zig.zon` until then.

---

### Why this exists

The Zig MCP space has one shallow protocol library (`mcp.zig`, v0.0.3) and one hand-rolled native MCP server in a high-visibility project (Lightpanda's browser — 21 flat tools, no `Result` contract, no validation, no designated escape hatch). Both are competent and shallow.

`adam-mcp-zig` defines the contract layer the others skip:

- **`Result(T)`** — typed `(status, value, raw, metrics, diagnostics, hint, mode_tag)`. Never raw output, never raw exceptions.
- **`validates(Model, fn)`** — comptime wrapper that parses MCP-side JSON into a typed Zig struct; parse failures become `Result.fail` with diagnostics.
- **`requires(precondition, hint, severity, fn)`** — comptime guard. WARN by default, FAIL only when destructive, bypass with `force=true` on `CallOpts`.
- **`passthrough(fn_or_struct)`** — marks a tool as the documented escape hatch. Composes with `validates`.
- **`Backend` / `detectBackend`** — vtable interface for IPC/local/web/etc. backends; `mode_tag` surfaces which path was used on every `Result`.
- **`Workflow`** — vtable struct for higher-order compositions distinct from atomic tools.
- **`BaseServer`** — hand-rolled JSON-RPC 2.0 over stdio. Owns the wire so the contract layer enforces at protocol level, not above it. Targets MCP 2024-11-05.

The single load-bearing principle: **AI-shaped, not API-shaped.** One tool per *coherent thing an AI can do*, not one tool per API endpoint. House style and rationale live in [adam-mcp-sdk/HOUSE_STYLE.md](https://github.com/dreliq9/adam-mcp-sdk/blob/main/HOUSE_STYLE.md) (the Python sibling repo; it is the cross-language source of truth).

---

### Quickstart

```bash
# 1. Build the SDK + CLI (macOS / Linux).
git clone https://github.com/dreliq9/adam-mcp-zig ~/Projects/adam-mcp-zig
cd ~/Projects/adam-mcp-zig
zig build              # produces zig-out/bin/adam-mcp + zig-out/bin/adam-greet-zig
zig build test         # 48 tests pass

# 2. Scaffold a new MCP.
./zig-out/bin/adam-mcp new my-thing --description "what it does" --target ~/Projects/my-thing
cd ~/Projects/my-thing
# Edit src/mcp/core_tools.zig to add a real tool.
zig build
./zig-out/bin/my_thing # speaks JSON-RPC on stdio

# 3. Try the reference MCP.
./tools/smoke_test.sh
```

```powershell
# Windows (PowerShell):
git clone https://github.com/dreliq9/adam-mcp-zig $HOME\Projects\adam-mcp-zig
cd $HOME\Projects\adam-mcp-zig
zig build
zig build test
.\zig-out\bin\adam-mcp.exe new my-thing --target $HOME\Projects\my-thing
.\tools\smoke_test.ps1
```

```bash
# Cross-compile from macOS/Linux to Windows:
zig build -Dtarget=x86_64-windows-gnu    # writes .exe artifacts under zig-out/bin/
```

### Adding to your project

```bash
# In your project root:
zig fetch --save https://github.com/dreliq9/adam-mcp-zig/archive/refs/tags/v0.2.0.tar.gz
```

Then in `build.zig`:

```zig
const adam_mcp = b.dependency("adam_mcp_zig", .{});
exe.root_module.addImport("adam_mcp_zig", adam_mcp.module("adam_mcp_zig"));
```

---

### Authoring a tool, end-to-end

```zig
const std = @import("std");
const adam = @import("adam_mcp_zig");

const GreetingInput = struct {
    name: []const u8,
    formality: u8 = 5,
};

fn composeGreetingImpl(allocator: std.mem.Allocator, in: GreetingInput) adam.Result([]const u8) {
    const phrase: []const u8 = if (in.formality > 6) "good morning" else "hello";
    const greeting = std.fmt.allocPrint(allocator, "{s}, {s}", .{ phrase, in.name }) catch {
        return adam.Result([]const u8).fail(.{ .hint = "out of memory" });
    };
    return adam.Result([]const u8).ok(.{ .value = greeting, .mode_tag = "[LOCAL]" });
}

// The two-line house style: typed input + escape variant.
pub const ComposeGreeting = adam.validates(GreetingInput, composeGreetingImpl);

fn rawGreetingImpl(_: std.mem.Allocator, in: struct { template: []const u8 }) adam.Result([]const u8) {
    return adam.Result([]const u8).ok(.{ .value = in.template, .mode_tag = "[LOCAL]" });
}
pub const ComposeRawGreeting = adam.passthrough(
    adam.validates(struct { template: []const u8 }, rawGreetingImpl),
);

// Register in your main:
//   try server.registerTool("compose_greeting", "...", json_schema, ComposeGreeting);
//   try server.registerTool("compose_raw_greeting", "...", json_schema, ComposeRawGreeting);
```

The compile-time wrappers enforce:
- Every tool returns a `Result(T)` (compile error otherwise).
- Every WARN/FAIL has a hint (non-optional field on `WarnOpts`/`FailOpts`).
- Every passthrough is detectable via `isPassthrough(ToolType)` at registration time.

---

### Layout

```
src/
  result.zig       result + status + jsonStringify (§1.1, §6.29)
  validation.zig   validates(Model, fn) wrapper        (§1.2)
  guardrails.zig   requires(precondition, ...) wrapper (§1.3, §6.31)
  escape.zig       passthrough(fn) + isPassthrough     (§6.30)
  backend.zig      Backend vtable + detectBackend      (§2.6)
  workflows.zig    Workflow vtable                     (§2.8)
  output.zig       outputDir helper                    (§2.10)
  opts.zig         CallOpts { force: bool }            (§1.3 carrier)
  protocol.zig     JSON-RPC types + ToolDescriptor
  base_server.zig  BaseServer: registerTool, run(io), handleMessage
  cli/             adam-mcp CLI (new, audit stub)
reference-mcp/
  adam-greet-zig/  canonical reference MCP (7 tools)
```

---

### Comparison

| | adam-mcp-zig | mcp.zig v0.0.3 | Lightpanda native MCP |
|---|---|---|---|
| Zig version | 0.16.0 | 0.15.2 | 0.15.2 |
| Wire layer | hand-rolled | provided | hand-rolled |
| `Result` contract | yes (typed generic) | no | no |
| Input validation | comptime `validates(Model, fn)` | no | no |
| Guardrails | comptime `requires(...)` | no | no |
| Designated escape hatch | yes (`passthrough` marker) | no | no |
| Backend abstraction | yes (vtable + `mode_tag`) | no | no |
| CLI scaffolder | `adam-mcp new` | no | no |
| Tool shape | AI-shaped (Principle Zero) | up to author | API-shaped (21 flat tools) |

---

### Roadmap

See [ROADMAP.md](./ROADMAP.md). Phase B closes nine known `[deferred-B]` PORT-NOTE follow-ups, including comptime JSONSchema generation, per-request arena allocators, audit rule bodies, and richer validation diagnostics.

### License

MIT.
