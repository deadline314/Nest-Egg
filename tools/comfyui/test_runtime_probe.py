import unittest
import os
import subprocess
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from runtime_probe import inspect_runtime
import comfy_guard


def runtime(hip=None, cuda=None, cuda_available=False, xpu_available=False):
    def api(available, name):
        return SimpleNamespace(is_available=lambda: available, get_device_name=lambda index: name)
    return SimpleNamespace(__version__="test", version=SimpleNamespace(hip=hip, cuda=cuda),
                           cuda=api(cuda_available, "AMD Radeon RX 9070 XT" if hip else "NVIDIA"),
                           xpu=api(xpu_available, "Intel Arc"))


class RuntimeProbeTest(unittest.TestCase):
    def test_rocm_uses_cuda_namespace_without_misidentifying_vendor(self):
        result = inspect_runtime(runtime(hip="10.0.0", cuda_available=True))
        self.assertEqual(result["backend"], "rocm")
        self.assertEqual(result["device"], "cuda")
        self.assertEqual(result["name"], "AMD Radeon RX 9070 XT")

    def test_cuda_and_xpu_remain_supported(self):
        self.assertEqual(inspect_runtime(runtime(cuda="12.8", cuda_available=True))["backend"], "cuda")
        self.assertEqual(inspect_runtime(runtime(xpu_available=True))["backend"], "xpu")

    def test_wrong_runtime_and_unavailable_driver_fail_explicitly(self):
        for candidate in (runtime(cuda="12.8"), runtime(hip="10.0.0"), runtime()):
            with self.subTest(version=candidate.version):
                with self.assertRaisesRegex(RuntimeError, "No usable GPU.*CPU fallback is disabled"):
                    inspect_runtime(candidate)

    def test_restart_keeps_the_selected_port_and_safe_mode(self):
        with patch.object(comfy_guard, "HOST", "http://127.0.0.1:8189"), patch.object(comfy_guard.subprocess, "run") as run:
            run.return_value = SimpleNamespace(returncode=0, stdout="ready", stderr="")
            comfy_guard._start("-Restart", "-Safe")
            command = run.call_args.args[0]
            self.assertEqual(command[-4:], ["-Port", "8189", "-Restart", "-Safe"])

    def test_remote_failure_does_not_restart_a_local_server(self):
        with patch.object(comfy_guard, "HOST", "http://remote.example:8189"), patch.object(comfy_guard.subprocess, "run") as run:
            with self.assertRaisesRegex(comfy_guard.ComfyStalled, "remote endpoint"):
                comfy_guard._start("-Restart")
            run.assert_not_called()

    def test_rocm_allocation_failure_is_a_fatal_device_error(self):
        self.assertIsNotNone(comfy_guard._FATAL_LOG.search("RuntimeError: HIP error: out of memory"))
        self.assertIsNone(comfy_guard._FATAL_LOG.search("Ran out of memory when regular VAE decoding, retrying with tiled VAE decoding"))

    @unittest.skipUnless(os.name == "nt", "PowerShell launcher is Windows-specific")
    def test_stop_selects_the_exact_port_without_touching_a_service(self):
        launcher = Path(__file__).with_name("start_comfyui.ps1")
        script = r'''
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:NEST_EGG_TEST_LAUNCHER, [ref]$tokens, [ref]$errors)
$function = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ComfyProcesses'}, $true)
Invoke-Expression $function.Extent.Text
$Port = 8189
function Get-CimInstance {
    @(
        'python main.py --listen 127.0.0.1 --port 8189 --safe',
        'python main.py --listen 127.0.0.1 --port=8189',
        'python main.py --listen 127.0.0.1 --port 81890',
        'python main.py --listen 127.0.0.1 --port 18189',
        'python main.py --listen 127.0.0.1 --port 8189invalid',
        'python other.py --listen 127.0.0.1 --port 8189'
    ) | ForEach-Object { [pscustomobject]@{CommandLine = $_} }
}
$selected = @(Get-ComfyProcesses)
if ($errors.Count -or $selected.Count -ne 2) { throw 'Exact-port selection failed' }
'''
        result = subprocess.run(["powershell", "-NoProfile", "-Command", script],
                                env=dict(os.environ, NEST_EGG_TEST_LAUNCHER=str(launcher)), capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors="replace"))

    @unittest.skipUnless(os.name == "nt", "PowerShell launcher is Windows-specific")
    def test_preview_rejects_mutation_and_bad_ports_before_loading_any_runtime(self):
        launcher = Path(__file__).with_name("start_comfyui.ps1")
        for flags in (["-PlanOnly", "-Stop"], ["-PlanOnly", "-Restart"], ["-PlanOnly", "-Port", "0"]):
            with self.subTest(flags=flags):
                result = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(launcher), *flags],
                                        capture_output=True, timeout=15)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
