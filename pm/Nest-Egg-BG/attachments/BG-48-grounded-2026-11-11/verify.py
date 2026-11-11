"""Verify published BG48 evidence and explicitly scoped BG49/BG55 reuse.

Run from any directory with Python, NumPy and Pillow. No Godot or GPU needed.
"""
from pathlib import Path
import hashlib
import json
import sys
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from verify_bg48_grounded import verify_grounded, verify_related
from test_bg48_grounded_verifier import check
from verify_bg49_held import verify_held
from verify_bg55_readability import verify


def digest(data):
    return hashlib.sha256(data).hexdigest()


def extract(archive, target, selected=None):
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        names = selected if selected is not None else z.namelist()
        for name in names:
            path = target / name
            assert path.resolve().is_relative_to(target.resolve())
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(z.read(name))
        manifest_name = next((n for n in ['manifest.json', 'manifest-part.json', 'manifest-raw.json'] if n in z.namelist()), None)
        if manifest_name:
            manifest = json.loads(z.read(manifest_name))
            for name in names:
                if name in manifest:
                    data = z.read(name)
                    assert digest(data) == manifest[name]['sha256']
                    assert len(data) == manifest[name]['bytes']
    return len(names)


def main():
    sources = json.loads((HERE / 'final-source-sha256.json').read_bytes())
    for name, sha in sources.items():
        assert digest((ROOT / name).read_bytes()) == sha, name
    results = {}
    with tempfile.TemporaryDirectory(prefix='bg48-evidence-') as temporary:
        temp = Path(temporary)
        for entry in json.loads((HERE / 'archives.json').read_bytes()):
            archive = HERE / entry['archive']
            data = archive.read_bytes()
            assert len(data) == entry['bytes'] and digest(data) == entry['sha256']
            extract(archive, temp / entry['case'])
        for quality in ['high', 'low']:
            results['lounge-' + quality] = verify_grounded(temp / quality)
            results['gate-' + quality] = verify_related(temp / ('gate-' + quality))
        results['metadata-negative-controls'] = check(temp / 'high')
        for entry in json.loads((HERE / 'related-origins.json').read_bytes()):
            folder = temp / entry['case']
            for part in entry['archives']:
                archive = HERE / part['path']
                data = archive.read_bytes()
                assert len(data) == part['bytes'] and digest(data) == part['sha256']
                extract(archive, folder, part.get('selected_members'))
            if entry['kind'] == 'handoff-original-point':
                for name, expected in entry['members'].items():
                    data = (folder / name).read_bytes()
                    assert digest(data) == expected['sha256'] and len(data) == expected['bytes']
                receipt = json.loads((folder / 'exit.json').read_bytes())
                assert receipt['exit'] == 0 and receipt['strict_clean'] and receipt['sources_unchanged']
                value = verify_held(folder)
                assert value['points'] == 1 and value['images'] == 5
                assert value['observations'][0]['spot'] == '交接櫃'
                data = json.loads((folder / 'ch1_handoff/bg49-held.json').read_bytes())
                records = data['results'][0]['bg55']['records']
                assert len({r['raw_sha256'] for r in records}) == 1
                assert all(r['fog_density'] == 1.0 and r['enemy_fill_scale'] == .6 for r in records)
            else:
                value = verify(folder, True, True)
                assert value['cells'] == 24 and value['control_failures'] == 0
                for path in folder.glob('ch2_market/*-index.json'):
                    for shot in json.loads(path.read_bytes())['shots']:
                        records = shot['bg55']['records']
                        assert len(records) == 5 and len({r['raw_sha256'] for r in records}) == 1
                assert all(c['player_from_raw'] is None or c['player_from_raw']['passed'] for c in value['results'])
            results[entry['case']] = value
        extract(HERE / 'official-tool-only-raw.zip', temp / 'official')
        receipt = json.loads((temp / 'official/exit.json').read_bytes())
        assert receipt['exit'] == 0
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
