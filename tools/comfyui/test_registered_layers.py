"""Frozen PNG integrity, exact reconstructed RGBA and interrupted publication; CPU only."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

from registered_layers import registered_layer_bytes, write_registered_file
import cut_layers


class RegisteredLayerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="registered-layers-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.layers = {"arm": Image.new("RGBA", (12, 16), (25, 50, 75, 253)),
                       "hand": Image.new("RGBA", (12, 16), (160, 90, 60, 255))}
        self.layers["arm"].putpixel((0, 0), (70, 80, 90, 0))
        self.record = {"outputs": {}, "approved_outputs": {}}
        self.data = {}
        for name, image in self.layers.items():
            path = self.work / f"{name}.png"
            image.save(path, compress_level=0)
            self.data[name] = path.read_bytes()
            self.record["outputs"][name] = hashlib.sha256(self.data[name]).hexdigest()
            self.record["approved_outputs"][name] = path.name

    def validate(self):
        return registered_layer_bytes(self.layers, self.work, self.record)

    def test_different_png_encoding_preserves_exact_approved_bytes(self):
        for name, image in self.layers.items():
            encoded = io.BytesIO()
            image.save(encoded, format="PNG", compress_level=9)
            self.assertNotEqual(encoded.getvalue(), self.data[name])
        self.assertEqual(self.validate(), self.data)

    def test_one_changed_visible_pixel_fails(self):
        self.layers["hand"].putpixel((5, 5), (161, 90, 60, 255))
        with self.assertRaisesRegex(ValueError, "output pixels changed: hand"):
            self.validate()

    def test_transparent_rgb_and_alpha_are_still_exact(self):
        for pixel in [(71, 80, 90, 0), (70, 80, 90, 1)]:
            self.layers["arm"].putpixel((0, 0), pixel)
            with self.subTest(pixel=pixel), self.assertRaisesRegex(ValueError, "output pixels changed: arm"):
                self.validate()

    def test_reencoded_approved_source_is_rejected_even_with_equal_pixels(self):
        self.layers["arm"].save(self.work / "arm.png", compress_level=9)
        with self.assertRaisesRegex(ValueError, "approved output bytes changed: arm"):
            self.validate()

    def test_wrong_format_and_dimensions_fail(self):
        original = self.layers["arm"]
        for image in [original.convert("RGB"), Image.new("RGBA", (13, 16))]:
            self.layers["arm"] = image
            with self.subTest(mode=image.mode, size=image.size), self.assertRaisesRegex(ValueError, "format or dimensions"):
                self.validate()

    def test_missing_or_extra_registration_fails(self):
        del self.record["approved_outputs"]["hand"]
        with self.assertRaisesRegex(ValueError, "layer names differ"):
            self.validate()
        self.record["approved_outputs"]["hand"] = "hand.png"
        self.record["outputs"]["extra"] = "unused"
        with self.assertRaisesRegex(ValueError, "layer names differ"):
            self.validate()

    def test_source_path_escape_fails(self):
        self.record["approved_outputs"]["arm"] = "../outside.png"
        with self.assertRaisesRegex(ValueError, "inside its registered source"):
            self.validate()

    def test_late_validation_failure_publishes_nothing(self):
        output = self.work / "outputs"
        output.mkdir()
        old = output / "arm.png"
        old.write_bytes(b"previous accepted output")
        self.layers["hand"].putpixel((4, 5), (0, 0, 0, 0))
        with self.assertRaisesRegex(ValueError, "output pixels changed: hand"):
            payloads = self.validate()
            for name, data in payloads.items():
                write_registered_file(output / f"{name}.png", data)
        self.assertEqual(old.read_bytes(), b"previous accepted output")
        self.assertFalse((output / "hand.png").exists())

    def test_existing_identical_file_does_not_rewrite(self):
        target = self.work / "arm.png"
        before = target.stat().st_mtime_ns
        with patch("registered_layers.os.replace", side_effect=AssertionError("identical file rewritten")):
            write_registered_file(target, self.data["arm"])
        self.assertEqual(before, target.stat().st_mtime_ns)

    def test_atomic_write_and_publication_failure_preserve_original(self):
        target = self.work / "outputs" / "arm.png"
        write_registered_file(target, self.data["arm"])
        self.assertEqual(target.read_bytes(), self.data["arm"])
        with patch("registered_layers.os.replace", side_effect=OSError("injected publication failure")):
            with self.assertRaisesRegex(OSError, "injected publication failure"):
                write_registered_file(target, self.data["hand"])
        self.assertEqual(target.read_bytes(), self.data["arm"])
        self.assertEqual(list(target.parent.iterdir()), [target])

    def test_sync_failure_preserves_previous_file(self):
        target = self.work / "outputs" / "arm.png"
        write_registered_file(target, self.data["arm"])
        with patch("registered_layers.os.fsync", side_effect=OSError("injected sync failure")):
            with self.assertRaisesRegex(OSError, "injected sync failure"):
                write_registered_file(target, self.data["hand"])
        self.assertEqual(target.read_bytes(), self.data["arm"])
        self.assertEqual(list(target.parent.iterdir()), [target])


class SupportSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="support-source-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.root = Path(__file__).resolve().parents[2]
        path = self.root / "art_src/characters/rin_support_grip_22308/rebuild.py"
        spec = importlib.util.spec_from_file_location("registered_support_source", path)
        self.source = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.source)

    def test_actual_source_matches_approved_bytes_and_repeats(self):
        out = self.work / "out"
        first = self.source.build(out)
        snapshots = {path.name: path.read_bytes() for path in out.iterdir()}
        timestamps = {name: (out / name).stat().st_mtime_ns for name in snapshots}
        second = self.source.build(out)
        self.assertEqual(first, second)
        self.assertEqual(first["outputs_sha256"], self.source.EXPECTED_OUTPUTS)
        self.assertEqual(snapshots, {name: (out / name).read_bytes() for name in snapshots})
        self.assertEqual(timestamps, {name: (out / name).stat().st_mtime_ns for name in snapshots})

    def test_unrelated_cutter_change_keeps_normal_contract(self):
        text = (self.root / "tools/comfyui/cut_layers.py").read_text()
        path = self.work / "cut.py"
        path.write_text(text + '\nUNRELATED_METADATA = "changed"\n')
        self.source.validate_normal_implementation(path)

    def test_normal_algorithm_and_duplicate_definition_are_rejected(self):
        text = (self.root / "tools/comfyui/cut_layers.py").read_text()
        path = self.work / "cut.py"
        path.write_text(text.replace("blurred * 3.0 + luma * 1.4", "blurred * 3.0 + luma * 1.5"))
        with self.assertRaisesRegex(AssertionError, "normal-map implementation changed"):
            self.source.validate_normal_implementation(path)
        path.write_text(text + '\ndef make_normal_map(rgba):\n    return rgba\n')
        with self.assertRaisesRegex(AssertionError, "expected one normal-map"):
            self.source.validate_normal_implementation(path)
        path.write_text(text.replace("def make_normal_map(", "@staticmethod\ndef make_normal_map("))
        with self.assertRaisesRegex(AssertionError, "normal-map decorators changed"):
            self.source.validate_normal_implementation(path)

    def test_changed_normal_pixels_preserve_existing_outputs(self):
        out = self.work / "out"
        self.source.build(out)
        before = {path.name: path.read_bytes() for path in out.iterdir()}
        original = cut_layers.make_normal_map

        def changed(rgba):
            pixels = original(rgba)
            pixels[0, 0, 0] ^= 1
            return pixels

        with patch.object(cut_layers, "make_normal_map", side_effect=changed):
            with self.assertRaisesRegex(ValueError, "output pixels changed: hand_back_n.png"):
                self.source.build(out)
        self.assertEqual(before, {path.name: path.read_bytes() for path in out.iterdir()})

    def test_corrupted_frozen_input_stops_before_publication(self):
        path, digest = self.source.PINNED["approved_normal"]
        corrupted = self.work / "damaged-normal.png"
        corrupted.write_bytes(path.read_bytes() + b"changed")
        self.source.PINNED["approved_normal"] = (corrupted, digest)
        out = self.work / "out"
        with self.assertRaisesRegex(AssertionError, "pinned hash mismatch: approved_normal"):
            self.source.build(out)
        self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
