# 第一章場景用途來源盤點

此為 `3c053d316fc4da97b00887c2cbbed60b19a12334` checkout 的唯讀來源快照；JSON `runtime_verified=false`。props、contact 與 policy 都是資料宣告，不代表已看畫面、已驗支撐、合理用途或引擎測試。圖片未解碼。ST-22 修改第一章 LevelData／產生器後須刷新。本次刷新依 ST-22 後 checkout bytes：`ch1_stall.tres` 的 stall_home portal 新增 `cinematic_preview_scene = ch1_c14_home`；其餘 216 筆來源逐一比對後僅 3 筆來源另有 bytes/hash 更新，結構計數仍為 9 LevelData、8 maps、70 props。

第一章有 9 份 LevelData、8 份唯一 map JSON（pawnshop dawn 與一般版共用地圖）。唯一 map 共 70 筆 props 放置、69 個不同 prop ID；重複計入九份 LevelData 則 89 筆。

| map JSON | props | SHA-256 |
|---|---:|---|
| `data/levels/ch1_booth_alley_map.json` | 9 | `1ea857320b434e843294a7b78eade548e766671ef87baab79144e52929bf0653` |
| `data/levels/ch1_lounge_map.json` | 9 | `240e683efb8b3fdd5f01121c8f703b2edc3c93e92adcbbde13009dcd4f0c516a` |
| `data/levels/ch1_pawnshop_map.json` | 19 | `616c065a87b59780da426317ce3052336c334b7f66f9bba438d9b43209e01f4c` |
| `data/levels/ch1_rooftop_map.json` | 8 | `0e5e165b74ad2f32be724939c2469cb070fc459806ba73a55d0d6db3708db67c` |
| `data/levels/ch1_stall_map.json` | 6 | `f621429142c398745733059700970e1a7679ed99ee4927bbf6256cbe8f15cc70` |
| `data/levels/ch1_street_map.json` | 10 | `385b777c3dea7e2cbdabf293a6642be3abb461ac469c8f0531ff288df2b0981a` |
| `data/levels/ch1_vault_map.json` | 1 | `1695d36f48ed9cc6a7863ad3c6473e1a8b61a278c42d1a6e8e4e7a1ee7742e23` |
| `data/levels/ch1_warehouse_map.json` | 8 | `64101482b40251ab9f7bb7b389887f28bc22795b32f7d7a5128fad4035460cf3` |

LevelData `legend` 共 80 筆引用（含共用 pawnshop map 重複計數）：18 portal、5 NPC、7 story item、28 props／mechanism、14 enemy、4 consumable、2 shop、2 weapon。前版未分類的 22 筆已依 `.tres` 路徑釐清；現無未知 legend 引用。唯一 map 有 25 個數字提示標記；計入 Dawn 共用 LevelData 則為 32。`LevelData.hints` 經 `LevelBuilder` 轉成 `_layout.hints`，`Level` 會建立 `HintSign`。

可見招牌文字來源不能由 legend 計數推斷。`LevelData.decor` 可觸發動態 neon/billboard；霓虹牌取 `sign_texts`（空陣列時 fallback `OPEN`），全像看板取 `billboard_ads`。九份 Chapter 1 LevelData 未明寫這些欄位，類別預設 decor 為空字典；預設文字陣列本身不證明有招牌實例。另有 6 個唯一 map 的 sign 命名 scenic props，貼圖未解碼，烘焙文字／標語為 unknown。JSON 逐筆列出原 entry、支撐宣告、contact、resource 與 texture 路徑及大小、class。

`level_02.tres` 是既有舊「天空的代價」LevelData，不能視為 ST-18 新第二章已接線。ST-18 的 23 場腳本／文稿審查已完成，但 `CH02_SCRIPT_REVIEW.md` 記錄新章資料與正式 quests 尚未生成，待 ST-19；序章及 `chapter_03` 未找到正式 LevelData。

BG-19 只保留歷史來源：其 coverage／inventory 基線為 `e0f5c157`，本盤點未重跑。兩個附件以唯讀 `git show HEAD` 取得，tracked at `3c053d316fc4da97b00887c2cbbed60b19a12334`，但 sparse worktree 排除在磁碟之外。JSON 列有來源 SHA-256 索引；hash 使用 checkout 原始 bytes、保留 CRLF，不做換行正規化。