# NPC 一次性反應的整輪存讀

2026-10-21，NE-240。NPC 的 capture_state 已寫出 reacted 索引，NpcAwareness 也能還原；整輪 RunSnapshot._world 只保留 talks／claimed，遺失 reacted。這是既有可選 once 設定的保存契約缺口；目前正式 data/npcs 沒有 once=true，不改其既有反應頻率，也不宣稱玩家已遇到全部 NPC 重做一次性招呼。

保留可選 reacted 陣列，維持原節點狀態的 talk／claimed 語義。合法整數索引去重，沿用有界狀態的上限；錯誤型別與不合法索引記具體 NPC 位置並回安全空值。舊存檔沒有此欄位時保持相容。只保存資料，不觸發手勢、不發物品或獎勵、不增加另一個旗標來源。

以既有 owner 的捕捉／還原、所有區域與當前 runtime／checkpoint 四處世界、真正 writer／reader 及新程序往返驗證。一次性頻率使用明示 fixture，不能將診斷設定宣稱為正式角色資料或替代未完成的手部／動作美術。

研究沿用本輪實看五款橫向作品的[原圖與來源](../../pm/Nest-Egg/attachments/NE-278-references/sources.json)，只採人物與場景前後資訊一致的原則；另已讀[Hades官方更新](https://www.supergiantgames.com/blog/hades-updates/)的對話資格／順序修補，不據此推論其內部存檔格式。[情境反應原設計](SITUATIONAL_REACTIONS.md)保持原動作與冷卻設定。
