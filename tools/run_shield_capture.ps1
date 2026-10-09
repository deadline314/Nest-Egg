param(
    [string]$Godot = "godot",
    [string]$OutputPath = ""
)
$ErrorActionPreference = "Stop"
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrEmpty($OutputPath)) { $OutputPath = Join-Path $taskProject "pm/Nest-Egg/images" }
$taskOutput = [IO.Path]::GetFullPath($OutputPath)
$taskProfile = Join-Path ([IO.Path]::GetTempPath()) ("ne239-shield-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $taskProfile,$taskOutput -Force | Out-Null
$taskLog = Join-Path $taskProfile "capture.log"
$taskOldAppData = $env:APPDATA
$taskOldLocalAppData = $env:LOCALAPPDATA
$taskOldProfile = $env:NE239_CAPTURE_PROFILE
$taskExit = 1
try {
    $env:APPDATA = $taskProfile
    $env:LOCALAPPDATA = $taskProfile
    $env:NE239_CAPTURE_PROFILE = $taskProfile
    & $Godot --path $taskProject --rendering-method forward_plus --rendering-driver vulkan --max-fps 60 --quit-after 600 res://tools/shield_surface_capture.tscn -- "--out=$taskOutput" 2>&1 | Tee-Object -FilePath $taskLog
    $taskExit = $LASTEXITCODE
    if (Select-String -LiteralPath $taskLog -Pattern 'SCRIPT ERROR|^ERROR:|Parse Error' -Quiet) { $taskExit = 1 }
    if ((Select-String -LiteralPath $taskLog -Pattern '^NE239_CAPTURE ' | Measure-Object).Count -ne 6) { $taskExit = 1 }
} finally {
    $env:APPDATA = $taskOldAppData
    $env:LOCALAPPDATA = $taskOldLocalAppData
    $env:NE239_CAPTURE_PROFILE = $taskOldProfile
}
exit $taskExit
