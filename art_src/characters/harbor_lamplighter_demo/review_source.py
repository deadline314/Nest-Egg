"""Record the unmodified native source and make inspection composites (no source edits)."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

WORK = Path(__file__).resolve().parent
source = WORK / 'base_rgba.png'
image = Image.open(source)
assert image.mode == 'RGBA'
alpha = np.asarray(image)[:, :, 3]
assert alpha.max() >= 250 and np.any(alpha == 0)
record = {'source': str(source), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'dimensions': list(image.size), 'mode': image.mode,
          'alpha_histogram': np.bincount(alpha.ravel(), minlength=256).tolist(),
          'opaque_bbox': image.getchannel('A').point(lambda value: 255 if value >= 250 else 0).getbbox()}
review = WORK / 'evidence'
review.mkdir(exist_ok=True)
(review / 'source-alpha.json').write_text(json.dumps(record, indent=2), encoding='utf8')
for name, value in [('black', 0), ('grey', 128), ('white', 255)]:
    background = Image.new('RGBA', image.size, (value, value, value, 255))
    background.alpha_composite(image)
    background.convert('RGB').save(review / f'source-{name}.png')
print(json.dumps({key: value for key, value in record.items() if key != 'alpha_histogram'}))
