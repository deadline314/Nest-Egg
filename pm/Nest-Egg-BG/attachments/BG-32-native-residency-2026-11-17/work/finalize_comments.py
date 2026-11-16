from pathlib import Path
import hashlib,json

work=Path(__file__).resolve().parent
original=(work/'candidate-512-theme-backdrop-only-prefetch.gd.txt').read_text(encoding='utf-8')
replacements={
 '## 一個區域一次送出的上限。第一章街道有四種各自外觀的敵人（NE-218），連同場景貼圖約 200 張；上限太低時剩下的不會被預載，換區才臨時讀檔。': '## 一個區域一次送出的上限。現有第一章街道鄰居已超過 256 張；與既有 512 張佇列容量對齊，避免第一次預載漏掉尾段。',
 '## 全部鄰居與過場共用同一範圍，不讓逐個鄰居互相清除。': '## 鄰居共用同一範圍，不讓逐個鄰居互相清除。',
 '# Do not pin a neighboring sky that the current theme never uses.': '# 鄰居的天空與遠景只保留目前主題也會用到的圖（含同名法線／發光變體）。',
 '# Idle areas retain neighbors only; active CutscenePlayer owns its stage.': '# 閒置區域不固定持有過場舞台；播放中的 CutscenePlayer 自己持有。',
 '# 只留這個區域的鄰居與過場用得到的：前幾個區域留下來的預載不再佔著記憶體（BG-32）。': '# 只留這個區域的鄰居所需資產：前幾個區域留下來的預載不再佔著記憶體（BG-32）。',
}
final=original
for old,new in replacements.items():
 assert final.count(old)==1,old
 final=final.replace(old,new)
code=lambda text: '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
assert code(original)==code(final)
(work/'candidate-final-prefetch.gd.txt').write_text(final,encoding='utf-8',newline='\n')
sha=lambda text:hashlib.sha256(text.encode('utf-8')).hexdigest()
(work/'comment-mapping.json').write_text(json.dumps({'native_E_sha256':sha(original),'final_comment_only_sha256':sha(final),'noncomment_lines_identical':True,'replacements':replacements},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Final Chinese comments only:',sha(final),'native executable lines unchanged from',sha(original))
