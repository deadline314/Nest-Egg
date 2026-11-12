"""Recheck the existing portrait source, publication pixels and review images; no GPU."""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from PIL import Image

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=here.parents[3])
args = parser.parse_args()
receipt = json.loads((here / 'receipt.json').read_bytes())
for name, wanted in receipt['files'].items():
    assert hashlib.sha256((args.root / name).read_bytes()).hexdigest() == wanted, name
source = np.array(Image.open(args.root / 'art_src/characters/rin_inventory/design_s24302.png').convert('RGBA'))
source[source[:, :, 3] < receipt['alpha_floor']] = 0
x0, y0, x1, y1 = receipt['crop']
portrait = np.array(Image.open(args.root / 'art/portraits/rin_inventory.png').convert('RGBA'))
assert list(portrait.shape[1::-1]) == receipt['published_size']
assert np.array_equal(source[y0:y1, x0:x1], portrait), 'source crop differs from the published portrait'
margin = receipt['margin']
assert not any(np.any(edge) for edge in (portrait[:margin, :, 3], portrait[-margin:, :, 3], portrait[:, :margin, 3], portrait[:, -margin:, 3]))
print(json.dumps(dict(accepted=True, files_verified=len(receipt['files']), source_crop_pixels_equal=True, transparent_margin=margin, scope=receipt['scope']), indent=2))
