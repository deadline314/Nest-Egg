"""Map traced rendered joint holes back through actual triangles/UV into this source."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
from scipy import ndimage

WORK=Path(__file__).resolve().parent
ROOT=WORK.parents[2]
sys.path.insert(0,str(ROOT/'tools/comfyui'))
from cut_layers import part_transform

def barycentric(triangle, point):
    return np.linalg.solve(np.vstack([triangle.T,np.ones(3)]),[*point,1])
assert np.allclose(barycentric(np.array([[0.,0.],[2.,0.],[0.,2.]]),[.5,.5]),[.5,.25,.25])

ap=argparse.ArgumentParser();ap.add_argument('directory');ap.add_argument('--pose',required=True);ap.add_argument('--zoom',type=float,default=3.4)
ap.add_argument('--facing',type=int,choices=[-1,1],default=1)
ap.add_argument('--snapshot',type=Path,help='Frozen source folder containing spec.json, base_rgba.png, 07_refined and hashes.json')
ap.add_argument('--out',type=Path,help='Optional receipt path; historical frame packets need not be rewritten')
args=ap.parse_args()
audit=Path(args.directory);groups=json.loads((audit/'frames.json').read_text(encoding='utf8'))
source_work=WORK;spec_path=ROOT/'tools/comfyui/specs/harbor_lamplighter_demo_side.json'
if args.snapshot:
    source_work=args.snapshot.resolve();spec_path=source_work/'spec.json'
    for relative,digest in json.loads((source_work/'hashes.json').read_text(encoding='utf8')).items():
        path=(source_work/relative).resolve()
        if not path.is_relative_to(source_work) or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise ValueError(f'Invalid frozen source: {relative}')
s=json.loads(spec_path.read_text(encoding='utf8'))
k=s['tex_px_per_wp']/s['illustration_px_per_wp'];joints={n:np.asarray(v)*k for n,v in s['joints'].items()}
base=np.asarray(Image.open(source_work/'base_rgba.png'))
g=next(g for g in groups if g['pose']==args.pose and g['zoom']==args.zoom)
cell=next(c for c in g['cells'] if c['facing']==args.facing and 'geometry_sample' in c)
frame=cell['geometry_frame'];sample=g['samples'][frame]
image=np.asarray(Image.open(audit/sample['file']));x,y,width,height=cell['rect'];alpha=image[y:y+height,x:x+width,3]
r=cell['radius'];band=alpha[64-r:64+r,64-r:64+r]>=128
holes=ndimage.binary_fill_holes(band)&~band;ys,xs=np.where(holes);receipt=[]
for px,py in zip(xs+64-r,ys+64-r):
    item={'pose':args.pose,'zoom':args.zoom,'frame':frame,'facing':args.facing,'source_snapshot':str(source_work),
          'spec_sha256':hashlib.sha256(spec_path.read_bytes()).hexdigest(),'cell_pixel':[int(px),int(py)],'parts':[]}
    for part in cell['geometry_sample']:
        transform=np.asarray(part['to_cell']);texture=None
        if 'vertices' in part:
            vertices=np.asarray(part['vertices']);uv=np.asarray(part['uv']);screen=np.c_[vertices,np.ones(len(vertices))]@transform.T
            for indices in part['triangles']:
                weights=barycentric(screen[indices],[px+.5,py+.5])
                if weights.min()>=-1e-6: texture=weights@uv[indices];break
        else:
            texture=np.linalg.solve(transform[:,:2],np.array([px+.5,py+.5])-transform[:,2])-part['rect_origin']
        if texture is None:continue
        name=Path(part['texture']).stem
        if name in ['head_half','head_closed']:name='head'
        source=np.asarray(Image.open(source_work/'07_refined'/f'{name}.png'))
        geometry=part_transform(Image.fromarray(source),s['parts'][name],joints,k)
        point=(geometry[0]@[*texture,1])/k
        sx,sy=np.round(point).astype(int)
        valid=0<=sx<source.shape[1] and 0<=sy<source.shape[0]
        item['parts'].append({'part':name,'texture':texture.tolist(),'source':point.tolist(),
                              'part_alpha_at_nearest_source':int(source[sy,sx,3]) if valid else None,
                              'base_rgba_at_nearest_source':base[sy,sx].tolist() if valid else None})
    receipt.append(item)
(args.out or audit/('source-hole-mapping.json' if args.facing==1 else 'source-hole-mapping-left.json')).write_text(json.dumps(receipt,indent=2),encoding='utf8')
print(json.dumps(receipt,indent=2))
