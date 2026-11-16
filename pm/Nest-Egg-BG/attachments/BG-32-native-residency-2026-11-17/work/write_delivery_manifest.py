from pathlib import Path
import hashlib
import json

root = Path('C:/Users/stanl/Github/Nest-Egg')
work = root / 'work/bg32-audit-20261117'
packet = root / 'pm/Nest-Egg-BG/attachments/BG-32-native-residency-2026-11-17'

def row(path):
    with path.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return {'path': path.relative_to(packet).as_posix(), 'bytes': path.stat().st_size, 'sha256': digest}

manifest = [row(p) for p in sorted(packet.rglob('*')) if p.is_file()
            and p.name not in ['manifest.json', 'verify-console.log', 'verification.json']]
(packet / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
candidate = json.loads((work / 'official-source-before.json').read_text(encoding='utf-8'))['source_files']
paths = ['design/11-free-assets/DESIGN.md', 'pm/Nest-Egg-BG/[BG-32]釋放用不到的過場舞台與背景貼圖.md',
         *candidate,
         *[p.relative_to(root).as_posix() for p in sorted(packet.rglob('*')) if p.is_file()],
         *['pm/Nest-Egg-BG/images/' + name for name in ['BG-32-9070xt-street-before.png', 'BG-32-9070xt-street-after.png', 'BG-32-9070xt-main-cinematic.png', 'BG-32-9070xt-main-dialogue.png']]]
delivery = {'files': sorted(set(paths)),
            'candidate_sources': {rel: {'source': str(work / 'frozen-candidate' / rel), **meta} for rel, meta in candidate.items()},
            'note': 'Parent copies frozen core/map/helper into root; root probe already matches. No stage/commit/push performed by child; preserve all unrelated dirty/untracked files.'}
(work / 'delivery-files.json').write_text(json.dumps(delivery, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'packet files {len(manifest)}, delivery paths {len(delivery["files"])}')
