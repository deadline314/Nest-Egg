<#
.SYNOPSIS
  Start (or restart / stop) the local ComfyUI server with the flags Nest Egg needs. Returns only when the server answers.

.EXAMPLE
  powershell -File tools/comfyui/start_comfyui.ps1            # start if not running, wait until ready
  powershell -File tools/comfyui/start_comfyui.ps1 -Restart   # restart the selected port
  powershell -File tools/comfyui/start_comfyui.ps1 -Stop      # stop the selected port
  powershell -File tools/comfyui/start_comfyui.ps1 -Restart -Safe   # conservative mode: models are unloaded after every job

  Exit code 0 = server ready (or stopped for -Stop), 1 = did not become ready in time (log tail printed).

  Runtime is checked with PyTorch, not guessed from the install folder. COMFYUI_DIR selects the install;
  COMFYUI_PYTHON (or -Python) selects the interpreter. AMD defaults to .venv-rocm when present.
  Intel XPU retains the measured bf16/reserved-memory flags. CUDA and ROCm use the normal defaults.
  -Safe adds --disable-smart-memory on every backend, including when COMFYUI_FLAGS is supplied.
  -PlanOnly reports the detected runtime and command without starting or stopping a server.

  Log: <ComfyUI>\nest_egg\comfy.log (comfy-<port>.log for nondefault ports; previous runs use .prev.log). The generation client
  (tools/comfyui/comfy_api.py) reads it to spot out-of-memory errors.
#>
param(
    [switch]$Restart,
    [switch]$Stop,
    [switch]$Safe,
    [string]$Python = $env:COMFYUI_PYTHON,
    [switch]$PlanOnly,
    [ValidateRange(1, 3600)][int]$TimeoutSec = 300,
    [ValidateRange(1, 65535)][int]$Port = 8188
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
    $portPattern = '(?:^|\s)--port(?:\s+|=)' + $Port + '(?=\s|$)'
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and $_.CommandLine -match "main\.py" -and $_.CommandLine -match "--listen" -and $_.CommandLine -match $portPattern
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
    $remaining = @(Get-ComfyProcesses)
    if ($remaining.Count -gt 0) { throw "ComfyUI on port $Port did not stop; process ids: $($remaining.ProcessId -join ', ')." }
    if ($procs.Count -gt 0) { Write-Host "stopped $($procs.Count) ComfyUI process(es)" }
}

if ($PlanOnly -and ($Restart -or $Stop)) { throw 'PlanOnly cannot start, stop or restart the service.' }
if ($Stop) { Stop-Comfy; exit 0 }

$dir = Find-ComfyDir
if (-not $Python) {
    $amd = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'AMD|Radeon' })
    $environments = if ($amd.Count -gt 0) { @('.venv-rocm', '.venv', 'venv') } else { @('.venv', 'venv') }
    foreach ($candidate in $environments) {
        $interpreter = Join-Path $dir "$candidate\Scripts\python.exe"
        if (Test-Path -LiteralPath $interpreter) { $Python = $interpreter; break }
    }
}
if (-not $Python -or -not (Test-Path -LiteralPath $Python)) {
    throw 'No Python interpreter found. Set COMFYUI_PYTHON to the intended environment python.exe.'
}
$py = (Resolve-Path -LiteralPath $Python).Path
$runtimeJson = & $py (Join-Path $PSScriptRoot 'runtime_probe.py')
if ($LASTEXITCODE -ne 0) { throw "ComfyUI GPU runtime is unavailable: $runtimeJson" }
$runtime = $runtimeJson | ConvertFrom-Json
$flags = if ($env:COMFYUI_FLAGS) { $env:COMFYUI_FLAGS }
         elseif ($runtime.backend -eq 'xpu') { '--bf16-unet --bf16-vae --bf16-text-enc --force-upcast-attention --reserve-vram 2.5' }
         else { '--disable-auto-launch' }
if ($Safe -and $flags -notmatch '(^|\s)--disable-smart-memory(\s|$)') { $flags += ' --disable-smart-memory' }
$serviceStorage = if ($Port -ne 8188) { Join-Path $dir "nest_egg\service-$Port" } else { $null }
if ($PlanOnly) {
    @{ directory = $dir; python = $py; runtime = $runtime; flags = $flags; port = $Port; storage = $serviceStorage } | ConvertTo-Json -Depth 5
    exit 0
}

if ($Restart) { Stop-Comfy }
elseif (Test-ComfyReady) {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    $serverProcess = if ($listener) { Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" }
    $command = if ($serverProcess) { $serverProcess.CommandLine.Replace('\', '/') } else { '' }
    if ($command.IndexOf($py.Replace('\', '/'), [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Port $Port is served by a different Python environment. Choose another -Port or explicitly restart the intended server."
    }
    Write-Host "ComfyUI already running on port $Port ($py)"; exit 0
}
else { Stop-Comfy }  # a half-dead server (port closed, process alive) would hold VRAM; clear it first

# VRAM is shared with anything else on the GPU: Godot imports or screenshots next to a running ComfyUI have caused out-of-memory hangs
$godot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Godot*" })
if ($godot.Count -gt 0) { Write-Warning "Godot is running ($($godot.Count) process(es)); close it before generating, VRAM is shared." }

$logDir = Join-Path $dir "nest_egg"
New-Item -ItemType Directory -Force $logDir | Out-Null
$logName = if ($Port -eq 8188) { 'comfy' } else { "comfy-$Port" }
$log = Join-Path $logDir "$logName.log"
if (Test-Path $log) { Move-Item -Force $log (Join-Path $logDir "$logName.prev.log") }

$env:PYTHONUNBUFFERED = "1"
$storageFlags = ''
if ($serviceStorage) {
    foreach ($folder in @('user', 'input', 'output', 'temp')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $serviceStorage $folder) | Out-Null
    }
    # An explicit database URL also disables ComfyUI's legacy shared-database migration.
    $databaseUrl = 'sqlite:///' + (Join-Path $serviceStorage 'user\comfyui.db').Replace('\', '/')
    $storageFlags = "--user-directory `"$serviceStorage\user`" --input-directory `"$serviceStorage\input`" --output-directory `"$serviceStorage\output`" --temp-directory `"$serviceStorage\temp`" --database-url `"$databaseUrl`""
}
$cmd = "`"$py`" main.py --listen 127.0.0.1 --port $Port $flags $storageFlags > `"$log`" 2>&1"
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
