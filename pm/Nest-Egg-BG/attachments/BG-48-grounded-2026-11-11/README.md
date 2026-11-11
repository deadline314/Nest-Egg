# 復原館外：真接地、同格霧量控制

這是 RX 9070 XT／Godot 4.7.2／Vulkan Forward+ 的腳本控制原生畫面，不是真人通關或實體手把。視窗 1280×720、HDR 2D、亮度 0.5、原倍率及真 WorldEnvironment/bloom。與其他專案共用電腦，不作排他效能結論。

## 原問題的根因

BG-53 已證明原工具混用世界面積與實際像素面積。本輪以原霧量 1.0 和已存在的局部候選 0.5 在同一場景交替，兩者都超過原門檻。原先「路燈暗段造成主角不足」沒有正確量測支持；不能再宣稱降低霧量是必要的過關修復。保留既有候選與雨霧／陰影，這次不改產品資料。

場景仍有兩盞 authored stable 燈；caption 的 lamps=full 是工具參數，不冒稱拍到自然閃爍。BG-48 舊誤算與早期跨程序未同步資料保留在原附件，不拿它們算此次改善比值。

## 同一個場景的五次控制

每品質完整 3×3 九格，六格有真可站地面；三格沒有地面保留場景圖，不製造玩家數據。先保留 PhysicsBody2D 的實際 physics space，再以 CharacterBody 原 safe margin 向下真碰撞求解；記錄支撐 ray、floor/feet/gap、碰撞法線與接觸陰影。這不是只把座標寫成 floor-minus-two，也沒有偽造 is_on_floor。

固定真角色、雨點、shader TIME 及動畫，仍更新原 LightBudget、WallShadows、接觸陰影、槍燈與霧取光 owner。高品質保留牆影、低品質保留原品質規則。主角移動後以真 owner 對齊 top-level 槍燈。

同格 A0→A1→B→恢復 A→B2，A 是原 market 霧量 1.0，B 是既有 lounge_front 0.5。前置逐 byte 守門確認兩份資料僅 id/fog_density 不同；離線另逐筆確認實際五個 fog_density 為 1/1/0.5/1/0.5，ambient、enemy fill 與 WorldEnvironment 不變。A0/A1/恢復 A 整張 float SHA 相同，B/B2 相同；同一 live instance 與 owner 字典一致。

| 品質／霧量 | 六站點最小主角對比 | 最小地面對比 |
| --- | ---: | ---: |
| 高／原 1.0 | 2.213979 | 3.408043 |
| 高／現況 0.5 | 2.183006 | 3.413033 |
| 低／原 1.0 | 2.295303 | 3.445517 |
| 低／現況 0.5 | 2.284305 | 3.446827 |

門檻保持主角 0.6／地面 1。每列是全六點各自最小值，不能誤當所有點都改善；例如最差玩家點現況略低，但仍通過。兩輪真正 exit0、無 ERROR／SCRIPT ERROR／退出洩漏、完成九格與前後所列來源 SHA 相同；約 33／29 秒只是擷取耗時，非遊戲性能。

原始 PNG、HDR bytes／實際 format/dimensions、完整 metadata、命令、runner、before/after 字典與所列來源副本都在 `lounge-high-raw.zip`／`lounge-low-raw.zip`；不是整個 repo 或所有素材的完整備份。每包逐成員 byte 長度／SHA 見內部 manifest，外部 `archives.json` 另列 ZIP 大小／SHA。原日誌、JSON、來源及圖片沒有換行正規化。

已實看全區原圖中的最小玩家點高低品質 A/B，紙燈、原霧、牆影與腳下支撐保留，角色可辨。四張公開 PNG 是原圖逐 byte 複製，不是重繪或插值。

## 獨立讀取器的版本

原生兩輪封存當時的 v1 離線程式。v2 不重拍影像，直接重讀原 float bytes，補明確 fog／ambient／enemy fill／WorldEnvironment 控制斷言；原 v1／v2 結果與 v2 原程式 bytes（SHA 與當時紀錄一致）也收進原始包。新 fog 與 owner 控制的四種故意破壞均被拒絕，原始檔未改；共用 reader 的八種 owner／raw／接觸負控制另有 BG-55 已發布證據，不冒稱本輪重新跑過那八項。

後續最終 reader 加市場入口同 profile 控制；每個版本及其適用案例分開列，不把新 reader 宣稱為原引擎當時執行的程式。UID sidecar 只供編輯器維持路徑參照，原生探針以明確 res:// path 載入；生成 UID 沒有改動已測 GDScript。

## 相關三區沒有退步

只套用復原館外的局部霧量，不更動三區各自正式 profile。每站的五步控制全部保有相同 HDR SHA，不用跨程序的動畫差量宣稱改善。市場入口沿用 BG-55 已發布的補光 1.0；此處不把它倒回修復前 0.6。

| 相關區域 | 每品質覆蓋 | 高／低主角最小對比 | 高／低地面最小對比 | 原始來源 |
| --- | --- | --- | --- | --- |
| 市集入口 | 21 格、14 個真站點 | 3.732583／3.321096 | 3.255723／3.433574 | 本附件 gate-high／low 四分包 |
| 公眾攤道 | 24 格、16 個真站點 | 3.442629／2.936626 | 見逐格讀取結果 | 已發布 BG-55 regression-grounded-ch2_market 高低 v2 |
| 第一章交接櫃 | 原巡覽的交接櫃 1 個站點 | 11.062221／9.859780 | 5.510768／2.075067 | 已發布 BG-49 held-complete 高低 v6 |

交接櫃是 ch1_handoff、腳下 (296, 319.997742)，不是 ch1_street；此處明確只引用原站點，沒有宣稱另拍九格全區。原 HDR、PNG、JSON 逐 byte 由已發布 BG-49 ZIP 讀出，並重新以獨立讀取器還原真支撐、光影 owner、五步相同 raw 與原門檻。未重跑原生程序；沿用其真 exit0／來源不變／無 ERROR 收據。公眾攤道同樣重讀已發布 BG-55 全部原始 float，而非重拍。

`related-origins.json` 列出來源 ZIP 的相對路徑、SHA、大小；交接櫃另列所選原始成員 SHA。保留前次 BG-48 未同步失敗與診斷，不以新的同格資料刪除舊紀錄。

## 檢查與重現

在 repo 內安裝 NumPy／Pillow 的 Python 執行：

```sh
python pm/Nest-Egg-BG/attachments/BG-48-grounded-2026-11-11/verify.py
```

此命令使用本附件及已發布 BG-49／55 的相對位置，無須 Godot、GPU 或外部 D 槽。它檢查 ZIP CRC／SHA、原始成員長度與 SHA、八份最終工具來源，再解出暫存檔重算四組本輪畫面、四種破壞控制與四組相關區域；結束自動移除自身暫存目錄。`verification.json` 是本次真正 exit0 的完整輸出。只讀證據不修改原包。

正式 `run_tests_changed.sh` 對精確八份工具選到 0 個遊戲套件、exit0，收據在 `official-tool-only-raw.zip`；沒有寫成遊戲全測通過。已發布 BG-49 的同八工具加預設不變共用 sampler 組合另選 1 套 ReadabilityTargets，158 checks／0 失敗／0 ERROR，原收據位於 BG-49 附件且來源 SHA 相同。最終新增的本附件讀取器另以真資料執行驗證。沒有改測試門檻、known failures、遊戲資料或執行中邏輯。
