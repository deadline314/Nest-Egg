from pathlib import Path,PurePosixPath
import hashlib,json,shutil,subprocess,sys,tempfile,zipfile
import numpy as np
import verify_ne260_current_20261118 as native

def sha(f):
 with f.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def verify(base):
 m=json.loads((base/'manifest.json').read_text())
 for n,h in m['readers'].items():assert sha(base/n)==h
 with tempfile.TemporaryDirectory(prefix='ne260-reader-',dir=base) as temporary:
  root=Path(temporary).resolve()
  with (root/'evidence.zip').open('wb') as combined:
   for part in m['parts']:
    assert Path(part['file']).name==part['file'] and (base/part['file']).stat().st_size==part['bytes'] and sha(base/part['file'])==part['sha256'],'Archive digest mismatch'
    with (base/part['file']).open('rb') as stream:shutil.copyfileobj(stream,combined,1024*1024)
  assert sha(root/'evidence.zip')==m['archive_sha256'],'Archive digest mismatch'
  with zipfile.ZipFile(root/'evidence.zip') as z:
   assert len(z.namelist())==len(set(z.namelist()))==len(m['files']) and set(z.namelist())==set(m['files'])
   for n,r in m['files'].items():
    name=PurePosixPath(n);assert not name.is_absolute() and '..' not in name.parts and '\\' not in n
    raw=z.read(n);assert len(raw)==r['bytes'] and hashlib.sha256(raw).hexdigest()==r['sha256'];target=root.joinpath(*name.parts);assert target.is_relative_to(root);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
  s0=json.loads((root/'source-base.json').read_text());s1=json.loads((root/'source-v1.json').read_text());s2=json.loads((root/'source-v2.json').read_text());s3=json.loads((root/'source-v3.json').read_text());assert s0.keys()==s1.keys()==s2.keys()==s3.keys() and len(s0)==10095
  assert [n for n in s0 if s0[n]!=s1[n]]==['tools/melee_art_probe.gd'];assert [n for n in s1 if s1[n]!=s2[n]]==['tools/melee_art_probe.gd']
  assert [n for n in s2 if s2[n]!=s3[n]]==['tools/melee_art_probe.gd']
  s4=json.loads((root/'source-v4.json').read_text());assert s3.keys()==s4.keys() and [n for n in s3 if s3[n]!=s4[n]]==['tools/melee_art_probe.gd']
  s5=json.loads((root/'source-v5.json').read_text());assert s4.keys()==s5.keys() and {n for n in s4 if s4[n]!=s5[n]}=={'tools/melee_art_probe.gd','tools/weapon_head_probe.gd'}
  for n in ['tools/melee_art_probe.gd','tools/weapon_head_probe.gd','tools/viewport_capture.gd','core/audio/audio_release.gd','core/melee_art.gd','game/player/blade_light.gd','game/player/melee_held.gd','data/weapon_art/melee.json']:
   assert sha(root/'source'/n)==s5[n]
  assert sha(root/'diagnostics/melee_art_probe-original.gd')==s0['tools/melee_art_probe.gd']
  final=(root/'source/tools/melee_art_probe.gd').read_text();initial=(root/'diagnostics/melee_art_probe-v1.gd').read_text()
  assert final.count('await AudioRelease.settle(get_tree())')==2 and 'func _capture_pose' in final
  assert sha(root/'diagnostics/melee_art_probe-v1.gd')==s1['tools/melee_art_probe.gd'] and sha(root/'diagnostics/melee_art_probe-v2.gd')==s2['tools/melee_art_probe.gd']
  assert sha(root/'diagnostics/melee_art_probe-v3.gd')==s3['tools/melee_art_probe.gd']
  assert sha(root/'diagnostics/melee_art_probe-v4.gd')==s4['tools/melee_art_probe.gd'] and sha(root/'diagnostics/weapon_head_probe-original.gd')==s4['tools/weapon_head_probe.gd']
  old=json.loads((root/'diagnostics/original-high/result.json').read_text());assert old['exit']==1 and len(old['error_lines'])==2 and old['png_count']==94
  rejected=json.loads((root/'diagnostics/candidate-high-v1/result.json').read_text());assert rejected['exit']==0 and rejected['error_lines']
  core=json.loads((root/'checks-v1/result.json').read_text());assert core['passed'] and core['source_held'] and all(r['exit']==r['script_errors']==0 for r in core['runs'])
  changed=json.loads((root/'changed-final/result.json').read_text());assert changed['passed'] and changed['source_held']
  rows={q:native.verify(root/('final-'+q)) for q in ['low','high']}
  for q in ['low','high']:
   report=json.loads((root/('final-'+q)/'current-index.json').read_text())
   assert all(h['recipients_hidden']==1 and h['blade_energy']>0 for weapon in report['weapons'].values() for h in weapon['head_exposure'])
  witness=root/'diagnostics/final-low-v3-head-bound';old_head=json.loads((witness/'current-index.json').read_text())['weapons']['dagger']['head_exposure'][-1]
  world=native.image(witness,old_head['files']['world_raw'][:-4],640,360,old_head['world_format']);mask=native.image(witness,old_head['files']['mask_raw'][:-4],640,360,old_head['mask_format']);opaque=mask[...,3]>=.999
  assert old_head['white_rectangle_pixels']==9 and int(opaque.sum())==391 and int(((world[...,:3]>.92).all(axis=2)&opaque).sum())==0
  witness=root/'diagnostics/final-low-v4-rectangle-bound';old_head=json.loads((witness/'current-index.json').read_text())['weapons']['glaive']['head_exposure'][1];world=native.image(witness,old_head['files']['world_raw'][:-4],640,360,old_head['world_format']);mask=native.image(witness,old_head['files']['mask_raw'][:-4],640,360,old_head['mask_format'])
  assert old_head['white_rectangle_pixels']==8 and int((mask[...,3]>=.999).sum())==394 and int(((world[...,:3]>.92).all(axis=2)&(mask[...,3]>0)).sum())==0
  # A copied real exposure with an empty mask must fail the same reader.
  case=root/'final-high';r=json.loads((case/'current-index.json').read_text())['weapons']['blade']['head_exposure'][0]
  mask=case/r['files']['mask_raw'];png=case/r['files']['mask_png'];saved=mask.read_bytes();saved_png=png.read_bytes();dtype,channels=native.pixels.FORMATS[r['mask_format']]
  value=np.frombuffer(saved,dtype=dtype).copy().reshape(r['height'],r['width'],channels);value[...,3]=0;mask.write_bytes(value.tobytes())
  from PIL import Image
  im=Image.open(png).convert('RGBA');im.putalpha(0);im.save(png)
  refused=False
  try:native.head(case,r)
  except AssertionError:refused=True
  finally:mask.write_bytes(saved);png.write_bytes(saved_png)
  assert refused,'Empty real head alpha was accepted'
  return {'passed':True,'source_count':len(s5),'native':rows,'actual_empty_alpha_rejected':True,'scope':'arranged native art/light verification; old rectangle W/H retained plus tighter nonzero-head-alpha W / opaque H upper bound at same2% gate; unobstructed head captures hide only nearby receiver and keep blade light; visible receiver for on/off pairs; no natural combat, all optional moves/poses, FPS or VRAM claim'}

if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]).resolve()),indent=2))
