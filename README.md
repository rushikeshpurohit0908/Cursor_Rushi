# Cursor_Rushi

## Quartus → Cursor (Windows)

To link a local **Quartus Prime Pro 26.3** install to Cursor via QuartusIQ MCP servers, see:

**[quartus-cursor-setup/README.md](quartus-cursor-setup/README.md)**

On the Windows PC where Quartus is installed:

```powershell
cd quartus-cursor-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup-quartus-mcp.ps1 -LicenseFile "C:\altera_pro\your-license.dat"
```

Then fully quit and reopen Cursor. You should see `user-quartus-mcp` and `user-programmer-mcp`.
