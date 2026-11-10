#Requires -Version 5.1
<#
.SYNOPSIS
  Install QuartusIQ MCP (+ optional Programmer MCP) for Cursor on Windows.

.DESCRIPTION
  Matches Altera QuartusIQ Expert Companion User Guide:
  B. Cursor + QuartusIQ MCP + skills (Windows)
  https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/b.-cursor-quartusiq-mcp-skills-windows

  1. Verifies Node.js / npm
  2. Optionally sets QUARTUS_ROOTDIR and LM_LICENSE_FILE
  3. npm install -g from downloaded .tgz (or zip of .tgz files)
  4. Writes %USERPROFILE%\.cursor\mcp.json using npx (official pattern)
  5. Optionally copies skills into %USERPROFILE%\.cursor\skills

.PARAMETER QuartusRoot
  Quartus root containing bin64\quartus_sh.exe.
  Default: C:\altera_pro\26.3\quartus

.PARAMETER LicenseFile
  Optional FlexLM license (.dat path or 1800@server). Sets User LM_LICENSE_FILE.

.PARAMETER PackagePath
  Path to a .tgz, a folder of .tgz files, or the Altera zip that contains them.
  Default: searches Downloads for quartusiq*.zip / altera-quartus*.tgz

.PARAMETER NodeDir
  Node.js install dir. Default: C:\Program Files\nodejs

.PARAMETER SkillsSource
  Optional folder containing QuartusIQ skill folders to copy into ~/.cursor/skills

.PARAMETER SkipInstall
  Only write mcp.json / env; skip npm install.

.PARAMETER SkipProgrammer
  Do not register programmer-mcp in mcp.json.

.EXAMPLE
  .\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\license.dat"

.EXAMPLE
  .\setup-quartus-mcp.ps1 -PackagePath "$env:USERPROFILE\Downloads\altera-quartus-mcp-0.6.0.tgz"
#>
[CmdletBinding()]
param(
    [string]$QuartusRoot = "C:\altera_pro\26.3\quartus",
    [string]$LicenseFile = "",
    [string]$PackagePath = "",
    [string]$NodeDir = "C:\Program Files\nodejs",
    [string]$SkillsSource = "",
    [switch]$SkipInstall,
    [switch]$SkipProgrammer
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
}

function Find-Packages {
    param([string]$Hint)

    $downloads = Join-Path $env:USERPROFILE "Downloads"
    $candidates = @()

    if ($Hint) {
        Assert-Path $Hint "PackagePath"
        if ((Get-Item -LiteralPath $Hint).PSIsContainer) {
            $candidates += Get-ChildItem -LiteralPath $Hint -Filter *.tgz -File
        }
        elseif ($Hint -like "*.tgz") {
            $candidates += Get-Item -LiteralPath $Hint
        }
        elseif ($Hint -like "*.zip") {
            $extract = Join-Path $env:TEMP ("quartusiq-mcp-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Force -Path $extract | Out-Null
            Expand-Archive -Force -Path $Hint -DestinationPath $extract
            $candidates += Get-ChildItem -LiteralPath $extract -Filter *.tgz -File -Recurse
        }
        else {
            throw "PackagePath must be a .tgz, a .zip, or a folder: $Hint"
        }
        return ,$candidates
    }

    $zips = @(Get-ChildItem -LiteralPath $downloads -Filter "*quartusiq*mcp*.zip" -File -ErrorAction SilentlyContinue)
    $zips += @(Get-ChildItem -LiteralPath $downloads -Filter "*quartus*mcp*.zip" -File -ErrorAction SilentlyContinue)
    $zips = $zips | Sort-Object LastWriteTime -Descending | Select-Object -Unique -First 3
    foreach ($z in $zips) {
        $extract = Join-Path $env:TEMP ("quartusiq-mcp-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        Expand-Archive -Force -Path $z.FullName -DestinationPath $extract
        $candidates += Get-ChildItem -LiteralPath $extract -Filter *.tgz -File -Recurse
    }

    $candidates += Get-ChildItem -LiteralPath $downloads -Filter "altera-quartus*.tgz" -File -ErrorAction SilentlyContinue
    $candidates += Get-ChildItem -LiteralPath $downloads -Filter "*quartus*mcp*.tgz" -File -ErrorAction SilentlyContinue

    $candidates = @($candidates | Sort-Object FullName -Unique)
    if ($candidates.Count -eq 0) {
        throw @"
No QuartusIQ MCP .tgz found.
1. Sign in at https://www.altera.com/products/software-tools/quartusiq
2. Download QuartusIQ MCP Server (+ Programmer MCP) into Downloads
3. Re-run this script, or pass -PackagePath to the .tgz / zip
"@
    }
    return ,$candidates
}

$nodeExe = Join-Path $NodeDir "node.exe"
$npxCmd = Join-Path $NodeDir "npx.cmd"
$npmCmd = Join-Path $NodeDir "npm.cmd"
$cursorDir = Join-Path $env:USERPROFILE ".cursor"
$mcpJsonPath = Join-Path $cursorDir "mcp.json"
$skillsDest = Join-Path $cursorDir "skills"
$quartusSh = Join-Path $QuartusRoot "bin64\quartus_sh.exe"

Write-Host "QuartusIQ MCP → Cursor (Windows)" -ForegroundColor Green
Write-Host "  Guide: docs.altera.com .../b.-cursor-quartusiq-mcp-skills-windows"
Write-Host "  User : $env:USERNAME"

# --- Node ---
Write-Step "Checking Node.js / npm"
Assert-Path $nodeExe "Node.js"
Assert-Path $npmCmd "npm"
Assert-Path $npxCmd "npx"
$nodeVer = & $nodeExe -v
$npmVer = & $npmCmd -v
Write-Host "  node $nodeVer"
Write-Host "  npm  $npmVer"

# --- Quartus (recommended for project tools) ---
Write-Step "Checking Quartus at $QuartusRoot"
if (Test-Path -LiteralPath $quartusSh) {
    $qOut = & $quartusSh --version 2>&1 | Out-String
    Write-Host ($qOut.Trim())
    [Environment]::SetEnvironmentVariable("QUARTUS_ROOTDIR", $QuartusRoot, "User")
    $env:QUARTUS_ROOTDIR = $QuartusRoot
    Write-Host "  QUARTUS_ROOTDIR=$QuartusRoot"
}
else {
    Write-Warning "quartus_sh.exe not found at $quartusSh. MCP can still register; project tools need Quartus Prime Pro 26.3."
}

if ($LicenseFile) {
    [Environment]::SetEnvironmentVariable("LM_LICENSE_FILE", $LicenseFile, "User")
    $env:LM_LICENSE_FILE = $LicenseFile
    Write-Host "  LM_LICENSE_FILE=$LicenseFile"
}

# --- npm install -g ---
if (-not $SkipInstall) {
    Write-Step "Installing MCP package(s) globally"
    $pkgs = Find-Packages -Hint $PackagePath
    Write-Host "  Found:"
    $pkgs | ForEach-Object { Write-Host "    $($_.FullName)" }
    & $npmCmd install -g ($pkgs.FullName)
    if ($LASTEXITCODE -ne 0) { throw "npm install -g failed ($LASTEXITCODE)" }
    & $npmCmd list -g --depth=0
}
else {
    Write-Step "Skipping npm install (-SkipInstall)"
}

# --- mcp.json (official npx pattern) ---
Write-Step "Writing $mcpJsonPath"
New-Item -ItemType Directory -Force -Path $cursorDir | Out-Null

$servers = [ordered]@{
    "quartus-mcp" = [ordered]@{
        type    = "stdio"
        command = (Join-Path $NodeDir "npx")
        args    = @("-y", "quartus-mcp")
        env     = @{}
    }
}

if (-not $SkipProgrammer) {
    $servers["programmer-mcp"] = [ordered]@{
        type    = "stdio"
        command = (Join-Path $NodeDir "npx")
        args    = @("-y", "quartus-programmer-mcp")
        env     = @{}
    }
}

if ($LicenseFile) {
    foreach ($name in @($servers.Keys)) {
        $servers[$name].env = [ordered]@{ LM_LICENSE_FILE = $LicenseFile }
    }
}

$mcp = [ordered]@{ mcpServers = $servers }

if (Test-Path -LiteralPath $mcpJsonPath) {
    $backup = "$mcpJsonPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $mcpJsonPath -Destination $backup
    Write-Host "  Backed up existing mcp.json → $backup"
}

($mcp | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $mcpJsonPath -Encoding UTF8
Write-Host "  Wrote mcp.json (npx -y quartus-mcp)"

# --- Skills (optional) ---
if ($SkillsSource) {
    Write-Step "Copying skills to $skillsDest"
    Assert-Path $SkillsSource "SkillsSource"
    New-Item -ItemType Directory -Force -Path $skillsDest | Out-Null
    Copy-Item -Path (Join-Path $SkillsSource "*") -Destination $skillsDest -Recurse -Force
    Write-Host "  Skills copied."
}

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  1. Fully quit Cursor (all windows), then reopen."
Write-Host "  2. In a local chat, ask: list MCP servers"
Write-Host "     Expect: user-quartus-mcp ready (and user-programmer-mcp if installed)."
Write-Host "  3. Ask: validate the Quartus installation"
Write-Host "     (uses validate_installation from QuartusIQ MCP)"
Write-Host ""
Write-Host "Download packages: https://www.altera.com/products/software-tools/quartusiq"
Write-Host "Guide: https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/b.-cursor-quartusiq-mcp-skills-windows"
