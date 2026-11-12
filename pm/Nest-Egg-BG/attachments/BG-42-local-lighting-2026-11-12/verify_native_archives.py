"""Check exact external native archives; this does not accept the ticket."""
from pathlib import Path
import argparse, hashlib, json, zipfile

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def verify(directory):
    root=Path(__file__).resolve().parent
    manifest=json.loads((root/'native-originals-external.json').read_bytes())
    for archive in manifest['archives']:
        index=json.loads((root/archive['index']).read_bytes())
        path=directory/archive['archive']
        assert path.is_file(), f'External original required: {path}'
        assert path.stat().st_size==index['bytes']==archive['bytes']
        assert sha(path)==index['sha256']==archive['sha256'],path
        with zipfile.ZipFile(path) as packet:
            assert packet.testzip() is None
            assert len(packet.infolist())==len(index['members'])
            assert set(packet.namelist())==set(index['members'])
            for name, item in index['members'].items():
                data=packet.read(name)
                assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256'],name
                assert f'{packet.getinfo(name).CRC:08x}'==item['crc32'],name
    return dict(archives=len(manifest['archives']),integrity_pass=True,ticket_accepted=False)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    args=parser.parse_args();print(json.dumps(verify(args.directory)))
