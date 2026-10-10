"""Replay actual SAM bytes through the delivery boundary; no GPU or inference."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/comfyui'))
import sam_masks

HERE = Path(__file__).resolve().parent
record = json.loads((HERE/'record.json').read_text(encoding='utf8'))
source = ROOT/'art_src/characters/rin_walk_source_ig01/sam/input-rgb.png'
assert hashlib.sha256(source.read_bytes()).hexdigest() == record['sam_input_sha256']
mask = HERE/'near_boot-rejected.png'
assert hashlib.sha256(mask.read_bytes()).hexdigest() == record['results']['near_boot']['sha256']
results = []
for role in ('pos','neg'):
    job = {kind:record['jobs']['near_boot'][kind] if kind == role else [] for kind in ('pos','neg')}
    with tempfile.TemporaryDirectory(prefix='sam-recorded-rejection-') as directory:
        work = Path(directory)
        out = work/'published'
        out.mkdir()
        existing = out/'near_boot.png'
        existing.write_bytes(b'previous-reviewed-mask')
        def run(graph, name):
            path = work/(name+'_0.png')
            path.write_bytes(mask.read_bytes())
            return [path]
        error = None
        with patch.object(sam_masks, 'run', run), patch.object(sam_masks, 'upload', return_value='recorded-source'), patch.object(sam_masks.comfy_guard, 'ensure_server'):
            try:
                sam_masks.segment_points(str(source), str(out), {'near_boot':job})
            except ValueError as failure:
                error = str(failure)
        assert error is not None, f'{role} failed to reject the recorded bad mask'
        assert existing.read_bytes() == b'previous-reviewed-mask'
        results.append({'role':role,'rejected':True,'existing_mask_unchanged':True,'error':error})
print(json.dumps({'status':'RECORDED_MASK_DELIVERY_REJECTED_NOT_ANATOMY_ACCEPTANCE',
                  'source_sha256':record['sam_input_sha256'],
                  'mask_sha256':record['results']['near_boot']['sha256'],
                  'gpu_or_new_model_inference':False,'cases':results},indent=2))
