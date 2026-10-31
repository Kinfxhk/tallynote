# Puts the VC++ runtime next to tallynote.exe (app-local deployment).
# A clean Windows has no VCRUNTIME140 / MSVCP140 and the exe imports them, so
# without these files the app fails to start on a fresh machine.
$ErrorActionPreference = 'Stop'
$out = 'build\windows\x64\runner\Release'
# Where the redistributable lives moves with the Visual Studio version the
# runner ships (and a future runner may move it again), so ask vswhere first
# and fall back to scanning both Program Files roots.
$roots = @()
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
  $roots += (& $vswhere -latest -products * -property installationPath) -split "`r?`n" | Where-Object { $_ }
}
foreach ($base in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
  if (-not $base) { continue }
  $vs = Join-Path $base 'Microsoft Visual Studio'
  if (Test-Path $vs) { $roots += (Get-ChildItem $vs -Directory | ForEach-Object { $_.FullName }) }
}
$roots = @($roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
Write-Output "visual studio roots: $($roots -join '; ')"

$crt = @(
  $roots |
    ForEach-Object { Get-ChildItem (Join-Path $_ 'VC\Redist\MSVC') -Directory -ErrorAction SilentlyContinue } |
    ForEach-Object {
      $x64 = Join-Path $_.FullName 'x64'
      if (Test-Path $x64) { Get-ChildItem $x64 -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue }
    } |
    Sort-Object FullName -Descending
) | Select-Object -First 1
if (-not $crt) { throw 'no VC++ redistributable CRT folder found on this runner' }

Copy-Item (Join-Path $crt.FullName '*.dll') $out -Force
Write-Output "copied from $($crt.FullName)"
Get-ChildItem "$out\*.dll" | Select-Object -ExpandProperty Name
