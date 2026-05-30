# SDK I/O-Context Extension — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `adam-mcp-zig` tools a way to do real file/subprocess I/O by threading a server-owned `Context` (io + environment) into tool dispatch, so the upcoming LTspice MCP (and taichi/brain later) can read files and spawn processes.

**Architecture:** Add a `Context` value built once in `BaseServer.run()` from the supplied `io`+`environ_map`. Carry an optional `*Context` through the existing `CallOpts` channel. `validates` comptime-detects whether a tool impl wants the context (3-arg `fn(*Context, Allocator, Model)` vs the existing 2-arg `fn(Allocator, Model)`) and forwards it; pure-compute tools are untouched. A per-request arena in the dispatcher frees tool allocations after the response is serialized, closing the documented per-call leak.

**Tech Stack:** Zig 0.16.0 (stock toolchain at `~/Projects/zig-toolchains/zig-aarch64-macos-0.16.0/`), `std.json`, `std.Io`, `std.heap.ArenaAllocator`.

---

## Context for the implementer

- **Where you are:** `~/Projects/adam-mcp-zig/`. Build with `zig build`, test with `zig build test` (48 tests currently pass). The reference MCP `adam-greet-zig` lives at `reference-mcp/adam-greet-zig/` and must keep working.
- **The contract today:** A tool is a *type* with `pub fn call(opts: CallOpts, allocator: std.mem.Allocator, input: std.json.Value) Result(T)`. `validates(Model, fn_impl)` produces that type from an impl `fn(Allocator, Model) Result(T)`. `BaseServer.registerTool(name, desc, schema_json, ToolType)` stores it; the dispatcher calls `ToolType.call(CallOpts{}, allocator, args)`.
- **Why this change:** The impl signature threads only an allocator — no `io`, no env. Pure compute is fine, but I/O tools can't read files or spawn engines. This closes deferred-B #8 (io threading) and #5 (per-request arena).
- **Port discipline:** Every new/changed behavior gets a `PORT-NOTE [equivalent|deferred-B]` comment cross-linking the HOUSE_STYLE rule. Run `zig build test` before every commit. Commit messages end with the Co-Authored-By trailer (see repo convention).
- **Backward-compat invariant:** All 48 existing tests must pass unchanged after every task. The `Result` wire envelope must not change (no `ENVELOPE_VERSION` bump).

---

## Task 1: `Context` type

**Files:**
- Create: `src/context.zig`
- Modify: `src/root.zig` (export `Context`)
- Test: in `src/context.zig` (inline `test` blocks, the repo convention)

- [ ] **Step 1: Write the failing test**

Add to `src/context.zig` (create the file with just the test + a stub first):

```zig
//! Server-owned I/O context threaded into tool dispatch.
//! Implements deferred-B #8 (io/output-dir threading) of the Zig port plan.

const std = @import("std");
const output = @import("output.zig");

pub const Context = struct {
    io: std.Io,
    environ_map: *const std.process.Environ.Map,

    /// `<home>/<name>-output/`, created if absent. Caller owns the slice.
    pub fn outputDir(self: *const Context, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        return output.outputDir(allocator, self.io, self.environ_map, name);
    }

    /// Cross-platform home dir. Caller owns the slice.
    pub fn home(self: *const Context, allocator: std.mem.Allocator) ![]u8 {
        return output.homeDir(allocator, self.environ_map);
    }
};

// =============================================================================
// Tests
// =============================================================================

fn testEnv(allocator: std.mem.Allocator, fake_home: []const u8) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(allocator);
    errdefer map.deinit();
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    try map.put(var_name, fake_home);
    return map;
}

test "Context.home — delegates to homeDir using the env map" {
    const allocator = std.testing.allocator;
    var env = try testEnv(allocator, "/tmp/ctx-home");
    defer env.deinit();

    // io is unused by home(); a zeroed std.Io is never dereferenced on this path.
    const ctx = Context{ .io = undefined, .environ_map = &env };
    const h = try ctx.home(allocator);
    defer allocator.free(h);

    try std.testing.expectEqualStrings("/tmp/ctx-home", h);
}
```

- [ ] **Step 2: Run test to verify it passes (this task is additive — the stub IS the impl)**

Run: `zig build test`
Expected: PASS — the new test runs and all 48 prior tests still pass. (Context is referenced by root.zig in Step 3; until then it's only compiled via its own test. If `zig build test` doesn't pick up `context.zig` yet, that's expected — Step 3 wires it into the root test aggregator.)

- [ ] **Step 3: Export `Context` from `root.zig` and add it to the test aggregator**

In `src/root.zig`, add the import near the other module imports (after line 22):

```zig
const context_mod = @import("context.zig");
```

Add the public export after the `CallOpts` export (line 42):

```zig
pub const Context = context_mod.Context;
```

Add to the `test {}` block (after line 57, before the closing brace):

```zig
    _ = context_mod;
```

- [ ] **Step 4: Run the full suite**

Run: `zig build test`
Expected: PASS — 49 tests (48 + the Context.home test).

- [ ] **Step 5: Commit**

```bash
git add src/context.zig src/root.zig
git commit -m "feat(sdk): add Context type for I/O threading

Implements deferred-B #8 (io/output-dir threading). Context wraps
io + environ_map and delegates to output.zig helpers.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `CallOpts.ctx` field

**Files:**
- Modify: `src/opts.zig`
- Test: in `src/opts.zig`

- [ ] **Step 1: Write the failing test**

Append to `src/opts.zig` (the file currently has no tests):

```zig
const std = @import("std");

test "CallOpts — ctx defaults to null" {
    const opts = CallOpts{};
    try std.testing.expect(opts.ctx == null);
    try std.testing.expect(opts.force == false);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: FAIL — compile error: `CallOpts` has no field `ctx`.

- [ ] **Step 3: Add the field**

In `src/opts.zig`, add the import at the top (after the doc comment, before `pub const CallOpts`):

```zig
const Context = @import("context.zig").Context;
```

Add the field to the struct (after the `force` field):

```zig
    /// Server-owned I/O context. Null for pure-compute tools and for
    /// in-process unit tests that call a wrapper directly. Threaded in by
    /// BaseServer.run(); see context.zig. PORT-NOTE [equivalent]: Python
    /// tools reach request context via FastMCP; Zig threads it explicitly.
    ctx: ?*Context = null,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: PASS — 50 tests. (Adding a defaulted field does not break existing `CallOpts{}` or `CallOpts{ .force = true }` construction anywhere.)

- [ ] **Step 5: Commit**

```bash
git add src/opts.zig
git commit -m "feat(sdk): add optional ctx pointer to CallOpts

Carries the server I/O Context through the existing wrapper channel.
Defaulted to null so pure tools and unit tests are unaffected.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `validates` forwards context to 3-arg impls

**Files:**
- Modify: `src/validation.zig`
- Test: in `src/validation.zig`

This is the core comptime branch. A 2-arg impl `fn(Allocator, Model)` behaves exactly as today. A 3-arg impl `fn(*Context, Allocator, Model)` gets `opts.ctx` forwarded; if `ctx` is null it returns FAIL with a hint.

- [ ] **Step 1: Write the failing tests**

Append to `src/validation.zig` (after the existing tests):

```zig
const Context = @import("context.zig").Context;

const CtxInput = struct { name: []const u8 };

// 3-arg impl: proves the context is forwarded. Returns the home dir so the
// test can assert the ctx was real and usable.
fn testImplWithCtx(ctx: *Context, allocator: std.mem.Allocator, in: CtxInput) Result([]const u8) {
    _ = in;
    const h = ctx.home(allocator) catch {
        return Result([]const u8).fail(.{ .hint = "could not read home from ctx" });
    };
    return Result([]const u8).ok(.{ .value = h });
}

fn ctxTestEnv(allocator: std.mem.Allocator, fake_home: []const u8) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(allocator);
    errdefer map.deinit();
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    try map.put(var_name, fake_home);
    return map;
}

test "validates — 3-arg impl receives forwarded ctx" {
    const allocator = std.testing.allocator;
    var env = try ctxTestEnv(allocator, "/tmp/v-home");
    defer env.deinit();
    var ctx = Context{ .io = undefined, .environ_map = &env };

    const Wrapped = validates(CtxInput, testImplWithCtx);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"name": "x"}
    , .{});
    defer parsed.deinit();

    var r = Wrapped.call(.{ .ctx = &ctx }, allocator, parsed.value);
    defer r.deinit(allocator);
    defer if (r.value) |v| allocator.free(v);

    try std.testing.expect(r.value != null);
    try std.testing.expectEqualStrings("/tmp/v-home", r.value.?);
}

test "validates — 3-arg impl with null ctx returns FAIL+hint" {
    const allocator = std.testing.allocator;
    const Wrapped = validates(CtxInput, testImplWithCtx);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"name": "x"}
    , .{});
    defer parsed.deinit();

    var r = Wrapped.call(.{}, allocator, parsed.value); // no ctx
    defer r.deinit(allocator);

    try std.testing.expect(r.value == null);
    try std.testing.expect(r.hint != null);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — compile error: `testImplWithCtx` has 3 params but `validates` calls `fn_impl(allocator, parsed)` with 2.

- [ ] **Step 3: Add the comptime arity branch**

In `src/validation.zig`, after `const ReturnT = FnInfo.return_type.?;` (line 54), add:

```zig
    // Detect whether the impl wants the server I/O Context. Convention:
    //   2 params  fn(Allocator, Model)          -> pure compute (unchanged)
    //   3 params  fn(*Context, Allocator, Model) -> I/O tool, ctx forwarded
    // The branch on `wants_ctx` is comptime-known, so the dead arm is not
    // analyzed — a 2-arg impl never sees the 3-arg call and vice versa.
    const wants_ctx = FnInfo.params.len == 3;
```

Replace the final line of `call` (line 89, `return fn_impl(allocator, parsed);`) with:

```zig
            if (wants_ctx) {
                const ctx = opts.ctx orelse return ReturnT.fail(.{
                    .hint = "This tool needs server I/O context; it must be called through BaseServer (which threads ctx), not via a bare dispatch.",
                });
                return fn_impl(ctx, allocator, parsed);
            } else {
                return fn_impl(allocator, parsed);
            }
```

Remove the now-incorrect `_ = opts;` line (line 66) — `opts` is now used on the `wants_ctx` path. (If the compiler complains `opts` is unused on the 2-arg path, it won't: a parameter used in any reachable branch counts as used.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS — 52 tests. Critically, the two pre-existing `validates` tests (`testImplSum`, 2-arg) still pass, proving backward compatibility.

- [ ] **Step 5: Commit**

```bash
git add src/validation.zig
git commit -m "feat(sdk): validates forwards Context to 3-arg I/O impls

Comptime-detects fn(*Context, Allocator, Model) vs fn(Allocator, Model).
Pure tools unchanged. Null ctx on an I/O tool returns FAIL+hint.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `BaseServer` threads ctx through dispatch

**Files:**
- Modify: `src/base_server.zig`
- Test: in `src/base_server.zig`

`DispatchFn` gains a `ctx: ?*Context` param. `makeDispatcher` builds `CallOpts{ .ctx = ctx }`. `handleToolsCall` passes `self.ctx`. `run()` takes `environ_map`, builds a `Context`, and stores `&ctx` in `self.ctx` for the loop's lifetime. `handleMessage` is unchanged (tests inject `self.ctx` directly).

- [ ] **Step 1: Write the failing test**

Append to `src/base_server.zig` (after the existing tests, before the final `}` of the file is N/A — these are top-level tests):

```zig
const Context = @import("context.zig").Context;

const TestCtxTool = struct {
    const Input = struct {};
    fn impl(ctx: *Context, allocator: std.mem.Allocator, in: Input) Result([]const u8) {
        _ = in;
        const h = ctx.home(allocator) catch {
            return Result([]const u8).fail(.{ .hint = "no home" });
        };
        return Result([]const u8).ok(.{ .value = h, .mode_tag = "[LOCAL]" });
    }
    pub const Tool = @import("validation.zig").validates(Input, impl);
};

fn bsTestEnv(allocator: std.mem.Allocator, fake_home: []const u8) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(allocator);
    errdefer map.deinit();
    const var_name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    try map.put(var_name, fake_home);
    return map;
}

test "BaseServer — tools/call threads ctx into a 3-arg I/O tool" {
    const allocator = std.testing.allocator;
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    var env = try bsTestEnv(allocator, "/tmp/bs-home");
    defer env.deinit();
    var ctx = Context{ .io = undefined, .environ_map = &env };
    server.ctx = &ctx; // inject directly (run() does this from io+env in production)

    try server.registerTool("whereami", "returns home dir", "{}", TestCtxTool.Tool);

    const line =
        \\{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"whereami","arguments":{}}}
    ;
    const response = (try server.handleMessage(allocator, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"isError\":false") != null);
    // The home dir is escaped inside content.text; search for the raw path.
    try std.testing.expect(std.mem.indexOf(u8, response, "/tmp/bs-home") != null);
}

test "BaseServer — 3-arg tool with no ctx set returns isError=true" {
    const allocator = std.testing.allocator;
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();
    // server.ctx left null

    try server.registerTool("whereami", "returns home dir", "{}", TestCtxTool.Tool);

    const line =
        \\{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"whereami","arguments":{}}}
    ;
    const response = (try server.handleMessage(allocator, line)).?;
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"isError\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "needs server I/O context") != null);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test`
Expected: FAIL — compile error: `BaseServer` has no field `ctx`.

- [ ] **Step 3: Wire ctx through the server**

In `src/base_server.zig`:

(a) Add the import near the top (after line 40, the `protocol` import):

```zig
const Context = @import("context.zig").Context;
```

(b) Change `DispatchFn` (lines 48-52) to take the context:

```zig
const DispatchFn = *const fn (
    ctx: ?*Context,
    allocator: std.mem.Allocator,
    args: std.json.Value,
    jws: *std.json.Stringify,
) anyerror!bool;
```

(c) Add the `ctx` field to `BaseServer` (after the `initialized` field, line 67):

```zig
    ctx: ?*Context = null,
```

(d) Update `makeDispatcher` (lines 109-122) so the inner dispatch accepts and uses ctx:

```zig
    fn makeDispatcher(comptime ToolType: type) DispatchFn {
        return struct {
            fn dispatch(
                ctx: ?*Context,
                allocator: std.mem.Allocator,
                args: std.json.Value,
                jws: *std.json.Stringify,
            ) anyerror!bool {
                var result = ToolType.call(CallOpts{ .ctx = ctx }, allocator, args);
                defer result.deinit(allocator);
                try jws.write(result);
                return result.status == Status.FAIL;
            }
        }.dispatch;
    }
```

(e) Update the dispatch call site in `handleToolsCall` (line 257) to pass `self.ctx`:

```zig
        const is_error = tool.dispatch(self.ctx, allocator, args, &inner_jws) catch |err| {
```

(f) Change `run` (line 303) to take `environ_map`, build a Context, and store it:

```zig
    pub fn run(self: *BaseServer, io: std.Io, environ_map: *const std.process.Environ.Map) !void {
        var ctx = Context{ .io = io, .environ_map = environ_map };
        self.ctx = &ctx;
        defer self.ctx = null;

        const stdin = std.Io.File.stdin();
        const stdout = std.Io.File.stdout();
```

(Leave the rest of `run`'s body unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test`
Expected: PASS — 54 tests. The existing `TestEcho`/`TestFail` (2-arg, `ctx` ignored) still pass.

- [ ] **Step 5: Commit**

```bash
git add src/base_server.zig
git commit -m "feat(sdk): thread Context through BaseServer dispatch

DispatchFn carries ?*Context; run() builds it from io+environ_map and
stores it for the loop lifetime; tools/call forwards self.ctx. 2-arg
tools unaffected.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Update reference MCP + scaffold template to new `run()` signature

**Files:**
- Modify: `reference-mcp/adam-greet-zig/src/main.zig`
- Modify: `src/cli/templates.zig` (the `src/main.zig` template string for generated MCPs)
- Modify: `tools/smoke_test.sh` and `tools/smoke_test.ps1` only if they call `run` (they drive the built binary over stdio, so likely no change — verify)
- Test: `zig build test` + the reference MCP smoke test

- [ ] **Step 1: Find every `.run(` call site**

Run: `grep -rn "\.run(" reference-mcp src/cli/templates.zig`
Expected: the reference MCP `main.zig` calls `server.run(init.io)`; `templates.zig` contains a `main.zig` template with the same call.

- [ ] **Step 2: Update the reference MCP main**

In `reference-mcp/adam-greet-zig/src/main.zig`, change:

```zig
    try server.run(init.io);
```
to:
```zig
    try server.run(init.io, &init.environ_map);
```

- [ ] **Step 3: Update the scaffold template**

In `src/cli/templates.zig`, find the `main.zig` template literal containing `server.run(init.io)` (the same call inside the generated-MCP template) and change it to `server.run(init.io, &init.environ_map)` so freshly scaffolded MCPs compile against the new signature.

- [ ] **Step 4: Rebuild everything and run the suite + smoke test**

Run:
```bash
zig build
zig build test
./tools/smoke_test.sh
```
Expected: build succeeds; 54 tests pass; smoke test prints its initialize → tools/list → tools/call success lines with no error.

- [ ] **Step 5: Verify a freshly scaffolded MCP still builds**

Run:
```bash
./zig-out/bin/adam-mcp new tmp-scaffold-check --target /tmp/tmp-scaffold-check
cd /tmp/tmp-scaffold-check
# fix fingerprint if the build asks; point the dep path at the SDK if needed
zig build 2>&1 | head -40
cd ~/Projects/adam-mcp-zig
rm -rf /tmp/tmp-scaffold-check
```
Expected: the generated MCP compiles (or fails only on the known fingerprint/dep-path step, which is a scaffold-config issue, not the `run` signature). If it fails on `run` arity, the template wasn't updated — fix Step 3.

- [ ] **Step 6: Commit**

```bash
git add reference-mcp/adam-greet-zig/src/main.zig src/cli/templates.zig
git commit -m "refactor(sdk): update run() call sites for environ_map param

Reference MCP and the scaffold template now call
server.run(init.io, &init.environ_map).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Per-request arena in the dispatcher (closes deferred-B #5)

**Files:**
- Modify: `src/base_server.zig` (`handleToolsCall`)
- Test: in `src/base_server.zig`

Today each tool call leaks its `value` allocation (`Result.deinit` frees only metrics+diagnostics). I/O tools return large parsed vectors, so this matters. Wrap the dispatch in a per-call arena: the tool allocates into the arena; the Result is serialized into `inner_buf` (owned by the long-lived allocator) *before* the arena is freed; then the arena is dropped wholesale.

- [ ] **Step 1: Write the failing test**

Append to `src/base_server.zig`:

```zig
// A tool that allocates a sizeable value every call. Under std.testing.allocator
// (which detects leaks) this passes only if the dispatcher frees the allocation.
const TestAllocTool = struct {
    const Input = struct {};
    fn impl(allocator: std.mem.Allocator, in: Input) Result([]const u8) {
        _ = in;
        const blob = allocator.alloc(u8, 4096) catch {
            return Result([]const u8).fail(.{ .hint = "oom" });
        };
        @memset(blob, 'a');
        return Result([]const u8).ok(.{ .value = blob });
    }
    pub const Tool = @import("validation.zig").validates(Input, impl);
};

test "BaseServer — per-request arena frees tool value allocations" {
    const allocator = std.testing.allocator; // leak-checking allocator
    var server = BaseServer.init(allocator, "test-server");
    defer server.deinit();

    try server.registerTool("blob", "allocates 4k", "{}", TestAllocTool.Tool);

    // Call several times; if value allocations leaked, testing.allocator fails.
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const line =
            \\{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"blob","arguments":{}}}
        ;
        const response = (try server.handleMessage(allocator, line)).?;
        allocator.free(response);
    }
    // No explicit assert: the test passes iff std.testing.allocator reports no leak.
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: FAIL — `std.testing.allocator` reports a memory leak (5 × 4096 bytes from the tool `value`, which the current dispatcher never frees).

- [ ] **Step 3: Add the arena in `handleToolsCall`**

In `src/base_server.zig` `handleToolsCall`, locate the block that creates `inner_buf` and calls `tool.dispatch` (lines ~252-260). Introduce an arena and pass its allocator to dispatch. `inner_buf` stays on the long-lived `allocator` so the serialized JSON survives the arena drop:

```zig
        // Per-request arena: the tool allocates freely into `arena`; its
        // Result is serialized into inner_buf (long-lived allocator) inside
        // dispatch, then the arena is dropped wholesale. Closes deferred-B #5.
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tool_alloc = arena.allocator();

        var inner_buf: std.Io.Writer.Allocating = .init(allocator);
        defer inner_buf.deinit();
        var inner_jws: std.json.Stringify = .{ .writer = &inner_buf.writer };

        const is_error = tool.dispatch(self.ctx, tool_alloc, args, &inner_jws) catch |err| {
            log.warn("tool '{s}' dispatch error: {s}", .{ tool_name, @errorName(err) });
            return try buildInternalError(allocator, id, "tool dispatch failed");
        };
```

(Replace the existing `inner_buf`/`inner_jws`/`is_error` lines with the block above. Note dispatch now receives `tool_alloc`, not `allocator`. `Result.deinit(tool_alloc)` inside the dispatcher is harmless on an arena allocator.)

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: PASS — 55 tests, no leak reported. All prior tests still pass (the arena is transparent to them).

- [ ] **Step 5: Add the PORT-NOTE and update ROADMAP**

In `src/base_server.zig`, replace the `PORT-NOTE [deferred-B]` block above `makeDispatcher` (lines 99-108) describing the per-call leak with a `PORT-NOTE [equivalent]` noting the per-request arena now frees tool allocations after serialization. In `ROADMAP.md`, mark deferred-B #5 (per-request arena) and #8 (io threading) as resolved by this plan.

- [ ] **Step 6: Commit**

```bash
git add src/base_server.zig ROADMAP.md
git commit -m "feat(sdk): per-request arena frees tool allocations (deferred-B #5)

Tool impls allocate into a per-call arena; Result is serialized before
the arena drops. Closes the documented per-call value leak.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: CHANGELOG + version bump

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `build.zig.zon` (version) and/or wherever the SDK version string lives

- [ ] **Step 1: Find the version string**

Run: `grep -rn "version" build.zig.zon CHANGELOG.md | head`
Expected: locate the current `.version = "0.x.y"` in `build.zig.zon`.

- [ ] **Step 2: Bump the minor version**

Edit `build.zig.zon`: bump the minor version (additive capability, no breaking envelope change), e.g. `0.1.0` → `0.2.0`.

- [ ] **Step 3: Add a CHANGELOG entry**

Add an `### Added` section under a new version heading in `CHANGELOG.md`:

```markdown
## [0.2.0] - 2026-05-29

### Added
- `Context` type (io + environ_map) threaded into tool dispatch via `CallOpts.ctx`.
- `validates` comptime-detects 3-arg I/O impls `fn(*Context, Allocator, Model)` and forwards the context; 2-arg pure impls unchanged.
- Per-request arena in the dispatcher frees tool `value` allocations after serialization.

### Changed
- `BaseServer.run` now takes `(io, environ_map)`. Reference MCP and scaffold template updated.

### Notes
- `Result` wire envelope unchanged; no `ENVELOPE_VERSION` bump. Resolves deferred-B #5 and #8.
```

- [ ] **Step 4: Run the full suite one last time**

Run: `zig build test && ./tools/smoke_test.sh`
Expected: 55 tests pass; smoke test green.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md build.zig.zon
git commit -m "chore(sdk): release 0.2.0 — I/O context + per-request arena

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage** (against design spec §2):
- §2.2a Context type → Task 1 ✓
- §2.2b CallOpts.ctx → Task 2 ✓
- §2.2c dispatcher threading + run() signature → Task 4 ✓
- §2.2e comptime arity detection in `validates` → Task 3 ✓ (`passthrough` needs no change — it forwards `validates`' `call`; `requires` is out of scope per §3.6, guardrails are in-impl)
- §2.3 per-request arena pulled forward → Task 6 ✓; version bump → Task 7 ✓
- §2.4 tests: 3-arg tool end-to-end (Task 4), null-ctx FAIL (Tasks 3+4), 48 existing pass (every task's Step 4) ✓

**Placeholder scan:** No TBD/TODO. Every code step shows complete Zig. The one non-code judgment ("fix fingerprint if the build asks" in Task 5 Step 5) is a known scaffold-config quirk, not a plan gap.

**Type consistency:** `Context{ .io, .environ_map }`, `CallOpts{ .ctx }`, `DispatchFn(ctx, allocator, args, jws)`, `fn(*Context, Allocator, Model)` impl shape, and `std.process.Environ.Map` are used identically across Tasks 1–6. `validates` 3-arg detection (Task 3) matches the impl shapes registered in Tasks 4 and 6.

**Known risk carried forward:** The comptime dead-branch elimination in Task 3 (`if (wants_ctx)`) is the one piece relying on Zig not analyzing the untaken arm of a comptime-known `if`. Task 3 Step 4 (build + run) is the verification gate; if the 2-arg arm gets analyzed for a 3-arg impl (or vice versa), the fix is to split into two `inline`-selected helper functions. This is a build-time catch, not a latent bug.
