"""Check recorded source/graph/capture provenance, never character acceptance."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / 'art_src/characters/rin_walk_torso_22316'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_composite(target, mask, final):
    assert target.shape == final.shape == (1408, 864, 4)
    assert mask.shape == target.shape[:2]
    assert set(np.unique(mask)) == {0, 255}
    assert np.array_equal(target[:, :, 3], mask)
    assert np.array_equal(target[mask == 0], final[mask == 0]), 'Changed protected RGBA'


def main():
    manifest = json.loads((HERE / 'manifest.json').read_text())
    assert manifest['status'] == 'REJECTED_NOT_ADOPTED'
    for name, digest in manifest['files'].items():
        assert sha(ROOT / name) == digest, 'Evidence changed: ' + name
    record = json.loads((SOURCE / 'candidate.json').read_text())
    assert record['status'] == 'SOURCE_CANDIDATE_NOT_ADOPTED'
    graph = json.loads((SOURCE / 'request.graph.json').read_text())
    executed = json.loads((SOURCE / 'executed.graph.json').read_text())
    clean = {key: {field: value for field, value in node.items() if field != 'is_changed'}
             for key, node in executed.items()}
    assert clean == graph
    for key, entry in [('T', record['target']), ('M', record['mask']),
                       ('R', record['costume_reference'])]:
        assert sha(ROOT / entry['path']) == entry['sha256']
        assert executed[key]['is_changed'] == [entry['sha256']]
    assert graph['6']['inputs']['seed'] == record['seed'] == 22316
    assert graph['4']['inputs']['resolution'] == 0
    target = np.asarray(Image.open(ROOT / record['target']['path']))
    mask = np.asarray(Image.open(ROOT / record['mask']['path']))
    final = None
    for node, entry in record['results'].items():
        path = SOURCE / entry['path']
        assert sha(path) == entry['sha256']
        with Image.open(path) as im:
            assert im.mode == 'RGBA' and im.size == (864, 1408)
            assert json.loads(im.info['prompt']) == executed
            if node == 'FINAL':
                final = np.asarray(im)
    verify_composite(target, mask, final)
    outside = np.argwhere(mask == 0)[0]
    corrupt = final.copy()
    corrupt[tuple(outside)][3] = 1
    invalid = [lambda: verify_composite(target, mask, corrupt),
               lambda: verify_composite(target, mask[:, :-1], final),
               lambda: verify_composite(target, np.where(mask == 255, 128, 0), final)]
    for negative in invalid:
        try:
            negative()
        except AssertionError:
            continue
        raise AssertionError('Negative control accepted')
    for run, speed in [('game-speed', 70.0), ('cutscene-speed', 21.56)]:
        report = json.loads((HERE / (run + '.json')).read_text())
        assert report['status'] == 'PRIVATE_NOT_ACCEPTED' and report['rows'] == 8
        assert report['speed'] == speed and len(report['captures']) == 5
        for index, capture in enumerate(report['captures']):
            assert capture['index'] == index
            path = ROOT / 'pm/Nest-Egg/images/NE-222-neutral-torso-mask' / run / capture['file']
            with Image.open(path) as im:
                assert im.format == 'PNG' and im.size == (1600, 1000)
        log = (HERE / (run + '.log')).read_text()
        assert 'Forward+' in log and 'RTX 4070 SUPER' in log and 'SCRIPT ERROR' not in log
    assert manifest['executed_capture_sha256'] == sha(HERE / 'capture.gd')
    print(f"Evidence PASS: {len(manifest['files'])} pinned files; 3 negative controls rejected; "
          '10 native PNG; character anatomy/material/seams NOT ACCEPTED')


if __name__ == '__main__':
    main()
