# 返回選單的渲染資源驗收

2026-10-10。重要通訊與第一章正式故事串接的本機驗收，發現真正讀檔、完成 NPC 對話並返回主選單時出現「Attempting to use an uninitialized RID」。錯誤必須消除，不能以流程斷言通過代替原生 log 通過。

## 目前證據

- Godot 4.7.2 ed1daf0bf、Forward+ Vulkan、Intel Arc B580。Native5 行為 55 項通過、1 筆原生 ERROR，因此整輪拒絕。
- 使用同一真 Main、真 NPC、固定檔案寫入器和新程序 Continue 的 Native6 診斷，再次記錄相同錯誤；原有行為斷言全部保留，額外錯誤檢查失敗。
- 錯誤發生於主執行緒一個 draw interval，早於轉場 covered 與第一個舊關卡節點 tree_exiting。舊 Level 當時仍存在；衝刺快照的 active、used、texture leases 均為零。
- 返回選單同時會切換背景預載範圍。尚未定位 RID owner；沒有足夠證據認定預載、殘影、立繪或卸載是根因。Logger 的 script backtrace 為空。

## 交付原則

先用狹小且可重現的原生路徑或原生 stack 定位實際資源使用順序，再修其生命週期。驗收工具不得加等待、強制同步、停用效果或隱藏資源讓錯誤消失。真正產品修補若需更改預載並行策略，必須保留正常非同步載入、畫面完整及明確記憶體上限，並保存修前修後原生 log。

重要通訊的確認、保存拒絕重試、取消與冷讀仍走原有 Source／receipt／固定寫入器。這張票不授予故事完成、全章可玩或正式打包資格。雲端無頭測試與本機 Forward+ 結果分開記錄。

## 2026-10-11 原生因素比較

真正 Main 新局也重現同一 RID 錯誤（normal-4），尚未修復。將真 lounge／pawnshop 的 61／112 個有序貼圖路徑帶到獨立正常場景，使用相同四輪、64 個绘圖包裝與四組 diffuse／normal。三種模式都觀察到八段「載入請求至完成」期間的真 draw，來源 7870 路徑與有序 batches 完全相同。

| 因素 | 真程序 PID | 原生 RID error | 行為 checks／failures | 結果 |
|---|---:|---:|---:|---|
| 原預載＋CanvasTexture | 34668 | 3 | 198／1 | 拒收 |
| 裸 ResourceLoader 背景載入＋CanvasTexture | 4952 | 2 | 1582／1 | 拒收 |
| 同裸背景載入＋直接 Texture2D | 33728 | 0 | 1582／0 | 診斷對照通過 |

三個程序皆自然結束，沒有腳本錯誤或來源漂移；private bytes 峰值約 0.85 GB，VRAM 未能可靠量測。結果支持 Canvas 包裝與並發 texture creation 的組合相關，沒有 native stack，因此尚未證明是哪個 RID owner。直接貼圖是因素對照，不能移除正常法線／光影作為產品修復。

[完整比較與 hash](../../pm/Nest-Egg-BG/attachments/BG-31-render-review/root-matrix-review.json)；同目錄保留三份完整原始 log 與 observer report。首次診斷 wrapper 的過寬 `SCRIPT ERROR` 字串匹配誤把失敗訊息內的「script errors」視為腳本錯誤，已另外留原結果與分類，未覆蓋舊 evidence；上表為修正 wrapper 後三個新的獨立程序。

下一個診斷因子是主執行緒分批建立真 texture，保留原 Canvas、正常法線、相同路徑及引用預算，不預先等待整批、強制 RenderingServer sync 或停用畫面。逐幀數量與 soft 時間预算均須保存實測；單一 texture 載入不可搶占，超過預算必須列為實際效能限制。若需採用此 rendering-affinity workaround，必須重新審查上述非同步策略要求，對原 Main 新局、返回選單與冷 Continue 作真實回歸；小型對照不授予產品交付資格。

## 2026-10-11 有界產品策略與主線進度交付

獨立因素比較支持CanvasTexture與背景texture creation的組合相關，沒有native stack／精確RID owner，不宣稱Godot upstream已修。產品只在Godot4.7.2原生RD的Forward+／mobile以主執行緒Pump延後逐process frame載入Texture2D、沿用CACHE_MODE_REUSE，每frame至多一個；request／dispatch不立即載入。headless仍是真正背景單槽，其他版本／後端保留背景四槽；mobile尚無本次原生圖片證據。

保留512待載、64個LRU引用、128MiB估算快取與generation／scope cancel／clear／shutdown。這是helper引用／估算上限，不能限制仍由活關卡持有的貼圖或稱全遊戲RAM／VRAM上限。2ms為soft budget，單張載入無法搶占；沒有整批預載等待、RenderingServer sync或停用法線／效果来使回歸變綠。

較早獨立產品診斷1599／0、692次draw、八段載入／繪製重疊、raw ERROR0，max單張9.331ms／92次soft超時；來源獨立。同步NE222三個角色渲染產品後，現主線來源d0e443f0c1fac13f9b4ae1c2bd0b96ec3d480998／base54b6f05dcb2dbac25b9467ed2458ac81a792fd19／7790路徑重新驗證：原策略PID26448為106／0、自然exit0/raw0，本輪未重現RID；修補recordPID30336為106／0，coldPID19692為96／0，不同程序、自然exit0/raw0/source0。修前修後來源除一份載入器外完全相同，原策略切回後7790來源精確復原。

真正Start／難度確認、pawnshop三句開場、已載入PauseMenu與Continue走三輪切換；300ms真暫停觀察保持Main／Level與run／HUD時鐘不變而PauseUI可操作。Root逐張看過六張current menu／cinematic／world：完整、沒有缺圖或黑掉，grain仍屬BG27。舊b941來源的2576／0與舊6圖保留歷史，不當新epoch通過。最新原受影響七套件tests4為2576／0新／0已知、自然exit0/source0；原容錯負控ERROR依未改filter分類，script／parse／compile0，符號連結測試跳過項仍不視為已驗。

這次renderer策略與primaryMain回歸作進度交付，BG31維持進行中。私人NPC／重要通訊與主線產品不同，不授primarySource、正式radio或全章完成；共同故事框架真正整合主線後再獨立收尾。current raw／完整before-after來源／記憶體／PNG與歷史紅索引見[精簡交付證據](../../pm/Nest-Egg-BG/attachments/BG-31-primary-main/README.md)。
