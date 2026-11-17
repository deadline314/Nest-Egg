from pathlib import Path
import hashlib,json,statistics,struct,sys,zipfile
base=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent
manifest=json.loads((base/"manifest.json").read_text(encoding="utf8"))
archive=base/manifest["archive"]
assert archive.stat().st_size==manifest["bytes"]
assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest["sha256"]
with zipfile.ZipFile(archive) as z:
    assert len(z.namelist())==len(set(z.namelist())) and set(z.namelist())==set(manifest["members"])
    for name,record in manifest["members"].items():
        value=z.read(name)
        assert len(value)==record["bytes"] and hashlib.sha256(value).hexdigest()==record["sha256"],name
    def read(name): return json.loads(z.read(name))
    def png(name,size):
        value=z.read(name)
        assert value[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack(">II",value[16:24])==size,name
    for prefix in ["gallery-before-write-control","native","checks","fixture-cost","fixture-cost-v2"]:
        assert read(prefix+"/source-before.json")==read(prefix+"/source-after.json") if prefix!="fixture-cost" else True
    runs=read("native/runs.json")
    assert len(runs)==7 and [r["exit"] for r in runs]==[0,0,0,1,1,0,0]
    assert all(r["script_errors"]==0 and r["source_held"] for r in runs)
    for quality in ["low","medium","high"]:
        prefix="native/gallery-"+quality
        rows=read(prefix+"/observations.json")
        assert len(rows)==2 and [r["power"] for r in rows]==[1,0]
        for r in rows:
            assert r["hdr"] and r["environments"]==1 and len(r["lamps"])==23
            assert len(set(a["id"] for a in r["lamps"]))==14
            assert all(a["supported"] and a["light_enabled"]==bool(r["power"]) and a["glow_visible"]==bool(r["power"]) for a in r["lamps"])
        for mode in ["lit","unlit"]: png(prefix+"/lamps-"+mode+".png",(2515,1415))
    for quality in ["low","high"]:
        rows=read("native/tour-"+quality+"/audit.json")["records"]
        assert len(rows)==16 and sum(len(r["lamps"]) for r in rows if r["entry"]==0)==35
        for i in range(0,len(rows),2):
            a,b=rows[i:i+2]
            assert a["entry"]==0 and b["entry"]==1 and a["level"]==b["level"] and a["lamps"]==b["lamps"]
            assert len(a["lamps"])<2 or a["kinds"]>=2
            assert all(l["supported"] and l["id"] for l in a["lamps"])
            for index in range(len(a["lamps"])): png("native/tour-"+quality+"/"+a["level"]+"-"+str(index)+".png",(1280,720))
    first=read("gallery-before-write-control/result.json")
    assert first["exit"]==0 and first["write_error"] and first["images"]==["lamps-unlit.png"]
    for name in ["gallery-write-failure","gallery-unlit-write-failure"]:
        assert b"ERROR:" in z.read("native/"+name+"/raw.log")
    records=read("fixture-cost-v2/runs.json")
    assert len(records)==8 and all(r["exit"]==r["script_errors"]==0 and r["source_held"] and not r["godot_before"] and not r["godot_after"] for r in records)
    results=read("fixture-cost-v2/result.json")
    for quality in ["low","high"]:
        selected=[r for r in records if r["quality"]==quality]
        assert [r["mode"] for r in selected]==["fixtures","white-block","white-block","fixtures"]
        for index,level in enumerate(["ch1_street","ch1_warehouse","ch1_vault"]):
            groups={"fixtures":[],"white-block":[]};contracts=[]
            for r in selected:
                prefix="fixture-cost-v2/"+quality+"-"+str(r["order"])+"-"+r["mode"]
                sample=read(prefix+"/samples.json")[index]
                assert sample["level"]==level and len(sample["samples_ms"])==180 and sample["active_actors"]==0 and sample["vsync"]==0 and sample["viewport"]==[1280,720]
                png(prefix+"/"+level+".png",(1280,720))
                groups[r["mode"]].append(statistics.median(sample["samples_ms"]))
                contracts.append([{k:v for k,v in lamp.items() if k!="body_visible"} for lamp in sample["lamps"]])
                assert all(l["body_visible"]==(r["mode"]=="fixtures") for l in sample["lamps"])
            assert all(c==contracts[0] for c in contracts)
            ratio=statistics.mean(groups["fixtures"])/statistics.mean(groups["white-block"])
            report=next(r for r in results["ratios"] if r["quality"]==quality and r["level"]==level)
            assert ratio==report["ratio"] and ratio<=1.05
    assert results["source_held"] and results["within_105_percent"]
    assert read("checks/result.json")["all_passed"]
    assert b"checks: 7663, new failures: 0, known failures" in z.read("checks/environment/raw.log")
    reused=read("reused-bg17/source-before.json")
    assert reused==read("reused-bg17/source-after.json") and read("reused-bg17/result.json")["all_original_thresholds_passed"]
    current=read("native/source-before.json")
    assert all(p in current for p in reused)
    assert [p for p in reused if reused[p]!=current[p]]==read("source-reuse.json")["differences"]
print("BG36_PACKET_PASS",len(manifest["members"]),"members; 14 fixtures / 23 mounts; 35 lamps twice per quality; 6 paired cost gates; 7663 checks")
