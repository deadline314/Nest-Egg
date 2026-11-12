#!/usr/bin/env python3
"""Reject false-green probe output and terminate only the runner's timed-out group."""

import json
import os
import pathlib
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

from runtime_probe import run_case


@unittest.skipUnless(os.name == "posix", "executable fixtures use POSIX process groups")
class RuntimeProbeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = pathlib.Path(self.temporary.name)

    def run_fixture(self, body, timeout=5, verbose=False):
        engine = self.directory / "fake-engine"
        engine.write_text(f"#!{sys.executable}\nimport json,pathlib,sys,time,subprocess\n"
                          "out=pathlib.Path(next(x[6:] for x in sys.argv if x.startswith('--out=')))\n"
                          "out.mkdir(parents=True)\n" + body + "\n")
        engine.chmod(0o700)
        return run_case("fixture", engine, self.directory, timeout, project=self.directory,
                        scene="res://fixture.tscn", slot=self.directory / "slot",
                        **({"verbose": True} if verbose else {}))

    def test_valid_protocol(self):
        result = self.run_fixture("assert '--verbose' not in sys.argv\n"
                                  "(out/'result.json').write_text(json.dumps({'checks':3,'failures':[]}))")
        self.assertTrue(result["passed"])
        self.assertEqual(result["diagnostic_count"], 0)

    def test_verbose_is_explicit_and_preserves_valid_protocol(self):
        result = self.run_fixture("assert '--verbose' in sys.argv\n"
                                  "(out/'result.json').write_text(json.dumps({'checks':3,'failures':[]}))",
                                  verbose=True)
        self.assertTrue(result["passed"])
        command = json.loads((self.directory / "fixture-process.json").read_text())["command"]
        self.assertIn("--verbose", command)

    def test_leak_details_survive_the_bounded_ci_summary(self):
        result = self.run_fixture("(out/'result.json').write_text(json.dumps({'checks':3,'failures':[]}))\n"
                                  "print('WARNING: 4 ObjectDB instances were leaked at exit')\n"
                                  "print('Leaked instance: GDScriptFunctionState:123')\n"
                                  "print('Resource still in use: res://game/original.gd')")
        self.assertFalse(result["passed"])
        self.assertEqual(result["diagnostic_count"], 3)
        self.assertIn("Leaked instance: GDScriptFunctionState:123", result["diagnostics"])
        self.assertIn("Resource still in use: res://game/original.gd", result["diagnostics"])

    def test_script_error_after_success_is_failure(self):
        result = self.run_fixture("(out/'result.json').write_text(json.dumps({'checks':3,'failures':[]}))\n"
                                  "print('SCRIPT ERROR: late shutdown failure',flush=True)")
        self.assertFalse(result["passed"])
        self.assertEqual(result["diagnostic_count"], 1)

    def test_malformed_json_root_remains_reportable(self):
        result = self.run_fixture("(out/'result.json').write_text('[]')")
        self.assertFalse(result["passed"])
        self.assertEqual(result["result"], {})
        self.assertIn("not an object", result["result_error"])

    def test_missing_result_is_failure(self):
        result = self.run_fixture("pass")
        self.assertFalse(result["passed"])
        self.assertIn("result_error", result)

    def test_boolean_check_count_is_not_an_integer_count(self):
        result = self.run_fixture("(out/'result.json').write_text(json.dumps({'checks':True,'failures':[]}))")
        self.assertFalse(result["passed"])

    def test_diagnostic_examples_are_bounded_and_raw_is_preserved(self):
        result = self.run_fixture("(out/'result.json').write_text(json.dumps({'checks':3,'failures':[]}))\n"
                                  "for i in range(100): print('ERROR: original diagnostic '+str(i))")
        self.assertFalse(result["passed"])
        self.assertEqual(result["diagnostic_count"], 100)
        self.assertEqual(len(result["diagnostics"]), 32)
        self.assertIn("original diagnostic 99", (self.directory / "fixture.log").read_text())

    @unittest.skipUnless(sys.platform == "linux", "observes Linux /proc process state")
    def test_timeout_terminates_owned_child_group(self):
        result = self.run_fixture("child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'])\n"
                                  "(out/'child.json').write_text(json.dumps({'pid':child.pid}))\n"
                                  "time.sleep(60)", timeout=1)
        self.assertFalse(result["passed"])
        self.assertTrue(result["timeout"])
        child = json.loads((self.directory / "fixture" / "child.json").read_text())["pid"]
        # A killed descendant may briefly await reaping; it must no longer run.
        status = pathlib.Path(f"/proc/{child}/stat")
        deadline = time.monotonic() + 2
        while True:
            try:
                state = status.read_text().split(") ", 1)[1].split()[0]
            except FileNotFoundError:
                return
            if state in ["Z", "X"]:
                return
            if time.monotonic() >= deadline:
                self.fail("timed-out child still runs after its owned group was terminated")
            time.sleep(0.01)


class ExactDiagnosticTests(unittest.TestCase):
    ERROR = "ERROR: [StoryContracts] res://data/story/ch2_heron.json/scenes/ch2_t_s05_gate: live content differs from independent contract"

    def run_fixture(self, lines, expected=(), checks=3, failures=None, code=0):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            def start(command, **kwargs):
                out = pathlib.Path(next(x[6:] for x in command if x.startswith("--out=")))
                out.mkdir()
                (out / "result.json").write_text(json.dumps({"checks": checks, "failures": [] if failures is None else failures}))
                kwargs["stdout"].write("\n".join(lines) + "\n")
                process = Mock(pid=123)
                process.wait.return_value = code
                process.poll.return_value = code
                return process
            with patch("runtime_probe.subprocess.Popen", side_effect=start):
                return run_case("fixture", directory / "unused-engine", directory, 5,
                                project=directory, scene="res://fixture.tscn", slot=directory / "slot",
                                expected_diagnostics=expected)

    def test_default_zero_diagnostics_stays_strict(self):
        self.assertTrue(self.run_fixture([])["passed"])
        self.assertFalse(self.run_fixture([self.ERROR])["passed"])

    def test_exact_intentional_error_once(self):
        result = self.run_fixture([self.ERROR], (self.ERROR,))
        self.assertTrue(result["passed"])
        self.assertEqual(result["diagnostics"], [self.ERROR])
        self.assertEqual(result["diagnostic_count"], 1)
        self.assertEqual(result["observed_expected_diagnostics"], {self.ERROR: 1})
        self.assertEqual(result["unexpected_diagnostic_count"], 0)

    def test_missing_expected_error_rejects(self):
        result = self.run_fixture([], (self.ERROR,))
        self.assertFalse(result["passed"])
        self.assertEqual(result["missing_expected_diagnostics"], {self.ERROR: 1})

    def test_duplicate_expected_error_rejects(self):
        result = self.run_fixture([self.ERROR, self.ERROR], (self.ERROR,))
        self.assertFalse(result["passed"])
        self.assertEqual(result["diagnostic_count"], 2)
        self.assertEqual(result["unexpected_diagnostic_count"], 1)

    def test_wrong_scene_or_path_rejects(self):
        for altered in (self.ERROR.replace("s05_gate", "s08_contract"), self.ERROR.replace("ch2_heron", "ch1_kasa")):
            with self.subTest(line=altered):
                self.assertFalse(self.run_fixture([altered], (self.ERROR,))["passed"])

    def test_other_error_and_script_error_reject(self):
        for extra in ("ERROR: unrelated", "SCRIPT ERROR: late failure", "Leaked instance: GDScriptFunctionState:123"):
            with self.subTest(extra=extra):
                result = self.run_fixture([self.ERROR, extra], (self.ERROR,))
                self.assertFalse(result["passed"])
                self.assertEqual(result["unexpected_diagnostic_count"], 1)

    def test_hidden_after_summary_limit_rejects(self):
        expected = tuple("ERROR: deliberate " + str(i) for i in range(32))
        result = self.run_fixture([*expected, "SCRIPT ERROR: thirty-third diagnostic"], expected)
        self.assertFalse(result["passed"])
        self.assertEqual(result["diagnostic_count"], 33)
        self.assertEqual(len(result["diagnostics"]), 32)
        self.assertEqual(result["unexpected_diagnostic_count"], 1)

    def test_full_line_not_truncated_summary_is_compared(self):
        expected = "ERROR: " + "x" * 600 + " original"
        altered = "ERROR: " + "x" * 600 + " altered"
        self.assertTrue(self.run_fixture([expected], (expected,))["passed"])
        self.assertFalse(self.run_fixture([altered], (expected,))["passed"])

    def test_expected_error_does_not_bypass_exit_or_assertions(self):
        for kwargs in ({"code": 1}, {"checks": 0}, {"checks": True}, {"failures": ["real assertion"]}):
            with self.subTest(kwargs=kwargs):
                self.assertFalse(self.run_fixture([self.ERROR], (self.ERROR,), **kwargs)["passed"])

    def test_probe_cannot_authorize_diagnostics(self):
        self.assertFalse(self.run_fixture([self.ERROR], failures=[])["passed"])

    def test_pattern_and_script_error_configuration_rejects(self):
        for expected in ((".*StoryContracts.*",), ("SCRIPT ERROR: deliberate",), [self.ERROR], (self.ERROR+"\n",)):
            with self.subTest(expected=expected), self.assertRaises(ValueError):
                self.run_fixture([], expected)


if __name__ == "__main__":
    unittest.main()
