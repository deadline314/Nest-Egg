from pathlib import Path
import argparse,json,hashlib,zipfile,tempfile,copy
import numpy as np
from PIL import Image
OLD_SHA="a5be720fe21b3a95388a3b59d013034b051249b74fe2474dc436c3fea358d19d"
AREA="res://data/levels/ch1_warehouse.tres"

def digest(data):return hashlib.sha256(data).hexdigest()
def load(path):return json.loads(path.read_text(encoding="utf8"))
def envelope(raw):
    value=json.loads(raw.decode("utf8"));assert value["version"]==1 and isinstance(value["payload"],str)
    assert digest(value["payload"].encode("utf8"))==value["checksum"],"original envelope checksum"
    return json.loads(value["payload"])

def semantics(old,new,backup,expect,meta,layout):
    assert old["level"]==new["level"]==AREA and old["runtime"].get("layout_revision",1)==1 and new["runtime"]["layout_revision"]==2
    assert old["runtime"]["position"]==[1240,272] and new["runtime"]["position"]==meta["player"]==[72,784]
    assert old["state"]["checkpoint_position"]==[1240,272] and new["state"]["checkpoint_position"]==meta["checkpoint"]==[1240,784]
    assert old["runtime"]["health"]==new["runtime"]["health"]==4
    assert old["progression"]["credits"]==new["progression"]["credits"]==17
    assert old["story"]["items"]==new["story"]["items"] and len(new["story"]["items"]["held"])==3 and "ch1_data_disk" in new["story"]["items"]["held"]
    assert old["story"]["flags"]["ledger_disk_obtained"] is True and new["story"]["flags"]["ledger_disk_obtained"] is True
    assert new["runtime"]["loadout"]==old["runtime"]["loadout"]
    assert expect["runtime"]["position"]==old["runtime"]["position"] and expect["story"]["items"]==old["story"]["items"]
    # Independent interpretation of the authored legacy table; no Godot migration code executed.
    legacy=layout["legacy_layout"];assert legacy["revision"]==1 and layout["layout_revision"]==2
    def cell(x,y):return legacy.get("cells",{}).get(f"{x},{y}",[x+legacy["cell_offset"][0],y+legacy["cell_offset"][1]])
    def key(k,phone=False):
        prefix,coord=k.rsplit("@",1);x,y=map(int,coord.split(","));a,b=cell(x,y-1 if phone else y);return f"{prefix}@{a},{b+1 if phone else b}"
    for field in ["consumed","damage","world"]:
        assert new["runtime"]["area"]["layout_revision"]==2
        for k,v in old["runtime"]["area"][field].items():assert new["runtime"]["area"][field][key(k)]==v,(field,k)
    for k,v in old["runtime"]["world"].items():assert new["runtime"]["world"][key(k)]==v,k
    for k,v in old["navigation"]["explored"][AREA].items():
        x,y=map(int,k.split(","));x,y=cell(x,y);assert new["navigation"]["explored"][AREA][f"{x},{y}"]==v
    for k,v in old["navigation"]["activated"].items():assert new["navigation"]["activated"][key(k,True)]==v
    assert new["navigation"]["layout_revisions"][AREA]==2 and new["navigation"]==meta["navigation"]
    # Level._capture_run_enemies allocates enemy:index again for each snapshot.
    # These IDs link encounter members within one snapshot, not across later captures.
    for snapshot in [old,new]:
        entries=snapshot["runtime"]["enemies"];ids=[e["snapshot_id"] for e in entries]
        assert len(ids)==len(set(ids)) and all(isinstance(i,str) and i.startswith("enemy:") for i in ids)
        for encounter in snapshot["runtime"].get("encounters",{}).values():
            assert all(i in ids for i in encounter.get("members",[])), "local encounter member closure"
    before={key(e["key"]):e for e in old["runtime"]["enemies"]};after={e["key"]:e for e in new["runtime"]["enemies"]}
    assert len(before)==len(old["runtime"]["enemies"]) and len(after)==len(new["runtime"]["enemies"]) and before.keys()==after.keys()
    for durable,e in before.items():
        n=after[durable];assert (e["resource"],e["lost"])==(n["resource"],n["lost"]),durable
    assert backup["runtime"]["layout_revision"]==2,"retained .bak is a revised intermediate slot, not the original legacy bytes"
    return {"level":AREA,"checkpoint_before":[1240,272],"checkpoint_after":[1240,784],"runtime_safe_entry":[72,784],"health":4,"credits":17,"held_items":3,"durable_enemy_identities_preserved":len(before),"snapshot_ids_local_not_cross_capture":True,"legacy_bak_distinguished":True}

def image(raw,metadata,png):
    assert metadata["format"]==14 and metadata["hdr_2d"] is True and metadata["size"]==metadata["window"]==[1280,720]
    assert len(raw)==metadata["bytes"]==1280*720*3*2
    a=np.frombuffer(raw,dtype="<f2").reshape(720,1280,3).astype(float);assert np.isfinite(a).all()
    shown=np.where(a<=.0031308,a*12.92,1.055*np.maximum(a,0)**(1/2.4)-.055);shown=np.dstack((np.clip(shown,0,1),np.ones((720,1280))))
    with Image.open(png) as im:
        assert im.format=="PNG" and im.size==(1280,720)
        error=float(np.max(np.abs(np.asarray(im.convert("RGBA"),dtype=float)/255-shown)))
    assert error<=1/255+.00001,("gamma before quantization original pixel comparison",error)
    return error

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--require-official",action="store_true");args=parser.parse_args();root=Path(__file__).resolve().parent;index=load(root/"index.json")
    for name,expected in index["files"].items():assert digest((root/name).read_bytes())==expected,name
    for name,archive in index["archives"].items():
        data=(root/name).read_bytes();assert digest(data)==archive["sha256"] and len(data)==archive["bytes"]<90_000_000
        with zipfile.ZipFile(root/name) as z:
            assert z.testzip() is None and set(z.namelist())==set(archive["members"])
            for key,expected in archive["members"].items():
                data=z.read(key);assert len(data)==expected["bytes"] and digest(data)==expected["sha256"],key
    manifest=load(root/"candidate-manifest.json");assert len(manifest["owned11"])==11 and len(manifest["borrowed21"])==21
    with zipfile.ZipFile(root/"sources.zip") as z:
        for prefix,files in [("owned11",manifest["owned11"]),("borrowed-ne298-context21",manifest["borrowed21"])]:
            for name,expected in files.items():assert digest(z.read(prefix+"/"+name))==expected,name
        layout=json.loads(z.read("borrowed-ne298-context21/data/levels/ch1_warehouse_map.json"))
    with zipfile.ZipFile(root/"raw.zip") as z:
        oldraw=z.read("legacy/saved-original.json");assert digest(oldraw)==OLD_SHA
        old=envelope(oldraw);new=envelope(z.read("continued/slot.json"));backup=envelope(z.read("continued/slot.json.bak"));expect=json.loads(z.read("legacy/expect-original.json"));meta=json.loads(z.read("continued/continued.json"))
        result=semantics(old,new,backup,expect,meta,layout)
        error=image(z.read("continued/continued.rgbh"),meta,root/"continued.png")
    # Explicit negative controls against the independent semantic reader.
    count=1
    for field in ["health","credits","items","checkpoint","navigation","enemy-key","enemy-local-ID"]:
        bad=copy.deepcopy(new)
        if field=="health":bad["runtime"]["health"]=5
        elif field=="credits":bad["progression"]["credits"]=18
        elif field=="items":bad["story"]["items"]["held"].pop()
        elif field=="checkpoint":bad["state"]["checkpoint_position"][1]+=16
        elif field=="navigation":bad["navigation"]["explored"][AREA]={}
        elif field=="enemy-key":bad["runtime"]["enemies"][0]["key"]="wrong@0,0"
        else:bad["runtime"]["enemies"][0]["snapshot_id"]=bad["runtime"]["enemies"][1]["snapshot_id"]
        try:semantics(old,bad,backup,expect,meta,layout)
        except (AssertionError,KeyError):count+=1
        else:raise AssertionError("negative semantic accepted: "+field)
    damaged=json.loads(oldraw);damaged["payload"]+=" "
    try:envelope(json.dumps(damaged).encode("utf8"))
    except AssertionError:count+=1
    else:raise AssertionError("checksum corruption accepted")
    with zipfile.ZipFile(root/"evidence.zip") as z:
        for tag,expected in [("focused-v2",32),("focused-v3",34)]:
            review=json.loads(z.read(tag+"/independent-review.json"));receipt=json.loads(z.read(tag+"/receipt.json"));log=z.read(tag+"/engine.log").decode("utf8")
            warnings=[line for line in log.splitlines() if line.startswith("WARNING:")]
            assert review["checks"]==expected and review["failures"]==0 and review["accepted"] is True
            assert warnings==review["expected_warnings"]==receipt["diagnostics"] and receipt["accepted"] is False
            assert f"checks: {expected}, failures: 0" in log and "SCRIPT ERROR" not in log and "Parse Error" not in log
        for tag in ["cold-old-write-v3","cold-new-read-v1"]:
            receipt=json.loads(z.read(tag+"/receipt.json"));assert receipt["exit_code"]==0 and receipt["accepted"] and not receipt["diagnostics"] and receipt["all_four_queue_gates"] and receipt["source_exact"] and receipt["c_unchanged"]
            assert z.read(tag+"/source-before.json")==z.read(tag+"/source-after.json") and z.read(tag+"/c-before.json")==z.read(tag+"/c-after.json")
    official=False
    if (root/"official.json").exists():
        value=load(root/"official.json");assert value["accepted"] is True and digest((root/value["receipt"]).read_bytes())==value["sha256"];official=True
    if args.require_official:assert official,"formal union and second canonical cold read not yet provided"
    print(json.dumps({"portable_evidence_verified":True,"semantic":result,"PNG_max_error":error,"independent_semantic_controls":count,"owned":11,"borrowed_context":21,"official_accepted":official},indent=2))

if __name__=="__main__":main()
