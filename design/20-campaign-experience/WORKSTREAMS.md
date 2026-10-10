# 票務盤點與跨環境分工

2026-10-10；最新唯讀盤點基準 `ff4b9dd095eab83076e030c92bb8625168f3cf43`（origin/main）。本輪新增 NE-227～NE-241、ST-17～ST-22、BG-20～BG-22，共24張；初次盤點基準 `9f6438869` 留作歷史紀錄。票務狀態以該基準的票檔為準；狀態或模型完成回報不等於整票驗收完成。

## 最新票況統計

下表依 origin/main 的票檔狀態欄統計；括號附註的「完成」仍算完成並排除。`審查中` 是歷史狀態，獨立列出，不混入 `進行中`／`待辦`。

| 專案 | 進行中 | 待辦 | 歷史審查中 | 明確未完成小計 |
|---|---:|---:|---:|---:|
| ST | 6 | 2 | 5 | 8 |
| NE | 21 | 10 | 5 | 31 |
| BG | 2 | 2 | 0 | 4 |
| 合計 | 29 | 14 | 10 | 43 |

明確未完成票共43張；另有10張歷史「審查中」票：ST-1／4／6／8／15、NE-17／67／118／181／196。取消、完成與封存不列入上述未完成數。

## 原有未交付票

| 工作組 | 票與遠端狀態 | 分工與剩餘界線 |
|---|---|---|
| 第一章故事／地圖與序章 | ST-2／ST-3／ST-9／ST-10／ST-16 進行中，NE-178 待辦 | ST-3 仍進行中；持有條件及整段預演已有真實 headless 通過證據；條件框架1133項、後續接合1512項、原件保管42組9005項通過，但正式故事接線驗收仍未勾。ST-9 以 d68 原 selector 80 組／54,352 checks 通過；c744 六組接合 3,438 checks 自然退出 0，這是來源接合交付，不等於第一章完整通關。ST-16 進行中；第一章產生器、正式任務與布局由同一 owner 管 |
| 第二／三章 | ST-18／ST-20 完成（劇本文稿），ST-19／ST-21 待辦（實際故事與關卡） | 文稿完成不代表新章 LevelData、遭遇、正式任務或可玩關卡已製作；先後依 ST-18→ST-19、ST-20→ST-21，第三章章節製作等第二章章節結果接續 |
| 任務與導覽 | NE-223 進行中 | UI 可獨立改版，正式任務由故事來源供應；不得用 fixtures 代替 |
| 環境與特效 | BG-17／NE-66／NE-95 進行中 | 低成本、調色、HDR 與效果複验；雲端只做 CPU／軟渲染，實際 GPU 指標留本機 |
| 音效 | NE-154 進行中，NE-196 審查中 | 正式後續章節音樂路由與使用者試聽；已有音源授權／加工流程沿用 |
| 模型整合 | NE-71／NE-153 進行中，NE-88 待辦 | 先準備審查材料，角色原 owner 修復後做本機整合與人工審查 |
| 敵人配置 | NE-97 進行中 | 更新跨章最多兩種重複身份規則，與故事／布局 owner 接線 |
| 跨章成長與一次帳務 | NE-231 進行中 | d68ddb79a 的一次帳務底層已局部交付；完整成長平衡、正式故事交易接線與跨章路線仍待驗收。条件與原件保管的框架交付屬 ST-3，分列在故事工作組，不合併算作本票完成 |
| 既有角色負責者（另一台電腦保留） | NE-222／NE-221／NE-218／NE-79／NE-80／NE-81／NE-90／NE-224 進行中；NE-242 待辦 | 原 owner 使用 ComfyUI；保留所有權，不另派重複美術、分件或骨架修正 |
| 其他審查材料 | NE-17／NE-67／NE-118／NE-181／NE-196、ST-1／ST-4／ST-6／ST-8／ST-15 均為歷史審查中 | 核對各票既有交付與剩餘人工審查，不因狀態字樣自動重做或勾完成；ST-3 狀態是進行中，另見上列未勾條件 |

NE-203／204／206／209／213、ST-11 的狀態是帶備註的「完成」，不列未完成；備註指向的後續票和實機審查仍照原票處理。上述「審查中」是歷史狀態，實際數量依票檔另列。

### NE-97 已發布關卡資料快照

只依每份 LevelData 的 `layout_path`、map JSON `segments` 網格，以及 `legend` glyph 對應的完整 `data/enemies/**/*.tres` 資源盤點，不代表實機遭遇或畫面驗收。計數流程是先由該 LevelData 的 legend 建立「字元→EnemyData 資源路徑」映射，再對每一 segment 的每一列逐字元計數；沒有直接對地圖文字做英數字母搜尋。以下 segment Counter 就是該映射結果的逐段原始證據，括號內為 glyph。

| 範圍 | 實際配置 | 結論與下一步 |
|---|---|---|
| 正式 `ch1_kasa` | `data/combat/chapter_rosters.json` 列9份 LevelData、6種身份；`ch1_street` 16隻、`ch1_warehouse` 13隻、`ch1_vault` 7隻，合計36隻。其餘正式區域無敵人。身份為 sweeper、collector_gunner、collector_brute、drone、watchdog、ch1_inspector。 | 同章多次重用符合規則；街道有近戰、槍手、空中單位與督察混編。倉庫目前10個開放遭遇、其中有相鄰清掃兵遭遇，列為檔案層節奏複核點，不據資料斷言無聊。 |
| 舊 `chapter_02` placeholder | `data/levels/level_02.tres`／`level_02_map.json` 共36隻、18種身份，11段配置；此為舊「天空的代價」，不是 ST-18／ST-19 新第二章。 | 舊資料中elite_grunt與wall_gecko各5次、stalker 4次、shaft_bat與rail_cannon各3次；新第二章待 ST-19 產生正式 LevelData 後再核跨章重複。 |
| `chapter_03` | roster 的 levels/enemies 為空；`data/levels/` 無第三章 LevelData/map。 | 沒有可核的第三章實際敵人名單；不要依 ST-20 文稿推定已配置。 |

目前正式第一章與舊第二章資源身份交集為0；此結論不涵蓋未製作的新第二／三章。

逐 map／逐 segment Counter（`EnemyData` ID 與 glyph；空段明列為0）：

| LevelData → map JSON | Segment | 已計入的 glyph → 完整 EnemyData 資源 ID | 數量 |
|---|---:|---|---:|
| `ch1_street` → `ch1_street_map.json` | 1 | — | 0 |
| 同上 | 2 | `g`→`sweeper` 4；`k`→`collector_gunner` 1 | 5 |
| 同上 | 3 | `b`→`collector_brute` 1；`d`→`drone` 2；`g`→`sweeper` 3 | 6 |
| 同上 | 4 | `d`→`drone` 2；`k`→`collector_gunner` 2；`z`→`ch1_inspector` 1 | 5 |
| 同上 | 5 | — | 0 |
| `ch1_warehouse` → `ch1_warehouse_map.json` | 1 | `g`→`sweeper` 2；`k`→`collector_gunner` 2 | 4 |
| 同上 | 2 | `b`→`collector_brute` 1；`w`→`watchdog` 1 | 2 |
| 同上 | 3 | `b`→`collector_brute` 1；`d`→`drone` 3；`g`→`sweeper` 2；`k`→`collector_gunner` 1 | 7 |
| 同上 | 4 | — | 0 |
| `ch1_vault` → `ch1_vault_map.json` | 1 | `k`→`collector_gunner` 1；`z`→`ch1_inspector` 1 | 2 |
| 同上 | 2 | `d`→`drone` 2；`g`→`sweeper` 2；`k`→`collector_gunner` 1 | 5 |
| 同上 | 3 | — | 0 |
| `level_02` → `level_02_map.json`（舊 placeholder） | 1 | `E`→`elite_grunt` 2 | 2 |
| 同上 | 2 | `+`→`shaft_bat` 1 | 1 |
| 同上 | 3 | `+`→`shaft_bat` 1；`>`→`rail_cannon` 1；`E`→`elite_grunt` 1；`O`→`flamer` 1；`S`→`wall_gecko` 1；`k`→`slasher` 2 | 7 |
| 同上 | 4 | `E`→`elite_grunt` 1；`Z`→`sniper` 1；`n`→`searchlight_drone` 1；`s`→`stalker` 3；`μ`→`hydraulic_claw` 1 | 7 |
| 同上 | 5 | `+`→`shaft_bat` 1；`S`→`wall_gecko` 2；`s`→`stalker` 1；`v`→`heavy_gunner` 1；`λ`→`chainsaw_arm` 1 | 6 |
| 同上 | 6 | — | 0 |
| 同上 | 7 | `O`→`flamer` 1 | 1 |
| 同上 | 8 | `<`→`tangle_wire` 1；`>`→`rail_cannon` 1；`E`→`elite_grunt` 1；`M`→`repair_drone` 1；`S`→`wall_gecko` 1；`v`→`heavy_gunner` 1；`ν`→`plasma_whip` 1 | 7 |
| 同上 | 9 | `S`→`wall_gecko` 1；`b`→`custodian` 1；`ξ`→`chain_hook` 1 | 3 |
| 同上 | 10 | `>`→`rail_cannon` 1 | 1 |
| 同上 | 11 | `Y`→`reclaimer` 1 | 1 |

第一章其他正式 map 的全部 segment 也逐一映射，結果皆為0：`ch1_pawnshop_map.json`（segment 1–3；Dawn共用同一map）、`ch1_rooftop_map.json`（1–2）、`ch1_booth_alley_map.json`（1–2）、`ch1_lounge_map.json`（1–2）、`ch1_stall_map.json`（1）。舊 Demo `level_01` 不計入正式 `ch1_kasa`；其7段另有30隻／9種身份，避免混併正式章節。所有計數均以對應 LevelData legend 指向的 `data/enemies/` 之 `.tres` 資源為準，包括 `data/enemies/` 子目錄中的資源。

上述 ID 已核對對應 EnemyData `.tres` 的 `id` 欄位。一般路徑為 `res://data/enemies/{id}.tres`；舊第二章四個 Strike 敵人完整路徑為 `hydraulic_claw`→`res://data/enemies/strike/hydraulic_claw.tres`、`chainsaw_arm`→`res://data/enemies/strike/chainsaw_arm.tres`、`plasma_whip`→`res://data/enemies/strike/plasma_whip.tres`、`chain_hook`→`res://data/enemies/strike/chain_hook.tres`。用來複核的核心步驟：讀每個 LevelData 的 `layout_path` JSON；讀其 `legend` 將 glyph 解到 resource path；僅保留 path 在 `data/enemies/**/*.tres` 且資源 `id` 確實為 EnemyData 的 glyph；對 `segments[i]` 每行逐字元做 `collections.Counter`。上表是該流程逐段輸出；沒有直接把 map 字元誤當敵人數。

可重跑[唯讀計數腳本](evidence/NE97_enemy_counter_ff4b.py)（使用 ff4b9dd09 的關卡資料）；完整逐檔SHA、glyph→資源路徑、每段與ID Counter見[原始JSON](evidence/NE97_enemy_counter_ff4b.json)。腳本對正式 ch1 加上 `assert sum(total.values()) == sum(segment_total) == 36`、身份數 `== 6`；舊第二章 placeholder 斷言 `36` 隻／`18` 身份；全部計數由同一 Counter 程式產生，沒有手工估算。

## 新票與工作組

| Owner 工作組 | 新票／沿用票 | 適合環境與責任 |
|---|---|---|
| A：劇本、故事與章節 | ST-17；ST-18→ST-19；ST-20→ST-21；原 ST-2／9／10／16、NE-178／NE-97 | 雲端獨立 Session 適合劇本、資料、旗標、可達性；第一章產生器單一 owner。第二、三章劇本可依各自檔案並行，核心入口与共享世界觀統一整合 |
| B：UI 主視覺與全頁體驗 | NE-227 完成→NE-228 進行中，NE-223 進行中 | 本 Session 一名 subagent 管共用 Theme／PixelUi／UiMotion 與頁面，主 Session 出面板／圖示素材；不把主題和頁面分給不同人同時改 |
| C：輸入與電影遮幅 | NE-229／ST-22 進行中 | 可用同一 subagent 依序做，或有清楚檔案界線時兩人並行；輸入服务与共用遮幅分別唯一 owner，UI接线由B合入。故事只交付觸發配置 |
| D：整輪存檔與發行 | NE-230／NE-232 進行中；NE-233／234／235 待辦 | CPU Session 適合存檔與發行邏輯、白名單及產物來源稽核；主選單繼續入口先與B約定，Windows單檔、本機手把與HDR最後本機驗證 |
| E：成長、近戰與武器 | NE-231 進行中（含 d68ddb79a 的局部帳務／框架交付）；NE-236／237／241 待辦 | CPU 可做數值、連段、升級、經濟模擬；共享 MeleeSet、成長與近戰資料由同一 owner。現有 conditions／custody 框架仍是局部進行中，不代表章節已完成；章節 owner 配置實際解鎖、獎勵與商店 |
| F：彈體與盾的視覺 | NE-238 完成、NE-239 進行中，沿用 NE-95 進行中 | CPU 可檢查投射物與特效邏輯，主 Session 審圖。角色姿勢、RigInput／HumanoidAnimator／PlayerVisual 接點與 NE-222 原 owner 協調，不並行修改其基礎修復 |
| G：場景、美術與情境動畫 | BG-20 進行中；BG-21／22、NE-240 待辦，沿用 ST-8 歷史審查／ST-10 進行中 | 主 Session 串行 ComfyUI 產圖；subagent 做逐區盤點、材質／用途和支撐清單。BG-22 與地圖配置由A接線，NE-240 新動作與角色 owner 一次交接 |
| H：逐章整合驗收 | NE-233→NE-234→NE-235 待辦；NE-241 待辦 | 對應章節完成後才做；布局、場景、敵人、劇情、音效、成長、手把與真正包一次完整走查。原角色票不能用假素材代驗 |

云端不是ComfyUI生成机。其4核配额、32GiB内存、约30GB可用磁碟与Godot4.7.2软Vulkan适合資料／程式／合成輸入／可達性／經濟和软渲染候选；不能承認為硬體GPU/HDR/VRAM/幀時間/真手把結果。

## 並行與記憶體

後續派工依2026-10-10使用者指定：複雜劇本、架構與戰鬥實作使用gpt-6.1-sol；較單純的票務、連結及資料核對使用gpt-6-luna。主代理驗收實際差異、測試與畫面；模型完成回報不等於交付通過。已啟動的工作可先完成，新的工作再依難度選擇。

本機代理併發上限為4人（包含root）。較早盤點時記錄的名單為 root、controller（gpt-6.1-sol）、story_result（gpt-6.1-sol）、remaining_inventory（gpt-6-luna）；這是盤點時的歷史快照，不能推論任何 subagent 現在仍執行。使用者自己建立的新 Codex Session／Task 是 user-owned session，須與 subagent 清楚分開記錄，成功建立也須確認確實啟動；不可把其狀態冒充本機 subagent。此前 cloudSession3 回 HTTP 401，無法工作，沒有可宣稱正在執行的雲端工作。

不要將更多任務映射成更多本機 Godot、模型或批量圖片載入；重點是 CPU 工作與單一生成流程並行。

ComfyUI一次一個模型／流程，默认batch1、先小样后批次；觀察可用RAM、VRAM和模型驻留，已审查图存磁碟、不将所有来源图解码常驻。使用者已授权ComfyUI與Godot可同时运行，也要求取消先前過度保守的自動保護；不擅自增加新的自动内存阈值或终止现有作业。出现持续逼近耗尽时降低批量、暂停新增载入、释放本任务已不用的缓存，并记录测量。角色机与本机生成不能互相假设对方空闲。

本机保留其他人的未提交BG-17和字幕目录；只用隔离分支／worktree修改，互不带入他人文件。共享源文件只允许一个owner写。跨工作组提交最新main后才串接，禁止两个Session各自产生不同的任务、经济或保存真相。

## 云端接手模板

以下为准备好的新Session任务文本；真正建立前先确认Nest-Egg云端环境可启动、fetch权限、写入路径、Godot版本、测试入口、显示与匯出能力。用户先前反映Session未运作，创建成功不等于工作已跑起来，须读取首个状态并确认已开始。

**A：故事与章节**：先fetch最新main，读AGENTS.md、pm-ticket、chapter-design、quest-map、continuity-qa及本组设计，先做ST-17，再按依赖完成新版第二、三章完整剧本与实际关卡。沿用第一章故事／地图owner，不并行改其生成器。脚本先审查因果、角色声音、伏笔、主支线及演出清单，原創对白参考Edgerunners语法，不抄台词。无GPU验收明写限制；每票局部测试、截图、票交付后独立commit并快转pushmain。

**D：存档与发行**：先fetch最新main并确认环境，读NE-230／NE-232及本组设计，承接现有故事／世界／成長／导航服务，完成真正退出再继续的整轮存档与累积章节打包工具。只写自己的worktree，与故事owner约定入口、UIowner约定继续按钮；不改第一章生成器。Linux产物检测不代表Windows最终单档已验收，等待本机确认后再完成对应章发行票。

**E：战斗成长**：先fetch最新main并读NE-231／236／237与战斗参考，承接近战、命中取消、输入缓冲、升级与经济，做每个武器不同姿势时序、击退、可选连段和跨章平衡。NE-222的角色骨架／姿势源由原owner维护，只提交动作需求与接点，不重画同角色。每武器比较起手、风险、控制、耗能和持续输出，保留头目反制，最终交NE-241做真实打击感总验收。

## 合并与交付顺序

先把本批需求同步到main；从可独立开始的剧本规划、UI样本、彈體与输入服务启动第一波。章节脚本通过才建设该章。基础存档／任务／成长／演出稳定后，每章逐区检查并生成独立包；之后按相同流程持续后续章。

每完成一票保留测试基准SHA，跑受影响套件；有画面变化必须真实截图，不把预生成概念图当游戏验收。作者／提交者统一Stanley Li <stanley890314@gmail.com>，消息不含模型署名。fetch后rebase，`git push origin HEAD:main`仅快转；主分支同步后才移除本轮已合并工作分支，未合并或他人分支保留。远端拒绝不重试／绕过。
