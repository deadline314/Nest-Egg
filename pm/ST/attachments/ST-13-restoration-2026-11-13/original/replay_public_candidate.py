"""Read-only ST13 replay from this packet and two externally retained raw ZIPs."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import time
import zipfile

PACKET = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf8'))


def exact_file(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.is_file() and path.read_bytes() == content, f'Collision: {path}'
    else:
        with path.open('xb') as handle:
            handle.write(content)


def unpack(archive, destination, index=None):
    records = {}
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None, f'CRC failure: {archive}'
        names = bundle.namelist()
        assert len(names) == len(set(names)), f'Duplicate ZIP names: {archive}'
        if index is not None:
            assert set(names) == set(index['files'])
            assert len(names) == index['member_count']
        for member in bundle.infolist():
            name = member.filename
            relative = PurePosixPath(name)
            assert not relative.is_absolute() and '..' not in relative.parts
            assert '\\' not in name and ':' not in name and not member.is_dir()
            target = destination.joinpath(*relative.parts)
            assert target.resolve().is_relative_to(destination.resolve())
            content = bundle.read(member)
            digest = hashlib.sha256(content).hexdigest()
            record = dict(bytes=len(content), sha256=digest)
            if index is not None:
                assert record == index['files'][name], f'Member mismatch: {name}'
            exact_file(target, content)
            records[name] = record
    return dict(member_count=len(records), crc_pass=True,
                all_member_sha_pass=index is not None, files=records)


def replay(raw_root, out):
    assert not out.exists(), f'Use a NEW destination, preserving every prior replay: {out}'
    out.mkdir(parents=True)
    receipt = dict(python=sys.version, executable=sys.executable,
                   packet=PACKET.as_posix(), raw_root=raw_root.as_posix(),
                   extracted_root=out.as_posix(), engines_started=False,
                   managed_checkout_required=False, archives={}, external_raw={}, runs=[])
    for name in ['completed', 'final-supplement']:
        index_name = 'completed-index-v1.json' if name == 'completed' else 'final-supplement-index-v1.json'
        index = load(PACKET / index_name)
        archive = PACKET / index['archive']
        assert archive.stat().st_size == index['bytes'] and sha(archive) == index['sha256']
        extraction = unpack(archive, out, index)
        receipt['archives'][archive.name] = dict(bytes=index['bytes'], sha256=index['sha256'],
                                                member_count=extraction['member_count'],
                                                crc_pass=True, all_member_sha_pass=True)
    # Exact originals are also exposed next to the ZIPs for review. Never patch them.
    for name in ['verify_final_delivery.py', 'verify_native_layout_final.py',
                 'verification-source-originals/index.json',
                 'verification-source-originals/verify_capture_precision.py']:
        exact_file(out / name, (PACKET / name).read_bytes())
    for name, item in load(PACKET / 'external-raw-index.json').items():
        original = raw_root / name
        assert original.stat().st_size == item['bytes'] and sha(original) == item['sha256']
        copy = out / name
        copy.parent.mkdir(parents=True, exist_ok=True)
        assert not copy.exists()
        shutil.copyfile(original, copy)
        assert sha(copy) == item['sha256']
        extraction = unpack(copy, copy.parent)
        receipt['external_raw'][name] = dict(bytes=item['bytes'], sha256=item['sha256'],
                                            member_count=extraction['member_count'], crc_pass=True)
    for count in [2, 3]:
        for page in ['early-actions', 'voluntary-card', 'natural-finish-menu']:
            assert sha(PACKET / f'images/count{count}/{page}.png') == sha(out / f'native-layout-v3-count{count}/{page}.png')
    logs = out / 'portable-replay-receipts'
    logs.mkdir()
    for label, reader, arguments in [
        ('final-delivery', 'verify_final_delivery.py', ['--require-official']),
        ('final-native', 'verify_native_layout_final.py', []),
    ]:
        command = [sys.executable, '-X', 'utf8', str(out / reader), '--raw-root', str(out), *arguments]
        started = time.perf_counter()
        process = subprocess.run(command, cwd=out, capture_output=True)
        (logs / (label + '.stdout')).write_bytes(process.stdout)
        (logs / (label + '.stderr')).write_bytes(process.stderr)
        record = dict(label=label, command=command, cwd=out.as_posix(),
                      exit_code=process.returncode, wall_seconds=time.perf_counter() - started,
                      reader_sha256=sha(out / reader),
                      stdout_sha256=sha(logs / (label + '.stdout')),
                      stderr_sha256=sha(logs / (label + '.stderr')))
        receipt['runs'].append(record)
        (logs / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf8')
        assert process.returncode == 0, f'{label} failed; original outputs retained in {logs}'
    receipt['accepted'] = True
    (logs / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-root', type=Path, required=True,
                        help='External directory containing native-layout-v3-count{2,3}/native-raw.zip')
    parser.add_argument('--out', type=Path, required=True, help='Brand new extraction/replay directory')
    options = parser.parse_args()
    replay(options.raw_root.resolve(), options.out.resolve())
