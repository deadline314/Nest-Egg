from pathlib import Path
import csv,hashlib,io,json,re,zipfile
HERE=Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
i=json.loads((HERE/'index.json').read_bytes());p=HERE/i['archive'];assert p.stat().st_size==i['bytes']and sha(p.read_bytes())==i['sha256']
with zipfile.ZipFile(p)as z:
 assert z.testzip()is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes']and sha(b)==v['sha256']
 summaries=[]
 for mode,checks in [('record',126),('cold',117)]:
  base='historical/after-real-audio/'+mode;b=z.read(base+'.log');text=b.decode();w=json.loads(z.read(base+'-wrapper.json'));d=json.loads(z.read(base+'-summary.json'))
  assert w['exit']==0 and w['natural_exit']and w['raw_error_count']==0 and w['warning_count']==0
  assert not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB.*leak|RID.*leak|resources still in use',text,re.I)
  assert w['renderer_line']in text and 'Forward+'in w['renderer_line']and 'B580'in w['renderer_line']
  assert z.read('exact-crlf-reconstruction/'+mode+'.log')==b.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
  assert sha(z.read('exact-crlf-reconstruction/'+mode+'.log'))==w['log_sha256']
  assert d['checks']==checks and d['failures']==0 and d['rounds_requested']==3
  assert len(re.findall(r'^BG31_MAIN_CHECK:PASS:',text,re.M))==checks and 'BG31_MAIN_CHECK:FAIL:'not in text
  events=[json.loads(s.split(':',1)[1])for s in text.splitlines()if s.startswith('BG31_MAIN_STAGE:')];assert events==d['events']
  assert {e['pid']for e in events if 'pid'in e}=={d['pid']}
  rows=[e for e in events if e['stage']=='menu-settled'];assert len(rows)==4
  assert {e['engine_node_count']for e in rows}=={163}and {e['engine_orphan_nodes']for e in rows}=={0}
  assert len({e['render_texture_bytes']for e in rows})==1 and len({e['render_video_bytes']for e in rows})==1
  assert all(e['prefetch']['cached']<=64 and e['prefetch']['inflight']<=1 and e['prefetch']['failed_total']==0 for e in rows)
  memory=list(csv.DictReader(io.StringIO(z.read(base+'-memory.csv').decode())))
  for field,key in [('working_set_bytes','peak_working_set_mb'),('private_bytes','peak_private_mb')]:assert round(max(int(row[field])for row in memory)/1048576,1)==w[key]
  summaries.append(d)
 assert summaries[0]['opening_starts']==summaries[0]['opening_finishes']==1 and summaries[1]['opening_starts']==summaries[1]['opening_finishes']==0
 assert summaries[1]['cold_record_pid']==summaries[0]['pid']and summaries[1]['pid']!=summaries[0]['pid']
 assert summaries[0]['npc_talks']==['ch1_t_oldk_1']and summaries[1]['npc_talks']==['ch1_t_oldk_1','ch1_t_oldk_2']
 for label in ['menu','npc','world']:assert sha(z.read('original-images/'+label+'.png'))==next(r['sha256']for r in summaries[0]['images']if r['kind']==label)
 assert 'ERROR: 4 resources still in use at exit'in z.read('historical/before/record-exit-error.log').decode()
print('BG31 original Arc B580: record126/cold117 real log assertions/events/images, exact CRLF hashes and four stable menu resource samples verified; historical exit failure preserved')
