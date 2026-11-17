"""Verify portable NE251 evidence without extraction or third-party dependencies."""
from pathlib import Path
import argparse, hashlib, json, struct, zipfile, sys, re

parser=argparse.ArgumentParser()
parser.add_argument('--workspace',type=Path)
parser.add_argument('--export',nargs=2,metavar=('LOGICAL_PATH','NEW_FILE'))
args=parser.parse_args()
root=Path(__file__).resolve().parent
manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
archives={}
checks=0

def check(value,label):
 global checks
 checks+=1
 if not value: raise AssertionError(label)

def read(name):
 row=manifest['members'][name]
 archive=row['archive']
 if archive not in archives: archives[archive]=zipfile.ZipFile(root/archive)
 return archives[archive].read(row['member'])

if args.export:
 name,destination=args.export; data=read(name); row=manifest['members'][name]
 check(hashlib.sha256(data).hexdigest()==row['sha256'],'selected export SHA')
 target=Path(destination);target.parent.mkdir(parents=True,exist_ok=True)
 with target.open('xb') as handle:handle.write(data)
 print('Verified one artifact and exported:',target,'(not a full packet verification)')
 for archive in archives.values():archive.close()
 sys.exit(0)

for name,row in manifest['members'].items():
 data=read(name)
 check(len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name)
for row in manifest['files']:
 data=(root/row['path']).read_bytes()
 check(len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],row['path'])

rows=[]
skipped=0
def samples(s):
 yield s
 for key in ['authored_offscreen_attempt','x_centered_cut_head_attempt']:
  if s.get(key): yield from samples(s[key])

for name in sorted(manifest['members']):
 if not name.startswith('evidence/') or not name.rsplit('/',1)[-1].startswith('ne251-') or not name.endswith('.json'): continue
 report=json.loads(read(name).decode('utf-8'))
 directory=name.rsplit('/',1)[0]
 for outer in report.get('sweep',[])+([report['wake']] if report.get('wake') else []):
  for sample in samples(outer):
   if not sample.get('files'): continue
   images={};complete=True
   for row in sample['files']:
    logical=directory+'/'+row['raw']
    if logical in manifest['members']:
     raw=read(logical)
     check(len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256'],row['raw'])
     images[row['raw']]=(row,raw)
    else:
     omitted=manifest['omitted_historical_binaries'][logical]
     check(omitted['bytes']==row['bytes'] and omitted['sha256']==row['sha256'],'explicit historical raw omission '+logical)
     complete=False
    png=read(directory+'/'+row['png'])
    check(hashlib.sha256(png).hexdigest()==row['png_sha256'] and png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',png,16)==(row['width'],row['height']),row['png'])
   if not complete:
    skipped+=1
    continue
   shot=sample['shot']; sr,shown=images[shot+'.bin']; _,hidden=images[shot+'-hidden.bin']; mr,mask=images[shot+'-head-alpha.bin']
   check(sr['format']==14 and mr['format']==15 and (sr['width'],sr['height'])==(mr['width'],mr['height']),'native HDR formats/dimensions')
   x,y,w,h=sample['rect']; H=W=washed=0; shown_stable=hidden_stable=(min(sr['width'],x+w)>max(0,x) and min(sr['height'],y+h)>max(0,y))
   sr2=images[shot+'-shown-repeat.bin'][1];hr2=images[shot+'-hidden-repeat.bin'][1]
   for yy in range(max(0,y),min(sr['height'],y+h)):
    start=(yy*sr['width']+max(0,x))*6; end=(yy*sr['width']+min(sr['width'],x+w))*6
    shown_stable=shown_stable and shown[start:end]==sr2[start:end]
    hidden_stable=hidden_stable and hidden[start:end]==hr2[start:end]
    for xx in range(max(0,x),min(sr['width'],x+w)):
     index=yy*sr['width']+xx
     if struct.unpack_from('<e',mask,index*8+6)[0]<.999: continue
     H+=1
     rgb=struct.unpack_from('<eee',shown,index*6); back=struct.unpack_from('<eee',hidden,index*6)
     luma=sum(c*k for c,k in zip(rgb,[.2126,.7152,.0722])); behind=sum(c*k for c,k in zip(back,[.2126,.7152,.0722]))
     W+=int(all(c>.97 for c in rgb)); washed+=int(luma>.75 and abs(luma-behind)<.2)
   check((H,W,washed)==(sample['head_pixels'],sample['clipped_pixels'],sample['washed_pixels']),'recomputed opaque H/white/washed '+shot)
   check(shown_stable==sample['shown_stable'] and hidden_stable==sample['hidden_stable'],'repeat raw region '+shot)
   if 'content_rect' in sample:
    cx,cy,cw,ch=sample['content_rect']
    fx,fy,fw,fh=sample.get('visual_rect',sample['rect'])
    inside=fw>0 and fh>0 and fx>=cx and fy>=cy and fx+fw<=cx+cw and fy+fh<=cy+ch
    check(inside==sample['head_inside_content'],'actual content bounds '+shot)
   if sample.get('skip_hint_measurement'):
    hint=sample['skip_hint_measurement']
    check(hint['hidden_during_capture'] and hint['restored'] and hint['before_visible']==hint['after_visible'],'temporary hint restoration '+shot)
   rows.append({'report':name,'shot':shot,'H':H,'W':W,'washed':washed,'reported_passed':sample['passed']})

ledger=json.loads((root/'run-ledger.json').read_text(encoding='utf-8'))
for row in ledger['runs']:
 result=json.loads(read('evidence/'+row['name']+'/result.json'))
 launch=json.loads(read('evidence/'+row['name']+'/launch.json'))
 for relative,sha in launch['source_before'].items():
  source=read('evidence/'+row['name']+'/source/'+relative)
  check(hashlib.sha256(source).hexdigest()==sha==result['source_after'][relative],'actual before/snapshot/after source '+row['name']+'/'+relative)
 check(result['natural_exit']==row['natural_exit'] and result['source_unchanged'] and result['script_errors']==row['script_errors'] and len(result['error_lines'])==row['error_lines'],'natural EOF/source/error ledger '+row['name'])

# Verify top-level GDScript function mappings against actual archived/frozen bytes.
def functions(data):
 chunks=re.split(r'(?m)(?=^func )',data.decode('utf-8-sig'))
 return {re.match(r'func (\w+)',part).group(1):part.strip().encode('utf-8') for part in chunks if part.startswith('func ')}
current=(root/'frozen-candidate/tools/ne251_wake_probe.gd').read_bytes(); current_funcs=functions(current)
for epoch,mapping in json.loads(read('evidence/function-source-map-v12.json')).items():
 alias='evidence/original-e053-ne251_wake_probe.gd' if epoch=='original-e053' else 'evidence/'+epoch+'/source/tools/ne251_wake_probe.gd'
 original=read(alias); original_funcs=functions(original)
 check(hashlib.sha256(original).hexdigest()==mapping['source_sha256'] and hashlib.sha256(current).hexdigest()==mapping['final_sha256'],'mapped whole source '+epoch)
 for name,entry in mapping['functions'].items():
  old=original_funcs[name];new=current_funcs.get(name)
  check(hashlib.sha256(old).hexdigest()==entry['source_sha256'] and (hashlib.sha256(new).hexdigest() if new is not None else None)==entry['final_sha256'] and (old==new)==entry['same_bytes'],'mapped function '+epoch+'/'+name)

# Recompute the original v11 UI-occlusion counterexample against the actual native glyph alpha.
support=json.loads(read('evidence/hint-overlap-v1/result.json'));support_log=read('evidence/hint-overlap-v1/raw.log')
check(support['natural_exit']==0 and b'SCRIPT ERROR:' not in support_log and b'\nERROR:' not in support_log,'glyph-only supporting native EOF; separate guard schema')
proof=json.loads(read('evidence/hint-overlap-v1/overlap.json'))
glyph=read('evidence/hint-overlap-v1/skip-hint-alpha.bin');gm=proof['glyph_meta']
check(hashlib.sha256(glyph).hexdigest()==gm['glyph_sha256'] and gm['format']==15,'native glyph alpha SHA/format')
original=json.loads(read('evidence/sweep-dark-v11/ne251-sweep-flood.json'))
for expected in proof['rows']:
 sample=original['sweep'][expected['index']]
 info=next(f for f in sample['files'] if f['raw'].endswith('-head-alpha.bin'))
 alpha=read('evidence/sweep-dark-v11/'+info['raw']);H=any_alpha=opaque=0;points=[]
 x,y,w,h=sample['rect']
 for yy in range(max(0,y),min(gm['height'],y+h)):
  for xx in range(max(0,x),min(gm['width'],x+w)):
   offset=(yy*gm['width']+xx)*8+6
   if struct.unpack_from('<e',alpha,offset)[0]<.999:continue
   H+=1;a=struct.unpack_from('<e',glyph,offset)[0]
   if a>.001:any_alpha+=1;points.append((xx,yy))
   opaque+=int(a>=.999)
 bounds=[min(q[0] for q in points),min(q[1] for q in points),max(q[0] for q in points)-min(q[0] for q in points)+1,max(q[1] for q in points)-min(q[1] for q in points)+1] if points else None
 check((H,any_alpha,opaque,bounds)==(expected['H'],expected['glyph_any_alpha_over_H'],expected['opaque_glyph_over_H'],expected['overlap_bbox']),'original UI overlap '+sample['shot'])

workspace=args.workspace
if workspace:
 mapping=json.loads((root/'source-newlines.json').read_text(encoding='utf-8'))
 for relative,row in mapping.items():
  raw=(workspace/relative).read_bytes()
  check(hashlib.sha256(raw.replace(b'\r\n',b'\n')).hexdigest()==row['canonical_lf_sha256'],'workspace canonical source '+relative)
print(json.dumps({'checks':checks,'failures':0,'raw_measurements_recomputed':len(rows),'historical_measurements_not_recomputed':skipped,'omitted_historical_binary_files':len(manifest.get('omitted_historical_binaries',{})),'workspace_checked':str(workspace) if workspace else None},indent=2))
for archive in archives.values():archive.close()
