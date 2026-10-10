# BG-25 廚房蒸汽接點：獨立部分交付

## 交付內容

當舖廚房燒水壺的既有蒸汽從木柴側起霧，現在改從左側實際壺嘴開始，起始左右散布縮到 ±0.25 世界像素。硬爐、壺身、木柴、燈光與地圖擺位不變；沿用既有蒸汽大小、強度、頻率與固定容量粒子場，没有額外疊發射器。其他物件仍用原 ±2 預設。非法散布退回安全預設並記錄物件；鏡像與縮放接點局部測試通過。

本階段依主 session 指示不修改 BG-25 票，票保持進行中；本紀錄供票務 owner 追加部分交付證據。不以此把布條、風扇、全場戰鬥／對話或整票驗收勾完成。

## 測試與原生證據

- 測試來源 main：9b1c01d3cea699dda56b2999283c8996b5e65b52；candidate 逐檔 SHA-256 見 source-manifest.json。
- tools/run_tests_changed.sh 選出 41 groups：44,743 checks、0 new failures、0 known failures、exit 0。摘要與四份完整原始 shard log 保存；沒有 SCRIPT/Parse/Compile ERROR。負面 fixture 的預期診斷原文未刪。
- 素材資料檢查 exit 0、OK；沒有新增或重生成貼圖。
- Godot 4.7.2.stable.official.ed1daf0bf，Vulkan1.4.305 Forward+ / llvmpipe 軟體渲染；hostname ec3872423d2c。
- 既有 ch1_pawnshop、玩家 tile96、floor 起點row14；player y=319.9977；真 kettle 世界出氣口從 (1582,297.5) 移至 (1569.5,299)。強持有基準資源，僅在 probe 記憶體恢復舊 offset/spread，沒有修改 .tres 檔。
- 低／高品質各三張1280×720 PNG，間隔約0.5秒；保存五張必要圖於 ../../images/BG-25-steam-*.png。先前誤用 ceiling floor 的兩次診斷不算接受證據。
- 暫停0.5秒：timer=0.199041、cursor=19、整個既有粒子壽命陣列不變；恢復0.5秒 cursor19→21。
- 十次重進廚房：每次 prop_released=true、field_released=true、nodes=89。static_memory 最初147584822、最後147565446 bytes，中間147565422–147594942，沒有逐次單調成長。
- native-after exit0，raw 沒有 ERROR/WARNING；native-before exit0，raw 仍含12 ObjectDB / 3 resources退出診斷，原文保留。
- probe 暫時排除劇情播放來維持測量視角，未修改故事來源；所以這不是劇情／對話或人工戰鬥驗收。

## 同機單次性能對照

320×180、同一probe/seed/位置、60 process-frame，與測試及其他Godot渲染程序串行執行。
before: median=23.0125 ms、p95=27.488 ms；static_memory=154464819 texture_bytes=140554240 nodes=929

after: median=24.1275 ms、p95=30.486 ms；static_memory=154463983 texture_bytes=140554240 nodes=929

兩邊 nodes929、texture_bytes140554240 相同。Godot static memory 是引擎部分配置，不是程序RSS或GPU總VRAM。此為軟Vulkan單次樣本，幀時間波動不能當作實體GPU效能認證；本機最終性能驗收另由主session負責。
