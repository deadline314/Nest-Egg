"""Offline Codex v5 evidence validation, independent numeric geometry checks."""
from pathlib import Path
import argparse,hashlib,io,json,re,zipfile
from PIL import Image
FINAL=["native-cb3a-720-clean-v2","native-cb3a-1080-scale12-clean-v2"]
PRODUCT="cb3a1565146a0c87e7a9f878f90bbfed2204588671181f2b02ab2d88a5bd4c21"
TEST="a9fd0603245471164596877092a0040b3ba3f770ecf4e1297069cc9340870c38"
def digest(b):return hashlib.sha256(b).hexdigest()
def enclosed(outer,inner,margin=0):
    return inner[0]>=outer[0]-margin and inner[1]>=outer[1]-margin and inner[0]+inner[2]<=outer[0]+outer[2]+margin and inner[1]+inner[3]<=outer[1]+outer[3]+margin
def mapped(rect,t):
    xs=[];ys=[]
    for x,y in [(rect[0],rect[1]),(rect[0]+rect[2],rect[1]),(rect[0],rect[1]+rect[3]),(rect[0]+rect[2],rect[1]+rect[3])]:
        xs.append(t[0]*x+t[2]*y+t[4]);ys.append(t[1]*x+t[3]*y+t[5])
    return [min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]
def qualify(doc):
    assert set(doc["ports"])=={"8188","8189"}
    return all(p["status"]=="reachable" and p["running"]==p["pending"]==0 or p["status"]=="connection_refused" and "10061" in p.get("error","") for p in doc["ports"].values())
def verify(root,fault=None):
    index=json.loads((root/"raw-index.json").read_text(encoding="utf-8"));raw=(root/"raw.zip").read_bytes()
    assert len(raw)==index["bytes"] and digest(raw)==index["sha256"]
    accepted=json.loads((root/"acceptance-index.json").read_text(encoding="utf-8"))
    manifest=json.loads((root/"candidate-manifest.json").read_text(encoding="utf-8"))
    assert manifest["formal_delta_paths"]==["ui/codex_screen.gd","tests/suite/test_ui_screens.gd"]
    assert accepted["native_final"]==FINAL and len(accepted["epochs"])==47
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        assert z.testzip() is None;members=json.loads(z.read("members.json"))
        def read(path):
            row=members[path];b=z.read("objects/"+row["sha256"])
            assert len(b)==row["bytes"] and digest(b)==row["sha256"],path
            if fault and path=="epochs/"+FINAL[0]+"/native-detail.json":
                j=json.loads(b);states={s["name"]:s for s in j["states"]}
                if fault=="wheel-snapback":states["manual-wheel"]["wall_scroll"]=states["manual-wheel"]["before_wheel"]
                elif fault=="resize-target-hidden":states["text-resize"]["target_rect"][1]+=100
                elif fault=="truncated-guide":states["longest-bottom"]["hint_text"]=states["longest-bottom"]["hint_text"][:-1]
                b=json.dumps(j).encode()
            return b
        for path in members:read(path)
        summaries=[]
        for tag,size,scale,selected in zip(FINAL,[[1280,720],[1920,1080]],[1.0,1.2],["720","1080-scale12"]):
            prefix="epochs/"+tag+"/"
            receipt=json.loads(read(prefix+"exit.json"));j=json.loads(read(prefix+"native-detail.json"))
            assert receipt["exit"]==0 and receipt["strict_clean"] and receipt["record_valid"] and not receipt["diagnostics"]
            assert receipt["sources_unchanged"] and receipt["before"]==receipt["after"] and receipt["c_sources_unchanged"]
            assert receipt["before"]["ui/codex_screen.gd"]==PRODUCT and receipt["before"]["tests/suite/test_ui_screens.gd"]==TEST
            c=json.loads(read(prefix+"c-context-expected.json"))["files"]
            assert len(c)==364 and json.loads(read(prefix+"c-before.json"))==json.loads(read(prefix+"c-after.json"))==c
            for name in ["queue-before.json","queue-after.json"]:assert qualify(json.loads(read(prefix+name)))
            assert j["passed"] and not j["failures"] and j["renderer"]=="forward_plus" and "9070 XT" in j["device"]
            assert j["requested_size"]==size and j["requested_text_scale"]==scale
            log=read(prefix+"run.log").decode("utf-8")
            assert "Forward+" in log and "Radeon RX 9070 XT" in log and not re.search(r"SCRIPT ERROR|^ERROR:|ObjectDB instances were leaked|resources still in use|RID allocations",log,re.M)
            for p,h in receipt["before"].items():
                source=prefix+"source/"+p
                if source in members:assert digest(read(source))==h
            cards=json.loads(read(prefix+"source/data/codex/defeat_cards.json"))["cards"]
            longest=max(cards,key=lambda c:len(c["hint"]))
            assert longest["id"]==j["longest_id"]=="ch1_inspector_contact" and len(longest["hint"])==j["longest_hint_length"]==62
            states={s["name"]:s for s in j["states"]}
            assert len(states)==8 and len(j["pictures"])==8
            for p in j["pictures"]:
                b=read(prefix+p["path"])
                assert digest(b)==p["sha256"] and (root/"images"/selected/p["path"]).read_bytes()==b
                with Image.open(io.BytesIO(b)) as im:assert list(im.size)==p["size"]==size and p["hdr_2d"]
            assert read(prefix+"last.png")==read(prefix+"returned-last.png")
            for state in states.values():
                assert state["actual_readback_size"]==state["window_property_size"]==state["display_server_native_window_size"]==size
                assert state["follow_focus"] and state["page_controls_enclosed"]
                for control in ["legend_rect","return_rect","detail_clip_rect"]:
                    assert enclosed(state["viewport_visible_rect"],state[control])
                    assert enclosed([0,0,*size],mapped(state[control],state["screen_transform"]),1)
            for name in ["first","last","longest-top","longest-bottom","returned-last","text-resize"]:
                s=states[name];assert s["target_has_focus"] and enclosed(s["wall_rect"],s["target_rect"],1),name
            top=states["longest-top"];bottom=states["longest-bottom"]
            assert top["hint_text"]==bottom["hint_text"]=="攻略　"+longest["hint"]
            overflow=bottom["reading_max"]>bottom["reading_page"]+1
            assert (not overflow or bottom["reading_scroll"]>0) and bottom["reading_scroll"]+bottom["reading_page"]>=bottom["reading_max"]-1
            assert bottom["hint_rect"][1]+bottom["hint_rect"][3]<=bottom["detail_clip_rect"][1]+bottom["detail_clip_rect"][3]+1
            assert bottom["hint_rect"][1]+bottom["hint_rect"][3]>bottom["detail_clip_rect"][1]
            assert states["returned-last"]["reading_scroll"]==0
            outside=states["outside-focus"];assert not outside["target_has_focus"] and outside["wall_scroll"]==states["returned-last"]["wall_scroll"]
            wheel=states["manual-wheel"];assert wheel["immediate_wheel"]>wheel["before_wheel"] and wheel["wall_scroll"]>=wheel["immediate_wheel"]
            assert enclosed(wheel["wall_rect"],[*wheel["event_point"],0,0]) and wheel["text_scale"]==1.0
            assert states["text-resize"]["text_scale"]==1.2
            # Cleanup/Return are original producer assertions and clean exit, not
            # a fabricated independently logged physical-button event.
            producer=read(prefix+"source/work/ne228-codex-focus-observer/native_detail.gd").decode()
            assert "back.pressed.emit()" in producer and "closed[0] and not is_instance_valid(screen)" in producer and "DefeatCodex.unlocked_ids() == previous" in producer
            summaries.append({"epoch":tag,"size":size,"initial_text_scale":scale,"pictures":8,"wheel":[wheel["before_wheel"],wheel["immediate_wheel"],wheel["wall_scroll"]],"last_enclosed":True,"full_longest_guide_at_end":True,"queue_before_after_empty":True})
        for tag,expected in zip(accepted["cpu_final"],[16,29]):
            prefix="epochs/"+tag+"/";r=json.loads(read(prefix+"exit.json"));o=json.loads(read(prefix+"observations.json"))
            assert r["exit"]==0 and not r["diagnostics"] and r["before"]==r["after"] and o["checks"]==expected and not o["failures"]
            assert r["before"]["ui/codex_screen.gd"]==PRODUCT and r["before"]["tests/suite/test_ui_screens.gd"]==TEST
        for tag,checks in [("detail-wheel-sort-hook-v11",14),("detail-wheel-nohook-ram-v11",27),("detail-gated-signature-120-30-v13",29)]:
            p="epochs/"+tag+"/";r=json.loads(read(p+"exit.json"));o=json.loads(read(p+"observations.json"))
            assert r["exit"]==1 and o["checks"]==checks and o["failures"]
        o=json.loads(read("epochs/detail-wheel-sort-hook-v11/observations.json"));wheel=next(x for x in o["observations"] if x["event"]=="manual_wheel_assert")
        assert wheel["immediate"]>wheel["before"] and wheel["after"]==wheel["before"]
        o=json.loads(read("epochs/detail-wheel-nohook-ram-v11/observations.json"));resize=next(x for x in o["observations"] if x["event"]=="text_resize_focus_assert")
        assert resize["no_hook"] and not resize["condition"] and resize["target_has_focus"]
        negative=json.loads(read("epochs/final-guard-follow-false-negative-v7/observations.json"))
        assert negative["fault_applied"] and len(negative["failures"])==1
        legacy=next(e for e in accepted["epochs"] if e["epoch"]=="native-cb3a-720-v1")
        assert "rejected" in legacy["classification"] and legacy["private_queue_files"]
        assert not any(p.startswith("epochs/native-cb3a-1080-scale12-v1/") and p.endswith("exit.json") for p in members)
        assert not any(p.endswith("/queue-after.json") and "native-cb3a-720-v1/" in p for p in members)
        return {"status":"passed","epochs_preserved":47,"final_native":summaries,"final_cpu_original_checks":[16,29],"formal_result_link":{"groups":19,"checks":9212,"independent_formal_reader":"separate published artifact; not rerun by this reader"},"private_external_graph_files":len(index["private_queue_archive"]["files"]),"virtual_files":len(members),"zip_members":len(z.namelist()),"mother_UI210":"pending"}

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--root",type=Path,default=Path(__file__).resolve().parent)
    print(json.dumps(verify(p.parse_args().root),ensure_ascii=False,indent=2))
