# Builds the executables with AutoHotkey's compiler (Ahk2Exe):
#   AutoFarmer\Autofarmer.exe, AutoFarmer\StatsReader.exe, AutoQuester\AutoQuester.exe
# Each exe has to stay in its folder: it reads the pictures, PlayerStats.txt, vision\ and
# ..\AutoQuester\resources\ from there.
# Easiest: double-click build.cmd (it runs this with PowerShell's script blocking turned off for this run).
# Or:      powershell -ExecutionPolicy Bypass -File build.ps1
# Needs AutoHotkey v1.1 with its compiler (the scripts are v1.1; https://www.autohotkey.com/download/1.1/).
$ErrorActionPreference = 'Stop'

# ---- where AutoHotkey is: the registry's install folder, then the usual places
$roots = @()
foreach ($key in 'HKLM:\SOFTWARE\AutoHotkey', 'HKLM:\SOFTWARE\WOW6432Node\AutoHotkey', 'HKCU:\SOFTWARE\AutoHotkey') {
    try { $dir = (Get-ItemProperty $key -ErrorAction Stop).InstallDir; if ($dir) { $roots += $dir } } catch {}
}
$roots += "$env:ProgramFiles\AutoHotkey", "${env:ProgramFiles(x86)}\AutoHotkey", "$env:LOCALAPPDATA\Programs\AutoHotkey"
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
if (-not $roots) {
    throw "AutoHotkey isn't installed. Install AutoHotkey v1.1 (it includes the compiler): https://www.autohotkey.com/download/1.1/ - or skip building: the ready-built exes are on the GitHub Releases page."
}

# ---- the compiler
$compiler = $roots | ForEach-Object { Join-Path $_ 'Compiler\Ahk2Exe.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "AutoHotkey is installed ($($roots -join ', ')) but not its compiler (Compiler\Ahk2Exe.exe). Install AutoHotkey v1.1 from https://www.autohotkey.com/download/1.1/ (the compiler comes with it), or with AutoHotkey v2 open its Dash and pick 'Compile' once to get the compiler."
}

# ---- a v1.1 base to build on: the v1 installer's .bin, else a v1.1 AutoHotkeyU64.exe (the v2 installer puts
# v1.1 in a v1.1.x.x folder). Not v2's AutoHotkey64.exe: these scripts are v1.1
$base = $null
foreach ($r in $roots) {
    $bin = Join-Path $r 'Compiler\Unicode 64-bit.bin'
    if (Test-Path $bin) { $base = $bin; break }
    $v1 = Get-ChildItem -Path $r -Filter 'AutoHotkeyU64.exe' -Recurse -Depth 1 -ErrorAction SilentlyContinue |
        Where-Object { $_.VersionInfo.FileVersion -like '1.1*' } | Sort-Object { [version]($_.VersionInfo.FileVersion -replace '[^\d.]', '') } -Descending | Select-Object -First 1
    if ($v1) { $base = $v1.FullName; break }
}
if (-not $base) {
    throw "Only AutoHotkey v2 is installed - these scripts are AutoHotkey v1.1. Install v1.1 too (https://www.autohotkey.com/download/1.1/; it sits alongside v2), then run this again."
}
"Compiler: $compiler"
"Base:     $base"

# ---- build (a running exe can't be replaced)
foreach ($script in 'AutoFarmer\Autofarmer.ahk', 'AutoFarmer\StatsReader.ahk', 'AutoQuester\AutoQuester.ahk') {
    $in = Join-Path $PSScriptRoot $script
    $out = [IO.Path]::ChangeExtension($in, '.exe')
    if (-not (Test-Path $in)) { throw "$script isn't there - run this from the Wizard101 folder (build.ps1 sits next to AutoFarmer\ and AutoQuester\)." }
    $running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($out)) -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $out }
    if ($running) { throw "$(Split-Path $out -Leaf) is running - close it first (its tray icon > Exit, or Windows+Esc), then build again." }
    if (Test-Path $out) { Remove-Item $out -Force }
    $p = Start-Process -FilePath $compiler -ArgumentList "/in `"$in`" /out `"$out`" /base `"$base`" /silent" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0 -or -not (Test-Path $out)) { throw "Compiling $script failed (Ahk2Exe exit $($p.ExitCode))." }
    '{0} -> {1} ({2:N0} KB)' -f $script, (Split-Path $out -Leaf), ((Get-Item $out).Length / 1KB)
}
'Done.'
