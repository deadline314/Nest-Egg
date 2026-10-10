from pathlib import Path
import json,math,hashlib
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
old=json.loads((HERE/'rejected-bone-axis-bind.json').read_text())
rig=json.loads((ROOT/'art/rigs/humanoid_tall.json').read_text())
char=json.loads((ROOT/'art/characters/rin/character.json').read_text())
# Check complete JSON data independently of checkout CRLF/LF conversion.
canonical=lambda obj:hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(',',':')).encode()).hexdigest()
contract=json.loads((HERE/'contract.json').read_text())
for relative,expected in contract.items():
 value=json.loads((ROOT/relative).read_bytes());assert canonical(value)==expected
 changed=dict(value);changed['ne222_wrong_contract_control']=True;assert canonical(changed)!=expected
assert hashlib.sha256((ROOT/'art_src/characters/rin2/base_rgba.png').read_bytes()).hexdigest()==old['protected_legacy_source']['sha256']
source=np.asarray(Image.open(ROOT/old['source']['path']))
assert hashlib.sha256((ROOT/old['source']['path']).read_bytes()).hexdigest()==old['source']['sha256']
rot=lambda a:np.array([[math.cos(a),-math.sin(a)],[math.sin(a),math.cos(a)]])
ang=lambda v:math.atan2(v[1],v[0])
wrap=lambda a:(a+math.pi)%(2*math.pi)-math.pi
def xform(a):return np.array([[a[0],a[2]],[a[1],a[3]]]),np.array(a[4:6])
names=[b['name'] for b in rig['bones']];parents={b['name']:b['parent'] for b in rig['bones']}
B={};C={}
for b in rig['bones']:
 n=b['name'];par=b['parent'];r,p=xform(old['bind_pose'][n]);B[n]=(r,p) if not par else (B[par][0]@r,B[par][1]+B[par][0]@p)
 cr=rot(1.4 if n.startswith('hand_') else 0.0);cp=np.array(b['pos']);C[n]=(cr,cp) if not par else (C[par][0]@cr,C[par][1]+C[par][0]@cp)
original={n:(r.copy(),p.copy()) for n,(r,p) in B.items()}
# Artist-reviewed material landmarks in the actual canonical texture; axes are not assumed +Y.
landmarks={'hand_front':('hand',[120,32]),'hand_back':('hand_left',[116,32]),'foot_front':('foot',[153,168]),'foot_back':('foot',[153,168])}
rows=[]
for n,(texture,end) in landmarks.items():
 spec=char['textures'][texture];pivot=np.array(spec['pivot']);local=np.array(end)-pivot
 img=np.asarray(Image.open(ROOT/'art/characters/rin'/spec['file']));assert img[end[1],end[0],3]>127
 start=np.array(old['source_pivots_native'][n]);src_end=np.array(old['terminal_probes_native'][n]);axis=src_end-start;assert source[int(src_end[1]),int(src_end[0]),3]>127
 r=rot(ang(axis)-ang(local));B[n]=(r,B[n][1]);mapped=C[n][0]@r.T@axis;target=C[n][0]@local
 error=abs(math.degrees(wrap(ang(mapped)-ang(target))));assert error<1e-8
 rejected=C[n][0]@original[n][0].T@axis;bad=abs(math.degrees(wrap(ang(rejected)-ang(target))));assert bad>8
 rows.append({'bone':n,'formal_texture':texture,'formal_sha256':hashlib.sha256((ROOT/'art/characters/rin'/spec['file']).read_bytes()).hexdigest(),'formal_pivot_xy':pivot.tolist(),'formal_material_endpoint_xy':end,'source_pivot_xy':start.tolist(),'source_material_endpoint_xy':src_end.tolist(),'local_material_axis_degrees':math.degrees(ang(local)),'canonical_material_world_axis_degrees':math.degrees(ang(target)),'new_material_error_degrees':error,'v4_wrong_material_axis_error_degrees':bad})
binds={}
for n in names:
 r,p=B[n];par=parents[n]
 if par:r,p=B[par][0].T@r,B[par][0].T@(p-B[par][1])
 binds[n]=[float(r[0,0]),float(r[1,0]),float(r[0,1]),float(r[1,1]),float(p[0]),float(p[1])]
fk={};err=0.0
for n in names:
 r,p=xform(binds[n]);par=parents[n];fk[n]=(r,p) if not par else (fk[par][0]@r,fk[par][1]+fk[par][0]@p);err=max(err,float(np.linalg.norm(fk[n][1]-B[n][1])),float(np.max(abs(fk[n][0]-B[n][0]))))
assert err<1e-8
report={'status':'SOURCE ONLY MATERIAL-AXIS CONTROL; no anatomy, mesh loader, seams, outfit or walk acceptance','source_sha256':old['source']['sha256'],'protected_standing_sha256':old['protected_legacy_source']['sha256'],'parent_order':names,'bind_pose':binds,'source_pivots_native':old['source_pivots_native'],'material_axis_controls':rows,'fk_max_error':err,'wrong_material_axis_controls_rejected':len(rows),'v4_branch_residuals_preserved':old['branch_geometry_endpoint_residuals'],'limits':['Material landmarks are author-reviewed source pixel probes, not animation approval.','The four nonprimary branch residuals remain; no production resource changed.']}
(HERE/'candidate.json').write_bytes((json.dumps(report,indent=2)+'\n').encode())
print(json.dumps({'fk_max_error':err,'material_axis_controls':rows},indent=2))
