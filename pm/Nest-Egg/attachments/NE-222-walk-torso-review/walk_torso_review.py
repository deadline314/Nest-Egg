from __future__ import annotations
import hashlib, json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path.cwd()
OUT=ROOT/'.godot/ne222-rin-walk-torso-review'
OUT.mkdir(parents=True,exist_ok=True)
FILES={
 'approved_fullbody':'art_src/characters/rin2/01_design/design_s33.png',
 'source_rgba':'art_src/characters/rin2/base_rgba.png',
 'refined_torso_source':'art_src/characters/rin2/07_refined/torso.png',
 'legacy_rin2_refined_jacket_not_runtime_source':'art_src/characters/rin2/07_refined/jacket.png',
 'worn_coat_rebuild':'art_src/characters/rin_worn_coat/rebuild.py',
 'worn_coat_manifest':'art_src/characters/rin_worn_coat/manifest.json',
 'worn_coat_generated_jacket_stage':'art_src/characters/rin_worn_coat/source/_gen/rin_worn_coat_J_0.png',
 'worn_coat_generated_jacket_job':'art_src/characters/rin_worn_coat/source/_gen/rin_worn_coat_J.job.json',
 'worn_coat_jacket_builder_input':'art_src/characters/rin_worn_coat/source/07_refined/jacket.png',
 'registered_jacket_override':'art_src/characters/rin2/overrides/refined/armor_jacket.png',
 'current_torso':'art/characters/rin/parts/torso.png',
 'current_torso_damage':'art/characters/rin/parts/torso_dmg.png',
 'current_jacket':'art/characters/rin/parts/armor_jacket.png',
 'current_jacket_hem':'art/characters/rin/parts/jacket_hem.png',
 'current_sleeve_upper':'art/characters/rin/parts/jacket_sleeve_upper.png',
 'current_sleeve_lower':'art/characters/rin/parts/jacket_sleeve_lower.png',
 'character':'art/characters/rin/character.json',
 'rig':'art/rigs/humanoid_tall.json',
 'motion':'art/motion/rin.json',
 'cut_spec':'tools/comfyui/specs/rin_side.json',
 'recipe':'tools/comfyui/recipes/rin.json',
}
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def loadjson(key): return json.loads((ROOT/FILES[key]).read_text(encoding='utf-8'))
char=loadjson('character'); rig=loadjson('rig'); motion=loadjson('motion'); spec=loadjson('cut_spec'); recipe=loadjson('recipe')
rig_bones={b['name']:b for b in rig['bones']}
part_by_name={p['name']:p for p in char['parts']}
source_spec=spec['parts']
selected_parts=['armor_torso','torso_dmg','armor_jacket','jacket_hem','head','jacket_sleeve_back_upper','jacket_sleeve_back_lower','jacket_sleeve_front_upper','jacket_sleeve_front_lower']
part_ids={p['name']:p for p in char['parts']}
selected_defs={k:part_ids[k] for k in selected_parts if k in part_ids}
source_joints=spec['joints']
# The game and cutscene both use the 150 px/s default reference in this build.
move=motion['move']; maxspeed=150.0; body_scale=float(char['scale']); walk_rows=[]
for label,speed,run_speed in [('game_slow_walk',30.0,150.0),('game_walk',70.0,150.0),('game_fast_walk',105.0,150.0),('game_full_speed',150.0,150.0)]:
    ratio=min(abs(speed)/run_speed,1.3); lean=move['chest_lean']*ratio*(1 if speed>=0 else -1)
    walk_rows.append({'case':label,'source_velocity_world_px_s':speed,'run_speed':run_speed,'speed_ratio':ratio,'chest_lean_rad':lean,'chest_lean_deg':math.degrees(lean),'body_scale':body_scale})
# Ch1 c14 stage move from x575 to x330 in 2.6s, actor scale 3.8; rig_body_scale 1.15.
cut_dist=575-330; cut_time=2.6; cut_actor_scale=3.8; cut_stage_velocity=cut_dist/cut_time; cut_rig_velocity=cut_stage_velocity/(cut_actor_scale*body_scale); cut_ratio=min(cut_rig_velocity/150.0,1.3); cut_lean=move['chest_lean']*cut_ratio
walk_rows.append({'case':'cutscene_ch1_c14_rin_walk_constant_segment','stage_distance_px':cut_dist,'duration_s':cut_time,'stage_velocity_px_s':cut_stage_velocity,'actor_scale':cut_actor_scale,'rig_body_scale':body_scale,'rig_input_velocity_px_s':cut_rig_velocity,'RigInput_run_speed_default_px_s':150.0,'speed_ratio':cut_ratio,'chest_lean_rad_without_inertia':cut_lean,'chest_lean_deg_without_inertia':math.degrees(cut_lean),'notes':'Excludes start/stop _lean inertia; computed from cutscene_actor.gd normalization.'})
# Annotate approved source with spec landmarks; diagnostic only; do not alter source.
source=Image.open(ROOT/FILES['approved_fullbody']).convert('RGBA')
canvas=Image.new('RGBA',source.size,(75,75,75,255)); canvas.alpha_composite(source)
d=ImageDraw.Draw(canvas)
for name in ['waist','neck','shoulder','hip']:
    x,y=source_joints[name]; color={'waist':'#00ffff','neck':'#ff4040','shoulder':'#ffe040','hip':'#40ff80'}[name]
    d.ellipse((x-6,y-6,x+6,y+6),outline=color,width=3)
    d.line((x-12,y,x+12,y),fill=color,width=2); d.line((x,y-12,x,y+12),fill=color,width=2)
    d.text((x+8,y-15),f'{name} {x},{y}',fill=color,stroke_width=2,stroke_fill='black')
canvas.save(OUT/'approved-s33-source-landmarks.png')
# Layered actual cut-part contact sheet on neutral white/gray backgrounds, without resizing input files.
entries=[]
for slot in selected_parts:
    part=part_ids.get(slot)
    if not part: continue
    tex=char['textures'].get(part['texture'])
    if not tex: continue
    f=ROOT/'art/characters/rin'/tex['file']
    if not f.exists(): continue
    im=Image.open(f).convert('RGBA')
    entries.append((slot,part,tex,im))
cell_w,cell_h=360,430
sheet=Image.new('RGB',(cell_w*3,cell_h*math.ceil(len(entries)/3)),(210,210,210))
draw=ImageDraw.Draw(sheet)
for i,(slot,part,tex,im) in enumerate(entries):
    x=(i%3)*cell_w; y=(i//3)*cell_h
    draw.rectangle((x+8,y+35,x+cell_w-8,y+cell_h-8),fill=(246,246,246))
    # show original-size inset, clipped only by the display cell, never resampled.
    px=x+(cell_w-im.width)//2; py=y+54+(cell_h-70-im.height)//2
    sheet.paste(im,(px,py),im)
    draw.text((x+10,y+10),f'{slot} | bone={part.get("bone")} | texture={part.get("texture")}',fill=(0,0,0))
    draw.text((x+10,y+cell_h-28),f'{im.width}x{im.height} pivot={tex.get("pivot")} scale={char.get("texture_scale")}',fill=(20,20,20))
sheet.save(OUT/'current-torso-jacket-parts-native-contact.png')
summary={
 'scope':'Private read-only diagnosis; no runtime/art/PM/Git/GPU writes.',
 'observed_head':__import__('subprocess').check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'files':{k:{'path':v,'sha256':sha(ROOT/v),'size_bytes':(ROOT/v).stat().st_size} for k,v in FILES.items()},
 'recipe_design_prompt':recipe['design']['prompt'],
 'design_size':recipe['design']['size'],'design_pick':recipe['design']['pick'],
 'source_joints':{k:source_joints[k] for k in ['waist','neck','shoulder','hip']},
 'character_scale':char['scale'],'texture_scale':char['texture_scale'],
 'motion':{'move':move,'inertia':motion['inertia'],'torso':motion['torso'],'look':motion['look']},
 'bone_rest':{k:rig_bones[k]['pos'] for k in ['hip','chest','neck','head','coat_1','coat_2']},
 'current_part_nodes':{k:{'texture':part_ids[k]['texture'],'bone':part_ids[k]['bone'],'z':part_ids[k].get('z'),'under':part_ids[k].get('under',False),'armor_order':part_ids[k].get('armor_order'),'root_attach':part_ids[k].get('root_attach',False),'bend_partner':part_ids[k].get('bend_partner')} for k in part_ids if k in selected_parts},
 'texture_records':{k:{'size':char['textures'][char['parts'][list(part_ids).index(k)]['texture']]['size'],'pivot':char['textures'][char['parts'][list(part_ids).index(k)]['texture']]['pivot']} for k in []},
 'walk_angle_estimates':walk_rows,
 'walk_angle_measurement_status':'Formula estimates from recorded motion/input values; not sampled from an executing Godot rig or native rendering.',
 'jacket_source_selection':{
  'recipe_registered_rebuild':'art_src/characters/rin_worn_coat/rebuild.py',
  'registered_rebuild_runs_before_cut_layers':True,
  'cut_layers_override_priority':'<work>/overrides/refined/<part>.png is selected before <work>/07_refined/<part>.png',
  'active_source_override':'art_src/characters/rin2/overrides/refined/armor_jacket.png',
  'active_source_override_sha256':sha(ROOT/'art_src/characters/rin2/overrides/refined/armor_jacket.png'),
  'registered_generation_source':'art_src/characters/rin_worn_coat/source/_gen/rin_worn_coat_J_0.png',
  'registered_generation_job':'art_src/characters/rin_worn_coat/source/_gen/rin_worn_coat_J.job.json',
  'job_seed':json.loads((ROOT/'art_src/characters/rin_worn_coat/source/_gen/rin_worn_coat_J.job.json').read_text(encoding='utf-8')).get('seed'),
  'legacy_lookalike_not_selected':'art_src/characters/rin2/07_refined/jacket.png',
  'runtime_cut':'art/characters/rin/parts/armor_jacket.png',
  'runtime_cut_sha256':sha(ROOT/'art/characters/rin/parts/armor_jacket.png'),
 },
 'animation_path_finding':{
  'gameplay':'PlayerVisual._physics_process copies Player velocity, Player.tuning.run_speed, facing and state to a persistent RigInput, then calls CharacterRig.animate(delta,input).',
  'cutscene':'CutsceneActor._process computes stage delta/(delta*abs(scale.x)*rig.body_scale()), maps pose=walk/run to input.velocity=(velocity.x,0), leaves RigInput.run_speed at its default 150, then calls the same CharacterRig.animate.',
  'cutscene_walker_animator':'CutsceneActor.setup requests animator_kind npc. NpcAnimator._is_npc_state returns false whenever velocity.length() >= 1, so moving cutscene actors delegate to HumanoidAnimator._body_pose; movement does not use NPC idle pose/life overlay.',
  'comparison':'Both are HumanoidAnimator while moving. At equal normalized local velocity and run_speed=150 their base chest_lean is the same. Differences can arise from velocity normalization/scale, player tuning, discrete acceleration/inertia, scene light/zoom, not a separate cutscene walking chest pose.'
 },
 'relevant_tests':['LocomotionSuite','AnimAuditSuite','CutsceneSuite (_test_walk_matches_stage_motion)','ChapterCutscenesSuite','RigMeshSuite (pose-part attachment plumbing only)'],
 'evidence_images':['approved-s33-source-landmarks.png','current-torso-jacket-parts-native-contact.png'],
}
# Exact metadata from selected nodes and textures.
summary['current_parts']={}
for slot in selected_parts:
    p=part_ids.get(slot)
    if not p: continue
    t=char['textures'][p['texture']]
    summary['current_parts'][slot]={'texture':p['texture'],'bone':p['bone'],'z':p.get('z'),'under':p.get('under',False),'armor_order':p.get('armor_order'),'root_attach':p.get('root_attach',False),'bend_partner':p.get('bend_partner'),'texture_size':t.get('size'),'pivot':t.get('pivot'),'texture_sha256':sha(ROOT/'art/characters/rin'/t['file'])}
(OUT/'walk-diagnosis.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'out':str(OUT),'s33_sha256':summary['files']['approved_fullbody']['sha256'],'current_torso_sha256':summary['files']['current_torso']['sha256'],'walk_angles':walk_rows,'parts':summary['current_parts']},ensure_ascii=False,indent=2))
