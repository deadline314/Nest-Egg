from pathlib import Path
import argparse,json
import numpy as np
from PIL import Image
from gallery_reader import decode,png_reference,projection_control
KEYS=["held-A1","held-A2","held-B","held-A3","released-HIGH","released-LOW","released-restored-HIGH"]

def states(rows):
    assert [r["key"] for r in rows]==KEYS, "all original held/release/quality phases"
    reference=rows[0]["stage_hold"]
    for i,row in enumerate(rows):
        h=row["stage_hold"]
        assert h["actor_canvas_layer"]==h["prop_canvas_layer"]==58, "real actor/prop same independent stage canvas"
        assert h["uses_world_context"] is False and h["fill"]==1 and 0<h["cap"]<=.5, "local context without world fill override"
        assert not h["actor_process"] and not h["actor_physics"] and len(h["parts"])>5, "real actor and visible parts frozen"
        assert all(not p["process"] and not p["physics"] and p["material_id"]==h["actor_material_id"] for p in h["parts"]), "every body has the same owned lit material"
        assert h["parts"]==reference["parts"] and h["actor_bounds"]==reference["actor_bounds"], "held actor actual part transforms remain fixed"
        assert h["prop_global_matrix"]==reference["prop_global_matrix"] and h["prop_texture_id"]==reference["prop_texture_id"], "hold/release/quality preserve actual prop geometry and texture"
        assert 0<=h["contact_error_world"]<=.25, "published hold contact tolerance"
        x,y,width,height=h["actor_roi"]
        assert x>=0 and y>=0 and width>0 and height>0 and x+width<=1280 and y+height<=720, "entire actor physical ROI on original frame"
        if i<4:
            assert h["held"] and h["bound_same_material"] and h["prop_material_id"]==h["actor_material_id"], "real hold binds exact actor material"
        else:
            assert not h["held"] and not h["bound_same_material"] and h["restored_original_material"] and h["restored_original_tint"] and h["prop_material_id"]==0, "real release restores original prop appearance"
        if row["key"]=="released-LOW":
            assert h["quality"]==0 and h["prop_normal_path"]=="", "LOW removes cached normal"
        else:
            assert h["quality"]==2 and h["prop_normal_path"].endswith("_n.png"), "HIGH restores actual cached normal"

def verify(root):
    m=json.loads((root/"capture.json").read_text(encoding="utf8"))
    assert m["renderer"]=="forward_plus" and m["display"]!="headless" and "9070" in m["adapter"]
    assert m["canvas_layer"]==58 and m["stage_light_range"]==[58,58]
    rows=m["frames"];states(rows)
    raws={};pixels={}
    for r in rows:
        assert r["window_mode"]==0 and r["window_size"]==r["raw_rid_image_size"]==[r["width"],r["height"]]==[1280,720]
        assert r["readback_supported"] and r["ui_complete"] and r["ui_frame_alpha"]==1
        data=(root/r["raw"]).read_bytes();a=decode(data,r);raws[r["key"]]=data;pixels[r["key"]]=a
        with Image.open(root/r["png"]) as image:
            assert image.format=="PNG" and image.size==(1280,720)
            delta=np.max(np.abs(np.asarray(image.convert("RGBA"),dtype=float)/255-png_reference(a)))
            assert delta<=1/255+.00001, "canonical encode of same original raw"
    assert raws["held-A1"]==raws["held-A2"]==raws["held-A3"], "held same-source A/A and light restoration exact"
    assert raws["released-HIGH"]==raws["released-restored-HIGH"], "cached quality restoration original raw exact"
    x,y,w,h=rows[0]["stage_hold"]["actor_roi"]
    assert np.any(pixels["held-A1"][y:y+h,x:x+w]!=pixels["held-B"][y:y+h,x:x+w]), "actual frozen actor/held light response"
    projection_control(m["objects"][0])
    return {"scope":"one controlled real Rin/physical kettle same-stage-canvas case only; not natural choreography/exposure/performance", "raw_exact_AABA":True,"release_restores_original":True,"LOW_HIGH_cached_normal_restoration":True,"contact_max_world":max(r["stage_hold"]["contact_error_world"] for r in rows),"frames":len(rows)}

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("root",type=Path);print(json.dumps(verify(p.parse_args().root),indent=2))
