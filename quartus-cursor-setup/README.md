# Link Quartus Prime Pro 26.3 → Cursor (Windows)

This folder automates the Altera **Cursor-QuartusIQ Windows Setup** so Cursor can talk to your local Quartus install through the QuartusIQ MCP servers.

> **Must run on the Windows PC where Quartus is installed.** A Cursor Cloud Agent cannot reach `C:\altera_pro\26.3`.

## You need

| Requirement | Notes |
|---|---|
| Quartus Prime Pro **26.1 / 26.1.1 / 26.3** | Default path: `C:\altera_pro\26.3\quartus` |
| Node.js **22.5+** | https://nodejs.org — open a **new** PowerShell after install |
| Altera.com login | Download the MCP zip from the QuartusIQ page |
| License | `.dat` file **or** server like `1800@server` |

Official download: https://www.altera.com/products/software-tools/quartusiq  
Guide: https://docs.altera.com/r/docs/m530666/current

## Quick setup (recommended)

1. Sign in at the QuartusIQ page → **Download** → save  
   `quartusiq-and-quartus-programmer-mcp-servers.zip` into your **Downloads** folder.  
   Skip the VS Code and Skills downloads.

2. Open **Windows PowerShell** and run (edit the license path):

```powershell
cd path\to\Cursor_Rushi\quartus-cursor-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\your-license.dat"
```

Server license example:

```powershell
.\setup-quartus-mcp.ps1 -LicenseFile "1800@your-license-server"
```

Custom Quartus folder:

```powershell
.\setup-quartus-mcp.ps1 `
  -QuartusRoot "D:\altera_pro\26.3\quartus" `
  -LicenseFile "C:\altera_pro\license.dat"
```

3. **Quit Cursor completely**, reopen it, and confirm MCP shows:
   - `user-quartus-mcp`
   - `user-programmer-mcp`

4. Ask Cursor: **validate the Quartus installation.**  
   A good answer shows your version, license, and no license error.

## What the script does

1. Checks `node -v` (≥ 22.5) and `quartus_sh.exe --version` (Pro)
2. Sets User env vars: `QUARTUS_ROOTDIR`, `LM_LICENSE_FILE`
3. Expands the zip and runs `npm install -g` on the `.tgz` packages
4. Writes `%USERPROFILE%\.cursor\mcp.json` (backs up any existing file)

Manual template (if you prefer Notepad): see [`mcp.json.example`](mcp.json.example). Replace `YOUR_WINDOWS_NAME` (`echo $env:USERNAME`) and the license path (use `\\` in JSON).

## Troubleshooting

| Symptom | Fix |
|---|---|
| MCP servers missing in Cursor | Check username/paths in `mcp.json`; fully quit Cursor |
| License error | Fix `.dat` path or use `1800@server`; re-run script; restart Cursor |
| Zip / install fails | Zip must be in Downloads (or pass `-ZipPath`) before install |
| Wrong Quartus path | Pass `-QuartusRoot` to the folder that contains `bin64\quartus_sh.exe` |

## Optional: QuartusIQ chat inside Quartus 26.3

**Skip for Cursor.** `View > QuartusIQ` is only inside Quartus 26.3+. An empty panel does not mean Cursor failed. A Cursor API key does not work there — configure a provider key (OpenAI / Gemini / Claude) in Quartus settings if you want that panel.
