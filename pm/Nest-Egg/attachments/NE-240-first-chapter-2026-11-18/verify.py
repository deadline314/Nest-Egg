"""Check an extracted NE-240 first-chapter evidence packet."""
from pathlib import Path
import hashlib
import json
import math
import sys

def verify(folder):
    folder = Path(folder)
    read = lambda name: json.loads((folder/name).read_text(encoding='utf-8'))
    native = read('native/result.json')
    assert native == {'exit': 0, 'script_errors': 0, 'errors': []}, native
    raw = (folder/'native/raw.log').read_text(encoding='utf-8')
    assert 'AMD Radeon RX 9070 XT' in raw and 'failures=0' in raw
    assert 'ERROR:' not in raw and 'SCRIPT ERROR:' not in raw
    rows = read('native/frames.json')
    summary = {}
    for ident in ['ledger_lock_check', 'pump_case_reset']:
        selected = [row for row in rows if row['id'] == ident]
        phases = {row['phase'] for row in selected}
        assert {'reach', 'turn', 'release'} <= phases
        if ident == 'ledger_lock_check': assert 'recoil' in phases
        contacts = [row for row in selected if row['phase'] in ['turn', 'recoil']]
        assert len(contacts) > 8
        assert all(row['crouch'] is True and row['grip'] is True and type(row['error']) in (int, float) and math.isfinite(row['error']) and 0 <= row['error'] <= .25 for row in contacts)
        summary[ident] = {'contact_frames': len(contacts), 'worst': max(row['error'] for row in contacts)}
    images = read('viewed.json')['images']
    assert len(images) == 13
    assert all(hashlib.sha256((folder/'native'/name).read_bytes()).hexdigest() == sha for name,sha in images.items())
    continuity = read('continuity.json')
    assert continuity['original_quests_identical'] and continuity['original_scenes_identical']
    assert continuity['original_quest_count'] == continuity['current_quest_count'] == 10
    checks = read('checks/runs.json')
    assert len(checks) == 4
    assert all(row['exit'] == row['script_errors'] == 0 and not row['errors'] and row['source_held'] for row in checks)
    return {'passed': True, 'native_samples': len(rows), 'images': len(images), 'actions': summary}

if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent), ensure_ascii=False, indent=2))
