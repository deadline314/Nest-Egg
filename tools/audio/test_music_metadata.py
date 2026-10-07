"""Provenance repair must preserve other Sessions' level mappings and audio bytes."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_audio as build


class MusicMetadataTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.music_path = self.root / 'music.json'
        self.registry_path = self.root / 'licenses.json'
        self.pipeline = {'music': {'victory_sting': {'pack': 'chosen', 'file': 'new.wav'},
                                   'calm': {'pack': 'other', 'file': 'calm.wav'}}}
        self.sources = {'chosen': {'title': 'Chosen title'}, 'other': {'title': 'Calm title'}}
        self.music = {'tracks': {
            'victory_sting': {'file': 'res://audio/music/victory_sting.ogg', 'title': 'Old', 'pack': 'old', 'loop': False, 'volume_db': -3},
            'calm': {'file': 'res://audio/music/calm.ogg', 'title': 'Calm title', 'pack': 'other'}},
            'cues': {'victory': {'track': 'victory_sting', 'fade_in': 0, 'volume_db': -2}},
            'map': {'levels': {'session3_prologue': {'calm': 'calm'}}, 'default': {'calm': 'calm'}},
            'custom': 'preserve'}
        self.music_path.write_text(json.dumps(self.music))
        self.registry = {}
        for track, item in self.pipeline['music'].items():
            output = 'res://audio/music/' + track + '.ogg'
            path = self.root / output.removeprefix('res://')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'original encoded output')
            self.registry[item['pack']] = {'license': 'CC0-1.0', 'outputs': [output], 'files_used': [item['file']]}
        self.registry_path.write_text(json.dumps(self.registry))
        for key, value in [('ROOT', self.root), ('MUSIC_DATA', self.music_path), ('LICENSES', self.registry_path)]:
            p = patch.object(build, key, value)
            p.start()
            self.addCleanup(p.stop)

    def test_repair_is_metadata_only_and_idempotent(self):
        audio = {p: p.read_bytes() for p in self.root.rglob('*.ogg')}
        self.assertEqual(build.repair_registered_music_metadata(self.pipeline, self.sources), 1)
        expected = copy.deepcopy(self.music)
        expected['tracks']['victory_sting'].update(pack='chosen', title='Chosen title')
        self.assertEqual(json.loads(self.music_path.read_text()), expected)
        self.assertEqual({p: p.read_bytes() for p in audio}, audio)
        self.assertEqual(build.repair_registered_music_metadata(self.pipeline, self.sources), 0)

    def test_invalid_provenance_never_partially_writes(self):
        before = self.music_path.read_bytes()
        self.registry['other']['outputs'] = []
        self.registry_path.write_text(json.dumps(self.registry))
        with self.assertRaises(build.BuildError):
            build.repair_registered_music_metadata(self.pipeline, self.sources)
        self.assertEqual(self.music_path.read_bytes(), before)

    def test_partial_build_updates_only_successful_selected_tracks(self):
        self.assertEqual(build.sync_music_metadata(self.pipeline, self.sources, []), 0)
        self.assertEqual(build.sync_music_metadata(self.pipeline, self.sources, ['calm']), 0)
        self.assertEqual(build.sync_music_metadata(self.pipeline, self.sources, ['victory_sting']), 1)

    def test_missing_output_and_wrong_file_are_rejected(self):
        (self.root / 'audio/music/calm.ogg').unlink()
        with self.assertRaises(build.BuildError):
            build.repair_registered_music_metadata(self.pipeline, self.sources)
        (self.root / 'audio/music/calm.ogg').write_bytes(b'output')
        self.pipeline['music']['calm']['file'] = 'unregistered.wav'
        with self.assertRaises(build.BuildError):
            build.repair_registered_music_metadata(self.pipeline, self.sources)

    def test_a_cached_partial_build_also_refreshes_provenance(self):
        paths = {'PIPELINE': self.root / 'pipeline.json', 'MANIFEST': self.root / 'manifest.json',
                 'BANK': self.root / 'bank.json', 'CACHE': self.root / 'cache.json',
                 'RAW': self.root / 'raw', 'MUSIC_DIR': self.root / 'audio/music', 'SFX_DIR': self.root / 'audio/sfx'}
        for key, value in paths.items():
            p = patch.object(build, key, value)
            p.start()
            self.addCleanup(p.stop)
        paths['PIPELINE'].write_text(json.dumps(self.pipeline))
        packs = [{'id': key, 'dir': key, **value} for key, value in self.sources.items()]
        paths['MANIFEST'].write_text(json.dumps({'packs': packs}))
        paths['BANK'].write_text(json.dumps({'sounds': {}}))
        cache = build.BuildCache(paths['CACHE'], read=True, write=True)
        for track_id, item in self.pipeline['music'].items():
            source = paths['RAW'] / item['pack'] / item['file']
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(b'unchanged source')
            spec = {**build.MUSIC_DEFAULT, **{k: v for k, v in item.items() if k not in ('pack', 'file')}}
            cache.record(paths['MUSIC_DIR'] / (track_id + '.ogg'), cache.fingerprint({'src': cache.source_digest(source), 'spec': spec}))
        cache.save()
        with patch.object(sys, 'argv', ['build_audio.py', '--only', 'victory_sting']), \
                patch.object(build, 'render_music', side_effect=AssertionError('cached audio must not render')):
            self.assertEqual(build.main(), 0)
        expected = copy.deepcopy(self.music)
        expected['tracks']['victory_sting'].update(pack='chosen', title='Chosen title')
        self.assertEqual(json.loads(self.music_path.read_text()), expected)


if __name__ == '__main__':
    unittest.main()
