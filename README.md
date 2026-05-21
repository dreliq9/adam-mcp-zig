# adam-mcp-zig

**Methodology-first MCP SDK for Zig 0.16** — typed `Result<T>` envelope, comptime validation & guardrails, designated escape hatches, and true cross-language parity with [adam-mcp-sdk (Python)](https://github.com/dreliq9/adam-mcp-sdk).

**AI-shaped tools by default.** Never raw JSON or unchecked exceptions leaking to LLMs.

![Zig](https://img.shields.io/badge/Zig-0.16-black?logo=zig) 
![Tests](https://img.shields.io/badge/tests-48-passing-brightgreen)
![Status](https://img.shields.io/badge/status-v0.2.0%20(Pre--1.0)-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

**Status:** v0.2.0 (May 2026) • 48 passing tests • End-to-end stdio verified • Windows first-class + cross-compile ready

> **Pre-1.0.** The public API in `src/root.zig` may change. Pin exact versions in `build.zig.zon` until v1.0.

---

### Why adam-mcp-zig?

Most Zig MCP libraries stop at the protocol. This SDK adds the **contract layer** that makes agents reliable and trustworthy:

- **`Result<T>`** — Typed success/failure with metrics, diagnostics, hints, and `mode_tag`
- **`validates(Model, fn)`** — Comptime input parsing + structured errors
- **`requires(...)`** — Comptime guardrails (WARN/FAIL + force bypass)
- **`passthrough(...)`** — Explicit, detectable escape hatches
- Hand-rolled JSON-RPC 2.0 `BaseServer` + backend vtable
- CLI scaffolder (`adam-mcp new`)
- AI-shaped philosophy (one tool per coherent capability)

**House style & full rationale** live in the [Python sibling repo](https://github.com/dreliq9/adam-mcp-sdk).

**Comparison**

| Feature                    | adam-mcp-zig              | Other Zig MCP libs     |
|---------------------------|---------------------------|------------------------|
| Result contract           | Yes (typed + rich)        | No                     |
| Comptime validation       | Yes                       | No                     |
| Guardrails                | Yes (`requires`)          | No                     |
| Designated escape hatches | Yes (`passthrough`)       | No                     |
| CLI scaffolder            | Yes                       | No                     |
| Cross-language parity     | Yes (Python)              | No                     |
| Tool philosophy           | AI-shaped                 | Mixed / API-shaped     |

---

### Quickstart

#### macOS / Linux
```bash
git clone https://github.com/dreliq9/adam-mcp-zig.git
cd adam-mcp-zig
zig build              # Builds SDK + CLI + reference MCP
zig build test         # 48 tests pass

# Scaffold a new MCP
./zig-out/bin/adam-mcp new my-tool --description "Demo tool" --target ../my-tool
cd ../my-tool
zig build
./zig-out/bin/my_tool
```

#### Windows (PowerShell)
```powershell
git clone https://github.com/dreliq9/adam-mcp-zig $HOME\Projects\adam-mcp-zig
cd $HOME\Projects\adam-mcp-zig
zig build
.\zig-out\bin\adam-mcp.exe new my-tool --target ..\my-tool
```

**Try the reference MCP** (`adam-greet-zig` with 7 tools):
```bash
./tools/smoke_test.sh    # or smoke_test.ps1 on Windows
```

#### Add to Existing Project
```bash
zig fetch --save https://github.com/dreliq9/adam-mcp-zig/archive/refs/tags/v0.2.0.tar.gz
```

Then in `build.zig`:
```zig
const adam_mcp = b.dependency("adam_mcp_zig", .{});
exe.root_module.addImport("adam_mcp_zig", adam_mcp.module("adam_mcp_zig"));
```

---

### Authoring Tools (Example)

```zig
const std = @import("std");
const adam = @import("adam_mcp_zig");

const GreetingInput = struct {
    name: []const u8,
    formality: u8 = 5,
};

fn composeGreetingImpl(allocator: std.mem.Allocator, in: GreetingInput) adam.Result([]const u8) {
    const phrase: []const u8 = if (in.formality > 6) "good morning" else "hello";
    const greeting = std.fmt.allocPrint(allocator, "{s}, {s}!", .{ phrase, in.name }) catch {
        return adam.Result([]const u8).fail(.{ .hint = "out of memory" });
    };
    return adam.Result([]const u8).ok(.{ .value = greeting, .mode_tag = "[LOCAL]" });
}

// House style: typed input + optional escape hatch
pub const ComposeGreeting = adam.validates(GreetingInput, composeGreetingImpl);

pub const ComposeRawGreeting = adam.passthrough( /* ... */ );
```

Full guide in `reference-mcp/adam-greet-zig`.

---

### Project Layout
- `src/` — Core SDK (result, validation, guardrails, base_server, etc.)
- `reference-mcp/adam-greet-zig/` — Canonical 7-tool example
- `tools/` — CLI + smoke tests
- Docs: `ROADMAP.md`, `AUDIT.md`, `LLM_GUIDE.md`, `SPEC.md`, `DECISIONS.md`

---

### Roadmap & Contributing
See [ROADMAP.md](./ROADMAP.md) (next: comptime JSON Schema, arenas, richer diagnostics).

Contributions welcome — read [CONTRIBUTING.md](./CONTRIBUTING.md).

**License:** MIT

---

**Built as part of the adam-mcp ecosystem** for reliable agentic tooling.