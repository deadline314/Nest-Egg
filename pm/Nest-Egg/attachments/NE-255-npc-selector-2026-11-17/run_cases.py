from pathlib import Path
import subprocess,os,json,sys
root=Path(__file__).resolve().parents[2];base=Path(__file__).resolve().parent
mode=sys.argv[1]
if mode=="before":cases=[("before-lean","lean","audit-before"),("before-crouch","crouch","audit-before"),("before-loop","loop:hammer","audit-before")]
else:cases=[("after-lean","lean",None),("after-crouch","crouch",None),("after-loop","loop:hammer",None),("after-invalid-loop","loop:no_such_registered_work",None),("missing-loop-input","loop:hammer","audit-missing-loop"),("defaults",None,None)]
results=[]
for name,pose,scene in cases:
 scene=f"res://work/ne255-npc-audit-20261117/{scene}.tscn" if scene else "res://tools/rig_joint_audit.tscn"
 env=os.environ.copy();env["APPDATA"]=str(base/f"userdata-{name}")
 argv=["python","tools/comfyui/gpu_lock.py","--","C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe","--path",str(root),"--rendering-method","forward_plus",scene,"--",f"--out={base/name}","--chars=old_k","--joints=elbow_front","--zooms=1","--frames=2","--npc-performance"]
 if pose:argv.append(f"--npc-pose={pose}")
 with (base/f"{name}.log").open("w",encoding="utf-8") as log:result=subprocess.run(argv,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
 record=dict(name=name,exit=result.returncode,argv=argv);results.append(record)
 (base/f"{name}.exit").write_text(str(result.returncode)+"\n",encoding="utf-8");print(name,result.returncode,flush=True)
(base/f"runs-{mode}.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
