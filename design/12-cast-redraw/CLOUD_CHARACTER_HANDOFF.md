# Session 1 雲端工作組交接（2026-10-09）

使用者授權將不需 ComfyUI 的程式、資料、headless 測試與可行的軟體渲染移到 Nest-Egg 雲端環境。主 Session 保留 Rin／共用骨架、素材來源、配方、ComfyUI，以及最後的實際 Forward+、HDR、操作與硬體效能驗收。完整測試交 CI，本機和雲端只執行受影響測試；固定 base 必須覆蓋本次差異，不能選出零套件便聲稱通過。

## 工作組與檔案責任

1. **ST-8 回歸**：沿用已交付的 77 個圖示。核對原生 RGBA、尺寸、來源重現、背包 UI、拾取物與水坑機關；先用既有 UiKitSuite、CollectiblesSuite、StoryContentSuite、FloodPitSuite 等對應測試，按實際依賴選擇，不重做地圖或機關。沒有差異時直接列明相關套件，不使用空集合。只新增獨立證據／必要的缺口測試。
2. **NE-79／80／81 回歸**：三個敵人的 spec／parts、八動作、固定骨長、護甲脫落底層、武器握點與槍口契約。沿用 NE-181 的腰髖成果；其三接點歷史通過不能當成其他接點通過。現有 rig_joint_audit 不含裝備／脫甲，需要明確補足覆蓋。專屬新增測試可放 tests/suite/test_enemy_art_delivery.gd；不修改既有共用動畫或預算。
3. **NE-221 眨眼時序**：以最小的可測資料驅動時序接上現有 NpcLife，限定 game/rig/npc_life.gd、新增 game/rig/eye_blink.gd（只有現有元件不足時）、tests/suite/test_eye_blink.gd。頭部 PNG、附件綁定與 CharacterRig 由主 Session 負責。交接介面須清楚給出 open／half／closed 狀態、seed、設定覆蓋、說話／死亡／重設行為；中位數約 3.5 秒，單次 120–150 ms，說話頻率增加，不能以更長動畫延遲輸入。所有新邏輯留有效自檢，測錯誤資料、delta 尖峰、重設、不同角色去同步。測試注册由主 Session 整合，避免碰到其他組。

若需要超出責任的改動，先留下實際退化證據和介面說明，再由主 Session 安排。雲端不得操作本機 ComfyUI，也不修改 game/rig/character_rig.gd、humanoid_animator.gd、art/rigs、角色 PNG／source／配方、故事／台詞／出場、NE-71／88／153。不重畫已同意的 Rin 定稿。

## 執行與驗收

- 完整閱讀 AGENTS、各票需求與全部 Commit、適用技能及 RIG_QUALITY，再核對最新 main；必要的方法研究只採官方 Godot／Spine／Live2D 等原始來源，區分來源做法與專案量測門檻。
- headless 模式不需要 GPU；程式／資料測試可在雲端直接跑。畫面檢查優先 Compatibility 與可用軟體驅動，記錄真正的 renderer／driver／版本／截圖尺寸。不能把 Compatibility 或軟體渲染當作本機 Forward+ HDR／glow／硬體效能通過。
- **所有既有檢查門檻不變**：任何小裂縫、一像素洞、錯切、多餘肢體及不合理姿勢仍失敗；骨長、折疊比例、500 頂點、效能預算不提高，也不刪指標或加 known_failures。
- 雲端結果保留基線、diff、來源 hash、命令、套件與 assert 數、真正失敗和原生圖片。未執行的項目明列，不能以文字冒充截图／人工遊玩。沒有 GPU 不阻擋可獨立完成的程式工作。
- 雲端以獨立 codex/ 分支交付可審查 patch／commit；不自行 push main，不改票審查中，不與主 Session 同改核心檔案。主 Session 驗收後按原票逐票 commit／push，再於該批主 Session 測試中一併執行 NE-224，不重跑無關完整測試。
- 每次 commit 的作者與提交者均 Stanley Li <stanley890314@gmail.com>，訊息只有票號和具體變更，沒有模型署名。

## 主 Session 結案

NE-224 記錄整合後的測試、全接點／全動作、裝備與脫甲、眨眼 30 秒場景、UI／拾取／機關、實際 Forward+、同條件效能和 CI。雲端通過不直接替代这些證據；原票只勾選真正驗證的條件，使用者同意不代勾。NE-222 的已知 Rin 接縫和姿勢修復繼續由主 Session 處理，不能因分組而停工或宣稱已結案。

## 所有 Session 的 main 同步與交付規則（2026-10-09 補充）

本節已送達 Session 2～7 與本次雲端工作組；補充原責任範圍，不擴大各組可修改的檔案。

1. 先完整閱讀 AGENTS.md、CLAUDE.md 第 3 節與適用的 pm-ticket／角色技能，核對需求、驗收、相依關係、全部 Commit 紀錄與最新程式。Godot 版本按目前 CI 與專案確認，不以舊環境版本代替。
2. 開始、恢復、承接相依成果、開票與每次 push 前先 fetch origin main。使用獨立 worktree／checkout、codex/ feature branch；既有變更先確認所有者，只保存自己的內容。遠端前進時 rebase，保留其他 Session 修改並重跑受影響合併結果。禁止清除、reset、stash 或覆寫別人的檔案。
3. 新票以最新 origin/main 的該專案資料夾最大編號加一，開完立即 commit／push；推送前再核對撞號。不要使用對話中的舊編號 NE-177／BG-16。已發布票號不可重編。
4. 每張票分別完成範圍、受影響測試、實際截圖與下一個 Commit-N，再單獨 commit 並立即快轉 push origin HEAD:main。未完成的部分保持真實狀態。此次角色工作只有真正交付才改「審查中」；使用者同意／試玩不代勾。雲端稽核子成果先交主 Session，不能把子成果冒充整張 NE-90／NE-224 已完成。
5. 以本票開始前的固定提交執行 tools/run_tests_changed.sh，核對選出的套件確實覆蓋差異；已提交或 rebase 後不得跑空集合當通過。只跑受影響範圍，完整測試由 CI 每次推送／PR／每小時有程式變動時負責；新 CI 失敗優先修，不加入 known_failures 過關。純文件只驗內容、連結與文件預覽。
6. 截圖存該票專案 images：NE 在 pm/Nest-Egg/images、ST 在 pm/ST/images、BG 在 pm/Nest-Egg-BG/images。保留原生尺寸、命令與環境；文件圖表註明是文件預覽，無 GPU／未播放的結果不能冒充遊戲截圖。
7. 每次核對作者與提交者均 Stanley Li，email 均 stanley890314@gmail.com；commit 訊息只含票號與具體變更，沒有模型名稱、Co-Authored-By 或其他模型署名。main 不 force push；非快轉才 fetch／rebase 正常重推，401／403／權限拒絕不重試、不繞過。
8. 推送後 fetch 並核對本機 main 與 origin/main。main checkout 有他人未提交變更時不強改，明列阻塞。結案只刪本組已合入 main 且不再使用的 worktree／分支；未合併、其他組或仍使用的分支保留，遠端拒絕刪除即停止。
9. CPU headless 不需要 GPU；匯入、實際渲染與效能走共用 GPU 鎖。ComfyUI 啟停只由 Session 1 操作。Compatibility／軟體渲染不得替代本機 Forward+、HDR、發光與硬體效能。所有單像素、解剖、骨長、頂點、效能門檻維持不變。

## 新增三組雲端角色稽核

| 工作組 | Session ID | 責任與交接 |
|---|---|---|
| NPC 動作與素材 | 01a12138-b2ff-7346-8c24-1ae85307108b | 列出實際 NPC／過場外觀、頭像、素材來源、借用與缺圖，檢查部件、綁定、站坐蹲走與切換。NE-221 眼部／衣襬與共用骨架仍由主 Session 處理。 |
| 其餘人形敵人素材與步態 | 01a1213b-04f6-70f4-a409-30b41f8810a6 | 稽核其餘人形敵人來源、分割、動作、裝備與掛點；enforcer／heavy_gunner／warden 的交付仍由主 Session 處理。先唯讀辨識，需修正時交具體範圍，避免多人同改共用核心。 |
| 四足與非人形 | 01a1213c-526b-771b-9187-697a6f6010a5 | 列出實際 creature 與錯用人形者，檢查足數、父子鏈、四足支撐步序、攻擊／受擊／倒地及掛點。NE-218 看門狗美術生成與掛載仍由主 Session 處理。 |

每組先核實環境 running、repo、HEAD、origin/main、乾淨隔離目錄、CI 與 Godot 版本，才開始正式驗證；發送成功或環境 starting 不代表能執行。保留固定 base、每角色／部件／接點帳本與所有適用動作矩陣，逐項列通過、失敗、未驗證與有理由的不適用。只查到數值或來源不能給外觀通過；軟體畫面與真正 Forward+ 分開記錄。

截至本次紀錄，NPC 組讀到 /workspace 的 a85b23f94c1ed96e3226191a6b026c91436efa68，但 git fetch 與官方引擎取得均被 proxy:8080 連線失敗阻擋，安裝版本為 Godot 4.6.3，不能證明最新 main 或 Godot 4.7 正式測試。人形敵人組第一次回報 starting／offline、尚無 shell；四足組尚未回傳成果。這些是環境紀錄，沒有角色驗收通過、修改或推送。後續以各組實際回傳的版本／log 更新，不把本段當固定環境現況。

無法在雲端完成時，提交具體角色、部件、姿態、失敗證據、來源與所需本機能力；既有票範圍接回原票，真正新增需求才按最新編號另開票。主 Session 的 NE-222 與 GPU 工作持續獨立進行。
