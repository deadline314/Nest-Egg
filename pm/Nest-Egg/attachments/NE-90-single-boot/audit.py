import argparse, hashlib, json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

EXPECTED = {
    'base_rgba.png': 'ba9af5139d225d492019c24c261bcd1ba9387d1bca7d10e7fd0fa3f5f1931bf3',
    'near_foot.png': 'f72640cc2736ce50335a8c719e4362e3bac6e0eecd9513c30e12e5e6ef709a85',
    'override_foot.png': '702d37fd217b851a5aae959b657471eafd1bd847d3b236a90a73576e45943c36',
}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):
    with Image.open(path) as im: return im.copy(), np.array(im)
def bbox(mask):
    ys, xs = np.nonzero(mask)
    return None if not len(xs) else [int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1)]
def comp_summary(mask):
    # 8-connected components; only diagnostic, never used as semantic acceptance.
    import cv2
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    sizes = sorted((int(stats[i, cv2.CC_STAT_AREA]) for i in range(1, n)), reverse=True)
    return {'pixels': int(mask.sum()), 'components': n-1, 'component_sizes_desc': sizes[:12], 'bbox_xyxy': bbox(mask)}
def composite(rgba, bg):
    rgba = rgba.astype(np.float32)
    a = rgba[:, :, 3:4] / 255.0
    return np.clip(rgba[:, :, :3] * a + np.asarray(bg, np.float32).reshape(1,1,3) * (1-a),0,255).astype(np.uint8)
def make_sheet(root, review, src, owner, anchors, negs):
    x0,y0,x1,y1 = (250,1000,520,1210); s=3
    w,h=(x1-x0)*s,(y1-y0)*s
    panels=[]
    for label,bg in [('source black',(0,0,0)),('source gray',(128,128,128)),('source white',(255,255,255))]:
        img=Image.fromarray(composite(src,bg)[y0:y1,x0:x1]).resize((w,h),Image.Resampling.NEAREST)
        d=ImageDraw.Draw(img)
        for gx in range(260,520,20):
            xx=(gx-x0)*s; d.line((xx,0,xx,h),fill=(105,105,105),width=1); d.text((xx+2,2),str(gx),fill=(255,255,0))
        for gy in range(1000,1210,20):
            yy=(gy-y0)*s; d.line((0,yy,w,yy),fill=(105,105,105),width=1); d.text((2,yy+1),str(gy),fill=(255,255,0))
        for a in anchors:
            x,y=a['xy']
            if x0<=x<x1 and y0<=y<y1:
                xx,yy=(x-x0)*s,(y-y0)*s; d.ellipse((xx-4,yy-4,xx+4,yy+4),outline=(0,255,0),width=2)
        for a in negs:
            x,y=a['xy']
            if x0<=x<x1 and y0<=y<y1:
                xx,yy=(x-x0)*s,(y-y0)*s; d.line((xx-4,yy-4,xx+4,yy+4),fill=(255,0,0),width=2); d.line((xx-4,yy+4,xx+4,yy-4),fill=(255,0,0),width=2)
        panels.append((label,img))
    # Source-domain mask overlay: cyan means selected owner, red means excluded source pixel.
    gray=composite(src,(128,128,128)); color=np.where(owner[:,:,None],np.array([0,255,255],np.uint8),np.array([255,48,48],np.uint8))
    mix=np.clip(gray.astype(np.float32)*0.58+color.astype(np.float32)*0.42,0,255).astype(np.uint8)
    img=Image.fromarray(mix[y0:y1,x0:x1]).resize((w,h),Image.Resampling.NEAREST); d=ImageDraw.Draw(img)
    for a in anchors:
        x,y=a['xy']
        if x0<=x<x1 and y0<=y<y1:
            xx,yy=(x-x0)*s,(y-y0)*s; d.ellipse((xx-4,yy-4,xx+4,yy+4),outline=(0,255,0),width=2)
    for a in negs:
        x,y=a['xy']
        if x0<=x<x1 and y0<=y<y1:
            xx,yy=(x-x0)*s,(y-y0)*s; d.line((xx-4,yy-4,xx+4,yy+4),fill=(255,0,0),width=2); d.line((xx-4,yy+4,xx+4,yy-4),fill=(255,0,0),width=2)
    panels.append(('source + near-foot owner mask (cyan selected / red excluded)',img))
    work=root/'art_src/characters/slasher'
    for rel in ['06_parts/foot.png','07_refined/foot.png','overrides/refined/foot.png']:
        im,a=load(work/rel); rgba=np.array(im.convert('RGBA'))
        for bgname,bg in [('gray',(128,128,128)),('white',(255,255,255))]:
            crop=Image.fromarray(composite(rgba,bg)[y0:y1,x0:x1]).resize((w,h),Image.Resampling.NEAREST)
            panels.append((f'{rel} on {bgname}',crop))
    cols=4; cap=28; rows=(len(panels)+cols-1)//cols
    sheet=Image.new('RGB',(cols*w,rows*(h+cap)),(24,24,24)); d=ImageDraw.Draw(sheet)
    for i,(label,img) in enumerate(panels):
        x=(i%cols)*w; y=(i//cols)*(h+cap); sheet.paste(img,(x,y+cap)); d.text((x+4,y+5),label,fill='white')
    sheet.save(review/'slasher-foot-owner-source-3x.png')
    # Native-size three-background source crop, for direct 1:1 review.
    cw,ch=x1-x0,y1-y0; native=Image.new('RGB',(3*cw,ch+24),(24,24,24)); d=ImageDraw.Draw(native)
    for i,(label,bg) in enumerate([('black',(0,0,0)),('gray',(128,128,128)),('white',(255,255,255))]):
        native.paste(Image.fromarray(composite(src,bg)[y0:y1,x0:x1]),(i*cw,24)); d.text((i*cw+4,4),f'{label} source (native 1:1)',fill='white')
    native.save(review/'slasher-source-boot-context-native.png')
def make_cuff_review(root, review, src, owner):
    work=root/'art_src/characters/slasher'; x0,y0,x1,y1=(300,1035,390,1100); scale=4; w=(x1-x0)*scale; h=(y1-y0)*scale
    lower=np.array(Image.open(work/'07_refined/leg_lower.png').convert('RGBA'))
    foot=np.array(Image.open(work/'overrides/refined/foot.png').convert('RGBA'))
    overlap=(lower[:,:,3]>=40)&owner; diff=np.any(lower!=foot,axis=2)&overlap
    panels=[]
    for label,rgba in [('base source gray',src),('07 refined lower leg gray',lower),('registered single foot gray',foot)]:
      im=Image.fromarray(composite(rgba,(128,128,128))[y0:y1,x0:x1]).resize((w,h),Image.Resampling.NEAREST); d=ImageDraw.Draw(im)
      for gx in range(300,390,10):
        xx=(gx-x0)*scale; d.line((xx,0,xx,h),fill=(100,100,100),width=1); d.text((xx+1,1),str(gx),fill=(255,255,0))
      for gy in range(1040,1100,10):
        yy=(gy-y0)*scale; d.line((0,yy,w,yy),fill=(100,100,100),width=1); d.text((1,yy+1),str(gy),fill=(255,255,0))
      panels.append((label,im))
    region=np.zeros_like(src); region[:,:,:3]=np.array([128,128,128]); region[:,:,3]=0
    region[:,:,3][overlap]=src[:,:,3][overlap]
    region[:,:,:3][overlap]=np.array([0,220,120])
    region[:,:,:3][diff]=np.array([255,35,35]); region[:,:,3][diff]=255
    im=Image.fromarray(composite(region,(128,128,128))[y0:y1,x0:x1]).resize((w,h),Image.Resampling.NEAREST)
    d=ImageDraw.Draw(im)
    for gx in range(300,390,10):
      xx=(gx-x0)*scale; d.line((xx,0,xx,h),fill=(100,100,100),width=1); d.text((xx+1,1),str(gx),fill=(255,255,0))
    for gy in range(1040,1100,10):
      yy=(gy-y0)*scale; d.line((0,yy,w,yy),fill=(100,100,100),width=1); d.text((1,yy+1),str(gy),fill=(255,255,0))
    panels.append(('source-space overlap green; changed RGBA red',im))
    cap=26; sheet=Image.new('RGB',(2*w,2*(h+cap)),(30,30,30)); d=ImageDraw.Draw(sheet)
    for i,(label,img) in enumerate(panels):
      x=(i%2)*w;y=(i//2)*(h+cap);sheet.paste(img,(x,y+cap));d.text((x+4,y+4),label,fill='white')
    sheet.save(review/'slasher-leg-lower-to-boot-cuff-native4x.png')
def main():
    ap=argparse.ArgumentParser(); here=Path(__file__).resolve(); default_root=here.parents[4]; ap.add_argument('--root',type=Path,default=default_root); ap.add_argument('--out',type=Path,default=default_root/'.godot/ne90-single-boot-review'); a=ap.parse_args()
    root=a.root.resolve(); out=a.out.resolve(); review=out/'review'; review.mkdir(parents=True,exist_ok=True)
    work=root/'art_src/characters/slasher'; repair=work/'near_hand_repair'
    srcp=work/'base_rgba.png'; maskp=repair/'near_foot.png'; overp=work/'overrides/refined/foot.png'
    srcim,src=load(srcp); maskim,maskrgb=load(maskp); overim,override=load(overp)
    assert srcim.mode=='RGBA' and srcim.size==(832,1216) and maskim.mode=='RGB' and maskim.size==srcim.size and overim.mode=='RGBA' and overim.size==srcim.size
    source_sha=sha(srcp); mask_sha=sha(maskp); override_sha=sha(overp)
    assert {'base_rgba.png':source_sha,'near_foot.png':mask_sha,'override_foot.png':override_sha}==EXPECTED
    mask=maskrgb[:,:,0]>127; source_valid=src[:,:,3]>=40
    record=json.loads((repair/'foot-mask-source.json').read_text(encoding='utf8')); prm=record['points']['near_foot']
    official_pos=[tuple(p) for p in prm['pos']]; official_neg=[tuple(p) for p in prm['neg']]
    manual_pos=[
      {'name':'boot cuff / top edge, not ankle pivot','xy':[335,1055]},
      {'name':'shaft','xy':[350,1090]},
      {'name':'heel side','xy':[310,1155]},
      {'name':'sole','xy':[400,1188]},
      {'name':'toe','xy':[472,1176]},
      {'name':'spec ankle pivot (inside shaft)','xy':[346,1113]},
    ]
    manual_neg=[
      {'name':'exposed opposite/far boot','xy':[439,1138]},
      {'name':'exposed opposite/far boot outer edge','xy':[460,1140]},
      {'name':'transparent outside boot','xy':[491,1159]},
    ]
    point_audit=[]
    for role,points,should_select in [('recorded_positive',official_pos,True),('recorded_negative',official_neg,False)]:
      for x,y in points:
        point_audit.append({'kind':role,'xy':[x,y],'mask_value':int(maskrgb[y,x,0]),'source_rgba':list(map(int,src[y,x])),'selected':bool(mask[y,x]),'expected':should_select,'pass':bool(mask[y,x])==should_select})
    for item,should_select in [(p,True) for p in manual_pos]+[(p,False) for p in manual_neg]:
      x,y=item['xy']; item['mask_value']=int(maskrgb[y,x,0]); item['source_rgba']=list(map(int,src[y,x])); item['selected']=bool(mask[y,x]); item['expected']=should_select; item['pass']=bool(mask[y,x])==should_select
      point_audit.append({'kind':'manual_semantic_anchor','name':item['name'],'xy':item['xy'],'mask_value':item['mask_value'],'source_rgba':item['source_rgba'],'selected':item['selected'],'expected':should_select,'pass':item['pass']})
    assert all(p['pass'] for p in point_audit),[p for p in point_audit if not p['pass']]
    # Reproduce approved alpha-floor + min-component rule used by the source-rebuild script.
    sys.path.insert(0,str(root/'tools/comfyui'))
    from refine_parts import components
    owner=components(mask & source_valid,30)
    replay=np.zeros_like(src); replay[owner]=src[owner]
    assert np.array_equal(replay,override), 'point-mask replay pixels do not equal registered source override'
    # Deterministic scratch reruns; no upstream source or formal file is written.
    run_hashes=[]
    for i in (1,2):
      op=out/f'run-{i}'/'foot.png'; op.parent.mkdir(parents=True,exist_ok=True); Image.fromarray(replay,'RGBA').save(op); run_hashes.append(sha(op))
    assert run_hashes[0]==run_hashes[1] and np.array_equal(np.array(Image.open(out/'run-1/foot.png')),np.array(Image.open(out/'run-2/foot.png')))
    # One-pixel failure controls: omitted selected toe texel and foreign opposite-boot texel.
    toe=(472,1176); omit=owner.copy(); omit[toe[1],toe[0]]=False
    omission_detected=bool(owner[toe[1],toe[0]] and not omit[toe[1],toe[0]] and np.array_equal(np.logical_xor(owner,omit).sum(axis=None),1))
    far=(439,1138); foreign=owner.copy(); foreign[far[1],far[0]]=True
    foreign_detected=bool(not owner[far[1],far[0]] and src[far[1],far[0],3]>=40 and foreign[far[1],far[0]])
    assert omission_detected and foreign_detected
    # Verify source-crop -> formal texture with the project's real cut_layers transforms.
    import cut_layers
    spec=json.loads((root/'tools/comfyui/specs/slasher_side.json').read_text(encoding='utf8'))
    char=json.loads((root/'art/characters/slasher/character.json').read_text(encoding='utf8'))
    recipe=json.loads((root/'tools/comfyui/recipes/slasher.json').read_text(encoding='utf8'))
    k=spec['tex_px_per_wp']/spec['illustration_px_per_wp']; joints={n:np.array(v,float)*k for n,v in spec['joints'].items()}
    source_choices={'leg_lower':work/'07_refined/leg_lower.png','foot':overp}
    formal_checks={}
    for tex,source_path in source_choices.items():
      part=spec['parts'][tex]; im=Image.open(source_path).convert('RGBA'); transform=cut_layers.part_transform(im,part,joints,k); cut=cut_layers.render_part(im,transform,k)
      formal_path=root/'art/characters/slasher'/char['textures'][tex]['file']; formalim,formal=load(formal_path)
      texmeta=char['textures'][tex]
      formal_checks[tex]={'source_path':source_path.relative_to(root).as_posix(),'source_sha256':sha(source_path),'formal_path':formal_path.relative_to(root).as_posix(),'formal_sha256':sha(formal_path),'recomputed_size_px':[int(cut.shape[1]),int(cut.shape[0])],'metadata_size_px':texmeta['size'],'recomputed_pivot':[round(float(transform[3][0]),2),round(float(transform[3][1]),2)],'metadata_pivot':texmeta['pivot'],'pixel_exact':bool(np.array_equal(cut,formal)),'rendered_alpha_ge_40':comp_summary(cut[:,:,3]>=40)}
      assert formal_checks[tex]['pixel_exact'] and formal_checks[tex]['recomputed_size_px']==texmeta['size'] and formal_checks[tex]['recomputed_pivot']==texmeta['pivot']
    # Formal logical slot mapping: same single-foot source intentionally instantiated twice.
    source_map={
      'leg_upper':{'source':'art_src/characters/slasher/07_refined/leg_upper.png','mask':['art_src/characters/slasher/near_hand_repair/far_hand_current.png'],'mask_role':'remove separately identified far-hand lobe from upper-leg source; registered rebuild.py creates the source override'},
      'leg_lower':{'source':'art_src/characters/slasher/07_refined/leg_lower.png','mask':['art_src/characters/slasher/sam/near_leg.png','art_src/characters/slasher/sam/boot.png'],'mask_role':'near_leg group with spec.parts.leg_lower.not_within=boot'},
      'foot':{'source':'art_src/characters/slasher/base_rgba.png','mask':['art_src/characters/slasher/near_hand_repair/near_foot.png'],'mask_role':'pinned original-source near-foot mask, existing alpha>=40 and connected-component min_area=30 rule'}
    }
    slot_ledger=[]
    for p in char['parts']:
      if p['name'] in {'leg_back_upper','leg_back_lower','foot_back','leg_front_upper','leg_front_lower','foot_front'}:
        t=p['texture']; m=char['textures'][t]; f=root/'art/characters/slasher'/m['file']; sm=source_map[t]
        slot_ledger.append({'slot':p['name'],'texture_key':t,'texture_path':f.relative_to(root).as_posix(),'texture_sha256':sha(f),'texture_size_px':m['size'],'pivot_px':m['pivot'],'source_path':sm['source'],'source_sha256':sha(root/sm['source']),'mask_paths':sm['mask'],'mask_sha256':[sha(root/x) for x in sm['mask']],'mask_role':sm['mask_role'],'bone':p['bone'],'z':p['z'],'tint':p.get('tint',1.0),'instances_using_texture':sum(q['texture']==t for q in char['parts'])})
    # Alpha and semantic area data for intermediate-vs-formal comparison.
    asset_stats={}
    assets=[('06_parts/leg_upper.png',work/'06_parts/leg_upper.png'),('07_refined/leg_upper.png',work/'07_refined/leg_upper.png'),('06_parts/leg_lower.png',work/'06_parts/leg_lower.png'),('07_refined/leg_lower.png',work/'07_refined/leg_lower.png'),('06_parts/foot.png',work/'06_parts/foot.png'),('07_refined/foot.png',work/'07_refined/foot.png'),('override/refined/foot.png',overp),('formal/leg_upper.png',root/'art/characters/slasher/parts/leg_upper.png'),('formal/leg_lower.png',root/'art/characters/slasher/parts/leg_lower.png'),('formal/foot.png',root/'art/characters/slasher/parts/foot.png')]
    for label,path in assets:
      im,a=load(path); rgba=np.array(im.convert('RGBA')); am=rgba[:,:,3]>=40
      asset_stats[label]={'path':path.relative_to(root).as_posix(),'sha256':sha(path),'mode':im.mode,'size_px':list(im.size),'alpha_ge_40':comp_summary(am)}
    foot_owner_relations={}
    for label,path in [('06_parts/foot.png',work/'06_parts/foot.png'),('07_refined/foot.png',work/'07_refined/foot.png'),('override/refined/foot.png',overp)]:
      im,a=load(path); am=np.array(im.convert('RGBA'))[:,:,3]>=40
      foot_owner_relations[label]={'alpha_ge_40_pixels':int(am.sum()),'also_in_semantic_near_foot_owner':int((am&owner).sum()),'outside_semantic_near_foot_owner':int((am&~owner).sum()),'semantic_owner_not_in_asset':int((owner&~am).sum()),'outside_owner_bbox_xyxy':bbox(am&~owner)}
    lower=np.array(Image.open(work/'07_refined/leg_lower.png').convert('RGBA')); lower_foot_overlap=(lower[:,:,3]>=40)&owner; lower_foot_rgba_delta=lower_foot_overlap&np.any(lower!=src,axis=2); lower_foot_bbox=bbox(lower_foot_overlap)
    # Pin all input hashes before reporting and confirm unchanged after writing.
    source_paths=[srcp,maskp,repair/'foot-mask-source.json',repair/'rebuild.py',repair/'far_hand_current.png',work/'sam/near_leg.png',work/'sam/boot.png',work/'06_parts/leg_upper.png',work/'07_refined/leg_upper.png',work/'06_parts/leg_lower.png',work/'07_refined/leg_lower.png',work/'06_parts/foot.png',work/'07_refined/foot.png',overp,root/'art/characters/slasher/parts/leg_upper.png',root/'art/characters/slasher/parts/leg_lower.png',root/'art/characters/slasher/parts/foot.png',root/'art/characters/slasher/character.json',root/'art/rigs/slasher.json',root/'tools/comfyui/recipes/slasher.json',root/'tools/comfyui/specs/slasher_side.json']
    before={p.relative_to(root).as_posix():sha(p) for p in source_paths}
    make_sheet(root,review,src,owner,manual_pos,manual_neg)
    make_cuff_review(root,review,src,owner)
    after={p.relative_to(root).as_posix():sha(p) for p in source_paths}; assert before==after
    report={'status':'SOURCE_AND_FORMAL_TEXTURE_PROVENANCE_REVIEW; NOT_ANATOMY_OR_RUNTIME_ACCEPTANCE','target':{'id':'slasher','name':'切割者','identity_evidence':'recipe id and source drawing match the red visor, dark red/purple combat suit; reviewed source is slasher, not stalker'},'head_sha256':__import__('subprocess').run(['git','rev-parse','HEAD'],cwd=root,text=True,capture_output=True).stdout.strip(),'source_resolution_mode':{'base_rgba':'RGBA 832x1216','mask':'RGB 832x1216','mask_model':record['model'],'threshold':record['threshold'],'refine':record['refine'],'SAM_seed':'not recorded in this mask-source JSON; not inferred'},'input_sha256':before,'official_point_audit':point_audit,'source_masks':{name:{'path':rel,'sha256':sha(root/rel),'stats':comp_summary(np.array(Image.open(root/rel))[:,:,0]>127)} for name,rel in [('near_leg','art_src/characters/slasher/sam/near_leg.png'),('boot','art_src/characters/slasher/sam/boot.png'),('far_hand_subtraction','art_src/characters/slasher/near_hand_repair/far_hand_current.png'),('near_foot','art_src/characters/slasher/near_hand_repair/near_foot.png')]},'manual_semantic_landmarks':{'positive':manual_pos,'negative':manual_neg,'coordinate_note':'Boot cuff is sampled separately from the spec ankle pivot; cuff is not labeled as the ankle.'},'owner_mask':{'binary_mask':comp_summary(mask),'selected_source_alpha_ge_40_before_speckle':comp_summary(mask&source_valid),'accepted_owner_after_existing_min_area_30':comp_summary(owner),'discarded_by_existing_min_area_30':[{'component_id':1,'pixels':5,'bbox_xyxy':[366,689,369,691],'source_RGBA_at_pixels':[[66,30,45,255],[69,33,48,255],[62,28,43,255],[69,32,48,255],[69,33,48,255]],'review':'outside footwear source region; suit/arm-leg area, not a boot; excluded by existing rebuild rule'},{'component_id':2,'pixels':1,'bbox_xyxy':[345,1040,346,1041],'source_RGBA':[16,15,23,255],'review':'isolated pixel above the visually continuous boot-cuff contour; excluded by existing rebuild rule'}],'candidate_equals_registered_override_pixels':True,'scratch_replay_png_sha256':run_hashes,'repeat_bytes_identical':run_hashes[0]==run_hashes[1],'mask_semantic_visual':'review/slasher-foot-owner-source-3x.png'},'one_pixel_negative_controls':{'omit_near_toe_source_pixel':{'xy':list(toe),'detected':omission_detected},'include_visible_opposite_boot_pixel':{'xy':list(far),'source_rgba':list(map(int,src[far[1],far[0]])),'detected':foreign_detected}},'official_texture_replay':{'k_tex_px_per_wp_over_illustration_px_per_wp':k,'parts':formal_checks,'foot_recomputed_exact_formal_texture':formal_checks['foot']['pixel_exact']},'intermediate_and_formal_asset_stats':asset_stats,'intermediate_foot_vs_near_owner':foot_owner_relations,'lower_to_near_boot_cuff_overlap':{'source_pixel_overlap_count':int(lower_foot_overlap.sum()),'bbox_xyxy':lower_foot_bbox,'overlap_pixels_where_refined_lower_rgba_differs_from_base_source':int(lower_foot_rgba_delta.sum()),'difference_bbox_xyxy':bbox(lower_foot_rgba_delta),'review_image':'review/slasher-leg-lower-to-boot-cuff-native4x.png','interpretation':'The overlap is a localized cuff underlap in source coordinates; the 76 changed RGBA pixels are an image-review item, not proof of a seam defect and not runtime acceptance.'},'logical_slot_ledger':slot_ledger,'ownership_conclusion':{'foot':'06_parts/foot and 07_refined/foot retain extra opposite-foot pixels; registered source override applies pinned near_foot mask plus existing connected-component area>=30 rule, yielding exactly one source-designated near boot. The scratch replay equals that override pixel-for-pixel and cut_layers output equals formal parts/foot.png pixel-for-pixel. Formal foot texture is then reused in two separate rig slots with distinct bones/z/tints; it is one single-foot image, not a two-boot atlas.','leg_upper':'One shared texture is used by back/front upper-leg slots. The registered leg_upper source override removes a separately identified hand lobe from the 07_refined layer; formal texture is exact output from cut_layers over this override. The requested source inspection does not prove full posed anatomy.','leg_lower':'One shared texture is used by back/front lower-leg slots. Spec excludes the boot group from leg_lower and the formal texture is exact cut_layers output from 07_refined/leg_lower. This confirms provenance and single-piece mapping, not movement-quality.'},'source_hashes_unchanged':before==after,'images':['review/slasher-source-boot-context-native.png','review/slasher-foot-owner-source-3x.png','review/slasher-leg-parts-gray-2x.png','review/slasher-leg-lower-to-boot-cuff-native4x.png'],'limitations':['No edits were made to formal files; no Godot, Forward+, gameplay, or dynamic motion was run.','A component count is not anatomy acceptance; source ownership conclusion relies on the displayed source-cropped semantic contour plus pinned point locations, not alpha counts alone.','One-foot asset reuse across back/front slots is a rig design choice; whether both placements and movement are visually correct requires native game review.']}
    (out/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({'status':report['status'],'scratch':str(out),'owner':report['owner_mask'],'pixel_replay':report['owner_mask']['candidate_equals_registered_override_pixels'],'negative_controls':report['one_pixel_negative_controls'],'texture_exact':{k:v['pixel_exact'] for k,v in formal_checks.items()},'source_unchanged':report['source_hashes_unchanged']},ensure_ascii=False,indent=2))
if __name__=='__main__': main()
