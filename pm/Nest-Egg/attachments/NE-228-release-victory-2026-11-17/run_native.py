from pathlib import Path
import subprocess,os,json
root=Path(__file__).resolve().parents[2]
base=Path(__file__).resolve().parent
cases=[("en",1280,720,1.2),("en",1920,1080,1.2),("ja",1920,1080,1.2),("zh",1280,720,1.2),("en",1280,720,1.0),("zh",1920,1080,1.0)]
results=[]
for language,width,height,scale in cases:
 name=f"{language}-{width}-{scale}"
 env=os.environ.copy();env["APPDATA"]=str(base/f"userdata-{name}")
 argv=["python","tools/comfyui/gpu_lock.py","--","C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe","--path",str(root),"--rendering-method","forward_plus","res://work/ne228-terminal-layout-20261117/capture.tscn","--",f"--language={language}",f"--width={width}",f"--height={height}",f"--scale={scale}",f"--out={base/name}.png"]
 with (base/f"{name}.log").open("w",encoding="utf-8") as log:
  result=subprocess.run(argv,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
 results.append(dict(case=name,exit=result.returncode,argv=argv))
 (base/f"{name}.exit").write_text(str(result.returncode)+"\n",encoding="utf-8")
 print(name,result.returncode,flush=True)
(base/"native-runs.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
raise SystemExit(0 if all(x["exit"]==0 for x in results) else 1)
