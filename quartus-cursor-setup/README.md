# Cursor + QuartusIQ MCP (Windows)

Follows Altera’s current guide:

- [Installation](https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/installation)
- [B. Cursor + QuartusIQ MCP + skills (Windows)](https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/b.-cursor-quartusiq-mcp-skills-windows)
- [How to get packages](https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/how-to-get-quartusiq-packages)

> Run this on the **Windows PC** where Quartus and Cursor Desktop are installed. A Cloud Agent cannot finish this link.

## Prerequisites

1. **Cursor** Desktop installed  
2. **Node.js** from https://nodejs.org (needed for `npm` / `npx`)  
3. **Quartus Prime Pro 26.3** recommended if you will create/compile projects (`C:\altera_pro\26.3\quartus`)  
4. Altera.com login → download **QuartusIQ MCP Server** (+ Programmer MCP) from https://www.altera.com/products/software-tools/quartusiq  
5. Optional: **QuartusIQ Skills** zip from the same page  

## One-command setup

```powershell
cd path\to\Cursor_Rushi\quartus-cursor-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\your-license.dat"
```

Or with an explicit package:

```powershell
.\setup-quartus-mcp.ps1 `
  -PackagePath "$env:USERPROFILE\Downloads\altera-quartus-mcp-0.6.0.tgz" `
  -LicenseFile "1800@your-license-server"
```

Optional skills:

```powershell
.\setup-quartus-mcp.ps1 `
  -LicenseFile "C:\altera_pro\license.dat" `
  -SkillsSource "$env:USERPROFILE\Downloads\quartusiq-skills"
```

## Manual steps (same as the Altera guide)

```powershell
node -v
npm -v

cd $env:USERPROFILE\Downloads
npm install -g .\altera-quartus-mcp-0.6.0.tgz
# version in the filename may differ; install every .tgz from the zip
```

Write `%USERPROFILE%\.cursor\mcp.json`:

```json
{
  "mcpServers": {
    "quartus-mcp": {
      "type": "stdio",
      "command": "C:\\Program Files\\nodejs\\npx",
      "args": ["-y", "quartus-mcp"],
      "env": {}
    }
  }
}
```

See [`mcp.json.example`](mcp.json.example) for quartus + programmer together.

Then:

1. Fully quit and reopen Cursor  
2. Ask: **list MCP servers** → expect `user-quartus-mcp` ready  
3. Ask: **validate the Quartus installation** → uses `validate_installation`  
4. Copy skill folders to `%USERPROFILE%\.cursor\skills\`

## Confirm it worked

| Check | Expected |
|---|---|
| MCP list | `user-quartus-mcp` ready (optional: `user-programmer-mcp`) |
| Validate | Quartus Pro **26.3**, license OK, no license error |
| Tools | e.g. `validate_installation`, `list_quartus_tools`, `create_project` |

## Troubleshooting

| Issue | Fix |
|---|---|
| MCP missing after restart | Confirm `mcp.json` uses `npx` + `quartus-mcp`; fully quit Cursor |
| `npx` / package not found | Re-run `npm install -g` on the downloaded `.tgz` |
| Validate fails / no Quartus | Set `QUARTUS_ROOTDIR` to `C:\altera_pro\26.3\quartus` (script does this) |
| License error | Set `LM_LICENSE_FILE` to your `.dat` or `1800@server`, restart Cursor |
