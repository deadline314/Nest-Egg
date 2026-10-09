param(
 [string]$Godot = "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe",
 [ValidateSet("unclaimed","claimed","failure","service","campaign","shutdown","cycle")][string]$Mode = "service",
 [string]$OutputPath = "",
 [switch]$Headless,
 [switch]$Native,
 [ValidateRange(1,4)][int]$CycleSlots = 4
)
$ErrorActionPreference = "Stop"
$bg23Project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrEmpty($OutputPath)) { $OutputPath = Join-Path $bg23Project ('pm/Nest-Egg-BG/attachments/BG-23-' + $Mode) }
$bg23Output = [IO.Path]::GetFullPath($OutputPath)
$bg23Profile = Join-Path ([IO.Path]::GetTempPath()) ('bg23-prefetch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $bg23Output,$bg23Profile -Force | Out-Null
$bg23Info = [Diagnostics.ProcessStartInfo]::new()
$bg23Info.FileName = $Godot
$bg23Info.UseShellExecute = $false
$bg23Info.CreateNoWindow = $true
$bg23Info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$bg23Info.RedirectStandardOutput = $true
$bg23Info.RedirectStandardError = $true
$bg23Info.Environment['APPDATA'] = $bg23Profile
$bg23Info.Environment['LOCALAPPDATA'] = $bg23Profile
$bg23Info.Environment['BG23_PREFETCH_PROFILE'] = $bg23Profile
$bg23Frames = if ($Mode -in @('service','campaign','cycle')) { '18000' } else { '1200' }
$bg23Arguments = @('--path',$bg23Project,'--verbose','--max-fps','60','--quit-after',$bg23Frames)
if ($Headless -or (-not $Native -and $Mode -ne 'campaign')) { $bg23Arguments += '--headless' }
else { $bg23Arguments += @('--rendering-method','forward_plus','--rendering-driver','vulkan') }
$bg23Arguments += @('res://tools/prefetch_lifetime_probe.tscn','--',('--mode='+$Mode),('--out='+$bg23Output),('--slots='+$CycleSlots))
foreach ($bg23Argument in $bg23Arguments) { $bg23Info.ArgumentList.Add($bg23Argument) }
$bg23Process = [Diagnostics.Process]::new()
$bg23Process.StartInfo = $bg23Info
$bg23Exit = 1
try {
[void]$bg23Process.Start()
if (-not ('Bg23LiveLog' -as [type])) {
 Add-Type -TypeDefinition @'
using System.IO;
using System.Text;
using System.Threading.Tasks;
public static class Bg23LiveLog {
 public static string ReadShared(string path) {
  using (var reader = new StreamReader(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))) {
   return reader.ReadToEnd();
  }
 }
 public static async Task CopyAsync(StreamReader reader, string path) {
  using (var writer = new StreamWriter(new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite), new UTF8Encoding(false))) {
   var buffer = new char[4096];
   int count;
   while ((count = await reader.ReadAsync(buffer, 0, buffer.Length)) > 0) {
    await writer.WriteAsync(buffer, 0, count);
    await writer.FlushAsync();
   }
  }
 }
}
'@
}
$bg23StdoutPath = Join-Path $bg23Output 'stdout.live.log'
$bg23StderrPath = Join-Path $bg23Output 'stderr.live.log'
$bg23StdoutTask = [Bg23LiveLog]::CopyAsync($bg23Process.StandardOutput, $bg23StdoutPath)
$bg23StderrTask = [Bg23LiveLog]::CopyAsync($bg23Process.StandardError, $bg23StderrPath)
$bg23Watch = [Diagnostics.Stopwatch]::StartNew()
$bg23ForcedFailure = $false
$bg23Poll = 0
$bg23NativeId = $bg23Process.Id
$bg23NativeFound = $false
$bg23WorkingSet = [Collections.Generic.List[object]]::new()
while (-not $bg23Process.HasExited) {
 $bg23Poll++
 if ($bg23Watch.Elapsed.TotalSeconds -gt 330 -or ($bg23Poll % 10 -eq 0 -and [Bg23LiveLog]::ReadShared($bg23StderrPath) -match 'SCRIPT ERROR|Failed to load script')) {
  $bg23ForcedFailure = $true
  $bg23Process.Kill($true)
  break
 }
 if (-not $bg23NativeFound) {
  $bg23Child = Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $bg23Process.Id) | Where-Object { $_.Name -like 'Godot*' } | Select-Object -First 1
  if ($null -ne $bg23Child) { $bg23NativeId = $bg23Child.ProcessId; $bg23NativeFound = $true }
 }
 $bg23Native = Get-Process -Id $bg23NativeId -ErrorAction SilentlyContinue
 if ($null -ne $bg23Native) { $bg23WorkingSet.Add(@{utc=[DateTime]::UtcNow.ToString('o');pid=$bg23NativeId;working_set_bytes=$bg23Native.WorkingSet64;private_bytes=$bg23Native.PrivateMemorySize64}); $bg23Native.Dispose() }
 Start-Sleep -Milliseconds 200
}
$bg23Process.WaitForExit()
$bg23StdoutTask.GetAwaiter().GetResult()
$bg23StderrTask.GetAwaiter().GetResult()
$bg23Stdout = [IO.File]::ReadAllText($bg23StdoutPath)
$bg23Stderr = [IO.File]::ReadAllText($bg23StderrPath)
$bg23Raw = $bg23Stdout + "`n" + $bg23Stderr
[IO.File]::WriteAllText((Join-Path $bg23Output 'engine.log'), $bg23Raw, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $bg23Output 'working-set.json'), (ConvertTo-Json -InputObject @($bg23WorkingSet.ToArray()) -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Output ('BG23_ISOLATED_PROFILE ' + $bg23Profile)
Write-Output ('BG23_NATIVE_PID ' + $bg23NativeId)
Write-Output $bg23Raw
$bg23Exit = $bg23Process.ExitCode
if ($bg23ForcedFailure -or $bg23Raw -match 'SCRIPT ERROR' -or $bg23Raw -notmatch ('BG23_RESULT mode='+$Mode+' checks=\d+ failures=0')) { $bg23Exit = 1 }
# Only the two deliberate corrupt-resource diagnostics are expected. Preserve
# the full log; unrelated native/script errors still fail this isolated probe.
foreach ($bg23Line in ($bg23Raw -split "`r?`n")) {
 if ($bg23Line -match '^ERROR:|Parse Error') {
  $bg23Expected = $Mode -eq 'failure' -and ($bg23Line -match '^ERROR: user://bg23-intentional-invalid-texture\.tres:3 - Parse Error: Expected value' -or $bg23Line -eq 'ERROR: Failed loading resource: user://bg23-intentional-invalid-texture.tres.')
  if (-not $bg23Expected) { $bg23Exit = 1 }
 }
}
} finally {
 if (-not $bg23Process.HasExited) { $bg23Process.Kill($true); $bg23Process.WaitForExit() }
 $bg23Process.Dispose()
}
exit $bg23Exit
