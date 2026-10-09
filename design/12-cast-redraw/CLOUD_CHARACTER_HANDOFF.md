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
