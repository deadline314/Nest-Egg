# BG-48 證據（2026-10-20）

固定修前 83e7d318；正式資料與產生器只將本地復原館外轉用新設定。新設定由 market 原樣複製，只有 id 與 fog_density（1→0.5）異動；全區環境光、路燈、主角補光、陰影與其他地圖設定都不改。profile-diff.json 與重產比對支持此範圍。

Godot 4.7.stable，Forward+／Vulkan、HDR 2D、llvmpipe、1280×720、brightness 0.5。實驗為停止主角、原九格巡覽，同一 ContrastProbe 公式、5 次中位數和原門檻。六格有可站地面，三格在上方無地面，後者不假造玩家對比。不是硬體 GPU、手把或真人通關驗收。

原委託終端一點對比約 2.93 不能代表圓桌旁；原 c1:r1 腳掌 (472,318) 重現 full 0.499、dim 0.514。只隱藏霧的診斷為 1.572，隱藏牆影仍約 0.512；後者不作相位等同的精確因果差值。正式候選不隱藏任何層，full 0.832、dim 0.808；0.25／0.5／0.75 相位另有原記錄。支持霧為主要因素，沒有把原問題簡化成只在暗段發生。

九格 full／dim／low 各一次，自然閃爍 high／low 各一次。循環每格額外取 16 次、間隔 0.2 秒，直接記最低值，不用中位數隱藏低谷。實際時間另受軟體影格速度影響；不當硬體效能數據。

正式候選巡覽與循環的原 log ERROR 數：{'bg48-after-tour-high-full': 0, 'bg48-after-tour-high-dim': 0, 'bg48-after-tour-low': 0, 'bg48-after-cycle-high': 0, 'bg48-after-cycle-low': 0}。 合併設定時曾誤留衝突標記並啟動測試，該輪已中止並另存 bg48-merge-conflict-attempt，完全不採計；修正與驗證全部 JSON 後才執行此處的正式重跑。早期草稿的腳本／退出問題均保留並與正式候選分開，不宣稱所有 raw 無 ERROR。相鄰區域原有未通過記錄：ch2_market_gate／地面戰區（high），主角 0.590→0.590，前／後通過 False／False。此區資料未改，逐點保留，不宣稱其他區域全部通過，也不把動態差異當成已修復。 相鄰區域比較保存每點原值，動態閃爍與霧可造成小幅不同，不把硬體舊紀錄當同機修前基準。

原選擇器受影響範圍 64401 checks 零新／已知失敗；原選擇器、log 過濾與 known_failures 未改。新增 id 的真環境音／配樂 owner 負控制有兩項失敗，正式別名零失敗；沿用原聲音檔與音量。

raw.zip／manifest.json 保存每張原圖、量測、歷史失敗、測試與來源 SHA；summary、related-comparison 是原始 JSON 的摘要，不取代原記錄。硬體原生條件保持原票。

重跑：`GODOT=/path/to/Godot tools/run_tests_changed.sh 4fb216fc`；視窗用 `res://tools/readability_phase_probe.tscn -- --level=ch2_lounge_front --player --quality=high|low --lamps=full|dim --out=<absolute>`，自然循環移除 --lamps 並加 `--cycle-samples=16`。診斷 --diagnostic-no-fog／--diagnostic-no-wall-shadows 必須保留畫面標示，不當正式候選。
