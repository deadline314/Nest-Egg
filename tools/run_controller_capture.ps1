param(
    [string]$Godot = "godot",
    [string]$OutputPath = "",
    [ValidateRange(640, 7680)][int]$Width = 1280,
    [ValidateRange(360, 4320)][int]$Height = 720,
    [ValidateRange(1.0, 1.2)][double]$TextScale = 1.0,
    [switch]$VerboseEngine,
    [switch]$SettingsOnly
)

$ErrorActionPreference = "Stop"
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path $taskProject "pm/Nest-Egg/images"
}
$taskOutput = [IO.Path]::GetFullPath($OutputPath)
$taskProfile = Join-Path ([IO.Path]::GetTempPath()) ("ne229-controller-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $taskProfile -Force | Out-Null
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskOldAppData = $env:APPDATA
$taskOldLocalAppData = $env:LOCALAPPDATA
$taskOldProfile = $env:NE229_CONTROLLER_CAPTURE_PROFILE
$taskCaptureExit = 1
$taskLog = Join-Path $taskProfile "capture.log"
try {
    $env:APPDATA = $taskProfile
    $env:LOCALAPPDATA = $taskProfile
    $env:NE229_CONTROLLER_CAPTURE_PROFILE = $taskProfile
    Write-Output "NE229_ISOLATED_PROFILE $taskProfile"
    $taskScaleArgument = $TextScale.ToString([Globalization.CultureInfo]::InvariantCulture)
    $taskEngineFlags = @()
    $taskUserFlags = @()
    if ($VerboseEngine) { $taskEngineFlags += '--verbose' }
    if ($SettingsOnly) { $taskUserFlags += '--settings-only' }
    & $Godot @taskEngineFlags --path $taskProject --rendering-method forward_plus --rendering-driver vulkan --max-fps 60 --quit-after 7200 res://tools/controller_flow_capture.tscn -- "--out=$taskOutput" "--width=$Width" "--height=$Height" "--text-scale=$taskScaleArgument" @taskUserFlags 2>&1 | Tee-Object -FilePath $taskLog
    $taskCaptureExit = $LASTEXITCODE
    if (Select-String -LiteralPath $taskLog -Pattern 'SCRIPT ERROR|^ERROR:|Parse Error' -Quiet) {
        $taskCaptureExit = 1
    }
    if (-not (Select-String -LiteralPath $taskLog -Pattern 'NE229_SYNTHETIC_FLOW checks=\d+ failures=0' -Quiet)) {
        $taskCaptureExit = 1
    }
} finally {
    $env:APPDATA = $taskOldAppData
    $env:LOCALAPPDATA = $taskOldLocalAppData
    $env:NE229_CONTROLLER_CAPTURE_PROFILE = $taskOldProfile
}
exit $taskCaptureExit
