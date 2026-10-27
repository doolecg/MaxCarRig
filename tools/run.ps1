# Opens 3ds Max and runs CarRig.ms. -Main runs the committed main branch, exported to build\main-run.
param([switch]$Main)
$root = Split-Path $PSScriptRoot -Parent
$max = $env:MAX_EXE
if (-not $max) { $max = (Get-ChildItem "C:\Program Files\Autodesk\3ds Max *\3dsmax.exe" -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1).FullName }
if (-not $max) { throw "3ds Max not found. Set MAX_EXE to the full path of 3dsmax.exe." }
$script = Join-Path $root "CarRig.ms"
if ($Main) {
    $out = Join-Path $root "build\main-run"
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    New-Item -ItemType Directory $out | Out-Null
    git -C $root archive main -o "$out\main.zip"
    Expand-Archive "$out\main.zip" $out
    Remove-Item "$out\main.zip"
    $script = Join-Path $out "CarRig.ms"
}
Start-Process $max -ArgumentList "-U", "MAXScript", "`"$script`"" -WindowStyle Minimized
