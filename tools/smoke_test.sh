#!/usr/bin/env bash
# tools/smoke_test.sh — end-to-end verification of adam-greet-zig.
#
# Sends three JSON-RPC messages over stdio and checks the responses
# contain expected substrings. Exits non-zero on any failure.
#
# Run from the repo root after `zig build`:
#   ./tools/smoke_test.sh

set -eu

BIN="${BIN:-./zig-out/bin/adam-greet-zig}"

if [ ! -x "$BIN" ]; then
    echo "FAIL: $BIN not found. Run 'zig build' first."
    exit 1
fi

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compose_greeting","arguments":{"name":"World","formality":7}}}' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"compose_raw_greeting","arguments":{"template":"escaped greeting"}}}' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"compose_greeting","arguments":{"name":42}}}' \
    | "$BIN" > "$OUT" 2>/dev/null

fail() { echo "FAIL: $1"; cat "$OUT"; exit 1; }
check() { grep -q "$1" "$OUT" || fail "missing: $1"; }

# initialize response
check '"protocolVersion":"2024-11-05"'
check '"serverInfo":{"name":"adam-greet"'

# tools/list response — all 7 tools present
check '"name":"compose_greeting"'
check '"name":"compose_personalized_greeting"'
check '"name":"get_morning_context"'
check '"name":"record_greeting"'
check '"name":"recent_greetings"'
check '"name":"morning_briefing"'
check '"name":"compose_raw_greeting"'

# compose_greeting — formality=7 → "good morning"
check 'good morning, World'
check '"isError":false'
check '\[LOCAL\]'

# passthrough — escaped greeting
check 'escaped greeting'

# parse failure — name as number → Result.fail with isError=true
check '"isError":true'

echo "OK: smoke test passed ($(wc -l < "$OUT") response lines)"
