"""由固定原圖與同部件座標映射，重建洪先生五片批准來源。"""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'tools/comfyui'))
from cut_layers import part_transform,render_part
from registered_layers import registered_layer_bytes,write_registered_file

def sha(data):
    return hashlib.sha256(data).hexdigest()

def input_sha(path):
    data=path.read_bytes()
    return sha(data.replace(b'\r\n',b'\n') if path.suffix in {'.json','.py'} else data)

def rgba(path):
    with Image.open(path) as image:
        return np.array(image.convert('RGBA'))

def main():
    record=json.loads((HERE/'provenance.json').read_text(encoding='utf-8'))
    for name,expected in record['inputs'].items():
        path=ROOT/name
        if not path.is_file() or input_sha(path)!=expected:
            raise ValueError(f'洪先生來源版本不同，重建前停止：{name}')
    mask_path=HERE/'neck-mask.png'
    if sha(mask_path.read_bytes())!=record['neck_mask_sha256']:
        raise ValueError('洪先生頸部遮罩版本不同：neck-mask.png')
    if record.get('schema_version')!=3 or set(record['approved_outputs'])!={'torso','arm_upper','arm_lower','leg_upper','pelvis'}:
        raise ValueError('洪先生來源契約版本不同：provenance.json，需要 schema 3 與五片批准來源')
    configs=record['coordinate_claims']
    if set(configs)!=set(record['approved_outputs'])-{'torso'}:
        raise ValueError('洪先生各映射分件須與批准內容吻合')
    claims_paths={}
    for part,config in configs.items():
        path=(HERE/config['file']).resolve()
        if not path.is_relative_to(HERE.resolve()) or not path.is_file():
            raise ValueError(f'洪先生分件映射來源位置不同：{part}/{config["file"]}')
        if input_sha(path)!=config['canonical_sha256']:
            raise ValueError(f'洪先生分件座標映射版本不同：{part}/{config["file"]}')
        claims_paths[part]=path
    work=ROOT/'art_src/characters/guest_hong'
    registered={work/f'overrides/refined/{part}.png' for part in record['approved_outputs']}
    for path in (work/'overrides').rglob('*.png'):
        if path not in registered:
            raise ValueError(f'洪先生未登記的來源覆寫會改變批准組裝，保留並停止：{path}')
    base=rgba(work/'base_rgba.png')
    originals={name:rgba(work/f'07_refined/{name}.png') for name in record['approved_outputs']}
    if base.shape!=(1536,1024,4) or any(image.shape!=base.shape for image in originals.values()):
        raise ValueError('洪先生來源必須保持1024×1536 RGBA畫布')
    results={name:image.copy() for name,image in originals.items()}
    with Image.open(mask_path) as image:
        if image.mode!='L' or image.size!=(1024,1536):
            raise ValueError('洪先生頸部遮罩須為1024×1536灰階圖')
        neck=np.array(image)==255
    if int(neck.sum())!=256 or np.any(base[:,:,3][neck]<128) or np.any(originals['torso'][:,:,3][neck]>=128):
        raise ValueError('洪先生頸部遮罩不符合256個原圖皮膚補點')
    results['torso'][neck]=base[neck]
    masks={'torso':neck}
    for part,config in configs.items():
        claims=json.loads(claims_paths[part].read_text(encoding='utf-8'))
        if not isinstance(claims,list) or len(claims)!=config['pixels']:
            raise ValueError(f'洪先生{part}映射須保留{config["pixels"]}個核對補點')
        selected=np.zeros(neck.shape,dtype=bool)
        for index,entry in enumerate(claims):
            if not isinstance(entry,dict) or entry.get('part')!=part:
                raise ValueError(f'洪先生{part}映射第{index}項的材料部件不同')
            coords=[entry.get('to'),entry.get('from')]
            if any(not isinstance(pair,list) or len(pair)!=2 or any(type(v) is not int for v in pair) for pair in coords):
                raise ValueError(f'洪先生{part}映射第{index}項須為整數座標')
            (x,y),(sx,sy)=coords
            if not (0<=x<1024 and 0<=sx<1024 and 0<=y<1536 and 0<=sy<1536):
                raise ValueError(f'洪先生{part}映射第{index}項超出來源畫布')
            if selected[y,x] or originals[part][y,x,3]>=128:
                raise ValueError(f'洪先生{part}映射第{index}項重複或改到既有opaque')
            if originals[part][sy,sx,3]<128 or base[sy,sx,3]<128:
                raise ValueError(f'洪先生{part}映射第{index}項不屬於同部件既有材料')
            selected[y,x]=True
            results[part][y,x]=originals[part][sy,sx]
        masks[part]=selected
    spec=json.loads((ROOT/'tools/comfyui/specs/guest_hong_side.json').read_text(encoding='utf-8'))
    scale=spec['tex_px_per_wp']/spec['illustration_px_per_wp']
    joints={name:np.array(point,float)*scale for name,point in spec['joints'].items()}
    layers={}
    for name,result in results.items():
        old=originals[name]
        if not np.array_equal(result[~masks[name]],old[~masks[name]]) or not np.array_equal(result[old[:,:,3]>=128],old[old[:,:,3]>=128]):
            raise ValueError(f'洪先生{name}超出來源核對範圍或改到既有opaque')
        old_image=Image.fromarray(old)
        image=Image.fromarray(result)
        before=part_transform(old_image,spec['parts'][name],joints,scale)
        after=part_transform(image,spec['parts'][name],joints,scale)
        if not all(np.array_equal(a,b) for a,b in zip(before,after)):
            raise ValueError(f'洪先生{name}畫布、支點或取樣格改變')
        if sha(render_part(image,after,scale).tobytes())!=record['diffuse_rgba_sha256'][name]:
            raise ValueError(f'洪先生{name}原生切件像素不同於批准候選')
        layers[name]=image
    payloads=registered_layer_bytes(layers,HERE,record)
    targets={name:work/f'overrides/refined/{name}.png' for name in payloads}
    # 先核對所有既有輸出，避免第二片錯誤時已發布第一片。
    for name,target in targets.items():
        if target.exists() and target.read_bytes()!=payloads[name]:
            raise ValueError(f'洪先生已有不同的來源覆寫，保留並停止：{target}')
    for name,target in targets.items():
        write_registered_file(target,payloads[name])
    print('洪先生五片來源已核對原圖、同件材料、批准 PNG 與位置。')

if __name__=='__main__':
    main()
