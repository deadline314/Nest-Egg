# BG-25 水流第一階段驗證

測試與原生畫面的 main 基線：`b4c186ea401dfb29b92e28a0a9c8e7de46f604e3`。候選來源逐檔 SHA-256 見 source-manifest.json；交付前 fetched main 只新增 CLOUD_DISPATCH 文件，沒有遊戲來源變更。

Godot 4.7.2.stable.official.ed1daf0bf，Debian 13.6，hostname ec3872423d2c。原生 Vulkan Forward+ 使用 llvmpipe 軟體渲染，截圖 1280×720。不是實體 GPU/HDR/VRAM 或人工手把最終驗收。

受影響測試選擇器：41 groups，44,725 checks，0 new failures，0 known failures，exit 0；完整摘要與四份原始 shard log 保存於本目錄。Environment focused：6,052 checks，0 failures。沒有 SCRIPT/Parse/Compile ERROR。負面 fixture 預期 ERROR 原文保留，不宣稱所有原始紀錄沒有 ERROR。

同一電話亭巷、seed 25025、tile 24，baseline 以同一已載入道具的記憶體資源回復原 ripple；log 明確驗證 baseline 不建立 LocalWaterFlow，不修改資源檔。三個 high 品質畫面 clock：1.633732、2.153635、2.698985（相距約 0.520、1.065 秒）。水口與地面承接面可見；硬管固定。low/medium/high 都已真渲染，保存 low 與 high 必要畫面。

真遊戲暫停 0.5 秒：clock 3.230905 → 3.230905；恢復後 clock 前進。十次電話亭巷／街道切區，每次 local_released=true、清理後 nodes=89。static memory 原始十次值保存於 native-after.log（149099206 → 149020960 bytes，非單調累積）。射擊圖是無敵人巷道的自動射擊，只作畫面辨識佐證，不當作完整戰鬥驗收。

獨立 320×180、60 process-frame 同機單次對照（不與測試程序並行）：原效果 median 16.1075ms / p95 23.097ms；候選 median 17.505ms / p95 23.494ms。static memory 150538936 / 151041519 bytes；texture bytes 同為 128582656；nodes 771 / 773。RSS 回報 -1，未取得；不可把 Godot static memory 當作全程序 RAM 或 GPU VRAM。軟渲染單次樣本有波動，不作硬體效能承諾。

native-after 結束仍記錄 16 ObjectDB / 5 resources in use；baseline 4 / 1。測試現有 exit 診斷過濾規則未修改，原始輸出完整保留；這不證明所有引擎關閉資源均已清理。十次切區針對局部元件的 weakref 釋放已通過。

街道截圖被既有劇情移動視角，未構成蒸汽位置驗收，未列入接受的 PNG。風扇與布條尚無合適獨立活動部件，因此此交付只確認水流第一階段；BG-25 保持進行中，完整戰鬥／對話、其他物件與本機最終驗收不勾完成。
