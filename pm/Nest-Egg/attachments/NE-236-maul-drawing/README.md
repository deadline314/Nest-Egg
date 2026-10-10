# NE-236 液壓槌繪製與真逐格掛點檢查

基準 `0a09e1bdd97c32d947e9224267fffc8f26c63c6e`；本階段修改現有程序式武器繪製、液壓槌自己的三招視覺尾跡、近戰回歸及專用量測工具。不生成角色／武器素材，不修改 Player、PlayerVisual、RigInput、CharacterRig、HumanoidAnimator、舊姿勢、共享 Fx、Main／Level／Story／保存服務。新正式美術與角色接合仍由原 owner 驗收。

## 玩家可見差異與 source

槌的金屬柄現在連續伸入槌頭，暗色握把跨過現有手的位置；槌頭有外殼、內側平面、亮斜邊、暗側及液壓縫，小型原有狀態條發光。這是既有 fallback 的繪製改善，不代表正式武器貼圖或握持美術完成。

只降低液壓槌自己的尾跡寬度／亮度／壽命及停用殘影，共 12 個資料欄位。半徑、弧度、傷害、命中範圍、起手／有效段／收招、消耗與升級價格不變；其他武器繪製分支不變。單改金屬層的中間試拍仍被原有粗亮弧遮擋，`after-material-only-*` 保留該試拍，最終高低設定均重新拍攝。

`source.diff` 包含本階段 source 與設計差異；`trail-only-diff.json` 列出全部 12 欄。`latest-source-at-capture.json` 記錄最終 source hash；對應純文字快照避免 Godot 重複註冊類別。`latest-source-at-test.json` 為局部 suite 啟動時來源，其中 probe 尚未加 viewport 原生像素距離與動畫輸入欄位；產品／測試來源沒有因此變動，selector 相同，最終 probe 已另以真正 Forward+ 高低設定實跑。`probe-at-suite.gd.txt` 保留其原版。

## 有效測試與失敗 raw

- 修前真正 MeleeWeaponsSuite：301 checks、3 new failures、0 known failures、exit 1，85 秒。三項失敗為金屬柄伸入槌頭、握把跨作者掌心位置、非發光槌頭材質層。不是像素美術驗收。
- fresh import 在最新基準 exit 0，raw 保留。受影響測試命令固定 `SHARDS=2 tools/run_tests_changed.sh 0a09e1bdd97c32d947e9224267fffc8f26c63c6e`，47 groups、36,864 checks、0 new failures、0 known failures、exit 0，427 秒。两份 shard 無 SCRIPT ERROR；刻意無效資料與既有物理／退出清理 ERROR 均保留，不宣稱 raw 無 ERROR。沒有修改 runner、selector 或 known_failures。
- 原先試拍 damaged callback 誤用兩參數，實際扣血但 hits 統計為零，exit 1；`signal-failed.log`、錯版 probe 與六張原生 ACTIVE 圖封存，不列有效證據。修正簽名後全部六次自然出招每次命中一次，兩方向三招 HP 999→993／991／988。
- 最終高／低 Forward+：各 440 個原生 1280×720 渲染影格、六次自然完整物理出招，exit 0，無 ERROR。沒有凍結／手動 thaw、直接呼叫 hit pass 或 animate 後修改 sprite。模拟 aim 不等於人工實機手把。

## 來源與原生畫面

歷史 `before`／`after-material-only`／`after`／`after-low` 是基於 `06c440760b91f882a8da2d1aedced1f7c04fcc50`，相同場景、鏡頭 3.4、兩方向三招；最終 `latest-high`／`latest-low` 在新主線 `0a09e1b`、該主線正式 hand_left_grip 更新後重拍。舊圖與旧 raw 不覆寫；最終新圖以 NE-236-maul-latest-* 命名。

主 session 拒絕的 NE-237-maul-hit-right-2-high 與 NE-236-natural-late-contact 原生 PNG 原樣保留在 images/NE-236-rejected-*，SHA 分別為 `8f2f21b5a28c5e3e3581fed5847cf9f6463fe50509a44c211bdd02fd834d9193`、`09dec0d8509ec009e5239c7b82eea0aee4d9a0888e678f326507bf9ac74de8af`。它們的舊鏡頭／停格方式與本次自然逐格路徑不同，不拿來宣稱同姿勢 A/B。

每次有效擷取的 measurements 保留全部 440 影格的實際 phase、時間、命中、骨頭／柄兩端世界座標、方向角差、手 alpha／掌心距離。Git 中每個 native-active.tar.xz 原樣封存 **94 張**：全部 ACTIVE 影格，加各招 WINDUP／RECOVERY 首／中／末格。signal-failed archive 為六張初始 ACTIVE 原圖。archive 內原圖逐張 SHA 由 native-frame-hashes-* 提供；完整 440 張原生 PNG 和其他影格仍保留雲端 `/workspace/work/cloud-weapon-combos/maul-draw/<variant>/frames/`，不把選定 94 張說成全部 440 張已入 Git。没有縮圖、resize、調光或後期覆畫。

高／低設定均 particles 0.25、shake 0、reduce_flashes true。Godot 4.7.2 Forward+ 真渲染，adapter 為 llvmpipe LLVM19.1.7 軟體 Vulkan；Dummy 音訊，固定渲染步長 60 不是實測 FPS、硬體 GPU／VRAM／HDR 顯示器或人工聽感驗收。共用 gpu_lock 與正常單次 require_escalated Xvfb 審查，沒有修改權限或網路政策。

## 真掛點的限制與 owner 需求

歷史改前 440 格作者握點到 GRIP 中線 1.35385–1.35388 world，手 alpha 質心到中線 1.80348–1.80488；改後分別 0.03067–0.03075、0.11948–0.12099。最終原生 viewport 距離由實際 Canvas transform 量測，詳 `latest-comparison.json`，不假設 world×zoom 便是原生像素。方向誤差也逐格保存。

**目前兩方向全部影格握持 variant 仍 false，公開握點仍零；本修正是握把幾何覆盖現有手，沒有建立真正掌心掛點或閉合握手。** 最近 alpha 像素碰線只證明某個手邊緣碰到柄，不能證明掌心抓實。動畫輸入 action／action_t 與物理 ACTIVE 分列保存，不能只由物理 phase 推定姿勢已正確。所有動作仍沿正式 animator 路徑。

`GRIP-INTERFACE.md` 為提交原角色 owner 的精確 holds_melee、同手槽握持切換、真掌心掛點與方向空間接口，未套用。沒有新增假槍 id、移手腕支點、拉手臂或遮斷口。敵人腰／胯缺口仍記錄屬 NE-79／90，沒有擅改其骨架。NE-236／237 全票保持進行中；這份只交付可獨立的液壓槌繪製階段。
