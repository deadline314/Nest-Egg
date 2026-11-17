# NE-276：雙向軟鞭逐格與量測分母核對

2026-11-18；main 基底 beaa2affa6d71b1b053d264c06d95368a081baa3。Godot 4.7.2、Forward+、Vulkan、RX 9070 XT、640×360、固定 60 更新率。本次交付只有驗證資料、設計與票的校正，正式遊戲、物理、招式、聲音、設定與測試沒有改動。10,095 份執行來源的 bytes／SHA 在整批原生程序前後一致，私有轉接器另列 hash。驗證 checkout 的 Git metadata 仍是 eb96adda；其正式執行來源與目前 main 相同，差異只有上張票的文件／證據。

## 覆蓋與原門檻

沿 NE-275 的私有轉接器與正式完整姿勢取景，改為只播放鞭子。左右各 541 步、61 張原圖：待機、真走／跑輸入、蹲、跳、衝刺；甩擊 lash、回甩 return_lash、持續招式 orbit 的安排起手與指定播放，每招結束再量 60 個物理步；另在出招第 8 步中斷，連續量 70 步，換槍、位移 160 像素、重新裝備。orbit 這裡只有指定的一個招式週期，不是假稱從公開按住輸入自然進入、長時間持續及任意放開。

每步保存真正 20 個繩節點、放線長度、地面、階段、進度、目標、招式距離，以及原腕矩陣、掌心與握把。122 張原圖的取景完整；24 頁全尺寸連續圖全部實際逐張檢視，未縮小每張 640×360 原圖。

從原始數值獨立重算：

| 項目 | 朝右 | 朝左 |
|---|---:|---:|
| 原量法 chord／放線長度最大值（門檻 <0.99） | 0.965000572 | 0.965000499 |
| 出招段 bow／放線長度最小值（門檻 ≥0.04） | 0.067096825 | 0.067868978 |
| 甩擊鞭梢最近距離／射程 | 4.030／100 | 4.312／100 |
| 回甩鞭梢最近距離／射程 | 4.855／80 | 3.974／80 |
| orbit 鞭梢最近距離／射程 | 2.584／90 | 2.626／90 |
| 最大出線口偏離 | 0.000016833 | 0.000016833 |
| 節點低於地面 | 0 | 0 |

六組招式皆觀察到前搖時近端向前、遠端仍在後方；原相鄰節長上限保持。左右各在真正中斷 70 步後鞭梢低於掌心 18.457／23.235 像素；換槍後 laid=false 且不可見；重新裝備後 laid=true，鞭梢距掌心 25.786 像素，小於原 50 門檻。原色、芯線與由粗到細的繩線仍在，未換畫法。

原 EnvironmentSuite 的握持、軟鞭、打斷與換裝檢查隨同 4 組原套件在相同正式執行來源通過 10,724 項／0 新失敗；同來源近戰、武器、特效及曝光四組原套件的 1,768 項／0 新失敗沿用 NE-260 的未變動遊戲依賴。封包保留原 log／分片及來源範圍，不把套件的刻意壞資料診斷說成完全無 ERROR。正式遊戲 bytes 未變，本次是文件交付，不重跑不相干套件。

## 一個不能以舊綠色結果帶過的形狀差異

原工具的 straightness 分母是模擬的放線長度，並非當格 19 段實際可見線的長度總和。補算後，朝左 orbit 第 48 步（從 0 起算，收招段）得到：chord=23.312085651，實際折線長=23.540639552，放線長=24.157600205；前者比值 0.990291092，原量法仍是 0.965000060。

因此「原放線長度門檻通過」不能擴張成「可見鞭身全段都低於 0.99」。獨立 reader 如實輸出 arc_shape_accepted=false、1 個失敗，保留 left/whip-orbit-048.png、該格原始節點與整段序列；不修改門檻、放線長度或正式求解器讓它過關。右側同範圍最大實際折線比值 0.986909703。這是形狀量法與驗收的未解差異，不是已證實切換為剛性模式的根因。票的相關形狀條件撤回勾選。

刻意將真正模擬節點排成直線的原生負控制實際退出 1，全部 541 個樣本被原比值檢查拒絕；正常兩面向實際退出 0，三個程序皆 0 SCRIPT ERROR、0 ERROR。封包 reader 重驗雜湊、圖像與原始繩節點後仍重現上述一格形狀未通過；另改壞一個節點但保留舊宣稱，同一 reader 拒絕。封包驗證成功不等於產品形狀全通過。

## 參考與驗收邊界

這輪核對五個不同作者／團隊的一手資料：

- [MachineGames／Bethesda 的鞭子開發說明](https://bethesda.net/en-AU/news/indiana-jones-and-the-great-circle-wits-whip-and-fists)：動畫與模擬合作形成可控且有重量的動作。
- [mphe 的 GDNative Ropesim](https://github.com/mphe/GDNative-Ropesim)：RopeHandle 控制局部，其餘繩身仍由模擬帶動。
- [Thomas Jakobsen 的原始論文（鏡像）](https://edelkas.github.io/n/files/bib/jakobsen.pdf)：固定步進、距離限制與反覆解限制；有限次迭代的形狀誤差須另量。
- [Erin Catto／Box2D v2.4.1 的繩子原碼](https://github.com/erincatto/box2d/blob/v2.4.1/src/rope/b2_rope.cpp)：拉伸與彎曲限制分別求解；不能以一個長度數值取代形狀判斷。
- [Motion Twin／Thomas Vasseur 的 Dead Cells 動作流程](https://www.gamedeveloper.com/production/art-design-deep-dive-using-a-3d-pipeline-for-2d-animation-in-i-dead-cells-i-)：先核對關鍵姿勢與時機，再使用補間與特效。本輪不為了外觀改動既有招式時間。

新資料的選擇是重新核對形狀與時間，不另引入物理外掛或改寫整套系統。原票的其他作品參考與歷史截圖保留，沒有將未看的影片寫成看過。

Arc B580 的歷史成對耗時只保留原意，不冒充此次 RX 9070 XT 的歷史實作／目前版本比較。全部招式同格修前連續影像亦未補齊。相關兩條驗收保持未勾選；連同形狀條件，票維持進行中。沒有 HDR／真頭 alpha 的這批 PNG 不作全招式曝光新結論。

## 重算與圖集

native.zip 是標準 ZIP，packet.json 記錄整體 SHA、大小、成員數；ZIP 內 manifest 逐檔驗證。replay 保留私有轉接器與獨立 reader；重跑需把其中本機 repo、引擎與輸出路徑換為現有環境，四個設定目錄保持獨立並沿用 GPU 共享鎖。無需更動玩家檔案或安裝外掛。最初曾從 work 子目錄啟動 runner，來源路徑檢查在 Godot 啟動前失敗；正確根目錄運行的命令與完整結果另存。

- [right-poses-01.png](../../images/NE-276-20261118/right-poses-01.png)
- [right-lash-01.png](../../images/NE-276-20261118/right-lash-01.png)
- [right-lash-02.png](../../images/NE-276-20261118/right-lash-02.png)
- [right-lash-03.png](../../images/NE-276-20261118/right-lash-03.png)
- [right-return_lash-01.png](../../images/NE-276-20261118/right-return_lash-01.png)
- [right-return_lash-02.png](../../images/NE-276-20261118/right-return_lash-02.png)
- [right-return_lash-03.png](../../images/NE-276-20261118/right-return_lash-03.png)
- [right-return_lash-04.png](../../images/NE-276-20261118/right-return_lash-04.png)
- [right-orbit-01.png](../../images/NE-276-20261118/right-orbit-01.png)
- [right-orbit-02.png](../../images/NE-276-20261118/right-orbit-02.png)
- [right-orbit-03.png](../../images/NE-276-20261118/right-orbit-03.png)
- [right-lifecycle-01.png](../../images/NE-276-20261118/right-lifecycle-01.png)
- [left-poses-01.png](../../images/NE-276-20261118/left-poses-01.png)
- [left-lash-01.png](../../images/NE-276-20261118/left-lash-01.png)
- [left-lash-02.png](../../images/NE-276-20261118/left-lash-02.png)
- [left-lash-03.png](../../images/NE-276-20261118/left-lash-03.png)
- [left-return_lash-01.png](../../images/NE-276-20261118/left-return_lash-01.png)
- [left-return_lash-02.png](../../images/NE-276-20261118/left-return_lash-02.png)
- [left-return_lash-03.png](../../images/NE-276-20261118/left-return_lash-03.png)
- [left-return_lash-04.png](../../images/NE-276-20261118/left-return_lash-04.png)
- [left-orbit-01.png](../../images/NE-276-20261118/left-orbit-01.png)
- [left-orbit-02.png](../../images/NE-276-20261118/left-orbit-02.png)
- [left-orbit-03.png](../../images/NE-276-20261118/left-orbit-03.png)
- [left-lifecycle-01.png](../../images/NE-276-20261118/left-lifecycle-01.png)
