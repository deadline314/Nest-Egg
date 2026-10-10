param([string]$Godot = 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe', [string]$OutputPath = 'C:/tmp/st22-resume', [string[]]$Modes = @('person_write','person_read','object_write','object_read','chain_write','badindex_read','badchain_read','chain_read','death','route','leave','sameid'))
$ErrorActionPreference = 'Stop'
$st22Project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$st22Output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path $st22Output | Out-Null
$st22OldApp = $env:APPDATA
$st22OldLocal = $env:LOCALAPPDATA
$st22OldProfile = $env:ST22_PROFILE
$st22Failed = $false
try {
 foreach ($st22Mode in $Modes) {
  $st22Group = $st22Mode.Split('_')[0]
  if ($st22Mode.StartsWith('bad')) {
   $st22BadDir = Join-Path $st22Output $st22Group
   New-Item -ItemType Directory -Force -Path $st22BadDir | Out-Null
   Copy-Item -LiteralPath (Join-Path $st22Output 'chain/slot.json') -Destination (Join-Path $st22BadDir 'slot.json') -Force
  }
  $st22Profile = Join-Path $st22Output ('profile-' + $st22Mode + '-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $st22Profile | Out-Null
  $env:APPDATA = $st22Profile
  $env:LOCALAPPDATA = $st22Profile
  $env:ST22_PROFILE = $st22Profile
  $st22Log = Join-Path $st22Output ($st22Mode + '.log')
  & $Godot --path $st22Project --rendering-method forward_plus --rendering-driver vulkan --max-fps 60 --quit-after 7200 res://tools/cinematic_resume_probe.tscn -- ('--mode=' + $st22Mode) ('--save-dir=' + (Join-Path $st22Output $st22Group)) *> $st22Log
  $st22Exit = $LASTEXITCODE
  $st22Raw = [IO.File]::ReadAllText($st22Log)
  Write-Output $st22Raw
  if ($st22Exit -ne 0 -or $st22Raw -match 'SCRIPT ERROR|(?m)^ERROR:|Parse Error' -or $st22Raw -notmatch 'ST22_RESUME_RESULT mode=\w+ checks=\d+ failures=0') {
   $st22Failed = $true
   break
  }
 }
} finally {
 $env:APPDATA = $st22OldApp
 $env:LOCALAPPDATA = $st22OldLocal
 $env:ST22_PROFILE = $st22OldProfile
}
exit $(if ($st22Failed) { 1 } else { 0 })
