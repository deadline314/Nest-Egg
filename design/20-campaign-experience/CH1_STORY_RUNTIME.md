# 第一章正式劇本的執行期契約（ST-9／ST-2／ST-3）

2026-10-11。取代保存分支 `a5f2a1ba` 的「原子提交／來源授權」框架：那套框架讓 Story 長到兩千多行、126 項測試失敗，且沒有讓第一章真正能玩。本輪改用 main 既有的劇情執行期，只補作者來源需要、能被測試與畫面驗證的最小欄位；新內容一律寫資料，不改程式。

## 資料流

```
tools/story/ch1_closure.py（作者來源：段落、條件、選項、段尾結果、任務語義）
        │  tools/story/ch1_runtime_backend.py（轉譯；build_ch1_story.py 的預設輸出也走這裡）
        ▼
data/story/ch1_kasa.json  ──►  autoload/story.gd ＋ core/story_outcomes.gd（播放、條件、結果）
tools/level/build_ch1.py  ──►  data/levels/ch1_*.tres、data/npcs/*.tres（入口、出現條件、世界事件旗標）
```

## 場景欄位

| 欄位 | 意義 |
|---|---|
| `when` | 前置條件（StoryConditionTree 格式：all／any／not、flag+equals、item＝目前手上有原件、receipt、account）。不成立就不播。 |
| `results` | 段尾結果：flag、item_acquire、item_transfer、transaction。**整段播完才一起生效**；先全部預檢，任一不成立整段不生效。 |
| `on_failure` | 交易被拒絕時改接的場景（例如現金不足改接「保留欠條／留下」的選擇）。 |
| `transfer_items` | 交出原件（ST-3）；選項上的交付等場景播完才生效，取消、死亡、換區就丟棄。預設選項不得交付。 |
| 選項 `target`、`when`、`set_flags`、`explanation` | 選了才接下一段；`set_flags` 只放可逆的意圖；說明在選擇畫面一句講清後果。 |
| `mode: dispatch` + `routes` | 人物／物件入口：依劇本階段挑第一個成立的段落；完成過的節點自動不重播。 |
| `then` | 同類演出接續：過場／動畫／對話接成一段鎖操作的演出；通訊／氣泡各自排隊。 |
| `context_facts` | 只在這串演出裡成立的事實（例如真正的初次建檔，回放不算）。 |

## 章節欄位

| 欄位 | 意義 |
|---|---|
| `transactions` | 正式交易 id → 資源（金額與互斥條件只在資源裡）。 |
| `derived_flags` | 由條件推出、每段結果後重算的旗標（例如四張標籤都讀過、還能不能重選去留）。 |
| `runtime_facts` | 讀當下服務、不存檔的事實：deaths_zero、checkpoint_registered、always、context:<鍵>。 |
| `restoration_flag` | 真正的一般死亡（不是初次建檔）且有登記電話亭時寫入，給「剛從電話亭回來嗎」這類台詞用。 |
| `event_scenes` | 世界事件第一次發生時播放的場景（第一次在電話亭備份播錄音）。 |
| `death_sequences` | 一般死亡畫面的序列；第一次死亡走初次建檔，不經過死亡畫面。 |

世界事件的旗標寫在產生它的資料上：關卡 `channel_done_flags`／`channel_cleared_flags`（打倒看門狗、水閘、路障解除）、物品 `acquire_flag`（拿到資料盤）。連續性審核從地圖本身就看得到誰產生旗標。

## 存檔契約變動（NE-230 請跟進）

- 新旗標都存在既有的本輪旗標裡（`story/flags`），沒有新增存檔欄位；執行期事實不存檔、讀檔後重新計算。
- 正式交易收據沿用 NE-231 的帳本快照；物品沿用 ST-3 的 held／transferred。
- 新增可存的世界旗標：`ch1_street_route_open`、`watchdog_defeated`、`ch1_flood_gate_open`、`ledger_disk_obtained`、`ch1_recording_heard`、`ch1_booth_restoration_done`。舊存檔缺這些值時退回預設 false。

## 與保存分支的對照

| 保存分支內容 | 本輪處理 |
|---|---|
| 115 場景正式劇本、11 個任務語義、交接櫃區域、四張標籤、阿梨出現條件 | 採用（從作者來源重新轉譯；任務只發布有真實地點的 9 個）。 |
| 原子提交埠、來源授權、診間舞台保管、通訊檢查點（約 4,000 行） | 不採用；以「段尾才生效＋過場取消回撤入口快照」達成同樣的玩家結果。 |
| 診間錄音與燈的聲音支線 | 採用，錄音改由第一次電話亭備份播放，聽過才開放追問。 |
| 測試契約遷移 | 依新地圖與新流程更新期望值（多了交接櫃區、人物入口改為分派、正式阿梨流程用真選擇與真交易），不刪斷言、不改選擇器。 |
