//! Validation wrapper — implements §1.2 of HOUSE_STYLE.md.
//!
//! `validates(Model, fn_impl)` returns a wrapper type whose `call`
//! function:
//!   1. Receives a std.json.Value (or anonymous struct literal in tests).
//!   2. Parses it into the typed `Model` struct.
//!   3. On parse failure, returns Result.fail with diagnostics.
//!   4. On success, invokes the inner fn_impl with the typed Model.
//!
//! PORT-NOTE [equivalent]: Python's `@validates(Model)` decorator uses
//!   Pydantic: `model(**input)` instantiates a BaseModel; ValidationError
//!   carries per-field loc+msg pairs that we format into diagnostics.
//!   Zig uses std.json.parseFromValueLeaky into a plain struct; the
//!   parse-error set covers UnknownField/MissingField/UnexpectedToken etc.
//!   Error mapping is direct from the error set to Result.fail.
//!
//! PORT-NOTE [deferred-B]: Pydantic gives rich per-field error info
//!   (`err['loc']` is a tuple path, `err['msg']` is human-readable).
//!   std.json's parseFromValueLeaky returns only the error tag from the
//!   error set — no field path. Phase B will either (a) hand-roll
//!   field-by-field validation via @typeInfo for richer diagnostics, or
//!   (b) use std.json.Scanner with diagnostics tracking to pinpoint the
//!   offending location. For Phase A we surface @errorName as the
//!   diagnostic and use a generic hint.

const std = @import("std");
const Result = @import("result.zig").Result;
const CallOpts = @import("opts.zig").CallOpts;

/// Wrap a tool function so it receives a typed Model parsed from JSON.
/// Implements §1.2.
///
/// `fn_impl` must have signature `fn(Allocator, Io, Model) Result(OutputT)`.
/// `Io` is `std.Io` — the vtable through which file/subprocess/network
/// syscalls go in Zig 0.16. Tools that don't perform I/O take `io` as a
/// `_ = io;` no-op; the parameter is mandatory so the dispatch shape is
/// uniform.
///
/// Usage:
///   const my_tool = validates(MyInput, struct {
///       fn impl(alloc: std.mem.Allocator, io: std.Io, in: MyInput) Result(MyOutput) {
///           const bytes = std.Io.Dir.cwd().readFileAlloc(io, in.path, alloc, .unlimited) catch {
///               return Result(MyOutput).fail(.{ .hint = "read failed" });
///           };
///           defer alloc.free(bytes);
///           return Result(MyOutput).ok(.{ .value = .{...} });
///       }
///   }.impl);
///
///   // Caller side (typically the JSON-RPC router):
///   const result = my_tool.call(.{}, alloc, io, json_value);
///
/// PORT-NOTE [equivalent]: Python's wrapper accepts either a dict OR an
///   already-parsed Model instance (early-return if `isinstance(input,
///   model)`). Zig's wrapper accepts std.json.Value only — pre-parsed
///   Model values can't be passed because the parameter type is fixed.
///   This is observably equivalent for the registration path (JSON
///   always arrives as std.json.Value); tests that want to bypass
///   parsing call fn_impl directly.
///
/// PORT-NOTE [n/a-language]: Python tool callbacks receive only
///   `(allocator-equivalent, model)` — there is no Io vtable in Python.
///   Zig 0.16 routes every blocking syscall (file read, subprocess
///   spawn, network) through `std.Io`, so Zig tool callbacks take
///   `(Allocator, Io, Model)`. This signature difference is internal:
///   the wire format (JSON-RPC envelope, Result fields, byte order)
///   is identical in both languages. Cross-language byte equivalence
///   is preserved.
pub fn validates(comptime Model: type, comptime fn_impl: anytype) type {
    const FnInfo = @typeInfo(@TypeOf(fn_impl)).@"fn";
    const ReturnT = FnInfo.return_type.?;
    // Detect whether the impl wants the server I/O Context. Convention:
    //   2 params  fn(Allocator, Model)          -> pure compute (unchanged)
    //   3 params  fn(*Context, Allocator, Model) -> I/O tool, ctx forwarded
    // The branch on `wants_ctx` is comptime-known, so the dead arm is not
    // analyzed — a 2-arg impl never sees the 3-arg call and vice versa.
    const wants_ctx = FnInfo.params.len == 3;

    return struct {
        /// Marker exposing the input model for the audit pass / future
        /// JSONSchema generation (deferred to Phase B).
        pub const adam_mcp_input_model = Model;

        pub fn call(
            opts: CallOpts,
            allocator: std.mem.Allocator,
            io: std.Io,
            input: std.json.Value,
        ) ReturnT {
            const parsed: Model = std.json.parseFromValueLeaky(
                Model,
                allocator,
                input,
                .{},
            ) catch |err| {
                // PORT-NOTE [deferred-B]: Phase A surfaces only the
                //   error name. Phase B will widen diagnostics with
                //   per-field path info (via @typeInfo walk or
                //   std.json.Scanner with Diagnostics tracking).
                var diag: std.ArrayList([]const u8) = .empty;
                diag.append(allocator, @errorName(err)) catch {
                    // OOM building diagnostics — return without them.
                    return ReturnT.fail(.{
                        .hint = "Fix input fields and retry.",
                    });
                };
                return ReturnT.fail(.{
                    .hint = "Fix input fields and retry. See diagnostics for the parser error.",
                    .diagnostics = diag,
                });
            };

            // Combined logic: support both std.Io plumbing (remote 0.3.0) and Context forwarding for I/O tools (local Context work).
            // - ctx tools: impl takes ( *Context, Allocator, Model ), ctx bundles .io + environ etc.
            // - non-ctx tools (incl. direct I/O): impl takes ( Allocator, Io, Model )
            if (comptime wants_ctx) {
                const ctx = opts.ctx orelse return ReturnT.fail(.{
                    .hint = "This tool needs server I/O context; it must be called through BaseServer (which threads ctx), not via a bare dispatch.",
                });
                return fn_impl(ctx, allocator, parsed);
            } else {
                return fn_impl(allocator, io, parsed);
            }
        }
    };
}

// =============================================================================
// Tests
// =============================================================================

const TestInput = struct {
    x: i32,
    y: i32,
};

fn testImplSum(allocator: std.mem.Allocator, io: std.Io, in: TestInput) Result(i32) {
    _ = allocator;
    _ = io;
    return Result(i32).ok(.{ .value = in.x + in.y });
}

test "validates — happy path parses JSON into typed model and calls inner" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const Wrapped = validates(TestInput, testImplSum);

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        \\{"x": 3, "y": 4}
    ,
        .{},
    );
    defer parsed.deinit();

    var r = Wrapped.call(.{}, allocator, io, parsed.value);
    defer r.deinit(allocator);

    try std.testing.expectEqual(@as(?i32, 7), r.value);
}

test "validates — invalid input returns Result.fail with hint" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const Wrapped = validates(TestInput, testImplSum);

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        \\{"x": "not-a-number", "y": 4}
    ,
        .{},
    );
    defer parsed.deinit();

    var r = Wrapped.call(.{}, allocator, io, parsed.value);
    defer r.deinit(allocator);

    try std.testing.expect(r.hint != null);
    try std.testing.expect(r.value == null);
}

test "validates — exposes input model marker for audit" {
    const Wrapped = validates(TestInput, testImplSum);
    try std.testing.expect(@hasDecl(Wrapped, "adam_mcp_input_model"));
    try std.testing.expectEqual(TestInput, Wrapped.adam_mcp_input_model);
}

// =============================================================================
// 3-arg (ctx-forwarding) tests
// =============================================================================

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

    // Use an arena so parseFromValueLeaky's CtxInput.name allocation is freed
    // when the arena is destroyed — keeps std.testing.allocator leak-free.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const call_alloc = arena.allocator();

    const r = Wrapped.call(.{ .ctx = &ctx }, call_alloc, parsed.value);
    // r.value (the home string) was allocated by testImplWithCtx via
    // ctx.home(call_alloc) — it lives in the arena, freed by arena.deinit().
    // r.deinit would double-free it, so we skip it and rely on the arena.
    _ = r;

    // Re-run with the testing allocator just to assert the value, keeping the
    // home string in a separate scope so we can free it correctly.
    var arena2 = std.heap.ArenaAllocator.init(allocator);
    defer arena2.deinit();
    var r2 = Wrapped.call(.{ .ctx = &ctx }, arena2.allocator(), parsed.value);
    try std.testing.expect(r2.value != null);
    try std.testing.expectEqualStrings("/tmp/v-home", r2.value.?);
    r2.value = null; // prevent r2.deinit from freeing arena-owned memory
    r2.deinit(arena2.allocator());
}

test "validates — 3-arg impl with null ctx returns FAIL+hint" {
    const allocator = std.testing.allocator;
    const Wrapped = validates(CtxInput, testImplWithCtx);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"name": "x"}
    , .{});
    defer parsed.deinit();

    // Arena absorbs the CtxInput.name allocation from parseFromValueLeaky.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var r = Wrapped.call(.{}, arena.allocator(), parsed.value); // no ctx
    // r.hint is a string literal (comptime), not heap — safe to check then drop.
    try std.testing.expect(r.value == null);
    try std.testing.expect(r.hint != null);
    // r has no heap-owned fields here (null ctx means we returned before
    // calling fn_impl, so no Result.value allocation). r.deinit is a no-op
    // but call it for discipline.
    r.deinit(arena.allocator());
}
