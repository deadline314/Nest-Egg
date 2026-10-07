# NE-223 與 Session 3 的一次接線交接

初始程式基線：origin/main `6f4805be`；最新已核對 `319eaf87` 的 ST-3 交付與 `STORY_FEATURES.md`。後續已整合 aae089c8 的敵人名單與音樂更新，未變更上述故事介面與第一章九區幾何。ST-3 已審查中，提供故事進度區塊、選項與死亡序列；ST-2、ST-6、ST-9 的正式主线來源仍待穩定交付，ST-15、ST-16 尚未交付。這份是介面交接，不代表相依已交付，也沒有自動傳訊其他聊天。

## Session 4 已提供

- `core/navigation/quest_catalog.gd`：從 `Story.CHAPTER_PATHS` 章節 JSON 讀取 `quests`，檢查型別、缺欄位、重複編號與真實地點。沒有資料就空目錄，不生成草稿旗標。
- `core/navigation/quest_map_index.gd`：真實地圖、出入口、標記、可通行路線與視線遮蔽；按章節快取。
- `core/navigation/quest_map_state.gd`：釘選、已探索格子、啟用復原點的 `snapshot()` / `restore(raw, catalog, maps)`；死亡和區域／章節切換保留，新遊戲清除。
- `ui/quest_map_screen.gd` / `ui/quest_guidance.gd`：目錄、細節、地圖、圖例、tooltip、HUD 和跨區出口箭頭。HUD 只讀 GameState.world_flags。
- 正式遊戲目前只使用實際地圖。`tests/fixtures/navigation/catalog.json` 及 `--fixtures` 限 UI 驗證，從未加入故事载入清單；樣本截圖明確標示「驗證樣本」。

## 最小故事欄位（保留在原始產生器）

在 `tools/story/build_ch1_story.py` 產生的章節資料增加頂層 `quests`。不另建第二份故事，也不只改 `data/story/ch1_kasa.json`。

```json
{
  "quests": [
    {
      "id": "穩定任務編號",
      "kind": "main",
      "title": "完整的一行動作目標",
      "background": "只敘述玩家已經知道的背景。",
      "reward": "由原有故事與獎勵資料核對的說明。",
      "visible_flags": [],
      "requires_flags": [],
      "blocked_reason": "有前置時說明缺少什麼。",
      "suggestion": "有前置時說明先去哪裡取得。",
      "complete_flag": "既有且可達的完成旗標",
      "steps": [
        {
          "title": "前往目的地完成這個步驟",
          "complete_flag": "該步驟既有且可達的旗標",
          "location": {
            "level": "res://data/levels/實際區域.tres",
            "cell": [0, 0]
          }
        }
      ]
    }
  ]
}
```

`cell` 是格子腳底座標；必須在範圍內且不是實心格。任務／步驟完成旗標不由 UI 建立。獎勵僅顯示，仍由既有系統發放。沒有合理的完成旗標時，Session 3 在原始故事資料與旗標生產者補齊。

本 Session 僅修改 NE-223 的相依關係；對應 ST 票的 Blocks：NE-223 由 Session 3 補上，遵守本次單票範圍。

Session 3 提供正式旗標定義、生產者與有順序的主線狀態軌跡，包含分支、死亡／復原、取得資料盤、回家與章末。不能只把全部旗標設成 true 便聲稱「每刻有主線」。章末若要保有非空目標，需要故事明確提供下一個可進行目標／結束狀態；UI 不替劇本決定。

## 存檔接點

最新 ST-3 提供 `GameState.story_progress_snapshot()` / `restore_story_progress()` 及 `save_story_progress()` / `load_story_progress()`，保存旗標、場景、故事道具與死亡次數。依其[交接邊界](../13-story-v2/STORY_FEATURES.md)，仍沒有整輪存檔／續玩入口，不能把故事磁碟區塊當作包含世界、玩家、檢查點與導覽的完整存檔。本 Session 沒有改 `game/main.gd`、`autoload/game_state.gd` 或 `autoload/story.gd`。

Session 3 在正式存檔保存 `navigation: QuestMapState.for_run().snapshot()`。完成 GameState、Story 和區域世界的還原之後，取得目前章節的 QuestCatalog 與 QuestMapIndex，再呼叫同一個 state 的 `restore(save.get("navigation"), catalog, maps)`。舊檔／損毀資料會回報 `navigation` 的具体欄位並退回安全預設。

目前新遊戲以 GameState.area_states 的物件身分區別新一輪；Session 3 若會在普通讀檔／換區替換該字典，務必在替換之後還原 navigation。若新增正式 run_started / run_restored 事件，再做一次明確接線取代這個基線適配；不同 Session 不同時改同一段主流程。

## 旗標相容性補充

導覽用 GDScript 原生條件判定純量旗標：0／空字串為 false，非零／非空為 true，避免把 0 當完成。追加測試包含布林、數字與字串。Godot 4.7 的 `bool(字串)` 會報不存在的建構子；ST-3 的 `GameState.has_flag()` 使用 `bool(get_flag(...))`，若正式來源以字串作條件旗標，故事 Session 需在該核心介面處理此型別。此 Session 未改其核心檔案；導覽已用安全的條件判定，正式資料仍建議使用布林完成旗標。

## 地圖與鎖門

原始關卡產生器仍是 `tools/level/build_ch1.py`。原因與取得方式補在既有 `PortalData.locked_text` 與 `MechanismData.hint`，避免 UI 和遊戲內各維護一份文字。現有文字如「漏水，別開。」、「先吃晚飯。老 K 在等。」須由故事／可讀性 Session 改成完整說明並保留在產生器；不能由地圖猜測原因。

世界地圖反映九份真實區域資料；目前沒有電話亭傳送接點，只標示已啟用復原點。若 Session 3 增加傳送，交付實際入口、啟用規則及保存格式後再接入。

## 接線完成後的驗收

1. 正式來源資料與本接點一起合入 main，再由 Session 4 接線；不改演員、舞台、骨架、出場配置或序章入口。
2. `tools/quest_map_audit.gd` 檢查真實旗標生產者與可達性，接上 Session 3 的逐狀態主線軌跡，確認每一刻目標非空。
3. ST-16 合入後，從正常結束與長按跳過兩條路線進入第一章，都有可進行主線；本基線先驗證當舖入口。
4. 真正退出再讀檔、死亡重試、章節切換與損毀存檔；不可拿快照單元測試代替這些操作。
5. 正式來源的全部分頁、亮暗地圖、HUD、鎖門，以及鍵盤／實體手把驗收。UI 樣本圖不能代替正式主線。
