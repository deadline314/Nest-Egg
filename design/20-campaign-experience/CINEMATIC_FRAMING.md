# ST-22：接近預告與正式演出的共用畫幅

## 已核定設計與現況

原設計基準 `33df641d839485808e925c6bc86d3f6e2ee13f5a`；本次整合基準 `7e05a6e78623e620482caa527d480cbc52b13a0c`（含NE-230存檔及NE-228 HUD），最終測試基準 `5366453717f9488d16b661a67299a7ad6360f242`（新增文件，遊戲來源無差異）。原本 DialogueLayer 與 CutscenePlayer 各自畫固定34px黑邊，沒有接近預告；PERSON 與 OBJECT 都可引用 dialogue 場景。Story 對外把 dialogue 的開始模式別名為 cinematic，NE-230 用此契約保存選擇入口，因此本票保留公開事件模式，資格讀實際場景資料及每次來源。

本票只改畫幅、介面安全區及必要互動接點。世界、物理、演員骨架、美術、預載服務與強制故事觸發語義不改。HUD只新增訊號安全接點，不改既有布局及提示機制。電影入口由章節作者明確宣告，不能把靠近強制事件偷偷改成可拒絕事件。

## 畫幅與生命週期

Story 擁有一個 CinematicFraming CanvasLayer，位於電影之上、人物對話之下；只有一份黑邊，不新增 project.godot autoload。正式演出以 owner/token 管理，巢狀範圍在最後一個 owner 釋放時才退回。owner 離樹自動釋放，正常結束在發出完成訊號前釋放；服務不取得 GameplayLock。

以實際 viewport 的 `W,H` 計算單側黑邊：`max(0, (H-W/(21/9))/2)`。640×360每邊42.857142px；已達21:9或更寬時黑邊為0，不另外縮窄。世界不縮放或伸展。畫幅動畫發出 `safe_rect_changed`，對話框、肖像、確認提示、電影選項依其布局；HUD依訊號暫隱操作卡及邊緣固定元件，避免黑邊裁半行：生命／時計／信用點／能力／頭目條／武器欄置於單一透明布局wrapper，inset>0時隱藏wrapper，退回零遮幅恢復。子元件原有visible、數值與動畫不改；操作卡的可見閱讀倒數同時停止。中央toast與world互動prompt不隱藏。正在交談的NPC同步隱藏自身重複互動prompt，完成／取消恢復；reach_check另排除交談、死亡與騎乘。

正式普通電影保持21:9整段，不受舊 letterbox on/off 步驟另起一份固定黑邊；舊步驟的等待時序仍保留。overlay 動畫是普通FX，不取得電影畫幅。減少介面動態時畫幅立即到目標，肖像不滑入，完成提示保持靜態；電影中的演員動作與世界物理仍正常。

死亡、離場、新局或恢復故事進度中止當前與排隊演出。中止不當作完成，不套用跳過預設選項，不寫完成旗標，也不增加 NPC 對話次數或發獎勵。正常略過仍沿既有完成／預設選項語義。尚未完成的 once 場景中止後可重新開始；已完成紀錄保持。延遲 auto-skip 回呼以世代防止取消後重播同ID被舊回呼誤結束。

## 接近資格與選擇

PERSON 必須有符合目前旗標、物品、死亡及對話次數條件的可用 NpcTalk，場景存在且實際mode為dialogue。OBJECT、看板、radio、bubbles及overlay不預告。

只有 NpcActor、顯式 CinematicEntrance 與宣告電影預告的 Portal 登記候選；集中10Hz讀取候選，不掃描所有UI或每影格建完整候選字典。預告距離起始值為80px進入、100px退出、垂直56px；距離接近48px人物互動範圍時漸進到完整21:9。Portal 仍按原本 Area2D 範圍互動，不把80px預告冒充已可使用。已選目標在退出範圍內保留，其他候選至少近16px才換人；淡入淡出0.28秒。**這些都是專案起始參數，沒有宣稱業界標準，需以實際操作與圖證校正。**

接近不呼叫 Story.play，不改旗標、seen、獎勵或輸入鎖。死亡、騎乘、暫停、現有演出鎖及附近 engaged 敵人抑制預告；戰鬥危險出現時立即收起預告，避免黑邊停留遮威脅。戰鬥抑制預告不改既有主動聊天能力。確認當下只選最近可互動來源，避免鄰接人物／入口同一輸入同時開始。

## 每次入隊來源與續玩接點

`Story.play(id, once, context)` 與 `play_and_wait` 第三參數可省略，原有呼叫保持有效。context僅保存 `framing_source`（person/object/entry）、`source_id` 字串，以及PERSON／OBJECT可選的純整數 `talk_index`。索引先驗有限整數，再核對實際NpcData.talks範圍及原talk到當前segment的then鏈；鏈檢查有visited及64段上限。非法索引／來源不猜測NPC獎勵，JSON數字讀回float時只接受精確整數。每次入隊拷貝自身 context，不以 scene ID 全域記憶 PERSON 身分，OBJECT 引用同一 dialogue 也不會誤用。

`current_presentation_context()` 回傳副本，供開始事件的存檔入口保存。黑邊比例、token、Node、Tween及選中預告來源不存檔。實際 dialogue＋person 才取得正式畫幅；cinematic 與非overlay animated本身是正式電影。公開 `scene_started` 的 dialogue→cinematic 別名維持。

每次入隊分配獨立 request handle，`play_and_wait` 只等自己的完成／取消結果。PERSON與OBJECT排入相同scene ID時，第一段完成不會提前結算第二個waiter的對話次數或獎勵；then鏈沿用原handle，到鏈尾才完成等待。公開scene_started／scene_finished(id)契約維持。

NE-230交付時只保存cinematic ID；本票已接Main入口保存context、RunSnapshot純資料清洗與Level真正NPC來源回播。舊檔缺context以空來源安全還原，不猜測dialogue來源或補發NPC獎勵；同版未知額外欄位保留。B是A的then續段時，保存B入口包含A已完成的旗標／交易，回播B經原NPC結算路徑才發一次原talk獎勵，不重播A。

取消順序：Story先同步發出 `presentation_cancelled(id, context, reason, request)`，再清播放器、排隊、畫幅及等待者；不發scene_finished。Main同步scene_started時讀current_presentation_request保存runtime handle，取消需比對handle，避免舊同ID通知清新入口；handle不存檔。死亡回呼由Story在Level死亡處理之前登記，Main收到reason=death時須先撤回入口後尚未完成的選項／故事／成長／世界暫定效果，保留當前死亡事實，再清 `_cinematic`／`_cinematic_entry`。Level隨後沿原register_death、死亡扣款及critical save結算；不能只清marker就保存半段choice，也不能扣款後再rollback吞掉費用。關閉程序須先沿NE-230原子入口_save_run，再取消釋放畫面；不將未完段落算完成。讀檔／新局須在恢復新狀態前清舊runtime標記。整合後需要真死亡扣款與關閉程序再續玩探針驗證，此接點已實際接入Main／RunSnapshot／Level；驗證結果及原log在下方，沒有把live Level整份runtime回套。撤回時保留真實時計、戰鬥／死亡統計、Player.health/state/位置與死亡原因。

## 顯式電影入口資料

LevelData.cinematic_entries 是 CinematicEntryData 陣列，每筆含 `id`、`scene`、腳底所在格 `cell`、`once` 及含 `{interact}` 的一句提示。Level建立入口，位置按真layout格座標；入口只接受實際cinematic或非overlay animated場景，無效資料指出關卡／入口／場景位置並略過。

入口顯示獨立電影記號與確認提示；必須按互動才開始，退回不變故事狀態。既有 intro/boss/outro/& 強制事件保持原來入口，不能在此欄重複宣告同一個強制事件來假裝可選。測試宣告的入口及合成事件必須標成 synthetic／受控資料，不能代稱正式通關。

正式範例沿用 `ch1_stall` 的 `stall_home`（格44,19，腳底712,320）。PortalData新增 `cinematic_preview_scene=ch1_c14_home`，必須對應目標 `ch1_pawnshop_dawn` 的正式intro，且實際模式為cinematic或非overlay animated；Portal只有原requires_flag `knows_ali_address` 已滿足、armed且電影未seen時才預告。80px階段提示「前方將播放劇情。」；原Area2D互動範圍內提示「{interact} 回家後播放劇情。」。原target_portal `pawn_front`、try_use、轉場、intro及complete_after_intro均維持。僅在formal tres和build_ch1.py同源新增metadata／提示，不改地圖layout，不提前套用完成旗標。

## 驗證矩陣與證據邊界

先在現有 NpcSuite／CutsceneSuite加入幾何、真Level互動、退回、邊界與相鄰候選、戰鬥、巢狀owner釋放、同ID不同queue來源、取消不發獎勵、公開催入模式、動畫選項布局與skip回歸。NE-230整合後涵蓋PERSON／OBJECT退出程序再續玩的實際入口，不只mock getter。

Forward+隔離探針使用獨立user資料，保護正式存檔。按真輸入事件抓預告遠端／近端／退回、人物對話、OBJECT閱讀、正式電影／選項，至少16:9與21:9或更寬viewport及120%文字。圖片存 `pm/Nest-Egg/images/ST-22-*.png`，ST票相對連到 `../Nest-Egg/images/`；合成電影入口圖證標明synthetic，正式stall_home另抓真遊戲畫面，均不冒充人工手把遊測。最終以原run_tests_changed selector實際選定範圍測試，保留完整console／ERROR；不改registry、filter或known_failures。

2026-10-10首次隔離headless editor import自然exit0，但Story第652行Array.pop_front的Variant推斷產生1個Parse Error及7個相依Compile Error。已改明確Dictionary，原失敗保留 `C:/tmp/st22-import.log`；整合後 `C:/tmp/st22-final-import.log` EXIT0且無Script／Parse／Compile Error。

局部真四組NpcSuite／CutsceneSuite／RunSaveSuite／TransitionSuite：原第一輪785/0，加入HUD／prompt／ALWAYS入口pause及鎖回歸後791 checks、0 new、0 known，31秒，完整console/shard在 `C:/tmp/st22-targeted-final-console.log`、`C:/tmp/st22-targeted-final-logs/shard_0.log`。誤用only簡稱的零檢查raw保留但不計驗收；不改測試filter，既有壞資料測試的預期ERROR完整保留。

首輪Forward+1600×900／120%文字37/0，圖確認頂部信用點及底部武器末列被預告裁切；最小wrapper修正後同構圖37/0，world互動prompt完整、退回恢復。修前圖／log保存 `C:/tmp/ST-22-pre-fix-person-approach.png`、`C:/tmp/ST-22-pre-fix-native.log`。加入NPC對話prompt同步隱藏後已重捕最後版本：16:9與寬視口各37/0，共74項合成輸入檢查，16張PNG及兩份report／engine log存於pm/Nest-Egg/images。1600×900採正式KEEP、640×360 viewport；2100×900寬視口工具只覆寫EXPAND為840×360，驗證零額外遮幅，沒有改正式DisplayMode。正式stall_home圖沿原portal／intro；OBJECT及choice圖明標synthetic。

隔離跨程序探針只在工具中替換正式阿梨NPC資料的talk與kind，角色節點、Main保存／Continue／quit及Level恢復／死亡結算仍用真服務；來源／then場景為合成驗證，不代稱正式故事或人工通關。首版fixture因未持有Resource強參照而實際載回正式原talk，assert已揭露場景ID不符，保留失敗 `C:/tmp/st22-resume/person_write.log`。第二版PERSON6+7、OBJECT6+7、then8+7、真死亡8共49/0；第二版route指到不存在ch1_home而回選單，過弱assert誤綠，該6項不計路由驗收，完整warning保留 `C:/tmp/st22-resume-v2/route.log`。已修為有效pawnshop目的地／pawn_front並收緊真Level＋目的地assert；原八模式最後55/0、EXIT0（C:/tmp/st22-resume-final-console.log）。另以實際磁碟讀檔驗非法索引／then鏈14/0，不補NPC獎勵、保留未完成入口及合法重新交談退路；真正Level.queue_free及同ID排隊／過期取消通知14/0、EXIT0（C:/tmp/st22-resume-owner-final-console.log）。上述三組不同情境共83項；重複跑的chain/death/route不重複加總。


實際boss_pending續玩回歸揭露兩個生命週期邊界。Level原先在camera建立前恢復arena，產生兩個Nil camera SCRIPT ERROR；現僅將原_restore_run_entities接點移至camera bounds／target／snap初始化之後，不改地圖或演員。相同resume世代另分settled與completed：成功才生成pending boss，取消／離場／非法來源回播也可結束等待而不生成頭目。以正確process_frame等待、暫移完成gate的失敗實證216/1且無SCRIPT ERROR（C:/tmp/st22-boss-proof-console.log），唯一失敗為cancel=true但spawned=true；恢復gate後正常新arena、保存arena、pending成功／取消四組798/0，EXIT0。舊camera、等待時序及失敗log完整保留，不加known failure或縮selector。

真正owner銷毀探針曾有8個功能assert通過、卻仍兩個previously-freed SCRIPT ERROR（C:/tmp/st22-resume-edge/leave.log），故包裝器EXIT1，未計為通過。Main保存及scene_started先驗is_instance_valid／queued狀態，取消handler也先驗有效才cast Level；匹配通知抵達已free畫面時僅安全清入口，不重掛live世界。新增matching delayed-cancel＋真正freed Level單元回歸，原失敗C:/tmp/st22-freed-guard-targeted-logs/shard_0.log保留。最後原受影響selector結果見下方；局部檢查沒有代替最終全範圍驗收。


最後四組含已free畫面的matching取消通知共799 checks、0 new、0 known、27秒，EXIT0（C:/tmp/st22-freed-guard-fixed-console.log及同名前綴logs/shard_0.log）。5366453717重新隔離匯入EXIT0、無Script／Parse／Compile／ERROR；原selector選66組（含main），原run_tests_changed.sh HEAD、SHARDS=2已自然EXIT0，47,088 checks、0 new、0 known、797秒；shard0為34,493、shard1為12,595。沒有更改registry／filter／known failures。完整console、兩shard與SHA報表在pm/Nest-Egg/attachments/ST-22-final-*.log、ST-22-verification.json。raw保留原本預期容錯ERROR，以及退出ObjectDB 4／25、resources 2／13診斷；本票未宣稱所有引擎警告或既有物件生命週期問題均已消除。

根代理最後目視確認人物近端預告／對話文字與肖像安全，NPC自身重複互動prompt消失，寬視口工具EXPAND的零遮幅成立。正式16:9 home-movie仍有老K與凜頭部超出上緣／被黑邊遮擋；保留原圖交ST-10舞台範圍，**本票UI安全區通過不能代稱演員與關鍵動作構圖通過**。一般告示牌與氣泡文字疊層屬BG-22／ST-9，本票不改地圖／演員美術／骨架補圖。此限制對應ST-22第五驗收條件，保持未勾選；所有native探針是合成輸入／受控路由，未宣稱實體手把人工驗收。
