# ST-22 home2連續頭部alpha補驗

本次新home2目標句首draw起258個連續樣本，原complete＋50process標記在sample64，之後自然actor時間3.216538s、實際NpcAnimator呼吸1.193806圈。三個真head/hair Sprite2D副本的所有正alpha在safe內，最少2430個opaque像素，ROI不觸邊。首格與更新最窄格的同draw全幅reference對ROI alpha16逐byte零差；原檢查沒有容差放寬。

最窄正alpha像素中心y86.5，safe top85.7142868，最小距離0.785713**physical pixel**。新trace有88格conservative body框上緣超safe，但同格三個head/hair的alpha仍全部在內；這只描述本次新資料，不能倒填Root舊native720-v1那個無alpha的41.601654 logical點為透明padding，也不把三個head/hair遮罩冒稱整個身體／全部動作alpha。

原native為Forward+／RX9070XT、1280×720；cap60只是觀察上限，physics／time_scale／actor／camera／材質／live pose／phase未修改。目標句首次顯示就開始，不多等1s；32physical px只增加觀察ROI餘裕，TARGET首pre固定整個ROI180×206@(522,45)，之後不追crop。這是明示進度fixture與對話推進，不是自然Main通關、人工鍵鼠／實體手把或效能。

來源是原D app `d20d88f46e4889e46efbbbe4d165ddf396db4346`，tracked/index皆未改。當時D18967（含Root舊leaf2＋新leaf4）與C397/v24前後SHA全部相同，engine exit0、0診斷、正常清場，雙port內外四讀真空／真10061。之後live C已升v25/402，沒有倒填到本epoch。

## 精確原圖

`selected/full-first.png`（sample0）、`full-narrowest.png`（52）、`full-worst.png`（0）、`full-last.png`（257）都是未resize的1280×720完整原viewport PNG。outside全0，因此worst與first同格，並非另一個異常。`selected/reference-alpha-{first,narrowest}.png`是完整透明reference；精確判定使用原RGBAH15而非8bit PNG。

完整主圖原RGBH14只有3通道、alpha隱含opaque；PNG為RGBA8/alpha255，float linear→sRGB後才量化。全部258小ROI及選定full/reference原浮點、Texture2D原bytes與mip offsets、每格真transform／shader uniforms／pose／process／physics／actor_t均留在完整ZIP；PNG不拼ROI、不重組原全圖。

## Portable重驗

`native720-continuous-v4.original.zip`共24,112,884B／289個檔案項目。Repo提供完整一份，外部另保原份`D:/NestEggDeliveries/ST22-continuous-20261112/`。`raw-index.json`逐檔SHA，Source／C／queue原收據皆在內，不需讀live D tree。需要Python3、numpy、Pillow，不啟動Godot：

```text
python verify.py
python read_capture_v2.py <原epoch或解壓目錄> <全新reader輸出目錄>
python verify_root_epochs.py
```

`verify.py`真正解壓並重算258樣本，另在temp副本更新資料SHA後注入空alpha、safe外極淡.0001 alpha，兩者都必須拒收。若用外部ZIP可加`--raw-root D:/NestEggDeliveries/ST22-continuous-20261112`。`images-index.json`核六張原PNG。沒有把temp負控冒稱原生圖片。

## 原紅與Root原件

`history-and-source-original.zip`保留自己的native720-continuous-v1工具紅：預暖時固定ROI不足、rows空，沒有取得目標alpha；exit1後舊runner缺outer-after的原事實不補寫。parser-v2 Variant推斷錯誤／150s timeout、原source及後驗、無owned child／無Stop動作均保留；v3/v4動態load短parser正常exit0。CPU控制原11/0與追加固定ROI生命週期後15/0均保留，沒有用CPU代稱native。封包第一版把合法untracked work/UID誤要求全空，只有metadata收尾失敗；新erratum保留原ZIP SHA，未重寫容器。

Root三個原epoch分別完整封包：`native720-v1.root-original.zip`（六點、無alpha）、`native720-alpha-v3.root-original.zip`與`nativewide-alpha-v3.root-original.zip`（各六settled alpha點）。`root-epochs-index.json`逐CRC／member SHA；parser/import原件及原reviewers另外封在`root-parser-import-and-reviewers-original.zip`。`verify_root_epochs.py`只在全新temp路徑替換兩個原reviewer的root常數，所有公式／assert／門檻原樣，舊原件／舊review不改。最早720 home2的bbox outlier仍不作opaque裁切或padding結論；12個settled點不能冒稱連續觀察，新的258也不回填舊點。


## 主線最終審查（2026-11-13）

根代理已從本封包獨立執行兩reader，兩者exit0：[連續alpha及兩負控制](root-packet-verify-v1.log)、[三組原生來源與12點alpha](root-packet-epochs-v1.log)。親看12張最後的720／超寬完整原圖及連續首／尾／最窄／worst四張原圖。序章、回家兩鏡與診間三鏡的頭、腳及字幕均可見；超寬採1680×720／840×360 EXPAND，零額外黑邊，未改正式顯示設定。

受驗原生基底為d20，已逐範圍比對至最新f25d：電影、角色、骨架、材質、舞台及原構圖工具沒有後續變動。舊原件維持當時C393或C397，不倒填目前C402。這次只交付審查證據，未修改遊戲程式，不重跑無變動的測試；原票既有回歸與已發布完整CI各有自己的來源基底。[整合收據](source-review-adoption.json)。

原來的「待本機原生」限制由本輪補齊；自然Main路線、曝光量測、全部肢體alpha、實體手把與效能仍不在這份構圖審查範圍。原720無alpha影格的保守外框outlier保持未定，沒有用新trace替舊格判透明。所有原始ZIP均在本目錄，可離線重算，不依賴舊D工作樹。
