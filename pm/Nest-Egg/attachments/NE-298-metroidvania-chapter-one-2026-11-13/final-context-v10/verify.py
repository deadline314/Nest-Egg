"""Read-only CPU recheck of this fixed NE298 supplement, without Godot or a WT."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import re
import sys
import tempfile
import zipfile


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def unpack(path, target):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            assert not Path(name).is_absolute() and '..' not in Path(name).parts
        archive.extractall(target)


def verify(root):
    root = Path(root)
    for item in json.loads((root / 'index.json').read_bytes())['files']:
        path = root / item['path']
        assert path.stat().st_size == item['bytes'] and sha(path) == item['sha256'], item['path']
    final = json.loads((root / 'final26-manifest.json').read_bytes())['files']
    original = json.loads((root / 'original21-v8-manifest.json').read_bytes())['owned']
    assert len(final) == 26 and len(original) == 21
    pins = {item['path']: item for item in final}
    assert len(pins) == 26
    for name, item in original.items():
        assert pins[name]['sha256'] == item['sha256'] and pins[name]['bytes'] == item['size']
    with zipfile.ZipFile(root / 'original21-v8-source.zip') as archive:
        assert archive.testzip() is None and set(archive.namelist()) == set(original)
        for name, item in original.items():
            data = archive.read(name)
            assert len(data) == item['size'] and hashlib.sha256(data).hexdigest() == item['sha256']
    with zipfile.ZipFile(root / 'final26-source.zip') as archive:
        assert set(archive.namelist()) == set(pins)
        for name, item in pins.items():
            data = archive.read(name)
            assert len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256']
    for item in json.loads((root / 'v9/manifest.json').read_bytes())['files']:
        for state in ['before', 'after']:
            path = root / 'v9' / state / item['path']
            assert path.stat().st_size == item[state]['bytes'] and sha(path) == item[state]['sha256']
        subsequent = root / 'v10/before' / item['path']
        if subsequent.exists():
            assert sha(subsequent) == item['after']['sha256']
        else:
            assert pins[item['path']]['sha256'] == item['after']['sha256']
    for item in json.loads((root / 'v10/changes.json').read_bytes()):
        assert sha(root / 'v10/before' / item['path']) == item['before_sha256']
        assert sha(root / 'v10/after' / item['path']) == item['after_sha256'] == pins[item['path']]['sha256']
    failures = [line for line in (root / 'v9/original-shard0.log').read_text(encoding='utf8').splitlines() if line.startswith('FAIL:')]
    assert len(failures) == 13 and all('feet have a floor' in line or 'clear headroom' in line for line in failures)
    with tempfile.TemporaryDirectory(prefix='ne298-cpu-context-') as folder:
        tree = Path(folder)
        unpack(root / 'final26-source.zip', tree)
        unpack(root / 'cpu-context.zip', tree)
        for item in [*final, *json.loads((root / 'cpu-context-manifest.json').read_bytes())['files']]:
            assert (tree / item['path']).stat().st_size == item['bytes'] and sha(tree / item['path']) == item['sha256']
        spec = importlib.util.spec_from_file_location('original_v9_cpu', root / 'v9/verify_geometry.py')
        reader = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reader)
        result = reader.replay(tree)
        source = (tree / 'tools/scenarios/throwables_ch1_scenario.gd').read_text(encoding='utf8')
        table = re.search(r'const BEATS := (\[.*?^\])', source, re.M | re.S)[1]
        table = table.replace('&"', '"').replace('STREET', '"ch1_street"').replace('WAREHOUSE', '"ch1_warehouse"')
        table = re.sub(r'Vector2\((\d+),\s*(\d+)\)', r'(\1,\2)', table)
        beats = ast.literal_eval(table)
        assert len(beats) == 3
        targets = 0
        for beat in beats:
            rows = reader.layout(tree, beat['level'])
            assert all(reader.checks(rows, int(beat['start']), beat['floor_row']))
            resource = (tree / f'data/levels/{beat["level"]}.tres').read_text(encoding='utf8')
            legend = re.search(r'legend = Dictionary\[String, Resource\]\(\{(.*?)\}\)', resource, re.S)[1]
            external = {ident: path for path, ident in re.findall(r'\[ext_resource[^\n]*path="res://([^"]+)" id="([^"]+)"', resource)}
            glyphs = dict(re.findall(r'"([^"]+)": ExtResource\("([^"]+)"\)', legend))
            for _, _, (x, y) in beat['throws']:
                path = external[glyphs[rows[y][x]]]
                assert path.startswith('data/enemies/') and 'script_class="EnemyData"' in (tree / path).read_text(encoding='utf8')
                targets += 1
        assert targets == 4
        roster = (tree / 'tools/scenarios/chapter_roster_scenario.gd').read_text(encoding='utf8')
        assert '["street", "ch1_street", 98, 32]' in roster and all(reader.checks(reader.layout(tree, 'ch1_street'), 98, 32))
    return {'PASS': True, 'scope': 'CPU-only v9/v10 supplement; no official87/finalcold verdict',
            'original21_unchanged': 21, 'final_sources': 26, 'original_shard_failures': 13,
            'geometry': result, 'throw_starts': 3, 'true_enemy_targets': 4}


if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent), indent=2))
