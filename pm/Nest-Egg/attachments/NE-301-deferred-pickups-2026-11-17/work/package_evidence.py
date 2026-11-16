from pathlib import Path
import hashlib
import json
import shutil

REPO = Path('C:/Users/stanl/Github/Nest-Egg')
WORK = REPO / 'work/ne301-deferred-pickup-20261117'
RAW = Path('D:/NestEggVerification/evidence-20261117/ne301')
PACKET = REPO / 'pm/Nest-Egg/attachments/NE-301-deferred-pickups-2026-11-17'

def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)

def main():
    PACKET.mkdir(parents=True, exist_ok=True)
    (PACKET / '.gdignore').write_bytes(b'')
    (PACKET / '.gitattributes').write_bytes(b'* -text\n')
    outputs = []
    for source in sorted(RAW.rglob('*')):
        if not source.is_file(): continue
        rel = source.relative_to(RAW)
        if any(part == 'profile' or part.endswith('-profile') or part.startswith('data_') for part in rel.parts): continue
        copy(source, PACKET / 'raw' / rel)
        outputs.append({'path': rel.as_posix(), 'bytes': source.stat().st_size,
                        'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
    (PACKET / 'original-outputs.json').write_text(json.dumps(outputs, indent=2) + '\n', encoding='utf-8')
    for source in WORK.iterdir():
        if source.is_file() and source.name != 'delivery-files.json':
            copy(source, PACKET / 'work' / source.name)
    for source in (WORK / 'frozen-candidate').rglob('*'):
        if source.is_file(): copy(source, PACKET / 'frozen-candidate' / source.relative_to(WORK / 'frozen-candidate'))
    # Earliest actual production-method failures retain the VFX/FSM fixture limit.
    initial = Path('D:/NestEggVerification/evidence-20261117/bg32/drop-owner-original-controls')
    for source in initial.iterdir():
        if source.is_file(): copy(source, PACKET / 'initial-bg32-drop-controls' / source.name)
    for name in ['NE-301-enemy-drops.png', 'NE-301-box-drop.png', 'NE-301-collected.png']:
        copy(RAW / 'native-fourth' / name, REPO / 'pm/Nest-Egg/images' / name)
    print(json.dumps({'packet': str(PACKET), 'raw_files': len(outputs),
                      'MiB': sum(p.stat().st_size for p in PACKET.rglob('*') if p.is_file()) / 1048576}, indent=2))

if __name__ == '__main__':
    main()
