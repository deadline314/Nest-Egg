# 設計文件索引

| 文件 | 內容 |
|---|---|
| [01-game-design.md](01-game-design.md) | 垂直切片的遊戲設計（核心循環、敵人設計原則、難度） |
| [02-cyberpunk-overhaul/DESIGN.md](02-cyberpunk-overhaul/DESIGN.md) | 賽博龐克改版：操作、格擋、骨架角色、美術風格、劇情、第一關 |
| [03-art-pipeline/ART_PIPELINE.md](03-art-pipeline/ART_PIPELINE.md) | 美術交付規格：骨架角色要畫哪些零件、尺寸、支點、ComfyUI 流程 |
| [04-story/STORY.md](04-story/STORY.md) | 劇情設定：世界觀、角色、主題、第一章大綱 |
| [04-story/BIBLE.md](04-story/BIBLE.md) | 故事聖經：四幕起承轉合、真相時間軸、角色祕密、母題、結局、第一二章場景清單 |
| [04-story/FORESHADOWING.md](04-story/FORESHADOWING.md) | 伏筆與暗線追蹤表（F01–F19）、死亡次數的劇情反應 |
| [04-story/WRITING.md](04-story/WRITING.md) | 文本風格指南：去 AI 感的十條規則、角色聲音、自動檢查規則 |
| [05-dynamic-hud/DESIGN.md](05-dynamic-hud/DESIGN.md) | 動態玩家介面：生命、護盾、彈藥跟著角色與準星，閒置淡出、危險常駐 |
| [07-weapons-inventory/DESIGN.md](07-weapons-inventory/DESIGN.md) | 實彈武器陣容、彈匣與換彈、消耗品、劇情道具、背包畫面 |
| [08-lighting/DESIGN.md](08-lighting/DESIGN.md) | 光影設計：重度壓抑的調性、環境光與區段設定、光源分級、體積光、法線貼圖、後製、可讀性守則 |
| [09-content/DESIGN.md](09-content/DESIGN.md) | 內容擴充：第二章、新敵人與頭目、場景互動與探索、成長系統 |
| [09-content/SYSTEMS_REFERENCE.md](09-content/SYSTEMS_REFERENCE.md) | 成長與貨幣（Hollow Knight、Dead Cells、Hades…）、死亡與復活的敘事與流程（BioShock、Dark Souls、Hades…）、小瑕疵檢查清單與狀態矩陣（業界做法與出處） |
| [10-presentation/DESIGN.md](10-presentation/DESIGN.md) | 演出與介面：過場動畫、轉場、UI 視覺語言、彈匣介面、環境美術元件、第一章改版、新敵人、第二章擴充 |
| [10-presentation/STAGING_REFERENCE.md](10-presentation/STAGING_REFERENCE.md) | 過場舞台與關卡佈景的合理性：以角色身高為尺的尺寸比例表、位置與接觸線、坐站起身、圖層遮擋、構圖槽位、可自動化的檢查規則（業界資料與出處） |
| [12-cast-redraw/DESIGN.md](12-cast-redraw/DESIGN.md) | 敵人與 NPC 重畫：用凜的流程做出同等精細度的人形角色（範圍、各角色外觀與比例、芽的可操控規格、NPC 動畫、票的順序） |
| [12-cast-redraw/ANIMATION.md](12-cast-redraw/ANIMATION.md) | 角色動畫系統：動畫器登記、敵人招式的專屬動作、NPC 動畫（姿勢、說話、工作循環）、新增特殊角色的步驟 |
| [12-cast-redraw/CREATURES.md](12-cast-redraw/CREATURES.md) | 特殊敵人提案：爬行、飛行、觸手與蠕動（網格變形）、每章名單不重複、動作資料各自獨立、順序與待決定事項 |
| [12-cast-redraw/RIG_QUALITY.md](12-cast-redraw/RIG_QUALITY.md) | 立繪套上骨架後的畫面品質與動作質感：關節切口與破圖的原因、五種做法（網格變形、彎曲變體、姿勢立繪庫…）、建議順序、NPC 去機器人感 |
| [12-cast-redraw/LOCOMOTION_REFERENCE.md](12-cast-redraw/LOCOMOTION_REFERENCE.md) | 2D 骨架角色移動動作：走跑循環、起伏幅度、步頻、落腳、頭穩定、待機像人、22 項可測指標（生物力學與業界資料、出處） |
| [12-cast-redraw/SKELETON_REFERENCE.md](12-cast-redraw/SKELETON_REFERENCE.md) | 2D 骨架動畫的更多業界實例與工具：Spine、Live2D、Godot、Unity 的慣例，Vanillaware、UbiArt、Cuphead、Xrd 等案例，關節處理、待機像人、程序動畫、驗收清單與可自動化的測試 |
| [13-story-v2/README.md](13-story-v2/README.md) | 劇情重整（v2，完全重新設計）：參考作品拆解、世界觀「沉港市與再來一次」、大致情節（四幕九章）；取代 04-story |
| [13-story-v2/PACING_REFERENCE.md](13-story-v2/PACING_REFERENCE.md) | 章節節奏、遭遇與地圖設計、敘事融入玩法（少過場）的業界做法，以及第一章八區的結構建議 |
| [14-combat-variety/DESIGN.md](14-combat-variety/DESIGN.md) | 戰鬥多樣性：近戰與長距離近戰武器、敵人的非槍械攻擊型態素材庫 |
| [15-combat-feel/DESIGN.md](15-combat-feel/DESIGN.md) | 戰鬥系統與打擊感（第二順位支柱）：動作遊戲為主、無限小槍加近戰加彈幕、中日英打擊感資料整理、回饋管線與力道分級、打擊感實驗室、2～3 隻魂系頭目、電話亭檢查點與死亡扣 5%、票的拆分 |
| [16-audio/DESIGN.md](16-audio/DESIGN.md) | 音效與音樂：CC0 素材原則、匯流排、音效庫與武器／角色／腳步／音樂資料格式、BGM 狀態切換、音效實驗室、票的順序 |
| [16-audio/SOURCES.md](16-audio/SOURCES.md) | 音訊素材來源目錄：CC0 素材包對應的音效類別與音樂用途、缺口、挑選注意事項 |
| [17-development-workflow/DESIGN.md](17-development-workflow/DESIGN.md) | 共用開發規範、逐票 commit 與 push、main 同步、作者資訊與舊分支清理 |
| [17-protagonist-motion/DESIGN.md](17-protagonist-motion/DESIGN.md) | 主角動作重設計與以主角為主的鏡頭：現況診斷、業界做法、跑步與待機、跳躍落地衝刺、腳步聲對齊、鏡頭拉近、票的順序 |
| [06-roadmap/open-questions.md](06-roadmap/open-questions.md) | 尚未決定的問題 |
