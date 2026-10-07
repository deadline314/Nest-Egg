# Handoff: Nest Egg（巢蛋）— 角色畫面品質、過曝修正、任務與地圖介面、對白可讀性、序章

**Date:** 2026-10-07
**Status:** NE-213（主角過曝）已在 Forward+ 重現並修好、全部測試通過並已推上 main（commit `e2e772c5`）；使用者要求的四項新工作（NE-222、NE-223、ST-15、ST-16）只開了票與設計文件，**尚未實作**；關節接縫的試作 patch 已存檔但未採用。

## For the next agent

- Environment：Linux 雲端容器，無 GPU。專案是 Godot 4.7（Forward+、HDR 2D）的 2D 動作遊戲，GDScript。使用者用繁體中文溝通，不要太多 emoji。
- Godot 執行檔：`/home/user/godot_build/godot`（無頭，跑測試）與 `/home/user/godot_build/godot_x11`（有 X11 與 Vulkan，截圖用），皆為自編；容器重置後可能不存在，CI 的下載方式在 `.github/workflows/tests.yml`（Godot 官方 release zip，版本在 `GODOT_VERSION`）。
- 指令（照打）：
  - 受影響範圍測試：`GODOT=/home/user/godot_build/godot tools/run_tests_changed.sh`
  - 完整平行測試（約 3.5 分鐘）：`GODOT=/home/user/godot_build/godot tools/run_tests_parallel.sh`；`--only=SuiteA,SuiteB` 指定套件
  - Forward+ 截圖（軟體 Vulkan，需先 `apt-get install -y mesa-vulkan-drivers libvulkan1 vulkan-tools`）：
    `export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json; xvfb-run -a -s "-screen 0 1280x720x24" /home/user/godot_build/godot_x11 --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/screenshot.tscn -- --out=<絕對路徑> --scenario=<名稱>`
  - 啟動訊息要出現 `Vulkan … Forward+ … llvmpipe` 才算真的在 Forward+。
- 先讀（依序）：
  1. `CLAUDE.md`（開發守則、git 流程、commit 作者與訊息限制）
  2. `.claude/skills/user-priorities/SKILL.md`（使用者在意的事總表）與 `.claude/skills/visual-verification/SKILL.md`（怎麼驗證畫面）
  3. 要做的票：`pm/Nest-Egg/[NE-222]…`、`[NE-223]…`、`pm/ST/[ST-15]…`、`[ST-16]…` 與對應設計文件（見下方 Files）
- Git：本機分支 `main`，做完一張票就 commit 並 `git fetch origin main` 後 `git push origin HEAD:main`；commit 作者與提交者都是 `Stanley Li <stanley890314@gmail.com>`；**commit 訊息不得出現 Claude、GPT、Codex 等 AI 名稱，也不得有 `Co-Authored-By`、`Claude-Session` 行**（CLAUDE.md 規定，優先於其他預設）。遠端拒絕（如 403）不重試不繞過，回報使用者。
- 不要用 `pkill -f "<和目前指令相同的字串>"`：會殺掉自己的 shell（已經發生過兩次，exit 144）。

## Goal

把遊戲推到使用者滿意的品質。使用者目前最在意五件事：
1. 主角（凜）的所有部件接縫、外套、雙手、蹲姿與開場姿勢要真的正確（NE-222）。
2. 主角不能過曝，但霓虹發光要保留（NE-213，已修）。
3. 要有任務目錄、地圖與目標指引的好看介面（NE-223）。
4. 對白不要用兩三個字的斷句裝酷，要完整易懂（ST-15）。
5. 遊戲要有序章，不要沒頭沒尾直接進遊戲（ST-16）。

使用者全權交給我決定細節，要求以業界最佳實例為主、品質要求（可維護、資料驅動、高容錯、高效能、不破壞原有功能）見 CLAUDE.md §1。這次使用者特別強調「票要寫清楚驗收目標、確保能解決問題」「花久一點沒關係」。

## Current state

已完成並推上 `origin/main`：
- 開票 commit `[NE-222、NE-223、ST-15、ST-16]`：四張票、設計文件 `design/13-story-v2/DIALOGUE_READABILITY.md`、`design/13-story-v2/PROLOGUE.md`、`design/18-quest-map-ux/DESIGN.md`、`design/12-cast-redraw/RIG_QUALITY.md` 補記；NE-220 改為「封存（由 NE-222 取代）」；NE-204 Related 補上 NE-222；多關節網格試作存成 `pm/Nest-Egg/attachments/NE-222-multizone-joint-wip.patch`。

NE-213（過曝）— 已 commit 並推上 main（`e2e772c5`），票已寫 Commit-2、狀態完成（需使用者在 Forward+ 實機確認）：
- 新增 `art/shaders/character_light.gdshader`：角色零件與武器共用的受光 shader，單盞光貢獻用 tanh 壓在 `light_cap` 內，且除回補光倍率。
- `core/light_kit.gd`：`CHARACTER_LIGHT_CAP_MAX/MIN`、`character_light_cap`、`character_light_cap_for()`、新的 `character_exposure()`。
- `game/level/lighting_controller.gd`：每格更新 `LightKit.character_light_cap`，離開關卡還原。
- `game/rig/character_rig.gd`：`_light_material`、`_apply_light_cap()`，零件與武器都指定該材質。
- `tests/suite/test_exposure.gd`：新增 cap 單調、零件材質、fill/cap 寫入材質的檢查。
- `tools/test_filters.sh`：把自編 Godot 沒有 fontconfig 的訊息列為引擎備註，不算腳本錯誤。
- `tools/screenshot.gd`：新增量測情境 `exposure_lamp`、`exposure_play`、`exposure_states`、`exposure_sweep`，以及 `--legacy-exposure` 旗標。
- 修前修後圖：`pm/Nest-Egg/images/NE-213-lamp-before-after.png`。
- 測試：完整平行測試 `checks: 45249, new failures: 0`。

尚未開始：NE-222、NE-223、ST-15、ST-16 的實作。

## Decisions made

| Decision | Why | Alternatives rejected |
|---|---|---|
| 在 Forward+（lavapipe 軟體 Vulkan）下驗證畫面問題 | 泛光只存在於 Forward+ HDR 2D，Compatibility 量不到；NE-213 第一次結案就是因為在 Compatibility 下「量不到」而被使用者退回 | 只用 Compatibility（看不到泛光與過曝） |
| 過曝用「角色專用受光 shader」壓住每盞光的貢獻 | 實測主因是預設受光公式把燈的亮度直接加在白色零件上（頭靠近場景燈時全白像素 約 13%、峰值 15）；修後 0.8% | 降低玩家自己的光與閃光（第一次修正，不是主因）；提高泛光門檻（會削弱環境霓虹）；調暗白色貼圖（改變美術） |
| 多關節網格試作不直接採用，只存 patch，NE-222 再做 | 使用者明確說「除了過曝，其他開票就好」；試作有未解問題（見 Gotchas） | 直接套用試作並結案 |
| NE-220 封存而不是改回進行中 | pm-ticket 規範：結案被推翻時舊票封存並說明原因，新票 Related 寫回舊票 | 偷偷改狀態 |
| 對白規則覆蓋舊的「短句風格」指示 | 使用者明說看不懂兩三字斷句；舊文件（`SCRIPT_CH01.md`、`CHARACTERS.md`、`CH01_NARRATIVE_V2.md`）刻意要求短句 | 保留短句風格只加註解 |
| 氣泡長度放寬為每句 ≤ 30 字、戰鬥短句 ≤ 16 字且必須是完整的話 | 原本 ≤ 18 / ≤ 10 字逼出斷句 | 維持原上限 |
| 新增 skill `user-priorities` 與 `visual-verification`，並在五個既有 skill 補「使用者在意的事」 | 使用者要求把他在意的事寫進 skill，確保之後的 session 會遵守 | 只寫在 handoff（不會被自動載入） |

## Gotchas and dead ends

- **過曝的追查過程（花最多時間）**：第一次 NE-213 修正（降低玩家的光、閃光能量上限、泛光亮度上限）在 Forward+ 下完全沒有改善使用者看到的畫面。我試過：改玩家光能量、關泡光（`glow_intensity=0`）、降低頭部 modulate、換掉頭部材質，團白都不變，因為**團白來自場景燈直接照在白色頭髮與臉上**。重現方法：`--scenario=exposure_lamp@ch1_vault@0`（對比 `--legacy-exposure`）。
- 量測的坑：
  - 專案用 stretch；螢幕座標要用 `get_viewport().get_final_transform() * get_viewport().get_canvas_transform()`，只用 `canvas_transform` 會量到錯的地方（我因此一度得到「沒有變化」的錯誤結論）。
  - `rig.find_child("head")` 會先回傳 Bone2D，不是同名的 Sprite2D；要用 `find_children("head", "Sprite2D", true, false)`。
  - 用字串替換改檔時，縮排錯了會**靜默失敗**（`part.material = _light_material` 一度沒加進去，測出「shader 沒有效果」）；改完要 grep 確認。
- 自編 Godot 沒有 fontconfig：載入介面字型時每次印 `ERROR: Godot was compiled without fontconfig, system font support is disabled.`，會讓測試腳本報「Detected script errors」。已在 `tools/test_filters.sh` 列為引擎備註；官方 Godot（CI）沒有這個訊息。
- 多關節網格試作（`NE-222-multizone-joint-wip.patch`）的已知問題：敵人瞄準上抬（`aim -1.0`）時肩膀區折疊比例 0.62，超過 `mesh_fold` 上限 0.4；頂點預算要從 500 放寬到約 900；`limb_pinch` 指標在旋轉混合下變成 1.00（用「最小面積比」量，被幾乎翻面的三角形主導），不能用，需要換穩定的指標。
- 軀幹貼圖本身的問題（NE-222 要處理）：`art/characters/rin/parts/torso.png`（170×281）原本手臂蓋住的位置是挖空的；腰部黑色帶子與骨盆零件接合高度不一致；外套分成 `jacket`、`jacket_collar`、`jacket_hem_1`、`jacket_hem_2` 四片，圖層在站姿像一團破碎的藍色塊；前後手共用同一張手貼圖。這些靠網格解決不了，可能需要補遮蓋零件或重畫，不能用「看起來還好」帶過。
- 目前只有膝與肘是網格，髖、肩、腕、踝、腰、臀都是剛體直線切口。
- 開場姿勢：`tools/story/build_ch1_story.py` 的 `ch1_c01_open` 有 `{"do":"actor","id":"rin","kind":"rin","pos":[385,348],"facing":-1,"scale":3.4,"weapon":"","pose":"squat"}`，這就是使用者看到的「開場蹲著」；改完要重跑產生器再 `godot` 重新匯入，產物是 `data/story/ch1_kasa.json`。
- 對白量測：`data/story/ch1_kasa.json`（36 場景、117 行）用簡單規則（≥3 子句且其中 ≥2 個 ≤3 字）抓到 10 行違規，例子：「地點，碼頭倉庫。目標，保險箱裡一片資料盤。」「上面。我不問，你也別問。」「照抽。保費嘛，你自己簽的。去後面試試手感。」。氣泡、路牌、提示、道具描述還沒量。
- CI 曾因主測試用固定 2 影格等待而偶發失敗，已改 `_wait_until`；新的測試也不要用固定影格數等待。
- `.import` 檔要一起提交（此 repo 追蹤 `.import`）；Godot 開啟專案會產生新的，commit 前 `git status` 看一下。

## Files and artifacts

- 票與設計：
  - `pm/Nest-Egg/[NE-222]逐一檢查主角動作與部件並修正.md`（驗收條件已寫：動作清單、接縫自動檢查、外套、雙手、蹲姿、發光、效能預算）
  - `pm/Nest-Egg/[NE-223]設計任務目錄與地圖指引介面.md`、`design/18-quest-map-ux/DESIGN.md`
  - `pm/ST/[ST-15]改寫對白成完整易懂的句子.md`、`design/13-story-v2/DIALOGUE_READABILITY.md`
  - `pm/ST/[ST-16]加入序章補上遊戲開頭.md`、`design/13-story-v2/PROLOGUE.md`
  - `pm/Nest-Egg/[NE-213]修正主角有時候過曝、光暈過大看不清楚.md`（需補完 Commit-2 與狀態，見 Next step）
  - `design/12-cast-redraw/RIG_QUALITY.md`（補記：NE-222 的原因分析與試作）、`design/08-lighting/DESIGN.md`（新增「角色受光與過曝」）
- 試作：`pm/Nest-Egg/attachments/NE-222-multizone-joint-wip.patch`（`game/rig/rig_part_mesh.gd`、`character_rig.gd`、`anim_audit.gd`、`tests/suite/test_rig_mesh.gd`、`tools/rig_preview.gd` 的 diff；用 `git apply` 套回）
- Skill：`.claude/skills/user-priorities/`、`.claude/skills/visual-verification/`（新增）；`rig-animation`、`chapter-design`、`continuity-qa`、`scene-staging`、`pm-ticket` 各補一段「使用者在意的事」
- 截圖與暫存（容器內，可能消失）：`/tmp/claude-0/shots/`（`fp`、`lampcmp*`、`bisect` 等）
- 關鍵程式：`game/rig/character_rig.gd`、`game/rig/rig_part_mesh.gd`、`game/rig/anim_audit.gd`、`art/characters/rin/character.json`、`art/rigs/humanoid_tall.json`、`tools/rig_preview.gd`、`ui/pause_menu.gd`、`ui/ui_kit.gd`、`core/story_lint.gd`、`autoload/story.gd`

## Open questions

- 使用者說的「原本主角不是會亮亮的嗎？為什麼效果沒了」：我判斷是指霓虹發光（鞋、軀幹、骨盆），在 Forward+ 截圖裡鞋的粉紅發光仍在；但不確定他指的是否是別的效果（例如以前的受擊閃光或環境光對角色的照亮變弱）。NE-222 的驗收條件已含「發光效果在 Forward+ 看得到」；若他說不是，請請他指出時機與場景。可由使用者回答。
- 「蹲下的姿勢又變成奇怪的姿勢」：不確定是遊戲內蹲下、蹲著瞄準、還是過場蹲姿。NE-222 要求檢查所有蹲相關動作並加回歸檢查。可由使用者補截圖與操作情境，或實作時逐一看畫面確認。
- NE-213 是否完全解決使用者看到的「有時候過曝」：已在最可能的情境（頭靠近場景燈）重現並修好，但他的原始截圖的確切地點未知；請他在實機（Forward+）確認，沒好請他附地點。
- NE-206（NPC 像人在待著）仍等使用者確認。
- 任務目錄的資料格式與是否做傳送（電話亭網路）尚未決定：NE-223 以「任務由資料描述、第一章對照故事資料」為原則，格式由實作時設計。

## Next step

做 NE-222（`pm/Nest-Egg/[NE-222]逐一檢查主角動作與部件並修正.md`）。建議順序：
1. 開場姿勢：把 `tools/story/build_ch1_story.py` 的 `ch1_c01_open` 凜的 `"pose":"squat"` 改成符合場景的站姿或靠櫃台（看老 K 與櫃台的位置），重跑產生器，重新匯入，用 `screenshot.tscn --scenario=cutscenes:ch1_c01_open`（Compatibility 也行）確認，補姿勢自動檢查（沒有理由的蹲、坐、跪要失敗）。這是最小、使用者最先看到的問題。
2. 建立動作與姿勢清單：用 `tools/rig_preview.tscn --chars=rin --closeup --zoom=4`（以及 `--joints --level=0..3`、`--gait`、`--action=…`、`--rigid` 對照）逐項看完，把結果寫在票上。
3. 接縫與零件：先看零件圖（把 `art/characters/rin/parts/*.png` 拼成 contact sheet 放大），決定網格、補遮蓋零件或美術重畫；可以從 `pm/Nest-Egg/attachments/NE-222-multizone-joint-wip.patch` 開始，但要先解決肩區折疊與 `limb_pinch` 指標問題，並加沿關節剖面量測洞的自動檢查。
完成每一項就依 CLAUDE.md 逐票 commit 與 push；NE-223、ST-15、ST-16 之後依使用者排序處理。
