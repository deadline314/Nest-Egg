from pathlib import Path
import argparse,hashlib,json,zipfile,tempfile,shutil,subprocess,sys

def sha(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda:f.read(1024*1024),b""):h.update(block)
    return h.hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--raw-root",type=Path);parser.add_argument("--require-official",action="store_true");args=parser.parse_args()
    root=Path(__file__).resolve().parent;index=json.loads((root/"index.json").read_text(encoding="utf8"))
    for name,digest in index["files"].items():assert sha(root/name)==digest,("file changed",name)
    for name,a in index["archives"].items():
        assert sha(root/name)==a["sha256"] and (root/name).stat().st_size==a["bytes"]<90_000_000
        with zipfile.ZipFile(root/name) as z:
            assert z.testzip() is None and set(z.namelist())==set(a["members"])
            for member,expected in a["members"].items():
                data=z.read(member);assert len(data)==expected["bytes"] and hashlib.sha256(data).hexdigest()==expected["sha256"],member
    owned=json.loads((root/"candidate-manifest.json").read_text(encoding="utf8"));assert owned["owned_count"]==len(owned["owned_files"])==18 and owned["borrowed_context_count"]==6
    with zipfile.ZipFile(root/"sources.zip") as z:
        for prefix,files in [("owned",owned["owned_files"]),("borrowed-context-only",owned["borrowed_excluded_from_BG_staging"])]:
            for name,digest in files.items():assert hashlib.sha256(z.read(prefix+"/"+name)).hexdigest()==digest,name
    with tempfile.TemporaryDirectory(prefix="BG57-portable-") as directory:
        raw=Path(directory) if args.raw_root is None else args.raw_root.resolve()
        if args.raw_root is None:
            with zipfile.ZipFile(root/"raw.zip") as z:
                for member in z.namelist():
                    target=(raw/member).resolve();assert target.is_relative_to(raw.resolve());target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(member))
        for tag,reader in [("gallery","gallery_reader.py"),("held","read_held.py")]:
            # Only a private replay copy is modified; supplied --raw-root remains read-only.
            replay=Path(directory)/("replay-"+tag);replay.mkdir()
            with zipfile.ZipFile(root/"raw.zip") as z:
                for member,expected in index["archives"]["raw.zip"]["members"].items():
                    if not member.startswith(tag+"/"):continue
                    source=raw/member;assert sha(source)==expected["sha256"];shutil.copyfile(source,replay/Path(member).name)
            for f in (root/"png"/tag).glob("*.png"):shutil.copyfile(f,replay/f.name)
            result=subprocess.run([sys.executable,str(root/"readers"/reader),str(replay)],capture_output=True)
            assert result.returncode==0,(reader,result.stdout.decode(errors="replace"),result.stderr.decode(errors="replace"))
            print(result.stdout.decode("utf8"),end="")
    official=False
    if (root/"official.json").exists():
        record=json.loads((root/"official.json").read_text(encoding="utf8"));assert record["accepted"] is True and sha(root/record["receipt"])==record["sha256"];official=True
    if args.require_official:assert official,"official affected-union receipt not yet supplied; candidate evidence is not overall completion"
    print(json.dumps({"candidate_evidence_verified":True,"owned":18,"borrowed_context":6,"native_originals":16,"official_accepted":official}))

if __name__=="__main__":main()
