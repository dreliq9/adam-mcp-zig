# tools/byte_equivalence_check.ps1 — Windows equivalent of
# byte_equivalence_check.sh. Compares adam-greet-zig.exe vs the Python
# adam-greet for semantic equivalence over JSON-RPC stdio.
#
# Wire format differs (Zig is hand-rolled, Python uses FastMCP), but
# the Result envelope content should match — same tool names, same
# Result.value bytes, same envelope_version, same mode_tag.
#
# Run from the repo root after `zig build`:
#   .\tools\byte_equivalence_check.ps1
#   .\tools\byte_equivalence_check.ps1 -PyCmd "uv run --directory C:\path\to\adam-mcp-sdk\reference-mcp\adam-greet python -m adam_greet.mcp.server"

[CmdletBinding()]
param(
    [string]$ZigBin = ".\zig-out\bin\adam-greet-zig.exe",
    [string]$PyCmd = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ZigBin)) {
    Write-Error "FAIL: $ZigBin not found. Run 'zig build' first."
    exit 1
}

$requests = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"byte-equivalence-check","version":"0"}}}'
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compose_greeting","arguments":{"name":"World","formality":7}}}'
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"compose_raw_greeting","arguments":{"template":"raw"}}}'
)

Write-Host "-> Running Zig binary..."
$zigOut = $requests | & $ZigBin 2>$null
Write-Host ("  Zig: {0} response lines" -f ($zigOut | Measure-Object -Line).Lines)

if (-not $PyCmd) {
    Write-Host ""
    Write-Host "Skipping Python comparison (no -PyCmd passed)."
    Write-Host ""
    Write-Host "To compare semantically:"
    Write-Host "  .\tools\byte_equivalence_check.ps1 -PyCmd `"uv run --directory C:\path\to\adam-mcp-sdk\reference-mcp\adam-greet python -m adam_greet.mcp.server`""
    Write-Host ""
    Write-Host "Expected equivalences (MUST match):"
    Write-Host "  - protocolVersion: 2024-11-05"
    Write-Host "  - tool names in tools/list: same set of 7"
    Write-Host "  - compose_greeting Result.value: 'good morning, World'"
    Write-Host "  - mode_tag: [LOCAL]"
    Write-Host "  - envelope_version: 1 (first field of every serialized Result)"
    exit 0
}

Write-Host "-> Running Python binary: $PyCmd"
$pyOut = $requests | Invoke-Expression "$PyCmd" 2>$null
Write-Host ("  Python: {0} response lines" -f ($pyOut | Measure-Object -Line).Lines)

Write-Host ""
Write-Host "=== Semantic checks ==="

function CheckBoth([string]$Needle) {
    $z = ($zigOut -match [regex]::Escape($Needle)).Count
    $p = ($pyOut -match [regex]::Escape($Needle)).Count
    if ($z -gt 0 -and $p -gt 0) {
        Write-Host "  OK  both: $Needle"
    } else {
        Write-Host "  XX  MISMATCH on: $Needle"
        Write-Host "      zig: $z matches"
        Write-Host "      py:  $p matches"
    }
}

CheckBoth '"protocolVersion":"2024-11-05"'
CheckBoth '"name":"compose_greeting"'
CheckBoth '"name":"compose_raw_greeting"'
CheckBoth 'good morning, World'
CheckBoth '[LOCAL]'
CheckBoth '"isError":false'
CheckBoth 'envelope_version'

Write-Host ""
Write-Host "Done. Wire format differs (expected) but envelope_version and semantic content should match above."
