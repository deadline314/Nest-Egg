"""Build this worker's limb normals from continuous source limbs, preserving each diffuse/alpha."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import cv2
import numpy as np
from PIL import Image

WORK = Path(__file__).resolve().parent
ROOT = WORK.parents[2]
sys.path.insert(0, str(ROOT / 'tools/comfyui'))
from cut_layers import part_transform, render_part, make_normal_map

spec_path = ROOT / 'tools/comfyui/specs/harbor_lamplighter_demo_side.json'
spec = json.loads(spec_path.read_text(encoding='utf8'))
k = spec['tex_px_per_wp'] / spec['illustration_px_per_wp']
joints = {name: np.asarray(point, float) * k for name, point in spec['joints'].items()}
parts_dir = ROOT / 'art/characters/harbor_lamplighter_demo/parts'
targets = {parts_dir / f'{name}_n.png' for name in ('leg_upper', 'leg_lower', 'foot')}
protected = [parts_dir.parent / 'character.json', ROOT / 'art/rigs/harbor_lamplighter_demo.json',
             ROOT / 'art/motion/harbor_lamplighter_demo.json'] + [path for path in parts_dir.iterdir() if path.is_file() and path not in targets]
unchanged = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
records = {}
for chain in [('leg_upper', 'leg_lower', 'foot')]:
    layers = [np.asarray(Image.open(WORK / '07_refined' / f'{name}.png').convert('RGBA')) for name in chain]
    stack = np.stack(layers)
    owners = np.argmax(stack[:, :, :, 3], axis=0)
    y, x = np.mgrid[:layers[0].shape[0], :layers[0].shape[1]]
    union = Image.fromarray(stack[owners, y, x])
    for name, layer in zip(chain, layers):
        diffuse_path = parts_dir / f'{name}.png'
        diffuse_sha256 = hashlib.sha256(diffuse_path.read_bytes()).hexdigest()
        diffuse = np.asarray(Image.open(diffuse_path).convert('RGBA'))
        transform = part_transform(Image.fromarray(layer), spec['parts'][name], joints, k)
        assert transform is not None
        assert np.array_equal(render_part(Image.fromarray(layer), transform, k), diffuse)
        affine, width, height, pivot = transform
        padding = 5
        expanded = affine.copy()
        expanded[:, 2] = affine[:, 2] - affine[:, :2] @ np.array([padding, padding])
        height_field = render_part(union, (expanded, width + padding * 2, height + padding * 2, pivot + padding), k)
        normal = make_normal_map(height_field)[padding:padding + height, padding:padding + width].copy()
        normal[:, :, 3] = diffuse[:, :, 3]
        assert normal.shape == diffuse.shape
        assert np.array_equal(normal[:, :, 3], diffuse[:, :, 3])
        target = parts_dir / f'{name}_n.png'
        previous = WORK / 'evidence/normal-before' / target.name
        previous.parent.mkdir(parents=True, exist_ok=True)
        if not previous.exists(): shutil.copy2(target, previous)
        Image.fromarray(normal).save(target)
        assert hashlib.sha256(diffuse_path.read_bytes()).hexdigest() == diffuse_sha256
        records[name] = {'diffuse_sha256': hashlib.sha256(diffuse_path.read_bytes()).hexdigest(),
                         'normal_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                         'source_parts': list(chain), 'padding': padding, 'alpha_unchanged': True,
                         'diffuse_matches_official_cut': True, 'dimensions': [width, height]}
assert all(hashlib.sha256(path.read_bytes()).hexdigest() == digest for path, digest in unchanged.items())
(WORK / 'evidence/continuous-normal-receipt.json').write_text(json.dumps(records, indent=2), encoding='utf8')
print(json.dumps(records))
