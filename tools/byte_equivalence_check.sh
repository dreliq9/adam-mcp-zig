#!/usr/bin/env bash
# tools/byte_equivalence_check.sh — compare adam-greet-zig vs adam-greet-py.
#
# Sends the same JSON-RPC sequence to both binaries and reports
# structural equivalence. Note: byte-identical output is NOT expected
# because Python (FastMCP) and Zig (hand-rolled) frame the wire
# differently. We check semantic equivalence: same tool names, same
# value content, same isError flag.
#
# Requires:
#   - ./zig-out/bin/adam-greet-zig built (run `zig build` first)
#   - Python adam-greet installed in a venv:
#       cd ~/Projects/adam-mcp-sdk
#       uv sync
#       uv run --directory reference-mcp/adam-greet python -m adam_greet.cli
#
# Run from this repo root:
#   ./tools/byte_equivalence_check.sh [path-to-python-adam-greet]

set -eu

ZIG_BIN="${ZIG_BIN:-./zig-out/bin/adam-greet-zig}"
PY_CMD="${1:-}"

if [ ! -x "$ZIG_BIN" ]; then
    echo "FAIL: $ZIG_BIN not found. Run 'zig build' first."
    exit 1
fi

REQUESTS=$(cat <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"byte-equivalence-check","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compose_greeting","arguments":{"name":"World","formality":7}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"compose_raw_greeting","arguments":{"template":"raw"}}}
EOF
)

ZIG_OUT="$(mktemp)"
PY_OUT="$(mktemp)"
trap 'rm -f "$ZIG_OUT" "$PY_OUT"' EXIT

echo "→ Running Zig binary…"
printf '%s\n' "$REQUESTS" | "$ZIG_BIN" > "$ZIG_OUT" 2>/dev/null
echo "  Zig: $(wc -l < "$ZIG_OUT") response lines"

if [ -z "$PY_CMD" ]; then
    cat <<'INFO'

Skipping Python comparison (no python binary passed).

To compare semantically:
  cd ~/Projects/adam-mcp-sdk
  uv sync
  ./tools/byte_equivalence_check.sh "uv run --directory reference-mcp/adam-greet python -m adam_greet.mcp.server"

Expected differences (these are NOT failures):
  - FastMCP capabilities object content (Python may publish more keys).
  - Field ordering inside content.text (Python's json.dumps may sort keys differently).
  - error code numbers on validation failures (different error sources).

Expected equivalences (these MUST match):
  - protocolVersion: "2024-11-05" on both
  - tool names in tools/list: same set of 7
  - compose_greeting Result.value: "good morning, World"
  - compose_raw_greeting Result.value: "raw"
  - mode_tag: "[LOCAL]"
  - isError: false on success, true on parse fail
  - envelope_version: 1 (first field of every serialized Result)

INFO
    exit 0
fi

echo "→ Running Python binary: $PY_CMD"
printf '%s\n' "$REQUESTS" | eval "$PY_CMD" > "$PY_OUT" 2>/dev/null
echo "  Python: $(wc -l < "$PY_OUT") response lines"

echo ""
echo "=== Semantic checks ==="

check_both() {
    local needle="$1"
    if grep -q "$needle" "$ZIG_OUT" && grep -q "$needle" "$PY_OUT"; then
        echo "  ✓ both: $needle"
    else
        echo "  ✗ MISMATCH on: $needle"
        echo "    zig: $(grep -c "$needle" "$ZIG_OUT") matches"
        echo "    py:  $(grep -c "$needle" "$PY_OUT") matches"
    fi
}

check_both '"protocolVersion":"2024-11-05"'
check_both '"name":"compose_greeting"'
check_both '"name":"compose_raw_greeting"'
check_both 'good morning, World'
check_both '\[LOCAL\]'
check_both '"isError":false'
check_both 'envelope_version'

echo ""
echo "Done. Wire format differs (expected) but semantic content should match above."
