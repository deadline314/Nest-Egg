# NE-154：背包操作的正式音效

拒絕購買／安裝／典當／贖回／能力解鎖時改為介面錯誤音，成功改裝與臂盾安裝改為確認音，切槍只保留真正裝備切換音。9 個操作的回傳值與完整前後進度狀態，原版／候選逐欄一致。

既有 headless WASAPI v3 與獨立 Windows 原生 Forward+／WASAPI 兩對資料都驗得：原版 9 個音效語意錯誤 → 候選 0 個；PCM clock 問題 0。原版有聲但用了合成退回，切槍另多播一個換彈完成音。這不是人耳試聽、完整玩家按鍵流程或整章驗收。

## 附件內容與完整性

- `raw.tar.xz`：**3,724,080 bytes**，93 個明列檔案，低於 100 MB。SHA256：`0538211974cad41f362a5b348fed63e8fdc72e73f35bc73a5a15b9fa3f6597da`。
- `manifest.json`：archive SHA／size、每個 member 原始 SHA／size／來源路徑、封裝時 Godot／Python binary SHA 與 runtime 資訊。
- `archive-verification.json`：從 archive 原始資料重算的逐 case 結果、f32 峰值／能量／RMS、狀態比較及 28 個負控制。
- `source-newline-map.json`：原始來源 SHA 與僅供分析的 CRLF→LF SHA 對應、CRLF 數量。**沒有變更任何 raw 來源位元或舊 SHA**。五頁產品來源本身為 LF；音效修改全文比較明確以 CRLF→LF 正規化文字進行。
- `.gdignore` 避免引擎匯入證據；`.gitattributes` 的 `* -text` 保留 raw 位元，不讓 Git 換行轉換。
- `package.py` 是本次 allowlist 封裝程序，會拒絕覆蓋既有 archive；重算不需要執行它。

四組有效原始錄音：`valid/{headless-original-v3,headless-candidate-v3,native-original,native-candidate}/`。每組保存原始 report／console、Master／SFX／Music／Ambience 四 bus 的 f32＋WAV、兩個 legacy WAV。原生另保存 process receipt 與原生 PNG；所有 profile／APPDATA／LOCALAPPDATA 存檔均排除。receipt 中的 profile 路徑只是本輪隔離命令紀錄，不包含該目錄資料。

`source/` 保存本輪真實 probe／scene、五份原版文字、五頁候選、未改 PCM clock／reader、相關執行來源、sound bank 與實際音檔。`review/` 保存獨立審查原報告、驗證器、原生 runner、run receipts 與結果；歷史報告內的 C:/NE 路徑是原機器來源，離線重算使用下述外層可攜驗證器。

## 早期失敗沒有刪除

| archive 位置 | 原始結果 | 性質 |
|---|---|---|
| `historical/initial-stop-error/` | Ambience.stop 的 `SCRIPT ERROR`、原 probe 版本 | 尚未產生 report 或有效錄音，不是 9-case 驗證 |
| `historical/incorrect-pawn-fixture/original-final/` | 9 rows／9 failures，原 report＋log | pawn fixture 沒到預期拒絕分支 |
| `historical/incorrect-pawn-fixture/candidate-final/` | 9 rows／1 failure，原 report＋log | 同一錯 fixture，不能當作候選有效 9-case 通過 |
| `historical/incorrect-pawn-fixture/probe.gd.txt` | 原 fixture 原碼 | 保留錯誤安排，沒有覆寫成 v3 |

錯 pawn fixture 的兩版都回 false、credits 0→0、events 空，未觸發預期介面拒絕回饋。有效 v3 改用 MAX_CREDITS 造成正式 block reason，並先驗有理由，兩版再以相同 fixture 比較。上表歷史資料不算入四組有效錄音，也不冒稱最早就完成了有效 9-case 前後驗證。

## 可攜離線重算

只需此附件目錄、Python 與 numpy；不需要 repo 的 `work/`、Godot、GPU、音訊裝置或網路：

```text
python -B verify.py
```

可用 `--out <路徑>`、`--newline-map <路徑>` 另存輸出。驗證器先驗 archive SHA 與全 member SHA／size，拒絕額外 member、symlink、絕對路徑及越界路徑，安全解到臨時目錄；然後載入 archive 內凍結、未改的 reader 與獨立驗證函式。它斷言 reader 確實從該臨時來源載入，不引用本機工作區。

沿用既有 clock 契約：四 bus 實際 Capture sample clock、非 Dummy driver、零 discarded、pushed／capture／WAV frame 數一致、原始 f32 有限值與長度、逐樣本 WAV 量化一致、gain／send 穩定、共同 epoch／stop 與 cleanup=4。完整 capture 作一個連續 segment 驗證；操作間有等待，各操作窗另依記錄的真實 sample start/end 嚴格取樣，不以秒數換算或擴窗。36 個 SFX 窗均 peak>0、sum(samples²)>0。

28 個拒絕負控制完整重跑：每組各 7 個，包含未改 reader 的空 segment／超界 segment／空 raw 檔，以及操作窗讀取器的空窗／負起點／過尾／空 PCM。此為 UI 錄音的 PCM 契約驗證，不宣稱近戰 24 段命中內容契約通過。此次離線驗證 exit 0，[console](verify-console.log) 與 JSON 已附。

## 原生證據與重現限制

兩輪命令、獨立 profile 環境、退出與來源前後 hash 保存於 archive 的 native process receipts 與 `review/native-runs.json`。使用一次外層 `gpu_lock.py` 序列執行，無重啟共享服務。原版預期 exit 1／9 錯，候選 exit 0／0 錯；兩輪無 ERROR／WARNING／洩漏日誌。Godot 4.7.2、Vulkan 1.4.359、Forward+、RX 9070 XT、WASAPI。

原生重現依賴正式遊戲 repo 與資源，不是把未進版控的 `res://work/...` 當成冷 clone 既有內容。需要重跑時，先從 archive 把 `source/work/ne154-inventory-audio-20261117/` 中的 probe.gd、probe.tscn 與五份 original-*.gd.txt **複製到驗證 checkout 同名 work 目錄**，保留硬編 `res://work/ne154-inventory-audio-20261117/` 路徑；該目錄加 `.gdignore`。再依 native receipt 的同一 Godot argv，設定各輪全新且彼此分離的 APPDATA／LOCALAPPDATA／NE154_PROFILE，NE154_OUT 設全新絕對路徑，NE154_VARIANT 設 original 或 candidate。不要覆寫正在使用的工作區或原始證據。

archive 的 `review/run_native.py` 記錄這台機器安排好的路徑與輸出，**僅適用原安排工作區**，不是冷 clone 一鍵 runner。原版是在同一 runtime 裡以五頁原始記憶體腳本比較，非完整歷史 checkout；候選與 runtime raw source hash 已保留供核對。重現還需相符 Godot／遊戲版本與已匯入資源，不使用附件複製產品檔來擅自覆寫當前 repo。

原生 PNG 原樣複製至票的 images，hash 與 archive 同份 PNG 相同。它們是錄音結束後打開正式背包的情境，不能代稱當格音效波形或人耳驗收。f32 來自 AudioEffectCapture bus，非喇叭／麥克風聲學輸出。

正式受影響測試：隔離986b3a6b8基準只放入五頁音效更動，11組、6,426項、0新／0已知失敗、退出0、293秒，五份來源全程不變。原故障fixture與resources-at-exit診斷保留，無腳本錯誤，不宣稱整份log零ERROR。見official-result.json、official三份原始log及來源SHA。root另獨立從archive重算93件、36窗與28負控制成功。本附件不替整張 NE-154、實體手把或主選單到第二章人耳驗收打勾。
