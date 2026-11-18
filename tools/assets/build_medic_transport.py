"""S13場景限定衍生：所有原圖保留，既有不同輸出先拒收。"""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFilter
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    config=json.loads((ROOT/'assets_src/pipeline/medic_transport.json').read_text(encoding='utf-8'))
    for name,expected in config['sources'].items():
        if digest(ROOT/name)!=expected:raise ValueError('S13來源不同，停止發布：'+name)
    sources=config['inputs'];outputs={}
    def image(name,normal=False):
        path=Path(sources[name]);path=path.with_name(path.stem+'_n.png') if normal else path
        if path.as_posix() not in config['sources']:
            raise ValueError(f'S13使用未登記的來源：{path}')
        with Image.open(ROOT/path) as source:
            return source.convert('RGBA')
    def publish(name,im,normal):outputs[name]=im;outputs[name+'_n']=normal
    def masked(name,box,polygon=None,flip=False):
        color=image(name);normal=image(name,True)
        if polygon:
            mask=Image.new('L',color.size,0);ImageDraw.Draw(mask).polygon(polygon,fill=255)
            for im in [color,normal]:im.putalpha(Image.fromarray(np.minimum(np.array(im.getchannel('A')),np.array(mask))))
        color=color.crop(box);normal=normal.crop(box)
        normal.putalpha(color.getchannel('A'))
        if flip:
            color=color.transpose(Image.Transpose.FLIP_LEFT_RIGHT);normal=normal.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            a=np.array(normal);a[:,:,0]=255-a[:,:,0];normal=Image.fromarray(a)
        return color,normal
    bed=image('bed')
    carrier,carrier_n=masked('bed',(0,0,*bed.size),flip=True)
    color=np.array(carrier);normal=np.array(carrier_n)
    rule=config['hidden_mattress'];mask=Image.new('L',carrier.size,0)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in rule['pillow_polygon_mirrored']],fill=255)
    claim=np.array(mask)>0;dilated=np.array(mask.filter(ImageFilter.MaxFilter(rule['edge_dilation'])))>0
    row_y,col_x=np.indices(claim.shape)
    claim |= dilated & (row_y<rule['edge_above_y']) & (col_x>=rule['edge_min_x']) & (color[:,:,:3].min(2)>rule['edge_min_channel'])
    changed=color.copy();changed_n=normal.copy();changed[claim,3]=0;changed_n[claim,3]=0
    yy,xx=np.nonzero(claim & (row_y>=rule['mattress_source_y']))
    donor_x=rule['donor_mirrored_x']+xx-rule['donor_target_x']
    changed[yy,xx]=color[yy,donor_x];changed_n[yy,xx]=normal[yy,donor_x];changed_n[:,:,3]=changed[:,:,3]
    if not np.array_equal(changed[~claim],color[~claim]) or not np.array_equal(changed_n[~claim],normal[~claim]):
        raise ValueError('S13床材改動超出批准枕面claim')
    publish('stretcher',Image.fromarray(changed),Image.fromarray(changed_n))
    patch_receipt={'claim_pixels':int(claim.sum()),'restored_pixels':int(len(xx)),'outside_claim_rgba_unchanged':True,'normal_alpha_matches':bool(np.array_equal(changed[:,:,3],changed_n[:,:,3])),'rule':rule}
    lock=image('lock')
    publish('pause_lock',*masked('lock',(83,128,139,190),[(94,131),(125,131),(133,145),(133,164),(136,170),(135,184),(92,187),(87,181),(87,170),(91,164),(91,143)]))
    # 沿現成金屬色材質組出小鑰匙，幾何與來源記錄在receipt，無人體補畫。
    metal=lock.crop((101,110,113,122)).resize((36,56),Image.Resampling.NEAREST)
    key_mask=Image.new('L',(36,56),0);d=ImageDraw.Draw(key_mask)
    d.ellipse((6,1,29,24),fill=255);d.ellipse((12,7,23,18),fill=0);d.rectangle((15,20,21,54),fill=255);d.rectangle((20,39,29,44),fill=255);d.rectangle((20,49,27,54),fill=255)
    metal.putalpha(key_mask);key_n=Image.new('RGBA',metal.size,(128,128,255,0));key_n.putalpha(key_mask)
    publish('maintenance_key',metal,key_n)
    strip=image('bed').crop((99,80,113,110));strip_n=image('bed',True).crop((99,80,113,110))
    belt=Image.new('RGBA',(14,120));belt_n=Image.new('RGBA',(14,120))
    for y in range(0,120,30):belt.paste(strip,(0,y));belt_n.paste(strip_n,(0,y))
    publish('restraint',belt,belt_n)
    # 現有醫護腰包作周轉裝備袋；多邊形只認領袋身，排除手與制服。
    publish('equipment_bag',*masked('bag',(110,12,186,111),[(114,21),(127,12),(169,16),(180,28),(181,91),(172,105),(127,107),(116,98)]))
    umbrella=image('umbrella');w,h=umbrella.size
    # 傘面與可見杆；桌、杯、椅與桶完全排除，不補原本被桌遮住的杆。
    publish('broken_umbrella',*masked('umbrella',(0,0,w,int(h*.69)),[(0,0),(w,0),(w,170),(181,170),(181,int(h*.69)),(172,int(h*.69)),(172,170),(0,170)]))
    publish('pause_box',image('box'),image('box',True))
    frame=image('gate');frame_n=image('gate',True)
    for im in [frame,frame_n]:
        a=np.array(im);a[:,34:236,3]=0;im.paste(Image.fromarray(a))
    publish('exit_frame',frame,frame_n)
    publish('exit_panel',*masked('gate',(32,44,238,449)))
    publish('exit_sill',*masked('bed',(120,128,420,137)))
    target=ROOT/config['output']
    for name,im in outputs.items():
        path=target/(config['prefix']+name+'.png')
        if path.exists():
            with Image.open(path) as current:
                if current.mode!='RGBA' or current.size!=im.size or current.tobytes()!=im.tobytes():raise ValueError('S13既有衍生不同，保留並拒絕：'+str(path))
    metadata={}
    for name,definition in config['objects'].items():
        im=outputs[name];size=[v*definition['scale']/config['actor_scale'] for v in im.size]
        identifier=config['prefix']+name
        text='[gd_resource type="Resource" script_class="PropData" format=3]\n\n[ext_resource type="Script" path="res://data/scripts/prop_data.gd" id="1_prop"]\n\n[resource]\nscript = ExtResource("1_prop")\nid = &"'+identifier+'"\ndisplay_name = "'+definition['name']+'"\ntexture = "res://'+config['output']+'/'+identifier+'.png"\nsize = Vector2('+', '.join(str(v) for v in size)+')\ncategory = &"scene"\n'
        path=ROOT/'data/environment/scene_props/ch2_medic_transport'/(identifier+'.tres')
        payload=text.encode('utf-8');metadata[path]=payload
        if path.exists() and path.read_bytes()!=payload:raise ValueError('S13既有PropData不同，停止發布：'+str(path))
    target.mkdir(parents=True,exist_ok=True)
    for name,im in outputs.items():
        path=target/(config['prefix']+name+'.png')
        if not path.exists():im.save(path)
    for path,payload in metadata.items():
        if not path.exists():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(payload)
    receipt={'sources':config['sources'],'hidden_mattress':patch_receipt,'outputs':{config['prefix']+name+'.png':digest(target/(config['prefix']+name+'.png')) for name in outputs},'generation':'none；既有原RGBA切件、水平翻面與金屬/布料幾何組合','normal_horizontal_mirror':'翻面法線R=255-R；像素來源不改','original_sources_unchanged':all(digest(ROOT/n)==v for n,v in config['sources'].items()),'key_geometry':'36x56的環、柄與兩齒，鎖具原金屬色材質，平面法線'}
    path=ROOT/'assets_src/pipeline/medic_transport-receipt.json';payload=(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if not path.exists() or path.read_bytes()!=payload:path.write_bytes(payload)
    print('S13限定原材質衍生：',len(outputs),'PNG；先生成完整stage後再套用既有import policy')
if __name__=='__main__':main()
