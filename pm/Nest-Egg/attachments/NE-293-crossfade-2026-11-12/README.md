# NE-293：修正換曲時的音量凹谷

同音量的實際固定輸入錄音由中段最低 −23.871dB 改為 +0.008686～+0.008697dB；不同音量／時間的錄音也符合各自的振幅曲線、秒數及端點。公開音量目標、滑桿、原壓低音樂包絡與釋放機制保留。實際五種近戰按住模式重走原操作，34段、32次真傷害與原音量規則全部通過，液壓錘待機聲未調低。

本票產品只有兩檔；`source-adoption.json` 記錄已測兩檔如何採入主要工作區。原文及九項追加回歸均經審查，原斷言保留。原受影響入口為原 Godot 執行檔、原 headless/default audio、30組／47,507項、0新／0已知失敗、腳本exit0；137行預期錯誤保留，0 SCRIPT ERROR／退出洩漏。額外觀察器沒有抓到各child退出碼，沒有補造。另袋的WASAPI加強測試不代稱原入口。

## 原件與重算

`packet/` 保留驗證代理交付的10份原件，逐位元未改；其中 README 是隔離驗證階段的原稿（其「C未改」指該階段），不是說發布時沒有採入產品。它的 source/proof ZIP、候選 SHA、原始執行命令、log、資料及每member SHA／CRC均由內附索引核對。封包已由交付者與主協調各在新的暫存目錄重算成功。

在任何位置可執行：

```powershell
python -X utf8 pm/Nest-Egg/attachments/NE-293-crossfade-2026-11-12/packet/verify_delivery.py --raw-root D:/NestEggDeliveries/NE293-20261112
```

需沿用既有 NumPy／Pillow；不啟動引擎、GPU、網路或來源工作樹。六個獨立讀取器的預期退出碼依序為 **0、0、0、0、1、0**：狀態、同音量PCM、不同音量PCM、原default30、原hold失敗、新hold通過。讀取器完整核對封包及大型錄音，不只讀文字摘要。

大型原始PCM另存持久路徑 `D:/NestEggDeliveries/NE293-20261112`：

- `before-hold-red-raw.zip`：91,569,131B，原NE261第二次失敗的逐位元副本。
- `after-hold-green-raw.zip`：92,391,412B，本次原34段操作真錄音。

兩份的SHA／逐member索引均在 `packet/index.json`。遠端checkout只含小型原始證據與讀取入口，**不含這兩份大型PCM**；另一台機器需要帶上外存原件並改 `--raw-root`。原工作錄音與較早另一輪失敗仍保留原位。

## 驗收範圍

固定PCM證明算法凹谷的消除，不把任意不同音樂說成恆能量；不同淡化時間仍可能有其合理音量起伏。34段是同原輸入的另一輪自然演出，非每個樣本byte A/A；只量實際裝甲靶，不代稱新全材質或真人試聽。原NE261的使用者試聽紀錄保留。三張波形是實錄數據圖，不是Forward+視覺截圖或GPU效能驗收。
