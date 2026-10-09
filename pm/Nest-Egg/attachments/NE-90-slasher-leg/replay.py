"""C9 private CPU replay for registered slasher hand/foot/leg rebuild and dynamic cut.
Run after root updates near_hand_repair/rebuild.py. All mutations occur in a temp tree.
"""
from __future__ import annotations
import hashlib, importlib.util, io, json, shutil, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=next(p for p in Path(__file__).resolve().parents if (p/'project.godot').is_file())
OUT=ROOT/'.godot/ne90-slasher-leg-replay'; OUT.mkdir(parents=True,exist_ok=True)
FORMAL_REBUILD=ROOT/'art_src/characters/slasher/near_hand_repair/rebuild.py'
FORMAL_REPAIR=FORMAL_REBUILD.parent; SOURCE_WORK=ROOT/'art_src/characters/slasher'
SOURCE_BASE=SOURCE_WORK/'base_rgba.png'; SOURCE_LEG=SOURCE_WORK/'07_refined/leg_upper.png'
SPEC=ROOT/'tools/comfyui/specs/slasher_side.json'; CUT=ROOT/'tools/comfyui/cut_layers.py'
FORMAL_CHAR=ROOT/'art/characters/slasher'; FORMAL_RIG=ROOT/'art/rigs/slasher.json'
FORMAL_HAND=SOURCE_WORK/'overrides/refined/hand.png'; FORMAL_FOOT=SOURCE_WORK/'overrides/refined/foot.png'
FORMAL_FAR_MASK=FORMAL_REPAIR/'far_hand_current.png'
SHA_BASE='ba9af5139d225d492019c24c261bcd1ba9387d1bca7d10e7fd0fa3f5f1931bf3'
SHA_LEG='f3bff90fa46785af4ff94a820b92826d6bf9bd0d434e8493ebfb61c4e75767fb'
SHA_HAND='18d024d38da8f329226bc09339cbed7758b9cef6a683a1a886931d2c2419270b'
SHA_FOOT='702d37fd217b851a5aae959b657471eafd1bd847d3b236a90a73576e45943c36'
SHA_FAR='718b09533a53441f2143cd9133d4714fdebcd6b1c923fe90f087c817c245f610'
SHA_LEG_FULLCANVAS='3a0a4852db6015bdd75b99588316dd4a43f564a3b43d8fce3fa28f372266661b'

def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def sha(p): return sha_bytes(p.read_bytes())
def require(ok,msg):
 if not ok: raise AssertionError(msg)
def load_module(script_path):
 sys.path.insert(0,str(ROOT/'tools/comfyui'))
 spec=importlib.util.spec_from_file_location('private_ne90_registered_rebuild',script_path)
 if spec is None or spec.loader is None: raise RuntimeError(f'cannot import {script_path}')
 module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
def png_hashes(folder):
 return {p.name:sha(p) for p in sorted(folder.glob('*.png')) if not p.name.endswith('_n.png')}
def read_rgba(p):
 with Image.open(p) as im:
  if im.mode!='RGBA': raise AssertionError(f'expected RGBA: {p} has {im.mode}')
  return np.asarray(im)
def run_cut(work,char,rig):
 char.mkdir(parents=True); rig.parent.mkdir(parents=True,exist_ok=True)
 cmd=[sys.executable,str(CUT),'--spec',str(SPEC),'--work',str(work),'--char',str(char),'--rig',str(rig)]
 r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,encoding='utf8',errors='replace')
 record={'command':cmd,'exit_code':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
 if r.returncode: raise RuntimeError(f'cut_layers failed: {r.stdout}\n{r.stderr}')
 return record
def stage(temp_root):
 work=temp_root/'art_src/characters/slasher'; repair=work/'near_hand_repair'
 work.mkdir(parents=True); shutil.copytree(FORMAL_REPAIR,repair)
 shutil.copy2(SOURCE_BASE,work/'base_rgba.png')
 shutil.copytree(SOURCE_WORK/'07_refined',work/'07_refined')
 module=load_module(repair/'rebuild.py'); module.HERE=repair
 return work,repair,module
def validate_leg(fullcanvas_path,source_bytes,mask_path):
 src=np.asarray(Image.open(io.BytesIO(source_bytes)).convert('RGBA')); out=read_rgba(fullcanvas_path)
 mask=np.asarray(Image.open(mask_path).convert('RGB'))[:,:,0]==255
 require(out.shape==src.shape,'full-canvas thigh dimensions changed')
 require(np.array_equal(out[~mask],src[~mask]),'full-canvas rebuild altered RGBA outside far-hand mask')
 require(np.all(out[:,:,3][mask]==0),'selected far-hand alpha remains visible')
 require(np.array_equal(out[:,:,:3][mask],src[:,:,:3][mask]),'RGB changed under transparent far-hand mask')
 return {'fullcanvas_size':[out.shape[1],out.shape[0],'source_pixels'],'mask_pixels':int(mask.sum()),'changed_rgba_pixels':int(np.count_nonzero(np.any(out!=src,axis=2))),'outside_mask_changed_pixels':0,'mask_alpha_nonzero_before':int(np.count_nonzero(mask&(src[:,:,3]>0))),'mask_alpha_nonzero_after':int(np.count_nonzero(mask&(out[:,:,3]>0))),'leg_override_sha256':sha(fullcanvas_path)}

def main():
 for p in [FORMAL_REBUILD,SOURCE_BASE,SOURCE_LEG,FORMAL_HAND,FORMAL_FOOT,FORMAL_FAR_MASK,SPEC,CUT]:
  if not p.is_file(): raise SystemExit(f'missing expected input {p}')
 expected={SOURCE_BASE:SHA_BASE,SOURCE_LEG:SHA_LEG,FORMAL_HAND:SHA_HAND,FORMAL_FOOT:SHA_FOOT,FORMAL_FAR_MASK:SHA_FAR}
 for p,d in expected.items():
  if sha(p)!=d: raise SystemExit(f'FAIL-CLOSED: {p.relative_to(ROOT).as_posix()} sha changed: {sha(p)}')
 report={'status':'RUNNING','python':sys.version,'inputs':{p.relative_to(ROOT).as_posix():sha(p) for p in expected},'formal_rebuild_sha256':sha(FORMAL_REBUILD),'spec_sha256':sha(SPEC),'runs':[],'negative_controls':{},'limitations':['CPU replay validates source ownership and deterministic recut only; no claim of anatomy/native visual acceptance.']}
 with tempfile.TemporaryDirectory(prefix='ne90-leg-replay-') as td:
  temp_root=Path(td); work,repair,module=stage(temp_root); target=work/'overrides/refined'; target.mkdir(parents=True)
  original_source_bytes=(work/'07_refined/leg_upper.png').read_bytes()
  for i in (1,2):
   rebuild_stdout=module.rebuild(work)
   full_hashes={name:sha(target/f'{name}.png') for name in ('hand','foot','leg_upper')}
   require(full_hashes=={'hand':SHA_HAND,'foot':SHA_FOOT,'leg_upper':SHA_LEG_FULLCANVAS},f'full-canvas outputs mismatch: {full_hashes}')
   char=temp_root/f'character-{i}'; rig=temp_root/f'rig-{i}'/'slasher.json'
   cutlog=run_cut(work,char,rig)
   part_hashes=png_hashes(char/'parts')
   report['runs'].append({'run':i,'rebuild_stdout':rebuild_stdout,'fullcanvas_override_sha256':full_hashes,'cut_layers':cutlog,'diffuse_part_sha256':part_hashes,'character_json_sha256':sha(char/'character.json'),'rig_json_sha256':sha(rig),'leg_upper_size':[Image.open(char/'parts/leg_upper.png').width,Image.open(char/'parts/leg_upper.png').height]})
  a,b=report['runs']
  require(a['fullcanvas_override_sha256']==b['fullcanvas_override_sha256'],'full-canvas rebuild not deterministic')
  require(a['diffuse_part_sha256']==b['diffuse_part_sha256'],'dynamic cut output PNGs not deterministic')
  require(a['character_json_sha256']==b['character_json_sha256'] and a['rig_json_sha256']==b['rig_json_sha256'],'cut configuration not deterministic')
  formal_parts=png_hashes(FORMAL_CHAR/'parts'); require(a['diffuse_part_sha256']==formal_parts,'private dynamic cut diffuse part set/hash differs from current formal runtime')
  formal_char=json.loads((FORMAL_CHAR/'character.json').read_text(encoding='utf8')); replay_char=json.loads((temp_root/'character-1'/'character.json').read_text(encoding='utf8'))
  formal_rig=json.loads(FORMAL_RIG.read_text(encoding='utf8')); replay_rig=json.loads((temp_root/'rig-1'/'slasher.json').read_text(encoding='utf8'))
  require(formal_char==replay_char,'current formal character.json differs from dynamic private cut')
  require(formal_rig==replay_rig,'current formal rig differs from dynamic private cut')
  formal_leg=read_rgba(FORMAL_CHAR/'parts/leg_upper.png'); replay_leg=read_rgba(temp_root/'character-1'/'parts/leg_upper.png')
  require(formal_leg.shape==replay_leg.shape and np.array_equal(formal_leg,replay_leg),'current formal leg_upper differs from dynamic candidate cut')
  require(list(formal_leg.shape[:2])==[251,119],f'unexpected dynamic recut shape {formal_leg.shape}')
  report['formal_equivalence']={'diffuse_parts_exact':True,'part_count':len(formal_parts),'character_json_exact':True,'rig_json_exact':True,'leg_upper_size':[formal_leg.shape[1],formal_leg.shape[0]],'leg_upper_sha256':sha(FORMAL_CHAR/'parts/leg_upper.png')}
  report['leg_pixel_contract']=validate_leg(target/'leg_upper.png',original_source_bytes,repair/'far_hand_current.png')

  # Negative control 1: an actual one-pixel 07 source change must fail before overwriting prior outputs.
  stable={n:(target/f'{n}.png').read_bytes() for n in ('hand','foot','leg_upper')}
  source_path=work/'07_refined/leg_upper.png'; orig=source_path.read_bytes(); arr=read_rgba(source_path).copy(); arr[0,0,0]^=1; Image.fromarray(arr,'RGBA').save(source_path)
  try:
   module.rebuild(work)
  except ValueError as e: report['negative_controls']['changed_one_source_pixel']={'rejected':True,'error':str(e)}
  else: raise AssertionError('altered source negative control was accepted')
  require({n:(target/f'{n}.png').read_bytes() for n in stable}==stable,'altered-source failure changed an existing output')
  source_path.write_bytes(orig)

  # Negative control 2: corrupt the registered mask in the isolated repair copy.
  mask_path=repair/'far_hand_current.png'; mask_orig=mask_path.read_bytes()
  with Image.open(mask_path) as im: pixels=np.asarray(im.convert('RGB')).copy()
  pixels[0,0,0]=255 if pixels[0,0,0]==0 else 0; Image.fromarray(pixels,'RGB').save(mask_path)
  corrupt_sha=sha(mask_path); require(corrupt_sha!=SHA_FAR,'mask corruption did not change file hash')
  expected_path=module.HERE/'far_hand_current.png'; require(expected_path.resolve()==mask_path.resolve(),f'module uses unexpected mask path: {expected_path}')
  try:
   module.rebuild(work)
  except ValueError as e: report['negative_controls']['corrupted_mask_hash']={'rejected':True,'corrupted_sha256':corrupt_sha,'error':str(e)}
  else: raise AssertionError('corrupted mask negative control was accepted')
  require({n:(target/f'{n}.png').read_bytes() for n in stable}==stable,'corrupted-mask failure changed an existing output')
  mask_path.write_bytes(mask_orig)
  report['negative_controls']['existing_temp_outputs_unchanged_on_fail']=True
  report['temporary_outputs_discarded']=True
 report['status']='PASS_REPLAY_AND_DYNAMIC_FORMAL_EQUIVALENCE_AND_NEGATIVE_CONTROLS; NOT_ANATOMY_ACCEPTANCE'
 out=OUT/'replay-report.json'; out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
