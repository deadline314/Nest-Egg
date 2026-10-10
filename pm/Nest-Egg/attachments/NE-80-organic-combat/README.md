# NE-80 自然交戰局部驗證

來源版本 `00a19ad5e6aab2b75a17d2344e53d0faabedbff3`，Godot 4.7.2，原生 Forward+。CPU 10／0；原生 13／0（含三次暫停讀回檢查）。完整事件和素材來源雜湊保留在原始 JSON，未改敵人 FSM、生命或裝甲狀態。

实际 Player 手槍射击：正面封閉護甲擋下子彈、生命 14→14；重裝機槍手自然预热→掃射→散熱，掃射計數 13 發，7 次實際 Player 傷害（999→992）；自然散熱時，Player 短距離射擊造成敵人生命 14→12。Player 的生命設定 999 用於持續觀察，散熱測試控制 Player 位置；這是局部交戰驗證，不能代表一般難度完整戰鬥。

三張 1280×720 圖片保存於 `../../images/NE-80-organic-combat/`，原始讀回時的模擬資料前後一致。畫面可能保留上一格動畫／槍口特效，HUD 可能遮擋角色；圖片僅供交戰情境查看，不作散熱姿勢、逐格接縫、八動作或全裝甲品質通過依據。

`archive-fixture.*` 保留實際原生執行的私有 fixture 原始位元組，僅供來源核對；請使用公開 `replay.*` 重跑。公開版本只變更自身資源路徑，並另跑一次 headless（10／0），沒有冒充另一次原生驗證。`verify.py --self-test` 比對原始紀錄、檔案位元組、來源版本 Git blob、三張 PNG、模擬凍結狀態與自然交戰事件；另確認錯誤來源 hash 及單位元組損壞圖片會被拒絕。後續 main 的改動不會把歷史驗證說成最新驗證。

從專案根目錄重跑，輸出必須是新的空絕對路徑：

```powershell
$revision = git rev-parse HEAD
$output = 'D:/NestEggVerification/ne80-new-run'
& $env:GODOT --headless --audio-driver Dummy --path . res://pm/Nest-Egg/attachments/NE-80-organic-combat/replay.tscn -- --head=$revision --out=$output
python pm/Nest-Egg/attachments/NE-80-organic-combat/verify.py --replay-report "$output/NE80-heavy-preflight.json"
```

原生重跑移除 `--headless --audio-driver Dummy`、加入 `--capture-images`，經 `tools/comfyui/gpu_lock.py` 序列化執行。原生截圖仍需人工檢視；資料驗證不能取代視覺與操作驗收。
