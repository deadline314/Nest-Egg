"""Verify the original controlled renderer pair without changing its files."""
from pathlib import Path, PurePosixPath
import hashlib,importlib.util,json,sys,tempfile,zipfile

root=Path(__file__).resolve().parent
index=json.loads((root/'native-index.json').read_bytes())
with (root/index['file']).open('rb') as stream:
    assert hashlib.file_digest(stream,'sha256').hexdigest()==index['sha256']
sys.dont_write_bytecode=True
with tempfile.TemporaryDirectory(prefix='bg27-native-readonly-') as directory:
    folder=Path(directory)
    with zipfile.ZipFile(root/index['file']) as packet:
        assert len(packet.infolist())==len(index['entries']) and set(packet.namelist())==set(index['entries'])
        for name,row in index['entries'].items():
            path=PurePosixPath(name)
            assert not path.is_absolute() and '..' not in path.parts and '\\' not in name and ':' not in name
            data=packet.read(name)
            assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
            assert f'{packet.getinfo(name).CRC:08x}'==row['crc32']
            target=folder/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    spec=importlib.util.spec_from_file_location('bg27_native_pair',root/'replay/verify_native_pair.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    print(json.dumps(module.verify(folder),indent=2))
