from pathlib import Path
import subprocess,os,json
root=Path(__file__).resolve().parents[2];base=Path(__file__).resolve().parent
cases=[("before-defaults","res://work/ne255-npc-audit-20261117/audit-before.tscn","--npc-performance"),("before-combat","res://work/ne255-npc-audit-20261117/audit-before.tscn",None),("after-combat","res://tools/rig_joint_audit.tscn",None),("before-transitions","res://work/ne255-npc-audit-20261117/audit-before.tscn","--npc-transitions"),("after-transitions","res://tools/rig_joint_audit.tscn","--npc-transitions")]
results=[]
for name,scene,flag in cases:
 env=os.environ.copy();env["APPDATA"]=str(base/f"userdata-{name}")
 argv=["python","tools/comfyui/gpu_lock.py","--","C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe","--path",str(root),"--rendering-method","forward_plus",scene,"--",f"--out={base/name}","--chars=old_k","--joints=elbow_front","--zooms=1","--frames=2"]
 if flag:argv.append(flag)
 with (base/f"{name}.log").open("w",encoding="utf-8") as log:result=subprocess.run(argv,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
 results.append(dict(name=name,exit=result.returncode,argv=argv));(base/f"{name}.exit").write_text(str(result.returncode)+"\n",encoding="utf-8");print(name,result.returncode,flush=True)
(base/"runs-regression.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
assert all(item["exit"]==0 for item in results),results
