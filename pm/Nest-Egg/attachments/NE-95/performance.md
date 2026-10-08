# NE-95 同機性能基線

主機與 BG-17 相同：Linux／AMD EPYC 9V74、5 vCPU、Godot 4.7 stable、Vulkan llvmpipe LLVM 19.1.7 Forward+，**沒有實體 GPU**。解析度 320×180，垂直同步／FPS 上限關閉，真實第一章市集 level_01/tile115、10 隻 grunt，seed95、持續開火14秒、品質與武器按表切換。每次共用 GPU 鎖串行執行，無 ComfyUI 生成、其他截圖、Godot 匯入或大量測試。

工具暖機：關卡 settle25、標題卡3.8秒、敵人0.8秒、取消vsync後10 frames。樣本保留首發與偶發尖峰，不刪除 outliers；未承諾所有 shader 已熱身。`--no-capture` 驗證輸出目錄沒有任何圖片；計時以 Time.get_ticks_usec 的未縮放牆鐘差值，完整包括 stalls。本票保留原配方與係數，對照衝擊波載體／重複爆炸回饋修正前後；不與其他主機或舊的縮放 delta／截圖中途寫檔數字比較。

| 品質 | 武器 | mean ms | median ms | p95 ms | p99 ms | max ms | frames | 粒子平均 | 粒子峰值 |
|---|---|---|---|---|---|---|---|---|---|
| low | rifle | 32.87 | 32.04 | 39.65 | 45.66 | 162.89 | 426 | 39.44 | 62.00 |
| low | launcher | 33.97 | 33.55 | 39.69 | 47.51 | 60.47 | 413 | 291.46 | 355.00 |
| medium | rifle | 38.21 | 37.64 | 48.23 | 58.93 | 116.49 | 367 | 35.30 | 52.00 |
| medium | launcher | 41.90 | 40.77 | 53.07 | 62.54 | 81.09 | 335 | 285.81 | 351.00 |
| high | rifle | 39.08 | 38.51 | 45.16 | 59.40 | 110.40 | 359 | 35.89 | 59.00 |
| high | launcher | 41.17 | 40.91 | 48.28 | 49.87 | 51.52 | 341 | 291.57 | 362.00 |

## 最終修前／修後

相同工具與條件，修前是原 Placeholder／雙重曝光，修後是完整環及單次爆炸回饋；只有一次樣本／配置，不主張統計顯著或全部無性能退化。ring-only 中間試驗單獨保存，不挑最好的試驗當結果。

| 品質 | 武器 | 修前 mean ms | 修後 mean ms | 修後／修前 |
|---|---|---|---|---|
| low | rifle | 31.24 | 32.87 | 105.2% |
| low | launcher | 34.41 | 33.97 | 98.7% |
| medium | rifle | 35.83 | 38.21 | 106.6% |
| medium | launcher | 36.98 | 41.90 | 113.3% |
| high | rifle | 39.75 | 39.08 | 98.3% |
| high | launcher | 40.44 | 41.17 | 101.8% |

沒有實體 GPU，軟體渲染的單次樣本差異與尖峰不能外推到 Windows／Arc。BG-17 的105%是五敵、180-frame、替換前對照的另一驗收，不能拿本表十敵／不同負載冒稱通過。實機性能仍待驗收。

重現：`python tools/comfyui/gpu_lock.py -- <GODOT> --audio-driver Dummy --resolution 320x180 --rendering-method forward_plus res://tools/screenshot.tscn -- --scenario=light_audit --level=level_01 --tile=115 --quality=low --weapon=rifle --enemies=10 --seconds=14 --no-capture --out=<絕對獨立目錄>`；Linux加xvfb-run。串行執行三檔／兩武器，禁止同時生成、截圖、匯入或大量測試。慢播只用於獨立視覺審查，不當性能數據。


修前重建：從 ea59d91b 建獨立 detached worktree，把本票最終 `tools/scenarios/light_audit_scenario.gd` 複製進去（只有計時／seed／no-capture 工具，不複製 Fx、Explosion、ShockRing），經 GPU 鎖匯入後執行同命令。修後使用本票最終版本。每次資料與主機保持一致；原始 before/、ring-only/、最終 logs 分開保存。


目前數據不能驗收「性能不受影響」：低檔步槍 +5.2%、中檔榴彈 +13.3%；需要在穩定条件補相同版本／同機配對重測與實機確認，不將差異全歸因於本票或宣稱全部通過。
