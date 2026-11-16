"""Package this appearance's immutable raw history; retain all original files locally."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / 'raw-archives'
MAX_INPUT = 38_000_000  # Tar headers included conservatively; each output must remain <50 decimal MB.


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def epoch(path):
    relative = path.relative_to(ROOT).as_posix()
    found = re.search(r'(?:^|[-_/])v(\d+)(?:[-_/.]|$)', relative)
    return f'v{int(found.group(1)):02d}' if found else 'unversioned-records'


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=OUT, help='Packet staging folder; may be on another drive')
    parser.add_argument('--inventory-only', action='store_true', help='Hash inputs and report duplicate bytes without packing')
    args = parser.parse_args()
    OUT = args.out.resolve()
    if OUT.exists() and any(OUT.iterdir()):
        raise SystemExit('Archive directory is not empty; existing evidence will not be overwritten.')
    OUT.mkdir(parents=True, exist_ok=True)
    frozen = json.loads((HERE / 'production-v12-freeze-123.json').read_text(encoding='utf8'))['files']
    for name, value in frozen.items():
        if digest(ROOT / name) != value:
            raise SystemExit(f'Frozen production file changed: {name}')
    excluded = {'pack_raw_evidence.py', 'verify_raw_archives.py', '.gitignore', 'REVIEW-v12.md', 'delivery-files.json'}
    sources = {ROOT / name: 'authoring-v12' for name in frozen}
    for path in (HERE.parent / '06_parts').rglob('*'):
        if path.is_file(): sources[path] = 'v12-intermediates'
    for path in HERE.rglob('*'):
        if path.is_file() and not path.is_relative_to(OUT) and not path.is_relative_to(HERE / 'raw-archives') and path.name not in excluded:
            sources[path] = epoch(path)
    images = ROOT / 'pm/Nest-Egg/images/NE-255-fresh-character'
    for path in images.rglob('*'):
        if path.is_file() and path.name != '.gitignore':
            sources[path] = epoch(path)
    for name in ['REPORT.md', 'verify.py', 'verification.json']:
        path = ROOT / 'work/ne255-independent-ui-review-v7' / name
        if path.is_file(): sources[path] = 'v07-independent-review'
    for name, label in [('v9-source-head-torso.png', 'v09-independent-review'), ('elbow-v12-source-ownership.png', 'v12-independent-review')]:
        root_review = ROOT / 'work/ne255-root-neck-review' / name
        if root_review.is_file(): sources[root_review] = label
    if args.inventory_only:
        records = []
        blobs = {}
        for path, label in sources.items():
            size = path.stat().st_size
            value = digest(path)
            blobs.setdefault(value, size)
            records.append({'path': path.relative_to(ROOT).as_posix(), 'epoch': label, 'size': size, 'sha256': value})
        inventory = {'source_files': len(records), 'source_bytes': sum(row['size'] for row in records), 'unique_sha256_blobs': len(blobs), 'sha256_deduplicated_bytes': sum(blobs.values()), 'files': records}
        destination = OUT.parent / 'raw-input-inventory.json'
        destination.write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
        print(json.dumps({key: value for key, value in inventory.items() if key != 'files'}), flush=True)
        print('Inventory:', destination, flush=True)
        return
    groups = {}
    # Adjacent pair/as-worn records let xz reuse identical bytes; every original
    # path and byte is still retained and independently hashed.
    def ordering(pair):
        name = pair[0].as_posix()
        return pair[1], name.replace('-pair-', '-view-').replace('-worn-', '-view-'), name
    for path, label in sorted(sources.items(), key=ordering):
        groups.setdefault(label, []).append(path)
    index = {'format': 1, 'maximum_archive_bytes': 50_000_000, 'original_files_retained_locally': True,
             'epoch_rule': 'Explicit vN labels in original paths; unlabelled original generation/diagnostics remain separate. Formal frozen production has its own volume.',
             'source_files': len(sources), 'source_bytes': sum(path.stat().st_size for path in sources), 'archives': []}
    for label, paths in groups.items():
        volumes = [[]]
        size = 0
        for path in paths:
            cost = path.stat().st_size + 2048
            if cost > MAX_INPUT: raise ValueError(f'Individual member exceeds volume budget: {path}')
            if volumes[-1] and size + cost > MAX_INPUT:
                volumes.append([])
                size = 0
            volumes[-1].append(path)
            size += cost
        for number, members in enumerate(volumes, 1):
            name = f'{label}-{number:02d}.raw.tar.xz'
            target = OUT / name
            records = []
            with tarfile.open(target, 'w:xz', preset=4, format=tarfile.PAX_FORMAT) as archive:
                for path in members:
                    relative = path.relative_to(ROOT).as_posix()
                    stat = path.stat()
                    records.append({'path': relative, 'size': stat.st_size, 'sha256': digest(path), 'original_mtime_ns': stat.st_mtime_ns})
                    info = tarfile.TarInfo(relative)
                    info.size = stat.st_size
                    info.mode = 0o644
                    info.mtime = 0
                    with path.open('rb') as source: archive.addfile(info, source)
            if target.stat().st_size >= 50_000_000: raise ValueError(f'Archive exceeds delivery limit: {target}')
            member_name = name + '.members.json'
            member_file = OUT / member_name
            member_file.write_bytes((json.dumps({'archive': name, 'members': records}, ensure_ascii=False, indent=2) + '\n').encode('utf8'))
            index['archives'].append({'file': name, 'epoch': label, 'size': target.stat().st_size,
                                      'sha256': digest(target), 'manifest': member_name,
                                      'manifest_sha256': digest(member_file), 'member_count': len(records)})
            print(f'{name}: {len(records)} members, {target.stat().st_size} bytes', flush=True)
    (OUT / 'index.json').write_bytes((json.dumps(index, ensure_ascii=False, indent=2) + '\n').encode('utf8'))
    print(f'Packed {index["source_files"]} original files without removing any source.', flush=True)


if __name__ == '__main__': main()
