<#
.SYNOPSIS
    Bootstraps a fresh clone of my-edotmw to the point where `just` works.

.DESCRIPTION
    Resolves the chicken-and-egg problem in the justfile: every other dev
    command goes through `just`, but a fresh clone has no `just`. This
    script fetches it into tools/ (gitignored), so nothing is installed
    system-wide and `just nuke` can still remove every trace.

    Godot itself is NOT fetched here. The default runtime is docker
    (see game_design_decisions.md D-014), which builds its own pinned
    Godot into the container image. Portable Godot is only needed for
    the native runtime and the GUI editor/client — run `just bootstrap`
    for that, once this script has given you `just`.

.PARAMETER Force
    Re-download `just` even if it is already present in tools/.

.EXAMPLE
    .\bootstrap.ps1
    .\tools\just.exe doctor
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Pinned for reproducibility — bump deliberately, not incidentally.
$JustVersion = '1.57.0'

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir = Join-Path $RepoRoot 'tools'
$JustExe = Join-Path $ToolsDir 'just.exe'

if ((Test-Path $JustExe) -and (-not $Force)) {
    Write-Host "OK: just already present at $JustExe (use -Force to re-download)"
    Write-Host "Next: .\tools\just.exe doctor"
    exit 0
}

if (-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Path $ToolsDir | Out-Null
}

if ([System.Environment]::Is64BitOperatingSystem) {
    $JustAsset = "just-$JustVersion-x86_64-pc-windows-msvc.zip"
} else {
    throw "Unsupported architecture: this project targets 64-bit Windows for local dev."
}

$JustUrl = "https://github.com/casey/just/releases/download/$JustVersion/$JustAsset"
$ZipPath = Join-Path $ToolsDir 'just.zip'

Write-Host "Fetching just $JustVersion ..."
Invoke-WebRequest -Uri $JustUrl -OutFile $ZipPath -UseBasicParsing

Write-Host "Extracting ..."
# -Force here overwrites extracted files; it does not touch anything
# outside $ToolsDir.
Expand-Archive -Path $ZipPath -DestinationPath $ToolsDir -Force
Remove-Item $ZipPath -Force

if (-not (Test-Path $JustExe)) {
    throw "Bootstrap failed: just.exe not found in $ToolsDir after extraction."
}

Write-Host ""
Write-Host "OK: just $JustVersion installed at $JustExe"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  .\tools\just.exe doctor      # verify Docker / prerequisites"
Write-Host "  .\tools\just.exe test-unit   # run the headless test suite"
Write-Host ""
Write-Host "Tear everything down again with: .\tools\just.exe nuke"
