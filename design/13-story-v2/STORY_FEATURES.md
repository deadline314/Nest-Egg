# 故事功能與相容資料格式（ST-3）

2026-10-08。本文件是 ST-2、ST-9 與 ST-16 的介面交接；不取代第一章劇本、章節名單或任務來源。

既有的 `mode`、`lines`、`steps`、`set_flags` 清單、NpcData/NpcTalk、StoryItems、死亡記憶卡全部保留。新功能採可選欄位；沒有新欄位的舊資料走原來的流程。第一章的實際節點與文案由 ST-9 承接，未先修改正在交接的故事／地圖產生器。

## 選项與分支

```json
{"do":"choice", "text":"要不要再問清楚？", "default":"leave", "options":[
  {"id":"ask", "text":"請把事情說清楚。", "set_flags":{"asked_contact":true},
   "steps":[{"do":"say","speaker":"rin","text":"我想先知道這次差事的風險。"}]},
  {"id":"leave", "text":"我先去完成差事。", "set_flags":{"asked_contact":false}, "steps":[]}
]}
```

選項為 2–4 項，有唯一 id 與非空文字，default 必須指向一項。鍵盤／手把使用焦點、確認鍵，滑鼠可以點擊。選擇後立即寫入選項旗標並执行所選 steps；直接跳過或設定自動略過採宣告的預設選项，確保沒有未回答的選擇。已選的選項不因接下來按跳過而改寫。

`branch` 在既有過場 steps 中選擇一組步驟：

```json
{"do":"branch", "requires_flag":"asked_contact", "requires_item":"nest07_shard", "steps":[], "else_steps":[]}
```

`requires_flag`、`unless_flag`、`requires_item` 為 AND 條件。選項也可帶這些條件；缺旗標為 false、缺道具不通過，沒有符合的選項時記錄場景與步驟並安全繼續。條件來源始終是 GameState 與 StoryItems，沒有第二份任務或收藏清單。靜態 ContinuityAudit 會掃描所有分支的讀寫；它判斷「可能可達」，並不證明互斥旗標同時成立。

## 預設、存檔與完成邊界

章節可宣告 `flag_defaults` 物件。值可為布林、整數、有限數字或字串；ST-2 應在第一章來源加入正式旗標預設。未宣告的舊旗標仍相容。

旗標条件採 Godot 原生條件判定：`false`、`0`、`0.0`、空字串為未滿足，其餘有效純量為滿足；不使用 `bool(String)`。完成旗標建議用布林，計數用整數，分支路線可用字串。缺漏的字串預設可用空字串，讀檔後維持相同語意。

故事存檔區塊 version 1 包含 `flags`、`seen`（已完成場景）、`items.owned`、`items.unseen` 與 `deaths`。選項中途存檔保留已做的選擇，但未播放完的場景不會記成已完成；重播場景由上層完整流程存檔決定。缺漏／錯型旗標退回章節預設，未知舊純量旗標保留；未知物品／場景略過並報具體位置。JSON 損毀報檔案與行號；原存檔先保留，成功寫入暫存檔才替換。

`GameState.story_progress_snapshot()`／`restore_story_progress()` 可嵌入完整遊戲存檔；`save_story_progress(path)`／`load_story_progress(path)` 支援独立故事區塊的磁碟往返。Main 開始實際新遊戲後開啟故事自動保存，旗標、場景完成或道具取得會合併到下一個 deferred tick 寫入；測試預設不寫使用者存檔。啟動時讀取既有故事區塊，明確開始新遊戲仍重置本輪進度。

**相容邊界**：現有基線沒有「繼續遊戲」或完整遊戲磁碟存檔。這個區塊只保存故事狀態，不聲稱保存玩家位置、HP、武器、世界與檢查點，也不能單獨拿它續玩第一章。ST-9／ST-16 做讀檔流程驗收時必須檢查上層完整存檔能力，不可把此元件當成已交付完整續玩。

## 互動與故事道具

沿用 NpcData 的 `Kind.OBJECT`、互動範圍及提示，台詞仍引用 Story 場景（短句可用 bubbles）。NpcTalk 增加 `requires_flag`、`unless_flag`、`requires_item`、`once`。once 的調查完成後不重複計數；普通 NPC 原有獎勵與檢查點回溯規則保留。`story_item` 可給普通故事道具，不再只限文件／錄音。背包與劇情條件均使用 StoryItems 的既有目錄、持有狀態。

## 死亡畫面序列

章節可有 `death_sequences` 清單。每筆 `min_deaths`、`skippable`、`steps`，採死亡次數符合的最高門檻；沒有配置就沿用原來的死亡畫面。step 的 `kind` 為 `line`（speaker/text，可帶現有 sfx id）、`status`（text）或 `card`（既有敗北記憶卡），time 為 0–3 秒。首死完整、第二次縮短、第三次可略過的範例在驗收 fixture；正式文字與聲音引用由 ST-9 接入。

特殊首死診間仍優先於一般死亡畫面；此功能不改復原扣款、頭目血量、水位或復原點規則。序列播完後才顯示重試按鈕；skippable 時確認／互動／取消可立即進記憶卡。無音訊裝置只能驗證引用，不能算試聽。

## 狀態驗證矩陣

| 狀態／動作 | 預期 |
|---|---|
| 未選擇 | 暫停遊戲，等待輸入；未完成場景不進存檔 seen |
| 選追問／先離開 | 對應旗標 true／false，走各自後續 |
| 未選擇就跳過 | 使用資料 default，所有必要旗標有決定 |
| 已選擇再跳過 | 保留已選結果，略過剩餘畫面 |
| 不持有故事道具 | 受道具條件限制的分支／調查不可用 |
| once 調查重複按鍵 | 不重複計數或重發故事道具 |
| 磁碟保存／重讀 | 數字旗標、已完成調查、故事道具一致 |
| 缺漏、錯型或 JSON 損毀 | 指出檔案／欄位，退回安全預設 |
| 第一次／第二次／第三次一般死亡 | 完整序列／縮短序列／可略過記憶卡 |
| 未提供新欄位的舊資料 | 原過場、人物、背包與死亡畫面照常 |
