"""Read-only NE262 evidence reader. Never launches Godot, repairs evidence or consults live runtime."""
from pathlib import Path
import argparse,hashlib,json,math
import numpy as np
from PIL import Image

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def artifact_guard(folder,receipt):
 # Initial CPU receipts precede this integrity field; native final receipts require it.
 for name,expected in receipt.get('artifacts',{}).items():
  assert Path(name).name==name and digest(folder/name)==expected,('artifact drift',name)

def point(t,p):
 assert len(t)==6 and all(math.isfinite(v) for v in t)
 return np.array([t[0]*p[0]+t[2]*p[1]+t[4],t[1]*p[0]+t[3]*p[1]+t[5]])

def segments(actor,legacy):
 result=[]
 for part in actor['parts']:
  if legacy:
   if part['mult']<=1 or not actor['main_enabled']:continue
  elif not part['enabled']:continue
  at=np.array(part['offset']);half=np.array(part['size'])*.5
  corners=[np.array(v) for v in [(-1,-1),(1,-1),(1,1),(-1,1)]]
  lines=[]
  if legacy:
   half+=1.5;arm=min(3,half[0]*.6)
   for c in corners:
    start=at+c*half
    lines.extend([(start,start-np.array([c[0]*arm,0])),(start,start-np.array([0,c[1]*arm]))])
  else:
   vertices=[at+c*half for c in corners]
   lines=list(zip(vertices,vertices[1:]+vertices[:1]))
  transform=actor['draw_to_viewport']
  for a,b in lines:
   result.append({'actor':actor['id'],'part':part['id'],'weak':part['mult']>1,'a':point(transform,a),'b':point(transform,b),'scale':max(np.linalg.norm(transform[:2]),np.linalg.norm(transform[2:4]))})
 return result

def region(line,width,height,shift=0):
 a=line['a']+np.array([shift,0]);b=line['b']+np.array([shift,0]);radius=max(2,line['scale']*.85)
 low=np.floor(np.minimum(a,b)-radius-1).astype(int);high=np.ceil(np.maximum(a,b)+radius+1).astype(int)
 assert (low>=0).all() and high[0]<width and high[1]<height,('projected line clipped',line['actor'],line['part'],low.tolist(),high.tolist())
 xs,ys=np.meshgrid(np.arange(low[0],high[0]+1)+.5,np.arange(low[1],high[1]+1)+.5)
 p=np.stack([xs,ys],axis=-1);ab=b-a;den=float(ab@ab);assert den>0
 t=np.clip(np.sum((p-a)*ab,axis=-1)/den,0,1)
 mask=np.linalg.norm(p-a-t[...,None]*ab,axis=-1)<=radius
 return (slice(low[1],high[1]+1),slice(low[0],high[0]+1)),mask

def check_cpu(folder):
 result=json.loads((folder/'cpu-result.json').read_bytes());receipt=json.loads((folder/'exit.json').read_bytes())
 artifact_guard(folder,receipt)
 before=json.loads((folder/'source-before.json').read_bytes());after=json.loads((folder/'source-after.json').read_bytes())
 assert before['published_inputs']==after['published_inputs'] and before['producer']==after['producer']
 assert receipt['source_same'] and not receipt['diagnostics']
 assert result['checks']==14
 if result['negative_body_as_head']:
  assert receipt['exit']==1 and len(result['failures'])==4
 else:
  assert receipt['exit']==0 and not result['failures']
  head,body=result['rows'];assert head['damage']==[{'part':'head','weak':True,'amount':2}]
  assert head['health_before']-head['health_after']==2 and body['health_before']-body['health_after']==1
  assert head['markers']==['weak'] and body['markers']==['hit']
  assert head['expected_emitted_particles']==max(1,round(head['requested_weak_particles']*head['published_particle_scale']*head['settings_particle_scale']))
  assert len(head['weak_callbacks'])==1 and not body['weak_callbacks']
  assert head['crosshair_weak_left']>0 and body['crosshair_weak_left']==0
  assert 'hit_weak' in head['sounds'] and 'hit_weak' not in body['sounds']
 return {'mode':'cpu','checks':result['checks'],'expected_negative':result['negative_body_as_head'],'recorded_failures':result['failures'],'pcm_or_listening':False}

def check_render(folder,projection_shift=0):
 result=json.loads((folder/'render-result.json').read_bytes());receipt=json.loads((folder/'exit.json').read_bytes())
 assert receipt.get('artifacts'),'native receipt lacks actual artifact hashes'
 artifact_guard(folder,receipt)
 before=json.loads((folder/'source-before.json').read_bytes());after=json.loads((folder/'source-after.json').read_bytes())
 assert before['published_inputs']==after['published_inputs'] and before['producer']==after['producer']
 assert receipt['exit']==0 and receipt['source_same'] and not receipt['diagnostics']
 assert not result['failures'] and result['renderer']=='forward_plus' and result['hdr_2d']
 rows=result['rows'];names=['after-a1','legacy-before','after-a2','debug','after-a3']
 assert [r['name'] for r in rows]==names
 images=[]
 for row in rows:
  image=Image.open(folder/(row['name']+'.png'));assert image.size==(row['width'],row['height'])
  assert (folder/(row['name']+'.raw')).stat().st_size==row['raw_bytes']>0
  assert row['state']==rows[0]['state'] and row['state']['paused']
  assert all(a['body_space'] and all(p['space'] for p in a['parts']) for a in row['state']['actors'])
  images.append(np.array(image.convert('RGB'),dtype=np.int16))
 assert np.array_equal(images[0],images[2]) and np.array_equal(images[0],images[4]),'actual after A/A/A pixels differ'
 assert len({r['engine_process_frame'] for r in rows})==5,'actual renderer did not publish five distinct frames'
 actors=rows[0]['state']['actors'];assert [a['id'] for a in actors]==['grunt','watchdog']
 height,width=images[0].shape[:2]
 observations=[]
 for index,legacy in [(1,True),(3,False)]:
  image=images[index];delta=np.max(np.abs(image-images[0]),axis=-1);lines=[line for a in actors for line in segments(a,legacy)]
  assert lines and any(l['weak'] for l in lines)
  if not legacy:assert any(not l['weak'] for l in lines),'no actual enabled ordinary part for cyan debug test'
  accepted=[]
  for line in lines:
   roi,mask=region(line,width,height,projection_shift)
   rgb=image[roi];changed=delta[roi]>3
   color=(rgb[...,0]>rgb[...,2]+12)&(rgb[...,1]>rgb[...,2]+12) if line['weak'] else (rgb[...,1]>rgb[...,0]+12)&(rgb[...,2]>rgb[...,0]+12)
   count=int(np.count_nonzero(mask&changed&color))
   # One actual projected line must cover more than a single accidental bright pixel.
   required=max(2,int(np.count_nonzero(mask)*.04))
   assert count>=required,('missing renderer line at independently projected geometry',names[index],line['actor'],line['part'],count,required)
   accepted.append({'actor':line['actor'],'part':line['part'],'weak':line['weak'],'changed_color_pixels':count,'required':required,'a':line['a'].tolist(),'b':line['b'].tolist()})
  observations.append({'name':names[index],'lines':accepted,'all_changed_pixels':int(np.count_nonzero(delta>3))})
 # Semantic flags are checked after real pixels, so the two deliberate native
 # faults must also fail the actual renderer/geometry observation.
 assert [r['before_draw_only'] for r in rows]==[False,True,False,False,False]
 assert [r['debug'] for r in rows]==[False,False,False,True,False]
 return {'mode':'native','width':width,'height':height,'same_pose':True,'actual_aa_equal':True,'observations':observations,'scope':'B differs only by the exact archived weak-point draw routine; this proves renderer changes at real authored part geometry, not a complete historical build or user listening.'}

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path);parser.add_argument('--projection-shift',type=float,default=0);args=parser.parse_args()
 result=check_cpu(args.folder) if (args.folder/'cpu-result.json').is_file() else check_render(args.folder,args.projection_shift)
 print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
