from pathlib import Path
import hashlib,json,re
from PIL import Image
out=Path(__file__).resolve().parent
root=out.parents[3]
receipt=json.loads((out/"receipt.json").read_text(encoding="utf-8"))
for name,digest in receipt["artifacts"].items():assert hashlib.sha256((out/name).read_bytes()).hexdigest()==digest,name
for name,digest in receipt["images"].items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
def report(name):
 text=(out/(name+".log")).read_text(encoding="utf-8")
 assert not re.search(r"^(?:SCRIPT )?ERROR:",text,re.M),name
 return json.loads(next(x.removeprefix("TERMINAL_LAYOUT ") for x in text.splitlines() if x.startswith("TERMINAL_LAYOUT ")))
before=report("before-native")
assert not before["valid"] and before["lines"]==1 and (out/"before-native.exit").read_text().strip()=="1"
runs=json.loads((out/"native-runs.json").read_text(encoding="utf-8"))
assert len(runs)==6
for item in runs:
 name=item["case"];row=report(name)
 assert item["exit"]==0 and (out/(name+".exit")).read_text().strip()=="0" and row["valid"],name
 assert row["lines"]==row["visible_lines"] and row["lines"]>=2,name
 assert row["renderer"]=="forward_plus" and row["adapter"]=="AMD Radeon RX 9070 XT",name
 png=root/"pm/Nest-Egg/images"/("NE-228-release-victory-"+name+".png")
 with Image.open(png) as image:assert list(image.size)==row["resolution"],name
 if name=="en-1280-1.2":assert row["text"]==before["text"]
for name,failures in [("ui-red",9),("ui-green",0)]:
 text=(out/(name+".log")).read_text(encoding="utf-8")
 assert f"checks: 509, failures: {failures}" in text and "SCRIPT ERROR:" not in text,name
before_source=(out/"victory-before.txt").read_text(encoding="utf-8");after_source=(out/"victory-final.txt").read_text(encoding="utf-8")
expected=before_source.replace('\t\tvar teaser_label := UiKit.label(teaser, UiKit.FS_BODY, Palette.NEON_YELLOW)\n','\t\tvar teaser_label := UiKit.label(teaser, UiKit.FS_BODY, Palette.NEON_YELLOW)\n\t\tteaser_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n').replace('累積版本的最後一章：同一行說清楚內容到此、進度已保存，不讓玩家以為下一章壞掉，也不加高面板。','累積版本的最後一章交代收錄範圍與保存結果；長預告依欄寬換行。')
assert expected==after_source
print("Verified: 509/9 -> 509/0, native original rejection and six complete layouts, exact English text retained, PNG sizes, one behavior line plus corrected comment.")
