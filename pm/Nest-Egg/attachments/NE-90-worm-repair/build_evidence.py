"""Index native screenshots separately from unscaled review crops."""
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image

out = Path(__file__).resolve().parent
root = out.parents[3]
folder = root / 'pm/Nest-Egg/images/NE-90-worm-repair'
old = json.loads((out / 'evidence.json').read_text(encoding='utf-8'))
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
sources = []
for source in old.get('source_files', old.get('source_runtime_png', [])):
    path = source['path']
    blob = subprocess.check_output(['git', 'hash-object', path], cwd=root, text=True).strip()
    sources.append(dict(path=path, base_git_blob=source['base_git_blob'], current_git_blob=blob,
                        unchanged=blob == source['base_git_blob']))

native, crops = [], []
for path in sorted(folder.glob('*.png')):
    with Image.open(path) as png:
        size = list(png.size)
    item = dict(path=path.relative_to(root).as_posix(), size=size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (crops if path.name.startswith('boundary-native-crops-') else native).append(item)
log = (out / 'render.log').read_text(encoding='utf-8')
assert len(sources) == 8 and all(item['unchanged'] for item in sources)
assert len(native) == 97 and all(item['size'] == [1280, 720] for item in native)
assert len(crops) == 7
assert log.count('body_inside=true') == 97 and 'body_inside=false' not in log
assert 'SCRIPT ERROR' not in log and 'ERROR:' not in log
result = dict(base=base, source_files=sources, source_unchanged=True,
              native_png=native, native_count=len(native), native_sizes_valid=True,
              review_crops=crops, crop_count=len(crops), full_head_and_body_inside=True,
              render=json.loads((out / 'command-render.json').read_text(encoding='utf-8')))
(out / 'evidence.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print('6 source/runtime PNG + 2 before PNG unchanged; 97 native originals; 7 unscaled crop sheets; complete head/body')
