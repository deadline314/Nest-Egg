"""Verify every archive and member SHA256 using Python's standard library; no extraction or source mutation."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import tarfile


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=Path(__file__).resolve().parent / 'raw-archives/index.json')
    parser.add_argument('--git-mapping', type=Path, default=Path(__file__).resolve().parent / 'git-canonical-production-v12.json')
    parser.add_argument('--skip-production-mapping', action='store_true', help='Only for small archive-integrity control fixtures')
    args = parser.parse_args()
    index_bytes = args.index.read_bytes()
    assert b'\r\n' not in index_bytes, 'Index must use canonical LF for Git-stable metadata hashes'
    index = json.loads(index_bytes)
    production = {} if args.skip_production_mapping else {row['path']: row for row in json.loads(args.git_mapping.read_text(encoding='utf8'))['files']}
    if not args.skip_production_mapping: assert len(production) == 123
    production_seen = set()
    folder = args.index.resolve().parent
    seen_all = set()
    count = 0
    for record in index['archives']:
        path = folder / record['file']
        manifest = folder / record['manifest']
        assert path.stat().st_size == record['size'] < index['maximum_archive_bytes'], path
        assert sha256(path) == record['sha256'], path
        assert sha256(manifest) == record['manifest_sha256'], manifest
        manifest_bytes = manifest.read_bytes()
        assert b'\r\n' not in manifest_bytes, manifest
        items = json.loads(manifest_bytes)['members']
        expected = {item['path']: item for item in items}
        assert len(items) == len(expected) == record['member_count'], manifest
        seen = set()
        with tarfile.open(path, 'r:xz') as archive:
            for member in archive:
                name = PurePosixPath(member.name)
                assert member.isfile() and not name.is_absolute() and '..' not in name.parts, member.name
                assert member.name in expected and member.name not in seen and member.name not in seen_all, member.name
                item = expected[member.name]
                assert member.size == item['size'], member.name
                source = archive.extractfile(member)
                assert source is not None
                with source:
                    if member.name in production:
                        payload = source.read()
                        contract = production[member.name]
                        raw_sha = hashlib.sha256(payload).hexdigest()
                        assert raw_sha == item['sha256'] == contract['tested_raw_sha256'], member.name
                        assert len(payload) == contract['tested_raw_bytes'], member.name
                        if contract['conversion'] == 'raw-bytes':
                            canonical = payload
                        else:
                            assert contract['conversion'] == 'Git-LF-only', member.name
                            canonical = payload.replace(b'\r\n', b'\n')
                        assert not member.name.endswith('.png') or canonical == payload, member.name
                        assert len(canonical) == contract['git_canonical_bytes'], member.name
                        assert hashlib.sha256(canonical).hexdigest() == contract['git_canonical_sha256'], member.name
                        blob = b'blob ' + str(len(canonical)).encode('ascii') + b'\0' + canonical
                        assert hashlib.sha1(blob).hexdigest() == contract['git_blob_oid'], member.name
                        production_seen.add(member.name)
                    else:
                        assert hashlib.file_digest(source, 'sha256').hexdigest() == item['sha256'], member.name
                seen.add(member.name)
                seen_all.add(member.name)
        assert seen == set(expected), path
        count += len(seen)
        print(f'PASS {path.name}: {len(seen)} member hashes', flush=True)
    assert count == index['source_files']
    assert production_seen == set(production)
    if production: print(f'PASS all {len(production)} tested-raw to Git-canonical production byte/blob mappings.', flush=True)
    print(f'PASS all {len(index["archives"])} archives / {count} members; no originals changed or extracted.', flush=True)


if __name__ == '__main__': main()
