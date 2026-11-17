"""Verify raw archives without extracting them. Python 3.10+, standard library only."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import math
import statistics
import sys
import zipfile


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(block)
    return value.hexdigest()


class Packet:
    def __init__(self, root):
        self.root = root
        self.index = json.loads((root / 'archives.json').read_text(encoding='utf8'))
        self.members = {}

    def verify(self):
        for archive in self.index['archives']:
            path = self.root / archive['file']
            require(path.parent.resolve() == self.root.resolve(), 'archive outside packet')
            with path.open('rb') as source:
                require(path.stat().st_size == archive['bytes'] < 50_000_000 and digest(source) == archive['sha256'], 'archive bytes: ' + path.name)
            expected = {row['path']: row for row in archive['members']}
            require(len(expected) == len(archive['members']), 'duplicate manifest member')
            with zipfile.ZipFile(path) as source:
                require(len(source.infolist()) == len(expected), 'archive member count')
                for member in source.infolist():
                    name = PurePosixPath(member.filename)
                    require(not name.is_absolute() and '..' not in name.parts and '\\' not in member.filename and ':' not in member.filename, 'unsafe member')
                    require(not any(p.lower() in ['private-profile', 'user-data', 'user', 'app_userdata'] for p in name.parts), 'runtime profile included')
                    key = member.filename.casefold()
                    require(key not in self.members and member.filename in expected, 'duplicate or unexpected member')
                    row = expected[member.filename]
                    with source.open(member) as stream:
                        require(member.file_size == row['bytes'] and digest(stream) == row['sha256'], 'member bytes: ' + member.filename)
                    self.members[key] = (archive['file'], member.filename)
            print(path.name, len(expected), 'verified', flush=True)
        require(len(self.members) == self.index['file_count'], 'total member count')
        return len(self.members)

    def read(self, name):
        archive, member = self.members[name.casefold()]
        with zipfile.ZipFile(self.root / archive) as source:
            return source.read(member)

    def json(self, name):
        return json.loads(self.read(name))


def acceptance(packet):
    base = 'evidence/candidates/v11-ground-plane/'
    read = lambda name: packet.json(base + name)
    affected = read('affected-main/result.json')
    require(affected['exit'] == 0 and affected['source_unchanged'] and affected['source_count'] == 14589, 'original affected suite')
    log = packet.read(base + 'affected-main/runner.log')
    require(b'Running 58 groups in 1 processes' in log and b'checks: 65303, new failures: 0, known failures' in log, 'actual original suite terminal counts')
    require(b'SCRIPT ERROR:' not in packet.read(base + 'affected-main/shards/shard_0.log'), 'actual original shard has no script errors')
    require(read('affected-main/source-before.json') == read('affected-main/source-after.json'), 'affected source guard')
    defaults = read('cpu-final/defaults.json')['cases']
    require(len(defaults) == 96 and all(r['exact'] and r['candidate_signature'] == r['original_signature'] for r in defaults), '96 legacy motion signatures')
    flight = read('cpu-final/flight.json')
    require(flight['failures'] == 0 and len(flight['records']) == 2 and all(r['exact_bone_signature'] and r['candidate_flight_frames'] == r['original_flight_frames'] == 44 for r in flight['records']), 'full flight retained')
    helper = read('helper/results.json')
    require(helper['candidate_restored'] and helper['helper_held'] and [r['exit'] for r in helper['cases']] == [1, 0], 'actual red/green helper controls')
    for name in ['native', 'alpha']:
        row = read(name + '/result.json')
        require(row['exit'] == 0 and row['source_held'] and row['script_errors'] == 0, name + ' native receipt')
        require(read(name + '/source-before.json') == read(name + '/source-after.json'), name + ' source guard')
    alpha = read('alpha/analysis.json')
    require(len(alpha['records']) == 240 and all(r['full_below'] == 0 for r in alpha['records']), '240 full-pixel ground contacts')
    for directory, samples, failures in [('joint-matrix', 53760, 362), ('npc-joint-matrix', 33600, 40)]:
        runs = read(directory + '/runs.json')
        require(len(runs) == 2 and all(r['exit'] == 0 and r['unchanged'] and r['checker_exit'] == 1 for r in runs), directory + ' raw failing checker retained')
        for mode in ['pair', 'as-worn']:
            report = read(directory + '/' + mode + '/report.json')
            require(report['samples'] == samples and report['failed_samples'] == len(report['failures']) == failures, directory + ' raw counts')
            require(all(r['enclosed_pixels'] == r['loose_pieces'] == 0 and r['center_alpha'] == 255 for r in report['failures']), directory + ' edge-only diagnostics')
    for row in read('fullcolor/runs.json'):
        require(row['exit'] == 0 and row['unchanged'] and row['source_before'] == row['source_after'], 'full-color source guard')
    require(read('cpu-cost-and-audit/audits.json')['source_held'], 'AnimAudit source guard')
    require(read('cpu-cost-and-audit/c11-audit.json')['failures'] == [], 'original AnimAudit')
    performance = read('performance-native-v5/runs.json')
    require(len(performance) == 8 and read('performance-native-v5/source-held.json')['source_held'], 'eight native ABBA runs')
    ratios = {}
    for quality in ['low', 'high']:
        means = {'baseline': [], 'c11': []}
        for row in performance:
            if row['quality'] != quality:
                continue
            require(row['exit'] == row['script_errors'] == 0, 'native performance exit')
            frame = read(f"performance-native-v5/{quality}-{row['order']}-{row['epoch']}/frames.json")
            require('9070' in frame['adapter'] and frame['renderer'] == 'forward_plus' and frame['hdr_2d'], 'actual hardware renderer')
            require(len(frame['records']) == 4, 'four native cases')
            for case in frame['records']:
                require(case['all_rigs_within_view'] == 10 and case['world_environment_active'], 'ten rigs and world environment')
                values = case['wall_ms']
                require(len(values) == case['frames'] and all(math.isfinite(v) and v > 0 for v in values), 'raw positive full-frame samples')
                means[row['epoch']].append(statistics.mean(values))
        ratios[quality] = statistics.mean(means['c11']) / statistics.mean(means['baseline'])
    return {'legacy_cases': 96, 'combat_raw_failures_each': 362, 'npc_raw_failures_each': 40, 'ground_masks': 240, 'native_frame_ratios': ratios, 'scope': 'Diagnostic edges remain raw failures; numerical ratios include recorded other-project load. Whole-ticket character acceptance is separate.'}


if __name__ == '__main__':
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
    packet = Packet(root)
    count = packet.verify()
    delivery = json.loads((root / 'delivery-source.json').read_text())
    require(len(delivery) == 28, 'canonical delivery count')
    tested = packet.json('evidence/candidates/v11-ground-plane/affected-main/source-before.json')
    for row in delivery:
        raw = packet.read('tested-source/' + row['path'])
        canonical = (root / 'canonical-source' / row['path']).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == row['tested_sha256'], 'tested delivery source')
        require(hashlib.sha256(canonical).hexdigest() == row['canonical_sha256'], 'canonical delivery source')
        require(raw == canonical or raw.replace(b'\r\n', b'\n') == canonical, 'only explicit line-ending mapping')
        if not row['path'].startswith('design/'):
            require(tested[row['path']] == row['tested_sha256'], 'delivery differs from original affected run')
        if len(sys.argv) > 2:
            require(hashlib.sha256((Path(sys.argv[2]) / row['path']).read_bytes()).hexdigest() == row['canonical_sha256'], 'workspace delivery source')
    print(json.dumps({'verified_members': count, 'failures': 0, 'acceptance': acceptance(packet)}, indent=2))
