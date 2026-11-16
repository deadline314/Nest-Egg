from pathlib import Path
import hashlib
import json
import shutil
import zipfile

REPO = Path('C:/Users/stanl/Github/Nest-Egg')
WORK = REPO / 'work/bg32-audit-20261117'
RAW = Path('C:/NE/evidence-20261117/bg32')
PACKET = REPO / 'pm/Nest-Egg-BG/attachments/BG-32-native-residency-2026-11-17'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)

def main():
    PACKET.mkdir(parents=True, exist_ok=True)
    (PACKET / '.gdignore').write_bytes(b'')
    images = []
    ledger = []
    for source in sorted(RAW.rglob('*')):
        if not source.is_file():
            continue
        rel = source.relative_to(RAW)
        if rel.parts[0] == 'official-3713' and rel.suffix not in ('.log', '.txt', '.json'):
            continue  # Per-shard temporary user profiles are not evidence outputs.
        if source.suffix.lower() == '.png':
            images.append(source)
        else:
            copy(source, PACKET / 'raw' / rel)
        ledger.append({'path': rel.as_posix(), 'bytes': source.stat().st_size,
                       'sha256': sha(source), 'kind': 'archived-image' if source.suffix.lower() == '.png' else 'raw'})

    # Keep every epoch's original PNG portable, using <45 MiB independent ZIPs.
    # Duplicate image bytes have one canonical ZIP member plus explicit aliases.
    seen = {}
    archive = None
    archive_bytes = 0
    volume = 0
    aliases = []
    try:
        for source in images:
            rel = source.relative_to(RAW).as_posix()
            digest = sha(source)
            if digest not in seen:
                if archive is None or archive_bytes + source.stat().st_size > 45 * 1024 * 1024:
                    if archive:
                        archive.close()
                    volume += 1
                    name = f'raw-images-{volume:02}.zip'
                    archive = zipfile.ZipFile(PACKET / name, 'w', zipfile.ZIP_STORED)
                    archive_bytes = 0
                archive.write(source, rel)
                archive_bytes += source.stat().st_size
                seen[digest] = {'archive': name, 'member': rel}
            aliases.append({'path': rel, 'bytes': source.stat().st_size, 'sha256': digest, **seen[digest]})
    finally:
        if archive:
            archive.close()
    (PACKET / 'raw-image-aliases.json').write_text(json.dumps(aliases, indent=2) + '\n', encoding='utf-8')
    (PACKET / 'original-outputs.json').write_text(json.dumps(ledger, indent=2) + '\n', encoding='utf-8')

    for source in sorted(WORK.iterdir()):
        if source.is_file() and source.suffix in ('.txt', '.log', '.json', '.py', '.ps1', '.sh'):
            if source.name != 'delivery-files.json':
                copy(source, PACKET / 'work' / source.name)
    for source in (WORK / 'frozen-candidate').rglob('*'):
        if source.is_file():
            copy(source, PACKET / 'frozen-candidate' / source.relative_to(WORK / 'frozen-candidate'))
    # Exact unmodified runtime support sources named in native reports.
    report = json.loads((RAW / 'isolated-E2/report.json').read_text(encoding='utf-8'))
    iso = Path('C:/NE/bg32-20261117')
    for rel, digest in report['source_shas'].items():
        if rel == 'core/asset_prefetch.gd':
            continue  # Raw E and final comment-only versions are both retained.
        assert sha(iso / rel) == digest, (rel, 'runtime support changed')
        copy(iso / rel, PACKET / 'native-support' / rel)
    copy(REPO / 'tools/viewport_capture.gd', PACKET / 'native-support/tools/viewport_capture.gd')

    public = REPO / 'pm/Nest-Egg-BG/images'
    for src, name in [
        ('isolated-A4/r1-s01-ch1_street.png', 'BG-32-9070xt-street-before.png'),
        ('isolated-E2/r1-s01-ch1_street.png', 'BG-32-9070xt-street-after.png'),
        ('main-E4/BG32-primary-cinematic.png', 'BG-32-9070xt-main-cinematic.png'),
        ('main-E4/BG32-primary-npc.png', 'BG-32-9070xt-main-dialogue.png'),
    ]:
        copy(RAW / src, public / name)
    print(json.dumps({'packet': str(PACKET), 'raw_files': len(ledger), 'png_aliases': len(aliases),
                      'unique_pngs': len(seen), 'zip_volumes': volume,
                      'MiB': sum(x.stat().st_size for x in PACKET.rglob('*') if x.is_file()) / 1048576}, indent=2))

if __name__ == '__main__':
    main()
