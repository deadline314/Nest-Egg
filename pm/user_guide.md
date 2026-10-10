# Nest Egg：使用者重點與跨 Session 工作指南

更新：2026-10-11。這份文件保存 Stanley 在本 Session 的要求、設計依據與退回原因；票的實際狀態仍以各票為準。使用者已要求本 Session 收尾後停止開發，換到其他 Session 工作。詳細分支、失敗紀錄與接手步驟見 [本次交接](SESSION_HANDOFF_2026-10-11.md)。

## 交付目標與優先順序

1. 先把**序章至第一章從正式新遊戲入口完整玩完**，再交雲端打包；不是直接跳到倉庫、授予旗標或只跑測試場景。
2. 第二、第三章各自先寫完整劇本、審查動機與因果，再做關卡、主支線、演出、動畫、敵人、音效與章末。之後沿全章大綱逐章推進。
3. 每章完成保存一份獨立 Windows 單檔：「序章至第一章」「序章至第二章」「序章至第三章」，不覆蓋前一版。可玩範圍、版本、提交、大小、校驗碼與真正 Windows 啟動結果都要清楚。
4. 故事有深度、遊玩一直有新發現，靠有用途的角色反應、道具、場景動畫、支線、敵人與空間變化達成；不靠道路加長、重複遭遇或滿畫面特效。

整體方案：[逐章交付設計](../design/20-campaign-experience/DESIGN.md)、[工作分工](../design/20-campaign-experience/WORKSTREAMS.md)。章節與打包對應 ST-16、ST-2、ST-9、ST-10、NE-178、NE-223、NE-232～235；新第二、三章為 ST-18～21，不能把舊第二關當新版第二章完成。

## 畫面與素材：看得到合理，才算驗收

- 世界保留既有賽璐璐／賽博龐克身份，UI 是**高清像素風**。像素面板、填色、材質與焦點有層次；避免只有細線框、臨時幾何圖示和過多閃光。文字與危險優先。
- **動畫最重要，打擊感非常重要。**角色動作、預備姿勢、命中時機、收招、受擊、音效與擊退先成立，再加克制特效。需要豐富情境動作，不是每個物件永遠只有靜態圖。
- 所有物件都要核對大小、位置、支撐、用途與圖層；海報必須真的貼在牆面，不能只因程式算出矩形就認定有牆。使用者的「再來一次」海報曾漏審，BG-19 已由 BG-26 接手補驗；後續同類物件都要實際看。
- 高低差與跳躍裂縫保留玩法，建築立面、側壁與背景補到鏡頭會看到的範圍。不能拉伸整棟房子、塞裝飾或填平坑洞掩蓋漏空（BG-28）。
- 地板、閥門、梯子、可擊碎牆、電子看板、告示牌換正式合適材質；閥門有管線、梯子有上下落點、牆有完整／破壞狀態，牌有支架與安裝面（BG-20、BG-21）。
- **一般遊玩與普通對話拿掉持續全畫面雜訊。**只在有明確理由的回憶／特殊感知少量使用，離開後恢復。不要降低整體光影品質或關掉所有後製冒充減噪（BG-27）。
- 每個玩家、NPC、敵人的影子符合腳下支撐、姿勢與跳躍高度；不能在坑洞或樓板另一側畫固定黑橢圓。光影多樣但主次清楚，主角霓虹保留、頭臉不能過曝（BG-29、BG-30、NE-213）。
- 水管流水可用 Godot 水流、落地濺水和音效；霓虹、風、機械等依用途做有界動畫（BG-25、NE-240）。真的需要影片生成的缺口先留票，不為流水載入大型影片模型。
- ComfyUI 圖示和立繪要貼近現有比例、色盤、線條與細節密度，避免雜亂生成紋理與明顯 AI 感。保留來源、提示詞、seed、job、hash、透明邊界，逐件看手、衣服、比例與 alpha。
- 角色骨架的髖、腰、肩、腕、踝、頸與外套接縫，要在遊戲倍率和過場約 3.4 倍核對全部動作；生成成功或特寫一處通過不等於整隻角色完成。看門狗須真正四足素材與動作。

場景／角色原生畫面須用 Godot 4.7.2 Forward+／HDR。無頭與雲端軟體 Vulkan 不能替代真 GPU、實體手把與人工遊玩。

## UI、閱讀與操作

- 操作提示依眼前情境顯示當下必要動作；完整操作另可查閱，不把 A/D、Space、Shift、射擊、格擋的大表一直蓋在畫面。文字用完整、自然繁中，一句講一件事。
- 告示牌**文字避開／繞角色的呈現是使用者喜歡的設計，保留**；改善牌體、尺寸與支架，整併重複功能提示，留下必要教學與故事證據（BG-21、BG-22、NE-228）。
- 背包參考圖只借「左側清單、右側角色」版面邏輯，沿用 Nest Egg 配色、字體與物品資料。凜另做自然、中性的選單姿勢，不能用持槍瞄準姿勢，也不照抄參考角色（NE-243、NE-244）。
- 人物交談／電影入口接近時，16:9 黑邊平順過渡到 21:9，玩家可以退回；正式交談／演出使用對應構圖。告示牌、普通物件閱讀、普通廣播與氣泡不觸發人物電影預告。預告不能提前改旗標、送獎勵或鎖操作（ST-22）。
- **重要通訊讓世界 Freeze，玩家確認才推進。**敵人、玩家、傷害、彈道與計時停下，閱讀 UI 可用；普通閒談不要每句打斷操作。長按確認不跳句，先展全文再前進。
- 閱讀上再開暫停頁，關閉暫停後仍保持閱讀的凍結；取消、死亡、換區、退出只釋放各自的暫停責任。讀檔／保存失敗要有安全重試，不藉退出或選單繞過寫入（NE-246、NE-230）。
- 背景 HUD 的 Hover／聚焦說明不能蓋住通訊、講者、選單或確認提示。此次已在真戰鬥閱讀截圖發現覆蓋問題，NE-228 留有候選與驗收項，**尚未修好**。
- 所有主要流程考量手把：開始／繼續、瞄準、戰鬥、聊天、機關、商店、任務、地圖、死亡和章末。確認／返回／分頁一致、焦點可见、返回恢復焦點；說明不只依賴滑鼠 Hover。近期裝置、改鍵、拔插與減震動都要驗（NE-229）。

## 戰鬥與關卡

- 每把武器的姿勢、節奏、聲音、彈體、擊退與收招有辨識度。重武器連段少、慢而重，輕武器快且可選接續多；不只換色（NE-236、NE-238）。
- 子彈有對應槍種的彈头／短尾跡、散彈分散、爆炸彈或能量輪廓；視覺和實際命中、穿透、反射相符，拖尾不是傷害區。
- 現有盾是**方向格擋**，盾面大小與角度要對得上前方防禦，角色仍可讀。不能畫全身罩暗示不存在的全向保護；舉盾、普通受擊、完美格擋、破盾與收盾要能區分（NE-239）。
- 連段升級可選，短連段仍好用；完整前搖、有效段、收招和緩衝／取消窗。揮空不播放命中聲或停頓，每招每目標一次，多目標不堆無限停頓，不允許免費終段、永久硬直或無限取消（NE-237）。
- 衡量首次傷害延遲、有效距離、整段輸出、操作鎖定、耗能、擊退、裝甲／頭目反制與多難度；最後 NE-241 統一驗收打擊感。
- **普通路線不要封牆強迫戰鬥。**NE-245 已交付；未来只有明確競技場／特殊空間才考慮鎖場，完整角色進入安全區才關門。取消牆不能直接贈送遭遇完成或破壞任務／頭目出場。
- 地圖有用途、路線、捷徑、秘密、落點、檢查點與地標，戰鬥與敘事有高低起伏，不硬塞同一模板。敵人符合地區生態與戰術；「跨章最多兩種重複身份」目前是專案暫定解讀，不是業界規則，配置時再依票核對（NE-97）。
- 主支線、地圖與 HUD 從同一正式故事來源讀取。實際完成、死亡、回訪與续玩會正確推進；不可手造第二份任務真相或讓可選支線變主線必做（NE-223）。
- 升級／貨幣沿用既有商店、改裝、典當與死亡結算，記跨章收入／支出，正常不刷錢路線可推進並有有意義的選擇；勿另造重複系統（NE-231）。

## 劇本與演出

每場先說清楚誰在何處、想做什麼、為什麼、玩家怎麼參與及之後改變什麼。參考 `Cyberpunk_Edgerunners_Subs` 的口語與社會處境，寫原創、合理完整句子，不能複製台詞或靠一兩字斷句裝酷。核對角色認識、持有物、付款、位置、死亡與伏筆時機。

使用者要求豐富過場、短對話、互動與動畫；舊「每章固定最多三過場／八分鐘間隔」不再是本輪硬性規則。每段演出要有資訊增量和作用、能跳過、重試不反覆強制重播；兼顧主動聊天、探索反應與可玩教學。序章練習倒地不能消耗真正首次死亡建檔（ST-16）。

## 已參考的業界資料，以及支持什麼

這些是本輪查過的原始設計資料／官方指南，不是所有玩家一致認可的唯一最佳方案。來源與樣本限制詳見 [研究紀錄](../design/20-campaign-experience/RESEARCH.md)及[畫面與閱讀研究](../design/20-campaign-experience/INVENTORY_WORLD_CLARITY.md)。

| 參考 | 用在 Nest Egg 的原則 |
|---|---|
| [Dead Cells 主設計師的關卡文章](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/) | 先做有功能與連線邏輯的區域，再放地形與敵人；多樣而不隨機塞滿。 |
| [Team Cherry 官方訪談](https://www.nintendo.com/au/news-and-articles/the-metamorphosis-of-hollow-knight-with-team-cherry-aussie-developer-interview/) | 可探索其他路線、回訪與有動機的人物；不照搬完全非線性。 |
| [Supergiant 的 Bastion 寫作](https://www.supergiantgames.com/blog/in-depth-writing-bastion/)與[Hades 更新](https://www.supergiantgames.com/blog/hades-updates/) | 玩家活動引出反應，角色事件有條件、優先序及重播規則。 |
| [Dead Cells 官方無障礙更新](https://dead-cells.com/patchnotes/29) | 文字、輪廓、攻擊預告、背景對比與粒子可調，重要威脅優先。 |
| [PlayStation 開發者談 God of War 戰鬥](https://blog.playstation.com/2022/10/04/game-developers-explain-what-makes-god-of-war-2018s-combat-tick/) | 動畫、聲音、受擊與短停頓共同表現重量；不只加震動和閃光。 |
| [GDC Skullgirls 動畫講座公開概要](https://www.gdcvault.com/play/1021657/Powerful-and-Effective-Animation-for) | 關鍵姿勢、預備、拖影與時序服務玩法。只查公開概要，沒有看會員影片。 |
| [Xbox XAG 116](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/116)（Ori 對話例） | 文字留到玩家主動推進。Freeze 是本使用者的專案決策，指南不強制所有通訊凍結。 |
| [XAG 102](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102)、[107](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107)、[112](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112)、[113](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/113)、[117](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117) | 可讀文字、完整輸入、一致導航、模態焦點與減動態。 |
| [Steam Input 官方指南](https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs) | 全流程手把、裝置提示及拔插處理。 |
| [Godot 2D 光影](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)、[自訂繪圖](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)、[多解析度](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) | 有限光源／陰影成本、快取繪圖及像素與文字各自適配；仍須本機實測。 |
| [Godot Windows 匯出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html) | 嵌入 PCK 的獨立單檔、資源白名單與匯出體積限制；正式包須真啟動。 |

玩家討論只用來辨識「視覺雜訊、頻繁打斷、盾偏好」等遊測風險，未做具代表性民調。21:9 預告、殘影深灰、盾外形、連段數與敵人重複數都是專案選擇，不可寫成普遍業界共識。

## 不要再犯的錯誤

1. 沒有逐條達成驗收就結票；把工具、生成、語法通過、排列好的單場景或大綱完成說成整章完成。
2. 用舊來源的綠色結果證明最新 main；漏看原生 log 的 RID、腳本、編譯錯誤；把 shutdown ERROR 當作乾淨退出。
3. 修改測試選擇器、加 known failure、刪掉舊斷言或授予假旗標，讓正式故事 owner 缺口看起來通過。歷史格式測試可留隔離 fixture，新正式契約另驗，不回填已刪掉的開場到產品。
4. 用假存檔埠、假 Source、直接播放正式 scene 或手動送道具代替正式新局、NPC／世界觸發、真正寫入與冷續玩。
5. 測試 observer 的 ALWAYS 讓遊戲 Main 也繼承 ALWAYS，測出「凍結」但敵人／計時其實還跑。檢查實際遊戲節點處理模式及同一活子彈、敵人和時鐘。
6. 整批預等待、強制渲染同步、停用正常法線／效果或隱藏缺圖，讓渲染錯誤暫時消失後就宣稱找到根因。
7. 合成手把事件當真實手把驗收；把寬螢幕視窗截出的 16:9 KEEP 畫布稱為原生 21:9 內容。
8. 只看 CPU／設定值說光影、記憶體或 VRAM 已改善。此次 RAM 有觀察，VRAM 未可靠量測；貼圖快取估算不是整個程序峰值。
9. 混入別人的工作、全域 stash／clean／重設、推主分支 force，或刪未合併分支。新分支只收必要來源、精選證據與文件，不能帶輸出大圖、整份快取、無用途診斷和私人暫存。
10. 宣稱雲端已正確派工但未驗 Nest-Egg 和 Git。曾有雲端 runtime connected、Git 仍被 proxy8080 阻擋；連線狀態不能代替實際 fetch 成功。

## 執行、記憶體與協作習慣

- 本機原生驗收一次一個 Godot；ComfyUI 如要並行，先確認當前 RAM／VRAM 和模型占用，圖像先單张、小批，生成完回收。使用者允許正常執行、不要額外過度保護，但要求持續觀察，不能在資源已滿時繼續堆。
- 本機本次 RAM 約 31.76 GiB，收尾前觀察剩 8.49 GiB；不是永久可用額度。Intel Arc 的 VRAM 此輪未量測，不能因沒有 nvidia-smi 就說顯存為零。
- 雲端 Nest-Egg：CPU 約 4 核配額、無硬體 GPU，軟體 Vulkan可做邏輯／輸入／打包與部分畫面；每個 Session 先驗 repo／Git／Godot／實際 cgroup 記憶體／磁碟。本輪一個雲端 cgroup 實際 16 GiB，不能沿用申稱的 32 GiB。
- 可以平行用 subagent，複雜工作選 6.1 Sol、較簡單盤點可用 Luna；父 Session 驗收。subagent 是目前工作的子任務，新 chat 是侧欄獨立 Session，兩者不同。生成／GPU留主 Session；不同代理不要同時改同一檔案。
- 另一台電腦的 NE-222、NE-221、NE-218、NE-79～81、NE-90、NE-224 由原負責者處理；這個 Session 的收尾不停止或刪除它們。
- 一般設計選擇已有授權，不重複問問題；這次明確要求停止，交接後不要自動續開章節或重新啟動工作。

## 開票、提交與验收

先讀本專案 pm-ticket，需求進 design；新票先 fetch、取**該專案目录 origin/main 最大號 +1**，開完立即 commit＋push，不能沿用本對話早期 NE177／BG16。NE／BG／ST 分別編號，重複需求補既有票，依賴雙向維護。

每張實作票：原 `tools/run_tests_changed.sh` 選出的受影響範圍全過 → 真實截圖 → Commit 段落／完成／實際驗收勾選 → 獨立 commit＋push。文件和票不啟動遊戲測試；完整 CI 由既有排程處理，但框架更動若原 selector 要 ALL，不能自行縮小選擇範圍。測試失敗如實保留，CI 新失敗依 AGENTS 優先處理。

分支用 `codex/`，推前 fetch origin main／必要 rebase；`git push origin HEAD:main` 只能快轉，確認本機 main＝origin/main。作者與提交者 **Stanley Li <stanley890314@gmail.com>**；commit 訊息沒有模型／工具署名和 Co-Authored-By。只刪已合併且屬於本 Session 的分支；遠端拒絕不重試、不繞過。

精選截圖放 `pm/Nest-Egg/images/`（BG／ST依自己的项目也可存），完整 raw／hash／必要來源放票的 attachments。`pm/.gdignore` 排除票據與 CSV 的引擎匯入，避免無用途的翻譯與 import 產物。必要歷史失敗保留一次、有清楚索引；無用途臨時腳本與重複輸出清掉。交接的 WIP 明示未採用、未驗收，避免混入正式遊戲。
