# NE-90 文字分割遮罩快取修復

此封包是離線 8×8 合成來源的 RED/GREEN 重現；沒有生成正式角色、呼叫 ComfyUI 或執行遊戲畫面驗收。診斷圖不是 Godot 截圖，不表示任何角色的解剖、分件所有權或動態接縫通過。

## 重跑

從 repository root 執行：

```powershell
D:/ComfyUI/.venv/Scripts/python.exe -X utf8 pm/Nest-Egg/attachments/NE-90-mask-cache/repro_cache_bug.py --mode red
D:/ComfyUI/.venv/Scripts/python.exe -X utf8 pm/Nest-Egg/attachments/NE-90-mask-cache/repro_cache_bug.py --mode green
D:/ComfyUI/.venv/Scripts/python.exe -X utf8 tools/comfyui/test_mask_delivery.py
```

RED 刻意退出 1；透過 git show 載入 0a09e1bdd97c32d947e9224267fffc8f26c63c6e 的舊工具。同尺寸 base / peeled-stage 各修改一個像素，舊程式仍沿用存在的遮罩，mocked SAM 呼叫數為 0，base 灰底未更新。GREEN 退出 0，同一 fixture 更新灰底並重新分割兩張文字遮罩。來源／灰底 SHA 與呼叫參數見兩份 report。

## 已執行

- 根工作區 rebase 到 ebb4c653 後獨立重跑 mask-delivery Python 檢查退出 0。
- 乾淨 detached 0a09 工作區只複製本次兩份 Python 工具，mask-delivery 退出 0；run_tests_changed.sh 固定比較 0a09，正確選出零個 Godot 套件。這是離線工具差異，不以空選集聲稱遊戲測試通過。
- 同輸入命中、同尺寸來源像素更改、stage、prompt、threshold、壞快取、同尺寸 PNG 被替換與 SAM 失敗均有測試；原遮罩在生成／驗證失敗時保留、失效 key 已刪除。
- peeled-stage 畫布與 base 不同時具名拒收，8×8 / 6×6 負控制確認沒有匯出部件 PNG。
- 三組 character-art-pipeline 技能同步，cache 一致不取代像素所有權或原生動態接合檢查。

封包文字依 repository 規則統一 LF 換行；執行內容及退出結果保留，SHA 帳本對應可攜封包位元組。

## 邊界

只修 text-mask 路徑；point-mask 維持原程式。模型 key 是 checkpoint 檔名，若同名權重原地替換或分割實作變更，須更新 cache version。輸出全部驗證後逐檔替換；OS 級替換中斷沒有整批回滾，但失效 key 已持久刪除，重跑不會誤用混合輸出。

這個重現不能推定某個歷史角色曾命中舊來源。OldK 的現有 P.png 與 P_grey.png 已逐像素比較，灰底合成差異為 0；不能把它的部件缺陷歸因於灰圖過期。

完整遊戲測試交 CI，角色與敵人尚未完成的驗收條件保持未勾選。
