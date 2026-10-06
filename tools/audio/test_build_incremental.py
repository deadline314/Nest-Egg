"""音訊建置增量快取的測試（NE-197）：合成的小檔，不依賴下載的素材。

用法：python tools/audio/test_build_incremental.py
"""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_audio as build  # noqa: E402


def make_job(source: Path, gain_db: float = 0.0) -> dict:
    spec = {"mode": "shot", "target_db": -16.0, "gain_db": gain_db, "quality": 4.0}
    return {"layers": [{"path": source, "spec": spec, "delay_ms": 0.0, "segment": None}], "spec": spec}


class BuildCacheTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        patcher = mock.patch.object(build, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)
        self.cache_path = self.root / "build_cache.json"
        self.source = self.root / "src.wav"
        self.source.write_bytes(b"source-one")
        self.out = self.root / "out.ogg"
        self.out.write_bytes(b"encoded-one")

    def cache(self, **kwargs) -> "build.BuildCache":
        return build.BuildCache(self.cache_path, **{"read": True, "write": True, **kwargs})

    def test_an_output_is_fresh_only_after_it_was_recorded(self):
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        self.assertFalse(cache.fresh(self.out, fp), "never built → must be built")
        cache.record(self.out, fp)
        self.assertTrue(cache.fresh(self.out, fp))

    def test_the_cache_survives_a_save_and_reload(self):
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        cache.record(self.out, fp)
        cache.save()
        reloaded = self.cache()
        self.assertTrue(reloaded.fresh(self.out, reloaded.fingerprint(reloaded.job_payload(make_job(self.source)))))

    def test_a_changed_source_or_parameter_changes_the_fingerprint(self):
        cache = self.cache()
        base = cache.fingerprint(cache.job_payload(make_job(self.source)))
        self.assertNotEqual(base, cache.fingerprint(cache.job_payload(make_job(self.source, gain_db=2.0))), "parameter changed")
        self.assertNotEqual(base, cache.fingerprint(cache.job_payload(make_job(self.source), speed=1.5)), "speed variant is its own output")
        other = self.root / "other.wav"
        other.write_bytes(b"source-two")
        self.assertNotEqual(base, cache.fingerprint(cache.job_payload(make_job(other))), "different source content")
        fresh_cache = self.cache()
        self.assertEqual(base, fresh_cache.fingerprint(fresh_cache.job_payload(make_job(self.source))), "same inputs → same fingerprint in a new process")

    def test_an_edited_source_file_in_place_is_noticed(self):
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        self.source.write_bytes(b"source-changed")
        again = self.cache()
        self.assertNotEqual(fp, again.fingerprint(again.job_payload(make_job(self.source))))

    def test_an_output_touched_by_hand_is_rebuilt_unless_adopted(self):
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        cache.record(self.out, fp)
        cache.save()
        self.out.write_bytes(b"encoded-by-another-machine")
        self.assertFalse(self.cache().fresh(self.out, fp), "bytes differ from what was recorded → rebuild")
        adopting = self.cache(adopt=True)
        self.assertTrue(adopting.fresh(self.out, fp), "--adopt trusts a matching fingerprint")
        adopting.save()
        self.assertTrue(self.cache().fresh(self.out, fp), "after adopting, the next normal run skips it")

    def test_a_missing_output_is_always_rebuilt(self):
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        cache.record(self.out, fp)
        self.out.unlink()
        self.assertFalse(cache.fresh(self.out, fp))
        self.assertFalse(self.cache(adopt=True).fresh(self.out, fp))

    def test_force_and_scratch_modes_never_skip(self):
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        cache.record(self.out, fp)
        cache.save()
        self.assertFalse(self.cache(read=False).fresh(self.out, fp))

    def test_a_broken_cache_file_means_rebuild_everything_without_crashing(self):
        self.cache_path.write_text("{ not json", encoding="utf-8")
        cache = self.cache()
        fp = cache.fingerprint(cache.job_payload(make_job(self.source)))
        self.assertFalse(cache.fresh(self.out, fp))

    def test_read_only_modes_do_not_write_the_cache(self):
        cache = self.cache(read=False, write=False)
        cache.record(self.out, "x")
        cache.save()
        self.assertFalse(self.cache_path.exists())

    def test_prune_drops_outputs_that_are_no_longer_wanted(self):
        cache = self.cache()
        cache.record(self.out, "x")
        cache.prune(set())
        self.assertEqual(cache.outputs, {})


class OnlyFlagTest(unittest.TestCase):
    def test_only_without_ids_is_an_error_instead_of_rebuilding_everything(self):
        with mock.patch.object(sys, "argv", ["build_audio.py", "--only"]), self.assertRaises(SystemExit) as raised:
            build.main()
        self.assertNotEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
