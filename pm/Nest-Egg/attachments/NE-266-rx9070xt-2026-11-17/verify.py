"""Read archived bytes and actual receipts without Godot or local worktrees."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'members.json').read_text(encoding='utf8'))
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1


with zipfile.ZipFile(root / 'raw.zip') as archive:
    check(set(archive.namelist()) == set(manifest), 'archive member set')
    for name, item in manifest.items():
        body = archive.read(name)
        check(len(body) == item['bytes'] and hashlib.sha256(body).hexdigest() == item['sha256'], name)

    def data(name):
        return json.loads(archive.read('raw/' + name))

    def log(name):
        return archive.read('raw/' + name).decode('utf8')

    for folder, expected in [('final-market-scenario-v4', 0), ('negative-save-conflict-v4', 1)]:
        result = data(folder + '/result.json')
        check(result['exit'] == expected and result['natural'] and result['source_unchanged'], folder + ' natural exit')
        before = data(folder + '/source-before.json')
        check(before == data(folder + '/source-after.json'), folder + ' source held')
        text = log(folder + '/native.log')
        check('SCRIPT ERROR' not in text, folder + ' scripts')
        check('MARKET escorts=3 throwers=1' in text and 'MARKET bypass escort states: ["patrol", "patrol", "patrol"]' in text, folder + ' identities/bypass')
        captures = [json.loads(line.removeprefix('MARKET_CAPTURE ')) for line in text.splitlines() if line.startswith('MARKET_CAPTURE ')]
        check([c['state'] for c in captures] == ['windup', 'strike', 'windup', 'recover'], folder + ' post-draw phases')
        check(all(c['physics_frame'] > 0 for c in captures), folder + ' real frames')
        for path, digest in before.items():
            if path.startswith('tools/') and 'source/final/' + path in manifest:
                check(hashlib.sha256(archive.read('source/final/' + path)).hexdigest() == digest, folder + ' final tool ' + path)
        if expected == 0:
            check('ERROR:' not in text and 'WARNING:' not in text, folder + ' diagnostics')
        else:
            check('[ScenarioBase] 無法儲存截圖' in text and 'NE-266-escort-windup.png' in text, 'actual PNG failure')

    mkdir = data('negative-mkdir-v4/result.json')
    check(mkdir['actual_exit'] == 2 and mkdir['natural'] and mkdir['source_before'] == mkdir['source_after'], 'actual mkdir failure')
    for path, digest in mkdir['source_before'].items():
        check(hashlib.sha256(archive.read('source/final/' + path)).hexdigest() == digest, 'mkdir final source ' + path)

    formal = data('formal-v4/result.json')
    check(formal['source_unchanged'] and all(r['exit'] == 0 for r in formal['commands']), 'original runners')
    check(data('formal-v4/source-before.json') == data('formal-v4/source-after.json'), '1963 formal sources held')
    for path, digest in data('formal-v4/source-before.json').items():
        if 'source/final/' + path in manifest:
            check(hashlib.sha256(archive.read('source/final/' + path)).hexdigest() == digest, 'formal final source ' + path)
    for name, count in [('changed', 2513), ('chapter2-enemies', 144)]:
        check(f'checks: {count}, new failures: 0, known failures' in log(f'formal-v4/{name}/runner.log'), name + ' actual count')
        for path in manifest:
            if path.startswith(f'raw/formal-v4/{name}/') and path.endswith('.log'):
                check(b'SCRIPT ERROR' not in archive.read(path), path + ' script diagnostics')

    original = data('original-market-scenario/result.json')
    check(original['exit'] == 0 and original['source_unchanged'], 'original false success retained')
    check('MARKET_CAPTURE' not in log('original-market-scenario/native.log'), 'original did not validate phases')
    for folder, expected in [('candidate-market-scenario-v1', 1), ('candidate-market-scenario-v2-context', 1), ('freeze-trace-v1', 1), ('freeze-control-v1', 0)]:
        result = data(folder + '/result.json')
        check(result['exit'] == expected and result['natural'] and result['source_unchanged'], folder + ' diagnostic history')

    for name in manifest:
        if name.startswith('raw/final-market-scenario-v4/') and name.endswith('.png'):
            body = archive.read(name)
            check(body[:8] == b'\x89PNG\r\n\x1a\n', name + ' PNG signature')
            check(int.from_bytes(body[16:20], 'big') == 1280 and int.from_bytes(body[20:24], 'big') == 720, name + ' native resolution')

print(f'NE266 portable checks: {checks}, failures: 0')
