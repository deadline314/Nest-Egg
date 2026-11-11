"""Verify original BG56 archive bytes and optionally restore one closed case."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024 * 1024): value.update(block)
    return value.hexdigest()


def verify(folder, selected=None, restore=None):
    index = json.loads((folder / 'raw-index.json').read_bytes())
    assert index['maximum_zip_bytes'] == 95_000_000
    cases = [case for case in index['cases'] if selected is None or case['name'] == selected]
    assert cases
    counts = dict(cases=0, archives=0, members=0, original_bytes=0, compressed_bytes=0)
    for case in cases:
        manifest_path = folder / case['index']
        assert digest(manifest_path) == case['index_sha256']
        manifest = json.loads(manifest_path.read_bytes())
        assert manifest['name'] == case['name'] and manifest['original_bytes_preserved']
        assert len(manifest['members']) == case['members']
        names = set()
        for archive in case['archives']:
            path = folder / 'raw' / archive['file']
            assert path.stat().st_size == archive['bytes'] < 95_000_000
            assert digest(path) == archive['sha256']
            rows = [row for row in manifest['members'] if row['archive'] == path.name]
            with zipfile.ZipFile(path) as stream:
                assert set(stream.namelist()) == {row['member'] for row in rows}
                for row in rows:
                    assert row['member'] not in names
                    names.add(row['member'])
                    value = hashlib.sha256()
                    length = 0
                    with stream.open(row['member']) as member:
                        while block := member.read(1024 * 1024):
                            value.update(block)
                            length += len(block)
                    assert length == row['bytes'] and value.hexdigest() == row['sha256'], row
                    if restore is not None:
                        target = (restore / row['member']).resolve()
                        assert target.is_relative_to(restore.resolve())
                        target.parent.mkdir(parents=True, exist_ok=True)
                        assert not target.exists(), 'never overwrite a restored case'
                        target.write_bytes(stream.read(row['member']))
                    counts['members'] += 1
                    counts['original_bytes'] += length
            counts['archives'] += 1
            counts['compressed_bytes'] += path.stat().st_size
        assert len(names) == case['members']
        counts['cases'] += 1
    return dict(valid=True, **counts, verifier_sha256=digest(Path(__file__)),
                scope='independent ZIP/member SHA and byte-length verification; original case payload unchanged; numeric/geometry acceptance uses the separately preserved NumPy tools')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--case')
    parser.add_argument('--restore', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = verify(args.folder, args.case, args.restore)
    if args.out: args.out.write_bytes((json.dumps(result, indent=2) + '\n').encode())
    print(json.dumps(result))
