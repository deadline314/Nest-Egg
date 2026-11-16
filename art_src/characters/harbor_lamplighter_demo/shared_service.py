"""Run an existing pipeline tool against the shared service without lifecycle control."""
import runpy
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / 'tools' / 'comfyui'
sys.path.insert(0, str(TOOLS))
import comfy_guard

def refuse_lifecycle(*args, **kwargs):
    raise RuntimeError('Shared ComfyUI service lifecycle is owned by another session; no start/restart is permitted.')

comfy_guard._start = refuse_lifecycle
comfy_guard.restart_server = refuse_lifecycle
comfy_guard.MAX_RETRIES = 0
# comfy_api reads OUT_DIR at import. Eye generation sets it later in main(), so
# choose this character's existing eye cache before importing the shared client.
if len(sys.argv) > 1 and sys.argv[1] == 'make_eye_states.py':
    os.environ['OUT_DIR'] = str(Path(__file__).resolve().parent / 'eyes' / 'raw')
import comfy_api
run_once_original = comfy_api._run_once

def record_job(graph, name):
    evidence = Path(__file__).resolve().parent / 'evidence' / 'graphs'
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / f'{name}.json').write_text(json.dumps(graph, indent=2), encoding='utf8')
    return run_once_original(graph, name)

comfy_api._run_once = record_job
qwen_original = comfy_api.qwen

def shared_qwen(*args, **kwargs):
    kwargs['retries'] = 1
    return qwen_original(*args, **kwargs)

comfy_api.qwen = shared_qwen
if __name__ == '__main__':
    tool = sys.argv.pop(1)
    if Path(tool).name != tool or not (TOOLS / tool).is_file():
        raise SystemExit(f'Unknown pipeline tool: {tool}')
    runpy.run_path(str(TOOLS / tool), run_name='__main__')


