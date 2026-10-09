from pathlib import Path
import hashlib, json, shutil, sys
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
WORK = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools/comfyui'))
from creature_art import clean_alpha


def rebuild():
    raw = WORK / '_gen/watchdog_design_21801_0.png'
    assert hashlib.sha256(raw.read_bytes()).hexdigest() == '8b7561a01f928772ce9543907625f6e2648fc0b037cf29cccb40092e69d30fbe', raw
    source = np.array(Image.open(raw))
    assert source.shape == (1024, 1536, 4)
    target = WORK / 'design_rgba.png'
    shutil.copyfile(raw, target)
    cleared = clean_alpha(target)
    pixels = np.array(Image.open(target))
    # Opaque metal interiors must not inherit the model's translucent alpha.
    core = cv2.erode((pixels[:, :, 3] >= 127).astype('uint8'), np.ones((11, 11), dtype='uint8')) > 0
    solidified = int((core & (pixels[:, :, 3] != 255)).sum())
    pixels[:, :, 3][core] = 255
    kept = source[:, :, 3] > 8
    assert np.array_equal(pixels[:, :, :3][kept], source[:, :, :3][kept]), 'foreground RGB changed'
    assert (pixels[:, :, 3][core] == 255).all()
    assert not pixels[~kept].any(), 'faint backdrop remains'
    assert not ((pixels[:, :, 0] > 110) & (pixels[:, :, 2] > 110) & (pixels[:, :, 1] < 90) & (pixels[:, :, 3] > 0)).any(), 'magenta haze remains'
    Image.fromarray(pixels).save(target)
    report = {'status': 'STATIC DESIGN SOURCE ONLY; NOT RIG OR ANIMATION ACCEPTANCE',
              'source_sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
              'output_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'canvas': [1536, 1024], 'alpha_background_floor': 8,
              'background_pixels_cleared': cleared, 'interior_alpha_pixels_solidified': solidified,
              'interior_mask': '11x11 square erosion of alpha>=127; RGB and outer antialias unchanged',
              'foreground_rgb_changed': 0}
    (WORK / 'rebuild.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    return report


if __name__ == '__main__':
    first = rebuild()
    assert rebuild() == first, 'rebuild is not deterministic'
    print(json.dumps(first))
