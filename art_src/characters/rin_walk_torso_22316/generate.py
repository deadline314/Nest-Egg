"""One masked source experiment, not a production asset or anatomy acceptance."""
import hashlib
import json
import os
import runpy
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
os.environ['OUT_DIR'] = str(HERE / 'source')
sys.path.insert(0, str(ROOT / 'tools/comfyui'))
import comfy_api as api

REF = ROOT / 'art/characters/rin/parts/torso.png'
REF_SHA = '9cb49daa7a166a2f7ed31e44f3995c8e5192446294f5c41d0aa67a40263e3d4f'
BASE = ROOT / 'art_src/characters/rin2/base_rgba.png'
BASE_SHA = '401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9'
SEED = 22316

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_inputs():
    assert sha(REF) == REF_SHA, 'Protected formal torso changed'
    assert sha(BASE) == BASE_SHA, 'Protected approved s33 changed'
    assert Path(os.environ['COMFYUI_DIR'], 'main.py').is_file()

verify_inputs()
HERE.mkdir(exist_ok=True)
(HERE / '.gdignore').touch()
refs = HERE / 'references'
refs.mkdir(exist_ok=True)
guide_data = runpy.run_path(str(HERE / 'references/build_silhouette_guide.py'))
mask = Image.new('L', (864, 1408), 0)
points = [(round(x * 4) + 32, round(y * 4) + 32) for x, y in guide_data['points']]
ImageDraw.Draw(mask).polygon(points, fill=255)
target = Image.new('RGBA', mask.size, (0, 0, 0, 0))
fill = Image.new('RGBA', mask.size, (222, 222, 222, 255))
target.paste(fill, (0, 0), mask)
target_path = refs / 'neutral-torso-target.png'
mask_path = refs / 'torso-edit-mask.png'
target.save(target_path)
mask.save(mask_path)
assert set(np.unique(np.asarray(mask))) == {0, 255}
assert np.array_equal(np.asarray(target)[:, :, 3], np.asarray(mask))
assert np.any(np.asarray(mask) == 255) and np.any(np.asarray(mask) == 0)

prompt = (
    'Paint the isolated side-view adult female torso in image1. The masked silhouette is the '
    'fixed neutral walking shape: relaxed ribcage, natural gently curved back, no arched '
    'lower back, no chest-thrust pose. Image2 is only the costume and linework reference. '
    'Same white fitted cyberpunk bodysuit, narrow cyan collar and armhole trim, black side '
    'panel, warm skin at a small shoulder attachment, understated two-tone cel shadows '
    'and clean deliberate dark ink contours. One consistent upper-left light. '
    'One torso attachment only, short high collar through waist with brief lower overlap; '
    'no head, hair, earrings, arms, hands, legs, hip, buttocks, extra breasts or detached '
    'parts. Finish all material inside the silhouette, do not draw a grey guide. '
    'No bloom, ornate decoration, glossy gradients or realistic rendering. Transparent '
    'background. Remove the background, and output a PNG image.'
)
record = {
    'status': 'EXPERIMENT_REQUEST_NOT_ADOPTED', 'seed': SEED, 'prompt': prompt,
    'target': {'path': str(target_path.relative_to(ROOT)), 'sha256': sha(target_path)},
    'mask': {'path': str(mask_path.relative_to(ROOT)), 'sha256': sha(mask_path),
             'white_means': 'edit', 'origin': 'proposed construction silhouette, not a generated-alpha or anatomy proof'},
    'costume_reference': {'path': str(REF.relative_to(ROOT)), 'sha256': REF_SHA},
    'requested_canvas': [864, 1408], 'resolution': 0, 'steps': 25, 'cfg': 1.0,
    'scope': 'private masked Qwen sampling and final-composite compatibility experiment; formal source and rig unchanged',
}
(HERE / 'candidate.json').write_text(json.dumps(record, indent=2) + '\n')
if '--prepare-only' in sys.argv:
    print(json.dumps(record), flush=True)
    raise SystemExit(0)

inspect_only = '--inspect-only' in sys.argv or all(
    (HERE / 'source' / f'rin_ne222_walk_torso_22316_{node}_0.png').is_file() for node in ('RAW','FINAL'))
if inspect_only:
    previous = json.loads((HERE / 'request.graph.json').read_text())
    names = [previous[node]['inputs']['image'] for node in ('T', 'R', 'M')]
else:
    with api.comfy_guard.server_lock():
        api.comfy_guard.ensure_server()
        names = [api.upload(p) for p in (target_path, REF, mask_path)]
g = {
    '1': {'class_type': 'UNETLoader', 'inputs': {'unet_name': api.QWEN_UNET, 'weight_dtype': 'default'}},
    '1c': {'class_type': 'QwenImage21Cache', 'inputs': {'model': ['1', 0], 'device': 'off', 'dtype': 'default'}},
    '2': {'class_type': 'CLIPLoader', 'inputs': {'clip_name': api.QWEN_CLIP, 'type': 'qwen_image', 'device': 'default'}},
    '3': {'class_type': 'VAELoader', 'inputs': {'vae_name': api.QWEN_VAE}},
    'T': {'class_type': 'LoadImage', 'inputs': {'image': names[0]}},
    'TA': {'class_type': 'JoinImageWithAlpha', 'inputs': {'image': ['T', 0], 'alpha': ['T', 1]}},
    'R': {'class_type': 'LoadImage', 'inputs': {'image': names[1]}},
    'RA': {'class_type': 'JoinImageWithAlpha', 'inputs': {'image': ['R', 0], 'alpha': ['R', 1]}},
    'M': {'class_type': 'LoadImageMask', 'inputs': {'image': names[2], 'channel': 'red'}},
    '4': {'class_type': 'TextEncodeQwenImage21', 'inputs': {'clip': ['2', 0], 'prompt': prompt,
          'negative_prompt': '', 'vae': ['3', 0], 'resolution': 0, 'images.image_1': ['TA', 0], 'images.image_2': ['RA', 0]}},
    '5': {'class_type': 'VAEEncodeForInpaint', 'inputs': {'pixels': ['TA', 0], 'vae': ['3', 0], 'mask': ['M', 0], 'grow_mask_by': 0}},
    '6': {'class_type': 'KSampler', 'inputs': {'model': ['1c', 0], 'positive': ['4', 0], 'negative': ['4', 1],
          'latent_image': ['5', 0], 'seed': SEED, 'steps': 25, 'cfg': 1.0, 'sampler_name': 'euler', 'scheduler': 'simple', 'denoise': 1.0}},
    '7': {'class_type': 'VAEDecode', 'inputs': {'samples': ['6', 0], 'vae': ['3', 0]}},
    'C': {'class_type': 'ImageCompositeMasked', 'inputs': {'destination': ['TA', 0], 'source': ['7', 0],
          'x': 0, 'y': 0, 'resize_source': False, 'mask': ['M', 0]}},
    'RAW': {'class_type': 'SaveImage', 'inputs': {'images': ['7', 0], 'filename_prefix': 'rin_walk_22316_raw'}},
    'FINAL': {'class_type': 'SaveImage', 'inputs': {'images': ['C', 0], 'filename_prefix': 'rin_walk_22316_composite'}},
}
(HERE / 'request.graph.json').write_text(json.dumps(g, indent=2) + '\n')
prefix = 'rin_ne222_walk_torso_22316'
paths = sorted((HERE / 'source').glob(prefix + '_*_0.png')) if inspect_only else api.run(g, prefix)
results = {}
for node in ('RAW', 'FINAL'):
    p = next(p for p in paths if p.name == f'{prefix}_{node}_0.png')
    with Image.open(p) as im:
        assert im.size == target.size and im.mode == 'RGBA', (node, im.size, im.mode)
        pixels = np.asarray(im)
        results[node] = {'path': str(p.relative_to(HERE)), 'sha256': sha(p), 'size': list(im.size),
                         'alpha_extrema': list(im.getchannel('A').getextrema())}
        if node == 'FINAL':
            outside = np.asarray(mask) == 0
            changed = np.any(pixels != np.asarray(target), axis=2) & outside
            results[node]['outside_mask_changed_rgba_pixels'] = int(changed.sum())
            assert not changed.any(), 'Final composite altered protected outside-mask RGBA'
        actual_graph = json.loads(im.info['prompt'])
        clean_graph = {key: {field: value for field, value in node.items() if field != 'is_changed'}
                       for key, node in actual_graph.items()}
        assert clean_graph == g, 'Saved graph differs from submitted experiment'
        for key, digest in [('T', sha(target_path)), ('R', REF_SHA), ('M', sha(mask_path))]:
            assert actual_graph[key].get('is_changed') == [digest], 'Executed input hash differs: ' + key
        (HERE / 'executed.graph.json').write_text(json.dumps(actual_graph, indent=2) + '\n')
verify_inputs()
record.update(status='SOURCE_CANDIDATE_NOT_ADOPTED', results=results)
(HERE / 'candidate.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record), flush=True)
