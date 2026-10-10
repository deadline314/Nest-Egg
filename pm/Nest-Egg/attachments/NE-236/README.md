# NE-236 近戰階段證據

- 固定測試起點：`b4c186ea401dfb29b92e28a0a9c8e7de46f604e3`，feature branch `codex/cloud-weapon-combos`。
- 命令：啟用 `/workspace/.nest-egg-env/activate.sh` 後，`SHARDS=2 tools/run_tests_changed.sh b4c186ea401dfb29b92e28a0a9c8e7de46f604e3`；76 組、56,095 checks、0 failures、exit 0。
- [完整摘要](changed-console.log)、[程序 0](changed-shard-0.log)、[程序 1](changed-shard-1.log)。無修改 selector、runner、known_failures。原始 ERROR 包括刻意容錯與原工具已有的引擎診斷；成功不是「無 ERROR」聲明。
- [原失敗摘要](regression-before-console.log)、[原失敗程序](regression-before-shard.log)：修正前新增回歸 84 checks、9 failures。後續 [回歸調整程序](regression-initial-shard.log) 保留；最終晚目標傷害於移入判定前記錄生命，避免把自動物理命中後的值當成命中前值。
- [source／圖片 SHA256](sha256.json)、[完整 source 差異](source.diff)。只新增武器 motion namespace，已有敵人／NPC／電話動作逐項相等；角色核心、共享 Fx、故事／保存及全域 Progression 沒有修改。
- [Forward+ 原始輸出](forward-plus.log)：既有 gpu_lock + 正式單次審查的 Xvfb，Godot 4.7.2、llvmpipe 軟體 Vulkan。最終重拍明確使用 Dummy 音訊；不代表聲音人工試聽。45 張圖位於 `../../images/NE-236-*.png`，含 3.4× 畫面、高／低品質及同招式／時序回放原 motion。不是生成示意圖；原動作回放不冒稱整份舊 runtime。
- [量測原輸出](balance.log)、[50 組原始 JSON](../NE-236-measurements.json)：60Hz、6 秒合成點按，每 8 步一個明確輸入。目標固定相對距離，真 Player／Hurtbox／Enemy 傷害與反應、真充電。headless 停用畫面外 activation culling，與既有測試一致。物理步數延遲與 wall-clock 延遲分列，補步與 CPU 排程影響後者。目標固定位置取消追逐因素，不能用來聲稱人工實戰、硬體幀時間或真手把驗收。
- 五組揮空無傷害／首次命中；45 組命中樣本皆有真傷害；看門狗的受力速度和暈眩為零。DPS 是有限六秒樣本，包含充電與真節奏，不能代稱無限時間穩態。

第一版量測直接呼叫近戰命令。`first_hit_physics_ms` 記錄命令時的 engine frame 差，呼叫與同幀 physics 更新的順序造成最多一個 60Hz 步的量化差；它不能當真人端到端輸入延遲。wall-clock 數據原樣保留，不以資料中的 windup 取代量測值。鍵盤／手把事件路徑的端到端驗證獨立於此訓練場。

遠程角色接點需求及未驗收界線见 [設計](../../../../design/20-campaign-experience/WEAPON_COMBOS.md)。NE-236 狀態保持進行中，完整驗收條件保持未勾。

## 最新 main 整合

rebase 的 main 為 `eadc5f8f`（含 BG-25 水流與 NE-81 頭目發射位置），無 source 衝突。[重新匯入](import-integrated.log) exit 0，重新建立 class cache；[七組摘要](integrated-console.log)／[程序0](integrated-shard-0.log)／[程序1](integrated-shard-1.log) 共 7,017 checks、0 new／known failures、exit 0。

第一次擷取工具手設 zoom 被 LevelCamera 每步重設，實際仍是 1.5×；[原擷取紀錄](forward-plus-first-camera1p5.log) 保留，不算 3.4× 通過。工具已固定拍攝鏡頭後重拍全部 45 格，最終 forward-plus.log 逐格記錄實際 `(3.4, 3.4)`。最終票內圖片和 sha256 對應重拍版本。

推送前再次正式 fetch 並整合 `4d125c0e`（NE-232 發行工具）；只有 release tools、其設計／票據與附件更新，未變動上述已驗 runtime 接點。`git diff --check` 通過，不重跑無新增疑慮的 runtime suite。
