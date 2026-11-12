"""Offline NE272 review: SHA/PNG/CI/source identity and actual pulse trajectories."""
from pathlib import Path
import argparse, hashlib, io, json, re, zipfile
from PIL import Image

def verify(root, semantic_fault=None):
    index=json.loads((root/"evidence-index.json").read_text(encoding="utf-8"))
    outer=json.loads((root/"raw-index.json").read_text(encoding="utf-8"))
    raw=(root/"raw.zip").read_bytes()
    assert hashlib.sha256(raw).hexdigest()==outer["sha256"] and len(raw)==outer["bytes"]
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        assert z.testzip() is None
        members=json.loads(z.read("members.json"))
        def read(path):
            row=members[path]
            data=z.read("objects/"+row["sha256"])
            assert len(data)==row["bytes"] and hashlib.sha256(data).hexdigest()==row["sha256"],path
            # Reader self-tests alter only a decoded in-memory counterexample after
            # checking the original bytes. They never rewrite source/engine receipts.
            if semantic_fault=="crouch-no-flight" and path=="attempts/crouch-v4/result.json":
                bad=json.loads(data)
                for step in bad["steps"]: step["pulses"]=[]
                data=json.dumps(bad).encode()
            if semantic_fault=="shield-no-callback" and path=="attempts/shield-v4/result.json":
                bad=json.loads(data);bad["blocks"]=[];bad["reflects"]=[]
                data=json.dumps(bad).encode()
            if semantic_fault=="jump-grounded" and path=="attempts/jump-v4/result.json":
                bad=json.loads(data)
                for step in bad["steps"]:
                    step["on_floor"]=True
                    step["hurtbox"][1]=278.2
                data=json.dumps(bad).encode()
            return data
        for path in members: read(path)
        source_count=0
        for row in index["sources"]:
            for tag,version in row["versions"].items():
                if version is None: continue
                data=read("review/"+version["path"])
                assert len(data)==version["bytes"] and hashlib.sha256(data).hexdigest()==version["sha256"]
            assert row["versions"]["published"] is not None
            assert row["ci_equals_published"] and row["versions"]["ci"]["sha256"]==row["versions"]["published"]["sha256"]
            source_count+=1
        assert source_count==66
        for picture in index["images"]:
            path="source/published/"+picture["path"]
            data=read("review/"+path)
            assert hashlib.sha256(data).hexdigest()==picture["sha256"]
            with Image.open(io.BytesIO(data)) as im: assert list(im.size)==picture["size"]==[1280,720] and im.mode=="RGBA"
            assert read("review/source/initial/"+picture["path"])==data
        log=read("review/ci/job-130838550773.log").decode("utf-8")
        assert hashlib.sha256(log.encode()).hexdigest()=="cb4f2838c709130f035fb4eee958b02165ccba296b9e20bb906d3fd1fef0c162"
        plans={int(m[1]):re.findall(r"\b(?:[A-Za-z0-9_]+Suite|main)\b",m[2]) for m in re.finditer(r"process (\d+) \(estimated \d+ s\): ([^\r\n]+)",log)}
        assert set(plans)==set(range(6)) and sum(map(len,plans.values()))==88 and len(set(sum(plans.values(),[])))==88
        assert "Chapter3EnemiesSuite" in plans[4]
        assert "checks: 98797, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 660 s)" in log
        meta=json.loads(read("review/ci/run.json"))
        assert meta["databaseId"]==43114416692 and meta["headSha"]==index["refs"]["ci"] and meta["conclusion"]=="success"
        expected={"pump":[("insulation_inspector",52,15),("pump_inspector",28,19),("pump_inspector",44,19)],"mezzanine":[("insulation_inspector",46,16),("pump_inspector",52,19)],"gate_hall":[("janus",36,19)]}
        for ident,record in index["maps"].items():
            doc=json.loads(read("review/source/published/data/levels/ch3_"+ident+"_map.json"))
            rows=["".join(seg[y] for seg in doc["segments"]) for y in range(len(doc["segments"][0]))]
            chars={"Ж":"pump_inspector","Ш":"insulation_inspector","Ю":"janus"}
            found=[(chars[c],x,y) for y,row in enumerate(rows) for x,c in enumerate(row) if c in chars]
            assert sorted(found)==sorted(expected.get(ident,[])),ident
            assert record["repair_grid_equals_published"] and record["ci_grid_equals_published"]
        design=json.loads(read("review/source/published/data/levels/ch3_design.json"))
        for area in ["pump","mezzanine"]:
            for encounter in design["areas"][area]["encounters"]:
                assert not encounter["lock"] and not encounter["wave_zone"]
                assert len(encounter["members"])<=3 and encounter["members"].count("抽水巡檢器")<=1 and encounter["members"].count("絕緣巡檢器")<=1
        outcomes=[];profiles=set();final_producer=set()
        for case in ["standing","crouch","shield","jump"]:
            prefix="attempts/"+case+"-v4/"
            receipt=json.loads(read(prefix+"exit.json")); result=json.loads(read(prefix+"result.json"))
            assert receipt["exit"]==0 and receipt["passed"] and not receipt["diagnostics"]
            assert receipt["before"]==receipt["after"] and receipt["sources_unchanged"] and receipt["c_sources_unchanged"]
            c_expected=json.loads(read(prefix+"c-context-expected.json"))["files"]
            assert len(c_expected)==364 and json.loads(read(prefix+"c-before.json"))==json.loads(read(prefix+"c-after.json"))==c_expected
            for p in receipt["published_matching_paths"]:
                data=read(prefix+"source/"+p)
                published=read("review/source/published/"+p)
                assert data==published and hashlib.sha256(data).hexdigest()==receipt["before"][p]
            final_producer.add(receipt["before"]["work/ne272-producer/probe.gd"])
            assert receipt["before"]["ui/codex_screen.gd"]=="cb3a1565146a0c87e7a9f878f90bbfed2204588671181f2b02ab2d88a5bd4c21"
            assert receipt["before"]["tests/suite/test_ui_screens.gd"]=="a9fd0603245471164596877092a0040b3ba3f770ecf4e1297069cc9340870c38"
            assert result["case"]==case and not result["headless_activation_culling_enabled"] and result["physics_ticks_per_second"]==60
            profiles.add(result["user_data_dir"])
            assert all(row["ok"] for row in result["checks"])
            assert len(result["pulses"])==1 and result["locked_frame"]==result["action_frame"]
            rows=result["steps"]
            assert all(b["physics"]>a["physics"] and b["process"]>a["process"] and b["msec"]>=a["msec"] for a,b in zip(rows,rows[1:]))
            assert any(r["fsm"]=="idle" for r in rows) and any(r["fsm"]=="charge" for r in rows) and any(r["fsm"]=="recover" for r in rows)
            pulse=[(r,p) for r in rows for p in r["pulses"] if p["team"]==1]
            assert pulse and len({p["id"] for r,p in pulse})==1
            assert all(abs(p["position"][1]-284.8)<0.001 and abs(p["velocity"][0]-520)<0.001 and p["velocity"][1]==0 and abs(p["radius"]-2.6)<0.001 for r,p in pulse)
            relevant=[(r,p) for r,p in pulse if r["hurtbox"][0]-p["radius"]<=p["position"][0]<=r["hurtbox"][0]+r["hurtbox"][2]+p["radius"]]
            if case=="standing":
                assert result["start_health"]==6 and result["end_health"]==5 and len(result["hits"])==1 and not result["blocks"] and not result["reflects"]
                assert result["hits"][0]["source"]=="insulation_pulse" and result["hits"][0]["projectile"]
            else:
                assert result["start_health"]==result["end_health"]==6 and not result["hits"]
                if case=="shield":
                    assert len(result["blocks"])+len(result["reflects"])==1 and result["end_guard"]<result["start_guard"]
                    assert (result["blocks"]+result["reflects"])[0]["source"]=="insulation_pulse"
                else:
                    assert min(p["position"][0] for r,p in pulse)<699.2 and max(p["position"][0] for r,p in pulse)>708.8
                    assert relevant,"no pulse samples actually cross the player's horizontal body"
                    if case=="crouch":
                        assert all(r["crouching"] and p["position"][1]+p["radius"]<r["hurtbox"][1] for r,p in relevant)
                    else:
                        assert all(not r["on_floor"] and p["position"][1]-p["radius"]>r["hurtbox"][1]+r["hurtbox"][3] for r,p in relevant)
            outcomes.append({"case":case,"checks":len(result["checks"]),"health":[result["start_health"],result["end_health"]],"guard":[result["start_guard"],result["end_guard"]],"pulse_crossing_samples":len(relevant)})
        assert len(profiles)==4 and len(final_producer)==1 and sum(r["checks"] for r in outcomes)==35
        # Original failed setup is kept as a failed setup, never a successful no-hit dodge.
        for tag in ["standing-v1","standing-culling-on-v2"]:
            r=json.loads(read("attempts/"+tag+"/exit.json"));j=json.loads(read("attempts/"+tag+"/result.json"))
            assert r["exit"]==1 and not r["passed"] and not r["diagnostics"] and not j["pulses"] and all(s["fsm"]=="idle" for s in j["steps"])
        return {"status":"passed", "source_paths":source_count,"ci_groups":88,"ci_total_checks":98797,"ci_per_suite_checks":None,"new_headless_checks":35,"new_headless_failures":0,"controls":outcomes,"virtual_files":len(members),"zip_members":len(z.namelist())}

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parent)
    args=parser.parse_args()
    print(json.dumps(verify(args.root),ensure_ascii=False,indent=2))
