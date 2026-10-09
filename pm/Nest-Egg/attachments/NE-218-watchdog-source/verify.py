from pathlib import Path
import hashlib, json, os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / 'art_src/creatures/watchdog/design_21801'


def verify():
    expected = json.loads((SOURCE / 'rebuild.json').read_text())
    before = (SOURCE / 'design_rgba.png').read_bytes()
    subprocess.run([sys.executable, str(SOURCE / 'rebuild.py')], check=True, capture_output=True)
    assert (SOURCE / 'design_rgba.png').read_bytes() == before, 'replay changed accepted source'
    assert hashlib.sha256(before).hexdigest() == expected['output_sha256']
    pixels = np.array(Image.open(SOURCE / 'design_rgba.png').convert('RGBA'))
    rows = []
    for face in (1, -1):
        oriented = pixels if face == 1 else pixels[:, ::-1]
        alpha = oriented[:, :, 3:4].astype(float) / 255
        for name, background in [('black', 0), ('gray', 128), ('white', 255)]:
            capture = ROOT / f'pm/Nest-Egg/images/NE-218-watchdog-source/{name}_face{face}.png'
            actual = np.array(Image.open(capture).convert('RGBA'))
            assert actual.shape == (1024, 1536, 4) and (actual[:, :, 3] == 255).all(), capture
            composite = np.rint(oriented[:, :, :3] * alpha + background * (1 - alpha))
            delta = abs(actual[:, :, :3].astype(float) - composite)
            assert delta.max() <= 1, (capture, delta.max())
            rows.append({'image': capture.name, 'max_channel_error': int(delta.max()),
                         'sha256': hashlib.sha256(capture.read_bytes()).hexdigest()})
    # Pin failure must precede writes, even for a one-byte corrupt source.
    with tempfile.TemporaryDirectory(prefix='ne218-source-negative-') as directory:
        private = Path(directory)
        shutil.copyfile(SOURCE / 'rebuild.py', private / 'rebuild.py')
        (private / '_gen').mkdir()
        raw = bytearray((SOURCE / '_gen/watchdog_design_21801_0.png').read_bytes())
        raw[-1] ^= 1
        (private / '_gen/watchdog_design_21801_0.png').write_bytes(raw)
        sentinel = b'untouched existing result'
        (private / 'design_rgba.png').write_bytes(sentinel)
        # Keep the copied script's project helper import valid without changing its guard.
        environment = os.environ.copy()
        environment['PYTHONPATH'] = str(ROOT / 'tools/comfyui')
        result = subprocess.run([sys.executable, str(private / 'rebuild.py')], env=environment, capture_output=True)
        assert result.returncode != 0 and b'AssertionError' in result.stderr, result.stderr
        assert (private / 'design_rgba.png').read_bytes() == sentinel
    report = {'scope': 'static source and six native source previews only',
              'deterministic_replay': True, 'one_byte_source_negative_control': 'rejected before overwrite',
              'native_composites': rows}
    (Path(__file__).resolve().parent / 'verify.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    verify()
