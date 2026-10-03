<#
.SYNOPSIS
  Start (or restart / stop) the local ComfyUI server with the flags Nest Egg needs. Returns only when the server answers.

.EXAMPLE
  powershell -File tools/comfyui/start_comfyui.ps1            # start if not running, wait until ready
  powershell -File tools/comfyui/start_comfyui.ps1 -Restart   # kill every ComfyUI process, then start fresh
  powershell -File tools/comfyui/start_comfyui.ps1 -Stop      # kill and leave it off
  powershell -File tools/comfyui/start_comfyui.ps1 -Restart -Safe   # conservative mode: models are unloaded after every job

  Exit code 0 = server ready (or stopped for -Stop), 1 = did not become ready in time (log tail printed).

  Profiles (picked by install folder; override the folder with $env:COMFYUI_DIR, the flags with $env:COMFYUI_FLAGS):
    C:\ComfyUI  Intel Arc B580 / PyTorch XPU: bf16 everywhere, reserve 2.5 GB VRAM
                (without them the model spills into shared memory and a step takes 160 s, or the image comes out black).
                Models stay loaded between jobs (measured 2026-10-04: 18 s per small image instead of 49 s, and no 16 GB
                re-read from disk per image). -Safe adds --disable-smart-memory, which unloads everything after each job:
                slow and disk-heavy, only for when the GPU keeps running out of memory (the generation client switches to it
                by itself after an out-of-memory failure).
    D:\ComfyUI  RTX 4070 SUPER / CUDA: no extra flags

  Log: <ComfyUI>\nest_egg\comfy.log (the previous run is kept as comfy.prev.log). The generation client
  (tools/comfyui/comfy_api.py) reads it to spot out-of-memory errors.
#>
param(
    [switch]$Restart,
    [switch]$Stop,
    [switch]$Safe,
    [int]$TimeoutSec = 300,
    [int]$Port = 8188
)

$ErrorActionPreference = "Stop"

function Find-ComfyDir {
    $candidates = @($env:COMFYUI_DIR, "C:\ComfyUI", "D:\ComfyUI") | Where-Object { $_ }
    foreach ($d in $candidates) {
        if (Test-Path (Join-Path $d "main.py")) { return $d }
    }
    throw "ComfyUI not found. Looked in: $($candidates -join ', '). Set `$env:COMFYUI_DIR to the folder that holds main.py."
}

function Get-ComfyProcesses {
    # python.exe running ComfyUI's main.py on our port, plus the shell wrappers that started it
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and $_.CommandLine -match "main\.py" -and $_.CommandLine -match "--listen" -and $_.CommandLine -match "--port $Port"
    }
}

function Test-ComfyReady {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/system_stats" -UseBasicParsing -TimeoutSec 3
        return $r.StatusCode -eq 200
    } catch { return $false }
}

function Stop-Comfy {
    $procs = @(Get-ComfyProcesses)
    foreach ($p in $procs) {
        # /T takes the child processes with it; ignore ones that are already gone
        cmd.exe /c "taskkill /PID $($p.ProcessId) /T /F >nul 2>&1"
    }
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-ComfyProcesses) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    if ($procs.Count -gt 0) { Write-Host "stopped $($procs.Count) ComfyUI process(es)" }
}

if ($Stop) { Stop-Comfy; exit 0 }
if ($Restart) { Stop-Comfy }
elseif (Test-ComfyReady) { Write-Host "ComfyUI already running on port $Port"; exit 0 }
else { Stop-Comfy }  # a half-dead server (port closed, process alive) would hold VRAM; clear it first

$dir = Find-ComfyDir
$py = if (Test-Path (Join-Path $dir "venv\Scripts\python.exe")) { "venv\Scripts\python.exe" } else { ".venv\Scripts\python.exe" }
$flags = if ($env:COMFYUI_FLAGS) { $env:COMFYUI_FLAGS }
         elseif ($py -like "venv\*") { "--bf16-unet --bf16-vae --bf16-text-enc --force-upcast-attention --reserve-vram 2.5" + $(if ($Safe) { " --disable-smart-memory" } else { "" }) }
         else { "--disable-auto-launch" }

# VRAM is shared with anything else on the GPU: Godot imports or screenshots next to a running ComfyUI have caused out-of-memory hangs
$godot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Godot*" })
if ($godot.Count -gt 0) { Write-Warning "Godot is running ($($godot.Count) process(es)); close it before generating, VRAM is shared." }

$logDir = Join-Path $dir "nest_egg"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "comfy.log"
if (Test-Path $log) { Move-Item -Force $log (Join-Path $logDir "comfy.prev.log") }

$env:PYTHONUNBUFFERED = "1"
$cmd = "`"$py`" main.py --listen 127.0.0.1 --port $Port $flags > `"$log`" 2>&1"
Write-Host "starting ComfyUI: $dir  ($flags)"
# cmd /c strips the outer pair of quotes, so the whole command line is wrapped once more
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmd`"" -WorkingDirectory $dir -WindowStyle Hidden | Out-Null

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if (Test-ComfyReady) {
        Write-Host "ComfyUI ready on port $Port (log: $log)"
        exit 0
    }
    Start-Sleep -Seconds 2
}
Write-Host "ComfyUI did not answer within $TimeoutSec s. Last log lines:"
if (Test-Path $log) { Get-Content $log -Tail 20 }
exit 1
