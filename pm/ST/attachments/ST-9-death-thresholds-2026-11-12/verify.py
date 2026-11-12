from pathlib import Path
import copy, hashlib, json, zipfile
from readers.verify_capture_precision import verify as verify_pixels

root=Path(__file__).resolve().parent
receipt=json.loads((root/'receipt.json').read_bytes())
archive=root/receipt['archive']['file']
assert archive.stat().st_size==receipt['archive']['bytes']
assert hashlib.sha256(archive.read_bytes()).hexdigest()==receipt['archive']['sha256']
with zipfile.ZipFile(archive) as z:
    index=json.loads(z.read('index.json'))
    assert set(z.namelist())==set(index)|{'index.json'} and len(z.namelist())==receipt['archive']['members']
    for name,row in index.items():
        data=z.read(name)
        assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
    read=lambda name:json.loads(z.read(name))
    for name,wanted in receipt['candidate'].items():
        assert hashlib.sha256(z.read('source-candidate/'+name)).hexdigest()==wanted
    for chapter in ('ch1_kasa','ch2_heron','ch3_clearwater'):
        name='data/story/'+chapter+'.json'
        old=read('source-before/'+name)
        expected=copy.deepcopy(old)
        assert [row['min_deaths'] for row in old['death_sequences']]==[1,3,5]
        expected['death_sequences'][1]['min_deaths']=2
        expected['death_sequences'][2]['min_deaths']=3
        assert read('source-candidate/'+name)==expected
    for phase,expected_exit,checks,failures in [('red-01',1,55,10),('green-01',0,55,0)]:
        run=read(phase+'/receipt.json')
        assert run['exit_code']==expected_exit and run['results']==[[str(checks),str(failures)]] and len(run['failures'])==failures and not run['diagnostics']
        assert read(phase+'/sources-before.json')==read(phase+'/sources-after.json')
    assert read('red-01/receipt.json')['errors']==read('green-01/receipt.json')['errors']
    run=read('affected-01/receipt.json')
    assert run['exit_code']==0 and run['checks']==4345 and not run['failures'] and not run['script_errors'] and not run['shutdown_diagnostics']
    assert read('affected-01/source-before.json')==read('affected-01/source-after.json')
    for phase in ('parser-01','parser-02','native-01','native-02'):
        run=read(phase+'/receipt.json')
        assert run['exit_code']==0 and run['source_unchanged'] and run['c_unchanged'] and not run['diagnostics']
        assert read(phase+'/source-before.json')==read(phase+'/source-after.json')
        assert read(phase+'/c-before.json')==read(phase+'/c-after.json')
    native=read('native-02/captures/manifest.json')
    assert native['renderer']=='forward_plus' and native['adapter']=='AMD Radeon RX 9070 XT' and native['hdr'] and native['resolution']==[1280,720]
    assert len(native['captures'])==4 and all(row['format']==14 for row in native['captures'])
    observations=native['observations']
    assert [(row['deaths'],row['selected_threshold'],row['public_confirm_sent']) for row in observations]==[(2,2,False),(3,3,True)]
    assert observations[1]['wait_after_first_capture_ms']<500
pixels=verify_pixels(archive)
assert len(pixels['native_images'])==8
print(json.dumps(dict(members_verified=len(index),accepted_native_epoch='native-02',native_pixels=pixels['native_images'],checks=4345,failures=0),indent=2))
