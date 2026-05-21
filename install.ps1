#Requires -Version 7

[CmdletBinding()]
param(
    [string]$Prefix = (Join-Path $HOME ".local"),
    [ValidateSet("Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall")]
    [string]$Optimize = "ReleaseSafe"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$zig = if ($env:ZIG) { $env:ZIG } else { "zig" }
& $zig build install "--prefix" $Prefix "-Doptimize=$Optimize"
if ($LASTEXITCODE -ne 0) { throw "zig build failed (exit $LASTEXITCODE)" }

$cli = Join-Path $Prefix "bin\adam-mcp.exe"
$greet = Join-Path $Prefix "bin\adam-greet-zig.exe"

foreach ($p in @($cli, $greet)) {
    if (-not (Test-Path $p)) { throw "expected $p after install, not found" }
}

Write-Output "Installed:"
Write-Output "  CLI:           $cli"
Write-Output "  Reference MCP: $greet"
Write-Output ""
Write-Output "Scaffold a new MCP:"
Write-Output "  $cli new my-mcp --target ../my-mcp"
Write-Output ""
Write-Output "Register the reference MCP with Claude Code (optional):"
Write-Output "  claude mcp add --scope user adam-greet -- `"$greet`""
