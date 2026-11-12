<!-- 僅草稿，尚未寫入pm。Root獨立確認原圖與讀取器後，再將狀態改完成；原Commit-1保留。 -->

# Commit-2

## 內文

補上可獨立重算的畫面與弱點回饋證據。正常畫面中，真敵人頭部及其他弱點的四角框已消失；開發debug仍會在真頭部畫黃框、普通砲塔畫青框。三張未改像素的原生圖、來源、浮點讀回與讀取器一起保存。

同一批真actor、同一姿勢／鏡頭依序比較正常、只還原舊繪製函式、恢復正常、debug與再次正常。三張正常圖及浮點原件完全相同；獨立讀取器按真部位幾何驗到legacy24線段與debug12線段。這是只還原舊draw的單因素對照，沒有假稱完整歷史版本重跑。

受控真head／body命中另外量到傷害2／1、head部位與weak旗標、真weak callback生成粒子、實際聲音leaf事件和準星弱點timer；故意拿body冒稱head、讓正常畫面仍有框、關掉debug以及錯投影都被拒絕。聲音資料／弱點音檔與函數對照另封，沒有把事件驗證說成人工試聽。

原550項測試未找到原始log／command／exit，保留為歷史原文，不由本次數字補造。首輪工具粒子期待錯誤、首輪相機太近導致框出viewport都保留；新構圖只修工具倍率，不動敵人或門檻。

### 測試結果

| 項目 | 結果 |
|---|---|
| 真head／body API控制 | 14/0；body冒稱head的4項真負控制拒絕 |
| 原生正常序列 | 13/0、engineexit0；獨立24段legacy＋12段debug全通，三張正常完整float/PNG相同 |
| 原生故障與錯投影 | after-still、debug-off新reader各exit1；24px錯投影亦exit1；原engine0與reader拒絕分開記錄 |
| 可移植唯讀核對 | raw539＋source90檔CRC/SHA、原失敗、C364／queue／三張原PNG重算成功；Python10控制通過 |

新[原生來源與完整紀錄](attachments/NE-262-weak-bracket-2026-11-12/README.md)供Root移入正式附件後連結。完整raw若外存，以index列SHA，repo reader用 `--raw-root` 重算。沒有新的產品差異。

### 截圖

![舊draw單因素](images/NE-262-legacy-before.png)

![正常無四角框](images/NE-262-normal-after.png)

![debug真黃／青部位](images/NE-262-debug-parts.png)

<!-- Root若引用已封正式42回歸，請使用其真路徑與NE228/NE231聯合scope，明記非本D8c同源，也非原550。此草稿不自行回填該次執行。 -->
