"""Read-only integrity/results check. No engine or repository mutation."""
import hashlib,json,pathlib,re,zipfile
R=pathlib.Path(__file__).resolve().parent
index=json.loads((R/'index.json').read_text(encoding='utf8'))
raw=R/index['archive']['name']
def digest(stream):
 h=hashlib.sha256()
 for chunk in iter(lambda:stream.read(1048576),b''):h.update(chunk)
 return h.hexdigest()
with raw.open('rb') as f:assert digest(f)==index['archive']['sha256'],'archive SHA'
with zipfile.ZipFile(raw) as z:
 assert set(z.namelist())==set(index['members']),'member names'
 for name,expected in index['members'].items():
  info=z.getinfo(name);assert info.file_size==expected['bytes'] and info.CRC==expected['crc32'],name
  with z.open(name) as f:assert digest(f)==expected['sha256'],name
 def data(name):return json.loads(z.read(name))
 red=data('runs/1794478140305629400/receipt.json')
 assert red['exit_code']==1 and red['source_unchanged'] and red['script_errors']==0
 assert red['results'][0]['failures']==6 and len(red['results'][0]['cases'])==13
 local=data('f80-final/local-receipt.json');eq=data('f80-final/equivalence-receipt.json')
 for row in (local,eq):assert row['exit']==0 and row['source_fixed'] and row['script_errors']==0
 assert 'ST3_LOCAL {"checks":74,"failures":0}' in z.read('f80-final/local.log').decode('utf8')
 comparison=data('f80-final/equivalence-results.json')
 assert comparison['conditions']==524 and comparison['comparisons']==5240 and comparison['failures']==0 and comparison['no_state_mutation']
 for row in comparison['rows']:
  assert not row['schema_error']
  assert all(r['equal'] and r['old']==r['new'] and r['old_reads']==r['new_reads'] for r in row['results'])
 final=data('official-f80/exit.json');assert final['exit']==0 and final['source_fixed'] and final['script_errors']==0 and final['shards']==2
 before=data('official-f80/source-before.json');after=data('official-f80/source-after.json');assert before==after
 candidate=data('f80-final/candidate.json');assert candidate['selector']['count']==22
 assert json.loads((R/'candidate.json').read_text(encoding='utf8'))==candidate
 for path,meta in candidate['files'].items():
  assert hashlib.sha256((R/'source'/path).read_bytes()).hexdigest()==meta['candidate_sha256']
  assert hashlib.sha256(z.read('f80-final/source/'+path)).hexdigest()==meta['candidate_sha256']==before[path]
 baseline=z.read('f80-final/baseline/core/story_rules.gd').split(b'\n',1)[1]
 assert baseline==z.read('baseline_story_rules.gd').split(b'\n',1)[1]
 output=z.read('official-f80/full.log').decode('utf8');assert re.search(r'checks: \d+, new failures: 0, known failures .*: 0',output)
 print('PASS: byte integrity; clean red13/6; final74/0; formal5240/0; original affected22 exit0/source-fixed. Intentional ERROR/shutdown diagnostics remain in original logs.')
