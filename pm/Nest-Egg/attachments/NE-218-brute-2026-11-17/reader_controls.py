from pathlib import Path
import hashlib
import io
import json
import sys
from contextlib import redirect_stdout
import zipfile
from ne218_packet_reader import Packet

out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd() / 'reader-controls'
out.mkdir(exist_ok=False)
payload = b'actual raw source\n'
cases = []
for label in ['valid', 'archive-hash', 'archive-size', 'member-hash', 'member-size', 'missing-member', 'duplicate-member', 'traversal', 'absolute', 'backslash', 'drive', 'profile', 'case-collision']:
    folder = out / label
    folder.mkdir()
    name = {'traversal': '../outside', 'absolute': '/outside', 'backslash': 'a\\b', 'drive': 'C:/outside', 'profile': 'a/app_userdata/settings.cfg'}.get(label, 'evidence/raw.log')
    archive = folder / 'raw-001.zip'
    entries = [name]
    if label == 'duplicate-member': entries.append(name)
    if label == 'case-collision': entries.append(name.upper())
    with zipfile.ZipFile(archive, 'w') as writer:
        for entry in entries:
            writer.writestr(entry, payload)
    rows = [{'path': entry, 'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()} for entry in entries]
    record = {'file': archive.name, 'bytes': archive.stat().st_size, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'members': rows}
    index = {'archives': [record], 'file_count': len(rows)}
    if label == 'archive-hash': record['sha256'] = '0' * 64
    if label == 'archive-size': record['bytes'] += 1
    if label == 'member-hash': rows[0]['sha256'] = '0' * 64
    if label == 'member-size': rows[0]['bytes'] += 1
    if label == 'missing-member': rows.append({'path': 'missing', 'bytes': 0, 'sha256': hashlib.sha256(b'').hexdigest()})
    (folder / 'archives.json').write_text(json.dumps(index) + '\n')
    rejected = False
    try:
        with redirect_stdout(io.StringIO()):
            packet = Packet(folder)
            packet.verify()
            assert packet.read(name) == payload
    except ValueError as error:
        rejected = True
        message = str(error)
    assert rejected == (label != 'valid'), label
    cases.append({'name': label, 'rejected': rejected, 'message': message if rejected else 'actual member readback exact'})
(out / 'results.json').write_text(json.dumps({'checks': len(cases), 'failures': 0, 'cases': cases}, indent=2) + '\n')
print('READER_CONTROLS', len(cases), 0)
