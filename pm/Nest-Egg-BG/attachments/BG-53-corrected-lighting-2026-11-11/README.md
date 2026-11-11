# BG-53：修正工具的受影響場景重驗

2026-11-11，Godot 4.7.2 official、Radeon RX 9070 XT、Vulkan Forward+、HDR 2D、1280×720、亮度 0.5。全程單一原生 Godot 取得 GPU lock。這是正式場景的固定取樣與腳本朝右瞄準，不是人工通關或實體手把驗收；沒有更改產品光影、材質、人物或門檻。

## 固定答案與擷取

[原始紅 84／38、凍結來源綠 84／0與原生證據](../BG-53-pixel-area-tests/README.md)完整保留。本批使用最終浮點轉 sRGB 再量化的 PNG 編碼，完全相同 84 條件再次原生 84／0、exit 0；[原圖](../../images/BG-53-corrected-native.png)。計算直接讀浮點資料，沒有從 PNG 反推數值。擷取來源 SHA 為 `390789818b405f341a6a0a24a880971353349c8c09dc907e9fd9d8538d98addd`；像素面積修正 SHA 為 `7620b2fa090cd67d7407908f78e94492cc4164114ff9808199fd096aa0ef5b9a`。

## BG-40／42

四區高低品質各一次完整格網，102 原圖。每格 5 次中位數，空中格不造主角數值。主角 ≥ 0.6、地面 ≥ 1；敵人仍以 0.45 判定。二樓帳房的敵人未達門檻，不能因巡覽工具 exit 0（原工具只判主角與地面）而宣稱敵人通過。兩張原票維持進行中。

| 區域／品質 | 原圖／主角樣本 | 主角最低 | 地面最低 | 敵人最低 |
|---|---:|---:|---:|---:|
| ch2_ledger_front high | 9／6 | 3.675 | 6.213 | N/A（原場景無樣本） |
| ch2_ledger_office high | 12／6 | 5.136 | 4.697 | 0.262 |
| ch2_pawnshop high | 18／12 | 0.826 | 5.179 | N/A（原場景無樣本） |
| ch3_office_hall high | 12／8 | 1.024 | 6.360 | N/A（原場景無樣本） |
| ch2_ledger_front low | 9／6 | 3.651 | 5.898 | N/A（原場景無樣本） |
| ch2_ledger_office low | 12／6 | 5.250 | 4.202 | 0.135 |
| ch2_pawnshop low | 18／12 | 0.848 | 4.902 | N/A（原場景無樣本） |
| ch3_office_hall low | 12／8 | 1.169 | 5.989 | N/A（原場景無樣本） |

## BG-49

現行第一章18點各取樣16次，高、低各18／18地面有效，工具均回報門檻通過；但碼頭照片仍出現世界說明框，污染主角周圍外圈，不能拿這輪數字當作無UI的場景可讀性驗收。BG-49第一條仍未勾。碼頭使用原檢查器的靜止 sweeper，敵人實測 feet 與指定地面誤差小於4世界像素。舊算法的0.43～0.44不能作本批修前值；本批只有目前正式內容，不是歷史產品前後對照，光池、曝光與其餘點位歷史不下降條件沒有因此自動通過。

| 品質 | 碼頭主角 | 碼頭敵人 | 碼頭地面 | 全章點位 |
|---|---:|---:|---:|---|
| high | 2.906 | 1.984 | 2.306 | 18／18工具回報；提示框污染，不作驗收 |
| low | 2.819 | 2.164 | 2.340 | 18／18工具回報；提示框污染，不作驗收 |

第一輪 ch1-high／ch1-low 因共用 runner 留有 lounge 關卡過濾，0 samples、exit 1，原始失敗仍各自 ZIP 保留；修正的只是 runner 參數，重跑另存 ch1-high-all／ch1-low-all，沒有覆寫。

第一章原工具只在起始時將世界提示框設為隱藏，移動到新點後它會自行顯回。碼頭兩品質原圖可見說明框；它不在敵人框內，但進入主角外圈，故原始數字如實保留，不解讀成乾淨的主角通過。重驗需要先修正測試場的提示框處理，原素材與光影不因此改動。

## BG-48

[新公式的局部原霧參照、全區高低品質、自然循環與相鄰區域](../BG-48-corrected-2026-11-11/README.md)另存13程序、265張原圖。復原館外主角與地面通過；相鄰市集入口的敵人另有低於0.45的真實記錄。原霧參照也通過，沒有把失效的歷史數字當成這次已重現的失敗。所有原票的歷史原文與圖保留並註記舊數值失效。

## 原始位元組與重跑

[summary.json](summary.json)保留每輪真正exit、引擎錯誤行、樣本／門檻結果；[archives.json](archives.json)列各ZIP SHA與大小。7個案例ZIP共264個原始檔，包含命令、log、所有PNG、JSON及真正被測source；每個ZIP內有manifest，已逐byte驗證。旁邊的原目錄保留本機但不重複上Git；canonical是ZIP內容，避免Git正規化CRLF破壞收據。所有成功原生程序都無SCRIPT ERROR／ERROR；失敗參數啟動仍是exit1，未冒充成功。

```powershell
python pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11/verify.py
$env:NE_READABILITY_OUT='C:/Users/stanl/Github/Nest-Egg/work/bg53-fresh'
python pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11/run.py
```

重跑wrapper可從repo內尋根並指定全新輸出，拒絕覆寫既有案例。附帶的native_ch1只固定測試儲存、亮度與角色局部腳本瞄準；沿用正式第一章點位、地面有效性、16次取樣與門檻。[原始執行協調程式](orchestration-raw.zip)保留原位元組；portable wrapper修正了首輪錯誤過濾，不宣稱其整檔與失敗runner相同。

受影響6組測試3893／0新／0已知、exit0，原始log與退出診斷見[測試收據](../BG-53-pixel-area-tests/affected-tests-receipt.json)。
