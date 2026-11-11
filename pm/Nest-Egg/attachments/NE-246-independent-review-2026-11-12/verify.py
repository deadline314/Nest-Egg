from pathlib import Path
import hashlib,io,json,re,zipfile
from PIL import Image
HERE=Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
i=json.loads((HERE/'index.json').read_bytes());bundles={};members=0
for p in i['packets']:
 folder=HERE.parent/p['folder'];raw=(folder/p['archive']).read_bytes()
 assert len(raw)==p['bytes']and sha(raw)==p['sha256']and sha((folder/p['manifest']).read_bytes())==p['manifest_sha256']
 z=zipfile.ZipFile(io.BytesIO(raw));assert z.testzip()is None and set(z.namelist())==set(p['entries'])
 for n,v in p['entries'].items():
  b=z.read(n);assert len(b)==v['bytes']and sha(b)==v['sha256']
 members+=len(z.namelist());bundles[p['folder']]=z
z=bundles['NE-246-real-combat'];records=[];total=0
for mode,count in [('writer',108),('continue',19)]:
 prefix='native/ne246-1022-real-combat-'+mode+'-v1';text=z.read(prefix+'.log').decode();d=json.loads(z.read(prefix+'/result.json'))
 assert len(re.findall(r'^PASS ',text,re.M))==count and not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB.*leak|RID.*leak|resources still in use',text,re.I)
 assert 'Forward+'in text and 'llvmpipe'in text and z.read(prefix+'.exit').strip()==b'0'
 assert d['completed']and d['failures']==0;records.append(d);total+=count
writer,cold=records;assert total==127 and writer['pause_checked']and writer['death_causes']==['flood']
readings=writer['actual_readings'];assert len(readings)==5
for r in readings:
 assert r['before']==r['after']and r['tree_paused']and r['main_process_mode']==1 and not r['main_can_process_while_paused']
 assert any(e['hp']>0 for e in r['before']['enemies'])and r['before']['player_instance']>0
 assert all(line['freeze']for line in r['source_queue'])
assert [len(r['before']['bullets'])for r in readings]==[1,0,0,1,0]
assert readings[0]['sources']==['ch1_g06_lamp','ch1_g06_tip_slide','ch1_g06_tip_blade','ch1_g06_tip_collector']
assert writer['public_confirmations']and all(r['before_count']-r['after_count']==1 for r in writer['public_confirmations'])
for r in cold['rows']:
 assert not r['radio']and not r['radio_queue']
 assert all(r['flags'][k]for k in ['watchdog_defeated','ch1_flood_gate_open','ch1_recording_heard'])
pngs=[n for n in z.namelist()if n.startswith('native/')and n.endswith('.png')];assert len(pngs)==18
for n in pngs:
 with Image.open(io.BytesIO(z.read(n)))as image:assert image.size==(1280,720);image.load()
z=bundles['NE-246-observer-policy']
for name,failed,policy,changed in [('negative-v4',6,0,True),('preflight-v4',0,1,False)]:
 prefix='work/ne246-combat/'+name;d=json.loads(z.read(prefix+'/result.json'));text=z.read(prefix+'.log').decode()
 assert d['failures']==failed and len(re.findall(r'^(?:PASS|FAIL) ',text,re.M))==93
 assert len(d['actual_readings'])==5
 for r in d['actual_readings']:assert r['main_process_mode']==policy and (r['before']!=r['after'])==changed
z=bundles['NE-246-durable-completion']
for name in ['radio-native-final.log','radio-native-final-rollback.log','radio-native-final-committed.log','radio-release-native.log']:
 text=z.read(name).decode();assert not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB.*leak|RID.*leak|resources still in use',text,re.I)
 assert 'Forward+'in text and 'RADIO_DURABLE_PROBE scenario='in text and 'failures=0'in text
for z in bundles.values():z.close()
print(json.dumps(dict(original_archive_members=members,native_processes=2,native_checks=127,native_failures=0,frozen_world_readings=5,readings_with_live_projectiles=2,original_pngs_decoded=18,old_observer='93 checks / 6 failures',fixed_observer='93 checks / 0 failures',scope=i['scope'])))
