from pathlib import Path
import collections,hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
def body(b):
 m=re.search(r'^func _test_free_encounter\(.*?(?=\nfunc |\Z)',b.decode(),re.S|re.M);assert m;return m.group(0)
i=json.loads((HERE/'index.json').read_bytes());p=HERE/i['archive'];assert p.stat().st_size==i['bytes']and sha(p.read_bytes())==i['sha256']
with zipfile.ZipFile(p)as z:
 assert z.testzip()is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes']and sha(b)==v['sha256']
 assert sha(z.read('source/fixed.gd'))=='54af8acc125876746cf9aa13a6bb19ec3b61594587b22f35ae9679d99d022be0'
 assert body(z.read('source/fixed.gd'))==body(z.read('source/published.gd'))
 d=z.read('source/exact-nine-line.diff').decode().splitlines();assert len([s for s in d if s.startswith('+')and not s.startswith('+++')])==9 and not[s for s in d if s.startswith('-')and not s.startswith('---')]
 base='historical/NE-249-input-fix/'
 for mode in ['right','left','mouse']:
  full=z.read(base+'ne249-final-suite-'+mode+'.log').decode();direct=z.read(base+'ne249-external-'+mode+'2.log').decode()
  assert 'checks: 158, failures: 0'in full and 'SCRIPT ERROR'not in full and '\nERROR:'not in full and 'actual_x=59.25'in full
  assert 'checks: 8, failures: 0'in direct and 'NE249_EXTERNAL_RESTORE'in direct and 'passed=true'in direct and 'actual_x=59.25'in direct
 red=z.read(base+'ne249-baseline-right.log').decode();assert 'checks: 157, failures: 1'in red and 'FAIL: the player can physically leave while both members remain alive'in red
 green=z.read(base+'ne249-final-main-order.log').decode();red=z.read('historical/NE-249-input-isolation/local-main-order.log').decode()
 errors=lambda s:collections.Counter(n for n in s.splitlines()if n.startswith('ERROR:'))
 assert errors(green)==errors(red)and sum(errors(green).values())==14 and 'checks: 2051, failures: 0'in green and 'SCRIPT ERROR'not in green
 for name in ['native.log','native-public-replay.log']:
  s=z.read(base+name).decode();assert 'checks: 8, failures: 0'in s and 'SCRIPT ERROR'not in s and '\nERROR:'not in s
 for name in ['native.json','native-public-replay.json']:
  r=json.loads(z.read(base+name));assert r['player_x']==59.25 and r['living_members']==2 and r['zone']=='active'and r['gate_collision']==[0,0]and r['renderer']=='forward_plus'and r['hdr_2d']
 c=json.loads(z.read('review.json'));assert c['ci_rechecked']['conclusion']=='success'and c['ci_rechecked']['headSha']==c['exact_ci_source']
 assert 'checks: 85189, new failures: 0, known failures (tests/known_failures.txt): 0'in z.read(base+'ci-tests.log').decode()
print('NE249 original three aim controls, restoration, same-process diagnostics, exact successful CI source and unchanged current function verified; no historical files rewritten')
