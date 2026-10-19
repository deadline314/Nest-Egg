# 阿梨坐姿：來源、接點與原始紀錄

## 問題與採用版本

阿梨的站姿褲子與骨盆，在坐下時會留下僵硬的平面。新補坐姿大腿後又出現臀下圓球：原骨盆還帶著站姿褲子的圓蓋，重複覆在新大腿前面。v1衣襬被褲子壓住且膝前伸太多；v2、v3仍有圓球，全部拒收並留原檔。

最終v4使用獨立坐姿褲子來源，登記到原髖／膝、以原褲色作通道校準；坐姿骨盆保留原青綠襯衫texel和原描邊，站姿褲子的圓蓋改由坐姿大腿負責。原立繪、臉、所有站姿PNG、骨長和關節座標逐檔保持。近側大腿僅在sit用原actor圖層範圍內的順序，站起來恢復既有順序。沒有以變暗、武器遮蓋或改長腿掩蓋問題。

[實際生成來源、完整prompt與校準](../../../../art_src/characters/ali_sit/README.md)。原始兩張image_gen產物保留；實際seed和model-job未提供，記null，不宣稱跑了不可用的ComfyUI／Qwen／SAM。來源重建是現有原生密度的部件登記，不是新高解析立繪。corrupt-source負控制在任何runtime寫入前拒絕，重建逐byte相同。

## 驗證

| 檢查 | 結果 |
|---|---|
| 姿勢圖層負控制／修後 | 舊行為167檢查7預期失敗；修後167檢查0失敗；分數、NaN、bool、越界與後段壞資料整組拒絕 |
| 離線pose alias | 覆寫不污染來源，未指定繼承原順序，壞資料不寫入 |
| NPC站／坐／靠／蹲／談話／聽／揮手／工作 | 兩面向原生全彩圖逐張看過；坐下與起身各兩面向8個時刻另附 |
| 連續接點 | 站→坐、坐→站，各120格×兩倍率×五接點×兩面向，共4800取樣，原checker 0失敗；不刪1像素孔洞判定 |
| 合併候選原選擇器 | 固定base e63a6710、75組、92874檢查，0新失敗／0已知，637秒；70輸入SHA前後一致 |

合併候選包含本票、BG-46舞台與NE-267三頭像；各自提交，並以來源SHA驗證整合。全測試log的刻意壞資料ERROR與退出資源訊息原文保留，不宣稱全輸出零ERROR。接點alpha通過只覆蓋指定接點，另看全彩臀／膝輪廓，不能替其他角色或全部第一章動作宣稱驗收。

原生均為Godot4.7.2、llvmpipe軟體Forward+。參考圖的before和after用同一原骨架、固定坐姿、unshaded全身；一般八姿勢圖有自然小動作，不能逐像素相減當成同時刻。

放進客人簿後，BG-46會再依新大腿輪廓校準坐深0.50，腳底與地面位置保持；該場景驗收及三訪客頭像由各自票保留。本票沒有把那些後續未推送內容算成已交付角色本體。

## 重跑與來源

- `PYTHONPATH=<opencv> python art_src/characters/ali_sit/register.py --publish`，再用既有Godot paint_normals指定ali，正常editor import。
- `res://tools/rig_preview.tscn -- --chars=ali --npc --bright --zoom=3.2 --out=<png>`；加`--left`；`--seq=npc_sit|npc_stand`為180格預備後固定時刻的NPC序列。
- `res://tools/rig_joint_audit.tscn -- --chars=ali --npc-transitions --frames=120 --joints=waist,hip_front,hip_back,knee_front,knee_back --out=<dir>`，再 `python tools/check_joint_frames.py <dir>`。原戰鬥稽核仍是預設，兩倍率與原門檻不動。
- 原選擇器：`GODOT=<4.7.2> SHARDS=4 tools/run_tests_changed.sh e63a6710`。

[技術原始來源與採用理由](references.json)，另先看[五款同類遊戲的實際圖片](../../../../design/08-lighting/READABILITY_REFERENCES.md)。只比較可讀輪廓和克制動作，沒有推論其隱藏骨架或代表全部玩家偏好。

[raw.zip](raw.zip)／[逐檔SHA](manifest.json)。原失敗指令、v1–v3、所有480格、來源校準、JSON及原log均在raw。
