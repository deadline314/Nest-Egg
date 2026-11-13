# NE-298 首章立體回環：v8 可攜候選

此附件記錄 published `92521d0cf3c18bd3dad4b13a316844e70bfaecd0` 加本票 21 個 v8 來源的實際測試。**不是整合後 74 個來源的 152/0 收據**；正式受影響聯集與新 Main 續玩結果另由 Root 補件。本附件不更新母票狀態或勾選驗收。

從附件目錄執行 `python -B verify_packet.py .`，只讀附件即可重驗 ZIP SHA/CRC、21 來源、歷史原件、原生來源／程序／隊列收據與全部 21 張 float→PNG 精度。程式不啟動 Godot，不讀原工作樹。原精度驗證器與 1/255 門檻未改。

## 實際結果與邊界

| epoch | 原始結果 | 界線 |
|---|---|---|
| cold-import-v1 | exit0，124.056 秒，0 diagnostic | 原 v4 來源，7 個引擎生成 UID 另列 |
| focused-v1 | 2408/11，exit1 | 首次真地形／門距離／舊 arena 配置失敗，原件保留 |
| focused-v2 | 2399/1，exit1 | 任務座標仍指向已退休 gate 的真紅 |
| focused-v3 | 2399/0，exit0 | v6 兩套件；保留 8 條原預期 warning，不能稱 0 diagnostic |
| native-high-v1 | 89/1，exit1，11 張 | v7 屋頂私有起點錯誤；原失敗與重建來源 provenance 保留 |
| native-high-v2 | 152/0，exit0，58.241 秒，21 張 | v8 HIGH，0 diagnostic，10185 runtime projection／C463／四次隊列門禁均穩定 |

CPU 最終單元 23/0；作者 18/0、completion policies 9/0、chapter policies 6/0 為各自收據。原生全部 19,353,600 pixel 用原公式重驗通過。v7 新增真 44px 身體／3 格淨空負控不倒算進 v6 兩套件綠，正式聯集將實際執行。

4 次能力前後真輸入、4 段普通路線、8 個安排視點及 1 次真 HUD 顯示，共 21 張。Vault 練習室前後 health 6→6；street 獎勵測試有實際敵人接觸 health 6→5，不能把該處稱安全區。敵人 AI／物理空間保留。HUD 圖為實際可見「空中再躍已解鎖，離地後再按一次跳躍」，有原 label／hold clock witness。

本票不另增 LOW 21 張矩陣：Root 安排由 NE295 appearance 與 BG finalheld7 的同 22v2 HIGH→LOW→HIGH 證據另行交叉引用；這些不是本附件的來源或新驗收結果。資料／碰撞不依 quality。沒有自然整章通關、實體手把、人工試玩、效能、頭部 alpha 或曝光合格聲明。

## 檔案

- `source-v8/`：21 來源 exact ZIP、事前 freeze manifest、246 舊 cell 對應；manifest 的 `engine_tested:false` 是當時 CPU freeze 原件，不回填，後續原生收據在 native metadata。
- `history/` 與 `history-index.json`：全部既存紅／綠 epoch 原 ZIP；新 native renderer 不覆蓋舊原件。
- `native-v8-high/`：原生原 PNG／float 分成 4 個小 ZIP、原 source／queue／engine metadata、私有工具、原精度 reader；`selected/` 為 7 張原 PNG。
- `topology.md`：資料幾何／遷移摘要，不代表自然走完整章。
- `commit-draft.md`：供 Root 後續獨立採用的進度段落草稿，並非已完成母票。
- `artifact-manifest.json`：本次 CPU 整理產生的精確檔案索引；不把 metadata 稱成引擎原件。

原完整 ZIP／PNG／float／log／JSON bytes 均不正規化。新增 README、reader、草稿、索引為 LF。所有驗證及來源範圍照各 epoch 分開，沒有以當前整合工作樹冒充舊 v8 capture 來源。
