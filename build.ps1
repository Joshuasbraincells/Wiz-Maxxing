# Builds the executables with AutoHotkey's compiler (Ahk2Exe):
#   Setup.exe, Wiz-Maxxing.exe (starts the bot), AutoFarmer\Autofarmer.exe, AutoFarmer\StatsReader.exe, AutoQuester\AutoQuester.exe
# Each exe has to stay in its folder: it reads the pictures, PlayerStats.txt, vision\ and
# ..\AutoQuester\resources\ from there.
# Easiest: double-click build.cmd (it runs this with PowerShell's script blocking turned off for this run).
# Or:      powershell -ExecutionPolicy Bypass -File build.ps1
# Needs AutoHotkey v2 and its compiler, Ahk2Exe (the scripts are v2 - ported from v1.1; https://www.autohotkey.com/).
# Ahk2Exe isn't in the v2 installer: open AutoHotkey's Dash once and pick 'Compile' to get it.
$ErrorActionPreference = 'Stop'

# ---- where AutoHotkey is: the registry's install folder, then the usual places
$roots = @()
foreach ($key in 'HKLM:\SOFTWARE\AutoHotkey', 'HKLM:\SOFTWARE\WOW6432Node\AutoHotkey', 'HKCU:\SOFTWARE\AutoHotkey') {
    try { $dir = (Get-ItemProperty $key -ErrorAction Stop).InstallDir; if ($dir) { $roots += $dir } } catch {}
}
$roots += "$env:ProgramFiles\AutoHotkey", "${env:ProgramFiles(x86)}\AutoHotkey", "$env:LOCALAPPDATA\Programs\AutoHotkey"
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
if (-not $roots) {
    throw "AutoHotkey isn't installed. Install AutoHotkey v2 (https://www.autohotkey.com/), then open its Dash and pick 'Compile' once to get the compiler - or skip building: the ready-built exes are on the GitHub Releases page."
}

# ---- the compiler
$compiler = $roots | ForEach-Object { Join-Path $_ 'Compiler\Ahk2Exe.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "AutoHotkey is installed ($($roots -join ', ')) but not its compiler (Compiler\Ahk2Exe.exe). Open AutoHotkey v2's Dash and pick 'Compile' once to get the compiler."
}

# ---- a v2 base to build on: AutoHotkey64.exe 2.x (the v2 installer puts it in v2\ - a v2.x.y folder when
# several are installed). Not v1.1's AutoHotkeyU64.exe / Unicode 64-bit.bin: these scripts are v2
$base = $null
foreach ($r in $roots) {
    $v2 = Get-ChildItem -Path $r -Filter 'AutoHotkey64.exe' -Recurse -Depth 1 -ErrorAction SilentlyContinue |
        Where-Object { $_.VersionInfo.FileVersion -like '2.*' } | Sort-Object { [version]($_.VersionInfo.FileVersion -replace '[^\d.]', '') } -Descending | Select-Object -First 1
    if ($v2) { $base = $v2.FullName; break }
}
if (-not $base) {
    throw "Only AutoHotkey v1.1 is installed - these scripts are AutoHotkey v2. Install v2 too (https://www.autohotkey.com/; it sits alongside v1.1), then run this again."
}
"Compiler: $compiler"
"Base:     $base"
# (the wizard face, assets\wizard.ico: the exes' icon - also their tray icon and the dashboard's)
$icon = Join-Path $PSScriptRoot 'assets\wizard.ico'
$iconArg = if (Test-Path $icon) { " /icon `"$icon`"" } else { '' }

# ---- build (a running exe can't be replaced)
foreach ($script in 'Setup.ahk', 'Wiz-Maxxing.ahk', 'AutoFarmer\Autofarmer.ahk', 'AutoFarmer\StatsReader.ahk', 'AutoQuester\AutoQuester.ahk') {
    $in = Join-Path $PSScriptRoot $script
    $out = [IO.Path]::ChangeExtension($in, '.exe')
    if (-not (Test-Path $in)) { throw "$script isn't there - run this from the Wizard101 folder (build.ps1 sits next to AutoFarmer\ and AutoQuester\)." }
    $running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($out)) -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $out }
    if ($running) { throw "$(Split-Path $out -Leaf) is running - close it first (its tray icon > Exit, or Windows+Esc; the 'Open with Wizard101' watcher: its tray icon > Stop watching), then build again." }
    if (Test-Path $out) { Remove-Item $out -Force }
    $p = Start-Process -FilePath $compiler -ArgumentList "/in `"$in`" /out `"$out`" /base `"$base`"$iconArg /silent" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0 -or -not (Test-Path $out)) { throw "Compiling $script failed (Ahk2Exe exit $($p.ExitCode))." }
    '{0} -> {1} ({2:N0} KB)' -f $script, (Split-Path $out -Leaf), ((Get-Item $out).Length / 1KB)
}
'Done.'
