# Cursor_Rushi

## QuartusIQ → Cursor (Windows)

Setup for **Cursor + QuartusIQ MCP** per the Altera user guide:

- [Installation](https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/installation)
- [Windows: Cursor + MCP + skills](https://docs.altera.com/r/docs/m530666/current/altera-quartusiq-expert-companion-user-guide/b.-cursor-quartusiq-mcp-skills-windows)

See **[quartus-cursor-setup/README.md](quartus-cursor-setup/README.md)**.

```powershell
cd quartus-cursor-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\your-license.dat"
```

Fully quit Cursor, reopen, then ask: **list MCP servers** and **validate the Quartus installation**.
