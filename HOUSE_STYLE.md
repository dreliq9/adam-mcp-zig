# House Style — Adam's MCPs (Zig pack)

**Version:** 2026.05 (CalVer; spec is the slow-moving source of truth)

This is the source of truth for how MCPs are built in Adam's Zig stack. Every library symbol, template, audit rule, and skill embeds rules from this document. Cross-links are mandatory: every rule names its corresponding library symbol; every library symbol names its rule.

**Sibling spec:** the cross-language methodology is shared with the Python pack at [adam-mcp-sdk/HOUSE_STYLE.md](https://github.com/dreliq9/adam-mcp-sdk/blob/main/HOUSE_STYLE.md). Both specs use the same `rule_id` numbering (§3.18 stability) so cross-language audit findings line up. This document is the Zig-native equivalent — same rules, Zig examples and library symbols. When a rule applies only to one language pack, it's marked.

---

## Principle Zero — AI-shaped, not API-shaped

The unit of a tool is "a coherent thing an AI can do," not "an API endpoint."

If clumping multiple API calls into one workflow-shaped tool makes the AI parse it better, do that. If splitting one API call into multiple specialized tools makes the AI parse it better, do that. The API surface is irrelevant to the tool surface.

Every other rule in this document descends from this one.

**You will be tempted to write one tool per API endpoint. Don't.** That's the shallow-wrapper default. The unit of work is what an AI does, not what an API exposes.

**Auditability ceiling.** Principle Zero is the SDK's most important rule and its least mechanically auditable — "is this tool AI-shaped?" is a judgment, not a regex. The canonical check is human review at LLM_GUIDE time: writing the LLM_GUIDE per §3.14 — describing each tool's purpose, parameter gotchas, and failure modes — surfaces API-shapedness because shallow wrappers are awkward to describe. There is no reliable mechanical proxy; resist the urge to add one (e.g., tool/endpoint ratio heuristics catch over-splitting but miss over-clumping, which is the more common failure).

## Principle One — Escape hatches always available

Tools shaped for AI consumption are the happy path. They are not a cage.

When an agent's task doesn't fit any tool's shape, it must be able to drop down to the underlying API/library/protocol directly. The MCP adds value by lifting common cases; it must never block the uncommon case.

Canonical example: `caid-mcp`'s `run_cadquery_script` (Python pack). Full validated tool surface for common operations, plus an unconstrained script-runner for everything else. The Zig reference MCP `adam-greet-zig` ships `compose_raw_greeting` as its `passthrough`-marked equivalent.

---

## §1 Tool contract

### §1.1 Result type

Every tool returns a typed `Result(comptime T: type)` with fields `(envelope_version, status, value, raw, metrics, diagnostics, hint, mode_tag)`. Never raw output. Never raw exceptions.

| Field | Type | Purpose |
|-------|------|---------|
| `envelope_version` | `i32` (default `1`) | Wire-format version. First field so parsers can short-circuit on mismatch. See [DECISIONS 2026-05-19 envelope versioning](https://github.com/dreliq9/adam-mcp-sdk/blob/main/DECISIONS.md). |
| `status` | `Status` (`OK`/`WARN`/`FAIL`) | Outcome category |
| `value` | `?T` | Synthesized/typed output for AI consumption |
| `raw` | `?Raw` (= `std.json.Value`) | Underlying API response when applicable (Principle One support). **Typed `std.json.Value` by contract** — `raw` is the documented exception to strict typing, because it carries unknown-shape payloads from foreign APIs. An individual MCP may decode `raw` into a project-specific type if its backend response is fully known. |
| `metrics` | `StringHashMapUnmanaged(std.json.Value)` | Numeric/scalar measurements (`elapsed_ms`, `bytes_read`, etc.) |
| `diagnostics` | `std.ArrayList([]const u8)` | What happened, in human terms |
| `hint` | `?[]const u8` | What to try next on FAIL/WARN |
| `mode_tag` | `?[]const u8` | Which backend/path was used (e.g., `[IPC]`, `[FILE]`, `[LOCAL]`) |

**If you can't write a useful `hint` on FAIL, the tool's shape is wrong.**

**Envelope is a wire format.** Cross-language byte-equivalence makes `Result` a serialization format, not just an in-process Zig struct. Field order is contractual — `tools/byte_equivalence_check.sh` enforces it against the Python pack. New top-level fields require an `envelope_version` bump and a CHANGELOG `### Breaking` entry, coordinated across both language packs.

→ Library: `adam_mcp_zig.Result`, `adam_mcp_zig.Raw`, `adam_mcp_zig.ENVELOPE_VERSION`

### §1.2 Validation layer

The MCP validates inputs before delegating to the underlying API. It catches silent failures (e.g., out-of-bounds values, malformed payloads), surfaces actionable diagnostics. Underlying API rawness must not bleed through unless the agent opts in via `Result.raw` or an escape-hatch tool.

In Zig: input validation is comptime-driven via `validates(comptime Model: type, fn impl)`. The `Model` is a Zig struct with field types; parse failures from `std.json.parseFromValueLeaky` become `Result.fail` with diagnostics.

→ Library: `adam_mcp_zig.validates`

### §1.3 Process guardrails

Preconditions are enforced before destructive operations (e.g., schema-valid before write; capability gate before exec).

Default severity is **WARN**. **FAIL** only when the consequence is genuinely destructive. Override via explicit `force = true` on `CallOpts`, with required justification in the call.

In Zig: `requires(comptime precondition, hint, severity, fn impl)` is a comptime wrapper. The non-optional `hint` field on `WarnOpts` / `FailOpts` enforces the "every WARN/FAIL has a hint" rule at compile time.

→ Library: `adam_mcp_zig.requires`, `adam_mcp_zig.CallOpts`, `adam_mcp_zig.Severity`

### §1.4 Mode/path transparency

When the server has multiple backends, the result tells the agent which one was used (`[IPC]` vs `[FILE]`, `[LOCAL]` vs `[WEB]`). Set `Result.mode_tag`.

→ Library: `adam_mcp_zig.Backend`, `adam_mcp_zig.detectBackend`

### §1.5 [Python-pack only — RESERVED in Zig pack]

§1.5 in the Python pack governs `@validates` parameter naming under FastMCP. It exists because FastMCP's `@wraps`-driven schema generation publishes the original function's first parameter name as a JSONSchema field, and the `validates` wrapper expects that name to be `input`.

**The Zig pack has no equivalent issue.** Zig's `validates(comptime Model: type, fn impl)` takes the model as a comptime type parameter, not a function parameter; there is no JSONSchema field generated from a parameter name. Parameter naming is the implementation function's concern, irrelevant to wire-format.

`rule_id` §1.5 is reserved in the Zig pack registry per §3.18 (never reassigned to a different rule), but no Zig audit rule is registered against it. If FastMCP changes its schema-generation behavior, the Python pack will deprecate §1.5 and route the replacement into [Appendix A](#appendix-a--framework-integration-notes); the Zig pack will not be affected.

→ See Python pack §1.5.

---

## §2 Architecture

### §2.5 Three-layer

Core lib → MCP layer → CLI. The MCP is a thin wrapper over a usable library; the CLI is too. Tools never reach into framework internals.

In Zig: `src/<package>.zig` (lib) → `src/mcp/*.zig` (MCP layer) → `src/cli/*.zig` (CLI). The reference MCP `adam-greet-zig` demonstrates the layering.

→ Template: `src/cli/templates.zig` (the 17-file scaffold rendered by `adam-mcp new`).

### §2.6 Pluggable backends

When there's an underlying engine, abstract over it via a vtable. `src/backends/` directory; each backend implements the `Backend` interface.

→ Library: `adam_mcp_zig.Backend`

### §2.7 Tool file organization

Tools live in `src/mcp/<area>_tools.zig`, grouped by concern. Suffix is `_tools.zig`. Never one giant `server.zig`.

Examples: `greeting_tools.zig`, `context_tools.zig`, `analysis_tools.zig`, `edit_tools.zig`.

### §2.8 Workflows directory

Higher-order compositions distinct from atomic tools live in `src/workflows/`. A workflow orchestrates many atomic ops.

→ Library: `adam_mcp_zig.Workflow`

### §2.9 Schema and types separated

`src/schema.zig` and `src/types.zig` exist as separate modules. They contain only type/schema definitions, no logic. The split helps the audit see "what shapes does this MCP define" without parsing tool implementations.

### §2.10 Predictable output location

Side effects go to `~/<domain>-output/` on POSIX, `%USERPROFILE%\<domain>-output\` on Windows. Use `outputDir(allocator, io, environ_map, name)` from the library.

→ Library: `adam_mcp_zig.outputDir`, `adam_mcp_zig.homeDir`

### §2.11 Pinned exact dependencies

Every MCP project's `build.zig.zon` pins exact `.url` + `.hash` for each dependency. Zig's package manager has no semver ranges — every dep is hash-pinned by design, so the "boring stable deps whitelist" from the Python pack has no equivalent here. The Zig substrate enforces what the Python rule prescribes.

When updating a dependency: bump the URL to the new tarball / tag, delete the `.hash`, run `zig build --fetch`, commit the resulting hash.

### §2.12 Underlying clients publicly importable

The lib layer must expose its dependencies. `pub const client = @import("backends/client.zig")` must work from outside the package. No hiding, no proxying. (Principle One.)

---

## §3 Documentation

### §3.13 SPEC.md is law

Versioned. Written before tools. No silent scope creep.

Mid-build discoveries are allowed — but require a `DECISIONS.md` entry + SPEC.md update *before* the code lands. The rule is "never quietly violate the spec," not "never deviate from the original." If the rule ever feels like "violate when needed," the spec is missing a documented path for honest scope expansion — add one.

### §3.14 LLM_GUIDE.md

Agent-facing usage guide. Lives next to README. Required sections:
- **Overview** — what this MCP is and what it does
- **Critical workflow** — order of operations that matters
- **Tool categories** — one paragraph per `_tools.zig`
- **Parameter gotchas** — non-obvious input details
- **Failure → fix** — what each FAIL means and how to recover
- **Mode/path transparency** — what each `mode_tag` means
- **Escape hatches** — when to drop down, how, what `Result.raw` contains for each tool

### §3.15 CLAUDE.md

Routing/usage discipline. Required sections:
- **When to use this MCP** — the trigger phrases
- **When NOT to use this MCP** — boundaries
- **When to drop down to underlying APIs** — Principle One in practice
- **Co-tools** — what other MCPs/skills pair well

### §3.16 AUDIT.md

Periodic research-driven SOTA survey. Compiled from parallel research agents. Compares "current" vs "best-in-class" with explicit upgrade plan. Re-run quarterly.

### §3.17 Working artifacts

- `CHANGELOG.md` — Keep a Changelog format
- `ROADMAP.md` — what's coming, what's deferred
- `DECISIONS.md` — architectural decision log
- `DEVLOG.md` — running notes during implementation
- `task_plan.md`, `progress.md`, `findings.md` — planning-with-files artifacts inside the project

### §3.18 — Audit rule_id stability

`rule_id` strings (`§N.NN`) in `src/cli/audit_rules.zig::registry` are stable forever once published. They are the cross-link substrate for the upgrade system (audit-as-migration); a rename or reassignment would silently break downstream MCPs' upgrade paths.

**Cross-pack stability:** `rule_id`s are shared across language packs. §1.1 means the same thing in the Zig pack and the Python pack. New rules in either pack take the next free number across both — coordinate via DECISIONS.md.

**Rules:**
- Once a rule_id appears in a tagged release of any language pack, its meaning is frozen across all packs.
- A rule may be deprecated (removed from a pack's `registry`) but its `rule_id` is reserved permanently — never reassigned to a different rule. Removals recorded in `DECISIONS.md`.
- A pack may legitimately have rules that don't apply in its language (e.g., §1.5 doesn't apply in Zig). Mark as reserved-but-not-registered; don't reassign.
- New rules use the next free number across both packs.
- A rule's `severity_default` may change across versions in a given pack. That is a breaking change and requires a CHANGELOG `### Breaking` entry referencing the rule_id, but the rule_id itself stays put.
- A rule's `check` function may be tightened (stricter behavior under the same rule_id). That is also a breaking change.

→ CLI: `adam_mcp_zig.audit_rules.AuditRule` (the struct that carries the rule_id).

**Cross-link enforcement:** `adam-mcp audit --self-check` (Python pack) and the future Zig equivalent verify that every registry rule_id appears in this spec, and that every CHANGELOG `### Breaking` bullet's `**§X.Y**` resolves to a real rule_id.

---

## §4 Authoring patterns (apply when relevant)

Not every MCP needs all of these.

### §4.18 Multi-source synthesis
Pull from N sources, return composite. Example: `vulnerability-intelligence` synthesizes NVD + CISA KEV + EPSS into composite risk.

### §4.19 Stateful server context
Server remembers profile/watchlist/history; every response is enriched.

### §4.20 Tool composition / pipelines
Tools designed to be chained by an agent. Example: `qa-hard` is `build_evaluator_prompts → dispatch → build_weigher_prompts → dispatch → finalize`.

### §4.21 Bundled subagents
Companion agents shipped with the MCP. Example: `local-llm-gateway` ships `batch-processor`, `draft-refine`, `tiered-reviewer`.

### §4.22 Domain logic baked in
Server has its own engine/rules/kernel. Example: `archi` has its own kernel + rules; tools call that, not an external API.

### §4.23 Parallel fan-out
Tools that orchestrate batched/parallel work across subagents/models. Example: `corpus-retrieval` summarize-pending fans out parallel Haiku 4.5 subagents.

### §4.24 Agent-aware result formatting
Outputs shaped for an agent: structured value + summary diagnostics + next-step hint, not raw API JSON.

---

## §5 Cross-link contract

### §5.25 Spec rules name library symbols

Every rule above with a `→ Library:` pointer must name an exact symbol that exists in `adam_mcp_zig` (i.e., is exported from `src/root.zig`).

### §5.26 Library symbols name rules

Every public symbol in `adam_mcp_zig` has a doc comment naming the rule it implements (e.g., `/// Implements §1.1.`).

### §5.27 Audit self-check

`adam-mcp audit --self-check` (Phase B in the Zig pack — currently Python-only) validates cross-link integrity:
- Every spec `→ Library:` pointer resolves to an importable symbol.
- Every public `adam_mcp_zig` symbol's doc comment names a spec rule.
- Drift fails CI.

Until Phase B lands the Zig self-check, drift is caught by human review at PR time and by the `claude-pack/tests/test_skill_sync.py` mirror tests in the Python pack (which check the SKILL.md ↔ HOUSE_STYLE.md sync).

---

## §6 Escape hatch contract

### §6.28 Underlying clients publicly importable
(Restates §2.12.)

### §6.29 Result.raw

Synthesized output goes in `Result.value`. Raw API response goes in `Result.raw`. Agent can use either.

### §6.30 Every MCP ships a passthrough tool

For MCPs wrapping an external API: a tool that makes raw API calls. For MCPs over an own-kernel/own-engine (archi-style): a tool that runs raw scripts/queries against the engine.

In Zig: wrap with `passthrough(fn_or_struct)`, which sets the `adam_mcp_passthrough_marker` comptime decl. The audit detects passthrough tools via `isPassthrough(ToolType)` — no text grep needed. One per server, enforced.

Generic name: `<domain>_passthrough` or `run_<domain>_script`. Canonical example: `caid-mcp`'s `run_cadquery_script` (Python). Zig reference MCP: `adam-greet-zig`'s `compose_raw_greeting`.

→ Library: `adam_mcp_zig.passthrough`, `adam_mcp_zig.isPassthrough`

### §6.31 Guardrails default WARN

Restates §1.3 default severity. Hard-block (FAIL) only when consequence is destructive.

### §6.32 LLM_GUIDE has Escape hatches section
(Restates §3.14 required section.)

### §6.33 CLAUDE.md has "when to drop down" guidance
(Restates §3.15 required section.)

---

## Appendix A — Framework integration notes

Rules in this appendix encode constraints that come from the underlying MCP framework, not from the agent-tool contract itself. They are listed here so that:

- The §1–§6 core stays portable across frameworks and protocol versions.
- When a framework's behavior changes, the affected rule can be deprecated (its `rule_id` reserved per §3.18) and a replacement added here without disturbing the core contract.

**Zig pack:** the Zig SDK hand-rolls JSON-RPC 2.0 over stdio in `BaseServer.run`. There is no framework layer — the SDK owns the wire directly. Consequently, no rules currently live in Appendix A for the Zig pack.

If a future Zig SDK release adopts an upstream MCP framework (e.g., a Zig port of FastMCP), framework-specific rules would land here.

**Python pack:** Appendix A is populated — `§1.5` (validates parameter naming) lives there because FastMCP drives the JSONSchema generation.

This appendix is intentionally short. New rules land here only when they encode a framework-specific behavior that the §1–§6 contract does not require.
