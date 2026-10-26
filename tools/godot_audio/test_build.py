"""Offline regressions for source preservation and engine-cache identity."""
import hashlib
import importlib.util
import io
import json
import pathlib
import tarfile
import tempfile
import unittest
import subprocess
import venv
from unittest import mock

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
        receipt.update(additional_patches=self.spec.get("additional_patches", []), recipe_sha256=self.fingerprint, binary_sha256=build.digest_file(binary),
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
                           ("audio_after_sha256", "wrong"), ("additional_patches", []), ("engine_version", "4.7.2.stable.official"),
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

    def test_selected_venv_interpreter_retains_its_package_context(self):
        environment = self.root / "selected-venv"
        venv.EnvBuilder(with_pip=False, symlinks=True).create(environment)
        python = environment / "bin/python"
        site = pathlib.Path(subprocess.check_output(
            [str(python), "-c", "import sysconfig; print(sysconfig.get_path('purelib'))"], text=True).strip())
        module = site / "SCons"
        module.mkdir(parents=True)
        (module / "__init__.py").write_text("__version__ = " + repr(self.spec["scons_version"]) + "\n")
        self.assertEqual(build.scons_python(self.root, str(python), self.spec["scons_version"]), python)
        before = (module / "__init__.py").read_bytes()
        with self.assertRaises(ValueError):
            build.scons_python(self.root, str(python), "a different pinned version")
        self.assertEqual((module / "__init__.py").read_bytes(), before)

    def test_auxiliary_patch_tampering_is_rejected_before_build(self):
        recipe = self.root / "recipe"
        recipe.mkdir()
        for name in ["manifest.json", "audio-bus-lifetime.patch", "dummy-texture-threads.patch"]:
            (recipe / name).write_bytes((HERE / name).read_bytes())
        original = (recipe / "dummy-texture-threads.patch").read_bytes()
        (recipe / "dummy-texture-threads.patch").write_bytes(original + b"changed")
        with mock.patch.object(build, "HERE", recipe), self.assertRaises(ValueError):
            build.recipe()
        self.assertEqual((HERE / "dummy-texture-threads.patch").read_bytes(), original)

    def test_auxiliary_patch_is_exact_idempotent_and_preserves_foreign_bytes(self):
        source = self.root / "texture.h"
        before = b"prefix\nunsafe owner\nsuffix\n"
        after = before.replace(b"unsafe owner", b"protected owner")
        patch = "@@ -1,3 +1,3 @@\n prefix\n-unsafe owner\n+protected owner\n suffix\n"
        pins = [hashlib.sha256(payload).hexdigest() for payload in [before, after]]
        source.write_bytes(before)
        build.apply_pinned_patch(source, patch, *pins)
        self.assertEqual(source.read_bytes(), after)
        build.apply_pinned_patch(source, patch, *pins)
        self.assertEqual(source.read_bytes(), after)
        source.write_bytes(before + b"local edit")
        with self.assertRaises(ValueError):
            build.apply_pinned_patch(source, patch, *pins)
        self.assertEqual(source.read_bytes(), before + b"local edit")
        source.write_bytes(before)
        with self.assertRaises(ValueError):
            build.apply_pinned_patch(source, patch, pins[0], "forged resulting digest")
        self.assertEqual(source.read_bytes(), before)

    def test_source_verification_covers_both_repairs_before_modifying_any_file(self):
        archive = self.root / "fixture.tar.gz"
        prefix = "godot-" + self.spec["source_commit"]
        payloads = {"audio.cpp": b"old audio\n", "texture.h": b"old texture\n", "unrelated.h": b"original\n"}
        with tarfile.open(archive, "w:gz") as package:
            for name, payload in payloads.items():
                entry = tarfile.TarInfo(prefix + "/" + name)
                entry.size = len(payload)
                package.addfile(entry, io.BytesIO(payload))
        patch = "@@ -1 +1 @@\n-old audio\n+fixed audio\n"
        auxiliary = "@@ -1 +1 @@\n-old texture\n+fixed texture\n"
        (self.root / "texture.patch").write_text(auxiliary)
        pins = lambda data: hashlib.sha256(data).hexdigest()
        spec = {"source_commit": self.spec["source_commit"], "audio_source_path": "audio.cpp",
                "audio_before_sha256": pins(payloads["audio.cpp"]), "audio_after_sha256": pins(b"fixed audio\n"),
                "additional_patches": [{"file": "texture.patch", "source_path": "texture.h",
                                        "before_sha256": pins(payloads["texture.h"]), "after_sha256": pins(b"fixed texture\n")}]}
        source = self.root / prefix
        with mock.patch.object(build, "HERE", self.root):
            result, count = build.prepare_source(self.root, archive, spec, patch)
            self.assertEqual((result, count), (source, 3))
            self.assertEqual((source / "audio.cpp").read_bytes(), b"fixed audio\n")
            self.assertEqual((source / "texture.h").read_bytes(), b"fixed texture\n")
            self.assertEqual(build.prepare_source(self.root, archive, spec, patch), (source, 3))
            (source / "audio.cpp").write_bytes(payloads["audio.cpp"])
            (source / "texture.h").write_bytes(b"unrelated local texture edit")
            with self.assertRaises(ValueError):
                build.prepare_source(self.root, archive, spec, patch)
            self.assertEqual((source / "audio.cpp").read_bytes(), payloads["audio.cpp"])
            self.assertEqual((source / "texture.h").read_bytes(), b"unrelated local texture edit")
            (source / "texture.h").write_bytes(payloads["texture.h"])
            (source / "unrelated.h").write_bytes(b"unrelated local edit")
            with self.assertRaises(ValueError):
                build.prepare_source(self.root, archive, spec, patch)
            self.assertEqual((source / "audio.cpp").read_bytes(), payloads["audio.cpp"])
            self.assertEqual((source / "unrelated.h").read_bytes(), b"unrelated local edit")


if __name__ == "__main__":
    unittest.main()
