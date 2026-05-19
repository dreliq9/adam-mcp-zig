# adam-mcp-zig — DECISIONS

Architectural decision log. Newest first.

## 2026-05-13 — Phase A foundational decisions

Locked at the start of the port session.

1. **Hand-roll JSON-RPC** (not depend on `mcp.zig`). Rationale: SDK value is the contract layer; owning the wire lets `Result.mode_tag`, `passthrough` enforcement, and JSON-RPC error codes live at protocol level rather than above a third-party wrapper. Trade-off: ~300–500 more LOC of Zig. Verified by Lightpanda's hand-rolled `src/mcp/` precedent.
2. **1:1 of public surface + behavior** (not strict-syntax 1:1). Strict 1:1 is impossible (Zig has no decorators, no Pydantic, no FastMCP). Equivalence test: byte/behavioral comparison of JSON-RPC responses for the same inputs. Idiomatic Zig at the foundation; observable behavior preserved.
3. **Separate repo at `~/Projects/adam-mcp-zig/`** (not a polyglot monorepo with the Python SDK). Reason: independent publish cadence + separate repo makes external dependencies easier to spot than burying inside a multi-language tree.
4. **Zig 0.16.0** (not 0.15.2). All of Adam's active Zig codebases run 0.16. Targeting 0.16 puts adam-mcp-zig ahead of Lightpanda and mcp.zig (both 0.15.2). Stock toolchain at `~/Projects/zig-toolchains/zig-aarch64-macos-0.16.0/`; Espressif fork aliased to `zig-esp`.

## 2026-05-13 — PORT-NOTE discipline

Every Python feature that does not carry over verbatim leaves a `PORT-NOTE [<status>]` comment in the analogous Zig location. Status values: `equivalent | dropped | deferred-B | n/a-language`. No silent drops during Phase A; `[dropped]` requires explicit user approval recorded here. Phase A shipped with **zero `[dropped]` markers**.

## 2026-05-13 — Inline templates (not a `_templates/` directory)

Python uses Jinja2 templates in `python/templates/_base/`. Zig CLI embeds template content as comptime string constants in `src/cli/templates.zig`. Trade-off: template content lives in source (less convenient to edit), but the binary ships self-contained with no template directory to install.

## 2026-05-13 — Type-erased dispatchers via JSON

Every registered tool exposes `call(opts: CallOpts, allocator: Allocator, input: std.json.Value) -> Result(OutputT)`. The `BaseServer` synthesizes a dispatcher per tool at comptime that calls `ToolType.call` and serializes the result. JSON is the wire format; input/output type erasure happens at the wire boundary, not inside tool code. Tools see typed Models thanks to `validates(...)`.

## 2026-05-13 — Hint required at compile time for non-OK Results

Python's `Result.warn`/`Result.fail` raise `ValueError` if `hint` is empty. Zig encodes the same invariant in the type system: `WarnOpts.hint` and `FailOpts.hint` are non-optional `[]const u8` fields. Compile-time enforcement is strictly stronger than Python's runtime check; observably equivalent for valid callers.

## 2026-05-13 — Empty struct for zero-input tools

Tools that take no input declare a named `const EmptyInput = struct {};` and call `validates(EmptyInput, fn)`. Anonymous `struct {}` literals at different declaration sites are different types in Zig and won't compile through `validates`. The named constant is the workaround.

## 2026-05-13 — posix.read / libc.write for stdio loop

Stock 0.16's `std.Io.Reader` streaming has busted EOF detection on pipes (observed: 100% CPU spin instead of `EndOfStream` after stdin closed). `BaseServer.run` reads via `std.posix.read` (returns 0 on EOF) and writes via `std.c.write` (since `std.posix.write` was stripped from 0.16-stock). Phase B revisits when upstream Zig fixes the Reader EOF behavior.
