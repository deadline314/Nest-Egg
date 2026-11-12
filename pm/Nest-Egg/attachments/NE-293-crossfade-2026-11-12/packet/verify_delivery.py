"""Portable read-only NE293 proof. Needs only this packet and external ZIPs."""
import argparse,hashlib,json,pathlib,subprocess,sys,tempfile,zipfile
HERE=pathlib.Path(__file__).resolve().parent
def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def extract_verified(path,expected,root):
    assert sha(path)==expected['sha256'] and path.stat().st_size==expected['bytes'],('archive bytes',path)
    with zipfile.ZipFile(path) as z:
        assert {i.filename for i in z.infolist()}==set(expected['members']) and len(z.infolist())==len(expected['members'])
        for i in z.infolist():
            target=(root/i.filename).resolve();assert target.is_relative_to(root.resolve()),'unsafe member'
            e=expected['members'][i.filename];assert i.file_size==e['bytes'] and i.CRC==e['crc32']
            with z.open(i) as f:assert hashlib.file_digest(f,'sha256').hexdigest()==e['sha256'],('member bytes',i.filename)
        z.extractall(root)
def main():
    p=argparse.ArgumentParser();p.add_argument('--raw-root',required=True,type=pathlib.Path);a=p.parse_args()
    index=json.loads((HERE/'index.json').read_text(encoding='utf8'))
    for name,digest in index['local_files'].items():assert sha(HERE/name)==digest,('local file',name)
    with tempfile.TemporaryDirectory(prefix='ne293-readonly-') as tmp:
        root=pathlib.Path(tmp)
        for name,record in index['archives'].items():extract_verified((a.raw_root if record['external'] else HERE)/name,record,root)
        for name,entry in index['candidate'].items():assert sha(root/entry['source'])==entry['sha256'],('candidate exact',name)
        before=root/'runs/1794472002092308000-holds';after=root/'hold-replay/runs/1794475671530991700'
        with zipfile.ZipFile(before/'executed-leaf.zip') as old,zipfile.ZipFile(after/'executed-leaf.zip') as new:
            assert old.read('audit_melee.gd')==new.read('audit_melee.gd')
            text=old.read('probe.gd').decode('utf8').replace('res://work/ne261-published-hold/','res://work/ne293-hold-replay/').replace('Published896 runtime+canonical7','Published4a2f9ecf+only2NE293')
            assert text.encode()==new.read('probe.gd'),'original hold input/timing logic differs'
        c0=json.loads((before/'command.json').read_text(encoding='utf8'));c1=json.loads((after/'command.json').read_text(encoding='utf8'))
        for n in index['unchanged_hold_inputs']:assert c0['source_before'][n]==c1['source_before'][n],('same hold dependency',n)
        commands=[(['verify_state.py'],0),(['verify_pcm.py'],0),(['unequal-pcm/verify.py'],0),(['summarize_official.py','published-default-official-1794475000448228800'],0),(['before_verify_holds.py','runs/1794472002092308000-holds','--audio-tools','hold-replay/canonical-audio-tools'],1),(['hold-replay/verify_holds.py','hold-replay/runs/1794475671530991700','--audio-tools','hold-replay/canonical-audio-tools'],0)]
        results=[]
        for command,expected in commands:
            r=subprocess.run([sys.executable,*command],cwd=root,capture_output=True)
            assert r.returncode==expected,(command,r.returncode,r.stdout.decode('utf8',errors='replace'),r.stderr.decode('utf8',errors='replace'))
            if command[0]=='before_verify_holds.py':
                j=json.loads(r.stdout);assert len(j['problems'])==1 and j['problems'][0]['weapon']=='maul' and not j['accepted']
            if command[0]=='hold-replay/verify_holds.py':assert json.loads(r.stdout)['accepted']
            results.append({'command':command,'exit':r.returncode,'expected_exit':expected})
    print(json.dumps({'accepted':True,'checks':results,'scope':'No Godot/GPU/network/live WT. Exact2 candidates; original default30 script/raw/filter outcome; state26 red/green; equal and unequal actual PCM; unchanged34-row hold RED/GREEN. Individual default child exit codes were not captured and are not invented. No human/controller/Forward+ claim.'},indent=2))
    return 0
if __name__=='__main__':raise SystemExit(main())
