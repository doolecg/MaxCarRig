# Builds build\V1_SimpleCarRig.mzp: drop it on a 3ds Max viewport to install the SCR button and open the tool.
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "dist"
New-Item -ItemType Directory $out -Force | Out-Null
$zip = Join-Path $out "V1_SimpleCarRig.zip"
$mzp = Join-Path $out "V1_SimpleCarRig.mzp"
Remove-Item $zip, $mzp -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $root "install\mzp.run"), (Join-Path $root "CarRig.ms") -DestinationPath $zip
Rename-Item $zip $mzp
$mzp
