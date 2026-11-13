"""Read-only historical red/source closure. This does not accept the untested v5 candidate."""
from pathlib import Path
import argparse,hashlib,json,zipfile,re,tempfile
def digest(b):return hashlib.sha256(b).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf8'))
def verify(root,require_green=False):
    index=load(root/'index.json');assert index['candidate_green'] is False and index['official_accepted'] is False
    for name,row in index['files'].items():assert digest((root/name).read_bytes())==row['sha256'] and (root/name).stat().st_size==row['bytes']
    with tempfile.TemporaryDirectory(prefix='ne297-destination-') as folder:
        d=Path(folder)
        for name,members in index['archives'].items():
            with zipfile.ZipFile(root/name) as z:
                assert z.testzip() is None and set(z.namelist())==set(members)
                for key,row in members.items():
                    parts=Path(key).parts;assert not Path(key).is_absolute() and '..' not in parts
                    raw=z.read(key);assert len(raw)==row['bytes'] and digest(raw)==row['sha256'];q=d/key;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(raw)
        manifest=load(d/'candidate/manifest-v5.json');assert len(manifest['files'])==14
        for name,sha in manifest['files'].items():assert digest((d/'candidate/final'/name).read_bytes())==sha
        proposal=load(d/'candidate/proposal.json')
        for name,row in proposal['changed_files'].items():assert digest((d/'candidate/before'/name).read_bytes())==row['before'] and digest((d/'candidate/final'/name).read_bytes())==row['after']
        red=d/'red/changed-v1';receipt=load(red/'receipt.json')
        assert receipt['accepted'] is False and receipt['exit_code']==1 and receipt['source_exact'] and receipt['c_unchanged'] and receipt['all_four_queue_gates']
        assert load(red/'source-before.json')==load(red/'source-after.json') and load(red/'c-before.json')==load(red/'c-after.json')
        count=0;failed=[];suites=[]
        for i in range(6):
            text=(red/f'test-logs/shard_{i}.log').read_text(encoding='utf8');matches=re.findall(r'^checks: (\d+), failures: (\d+)$',text,re.M);assert len(matches)==1
            checks,failures=map(int,matches[0]);count+=checks;local=re.findall(r'^FAIL: (.*)$',text,re.M);assert len(local)==failures;failed+=local;suites+=re.findall(r'^SUITE_TIME (\S+) ',text,re.M)
        summary=(red/'engine.log').read_text(encoding='utf8');assert 'Running 87 groups in 6 processes' in summary
        assert count==99481 and len(failed)==20 and len(suites)==len(set(suites))==87
        assert re.search(r'checks: 99481, new failures: 20, known failures .*: 0',summary)
        destination=[s for s in failed if s.startswith('actual reader sees the correct destination entry:') or s in ['Main saves a new-area entry with the current membership marker','empty destination membership is valid new-format data','a new-area empty runtime still creates and captures the full authored Level']]
        assert len(destination)==7
        old=load(d/'red/canonical-v2/manifest.json');assert len(old['files'])==74
        before=load(red/'source-before.json')
        # The canonical delivery also includes one design document, explicitly outside the original runtime guard.
        excluded=[n for n in old['files'] if n not in before]
        assert excluded==['design/21-metroidvania/CHAPTER1.md']
        assert all(before[n]==v for n,v in old['files'].items() if n in before)
        with zipfile.ZipFile(d/'red/canonical-v2/source.zip') as source:
            assert set(source.namelist())==set(old['files']) and source.testzip() is None
            assert all(digest(source.read(n))==v for n,v in old['files'].items())
        for name in proposal['changed_files']:assert before[name]==proposal['changed_files'][name]['before']
    if require_green:raise AssertionError('Candidate14 has not been parsed or run. Original87 was 20 new failures; final canonical/native/formal receipts required.')
    return {'historical_red_and_sources_verified':True,'historical_groups':87,'historical_checks':count,'historical_new_failures':len(failed),'destination_failures':destination,'candidate_files':14,'canonical_source_archive_files':74,'canonical_files_in_original_runtime_guard':73,'excluded_design_document':excluded,'candidate_green':False,'official_accepted':False,'engine_started':False}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path,nargs='?',default=Path(__file__).resolve().parent);p.add_argument('--require-green',action='store_true');a=p.parse_args();print(json.dumps(verify(a.root,a.require_green),indent=2))
