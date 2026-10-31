# Puts the VC++ runtime next to tallynote.exe (app-local deployment).
# A clean Windows has no VCRUNTIME140 / MSVCP140 and the exe imports them, so
# without these files the app fails to start on a fresh machine.
$ErrorActionPreference = 'Stop'
$out = 'build\windows\x64\runner\Release'
$crt = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT' -Directory |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw 'no VC++ redist folder on this runner' }
Copy-Item (Join-Path $crt.FullName '*.dll') $out -Force
Get-ChildItem "$out\*.dll" | Select-Object -ExpandProperty Name
