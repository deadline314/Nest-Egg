"""Verify immutable candidate evidence; this is not an art acceptance gate."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def checked_image(path, size, digest):
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, path
    with Image.open(path) as image:
        assert list(image.size) == size, path
        return image.copy()

def main():
    assert sys.argv[1:] in ([], ['--self-test'])
    manifest = json.loads((HERE / 'manifest.json').read_text(encoding='utf8'))
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    for name, digest in manifest['protected_sources'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    source = checked_image(HERE / 'raw/source.png', [1037,1516], manifest['source_sha256'])
    assert source.mode == 'RGBA' and source.getchannel('A').getextrema() == (0,255)
    samples = [(0,1505),(0,1511),(0,1515)]
    assert all(source.getpixel(point) == (0,0,0,1) for point in samples)
    sam = json.loads((HERE / 'sam/result.json').read_text(encoding='utf8'))
    assert len(sam['results']) == 14 and sam['source_sha256'] == manifest['source_sha256']
    assert hashlib.sha256((HERE / 'sam/input-rgb.png').read_bytes()).hexdigest() == sam['sam_input_sha256']
    for name, item in sam['results'].items():
        mask = checked_image(HERE / 'sam' / (name+'.png'), [1037,1516], item['sha256']).convert('L')
        assert all(mask.getpixel(tuple(point)) > 127 for point in sam['jobs'][name]['pos'])
        assert all(mask.getpixel(tuple(point)) == 0 for point in sam['jobs'][name]['neg'])
    graph = json.loads((HERE / 'sam/executed.workflow.json').read_text(encoding='utf8'))
    assert sum(node['class_type'] == 'SAM3_Detect' for node in graph.values()) == 14
    assert graph['ckpt']['inputs']['ckpt_name'] == sam['checkpoint']
    keypoints = json.loads((HERE / 'keypoints-proposal.json').read_text(encoding='utf8'))
    assert keypoints['image_size'] == [1037,1516] and len(keypoints['points']) == 70
    capture = ROOT / 'pm/Nest-Egg/images/NE-222-walk-source-ig01.png'
    assert Image.open(capture).size == (1920,1600)
    failures = 0
    if '--self-test' in sys.argv:
        with tempfile.TemporaryDirectory(prefix='rin-walk-source-check-') as directory:
            changed = Path(directory) / 'changed.png'
            edited = source.copy()
            edited.putpixel((500,500),(1,2,3,255))
            edited.save(changed)
            for path, size, digest in [(changed,[1037,1516],manifest['source_sha256']),
                                       (HERE/'raw/source.png',[1037,1515],manifest['source_sha256']),
                                       (HERE/'raw/source.png',[1037,1516],'0'*64)]:
                try:
                    checked_image(path,size,digest)
                except AssertionError:
                    failures += 1
            assert failures == 3
    print(json.dumps({'status':'EVIDENCE_VERIFIED_NOT_ART_ACCEPTED','files':len(manifest['files']),
                      'sam_masks':14,'model_points':70,'negative_controls':failures,
                      'production_changes':0,'source_defects_preserved':True}))

if __name__ == '__main__':
    main()
