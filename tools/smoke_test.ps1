# tools/smoke_test.ps1 — Windows equivalent of smoke_test.sh.
#
# End-to-end verification of adam-greet-zig.exe. Sends five JSON-RPC
# messages over stdio and checks the responses contain expected
# substrings. Exits non-zero on any failure.
#
# Run from the repo root after `zig build -Dtarget=x86_64-windows-gnu`
# (or a native Windows `zig build`):
#   .\tools\smoke_test.ps1
#
# Override the binary path with -Bin:
#   .\tools\smoke_test.ps1 -Bin .\zig-out\bin\adam-greet-zig.exe

[CmdletBinding()]
param(
    [string]$Bin = ".\zig-out\bin\adam-greet-zig.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Bin)) {
    Write-Error "FAIL: $Bin not found. Run 'zig build' first."
    exit 1
}

$requests = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compose_greeting","arguments":{"name":"World","formality":7}}}'
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"compose_raw_greeting","arguments":{"template":"escaped greeting"}}}'
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"compose_greeting","arguments":{"name":42}}}'
)

# Pipe each request as a line into the binary; capture stdout.
# 2>$null silences the binary's stderr (server diagnostics).
$out = $requests | & $Bin 2>$null

function Check([string]$Needle) {
    if (-not ($out -match [regex]::Escape($Needle))) {
        Write-Error "FAIL: missing: $Needle"
        $out | ForEach-Object { Write-Host $_ }
        exit 1
    }
}

# initialize response
Check '"protocolVersion":"2024-11-05"'
Check '"serverInfo":{"name":"adam-greet"'

# tools/list response — all 7 tools present
Check '"name":"compose_greeting"'
Check '"name":"compose_personalized_greeting"'
Check '"name":"get_morning_context"'
Check '"name":"record_greeting"'
Check '"name":"recent_greetings"'
Check '"name":"morning_briefing"'
Check '"name":"compose_raw_greeting"'

# compose_greeting — formality=7 -> "good morning"
Check 'good morning, World'
Check '"isError":false'
Check '[LOCAL]'

# passthrough — escaped greeting
Check 'escaped greeting'

# parse failure — name as number -> Result.fail with isError=true
Check '"isError":true'

# envelope_version — first field of every serialized Result
Check 'envelope_version'

$lineCount = ($out | Measure-Object -Line).Lines
Write-Host "OK: smoke test passed ($lineCount response lines)"
