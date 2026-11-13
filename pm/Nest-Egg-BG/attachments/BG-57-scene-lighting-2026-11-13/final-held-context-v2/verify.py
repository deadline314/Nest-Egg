from pathlib import Path
import argparse,hashlib,json,zipfile,tempfile,shutil,subprocess,sys

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument("--require-official",action="store_true");args=p.parse_args();root=Path(__file__).resolve().parent;i=json.loads((root/"index.json").read_text(encoding="utf8"));m=json.loads((root/"manifest.json").read_text(encoding="utf8"))
    for name,digest in i["files"].items():assert sha(root/name)==digest,name
    for name,a in i["archives"].items():
        assert sha(root/name)==a["sha256"] and (root/name).stat().st_size==a["bytes"]<90_000_000
        with zipfile.ZipFile(root/name) as z:
            assert z.testzip() is None and set(z.namelist())==set(a["members"])
            for name,row in a["members"].items():
                data=z.read(name);assert len(data)==row["bytes"] and hashlib.sha256(data).hexdigest()==row["sha256"]
    assert len(m["owned18"])==18 and len(m["borrowed6"])==6
    with zipfile.ZipFile(root/"sources.zip") as z:
        for label,values in [("owned18",m["owned18"]),("borrowed6",m["borrowed6"])]:
            for name,digest in values.items():assert hashlib.sha256(z.read(label+"/"+name)).hexdigest()==digest
    with tempfile.TemporaryDirectory(prefix="BG57-final-held-") as temp:
        raw=Path(temp)
        with zipfile.ZipFile(root/"raw.zip") as z:
            for name in z.namelist():
                target=(raw/name).resolve();assert target.is_relative_to(raw.resolve());target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(name))
        for f in (root/"png").glob("*.png"):shutil.copyfile(f,raw/f.name)
        r=subprocess.run([sys.executable,"-B",str(root/"read_held.py"),str(raw)],capture_output=True);assert r.returncode==0,(r.stdout.decode(errors="replace"),r.stderr.decode(errors="replace"));print(r.stdout.decode("utf8"),end="")
    official=False
    if (root/"official.json").exists():
        o=json.loads((root/"official.json").read_text(encoding="utf8"));assert o["accepted"] is True and sha(root/o["receipt"])==o["sha256"];official=True
    if args.require_official:assert official,"final affected union pending"
    print(json.dumps({"final_held_evidence_verified":True,"owned":18,"borrowed":6,"original_frames":7,"official_accepted":official}))
if __name__=="__main__":main()
