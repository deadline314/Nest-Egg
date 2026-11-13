from pathlib import Path
import argparse,json,hashlib,copy
import numpy as np
from PIL import Image
SCENE="ch1_t_egret_1"

def digest(data):return hashlib.sha256(data).hexdigest()
def envelope(data):
    raw=json.loads(data.decode("utf8"));assert raw["version"]==1 and digest(raw["payload"].encode("utf8"))==raw["checksum"]
    return json.loads(raw["payload"])
def validate(old,new,spec):
    a,b=spec["cases"]["old"],spec["cases"]["new"]
    assert old["starts"]==1 and old["finishes"]==0 and old["talks"]==0 and old["heard"] is False
    assert new["starts"]==new["finishes"]==new["talks"]==1 and new["heard"] is True and new["pending_cleared"] is True
    assert old["source_id"]==a["source_id"] and old["cell"]==a["cell"] and old["context"]==old["saved_context"]==a["context"]
    assert new["source_id"]==b["source_id"] and new["cell"]==b["cell"] and new["context_during_resume"]==b["context"]
    assert old["scene"]==SCENE and old["credits"]==new["credits"]==17 and old["items"]==new["items"] and old["claimed"]==new["claimed"]==[]
    lines=new["read_lines"];assert len(lines)==len(b["lines"])
    for got,wanted in zip(lines,b["lines"]):
        assert got["where"]==wanted["where"] and got["text"]==wanted["text"] and got["name"]==wanted["name"] and got["complete"] is True and got["frame_alpha"]==1
    return {"actual_NPC_source_migrated":True,"one_completion":True,"seven_source_lines":len(lines),"reward_free_wallet_custody_unchanged":True}
def verify(root,spec):
    old=json.loads((root/"pending-old-proof.json").read_text(encoding="utf8"));new=json.loads((root/"pending-new-proof.json").read_text(encoding="utf8"));result=validate(old,new,spec)
    raw=(root/"pending-original.json").read_bytes();assert digest(raw)==old["slot_sha256"];before=envelope(raw);after=envelope((root/"slot.json").read_bytes())
    assert before["cinematic"]==SCENE and before["cinematic_context"]==spec["cases"]["old"]["context"]
    assert before["runtime"]["world"][old["source_id"]]["talks"]==0 and before["story"]["flags"]["ch1_heard_brief"] is False
    assert after["cinematic"]=="" and after["runtime"]["world"][new["source_id"]]["talks"]==1 and after["story"]["flags"]["ch1_heard_brief"] is True
    assert after["progression"]["credits"]==before["progression"]["credits"]==17 and after["story"]["items"]==before["story"]["items"]
    meta=json.loads((root/"pending-first-line.json").read_text(encoding="utf8"));assert meta["format"]==14 and meta["hdr_2d"] is True and meta["size"]==[1280,720] and meta["renderer"]=="forward_plus" and "9070" in meta["adapter"]
    assert meta["context"]==spec["cases"]["new"]["context"] and meta["actor_source"]==new["source_id"] and meta["text"]==spec["cases"]["new"]["lines"][0]["text"]
    raw=(root/"pending-first-line.rgbh").read_bytes();assert len(raw)==meta["bytes"]==5529600
    data=np.frombuffer(raw,dtype="<f2").reshape(720,1280,3).astype(float);assert np.isfinite(data).all()
    rgb=np.where(data<=.0031308,data*12.92,1.055*np.maximum(data,0)**(1/2.4)-.055);reference=np.dstack((np.clip(rgb,0,1),np.ones((720,1280))))
    with Image.open(root/"pending-first-line.png") as image:
        assert image.format=="PNG" and image.size==(1280,720)
        error=float(np.max(np.abs(np.asarray(image.convert("RGBA"),dtype=float)/255-reference)))
    assert error<=1/255+.00001
    return result|{"PNG_max_error":error,"scope":"arranged genuine NPC pending Main save/restore/completion, not natural chapter or configured money reward"}
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("root",type=Path);p.add_argument("--expected",type=Path,default=Path(__file__).with_name("expected.json"));args=p.parse_args();print(json.dumps(verify(args.root,json.loads(args.expected.read_text(encoding="utf8"))),indent=2))
