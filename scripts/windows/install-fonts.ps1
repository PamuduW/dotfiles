param([Parameter(Mandatory = $true)][string]$FontDirectory)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DotfilesFonts {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResourceEx(string file, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message,
        UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@

$fonts = @(Get-ChildItem -LiteralPath $FontDirectory -File -Filter 'UbuntuSansMono-*.ttf')
if ($fonts.Count -eq 0) { throw 'No Ubuntu Sans Mono static fonts found.' }
$destination = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$registry = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
if (!(Test-Path -LiteralPath $registry)) { New-Item -Path $registry -Force | Out-Null }
foreach ($font in $fonts) {
    $digest = (Get-FileHash -LiteralPath $font.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $target = Join-Path $destination ($font.BaseName + '-' + $digest.Substring(0, 16) + $font.Extension)
    if (!(Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $font.FullName -Destination $target
    } elseif ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $digest) {
        throw "Existing versioned font has unexpected contents: $target"
    }
    $style = $font.BaseName.Substring('UbuntuSansMono-'.Length)
    New-ItemProperty -Path $registry -Name "Ubuntu Sans Mono $style (TrueType)" `
        -Value $target -PropertyType String -Force | Out-Null
    if ([DotfilesFonts]::AddFontResourceEx($target, 0, [IntPtr]::Zero) -eq 0) {
        throw "Windows could not load $($font.Name). Close font-using apps and retry."
    }
}
$result = [UIntPtr]::Zero
[DotfilesFonts]::SendMessageTimeout([IntPtr]0xffff, 0x001d, [UIntPtr]::Zero,
    [IntPtr]::Zero, 2, 1000, [ref]$result) | Out-Null
Write-Output "Ubuntu Sans Mono installed for the current Windows user ($($fonts.Count) fonts)."
