# NE-261 音訊來源與 PCM 錄音

錄音探針改用實際四匯流排 PCM 樣本邊界，片段結束先固定，再寫檔；以音樂與環境音的直接錄音比較背景音量。播放中的武器、招式、聲音資產及音量設定沒有因此改變。讀取器逐樣本驗證、不接受默默裁短的片段，並以有界區塊取代數百萬個 Python 浮點物件。

原本公開的 `melee-master.wav`、`melee-sfx.wav` 檔名保留，與對應匯流排 WAV 逐位元相同。一般使用者直接執行原探針及報告命令即可，不要求外部驗證工具的 `exit.json`；若提供紅色程序收據仍會拒絕。正式交付驗證另強制檢查實際程序退出碼、診斷及來源。

## 最終原連段錄音

`original-stage5` 完整保留原件、來源包、程序收據及可攜讀取器：

| 項目 | 實際結果 |
|---|---|
| 錄音 | 真 WASAPI；headless 顯示、無 GPU 渲染，不稱原生畫面驗收 |
| PCM | 四匯流排各 2,252,800 幀／48 kHz；0 丟幀、停止後計數固定、WAV 量化逐樣本相同 |
| 真操作 | 24 段；3 次手槍、15 次近戰真傷害回呼，共 18 次，實際裝甲靶材質聲 |
| 音量 | 原手槍比較、待機低於腳步 6 dB／背景 10 dB、收起停止等原規則：0 問題 |
| 原公開檔名 | 兩份各 9,011,244 bytes；與匯流排檔案逐位元相同 |
| 實際寫入故障 | 原公開檔名位置故意放目錄，真 copy error、具體來源／目標錯誤訊息、engine exit1；原件保留 |
| 讀取器控制 | 原 27 項及普通無側錄檔／紅側錄檔兩項，共 29 項通過；未降低原數值門檻 |
| 原受影響入口 | 隔離 `896d3e8a` 加最終五來源、兩個真 Godot UID；原選擇器及 changed-runner **0 groups／exit0**，列入 3,871 來源前後固定。沒有冒稱套件檢查數。 |

完整原連段的液壓錘第三擊是原設計已記錄的揮空：靶先被第二擊擊退，第三擊真查詢 0 靶／0 傷害，播放重揮動聲。沒有為了通過把靶搬回、改距離或改成每一擊都必須命中。

```text
python -X utf8 original-stage5/verify_delivery.py --raw-root D:/NestEggDeliveries/NE261-20261112/pcm-progress-20261112/stage5/accepted-raw.zip
```

此命令在暫存目錄重算逐樣本 PCM、真事件、原音量規則及兩份公開 WAV，不啟動引擎，也不覆寫原封存。原件 ZIP 82,571,586 bytes，SHA-256 `8f80304ac364f2324111b12d2e4b0f502efdc20046392e87a44fa760bb412ad9`；該大體積 PCM 原件逐位元保存在 `D:/NestEggDeliveries/NE261-20261112/pcm-progress-20261112/stage5/accepted-raw.zip`，Git 保留其完整原索引、來源、官方 0 組執行與讀取器；遠端 checkout 不含這個錄音容器。原封包 README 的預設同目錄命令須以上述 `--raw-root` 明示外存路徑取代。

## 既有資產與歷史驗收

`source-audit/source-audio-clock-packet.zip` 保存原提交 `bbe79e04` 與已發布 `a4f2db7a` 的原始 Git 位元組、讀取器與六個壞資料控制。五把各六個、共 30 個 OGG 逐位元相同；聲音庫、配方、35 個來源元件／12 個 pack 的既有 CC0 登記、快取與匯入資料一致。這是原登記鏈核對，沒有冒稱本輪重新打開全部授權頁。

```text
python -X utf8 source-audit/verify_pack.py
```

可將該標準 ZIP 解到獨立暫存目錄後執行其原 `reader.py` 及 `test_reader.py`。279 個原件的容器 SHA／逐件 SHA 均已重核，六個缺登記、錯音量、遺失來源、非 CC0 等控制都拒絕。

原票在 2026-10-12 已記錄使用者聽過附件並確認聲音；保留該既有試聽紀錄，不說成本輪再次盲聽。不同材質沿用原材質路由，與資產均沒有改動；這次新錄音只有裝甲靶，不把它稱為全材質矩陣。原 Commit-2 的 28 輪壓力測試與 1,522 檢查只有歷史文字，沒有找到該附件樹的原 log，不重建或補報通過。

原舊錄音的 wall-clock 索引末端超過 OGG，且原報告以 post-limiter Master 減 pre-master SFX 估背景；這些不能作為可信的完整 PCM 驗收。舊 OGG／索引原封保留。新嚴格報告要求樣本索引，不能把舊 wall-clock 索引直接當成新格式使用。

## 保留失敗

stage3／stage4 所有早期計數、尾端、實際無命中、觀察關閉時機、報告及寫入控制的紅綠原件仍在 `D:/NestEggDeliveries/NE261-20261112/all-red-green-raw.zip`（278,354,050 bytes，SHA-256 `6693402abc859f8eb39c5044e504a80d105908e7b4d63787b5c29a79dc7c69ea`）。相對 member SHA／CRC 由 `stage4-external-red-green-index.json` 留存。Git 不包含這個外存 ZIP；沒有從工作樹刪除其原始執行資料。

原 24 段只覆蓋原連段及延伸招，不能借它宣稱後加五個按住模式已錄過。現行按住模式另作明確範圍的補驗，不改寫這份原索引或片段名稱。


## 現行五種按住模式：真失敗補驗

`hold-supplement` 是獨立 schema／原操作，沒有把按住模式改名為原連段。兩次實際 headless＋WASAPI 錄音均自然 exit0、無引擎診斷、3,871 來源固定；真公開按住／放開、蓄滿、重複與持續上限、10 段 miss/hit、32 次真傷害及 312 次原 hit_pass 的路由均逐一核對。原 module／只觀察子類的短 A/B 狀態與傷害等價；19 個離線控制通過。

**兩輪獨立讀取器均正確 exit1，唯一問題是液壓錘待機音床。** 原完整錄音 floor −43.440892dB、背景 −44.167589dB；同輸入及時序的 metadata 重播 floor −43.717873dB、背景 −43.649280dB。兩者均未符合背景低 10dB，沒有改音量、門檻、片段或增加環境音來變綠。第二次確認 neutral 試場沒有環境音，音樂正換曲；原文件明示這不是每個正式場景都失敗的證明。共用淡化凹谷另由 NE-293 處理，NE-261 第二項保持未完成。

兩個 91MB 原始錄音容器分別外存在 `external-originals.json` 所列 `hold-supplement` 路徑；其原 SHA 為 `b49d0af2e4f26bd9e29f4925bcc110c6f3057362df958d26823bcc6a50b3be3f`、`de3c7eb2140d7dcd5775c8cc8af7802173b9cc707d84ed64d926d213133a4cf0`。原 source bundle、全部較小程序與觀察器失敗、19 控制、完整因果、每件來源 SHA 在 Git 內。將 `source-and-review-v2.zip` 及索引所列全部 raw ZIP 解到同一個暫存目錄，依其原 README 執行：等價與控制應 exit0，兩個 hold reader 應各自 exit1 且只有上述真失敗。最初 Windows 預設 cp950 讀取器拒絕及 v1 來源原封保留，v2 顯式 UTF-8，沒有重錄或修改 raw。
