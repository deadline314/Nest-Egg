"""Offline regressions for source preservation and engine-cache identity."""
import hashlib
import importlib.util
import io
import json
import pathlib
import tarfile
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
loader = importlib.util.spec_from_file_location("audio_engine_build", HERE / "build.py")
build = importlib.util.module_from_spec(loader)
loader.loader.exec_module(build)


class EngineRecipeChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.spec, _, self.fingerprint = build.recipe()

    def cache(self):
        dist = self.root / "dist"
        dist.mkdir()
        binary = dist / "godot"
        binary.write_bytes(b"fixture engine bytes, never executed")
        receipt = {key: self.spec[key] for key in ["source_commit", "source_archive_sha256", "patch_sha256", "audio_after_sha256"]}
        receipt.update(recipe_sha256=self.fingerprint, binary_sha256=build.digest_file(binary),
                       binary_bytes=binary.stat().st_size, engine_version="4.7.2.stable.custom_build",
                       features={"wayland": True, "x11": True, "accesskit": True, "renderers": ["vulkan", "opengl3"]})
        (dist / "receipt.json").write_text(json.dumps(receipt))
        return binary, receipt

    def test_changed_binary_cannot_use_an_old_receipt(self):
        binary, _ = self.cache()
        self.assertEqual(build.verify_cached(self.root, self.fingerprint, self.spec), binary)
        binary.write_bytes(binary.read_bytes() + b"changed")
        self.assertIsNone(build.verify_cached(self.root, self.fingerprint, self.spec))

    def test_source_patch_and_features_must_match(self):
        _, original = self.cache()
        path = self.root / "dist/receipt.json"
        for key, value in [("source_commit", "wrong"), ("patch_sha256", "wrong"),
                           ("audio_after_sha256", "wrong"), ("engine_version", "4.7.2.stable.official"),
                           ("features", {"wayland": False})]:
            with self.subTest(field=key):
                path.write_text(json.dumps({**original, key: value}))
                self.assertIsNone(build.verify_cached(self.root, self.fingerprint, self.spec))

    def test_foreign_symlink_is_not_an_owned_cached_engine(self):
        binary, _ = self.cache()
        foreign = self.root / "foreign"
        binary.rename(foreign)
        binary.symlink_to(foreign)
        self.assertIsNone(build.verify_cached(self.root, self.fingerprint, self.spec))
        self.assertEqual(foreign.read_bytes(), b"fixture engine bytes, never executed")

    def test_changed_audio_source_is_preserved(self):
        path = self.root / "audio.cpp"
        path.write_bytes(b"an unrelated local edit")
        with self.assertRaises(ValueError):
            build.apply_exact_patch(path, (HERE / "audio-bus-lifetime.patch").read_text(), self.spec)
        self.assertEqual(path.read_bytes(), b"an unrelated local edit")

    def test_malformed_receipt_is_not_a_verified_engine(self):
        self.cache()
        path = self.root / "dist/receipt.json"
        for value in [[], None, "not a receipt", {"schema": 1}]:
            path.write_text(json.dumps(value))
            self.assertIsNone(build.verify_cached(self.root, self.fingerprint, self.spec))

    def test_source_directory_link_is_preserved(self):
        foreign = self.root / "foreign"
        foreign.mkdir()
        (self.root / ("godot-" + self.spec["source_commit"])).symlink_to(foreign, target_is_directory=True)
        with self.assertRaises(ValueError):
            build.prepare_source(self.root, self.root / "absent.tar.gz", self.spec, "")
        self.assertEqual(list(foreign.iterdir()), [])

    def test_wrong_archive_root_cannot_overwrite_distribution(self):
        dist = self.root / "dist"
        dist.mkdir()
        binary = dist / "godot"
        binary.write_bytes(b"preserve existing distribution")
        archive = self.root / "wrong.tar.gz"
        with tarfile.open(archive, "w:gz") as package:
            entry = tarfile.TarInfo("dist/godot")
            entry.size = 7
            package.addfile(entry, io.BytesIO(b"changed"))
        with self.assertRaises(ValueError):
            build.prepare_source(self.root, archive, self.spec, "")
        self.assertEqual(binary.read_bytes(), b"preserve existing distribution")

    def test_existing_download_is_validated_before_reuse(self):
        path = self.root / "source.tar.gz"
        path.write_bytes(b"corrupt local cache")
        with self.assertRaises(ValueError):
            build.download("https://unused.invalid", path, hashlib.sha256(b"expected").hexdigest(), 1024)
        self.assertEqual(path.read_bytes(), b"corrupt local cache")


if __name__ == "__main__":
    unittest.main()
