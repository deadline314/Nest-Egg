"""Read-only reuse of the stage4 archive/PCM contract, plus public WAV aliases."""
import argparse,hashlib,importlib.util,io,json,os,pathlib,re,subprocess,sys,tempfile,zipfile
HERE=pathlib.Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()
def checked(path,row):
    with path.open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==row['sha256']
    z=zipfile.ZipFile(path)
    assert len(z.namelist())==len(set(z.namelist()))==len(row['members']) and set(z.namelist())==set(row['members'])
    for name,meta in row['members'].items():
        data=z.read(name);assert len(data)==meta['bytes'] and sha(data)==meta['sha256'],name
    return z
def extract(z,prefix,target):
    for name in z.namelist():
        if not name.startswith(prefix):continue
        relative=pathlib.PurePosixPath(name[len(prefix):]);assert not relative.is_absolute() and '..' not in relative.parts
        path=target/pathlib.Path(*relative.parts)
        if name.endswith('/'):path.mkdir(parents=True,exist_ok=True)
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(z.read(name))
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--index',default=str(HERE/'delivery/index.json'));ap.add_argument('--raw-root');args=ap.parse_args()
    index_path=pathlib.Path(args.index);index=json.loads(index_path.read_text());base=index_path.parent
    source=checked(base/'source.zip',index['archives']['source.zip'])
    raw_path=pathlib.Path(args.raw_root) if args.raw_root else base/'accepted-raw.zip'
    raw=checked(raw_path,index['archives']['accepted-raw.zip'])
    prefix='runs/'+index['accepted_run']+'/'
    command=json.loads(raw.read(prefix+'command.json'));receipt=json.loads(raw.read(prefix+'exit.json'))
    assert receipt['exit_code']==0 and not receipt['diagnostic_lines'] and not receipt['gpu_log_rejected'] and not receipt['timed_out']
    assert receipt['source_unchanged'] and command['source_before']==receipt['source_after'] and receipt['runtime_ok']
    assert receipt['runtime'][0]['audio_driver']=='WASAPI'
    assert not re.search(r'SCRIPT ERROR|^ERROR:|WARNING:',raw.read(prefix+'engine.log').decode('utf8').replace('\r',''),re.M)
    nested=zipfile.ZipFile(io.BytesIO(raw.read(prefix+'executed-leaf-source.zip')))
    assert sha(nested.read('run.py'))==command['runner_sha256']
    for name,row in command['mapping'].items():
        canonical=nested.read('canonical/'+name);deployed=nested.read('deployed/'+name)
        assert sha(canonical)==row['canonical_sha256'] and sha(deployed)==row['deployed_sha256']
        expected=canonical.decode('utf8')
        for old,change in row['only_path_replacements'].items():assert expected.count(old)==change['count'];expected=expected.replace(old,change['replacement'])
        assert expected.encode('utf8')==deployed
    manifest=json.loads(source.read('canonical-7-manifest.json'))
    for name,row in manifest['source_files'].items():assert sha(source.read(name))==row['sha256'] and source.read(name)==nested.read('canonical/'+name)
    for name,row in manifest['metadata_files'].items():assert sha(source.read(name))==row['sha256']
    fault_prefix='runs/'+index['negative_run']+'/'
    fault=json.loads(raw.read(fault_prefix+'exit.json'));negative=json.loads(raw.read(fault_prefix+'recording/melee-index.json'))
    assert fault['exit_code']!=0 and fault['source_unchanged'] and not fault['gpu_log_rejected']
    assert raw.getinfo(fault_prefix+'recording/melee-master.wav/').is_dir()
    assert negative['sample_clock']['buses']['Master']['legacy_copy_error']!=0
    assert any('legacy WAV copy failed' in line and 'target=' in line for line in fault['diagnostic_lines'])
    with tempfile.TemporaryDirectory(prefix='ne261-stage5-readonly-') as temp:
        temp=pathlib.Path(temp);extract(source,'',temp/'source');extract(raw,prefix,temp/'raw')
        folder=temp/'raw/recording';data=json.loads((folder/'melee-index.json').read_text())
        for bus,legacy in [('Master','melee-master.wav'),('SFX','melee-sfx.wav')]:
            row=data['sample_clock']['buses'][bus];assert row['legacy_file']==legacy and row['legacy_copy_attempted'] and row['legacy_copy_error']==0
            assert (folder/legacy).is_file() and (folder/legacy).read_bytes()==(folder/('bus-'+bus+'.wav')).read_bytes()
        spec=importlib.util.spec_from_file_location('stage5_pcm',temp/'source/tools/audio/melee_pcm_reader.py');reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
        rate,audio=reader.load(folder,data);content=reader.verify_content(data);frames={n:len(a['raw_f32'])//8 for n,a in audio.items()};del audio
        env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
        p=subprocess.run([sys.executable,'-X','utf8',str(temp/'source/tools/audio/melee_sound_report.py'),str(folder)],env=env,capture_output=True)
        assert p.returncode==0,(p.stdout,p.stderr)
        print(json.dumps({'candidate_sources':5,'actual_import_metadata':2,'rate':rate,'frames':frames,'content':content,'legacy_aliases_byte_exact':2,'legacy_directory_rejected':True,'loudness_exit':p.returncode,'engine_started':False},indent=2))
if __name__=='__main__':main()
