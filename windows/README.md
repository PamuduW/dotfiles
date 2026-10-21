# Windows Terminal

Reference export for Windows Terminal — not deployed by the dotfiles installer.

- **File:** `terminal-settings.json`
- **Import:** Windows Terminal → Settings → Open JSON file, or merge profiles/schemes into your local `settings.json`
- **Font:** Uses Ubuntu Sans Mono on Windows; the dotfiles font component installs it for the current Windows user when WSL interop is available.

The font installer uses versioned files in the current Windows user's font
directory, preserving previous files and existing registrations for other font
families. Restart font-using apps after an update.

The Windows installer regression test simulates a locked registered font and
checks repeat installs, changed-byte upgrades and registry preservation. It
writes only to a temporary directory and mocks registry and font-loading calls:

```powershell
& ([ScriptBlock]::Create((Get-Content -Raw tests/windows/test_fonts.ps1))) -InstallerPath (Resolve-Path scripts/windows/install-fonts.ps1)
```
