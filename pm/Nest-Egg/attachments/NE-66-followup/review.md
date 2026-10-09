# NE-66 2026-10-09 當前版光影複驗

基線 `dfacf916`。獨立 checkout：`codex/session-environment-performance-followup`；原四筆交付均保留。Session 3 的 ST-6 第一章地圖與 Session 1 的角色／HDR 擷取成果已從 origin/main 取得並重新匯入。

主機：Linux AMD EPYC 7763、可見 5 CPU、cgroup CPU 配額 4 核；Godot 4.7 stable、Forward+、Vulkan 1.4.305 llvmpipe LLVM 19.1.7，無實體 GPU。此主機與前輪 EPYC 9V74 不同，**不互比兩輪效能數字**。本輪沒有新增效能或 VRAM 通過聲明。

## 原生驗證條件

640×360；亮度 0.5；每點 16 樣本、間隔 0.2 秒。門檻原封保留：玩家 0.60、地面 1.00、戰鬥區敵人 0.45。第一章依最新 roster 九份關卡資料／十四點，安全區不虛構敵人；戰鬥區使用確實存在的 sweeper。第二章保留十點 grunt 探針。共用 GPU 鎖串行執行，沒有 ComfyUI 操作。

PNG 改用 main 既有 ViewportCapture，將 HDR readback 編碼為 sRGB；ContrastProbe 仍量原始線性 HDR，沒有改亮度、曝光、對比算法或門檻。舊線性 PNG 保留為歷史，不能直接與本輪顯示編碼作風格差異比較。既有 sRGB 檢查驗證 HDR／LDR 的已知色、alpha、尺寸及 LDR bytes 保持，退出 0。

## 結果

| 範圍 | 有效通過 | 真實結果 |
|---|---:|---|
| 第一章 low | 13 / 14 | 電話亭 玩家 0.593114、地面 1.870257、敵人 N/A |
| 第一章 high | 13 / 14 | 市集 玩家 0.560391、地面 5.180511、敵人 0.571014 |
| 第一章 medium | 2 / 2 | 全部取樣有效且達標 |
| 第二章 low | 10 / 10 | 首輪八個有效點＋修正後兩點；不是首輪整包通過 |
| 第二章 high | 10 / 10 | 首輪八個有效點＋修正後兩點；不是首輪整包通過 |

第二章首輪兩點取樣無效，兩份退出碼 1／原始报告保留。升降井敵人在 106 欄撞上實體油桶，改用同區空位 108 欄／第 14 列；電力室敵人在 356 欄被天花板幾何困住，明确使用第 20 列地面。僅改工具資料，地圖、家具、燈、角色、骨架均未動。兩點低／高各 16 樣本重測，站立有效且退出 0；新增幾何檢查擋住地面、淨空與油桶錯位。無效點不算暗場通過，也不把它報成有效的太暗結果。

| 修正後點 | 品質 | 玩家 | 地面 | 敵人 |
|---|---|---:|---:|---:|
| 升降井 | low | 0.702395 | 27.189615 | 0.562588 |
| 電力室 | low | 0.828640 | 25.688024 | 0.643401 |
| 升降井 | high | 0.628688 | 27.581296 | 0.541028 |
| 電力室 | high | 0.779023 | 25.523919 | 0.543554 |

首輪完整關卡工具結束仍出現 ObjectDB／resources-at-exit 清理訊息；保存原始 log，不聲稱所有 log 無 ERROR。兩點修正後沒有腳本錯誤，退出 0，但仍有 ObjectDB 清理警告。新腳本錯誤及受影響測試失敗均不豁免。

## 接手與待審查

- Session 3：電話亭巷 `ch1_booth_alley` 26 欄／第 20 列、第一章街道 `ch1_street` 60 欄／第 20 列是當前實際站立有效的低／高檔不足點。此輪未移動燈或家具，未修改故事產生器；若採局部場景光影／燈資料修正，請由關卡資料與產生器同時保留，避免下次重建覆寫。電話亭低檔 0.593、高檔通過；市集高檔 0.560、低／中通過，不可只測單一檔。

- Session 1：上述樣本使用 `dfacf916` 角色與 shader；沒有更改角色、共用動畫、來源或全局光影參數。角色後續合入後須同場景再驗，不將本輪不足武斷歸因於角色。

- 使用者：審查本輪當前市集三檔與當舖／電話亭等原生圖；風格確認仍未勾選。BG-17 的實體 GPU 記憶體、替換前低檔 105% 仍阻塞，NE-66 不結案。

## 重現

```sh
source /workspace/.nest-egg-env/activate.sh
python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/ch1_readability_check.tscn -- --quality=low --capture-prefix=NE-66 --out=<絕對目錄>
python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/readability_check.tscn -- --level=level_02 --spots=升降井,電力室 --quality=high --capture-prefix=NE-66 --out=<絕對目錄>
SHARDS=4 tools/run_tests_changed.sh dfacf916
```

品質切 low／high 可重跑全章；medium 只取本輪街道兩點。新工具可跑完整第二章，舊首輪報告不可覆寫。PNG、JSON 與每次退出碼均在本輪目錄。受影響測試 1 組 ReadabilityTargetsSuite、134 checks，new／known failures 皆 0；只跑本次差異，不重跑完整套件。CI API 查詢仍 Forbidden，未驗證遠端 CI。

![目前市集三檔](../../images/NE-66-followup-three-tiers.png)
![未達標點](../../images/NE-66-followup-readability-issues.png)
![探針修正前後](../../images/NE-66-followup-probe-before-after.png)
