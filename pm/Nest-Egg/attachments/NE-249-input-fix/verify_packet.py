from pathlib import Path
import collections, hashlib, json, re
from PIL import Image
root = Path(__file__).resolve().parents[4]
packet = root / 'pm/Nest-Egg/attachments/NE-249-input-fix'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
test = root / 'tests/suite/test_encounter.gd'
assert sha(test) == '54af8acc125876746cf9aa13a6bb19ec3b61594587b22f35ae9679d99d022be0'
for mode in ['right', 'left', 'mouse']:
    full = (packet / f'ne249-final-suite-{mode}.log').read_text(encoding='utf-8')
    direct = (packet / f'ne249-external-{mode}2.log').read_text(encoding='utf-8')
    assert 'checks: 158, failures: 0' in full and 'SCRIPT ERROR' not in full and '\nERROR:' not in full
    assert 'checks: 8, failures: 0' in direct and 'NE249_EXTERNAL_RESTORE' in direct and 'passed=true' in direct
    assert 'actual_x=59.25' in full and 'actual_x=59.25' in direct
green = (packet / 'ne249-final-main-order.log').read_text(encoding='utf-8')
red = (root / 'pm/Nest-Egg/attachments/NE-249-input-isolation/local-main-order.log').read_text(encoding='utf-8')
errors = lambda s: collections.Counter(line for line in s.splitlines() if line.startswith('ERROR:'))
assert errors(green) == errors(red) and sum(errors(green).values()) == 14
assert 'checks: 2051, failures: 0' in green and 'SCRIPT ERROR' not in green
for name in ['native.log', 'native-public-replay.log']:
    log = (packet / name).read_text(encoding='utf-8')
    assert 'checks: 8, failures: 0' in log and 'SCRIPT ERROR' not in log and '\nERROR:' not in log
for name in ['native.json', 'native-public-replay.json']:
    record = json.loads((packet / name).read_text(encoding='utf-8'))
    assert record['player_x'] == 59.25 and record['living_members'] == 2 and record['zone'] == 'active'
    assert record['gate_collision'] == [0, 0] and record['renderer'] == 'forward_plus' and record['hdr_2d']
assert Image.open(root / 'pm/Nest-Egg/images/NE-249-free-exit.png').size == (1280,720)
files = [p for p in packet.iterdir() if p.is_file() and p.name != 'manifest-sha256.json']
files += [test, root / 'pm/Nest-Egg/images/NE-249-free-exit.png']
manifest = {'base': '76180645419ae5010a222a8622352714ec53cf05', 'fixed_root_test_base': 'f2798bdc942c93b49336d09f4e4695eeaf40184a', 'status': 'local verification complete; full CI pending', 'same_process_existing_error_lines': 14, 'files': {p.relative_to(root).as_posix(): sha(p) for p in sorted(files)}}
(packet / 'manifest-sha256.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
print('NE249 packet PASS:', len(files), 'files; final candidate and actual logs verified; historical diagnostics retained')
