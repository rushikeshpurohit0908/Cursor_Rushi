#Requires -Version 5.1
<#
.SYNOPSIS
  Links Quartus Prime Pro 26.3 to Cursor via QuartusIQ MCP servers (Windows).

.DESCRIPTION
  Follows Altera's Cursor-QuartusIQ Windows setup:
  1. Verifies Node.js 22.5+ and Quartus Pro at the given root
  2. Sets QUARTUS_ROOTDIR (User)
  3. Installs @altera/quartus-mcp and @altera/quartus-programmer-mcp from the downloaded zip
  4. Writes %USERPROFILE%\.cursor\mcp.json
  5. Sets LM_LICENSE_FILE (User)

  Prerequisites (manual):
  - Quartus Prime Pro 26.1 / 26.1.1 / 26.3 installed
  - Node.js 22.5+ from https://nodejs.org (new PowerShell after install)
  - Download quartusiq-and-quartus-programmer-mcp-servers.zip from
    https://www.altera.com/products/software-tools/quartusiq (sign in → Download)
    into your Downloads folder (or pass -ZipPath)

.PARAMETER QuartusRoot
  Path to the Quartus install root that contains bin64\quartus_sh.exe.
  Default: C:\altera_pro\26.3\quartus

.PARAMETER LicenseFile
  FlexLM license: a .dat path (e.g. C:\altera_pro\license.dat) or server (e.g. 1800@server).
  Required unless LM_LICENSE_FILE is already set in the User environment.

.PARAMETER ZipPath
  Path to quartusiq-and-quartus-programmer-mcp-servers.zip.
  Default: $env:USERPROFILE\Downloads\quartusiq-and-quartus-programmer-mcp-servers.zip

.PARAMETER NodeExe
  Path to node.exe. Default: C:\Program Files\nodejs\node.exe

.PARAMETER SkipInstall
  Only write mcp.json and env vars; skip npm install from the zip.

.EXAMPLE
  .\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\license.dat"

.EXAMPLE
  .\setup-quartus-mcp.ps1 -LicenseFile "1800@myserver" -QuartusRoot "C:\altera_pro\26.3\quartus"
#>
[CmdletBinding()]
param(
    [string]$QuartusRoot = "C:\altera_pro\26.3\quartus",
    [string]$LicenseFile = "",
    [string]$ZipPath = "",
    [string]$NodeExe = "C:\Program Files\nodejs\node.exe",
    [switch]$SkipInstall
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

function Get-SemVerParts([string]$Version) {
    $clean = ($Version -replace '^v', '').Trim()
    $parts = $clean.Split('.') | ForEach-Object { [int]$_ }
    while ($parts.Count -lt 3) { $parts += 0 }
    return ,$parts[0..2]
}

function Test-NodeVersionOk([string]$Version) {
    $p = Get-SemVerParts $Version
    # Require Node >= 22.5.0
    if ($p[0] -gt 22) { return $true }
    if ($p[0] -lt 22) { return $false }
    if ($p[1] -gt 5) { return $true }
    if ($p[1] -lt 5) { return $false }
    return $true
}

# --- Resolve defaults ---
if (-not $ZipPath) {
    $ZipPath = Join-Path $env:USERPROFILE "Downloads\quartusiq-and-quartus-programmer-mcp-servers.zip"
}
if (-not $LicenseFile) {
    $LicenseFile = [Environment]::GetEnvironmentVariable("LM_LICENSE_FILE", "User")
    if (-not $LicenseFile) {
        $LicenseFile = $env:LM_LICENSE_FILE
    }
}
if (-not $LicenseFile) {
    throw @"
LicenseFile is required. Pass -LicenseFile with your .dat path or server, for example:
  .\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\license.dat"
  .\setup-quartus-mcp.ps1 -LicenseFile "1800@license-server"
"@
}

$quartusSh = Join-Path $QuartusRoot "bin64\quartus_sh.exe"
$npmGlobalRoot = Join-Path $env:APPDATA "npm\node_modules"
$quartusMcpEntry = Join-Path $npmGlobalRoot "@altera\quartus-mcp\dist\index.mjs"
$programmerMcpEntry = Join-Path $npmGlobalRoot "@altera\quartus-programmer-mcp\dist\index.mjs"
$cursorDir = Join-Path $env:USERPROFILE ".cursor"
$mcpJsonPath = Join-Path $cursorDir "mcp.json"
$extractDir = Join-Path $env:USERPROFILE "Downloads\quartusiq-mcp"

Write-Host "Quartus → Cursor MCP setup" -ForegroundColor Green
Write-Host "  User          : $env:USERNAME"
Write-Host "  QuartusRoot   : $QuartusRoot"
Write-Host "  License       : $LicenseFile"
Write-Host "  Node          : $NodeExe"
Write-Host "  mcp.json      : $mcpJsonPath"

# --- 1. Verify Node ---
Write-Step "Checking Node.js (>= 22.5)"
Assert-Path $NodeExe "Node.js"
$nodeVer = & $NodeExe -v
if (-not (Test-NodeVersionOk $nodeVer)) {
    throw "Node $nodeVer is too old. Install Node.js 22.5+ from https://nodejs.org and open a new PowerShell."
}
Write-Host "  node $nodeVer OK"
$npmCmd = Join-Path (Split-Path $NodeExe -Parent) "npm.cmd"
Assert-Path $npmCmd "npm"
Write-Host "  npm $(& $npmCmd -v) OK"

# --- 2. Verify Quartus ---
Write-Step "Checking Quartus Pro at $QuartusRoot"
Assert-Path $quartusSh "quartus_sh.exe"
$qOut = & $quartusSh --version 2>&1 | Out-String
Write-Host $qOut.Trim()
if ($qOut -notmatch "(?i)Pro") {
    Write-Warning "Output does not clearly say Pro Edition. Continue only if this is Quartus Prime Pro 26.1+."
}

# --- 3. Env: QUARTUS_ROOTDIR + LM_LICENSE_FILE ---
Write-Step "Setting User environment variables"
[Environment]::SetEnvironmentVariable("QUARTUS_ROOTDIR", $QuartusRoot, "User")
[Environment]::SetEnvironmentVariable("LM_LICENSE_FILE", $LicenseFile, "User")
$env:QUARTUS_ROOTDIR = $QuartusRoot
$env:LM_LICENSE_FILE = $LicenseFile
Write-Host "  QUARTUS_ROOTDIR=$QuartusRoot"
Write-Host "  LM_LICENSE_FILE=$LicenseFile"

# --- 4. Install MCP packages from zip ---
if (-not $SkipInstall) {
    Write-Step "Installing QuartusIQ MCP servers from zip"
    Assert-Path $ZipPath "MCP servers zip (download from altera.com QuartusIQ page → Download)"
    if (Test-Path -LiteralPath $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -Force -Path $ZipPath -DestinationPath $extractDir
    Push-Location $extractDir
    try {
        $tgz = @(Get-ChildItem -Filter *.tgz)
        if ($tgz.Count -eq 0) {
            throw "No .tgz packages found inside $extractDir after extracting $ZipPath"
        }
        Write-Host "  Installing: $($tgz.Name -join ', ')"
        & $npmCmd install -g ($tgz.FullName)
        if ($LASTEXITCODE -ne 0) { throw "npm install -g failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
    & $npmCmd list -g --depth=0
} else {
    Write-Step "Skipping npm install (-SkipInstall)"
}

Assert-Path $quartusMcpEntry "quartus-mcp entry"
Assert-Path $programmerMcpEntry "quartus-programmer-mcp entry"

# --- 5. Write mcp.json ---
Write-Step "Writing $mcpJsonPath"
New-Item -ItemType Directory -Force -Path $cursorDir | Out-Null

# Escape backslashes for JSON
function To-JsonPath([string]$Path) {
    return ($Path -replace '\\', '\\')
}

$mcp = [ordered]@{
    mcpServers = [ordered]@{
        "quartus-mcp" = [ordered]@{
            type    = "stdio"
            command = $NodeExe
            args    = @($quartusMcpEntry)
            env     = [ordered]@{
                LM_LICENSE_FILE = $LicenseFile
            }
        }
        "programmer-mcp" = [ordered]@{
            type    = "stdio"
            command = $NodeExe
            args    = @($programmerMcpEntry)
            env     = [ordered]@{
                LM_LICENSE_FILE = $LicenseFile
            }
        }
    }
}

# Prefer ConvertTo-Json for correct escaping; depth covers nested objects
$json = $mcp | ConvertTo-Json -Depth 6
# Preserve existing file as backup if present
if (Test-Path -LiteralPath $mcpJsonPath) {
    $backup = "$mcpJsonPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $mcpJsonPath -Destination $backup
    Write-Host "  Backed up existing mcp.json → $backup"
}
Set-Content -LiteralPath $mcpJsonPath -Value $json -Encoding UTF8
Write-Host "  Wrote mcp.json"

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. Quit Cursor completely (all windows)."
Write-Host "  2. Reopen Cursor on any folder on this PC."
Write-Host "  3. Confirm MCP shows user-quartus-mcp and user-programmer-mcp."
Write-Host "  4. Ask Cursor: validate the Quartus installation."
Write-Host ""
Write-Host "If servers are missing, check paths in $mcpJsonPath and fully quit Cursor."
Write-Host "If license fails, fix -LicenseFile (.dat path or 1800@server) and re-run, then restart Cursor."
Write-Host "Optional QuartusIQ chat inside Quartus 26.3 (View > QuartusIQ) is separate — skip for Cursor."
