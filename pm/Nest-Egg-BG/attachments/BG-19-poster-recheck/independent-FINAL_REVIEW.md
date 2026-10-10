# 壁掛佈景獨立 CPU 審查

結論：本次海報修正可接受；沒有找到阻擋這三個修正檔交付的額外缺陷。舊 raw y14 確有 80 px 上移；目前正式 JSON 一直是 y19。既有完整生成流程會經 prepare_props＋policy 把 raw y14 改成 y19，所以不能把差異描述成「目前完整生成必然輸出浮空海報」。此次把 raw 本身改正、刪去重複 override，消除了原稿與正式資料的分歧。CPU不代替原生畫面驗收。

本次修正樹 C:/tmp/Nest-Egg-poster-support 的確切 freeze（核對時的檔案，不推定之後 HEAD）：

- tools/level/build_ch1.py：fef3067ec80b84afc59e1632deebf94b8657126f21771a23daf457b1e74ca5f1。
- assets_src/pipeline/scenery_placement.json：b73b883e171ce4fab159e2d8f87c319e5f204d0a1fcc6c0eaec34c80b5a2616b。
- tests/suite/test_scene_sanity.gd：8bc24b9f8b0c2939872f948b96143fa73f6da69e033a21a44738c1a4ead4211a。
- 正式 booth map：1ea857320b434e843294a7b78eade548e766671ef87baab79144e52929bf0653，兩樹一致。

完整讀 scene-staging、visual-verification、STAGING_REFERENCE；只做來源/Python/Pillow讀取及Ctmp報告，未跑引擎、Git、未改repo/PM。看過root既有原生 BG-19-ch1_booth_alley-28.png：海報上緣後方確為牆，底部接地；這是root產生的圖，不是本review執行引擎的結果。root回報原生 SceneSanitySuite 324/0，這裡不重新執行、不冒充独立原生測試。

## 海報的實際幾何

舊 main tools/level/build_ch1.py:613 為 raw x28,y14；tools/level/scenery_placement.py:16–26 先分類，再套 override；舊 assets_src/pipeline/scenery_placement.json 的 ch1_booth_alley override 將 y 改19。正式 data/levels/ch1_booth_alley_map.json 的海報也為 y19/support wall。修正樹 build_ch1.py:614 raw直接y19，policy override已不存在。

PropPlacement 的固定列底邊=(y+1)*16。PropData.size=(40.5,66)，故 y14→Rect(448,174,40.5,66)，y19→Rect(448,254,40.5,66)。PNG243×396底圖alpha bbox全畫布，沒有透明上邊能抵銷錯位。PropNode:33/43–46/96–98 採左上角、非centered、size/texture尺寸縮放，沒有另外的66或6倍率。

Booth地面y320，這段是outdoor。BackWallGeometry:43–69 的立面可能1–3層；ground40＋每層body32＋cap8。最矮一層的完整body位於248..280，ground280..320；即使最矮立面，正式poster254..320也完全在不透明牆上，尚有6 px上緣裕量。最多三層的cap176..184，其連續不透明部分開始180.1667；raw舊poster從174開始，即使最高立面仍有至少6.1667 px不能獲得完整牆支撐，更矮立面缺口更大。這不是元資料的support字串推論。

ScenerySupport:17–18 用visible alpha bounding rectangle交給walls.covers；BackWallGeometry:69–71 和 BackWall:103–108 共用同一批module rect/path，沒有另一個被metadata虛構的牆。Level:519–528 在支撐失敗時warning並略過，而不畫一個漂浮sprite。因此root目前引擎的y14負例「拒絕並略過」正確，不能說它原生重現了舊圖中的浮空繪製。

獨立呼叫修正樹 build_booth_alley()（未呼叫main/write）：rawy19、無override、prepare_props後全部9個props與正式JSON完全一致；24列全部terrain/decor grid逐字一致。兩樹全部10份正式*_map.json逐byte一致（11 LevelData中含共用當舖地圖的dawn）。詳 poster-source-verification.json、formal-maps-byte-check.json。

## 全部同類壁掛

wall-inventory.md 逐項列出全部62件：booth1、lounge3、pawnshop4、level_01 11、level_02 43；每件含精確x/y、worldRect、W/H與h/H。wall-audit.json保存同項原始資料、alpha核對及支撐欄位。

CPU按LevelBuilder的實際首表面/covered column規則、zone_at規則、geometry的panel64與最低floor計算，取所有合法seed共同必有的牆面，再逐件做矩形相減；62件均被包含，非只假設當前Godot seed。逐張讀54張facade base alpha，從底向上找每列全寬alpha≥128；全部與facade_wall_support.json相符。室內所用9張texture min-alpha皆255，沒有用透明室內材質冒充滿牆。62件的scenery_contacts bbox皆與PNG真正alpha bbox相符；全部wall prop sway=0，沒有漏掉擺動延伸。這是對目前資源的CPU覆核，非完整GPU取樣/IEEE證書。

第一章8件的H=56 authoring基準結果：

|物件|x,y|W/H|h/H|尺寸判讀|
|---|---|---|---|---|
|poster_wall|28,19|.723|1.179|大型直式肖像海報，接地；不是門頂小橫招|
|bottle_wall_shelf|28,14|.954|.804|PNG為三層酒瓶壁架，不能把整架高度當單瓶尺寸|
|menu_board|38,14|.421|.643|直式菜單板；略高於小霓虹横招建議，不等同違規|
|neon_glass_sign|10,13|.316|.482|小直式霓虹牌；字可讀性仍需native|
|wall_instruments|49,14|1.007|.857|四樂器與橫掛架組合；不能當單件樂器H|
|pawn_sign|64,11|1.241|.482|橫招落在reference .8–3H寬/.2–.6H高；底邊離地128px=2.286H|
|hanging_pans|94,13|.891|.536|多鍋與掛杆組合，牆面完整|
|tear_off_calendar|100,14|.159|.321|小掛曆，PNG有吊環，牆面完整|

沒有發現需要縮海報或放大牆來遮掩的比例缺陷。H≈56來自本工程authoring reference；這不是對全部最新rig的原生身高量測，也不保證縮放後文字清晰。reference霓虹橫招範圍是C類設計起點，不可機械套給大型海報、酒架、窗、梯子或整組樂器。全圖17種壁掛的尺寸列在inventory，最大完整画布h/H為fire_escape1.286，graffiti1.071；其語義並非手持小物，不因大於小招牌建議就自動判錯。

## 同類但未分類為wall的物件與邊界

額外52個sign/lamp/pipe/shelf/hanging等名稱物件也保留在wall-audit.json，並查看排水管、繩圈、立式五連霓虹牌、大廣告牌底圖。後三者底圖分別是真放地繩鉤、連續直立支架、廣告牌中央支柱；不是單靠把support改ground就宣稱有牆。booth shutter_graffiti x8的整扇捲門底图73.2×66；restore_arrow_sign x48為ground道具；本次以CPU牆集合覆核，兩者實際rect也完全被牆覆蓋。

注意項（不是本海報修正的實際反例）：booth gutter_downpipe x20的rect=(320,236,18.4,84)，模式ground只能證明下端落地，不證明上端卡箍附牆。最矮一層立面opaque開始244.1667，可令頂端8.1667 px缺全寬牆；本次root current原生圖實際較高牆已蓋住整管。未宣稱目前seed有缺陷，未把所有seed下的「落地」等同「壁掛可靠」。若之後變更level id/seed/地形/zone，應對卡箍另建牆接點或加入實際support wall檢查，而不是放大牆。

程序ASCII霓虹也掃了：decor-audit.json有16件（level_01 8、level_02 8）。NeonSign的FONT11/PADDING5/CHAR_STEP12與ScenerySupport.decor_rect一致。12件有所有seed共同牆面證明；level_01的(47,9)、(108,11)、(60,12)、(101,14)依具體立面高度，不能由最矮所有seed交集認證。不是CPU證明它們實際無牆；root完整actual SceneSanity已涵蓋這些當前seed case。正式16件没有HoloBillboard，故其glitch水平±3 jitter與角框stroke未納入decor_rect是未來支撐擴充的邊界，不是目前海報/壁掛的實際缺陷。

資料信任邊界：scenery_contacts及facade_wall_support是靜態表，runtime沒有重讀PNG核alpha；若將來換貼圖而不重建表，可能虛假通過。現在這兩張表已獨立對照底圖，不需將「必須未來校驗」當成本輪blocker。Emissive/glow/bloom不當作結構牆。裝飾字體出界、屏幕對比、雨遮擋、角色遮擋與真Forward+材質仍留給root原生驗收。

## 可重跑證據

- audit.py：只讀當前formal source，逐項alpha與所有seed保守共同牆集合，寫Ctmp wall-audit.json／wall-inventory.md；沒有Godot RNG猜值。
- audit_decor.py：16個ASCII霓虹對照NeonSign真尺寸；明列四個不能由all-seed證明的case。
- verify_fix.py：修正樹raw/policy/全部booth props/grid一致性。
- source-sha.json：本次覆核當時的main來源、資源及各壁掛地圖SHA。

本次既有source-wall判定與renderer共用幾何，沒有找到「support=wall字串自動造牆」或縮放/原點bug。可收束本海報source修正；其它壁掛目前無確定blocker，保留以上data更新與ground-only掛點的明確邊界。

