"""Independent NE285 ledger and raw archive verification; no Godot or third-party modules."""
import argparse, hashlib, json, math, struct, zipfile, tempfile, re
from pathlib import Path

def ledger(folder, retained, native=False):
    folder=Path(folder)
    receipt=json.loads((folder/"receipt.json").read_bytes())
    assert receipt["exit"]==0 and receipt["same_source"] and not receipt["diagnostics"]
    assert receipt["before"]==receipt["after"]
    data=json.loads((folder/"order-ledger.json").read_bytes())
    rows=data["events"]
    hits=[(i,x) for i,x in enumerate(rows) if x["event"]=="hit_confirmed_inside_hit_pass"]
    assert len(hits)==1, "requires one real formal hit observation"
    index,hit=hits[0]
    pre=next(x for x in reversed(rows[:index]) if not x["player_frozen"])
    post=next(x for x in rows[index+1:] if not x["player_frozen"])
    checks=0
    for key in ["player_physics","target_physics"]:
        for sample in [pre,post]:
            row=sample[key]
            assert row["body_space"]==row["expected_space"]!=0
            assert row["hurtbox_space"]==row["expected_space"]
            checks+=2
        row=hit[key]
        assert not row["body_can_process"] and not row["hurtbox_can_process"]
        assert row["body_in_space"]==retained and row["hurtbox_in_space"]==retained
        if retained:
            assert row["body_space"]==row["hurtbox_space"]==row["expected_space"]!=0
        else:
            assert row["body_space"]==row["hurtbox_space"]==0
        checks+=3
    stopped=[x for x in rows[index:] if x["player_frozen"] and x["order"]<post["order"]]
    assert stopped and all(math.isclose(x["animator_time"],hit["animator_time"],abs_tol=1e-9) for x in stopped)
    assert any(x["physics"]>hit["physics"] for x in stopped)
    checks+=2
    if native:
        assert data["display"]!="headless" and receipt["native"]
        drawn=[x for x in stopped if x["event"]=="frame_post_draw"]
        assert drawn, "requires actual rendered frozen frames"
        for x in drawn:
            for key in ["player_physics","target_physics"]:
                assert x[key]["hurtbox_point_query"], "actual frozen hurtbox must remain queryable"
                checks+=1
        pngs=list(folder.glob("*.png"));assert len(pngs)==1
        raw=pngs[0].read_bytes();assert raw[:8]==b"\x89PNG\r\n\x1a\n"
        size=struct.unpack(">II",raw[16:24]);assert size[0]>=1280 and size[1]>=720
        checks+=3
    return {"checks":checks,"hit_tick":hit["physics"],"pre_tick":pre["physics"],"thaw_tick":post["physics"],"retained":retained,"native":native,"fx_sha256":receipt["before"]["autoload/fx.gd"]}

def verify_package(root):
    root=Path(root);index=json.loads((root/"archive-index.json").read_bytes());checks=0
    for row in index:
        p=root/row["file"];assert p.stat().st_size==row["bytes"]
        assert hashlib.sha256(p.read_bytes()).hexdigest()==row["sha256"]
        with zipfile.ZipFile(p) as z: assert z.testzip() is None
        checks+=3
    for filename,prefix,retained,native in [("formal-contact-red.zip","red",False,False),("formal-contact-headless-green.zip","green",True,False),("formal-contact-native-green.zip","native",True,True)]:
        if not (root/filename).exists():
            assert not native, "final delivery requires native archive"
            continue
        with zipfile.ZipFile(root/filename) as z:
            r=json.loads(z.read(prefix+"/receipt.json"))
            for name,expected in r["before"].items():
                assert hashlib.sha256(z.read(prefix+"/source/"+name)).hexdigest()==expected
                checks+=1
            with tempfile.TemporaryDirectory() as td:
                for name in ["receipt.json","order-ledger.json"]:
                    (Path(td)/name).write_bytes(z.read(prefix+"/"+name))
                if native:
                    for name in z.namelist():
                        if name.startswith(prefix+"/") and name.endswith(".png") and name.count("/")==1:
                            (Path(td)/Path(name).name).write_bytes(z.read(name))
                checks+=ledger(td,retained,native)["checks"]
    manifest=json.loads((root/"final-source.json").read_bytes())
    with zipfile.ZipFile(root/"feel-controls.zip") as z:
        green=json.loads(z.read("green/receipt.json"));red=json.loads(z.read("negative/receipt.json"))
        assert green["exit"]==0 and red["exit"]==1
        assert green["before"]==green["after"]==manifest
        assert red["before"]==red["after"]
        assert red["before"]["autoload/fx.gd"]!=manifest["autoload/fx.gd"]
        assert all(red["before"][k]==v for k,v in manifest.items() if k!="autoload/fx.gd")
        for mode,receipt in [("green",green),("negative",red)]:
            for name,expected in receipt["before"].items():
                assert hashlib.sha256(z.read(mode+"/source/"+name)).hexdigest()==expected
                checks+=1
        assert b"checks: 829, new failures: 0" in z.read("green/process.log")
        assert b"checks: 829, new failures: 7" in z.read("negative/process.log")
        for mode in ["green","negative"]:
            assert b"SCRIPT ERROR" not in z.read(mode+"/logs/shard_0.log")
        checks+=9
    with zipfile.ZipFile(root/"official-affected-raw.zip") as z:
        candidate=json.loads(z.read("candidate.json"));done=json.loads(z.read("exit.json"))
        assert done["exit"]==0 and done["sources_unchanged"]
        assert done["source_after"]==candidate["source_sha256"] and len(done["source_after"])==12
        assert all(done["source_after"][name]==expected for name,expected in manifest.items())
        for name,expected in candidate["source_sha256"].items():
            assert hashlib.sha256(z.read("source/"+name)).hexdigest()==expected
            checks+=1
        full=z.read("full.log")
        assert b"Running 71 groups in 4 processes" in full
        assert b"checks: 93799, new failures: 0, known failures" in full
        filters=z.read("tools/test_filters.sh").decode("utf-8")
        def pattern(name):return re.compile(re.search('^'+name+'="(.*)"$',filters,re.M).group(1))
        allowed=[pattern(name) for name in ["EXPECTED_ERRORS","EXIT_DIAGNOSTICS","ENGINE_BUILD_NOTES"]]
        for shard in range(4):
            raw=z.read(f"logs/shard_{shard}.log").decode("utf-8")
            assert "SCRIPT ERROR" not in raw
            unexpected=[line for line in raw.splitlines() if (line.startswith("ERROR:") or "Parse Error" in line) and not any(p.search(line) for p in allowed)]
            assert not unexpected, unexpected
            checks+=2
        checks+=5
    return checks

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("folder");p.add_argument("--ledger",choices=["red","green","native"]);a=p.parse_args()
    print(json.dumps(ledger(a.folder,a.ledger!="red",a.ledger=="native") if a.ledger else {"checks":verify_package(a.folder),"failures":0},indent=2))
