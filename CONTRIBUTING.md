# Contributing to adam-mcp-zig

Thanks for your interest. A few expectations before sending a PR.

## File an issue first

For anything beyond a typo or a one-line bug fix, open an issue first so we can sanity-check direction before you spend time on a patch. Small docs / typo PRs without a prior issue are welcome.

## Required reading

[`HOUSE_STYLE.md`](./HOUSE_STYLE.md) is the methodology spec — what a tool is, what a `Result` is, what an escape hatch is. The same methodology is documented in the [Python sibling repo](https://github.com/dreliq9/adam-mcp-sdk/blob/main/HOUSE_STYLE.md) using Python-native examples; both specs use the same `rule_id` numbering (§3.18 stability) so cross-language audit findings line up.

[`SPEC.md`](./SPEC.md) is the Zig-specific contract — argv, env, stdio, wire shape, platform support. Distinct from HOUSE_STYLE.md, which is language-agnostic methodology.

## PORT-NOTE discipline

Every Python feature that diverges from a verbatim translation needs a `PORT-NOTE [<status>]` comment with one of:

- `equivalent` — same behavior, idiomatic-Zig implementation.
- `dropped` — explicitly not ported; requires a `DECISIONS.md` entry naming the reason.
- `deferred-B` — Phase B follow-up; track in `ROADMAP.md`.
- `n/a-language` — Zig has no analog (e.g. Python's `@dataclass` decorator).

Silent drops are not acceptable. If you can't write a `PORT-NOTE`, the change probably needs a discussion in the issue first.

## Testing

```bash
zig build test                                # 48 tests, native target
zig build -Dtarget=x86_64-windows-gnu         # cross-compile to Windows
zig build -Dtarget=x86_64-linux-gnu           # cross-compile to Linux
./tools/smoke_test.sh                         # end-to-end stdio loop
```

Tests must pass on the three big triples (`x86_64-linux-gnu`, `x86_64-macos`/`aarch64-macos`, `x86_64-windows-gnu`). CI runs all three on every PR.

## Cross-platform rules (`src/`)

- Stdio I/O goes through `std.Io.File.stdin()` / `stdout()` with the supplied `io: std.Io`. Never `std.posix.read`, `std.posix.STDIN_FILENO`, or `std.c.write` — Windows HANDLEs aren't file descriptors.
- Env vars come from `init.environ_map.get(name)`. 0.16 removed global env accessors; the environment is owned by `std.process.Init`. Use the `homeDir(allocator, env)` helper for the cross-platform HOME / USERPROFILE lookup.
- Argv comes from `init.minimal.args.toSlice(arena)` — returns WTF-8 strings on Windows, opaque bytes on POSIX. Don't index `args.vector` directly (it's `[]const u16` on Windows).
- Templates may use `/` as a path separator; Zig stdlib converts internally on Windows.

## Audit rule IDs are stable

`rule_id` strings (`§N.NN`) in `src/cli/audit_rules.zig::registry` are frozen forever once published. See §3.18 in the spec. A rule may be deprecated (removed from `registry`) but its `rule_id` is reserved permanently — never reassigned to a different rule. Removals get a `DECISIONS.md` entry.

## Pre-1.0

The public API in `src/root.zig` may break between minor versions until v1.0. Breaking changes require a `CHANGELOG.md ### Breaking` entry citing the affected rule_id.

## Style

Run `zig fmt src/ tests/` before committing. CI rejects unformatted code.

## License

By contributing, you agree your contributions will be licensed under the MIT License, same as the rest of the project. See [LICENSE](./LICENSE).
