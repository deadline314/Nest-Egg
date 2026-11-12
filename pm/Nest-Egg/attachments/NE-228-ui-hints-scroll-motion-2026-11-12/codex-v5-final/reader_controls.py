from pathlib import Path
import argparse,hashlib,importlib.util,json,traceback
p=argparse.ArgumentParser();p.add_argument("--root",type=Path,default=Path(__file__).resolve().parent);root=p.parse_args().root
spec=importlib.util.spec_from_file_location("codex_proof",root/"verify.py");m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
rows=[]
for fault in ["wheel-snapback","resize-target-hidden","truncated-guide"]:
    try:m.verify(root,fault=fault)
    except AssertionError as error:rows.append({"fault":fault,"rejected":True,"reader_line":traceback.extract_tb(error.__traceback__)[-1].lineno})
    else:rows.append({"fault":fault,"rejected":False})
assert all(row["rejected"] for row in rows)
print(json.dumps({"scope":"reader-only in-memory counterexamples; actual engine controls are preserved separately", "raw_sha256":hashlib.sha256((root/"raw.zip").read_bytes()).hexdigest(),"controls":rows},indent=2))
