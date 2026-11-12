"""Verify closed original-source/leaf packet without engine or extraction."""
import argparse, hashlib, json, pathlib, zipfile

def verify(folder):
    folder=pathlib.Path(folder);index=json.loads((folder/'packet-index.json').read_text(encoding='utf8'))
    archive=folder/'source-audio-clock-packet.zip'
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==index['archive_sha256'],'archive SHA mismatch'
    with zipfile.ZipFile(archive) as z:
        assert len(z.namelist())==len(set(z.namelist()))==len(index['members']),'duplicate/missing members'
        for name,row in index['members'].items():
            data=z.read(name)
            assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
    return {'members':len(index['members']),'bytes':archive.stat().st_size,'sha256':index['archive_sha256'],'engine_started':False}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('folder',nargs='?',default=str(pathlib.Path(__file__).resolve().parent));args=ap.parse_args()
    print(json.dumps(verify(args.folder),indent=2))
