# 當舖、帳房與接待廊的補充可讀性（BG-40／42）

> 量測更正（2026-11-11，BG-53）：下列歷史亮度與對比數字使用錯誤的像素面積，不能作為通過、失敗或修前修後改善的依據。原文與原圖保留；修正工具的本機重驗另列。

2026-10-20。開始前依 User-guide 核對兩票全部既有交付；既有正式素材與擺位不重做。本批 BG-48 只降低復原館外局部霧，BG-49 只改第一章街道末段敵人補光，沒有更改此處四區的地圖與素材。

以 Godot 4.7.stable、軟體 Forward+／Vulkan HDR、llvmpipe、1280×720、預設亮度 0.5 重拍原 SceneTour 的地面帶（r1／r2、全部水平欄）。這是補充對照，**不是整圖巡覽、真 GPU 或真人操作驗收**。原工具固定玩家、敵人及相機，用原五次中位數、公式與門檻；數值判定用未四捨五入的原值。無地面格不造玩家數據；無敵人樣本記 N/A。

復原館外另外保有 [BG-48 的完整九格與自然循環證據](../../pm/Nest-Egg-BG/attachments/BG-48-lounge-readability/README.md)，此處不重複拷貝。原實體 Arc GPU 的修前結果不與本軟體數字冒稱同機比較；最後原生條件維持未勾。

| 區域／品質 | 圖數／玩家樣本 | 主角最低 | 地面最低 | 敵人最低 | 原門檻 |
|---|---|---|---|---|---|
| ch2_pawnshop high | 12／12 | 0.630 | 10.084 | N/A（無敵人取樣） | 通過 |
| ch2_ledger_front high | 6／6 | 0.757 | 11.432 | N/A（無敵人取樣） | 通過 |
| ch2_ledger_office high | 8／6 | 0.695 | 11.154 | 0.405 | 未通過 |
| ch3_office_hall high | 8／8 | 0.871 | 10.474 | N/A（無敵人取樣） | 通過 |
| ch2_pawnshop low | 12／12 | 0.695 | 9.613 | N/A（無敵人取樣） | 通過 |
| ch2_ledger_front low | 6／6 | 0.793 | 10.534 | N/A（無敵人取樣） | 通過 |
| ch2_ledger_office low | 8／6 | 0.861 | 8.936 | 0.418 | 未通過 |
| ch3_office_hall low | 8／8 | 0.895 | 9.588 | N/A（無敵人取樣） | 通過 |

原生 log 的 ERROR 數：{'high': 0, 'low': 2}；原始訊息完整保留，不以退出碼或量測通過取代乾淨原生執行。

[全部原圖、索引、逐檔 SHA 與摘要](../../pm/Nest-Egg-BG/attachments/BG-40-42-readability-followup/README.md)。參考延用 [五款同類型遊戲原圖](READABILITY_REFERENCES.md)，沒有另做未查證的偏好民調。


## 2026-11-11 正確面積的硬體重驗

原表數值失效。本機9070XT／Forward+、亮度0.5完整格網，高低各51圖，實際主角樣本各32；場景與門檻保持。

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

二樓帳房敵人低於0.45，BG40／42驗收維持未勾。[原圖、source／命令／log與逐byte ZIP](../../pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11/README.md)。
