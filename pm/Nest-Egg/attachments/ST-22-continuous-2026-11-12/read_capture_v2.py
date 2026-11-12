"""Independent continuous home2 alpha/ROI/publication validation. No Godot."""
from pathlib import Path
import argparse,hashlib,json,math,traceback
import numpy as np
from PIL import Image

def sha(raw):return hashlib.sha256(raw).hexdigest()
def matrix(t):return np.array([[t[0],t[2],t[4]],[t[1],t[3],t[5]],[0,0,1]],dtype=np.float64)
def close(a,b):return np.max(np.abs(np.asarray(a)-np.asarray(b)))<=.001
def clear(rows):return len(rows)==2 and all(r['state'] in ['empty','refused'] and (r['state']!='refused' or r['winerror']==10061) for r in rows)

def validate(epoch):
    root=epoch/'captures';report=json.loads((root/'observations.json').read_bytes())
    receipt=json.loads((epoch/'receipt.json').read_bytes())
    assert receipt['exit_code']==0 and receipt['source_unchanged'] and receipt['c_unchanged'] and not receipt['diagnostics']
    before=json.loads((epoch/'source-before.json').read_bytes());assert len(before)==receipt['source_count']==18967 and before==json.loads((epoch/'source-after.json').read_bytes())
    c=json.loads((epoch/'c-before.json').read_bytes());assert len(c)==397 and c==json.loads((epoch/'c-after.json').read_bytes())==json.loads((epoch/'c-context-expected.json').read_bytes())['files']
    for name in ['outer-queue-before.json','inner-queue-before.json','inner-queue-after.json','outer-queue-after.json']:assert clear(json.loads((epoch/name).read_bytes()))
    assert report['renderer']=='forward_plus' and '9070 XT' in report['device'] and not report['issues']
    rows=report['rows'];marker=report['marker50_sample'];assert rows and 0<=marker<len(rows)
    assert report['roi_frozen_at_target'] and report['observation_margin_physical_pixels']==32
    frozen_roi=rows[0]['roi'];assert all(row['roi']==frozen_roi for row in rows), 'TARGET crop must never chase the head'
    masks=[];measurements=[]
    for i,row in enumerate(rows):
        assert row['sample']==i and row['actual_max_fps']==60 and row['time_scale']==1
        assert row['actor_processing'] and row['actor_can_process'] and row['actor_visible']
        assert row['process_pre']==row['process_post'] and row['physics_pre']==row['physics_post']
        assert row['actor_t']==row['actor_t_post'] and row['source_pre_post_equal'] and not row['live_material_mutated']
        assert row['world_to_pixels']==row['world_to_pixels_post']
        if i:
            assert row['process_pre']==rows[i-1]['process_pre']+1,'missing or repeated process publication in target-line trace'
            assert row['actor_t']>rows[i-1]['actor_t'] and row['usec_pre']>rows[i-1]['usec_post']
        assert len(row['parts'])==3 and all(p['copy_transform_equal'] and p['class']=='Sprite2D' for p in row['parts'])
        x,y,w,h=row['roi'];assert all(isinstance(n,int) for n in [x,y,w,h]) and row['mask_format']==15 and row['mask_size']==[w,h]
        translated=np.array([[1,0,-x],[0,1,-y],[0,0,1]])@matrix(row['world_to_pixels'])
        assert close(matrix(row['roi_canvas']),translated)
        for part in row['parts']:
            assert close(matrix(part['pixel_transform']),matrix(row['world_to_pixels'])@matrix(part['global_transform']))
        raw=(root/row['mask_path']).read_bytes();assert sha(raw)==row['mask_sha256'] and len(raw)==row['mask_bytes']==w*h*8
        rgba=np.frombuffer(raw,dtype='<f2').reshape(h,w,4);assert np.isfinite(rgba).all()
        alpha=rgba[:,:,3].astype(np.float64);assert (alpha>=0).all() and (alpha<=1).all()
        opaque=alpha>=.999;present=alpha>0
        sx,sy,sw,sh=row['safe_pixels'];xx,yy=np.meshgrid(np.arange(w)+x+.5,np.arange(h)+y+.5)
        inside=(xx>=sx)&(xx<sx+sw)&(yy>=sy)&(yy<sy+sh)
        outside=int((present&~inside).sum());border=int(present[0,:].sum()+present[-1,:].sum()+present[:,0].sum()+present[:,-1].sum())
        assert int(opaque.sum())==row['opaque_pixels']>=200 and border==row['alpha_border_pixels']==0
        assert outside==row['any_alpha_outside_safe']==0,'actual positive head alpha outside original safe boundary'
        top=float(yy[present].min());margin=float(np.minimum.reduce([xx-sx,sx+sw-xx,yy-sy,sy+sh-yy])[present].min())
        assert abs(top-row['first_alpha_pixel_center_y'])<1e-6 and abs(margin-row['minimum_safe_margin_pixels'])<.001
        measurements.append({'sample':i,'first_alpha_y':top,'safe_top':sy,'minimum_margin':margin,'outside':outside,'opaque':int(opaque.sum()),'body_top':row['body_pixels'][1],'body_above_safe':row['body_pixels'][1]<sy})
        masks.append(rgba)
    original50=rows[marker]
    assert original50['original50_marker'] and original50['process_pre']-original50['original_complete_process']==50
    assert rows[-1]['actor_t']-original50['actor_t']>=3.2
    assert rows[-1]['breath_phase']-original50['breath_phase']>=math.tau
    assert rows[-1]['physics_post']>rows[0]['physics_pre']
    # Same-draw full reference alpha must be byte-exact to the original ROI.
    for reason,item in report['reference'].items():
        row=rows[item['sample']];x,y,w,h=row['roi'];width,height=item['size']
        assert item['format']==15 and item['png_error']==0 and row['same_draw_reference_alpha_differences']==0
        raw=(root/item['raw_path']).read_bytes();assert sha(raw)==item['raw_sha256'] and len(raw)==width*height*8
        rgba=np.frombuffer(raw,dtype='<f2').reshape(height,width,4)
        assert np.array_equal(rgba[y:y+h,x:x+w,3].view('<u2'),masks[item['sample']][:,:,3].view('<u2'))
    # Selected full RGBH/RGBAH originals stay full size and use float->sRGB first.
    for reason,item in report['full'].items():
        width,height=item['size'];assert [width,height]==[1280,720] and item['png_error']==0
        channels={14:3,15:4}[item['format']];raw=(root/item['raw_path']).read_bytes()
        assert sha(raw)==item['raw_sha256'] and len(raw)==width*height*channels*2
        rgba=np.frombuffer(raw,dtype='<f2').reshape(height,width,channels).astype(np.float64);assert np.isfinite(rgba).all()
        rgb=rgba[:,:,:3];expected=np.clip(np.where(rgb<=.0031308,12.92*rgb,1.055*np.maximum(rgb,0)**(1/2.4)-.055),0,1)
        png=np.asarray(Image.open(root/item['png_path']).convert('RGBA'));assert list(png.shape[:2])==[height,width]
        assert np.max(np.abs(png[:,:,:3]/255-expected))<=1/255+1e-5
    return {'scope':'new continuous same-line natural trace only; never proves the missing alpha of old v1 frame','draws':len(rows),'first_complete_process':original50['original_complete_process'],'original50_sample':marker,'actor_seconds_after50':rows[-1]['actor_t']-original50['actor_t'],'actual_breath_cycles_after50':(rows[-1]['breath_phase']-original50['breath_phase'])/math.tau,'minimum_alpha_margin_pixels':min(r['minimum_margin'] for r in measurements),'conservative_body_above_safe_in_new_frames':[r for r in measurements if r['body_above_safe']],'measurements':measurements,'passed':True}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('epoch',type=Path);parser.add_argument('out',type=Path);args=parser.parse_args();args.out.mkdir()
    result={'passed':False}
    try:result=validate(args.epoch)
    except Exception as error:result.update(error=repr(error),traceback=traceback.format_exc())
    (args.out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    (args.out/'reader-original.py').write_bytes(Path(__file__).read_bytes())
    print(json.dumps({k:v for k,v in result.items() if k!='measurements'},indent=2));raise SystemExit(0 if result['passed'] else 1)
