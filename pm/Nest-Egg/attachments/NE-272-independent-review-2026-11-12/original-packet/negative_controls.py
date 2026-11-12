"""Reader-only counterexamples; original ZIP/source/engine receipts stay untouched."""
from pathlib import Path
import hashlib,importlib.util,json,traceback,argparse
parser=argparse.ArgumentParser();parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parent)
ROOT=parser.parse_args().root
spec=importlib.util.spec_from_file_location("ne272_reader",ROOT/"verify.py")
reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
rows=[]
for fault in ["crouch-no-flight","shield-no-callback","jump-grounded"]:
    try: reader.verify(ROOT,semantic_fault=fault)
    except AssertionError as error:
        rows.append({"fault":fault,"rejected":True,"exception":type(error).__name__,"reader_line":traceback.extract_tb(error.__traceback__)[-1].lineno})
    else: rows.append({"fault":fault,"rejected":False})
assert all(r["rejected"] for r in rows)
result={"scope":"in-memory reader negative controls only; not additional gameplay runs", "raw_sha256":hashlib.sha256((ROOT/"raw.zip").read_bytes()).hexdigest(),"controls":rows}
print(json.dumps(result,indent=2))
