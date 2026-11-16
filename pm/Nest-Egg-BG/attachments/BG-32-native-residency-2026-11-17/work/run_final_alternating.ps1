$ErrorActionPreference='Stop'
$bg32Project='C:/NE/bg32-20261117'
$bg32Work='C:/Users/stanl/Github/Nest-Egg/work/bg32-audit-20261117'
$bg32Evidence='C:/NE/evidence-20261117/bg32'
$bg32Variants=@(
 @('A3','original-256-prefetch.gd.txt'),
 @('E1','candidate-512-theme-backdrop-only-prefetch.gd.txt'),
 @('A4','original-256-prefetch.gd.txt'),
 @('E2','candidate-512-theme-backdrop-only-prefetch.gd.txt')
)
foreach($bg32Variant in $bg32Variants) {
 $bg32Label=$bg32Variant[0]
 $bg32Output=Join-Path $bg32Evidence ('isolated-'+$bg32Label)
 if(Test-Path -LiteralPath $bg32Output) { throw "Refuse to overwrite $bg32Output" }
 Copy-Item -LiteralPath (Join-Path $bg32Work $bg32Variant[1]) -Destination (Join-Path $bg32Project 'core/asset_prefetch.gd')
 $env:APPDATA='C:/NE/bg32-profile-'+$bg32Label
 $env:LOCALAPPDATA=$env:APPDATA
 $env:PYTHONUTF8='1'
 $bg32Log=Join-Path $bg32Work ('native-isolated-'+$bg32Label+'.log')
 Push-Location $bg32Project
 try {
  python tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method forward_plus --rendering-driver vulkan res://tools/texture_route_probe.tscn -- ('--out='+$bg32Output) --dwell=300 *> $bg32Log
  $bg32Exit=$LASTEXITCODE
 } finally { Pop-Location }
 [IO.File]::WriteAllText((Join-Path $bg32Work ('exit-'+$bg32Label+'.txt')),[string]$bg32Exit)
 Write-Output ($bg32Label+' natural_exit='+$bg32Exit+' source='+((Get-FileHash -LiteralPath (Join-Path $bg32Project 'core/asset_prefetch.gd') -Algorithm SHA256).Hash))
 if(!(Test-Path -LiteralPath (Join-Path $bg32Output 'report.json'))) { throw "Missing final report for $bg32Label; do not continue variants" }
}
