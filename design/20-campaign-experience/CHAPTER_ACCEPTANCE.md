# 各章驗收與發行清單（NE-233／NE-234／NE-235）

2026-10-11。三張驗收票的條件相同，只差收錄到哪一章。這份清單把每一條拆成「自動檢查」「雲端軟體渲染」「需要人或實機」三種證據，避免用工具通過冒充人工遊玩，也避免該自動化的事每次手動重做。各章擋住的票先用 `python3 tools/release/chapter_gate.py NE-233 NE-234 NE-235` 查，全部完成（或審查中）才開始逐條驗。

## 開始前（每章一次）

1. `git fetch origin`，在最新 `origin/main` 上記下基準 SHA；之後所有證據都要對應同一個提交，不能拿舊來源的綠燈證明新 main。
2. `chapter_gate.py` 顯示「可開始驗收」。
3. `python3 tools/release/campaign_build.py prepare --source <SHA> --through <章> --version <版本> --out-root <repo 外>`：版本設定寫入、資源閉包 0 缺漏；readiness 只剩本票自己的驗收證據時才往下。
4. `tools/run_tests_changed.sh <基準>` 受影響範圍全過；CI 在同一提交為綠。

## 逐條驗收

| 驗收條件 | 自動檢查（雲端可跑） | 雲端軟體渲染（Forward+／lavapipe） | 需要人或實機 |
|---|---|---|---|
| 從正式新遊戲入口完整遊玩到章末，主線、支線、死亡、跳過、續玩合理 | `run_continuity_probe` 全部模式（序章不重播、探索與世界、成長與獎勵、死亡後關閉、區域遺失、版本鏈）；`run_save_probe` 既有模式；`continuity_report` 旗標誰寫誰讀；`quest_map_audit` 任務接線 | 選單、完成卡與修復說明截圖 | 人工從「開始任務」玩到章末一次，中途至少一次死亡、一次跳過演出、一次真的關閉再續玩；記錄每區時間與問題 |
| 逐區長度、迴圈、捷徑、落點、檢查點與敘事節奏 | `pacing_report`（每區時間、遭遇數、無遭遇連續段）；`scene_report`（佈景合理性錯誤數為 0） | `scene_tour` 逐格拍整區 | 人工確認捷徑與回訪有用途；問題開票並列進本票的阻擋 |
| 場景與電影舞台比例、支撐、裝飾、人物接地、無占位素材 | `scene_report`、`humanoid_scope_audit`、`world_item_inventory` | `scenery_capture`、`scenery_stage_capture`、`ne251_wake_probe --mode=sweep`（頭部純白 < 2%） | 本機 GPU 看過曝與泛光（軟體渲染只看形狀與接縫） |
| 敵人種類、重複、密度、預兆、難度；素材、骨架、動作、音效已整合 | `rig_joint_audit`、`rig_pose_report`、`rig_locomotion_report`；`free_encounter_native_probe` | `rig_preview --chars --closeup`、`creature_preview` | 人工打過每種敵人一次；音效試聽 |
| 武器、子彈、盾、近戰的動作與打擊感，升級不破壞平衡，特效不遮危險 | `weapon_balance_probe`、`weapon_guard_probe`、`economy_report`（必要準備與選購合計） | `weapon_combo_capture`、`weapon_growth_capture`、`projectile_visual_capture`、`vfx_exposure_probe` | 人工手感（NE-241 的總驗收）；實體手把震動 |
| 正式任務、HUD、介面、手把與 21:9 過渡 | `quest_map_probe`、`controller_flow_probe`（合成手把事件，只算邏輯） | `hud_guidance_capture`、`pixel_ui_capture`、`cinematic_framing_probe`、`run_save_ui_probe` | 實體手把全流程（開始／繼續、戰鬥、對話、商店、地圖、死亡、章末）；原生 21:9 視窗 |
| 累積單檔在 Windows 乾淨目錄可啟動可玩，記錄版本、體積、校驗碼與章末 | `campaign_build.py prepare／import-stage／verify-stage／export`，`pack_integrity` 逐項校驗；Linux 乾淨目錄啟動 | — | Windows 真機：只放單一 EXE 的乾淨目錄啟動、玩到章末看到「本版本收錄到這裡」、確認存檔在 `runs/through-<章>/` |
| 自動、軟渲染、人工、實體手把、本機 Forward+ 分開記錄 | 本表每欄各自留證據 | | 未驗的欄位不勾、不寫成通過 |
| 從正式新遊戲入口自然完成，不跳區、不手授旗標 | `run_continuity_probe` 的版本鏈模式會用 fixture，**不能**當作這一條的證據 | | 人工全路線紀錄，同一提交的受影響測試與自然退出紀錄留存 |

## 版本與存檔（三章共用）

- 「序章至第 N 章」的存檔在 `user://runs/through-<章 id>/`；新版本可接續舊版本的進度且舊檔不變，舊版本看到新版本存檔只提示（NE-230）。驗收時至少做一次：用前一章的包玩到章末 → 開新一章的包 → 主選單出現接續提示 → 續玩直接進入新一章入口。
- 最後一章停在完成卡，同一行寫「本版本收錄到這裡，進度已保存」；不能出現未收錄章節的關卡。

## 證據放哪裡

票的 Commit 段落只寫問題—改動—驗收與精簡表格；原始 log、manifest、校驗碼放 `pm/Nest-Egg/attachments/NE-23x/`，截圖放 `pm/Nest-Egg/images/NE-23x-*.png`。軟體渲染截圖要標明 llvmpipe，不能代替本機 GPU 的過曝判斷。
