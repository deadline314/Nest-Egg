# NE-237 可選近戰成長階段證據

固定第一輪基準 `cd0d454f6211fb83e1ab06e183257b1fb469c726`；NE-236 自然晚目標独立交付與最新主線已整合至 `700f1dd8a931b4f1d88d68f13614b9da4256edf1`。本組檔案範圍是 Player 近戰、專用 command 子節點、MeleeSet、五種近戰資料、五筆既有型錄改裝資料、五份新近戰 motion namespace、專用測試／取證工具。另有使用者明確授權的 price_list 純報表接點，沒有改商店平衡、收益或故事 ledger。

## 實際執行與保留失敗

- 初次受影響65組：[摘要](changed-final-console.log)、[raw0](changed-final-shard_0.log)、[raw1](changed-final-shard_1.log)，55,867 checks、2 new failures、exit1。新可選招式被舊報表全部列為必要支出，必要比例125%；已授權並修正報表分列，售價不變。另一項 Feel ducking 回復時序失敗發生於同時軟體 GPU 擷取，獨立複跑通過；未改 Feel／runner／known_failures，後續 [獨立Feel raw](feel-isolated-shard_0.log) 650 checks、0 failures，exit0。
- 報表修正後65組：[摘要](changed-approved-final-console.log)、[raw0](changed-approved-final-shard_0.log)、[raw1](changed-approved-final-shard_1.log)，55,907 checks、0 new/known failures，exit0，513秒。來源校驗 [full-source-sha256.json](full-source-sha256.json) 對應當輪 runtime；最後自然晚目標回歸另於後述整合實跑。
- [Economy／Progression](economy-fixed-console.log) 412 checks、0 failures、exit0；[接觸／輸入回歸](contacts-final-console.log) 411 checks、0 failures、exit0；[自然晚目標三組](natural-late-first-console.log) 538 checks、0 failures、exit0。所有新拒絕、中斷、guard／gun 付費取消、phone／vehicle／GameplayLock／暫停／死亡、方向鎖定、两鍵全部五武器 hold、event／poll 去重、真 mapped 合成JoypadButton、冻结期间接收和过期均實跑。合成裝置不代稱實機手把。
- regression-first／second／third／fourth／landed-hold 原始失敗全留：初期測試用錯既有 reset／damage 契約、相對 XDG 路徑受 readonly home 限制、Joypad dispatch 需 render process frame、物理 timer 不等同單調時鐘到期等均在測試修正後複跑。沒有改 runner／selector／known_failures 或放寬真傷害／能源／一次命中規則。
- raw 中刻意容錯、既有引擎／音訊與退出 ERROR 保留，成功不是「無 ERROR」聲明。

## 公開購買與保存邊界

五招實際公開購買，80／100／140／120／100 共540；重複／餘額不足拒絕，錯武器不適用。短首招 hold 不接後招，追加招要點按，護盾8／18／30／20／16，終段不得提早取消或循環。錘另外付電量；護盾不足不先扣電量。收入、充電與全域保存服務沒有另造。

已沿公開 snapshot／restore 驗解鎖保留；严格 prepare_install 真回 `install/progression/upgrades unknown weapon or invalid list`，因合法武器型錄只掃根目錄而未包含 `data/weapons/melee`。回歸明確記錄此 NE-230 依賴，沒有把拒絕當真退出續玩成功，最後一條驗收保留未勾。精確 owner 需求見設計文件。

原三筆改裝370＋必要補給200＝必要570；選購540另列；全部改裝910保留。舊第一章靜態區域收入888，必要比例64%。這只是資料對帳，不是序章／第一章實走、不刷錢通關或永久成長保存驗收。

## 基礎與追加比較

[基礎50筆](balance-base.json)、[正確追加50筆](balance-upgraded-fixed.json)、[完整配對](comparison.json) 與兩份 balance raw。60Hz、六秒，每8 ticks合成明確點按一次；真 Player/Hurtbox/Enemy 傷害／反應，固定相對距離、AI停用，包含 hitstop、充電、guard。每模式45組命中、5組遠距揮空；普通／裝甲／看門狗，assist／standard／hardcore。追加每一筆命中均有實際 tail damage event，upgrade_owned=true；五筆miss零傷害。看門狗全部自身擊退與暈眩為零。

| 武器 | 基礎→追加 DPS | 首擊物理 ms | 基礎→追加鎖定比例 | 追加招真擊退速度 |
|---|---:|---:|---:|---:|
| melee_dagger | 5.67→5.67 | 33.3 | 95.0%→100.0% | 64 |
| melee_blade | 6.02→6.50 | 83.3 | 95.8%→98.1% | 104 |
| melee_maul | 5.72→6.51 | 350.0 | 78.9%→92.5% | 232 |
| melee_glaive | 4.54→4.33 | 150.0 | 94.2%→96.4% | 120 |
| melee_whip | 2.66→2.83 | 183.3 | 90.3%→95.8% | 64 |

表為 standard grunt 六秒樣本，DPS 以真 wall seconds；首擊以 physics步數。鎖定比例是360步中實際不能取消的步數，包含局部停頓，不是圖形幀時間。有限樣本受點按相位與排程影響，不代表無限時間穩態或人工延遲。長柄追加提供較寬掃擊、較重單擊並付較長風險，沒有承諾每一種追加必然提升DPS。

第一份 [錯誤追加50筆](balance-upgraded.json)／[raw](balance-upgraded.log) 必須排除：購買發生於 Level ready 還原之前，解鎖被還原清掉，flag雖標追加、實際只有基礎段。工具改為 spawn 完後公開購買，再逐筆斷言升級存在及真追加段；上面的 fixed50 才是交付數據。錯誤資料原樣保留，沒有覆寫冒稱通過。

## 真畫面與動作

90 張真 Forward+：五武器購買前後10張、兩面向三段高低FX60張、兩面向高低FX真尾招命中20張；相機實際3.4×。低品質particles.25／shake0／reduce_flashes=true。沒有生成素材或修改舊姿勢／CharacterRig／HumanoidAnimator／RigInput／PlayerVisual。

[首輪70張](forward-plus.log) 拍 WINDUP 起點的中性姿勢，不用它冒稱前搖預備峰值；最後改拍前搖65%時序，原 raw 留存，最终照片與 hash 對應重拍。[命中第一次失敗](forward-plus-hit.log)：新生成目標尚未 activation，保存退出1；[修正後20張](forward-plus-hit2.log) 使用已註冊真Hurtbox移入，全部hit=true和真HP減少。

gpu_lock＋正常單次審查Xvfb／Godot4.7.2 Forward+／llvmpipeLLVM19.1.7軟體Vulkan，Dummy音訊。不是硬體GPU／HDR／VRAM性能或人工試聽／實機手把驗收。有效段圖在真接觸姿勢；命中擷取為定格取證，完整風險由自然physics测试與量測独立驗，不能用定格圖冒稱無限風險／人體關節完整驗收。


## 最新主線完整受影響複驗

命令 `SHARDS=2 tools/run_tests_changed.sh 700f1dd8a931b4f1d88d68f13614b9da4256edf1`；[摘要](changed-latest-main-console.log)、[程序0](changed-latest-main-shard-0.log)、[程序1](changed-latest-main-shard-1.log)：65組、55,932 checks、0 new／known failures、exit0，467秒。包含 Main／RunSave 通知修正後的真購買、near/far尾招、自身反應、兩输入路徑、有限 hitstop／buffer、全部拒絕與中斷回歸。沒有在 commit 後選空 diff。

[當輪來源校驗](latest-suite-source-sha256.json)涵蓋實際 runtime／資料／測試；此後只修改專用擷取工具的按武器篩選與重錘鏡頭位置，其實際執行另存 raw，沒有改 runtime 或驗收 runner。


最後重錘前搖接近畫面上緣，專用鏡頭由相對Y=-32移至-44，按 `--weapon=maul` 補拍兩面向三段高低FX12張；[最後raw](forward-plus-maul-framed.log) exit0，對應最終同名12圖。其他照片來自前搖重拍70與真命中20。工具的最終改動僅篩選和鏡頭，不改Player物理、判定、角色或motion資料；完整舉錘輪廓可見。[執行結束碼](execution-receipts.json)。


最後審查移除描述測試的未釋放临时改裝卡節點，沒有更動測試邏輯／斷言或runtime；[最終近戰298檢查](final-test-disposal-console.log)／[raw](final-test-disposal-shard-0.log) 0 new/known failures、exit0，76秒，全部新拒絕／中斷／自然晚目標重跑。最終差異與校驗以 [source.diff](source.diff)／[sha256.json](sha256.json) 為準。

兩份 suite-source-sha256 是當輪歷史來源，不假裝最後兩個檔案仍相同；差別只有取證工具的鏡頭／篩選，以及測試释放UI。相同歷史bytes保存在 historical-test-before-natural.gd.txt、historical-test-before-disposal.gd.txt、historical-capture-before-framing.gd.txt，均為純文字避免再登記 class_name。其餘runtime／資料仍與65組全過來源逐位元一致；最終測試與取證工具分別有真實重新執行raw。
