# BG-49 證據（2026-10-20）

固定修前 83e7d318；修後已含 BG-47 5966b35e。Godot 4.7.stable，Forward+／Vulkan HDR 2D，llvmpipe 軟體渲染，brightness 0.5、1280×720。不是實體 GPU 或真人戰鬥驗收。

原工具的 18 點、16 次取樣、公式與門檻不變；新觀察器只加私有設定、畫面標示與 HDR 曝光觀察。comparison.json 保存兩品質每點的前後數值與差；全部 18 點通過，其餘 17 點玩家／敵人差均不低於 -0.05。

新設定只有 id 與 enemy_fill_scale（0.8→0.5）異動；環境光、霧、陰影、霓虹與路燈樣式／種子不變，產生器重產與正式資料逐 bytes 相同。

碼頭完整外觀矩形有全白像素，尚不能用含背景的分母判定敵人比例；曝光條件維持未勾。 早期 critical-v2 只覆蓋舊對比框，不能當作整個身體的曝光證據；最終全章觀察明確記 visible rig parts and weapon bounds。非零矩形不推算純敵人比例。

光池原探針仍保留全部八盞活燈原始結果：修前中位 7.697、修後 7.542；靠近新區段的 tile176 為 4.692→2.666。tile201 原本是壞燈，未產生活燈記錄。燈設定完全相同不能取代這項實測；沒有把數值下降勾成「不低於修前」，也沒有為追數字調亮其他光源。

受影響範圍原選擇器 63 群、64392 checks，零新／已知失敗；原 log 過濾與 known_failures 不變。環境音／配樂真 owner 負控制移除新別名有兩項失敗，還原原 bytes 後零失敗；不新增音訊素材。早期未正確等待 autoload 的草稿編譯錯誤保留但不列入驗收。high exit 0，ERROR 1；low exit 0，ERROR 0。引擎錯誤完整保留，不當成乾淨原生驗收。 原生全章與測試各以實際退出結果為準，不能寫全部 raw 無 ERROR。

raw.zip 保存修前／修後圖片、18 點原報表、HDR 觀察、光池與歷史草稿；manifest.json 是逐檔 SHA。原 NPC 來源警告保留，不為本票更動角色來源。

重跑：`GODOT=/path/to/Godot tools/run_tests_changed.sh 5966b35e`；正式視窗 `res://tools/harbor_readability_probe.tscn -- --quality=high|low --detail --out=<absolute>`；光池用既有 `light_pool_probe.tscn -- --level=ch1_street --max=40 --quality=high --out=<absolute>`。
