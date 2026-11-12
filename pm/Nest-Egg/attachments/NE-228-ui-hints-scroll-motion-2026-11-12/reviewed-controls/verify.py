from pathlib import Path
import argparse,hashlib,json,struct,zipfile
HERE=Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
p=argparse.ArgumentParser();p.add_argument('--raw-root',type=Path,required=True);a=p.parse_args()
m=json.loads((HERE/'manifest.json').read_bytes());raw=(HERE/m['archive']).read_bytes();assert len(raw)==m['bytes']and sha(raw)==m['sha256']
with zipfile.ZipFile(HERE/m['archive'])as z:
 assert z.testzip()is None and set(z.namelist())==set(m['members'])
 for n,v in m['members'].items():
  b=z.read(n);assert len(b)==v['bytes']and sha(b)==v['sha256']
 assert len(m['sources'])==5 and 'ui/codex_screen.gd'not in m['sources']
 for n,v in m['sources'].items():assert sha(z.read('baseline/'+n))==v['before_sha256']and sha(z.read('candidate/'+n))==v['candidate_sha256']
 old=z.read('baseline/tests/suite/test_ui_screens.gd').decode();new=z.read('candidate/tests/suite/test_ui_screens.gd').decode()
 assert 'DefeatCodex.restore_unlocked'not in new and 'animated_overlay'in new and 'animated_overlay'not in old
index=json.loads((HERE/'original-controls-index.json').read_bytes());archives={r['path']:r for r in index['archives']}
for family,report in [('quality','report.json'),('death-reduced','death-motion.json'),('scrollbar','scrollbar.json')]:
 for variant in ['original','candidate']:
  positive=variant=='candidate';tag=family+'-'+variant+('-cpu-v4'if family=='scrollbar'else'-native-v1');name='ne228-'+tag+'.zip';v=archives[name];p=a.raw_root/name
  assert p.stat().st_size==v['bytes']and sha(p.read_bytes())==v['sha256']
  with zipfile.ZipFile(p)as z:
   assert z.testzip()is None;r=json.loads(z.read(report));receipt=json.loads(z.read('exit.json'));before=json.loads(z.read('source-before.json'))
   assert receipt['sources_unchanged']and before==receipt['source_after']and not receipt['diagnostics']and receipt['exit']==(0 if positive else 1)
   for n,wanted in before.items():assert sha(z.read('source/'+n))==wanted
   if family=='quality':
    assert len(r['checks'])==4 and sum(not row['passed']for row in r['checks'])==(0 if positive else 4)
    if positive:assert all(row['actual']==row['expected']==row['tooltip']for row in r['checks'])
   elif family=='death-reduced':
    assert r['failures']==(0 if positive else 3)
    if positive:
     row=r['record'];assert row['reduced_ui_motion']and not row['reduce_flashes']and row['card_scale']==[1,1]and row['card_alpha']==1 and row['shader_overlays']==0
   else:
    # Only two scrollbar thickness cases are adopted here. The archived third
    # focus case belongs to the separate, pending Codex delivery.
    rows=r['records'];vertical=next(row for row in rows if 'style_minimum'in row);horizontal=next(row for row in rows if 'fixture'in row)
    assert vertical['overflow']and horizontal['overflow']
    assert (vertical['bar_visible']and vertical['bar_size'][0]>0)==positive
    assert (horizontal['bar_visible']and horizontal['bar_size'][1]>0)==positive
   if family!='scrollbar':
    log=z.read('run.log').decode();assert 'Forward+'in log and '9070 XT'in log
    for n in z.namelist():
     if n.endswith('.png')and '/'not in n:
      b=z.read(n);assert b[:8]==b'\x89PNG\r\n\x1a\n'and struct.unpack('>II',b[16:24])==(1280,720)
print('Reviewed controls only: quality4/4→4/0, scrollbar thickness2/2→2/0, death3/3→3/0; five exact sources/native originals verified; pending Codex focus excluded')
