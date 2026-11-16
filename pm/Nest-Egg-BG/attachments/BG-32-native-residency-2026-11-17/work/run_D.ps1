$ErrorActionPreference='Stop'
$bg32Project='C:/NE/bg32-20261117'
$bg32Work='C:/Users/stanl/Github/Nest-Egg/work/bg32-audit-20261117'
foreach($bg32Label in @('D1','D2')) {
 $bg32Output='C:/NE/evidence-20261117/bg32/isolated-'+$bg32Label
 if(Test-Path -LiteralPath $bg32Output) { throw 'Refuse existing '+$bg32Output }
 $env:APPDATA='C:/NE/bg32-profile-'+$bg32Label
 $env:LOCALAPPDATA=$env:APPDATA
 $env:PYTHONUTF8='1'
 Push-Location $bg32Project
 try {
  python tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method forward_plus --rendering-driver vulkan res://tools/texture_route_probe.tscn -- ('--out='+$bg32Output) --dwell=300 *> (Join-Path $bg32Work ('native-isolated-'+$bg32Label+'.log'))
  $bg32Exit=$LASTEXITCODE
 } finally { Pop-Location }
 [IO.File]::WriteAllText((Join-Path $bg32Work ('exit-'+$bg32Label+'.txt')),[string]$bg32Exit)
 Write-Output ($bg32Label+' natural_exit='+$bg32Exit)
 if(!(Test-Path -LiteralPath (Join-Path $bg32Output 'report.json'))) { throw 'No final report '+$bg32Label }
}
