"""Read-only verification of the original evidence, without running Godot."""
from pathlib import Path
import hashlib
import json
import tarfile

ROOT = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    summary = json.loads((ROOT / 'summary.json').read_text(encoding='utf-8'))
    members = json.loads((ROOT / 'raw-members.json').read_text(encoding='utf-8'))
    archive = ROOT / 'raw.tar.xz'
    assert archive.stat().st_size == summary['archive_bytes']
    assert sha(archive.read_bytes()) == summary['archive_sha256']
    with tarfile.open(archive, 'r:xz') as tf:
        assert {m.name for m in tf.getmembers()} == set(members)
        for name, record in members.items():
            data = tf.extractfile(name).read()
            assert len(data) == record['size'] and sha(data) == record['sha256'], name
        assert sum(name.endswith('.png') for name in members) == 48
        original = tf.extractfile('hook-entry-original/shard_0.log').read().decode()
        assert 'checks: 138, failures: 1' in original
        assert original.count('FAIL: the first hook telegraph already points toward the player on its left') == 1
        wrapper = tf.extractfile('official/wrapper.log').read().decode('utf-8-sig')
        assert 'checks: 56758, new failures: 0, known failures (tests/known_failures.txt): 0' in wrapper
        before = tf.extractfile('official/source-before.json').read()
        after = tf.extractfile('official/source-after.json').read()
        assert json.loads(before) == json.loads(after) == summary['official_source_sha256']
        for phase in ['native-v3/strike_enemies', 'native-final']:
            result = json.loads(tf.extractfile(phase + '/result.json').read())
            assert result['exit_code'] == 0 and result['png_count'] == 12 and result['source_unchanged']
            log = tf.extractfile(phase + '/native.log').read().decode()
            assert 'Forward+' in log and 'Radeon RX 9070 XT' in log
            assert not any(x in log for x in ['ERROR:', 'SCRIPT ERROR:', 'Assertion failed'])
        for name in ['official/shard_0.log', 'official/shard_1.log']:
            assert 'SCRIPT ERROR:' not in tf.extractfile(name).read().decode()
    print(f'NE118: {len(members)} exact members, 48 PNG, original 138/1, official 56758/0; verified')


if __name__ == '__main__':
    main()
