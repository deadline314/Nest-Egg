param(
    [string]$Godot = "godot",
    [string]$OutputPath = ""
)
$ErrorActionPreference = "Stop"
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrEmpty($OutputPath)) { $OutputPath = Join-Path $taskProject "pm/Nest-Egg/images" }
$taskOutput = [IO.Path]::GetFullPath($OutputPath)
$taskProfile = Join-Path ([IO.Path]::GetTempPath()) ("ne228-hud-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $taskProfile,$taskOutput -Force | Out-Null
$taskOldAppData = $env:APPDATA
$taskOldLocalAppData = $env:LOCALAPPDATA
$taskOldProfile = $env:NE228_HUD_PROFILE
$taskExit = 0
try {
    $env:APPDATA = $taskProfile
    $env:LOCALAPPDATA = $taskProfile
    $env:NE228_HUD_PROFILE = $taskProfile
    foreach ($taskSize in @(@(1280,720), @(1920,1080), @(2560,1080))) {
        $taskWidth = $taskSize[0]
        $taskHeight = $taskSize[1]
        $taskLog = Join-Path $taskProfile "hud-$taskWidth.log"
        & $Godot --path $taskProject --rendering-method forward_plus --rendering-driver vulkan --max-fps 60 --quit-after 1800 res://tools/hud_guidance_capture.tscn -- "--out=$taskOutput" "--width=$taskWidth" "--height=$taskHeight" 2>&1 | Tee-Object -FilePath $taskLog
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $taskLog -Pattern 'SCRIPT ERROR|^ERROR:|Parse Error' -Quiet)) { $taskExit = 1; break }
        if ((Select-String -LiteralPath $taskLog -Pattern '^NE228_HUD_RESULT \d+ checks, 0 failures' | Measure-Object).Count -ne 1) { $taskExit = 1; break }
    }
} finally {
    $env:APPDATA = $taskOldAppData
    $env:LOCALAPPDATA = $taskOldLocalAppData
    $env:NE228_HUD_PROFILE = $taskOldProfile
    Write-Output "HUD capture raw logs: $taskProfile"
}
exit $taskExit
