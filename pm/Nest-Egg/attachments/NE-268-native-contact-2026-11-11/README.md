# NE-268：Radeon 原生接觸回饋

2026-11-11，Godot 4.7.2 official、AMD Radeon RX 9070 XT、Vulkan Forward+、HDR 2D，1280×720、3.4 倍鏡頭。只補原生驗收，沒有修改正式遊戲程式。正式章節 `ch1_kasa` 中的安排測試場地，兩側各一個停止主動攻擊、999 生命的保全；玩家亦沿用 ScenarioBase 的 999 生命／0 受傷保護。使用虛擬瞄準與公開近戰 action，時間倍率 0.1。這不是人類遊玩、真實手把或自然整章的證據。

## 對照內容

- [before](before/report.json)：現版近戰模組的子類，只將 a5dd106c 修前的五處回饋定位行為還原。沒有回退整個歷史 checkout，也沒有改傷害、受擊框、時序、擊退、硬直或聲音。
- [current](current/report.json)：正式現版近戰模組。兩輪同一武器／場地／位置／鏡頭／輸入方式；自然雨滴相位不同，不作逐像素影像比較。
- [獨立驗證](verification.json)：34 項、0 失敗。舊座標兩側都因火花確認點在腳底、數字不在同一接觸點而失敗；現版兩側都通過。兩版生命 999→993、單次傷害 6、擊退 (±420,-160)、stagger 3 相同。
- 右側現版接觸 (508.5,295.8)、腳底 (512,320)；左側現版接觸 (451.5,295.8)、腳底 (448,320)。數字發送位置與 DamageInfo.contact_point／hit_confirmed 相等。這是事件來源核對，不是宣稱每個數字字形的最終像素都落在框內。
- 八張原圖（兩側、命中與下一個取樣、前後兩輪）全部逐張看過。舊版地面多出的青黃火花消失，現版火花在身體上；原本的瞬間亮閃保留，未調弱粒子或光照來方便過關。原圖保留在 before／current，精選並排圖放票的 images。

## 結果與失敗記錄

| 執行 | 結果 |
|---|---|
| 正式章節 before／current | 各退出 0；無 ERROR／SCRIPT ERROR／退出洩漏訊息 |
| 原 HeavyEnemiesSuite | [293 項、0 失敗](heavy-enemies-direct.log)，121.5 秒，退出 0；原本的跳砍、左右、平台下刺、多目標與深處核心回饋回歸保留 |
| 本次工具選擇 | [0 個受影響遊戲套件](selection.txt)，因只有新拍攝／驗證工具；沒有以此代替上述補驗 |
| 首次直接執行舊拍攝工具 | [class cache 過期](initial-stale-cache.log)，多個型別未註冊，已終止自己的失敗程序；[重新匯入](import.log)退出 0，沒有改遊戲來源配合舊快取 |
| 首版新探針使用預設舊章節 | [畫面／數字記錄](legacy-chapter-crash/report.json)完成，但退出 -1073741819 (0xC0000005)。原 log／退出碼保留；未把此輪當成乾淨通過 |

最後兩輪明確指定正式 `ch1_kasa`，沒有宣稱已修復未指定章節的舊 `chapter_01` 退出崩潰。這個本機結果與 user_guide 先前記錄的舊章節退出問題相符，但沒有符號堆疊，不能由此證明唯一根因。

## 重跑

在 repo 根目錄，兩個原生命令依序跑，均經共享 GPU 鎖：

```powershell
python tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path C:/Users/stanl/Github/Nest-Egg --rendering-method forward_plus --rendering-driver vulkan res://tools/ne268_native_contact_probe.tscn -- --legacy --out=<絕對目錄>/before
python tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path C:/Users/stanl/Github/Nest-Egg --rendering-method forward_plus --rendering-driver vulkan res://tools/ne268_native_contact_probe.tscn -- --out=<絕對目錄>/current
python tools/verify_ne268_native_contact.py <絕對目錄>
```

每輪的實際 shell 結束碼需另存為 `exit-code.txt` 才能執行獨立驗證。拍攝設定寫到各自輸出目錄的 probe-settings.cfg，未呼叫正式存檔。原始程式雜湊、固定 HEAD 與引擎版本在 [receipt.json](receipt.json)。歷史控制只對本次固定來源有效，正式近戰重構後須重新核對，不可默認它永遠代表未來版本。
