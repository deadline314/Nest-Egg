# NE-274：真正的局部大字壓測

舊工具把要求的 `1.5` 寫進報告，卻經過正式設定的 `1.2` 上限；11 字級實際為 13，不能把原標示 1.5 的圖當作 17 字級證明。本次保留舊圖與原工具，只補驗證，不重畫或修改通訊外觀。

新工具明示局部壓測：要求 1.5 時，正式設定仍是 1.2，**只把通訊卡的講者、內文、繼續提示三個 Label 全部設為 round(11×1.5)=17**。實際字級比是 17/11≈1.54545，沒有把整數字級誇稱成精確 1.5，也沒有擴充玩家的全域設定。三階段逐次讀真正 theme 字級，不以要求參數作通過證據。

## 最終同版結果

最終 capture 原始碼 SHA256：`c7dff8ef0aca5590e46e2c48ebee5f6f0d9ea1d21c4cce05e7587de4be63d090`。以下只使用同版 v4，不混合先前原生來源。

| 項目 | 一般 | 局部 1.5 壓測 | 減少動態 |
|---|---:|---:|---:|
| 要求倍率 | 1.0 | 1.5 | 1.0 |
| 正式設定有效倍率 | 1.0 | 1.2 | 1.0 |
| 講者／內文／繼續提示實字級 | 11／11／11 | 17／17／17 | 11／11／11 |
| 五講者×出現／整句／快換句 | 15 張 | 15 張 | 15 張，另 5 張第二幀 |
| 長句→下一短句高度（UI 座標） | 69→53 | 121→65 | 69→53 |
| 頭像格 | 全部 40×40 | 全部 40×40 | 全部 40×40 |
| 超出畫面／裁字 | 0／0 | 0／0 | 0／0 |
| 不透明整句與快換句的對比 | 16.172:1 | 16.172:1 | 16.172:1 |
| 原生退出／ERROR／WARNING | 0／0／0 | 0／0／0 | 0／0／0 |

五講者為凜、老 K 長句、芽的下一短句、天穹廣播與無頭像的不明訊號。每一個有名稱、講者色與相符邊框，無圖時方格內為波形。15 個整句原圖已逐張檢視，另看一般的出現／快換句與減少動態的第二幀；沒有空頭像框、裁字或大字後未縮回的情形。

原生為 Godot 4.7.2、Windows、Vulkan 1.4.359、Forward+、AMD Radeon RX 9070 XT，1280×720。每輪獨立 APPDATA／LOCALAPPDATA，透過單一外層 gpu_lock 等共享生成自然完成，未重啟 GPU 或服務。完整 argv、環境覆寫、時間、退出與七份關鍵來源前後 hash 保存在各組 process receipt，三輪來源皆相同。正式設定與其他 UI 產品的 raw hash，另與工作開始前快照核對保持相同。

## 減少動態的實際像素

五位講者各比較頭像裝飾與訊號格兩塊區域，共 10 塊。每塊在相隔 12 個實際 UI 影格的兩張原生 PNG 中，**相同 pixel rect、全部 RGBA bytes 的 SHA 完全相同**；裝飾時鐘都為 0，卡片仍在 process。區域位置、hash、UI 狀態與前後圖片名稱均在 index，離線驗證器直接重讀 PNG crop bytes 重算，沒有像素容忍範圍。

此範圍不包含功能性的讀句倒數與文字。拍攝 fixture 固定玩家／NPC 既有姿勢與鏡頭，避免待機骨架讓避讓位置改變；既有移除敵人的安排保留。**沒有停止通訊卡、文字、倒數或 UI 的 process，也沒有把 tree 暫停。**這是 UI 捕捉情境，不是自然玩家戰鬥、角色動作或完整遊玩驗收。

減少動態的不明訊號兩幀恰逢背景閃電，主角有既有白閃；完整原圖保留，沒有消除背景或後製。這不屬於本票曝光驗收。即使背景改變，該兩塊 UI 裝飾像素仍完全相同；沒有用全畫面相等冒充裝飾判定。

## 原失敗及工具問題保留

- 最初原路徑負控制：要求 1.5、有效 1.2、實際 13、要求 17，退出 1。最終工具的無頭 self-check 使用同一實字級判定，先拒絕未覆寫的 13，再接受 17，退出 0。
- v1 減少動態報 5 失敗：裝飾時鐘都為 0，但人物／鏡頭與避讓位置仍變動，3 組畫素 hash 受次像素重採樣影響。原 PNG、log、index、退出與原碼完整保存。
- v2 固定捕捉姿勢後報 2 失敗：五組實際裝飾像素都已相同，卻把診斷用的浮點避讓位置也拿來做整份字典相等。最終判定改為同區域、完整像素、時鐘及持續 process；位置仍保留診斷。沒有放寬任何像素、對比或字級門檻。
- v3 明確 bool 型別之前發生 GDScript `Cannot infer the type of "stable"`。該次沒有進原生；確認命令列後只停止自己的 headless 程序，退出 4294967295 屬人工終止，不冒稱自然清理。parse error、source、退出收據完整保存。
- v4 型別修正後，先自然完成同版負控制／self-check，再三輪原生退出 0；只有這一版作最終通過證據。

原 Commit-1 的「1.5」圖片以原 bytes 保留於 archive 的 historical，不更換圖中文字或抹除過去聲明；本次修正聲明以新的真字級證據為準。不存在或未取得的 2026-10-11 全套 raw／原 index／原 log 不補造。

## 原始封包與可攜重算

`raw.tar.xz`：**62,490,056 bytes**、230 members，SHA256：`ec491c975ea114a15952bd27be35ddd2ede342c43eb460e2e81d3de2aba36dbd`。`manifest.json` 列每份檔案 size／raw SHA／來源、引擎 binary SHA。`.gitattributes` 保持 bytes，`.gdignore` 避免引擎匯入證據。所有 profile、存檔、設定及 shader cache 內容均排除；process receipt 只有隔離 profile 的路徑紀錄。

封包 `final/` 為 v4 五組程序：original-negative、self-check、normal、large、reduced；後三組包含 45 個主階段原生 PNG、5 張第二幀及所有 index／log／receipt。`historical/` 保留 v1／v2 完整資料與 v3 parse error。`source/` 是最終工具與必要執行來源，`review/` 是原始快照、各版工具、runner、獨立讀取器及結果。

只需此附件目錄、Python 與 Pillow，不需工作區 work、Godot、GPU、網路或裝置：

```text
python -B verify.py
```

先驗 archive 與全部 member SHA／size，拒絕 symlink／絕對路徑／穿越路徑後安全解到 temp，再使用封包中的驗證器。重算 45 階段的三 Label 真字級、實字級比、screen bounds、40 方格、姓名／顏色、無頭像波形、長短高度、真 PNG 背景像素與對比、讀句狀態，以及兩幀 10 塊完整 RGBA bytes；也確認原負控制及歷史失敗保留。此次 exit 0，見 `verify-console.log` 與 `verification.json`。

對比以實際 PNG 背景取樣與指定文字填色計算（不把抗鋸齒邊緣混色當作文字填色）。出現階段保留原淡入，當時對比只記錄；原門檻仍用不透明整句與快換句驗證，皆為 4.5:1，未降低。座標用 viewport final × control canvas transform，並記實際 image size／取樣點；文字整句排版採真實 17 字級，並非只改 report。

## 原生重跑

正式 tracked 工具即可重跑（每輪先設定獨立、全新的 APPDATA／LOCALAPPDATA；不使用玩家 profile）：

```text
godot --headless --path . res://tools/dialogue_box_capture.tscn -- --out=<絕對資料夾> --tag=self-check --text-scale=1.5 --self-check
python tools/comfyui/gpu_lock.py -- godot --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/dialogue_box_capture.tscn -- --out=<絕對資料夾> --tag=normal
```

另以新輸出／profile 加 `--tag=large --text-scale=1.5`，及 `--tag=reduced --reduce-motion` 各跑一次。原始負控制的 work scene／script 已入 archive；若要重跑該程序，先還原到 receipt 指定的 work 路徑。`review/run.py` 只適用安排好的 checkout，其 `--output-root` 必須指定不存在的新目錄；不是冷 clone 一鍵安裝器。正式遊戲資源需由 Godot 匯入後使用。

root 已用相同 c7 來源完成隔離正式驗證：受影響範圍挑選未選到遊戲套件、退出 0；工具真實字級自檢退出 0，省略局部覆寫的同判定負控制退出 1，兩者無腳本錯誤；CombatHudSuite 94＋UiScreensSuite 509＝603 項、0 新失敗／0 已知失敗、59 秒。其原始證據位於 `C:/NE/evidence-20261117/ne274-official`，由 root 一併收錄，與本 raw 包的原生資料分列，不冒稱完整 CI。本次依現行 AGENTS 交付規則及本輪授權完成實測後結案，不捏造歷史使用者批准，亦不代驗實體裝置或人耳條件。

### 已收錄的正式原件

本附件的official-*檔與root-archive-check.json已收錄上述隔離原始log、自檢JSON、實際來源SHA及root獨立重算。official-omit-override.gd.txt由最終c7按該輪已記錄的單行替換重建，SHA與當次producer紀錄de5de983…完全吻合，並非事後猜測另一個控制。UI回歸保留刻意缺角色的故障診斷，不宣稱整份回歸log零ERROR。
