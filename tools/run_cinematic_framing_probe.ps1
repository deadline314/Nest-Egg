param(
 [string]$Godot = 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe',
 [string]$OutputPath = '',
 [switch]$Wide
)
$ErrorActionPreference = 'Stop'
$st22Project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrEmpty($OutputPath)) { $OutputPath = Join-Path $st22Project 'pm/Nest-Egg/images' }
$st22Output = [IO.Path]::GetFullPath($OutputPath)
$st22Profile = Join-Path ([IO.Path]::GetTempPath()) ('st22-framing-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $st22Output,$st22Profile | Out-Null
$st22OldAppData = $env:APPDATA
$st22OldLocalData = $env:LOCALAPPDATA
$st22OldProfile = $env:ST22_PROFILE
$st22Suffix = if ($Wide) { 'wide' } else { '16x9' }
$st22Log = Join-Path $st22Output ('ST-22-' + $st22Suffix + '-engine.log')
$st22Exit = 1
try {
 $env:APPDATA = $st22Profile
 $env:LOCALAPPDATA = $st22Profile
 $env:ST22_PROFILE = $st22Profile
 $st22Args = @('--path',$st22Project,'--rendering-method','forward_plus','--rendering-driver','vulkan','--max-fps','60','--quit-after','10800','res://tools/cinematic_framing_probe.tscn','--',('--out='+$st22Output))
 if ($Wide) { $st22Args += '--wide' }
 & $Godot @st22Args *> $st22Log
 $st22Exit = $LASTEXITCODE
 $st22Raw = [IO.File]::ReadAllText($st22Log)
 Write-Output $st22Raw
 if ($st22Raw -match 'SCRIPT ERROR|(?m)^ERROR:|Parse Error' -or $st22Raw -notmatch 'ST22_RESULT checks=\d+ failures=0') { $st22Exit = 1 }
} finally {
 $env:APPDATA = $st22OldAppData
 $env:LOCALAPPDATA = $st22OldLocalData
 $env:ST22_PROFILE = $st22OldProfile
}
Write-Output ('ST22_ISOLATED_PROFILE ' + $st22Profile)
exit $st22Exit
