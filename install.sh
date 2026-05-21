#!/usr/bin/env bash
set -euo pipefail

prefix="${PREFIX:-$HOME/.local}"
optimize="${OPTIMIZE:-ReleaseSafe}"
zig="${ZIG:-zig}"

cd "$(dirname "$0")"

"$zig" build install --prefix "$prefix" "-Doptimize=$optimize"

cli="$prefix/bin/adam-mcp"
greet="$prefix/bin/adam-greet-zig"

for p in "$cli" "$greet"; do
    if [[ ! -x "$p" ]]; then
        echo "expected $p after install, not found" >&2
        exit 1
    fi
done

echo "Installed:"
echo "  CLI:           $cli"
echo "  Reference MCP: $greet"
echo
echo "Scaffold a new MCP:"
echo "  $cli new my-mcp --target ../my-mcp"
echo
echo "Register the reference MCP with Claude Code (optional):"
echo "  claude mcp add --scope user adam-greet -- \"$greet\""
