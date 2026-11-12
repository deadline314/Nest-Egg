# NE-264 本機 HUD 補驗與安全通道修正

8 個實際 Forward+／RX 9070 XT 原生擷取全部通過獨立 reader，共 1,076 個連續 post-draw 樣本、18 張完整 viewport 原 PNG。來源、正常清場及雙 port 佇列守門均通過。這是明示安靜街道 fixture 與合成公開輸入，沒有宣稱人工遊玩、實體手把、自然通關或效能。

## 產品與來源

`AmmoTray` 與 `VitalsTag` 共用安全通道，依真頭部、完整文字範圍、視窗及槍口避讓；轉向不直接穿過頭部或射線。窄空間從上瞄回水平時，可依元件當前位於槍口的上、下側分層繞行，並非永遠整組一起在頭頂。缺視覺資源的 fallback、換 Player／skin／rig 的快取失效，以及原大位移復位保留。108／4／120、字級與原顯示內容保留；沒有每 draw 配置容器或用24作硬截步。

published 的 `BLEND_SPEED=5` 是完整weight200ms。本次選擇weight `1/.3`與side `2/.3`，完整weight或完整side各300ms，讓分段避讓可讀；這是本次速度選擇，不是原published值。完整翻側包含進入通道、橫移、離開通道與實際guide穩定，總時間並非300ms，所有追加尾段仍逐draw守原24門檻。

真正 native 與原22組測試來源是 published `2fa7bde15a08d0744d968c796ed9c5c4bf614015`＋四個 v14 候選，D10162／C393v23每輪原收據不變。最終 helper 另改三處維護註解，execution lines 逐 byte 相同：native helper SHA `2fa0631d7978c5b8552a6daf9faab287eefa71216bab418d3f7c35f12bea356e`；final helper SHA `6a77f0b70f14144cb4235aadec4fc972926e34d719ff1473d0302ff875008573`。另外三檔完全同 byte。不能將 final SHA 倒填到 native。

最新接合真 fetch/rebase 到 `d20d88f46e4889e46efbbbe4d165ddf396db4346`，核對四項 published base SHA 未變才套 final4。發布間只有兩個 story/fact runtime、三章 story 資料及兩套相關測試改變；UI、Player、Rig、Fx、材質與關卡幾何未變。最新接合與較早 native 的來源範圍分開記錄。

## 原生範圍與原門檻

| case | 尺寸／process cap | 連續 draw | 最大最遠子彈位移（logical px） |
|---|---|---:|---:|
| matrix72060 | 1280×720／60 | 131 | 10.500357 |
| matrix72030 | 1280×720／30 | 109 | 20.124657 |
| matrix108060 | 1920×1080／60 | 131 | 10.493623 |
| matrix108030 | 1920×1080／30 | 109 | 20.111562 |
| mixed30 | 1280×720／30 | 54 | 22.253813 |
| aim60 | 1280×720／60 | 230 | 9.722115 |
| shoot60 | 1280×720／60 | 80 | 1.707472 |
| aim-full60（獨立補拍） | 1280×720／60 | 232 | 9.722115 |

四個 matrix 每輪都有左、右邊緣×兩面向的四張完整 PNG，原 turn 首40＋真穩態尾段、jump 首50＋完整落地、真 run 跨 above→beside，沒有刪掉中間 draw。水平 run240 原紅保留；新 crossing 只在原 move 起點公開切上瞄，不改108或相機／碰撞來造跨界。混合操作為公開反向→兩 draw→hold jump→第6 draw前再反向，保存完整落地與三個穩定 draw。shoot實際彈匣12→11→12，記錄真 reloading／完成，沒有設定彈量。

獨立 aim 從第一個上瞄 draw 起保留，sample60真 move、180回水平，直到位置穩定；180／229完整原浮點另補新 epoch，未改寫第一輪。所有 attached icon／備彈／plate 包絡均不碰實際 muzzle＋aim_dir 經 numeric canvas 轉換的 forward ray。

原 `<24` 是原測試的 logical slot 座標，不冒稱所有 screen pixel 位移也小於24。logical／screen與final／canvas／head transform均保存。頭部以真 Sprite2D、非空原 Texture2D alpha、明示 mip layout與無 shader warp驗證；完整 affine quad再加1 logical px AA作保守上界，交疊即拒收，不縮 alpha mask。站立四格另驗 feet／WeaponBar包絡不重疊；所有樣本玩家存活、自然 physics／process、兩個 HUD 可見且正常處理。

## 原圖與編碼

[18張完整原圖及53張明標derived的SHA／尺寸索引](selected-index.json)，[各epoch完整來源／reader／輸出索引](capture-index.json)。`selected/matrix*/` 的四個 `.png` 是完整 viewport 原圖；`*-derived.png` 是驗證後由原浮點ROI轉換的1:1局部預覽，不能當全畫面。

`selected/aim-full60/full-aim-180.png` 與 `full-aim-229.png` 各1280×720，對應完整RGBH14原始5,529,600 bytes。完整圖與該 draw ROI逐float一致；先由float linear轉sRGB、再量化RGBA8，無resize、無拼接。原RGBH只有3色通道、alpha隱含opaque；PNG alpha255，沒有宣稱原檔含alpha。獨立NP逐pixel核傳輸公式，與Godot量化差至多1個8bit單位；HUD門檻以原float／geometry驗，不拿PNG量化放寬產品門檻。

## 正式與最新接合

| 執行 | 真結果 |
|---|---|
| 原 `run_tests_changed.sh`，2fa7＋v14 only4、實選22組 | 10,478／0新／0已知，exit0；原wall626s，wrapper662.752s；10162來源前後同，0SCRIPT ERROR |
| 最新d20＋final4，原AmmoTray／DeathFlow／Cutscene短接合 | 2,089／0新／0已知，exit0；原wall82s，wrapper83.871s；10162來源前後同，0SCRIPT ERROR |
| v14原AmmoTraySuite | 65／0；自然公開CPU瞄準／移動241樣本亦另留，不代稱native |

22組原log有原filter允許的fixture ERROR及9 ObjectDB／5 resources退出診斷，完整保留，不稱所有headless log零ERROR。八個native則嚴格拒絕所有engine／SCRIPT／清場診斷，均為0。latest短接合不能冒充再次跑完整22組；原native不能冒充最新main全來源相同。

## 離線重驗

完整8 ZIP留在 `D:/NestEggDeliveries/NE264-20261112/v14-native-v1/`，共456,128,633 bytes／13,591個ZIP檔案項目，原始各epoch也未刪除。Repo只收精選原圖、完整來源與小proof，避免把456MB原始浮點放入Git。`raw-index.json`逐ZIP與檔案項目保存完整SHA；預設reader找本目錄`raw/`，也可指定外部位置。需要Python3、numpy與Pillow，完全不啟動Godot：

```text
python verify_native.py --raw-root D:/NestEggDeliveries/NE264-20261112/v14-native-v1
python verify_legacy.py
python verify_tests.py
```

native reader實際從8 ZIP解壓／驗SHA／重算全門檻均過；會以實際記錄射線上的故障HUD與恰24位移作拒收負控。`--only`可窄讀單case；`--receipt`只寫新檔、拒絕覆蓋舊收據。

## 原失敗與勘誤

`legacy-selected-original.zip`保存四個原失敗的原report／來源／收據與精選raw；`legacy-index.json`明列完整原epoch所在D路徑。它是精選失敗proof，並非聲稱完整舊raw都已裝進Repo。

* 原published水平run240未跨界：刺激未建立足夠room，原exit1不改，不把它當產品已過或為它強退到beside。
* v8候選mixed：原33.844593／獨立重算33.844592，大於24；sample4保守head交疊亦仍拒收。
* v11候選：engine0仍有reserve最左−5.181038與head交疊，獨立reader真紅，未以exit0藏缺陷。
* v12候選：舊六輪較窄reader綠仍保留，但UP射線實際穿過滿格guard白條，不能稱整票已過。

舊mipmap flag缺漏／RGBH14 reader拒收、原sparse音訊fixture遺漏導致的22組紅、修復同pin fixture後的原收據均另保留在diagnostics。這些工具／刺激問題與上列產品紅分開；本輪producer明存mip flag／offset／頂層alpha。早期準備腳本的cp950與既存目錄錯誤都在啟engine前，原source保留，沒有冒稱成功原生。既有票的『永遠整組頭頂』及固定1/60單元回歸屬歷史行為／受控測試，不代表本次自然draw的產品行為。
