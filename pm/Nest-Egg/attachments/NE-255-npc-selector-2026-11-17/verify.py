from pathlib import Path
import hashlib,json,re
from PIL import Image
out=Path(__file__).resolve().parent
receipt=json.loads((out/"receipt.json").read_text(encoding="utf-8"))
for name,digest in receipt["artifacts"].items():assert hashlib.sha256((out/name).read_bytes()).hexdigest()==digest,name
def text(name):return (out/name).read_text(encoding="utf-8")
def groups(name):return json.loads(text(name+"/frames.json"))
records=sum((json.loads(text(f"runs-{mode}.json")) for mode in ["before","after","regression"]),[])
assert len(records)==14
for item in records:
 name=item["name"];expected=1 if name in {"before-lean","before-crouch","before-loop","after-invalid-loop","missing-loop-input"} else 0
 assert item["exit"]==expected and int(text(name+".exit"))==expected,name
 log=text(name+".log");assert "SCRIPT ERROR:" not in log and "leaked at exit" not in log and "resources still in use" not in log,name
 if expected==0:assert not re.search(r"^ERROR:",log,re.M),name
 else:assert "ERROR: [rig_joint_audit]" in log and not (out/name/"frames.json").exists(),name
for name,pose,posture,loop in [("after-lean","lean","lean",""),("after-crouch","crouch","crouch",""),("after-loop","loop:hammer","stand","hammer")]:
 data=groups(name);assert len(data)==1 and data[0]["pose"]==pose,name
 group=data[0];assert group["prewarm_frames"]==180 and abs(group["fixed_step"]-1/60)<1e-12 and group["zoom"]==1 and group["renderer"]=="forward_plus" and group["adapter"]=="AMD Radeon RX 9070 XT",name
 assert [x["frame"] for x in group["samples"]]==[0,1]
 assert {x["facing"] for x in group["cells"]}=={-1,1} and len(group["cells"])==2
 assert all(x["npc_pose_observed"]==posture and x["npc_loop_observed"]==loop for x in group["cells"])
 for sample in group["samples"]:
  assert not re.search(r'[<>:"/\\|?*]',sample["file"])
  with Image.open(out/name/sample["file"]) as image:assert image.size==(256,128)
 assert json.loads(text(name+"/report.json"))["failed_samples"]==0
assert [x["pose"] for x in groups("defaults")]==["stand","sit","sit_talk","sit_listen","wave"]
assert "frame=0 requested NPC stand/hammer, observed stand/ (active=true)" in text("missing-loop-input.log")
after=text("audit-after.gd");missing=text("audit-missing-loop.gd");line="\t\t\t\t\t\t\tinput.npc_loop = expected_npc_loop\n"
assert after.count(line)==1 and after.replace(line,"")==missing
assert 'const NPC_PERFORMANCES := ["stand", "sit", "sit_talk", "sit_listen", "wave"]' in after
count=0
for before_name,after_name in [("before-defaults","defaults"),("before-combat","after-combat"),("before-transitions","after-transitions")]:
 before=groups(before_name);candidate=groups(after_name);assert len(before)==len(candidate)
 for old,new in zip(before,candidate):
  for a,b in zip(old["samples"],new["samples"]):
   assert a==b and (out/before_name/a["file"]).read_bytes()==(out/after_name/b["file"]).read_bytes();count+=1
  for cell in new["cells"]:cell.pop("npc_pose_observed",None);cell.pop("npc_loop_observed",None)
 assert before==candidate
assert count==30
checks=json.loads(text("pixel-checks.json"));assert len(checks)==5 and all(x["exit"]==0 for x in checks)
assert json.loads(text("defaults/report.json"))["samples"]==20
assert 'intact passes; one-pixel hole and disconnected pair fail' in text("checker-self-check-pixels.log")
print("Verified 14 native runs, actual selected states, unchanged five defaults, invalid/missing loop refusal, Windows filenames, 30 byte-identical legacy PNGs/metadata, 32 local pixel samples and unchanged checker self-check.")
