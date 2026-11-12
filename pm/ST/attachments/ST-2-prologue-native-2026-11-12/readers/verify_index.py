"""Portable CPU-only index/hash/actual-label reader; no engine or network."""
import hashlib,json,sys,zipfile
from pathlib import Path
p=Path(sys.argv[1])
with zipfile.ZipFile(p) as z:
 d=json.loads(z.read("index.json"))
 for name,record in d["files"].items():
  raw=z.read(name)
  assert len(raw)==record["bytes"] and hashlib.sha256(raw).hexdigest()==record["sha256"],name
 story=z.read("source/data/story/ch1_kasa.json")
 assert hashlib.sha256(story).hexdigest()==d["story_source_sha256"]
 steps=json.loads(story)["scenes"]["ch1_p01_door"]["steps"]
 for language in ("ja","en"):
  m=json.loads(z.read(language+"/manifest.json"))
  assert m["failures"]==[] and m["renderer"]=="forward_plus" and m["hdr_2d"] is True
  assert "9070xt" in m["adapter"].lower().replace(" ","")
  expected=(steps[1]["lines_"+language][0],steps[2]["sub_"+language])
  for r,kind,text in zip(m["captures"],("narration","subtitle"),expected):
   label=r["text" if kind=="narration" else "sub"]
   assert r["scene"]=="ch1_p01_door" and r["kind"]==kind and r["size"]==[1280,720]
   assert r["speed"]==1 and not r["skipping"] and not r["user_skipped"]
   assert not r["world_can_process"] and not r["player_can_process"]
   assert r["steps_sha256"]==m["expected_steps_sha256"]
   assert label["text"]==text and label["visible"] and label["visible_ratio"]>=.999 and label["alpha"]>=.999
   assert label["visible_line_count"]>=label["line_count"]>0
 for name in ("outside-before","inside-before","inside-after","outside-after"):
  assert json.loads(z.read("queues/"+name+".json"))["clear"] is True
 assert d["guards"]["before_sha256"]==d["guards"]["after_sha256"]
print(json.dumps({"archive_sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"members_verified":len(d["files"]),"actual_locale_frames_verified":4,"classification":"CPU metadata/hash validation; run the included original float-PNG verifier for all pixels"},indent=2))
