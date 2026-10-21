param([Parameter(Mandatory = $true)][string]$InstallerPath)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Exercise file operations without changing Windows font registration or loading fonts.
Add-Type -TypeDefinition @'
using System;
public static class DotfilesFonts {
    public static int AddFontResourceEx(string file, uint flags, IntPtr reserved) { return 1; }
    public static IntPtr SendMessageTimeout(IntPtr window, uint message,
        UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result) {
        result = UIntPtr.Zero;
        return IntPtr.Zero;
    }
}
'@
function Add-Type { param([string]$TypeDefinition) }
$script:registrations = @{ 'Existing font (TrueType)' = 'preserve-me.ttf' }
$script:copies = 0
function Test-Path {
    param([string]$LiteralPath)
    if ($LiteralPath -like 'HKCU:*') { return $true }
    Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
}
function New-Item {
    param([string]$Path, [string]$ItemType, [switch]$Force)
    if ($Path -like 'HKCU:*') { throw 'Existing font registry key must never be recreated.' }
    Microsoft.PowerShell.Management\New-Item @PSBoundParameters
}
function New-ItemProperty {
    param([string]$Path, [string]$Name, [string]$Value, [string]$PropertyType, [switch]$Force)
    $script:registrations[$Name] = $Value
}
function Copy-Item {
    param([string]$LiteralPath, [string]$Destination, [switch]$Force)
    if (Microsoft.PowerShell.Management\Test-Path -LiteralPath $Destination) {
        throw 'Simulated Windows lock: registered font cannot be overwritten.'
    }
    $script:copies++
    Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-font-tests-' + [Guid]::NewGuid())
$previousAppData = $env:LOCALAPPDATA
$installer = [ScriptBlock]::Create([IO.File]::ReadAllText($InstallerPath))
try {
    $source = Join-Path $root 'source'
    Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path $source -Force | Out-Null
    $env:LOCALAPPDATA = Join-Path $root 'appdata'
    $font = Join-Path $source 'UbuntuSansMono-Regular.ttf'
    [IO.File]::WriteAllText($font, 'release one')
    & $installer -FontDirectory $source
    $first = $script:registrations['Ubuntu Sans Mono Regular (TrueType)']
    if (!$first -or $script:registrations['Existing font (TrueType)'] -ne 'preserve-me.ttf') {
        throw 'Existing font registration was lost.'
    }
    & $installer -FontDirectory $source
    if ($script:copies -ne 1) { throw 'Identical install copied a registered font again.' }
    [IO.File]::WriteAllText($font, 'release two')
    & $installer -FontDirectory $source
    $second = $script:registrations['Ubuntu Sans Mono Regular (TrueType)']
    if ($first -eq $second -or [IO.File]::ReadAllText($first) -ne 'release one' -or
        [IO.File]::ReadAllText($second) -ne 'release two' -or $script:copies -ne 2) {
        throw 'Changed-byte upgrade did not retain the old file and activate the new file.'
    }
    Write-Output 'Windows font preservation, repeat-install and changed-byte upgrade checks passed.'
} finally {
    $env:LOCALAPPDATA = $previousAppData
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
