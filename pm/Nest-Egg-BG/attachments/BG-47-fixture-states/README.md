# BG-47 證據索引（2026-10-20）

基準 83e7d318；Godot 4.7.stable、Forward+／Vulkan、llvmpipe 軟體渲染、1280×720、brightness 0.5、high。沒有實體 GPU／手把效能驗收。

- raw.zip 保留修前／後完整圖片、逐狀態 receipt、測試／章節稽核 log 及早期失敗。manifest.json 為解壓後每檔 SHA-256。
- v2 修前 29 checks／6 預期缺圖失敗，exit 1；修後 29 checks／0 失敗，exit 0，兩份均無引擎 ERROR。修前 checkout 的 ch2 光照另有本批候選，但本工具只載道具實驗場與 ch1_pawnshop；道具程式為原基準。
- 工具透過真投射物碰撞、切換與升降物理驅動狀態；實驗場使用高生命值，當舖使用已見故事的排列鏡頭，均不是人工操作通關。receipt 記實際場景、腳掌與相機座標。
- 原測試選擇器相對固定基準挑 51 群，55,603 checks／0 新失敗／0 known，1186 秒。原過濾器與 known_failures 未改。另聚焦 7,273 checks、素材檢查通過。
- 章節稽核 ch1／2／3 共 30 區的 placeholders 均空；修前當舖與其 dawn 共用地圖各列兩箱，不能算四個獨立物件。序章沒有獨立章節列，但 ch1 的 11 區明確包含 ch1_prologue.tres；序章地圖亦已稽核且 placeholders 為空。
- 早期 v1 前／後與 cache 診斷均 exit 250（CanvasShaderRD／DecalAtlas cleanup）；嘗試只清 VfxAtlas／ShockRing 快取仍失敗，該嘗試已移除。v2 增加正式當舖覆蓋後乾淨退出不代表找到或修復引擎根因。失敗片段與原 log 留存，沒有關閉 normal、陰影或效果掩蓋。

重跑：`GODOT=/path/to/Godot tools/run_tests_changed.sh 83e7d318`；正式視窗用 `res://tools/fixture_states_probe.tscn -- --out=<absolute>`。軟體渲染原始 wrapper 只供重現本環境。
