# Builds the executables with AutoHotkey's compiler (Ahk2Exe, installed with AutoHotkey v1.1):
#   AutoFarmer\Autofarmer.exe, AutoFarmer\StatsReader.exe, AutoQuester\AutoQuester.exe
# Each exe has to stay in its folder: it reads the pictures, PlayerStats.txt, vision\ and
# ..\AutoQuester\resources\ from there.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1   (close the bots first: a running exe is locked)
$ErrorActionPreference = 'Stop'
$compiler = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$base = 'C:\Program Files\AutoHotkey\Compiler\Unicode 64-bit.bin'
if (-not (Test-Path $compiler)) { throw "Ahk2Exe not found at $compiler - install AutoHotkey v1.1 (with the compiler)." }
foreach ($script in 'AutoFarmer\Autofarmer.ahk', 'AutoFarmer\StatsReader.ahk', 'AutoQuester\AutoQuester.ahk') {
    $in = Join-Path $PSScriptRoot $script
    $out = [IO.Path]::ChangeExtension($in, '.exe')
    if (Test-Path $out) { Remove-Item $out -Force }
    $p = Start-Process -FilePath $compiler -ArgumentList "/in `"$in`" /out `"$out`" /base `"$base`" /silent" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0 -or -not (Test-Path $out)) { throw "Compiling $script failed (Ahk2Exe exit $($p.ExitCode))." }
    '{0} -> {1} ({2:N0} KB)' -f $script, (Split-Path $out -Leaf), ((Get-Item $out).Length / 1KB)
}
