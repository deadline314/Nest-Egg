# ST-3 九條驗收只讀審查

固定來源 `dbbafd79122426fe4f85b2e6e3c32df03be8503a`。全部產品、資料、測試及PM皆以 immutable git blob 讀取；本次未啟動 Godot、長測或 GPU，未改工作樹、index、產品、PM或commit。歷史結果採信原始紀錄，來源/接入口/測試範圍分開核對。

結論：九項均有可追溯的實作或歷史證據，但不能把九個勾號直接視為當前正式全流程已全部驗收。已確認正式 `StoryRules.holds` 的壞條件反轉/短路放行缺口；另一隔離工作者正處理此根因，本文不改產品。死亡1/2/3 fixture與正式1/3/5、茶杯指示與現行取灰布、通用資料schema與有限耐久來源、原完整測試與當前未重跑範圍均須分別記錄。

| 條 | 結論 | 主要正式證據 |
|---|---|---|
| 1 過場選項、不同後續、選擇旗標 | 正式接入與歷史真入口證據支持；條件壞資料另有已確認缺口 | pm/ST/attachments/ST-9-sunday-choice/validation.json |
| 2 旗標保存、缺漏/損毀預設回退與具體診斷 | 存檔owner與既有回歸支持；不能延伸為runtime條件也已fail-closed | pm/ST/attachments/ST-3-conditions/manifest.json |
| 3 物件按鍵短台詞、狀態變體、已聽記錄 | 正式四標籤/真NPC完成與冷讀證據支持 | pm/ST/attachments/ST-9-npc-completion/validation.json |
| 4 死亡序列：台詞/另一聲音/狀態列/記憶卡，之後縮短與可略過 | 通用能力與正式資料皆存在；票內三次測試流程不能直接視作正式節奏通過 | pm/ST/attachments/ST-9-clinic-results/README.md:3-7 |
| 5 故事道具可入背包並被後續劇情檢查 | 框架與正式灰布/資料盤/回執等入口支持；茶杯測試指示已非現行道具流程 | pm/ST/attachments/ST-9-clinic-results/README.md:32-65 |
| 6 以上由資料描述、新增內容不需改程式 | 通用schema可資料化；正式耐久結果僅有限已登記來源，不能照字面泛稱任意新內容零程式 | design/20-campaign-experience/TERMINAL_STORY_RESULTS.md:40-56 |
| 7 既有功能不回歸、完整測試全通過 | 接受並保留歷史原結果；本只讀審查未取得dbb全套新執行證據，也未重跑 | pm/ST/attachments/ST-9-clinic-results/validation.json |
| 8 廣播接續/重播/重設首句立即持續可見 | 當前同一生命週期修復仍在，原始紅綠/畫面範圍有可驗packet | design/20-campaign-experience/RADIO_LIFECYCLE.md |
| 9 取得史/現持有分開；已交原件不因重播/死亡/續玩復生；未完成可取消 | 服務/框架生命週期及正式交接櫃冷讀各有真證據；不可合併宣稱完整自然流程 | pm/ST/attachments/ST-9-clinic-results/README.md:50 |

**第1條：過場選項、不同後續、選擇旗標**

正式接入與歷史真入口證據支持；條件壞資料另有已確認缺口。fixture不是唯一證據；週日正式入口已有拒寫/重試、返回/預設略過與冷程序接續。只授權有限原屋頂來源，不是任意選項的通用耐久承諾。

來源：data/npcs/ch1_egret.tres:9；tools/story/ch1_closure.py；data/story/ch1_kasa.json /scenes/ch1_t_egret_sunday_prompt/steps/4/options；game/story_result_completion.gd:40-90；game/story_result_sources.gd:64-74。

既有測試：tests/suite/test_cutscene.gd:668-731；tests/suite/test_cutscene.gd:917-977；tests/probes/sunday_choice.gd。

歷史證據：pm/ST/attachments/ST-9-sunday-choice/README.md:15-35；pm/ST/attachments/ST-9-sunday-choice/validation.json。


**第2條：旗標保存、缺漏/損毀預設回退與具體診斷**

存檔owner與既有回歸支持；不能延伸為runtime條件也已fail-closed。已知宣告旗標的磁碟錯型/缺值回退有來源與file/path警告。strict條件框架的not-invalid防護沒有同等進入StoryRules.holds；未知flag/item/壞ledger的值級接線不可從schema-only修復推定完成。

來源：autoload/game_state.gd:437-470；autoload/game_state.gd:477-515；autoload/story.gd:367-399；core/story_rules.gd:38-76。

既有測試：tests/suite/test_cutscene.gd:739-752；tests/suite/test_story_content.gd:314-364。

歷史證據：pm/ST/[ST-3]加入故事需要的對話選項旗標與演出功能.md Commit-1/2/6；pm/ST/attachments/ST-3-conditions/manifest.json。


**第3條：物件按鍵短台詞、狀態變體、已聽記錄**

正式四標籤/真NPC完成與冷讀證據支持。正式標籤已讀旗標、NPC次數及三份磁碟world投影先保存後通知；原始once fixture只能證框架。安排位置/前提、軟體畫面與人類自然探索分開。

來源：data/npcs/ch1_label_watch.tres:8；data/npcs/ch1_label_guitar.tres:8；data/npcs/ch1_label_raincoat.tres:8；data/npcs/ch1_label_fare.tres:8；tools/level/build_ch1.py:1060-1066；game/npc/npc_actor.gd:237-320；data/scripts/npc_data.gd:53-75；data/story/ch1_kasa.json /scenes/ch1_dispatch_label_*。

既有測試：tests/suite/test_cutscene.gd:753-765；tests/helpers/npc_terminal_save_checks.gd；tests/probes/story_marker_completion.gd。

歷史證據：pm/ST/attachments/ST-9-npc-completion/README.md:3-21；pm/ST/attachments/ST-9-npc-completion/validation.json。


**第4條：死亡序列：台詞/另一聲音/狀態列/記憶卡，之後縮短與可略過**

通用能力與正式資料皆存在；票內三次測試流程不能直接視作正式節奏通過。fixture門檻1/2/3，正式作者與三章重用門檻1/3/5；真首次死亡走診間不經一般DeathScreen。舊SCRIPT設計與票內測試流程寫第二次縮短/第三次略過，現行作者只寫首個電話亭死亡完整版、之後縮短/再後略過，未找到明示第五次理由。本審查不改節奏、不判定序列崩潰。

來源：autoload/story.gd:1408-1455；game/level/level.gd:1028-1035；game/level/level.gd:1296-1326；tools/story/ch1_runtime_backend.py:88-102；data/story/ch1_kasa.json /death_sequences；design/13-story-v2/STORY_FEATURES.md:45-61；design/13-story-v2/SCRIPT_CH01.md:794-796。

既有測試：tests/fixtures/story_features.json:4-13；tests/suite/test_cutscene.gd:766-780；tests/suite/test_death_flow.gd。

歷史證據：pm/ST/[ST-3]加入故事需要的對話選項旗標與演出功能.md Commit-1；pm/ST/attachments/ST-9-clinic-results/README.md:3-7。


**第5條：故事道具可入背包並被後續劇情檢查**

框架與正式灰布/資料盤/回執等入口支持；茶杯測試指示已非現行道具流程。正式杯/托盤是演出道具，當前選擇取得灰布且茶不取走；不能稱原測試流程第4步「茶杯進道具欄」已照字面驗證。廣義驗收項目5不指定茶杯。

來源：autoload/story_items.gd；core/story_rules.gd:5-30；data/story/ch1_kasa.json /scenes/ch1_t_clinic_cloth_take/results；data/story/ch1_kasa.json /scenes/ch1_t_handoff_*；game/story_result_clinic.gd。

既有測試：tests/suite/test_cutscene.gd:732-734；tests/suite/test_collectibles.gd:197-222；tests/probes/clinic_completion.gd:23-82；tests/probes/clinic_original.gd:53-95。

歷史證據：pm/ST/attachments/ST-3-custody/manifest.json；pm/ST/attachments/ST-9-clinic-results/README.md:32-65。


**第6條：以上由資料描述、新增內容不需改程式**

通用schema可資料化；正式耐久結果僅有限已登記來源，不能照字面泛稱任意新內容零程式。choices/branches/death/items可新增資料；但新正式耐久producer要擴充有限來源與契約。目前不是通用atomic_v1。不能為滿足此句放寬來源授權，也不能把歷史framework packet當正式完整接線。

來源：design/13-story-v2/STORY_FEATURES.md；design/20-campaign-experience/CH1_STORY_RUNTIME.md；tools/story/ch1_runtime_backend.py:3-11；game/story_result_sources.gd:1-90；game/story_result_completion.gd:2-3；game/story_result_completion.gd:38-66。

既有測試：tools/story/test_completion_policies.py；tests/probes/story_contract_audit.gd；tests/suite/test_cutscene.gd:917-977。

歷史證據：pm/ST/attachments/ST-3-conditions/manifest.json formal_scene_wired=false；pm/ST/attachments/ST-3-result-plan/manifest.json；pm/ST/attachments/ST-3-silent-install/manifest.json formal_scene_installed=false；design/20-campaign-experience/TERMINAL_STORY_RESULTS.md:40-56。


**第7條：既有功能不回歸、完整測試全通過**

接受並保留歷史原結果；本只讀審查未取得dbb全套新執行證據，也未重跑。歷史baseline、範圍與已封存失敗維持原記錄；不把新source/入口反例、較晚資料配置或本次source inspection冒充同一完整套件已重跑。未修改assertions/filter/known。

來源：tools/run_tests_changed.sh；tools/run_tests_parallel.sh；tests/known_failures.txt。

既有測試：tests/suite/test_cutscene.gd；tests/suite/test_death_reactions.gd；tests/suite/test_collectibles.gd；tests/suite/test_run_save.gd。

歷史證據：ST-3票Commit-1完整45286/0、Commit-2完整45317/0；pm/ST/attachments/ST-3-custody/manifest.json 9005/0；pm/ST/attachments/ST-3-silent-install/manifest.json 41891/0；pm/ST/attachments/ST-9-terminal-results/validation.json 65524/0；pm/ST/attachments/ST-9-npc-completion/validation.json 63403/0；pm/ST/attachments/ST-9-clinic-results/validation.json。


**第8條：廣播接續/重播/重設首句立即持續可見**

當前同一生命週期修復仍在，原始紅綠/畫面範圍有可驗packet。現有退場Tween在_next_radio與cancel前kill；原真Story/DialogueLayer一般與減少動態、next/reset/replay 18影格回歸保留。原packet154/4紅→154/0綠、原選取180/0；84ms修前與99ms修後捕捉不當成同一時間。舊版native GPU證據非本次新GPU測試、非全關卡真人遊玩。

來源：ui/dialogue_layer.gd:42；ui/dialogue_layer.gd:172；ui/dialogue_layer.gd:228-266。

既有測試：tests/suite/test_death_reactions.gd:317-385。

歷史證據：pm/ST/attachments/ST-3-radio-verification.json；design/20-campaign-experience/RADIO_LIFECYCLE.md。


**第9條：取得史/現持有分開；已交原件不因重播/死亡/續玩復生；未完成可取消**

服務/框架生命週期及正式交接櫃冷讀各有真證據；不可合併宣稱完整自然流程。cutscene fixture驗取消/選交未播完/安全預設/完成轉交/重播拒絕/JSON往返；Collectibles驗register_death、checkpoint清除及真Level重建不復生。正式Main交盤/取回執/摘要有原主檔及獨立冷讀；其前提是公開服務安排持盤/金額/位置，未找到同一packet自然取得盤→正式交付→真致死→冷續玩全串，不能代稱已跑。

來源：autoload/story_items.gd；core/story_rules.gd:5-30；autoload/story.gd:332-363；game/story_result_completion.gd；data/story/ch1_kasa.json /scenes/ch1_t_handoff_accept/results。

既有測試：tests/suite/test_cutscene.gd:798-903；tests/suite/test_collectibles.gd:197-222；tests/probes/handoff_completion.gd:33-52；tests/probes/handoff_completion.gd:65-144。

歷史證據：pm/ST/attachments/ST-3-custody/manifest.json formal_story_verified=false；pm/ST/attachments/ST-9-terminal-results/README.md:3-11；pm/ST/attachments/ST-9-clinic-results/README.md:50。


**已確認的源碼反例與影響界線**

`StoryRules.holds({"not":{"unknown":true}})`：內層落在 core/story_rules.gd:64 回 false，54–55 行反成 true。`{"any":[{}, {"unknown":true}]}`：第一支在45–52行即回 true，壞第二支不會被看見。這是可逐行求值的源碼反例，並非本次 native execution，也不是宣稱 dbb 正式 JSON 目前含有這些壞條件。

正式入口是 autoload/story.gd:384 scene_available、399 dispatch、CutscenePlayer:921 options/976 branch，以及候選/衍生條件 callers；strict StoryConditionTree 的 validate/evaluate 契約存在，但目前這些 bool-only runtime入口沒有一致沿用 invalid 語義。完整結果 planner 的另一次嚴格預檢及有限來源防護仍存在；不由入口反例推定能繞過所有正式結果保存/發獎。


**全 caller 與 schema 差異**

`storyrules-callers.json` 有 50 個 live 呼叫 occurrence、11 檔；排除 pm 歷史副本與純註解。每筆保留檔案/行號/方法/原句。

| 差異 | 現 runtime / legacy | strict contract | 保留界線 |
|---|---|---|
| legacy外層 | eligible: requires_flag/unless_flag/requires_item(取得史) + requires_held/unless_held/requires_transferred；ID先str→StringName；flag_reader使用八種scalar truth | 不是when tree schema，strict evaluate拒絕requires_item這類op | 不要把legacy外層欄位直接當strict when或改其owns/held語義 |
| when形狀 | 空物件true；all/any/not/flag/item/receipt/account；同時多op/額外key依分支先後接受；沒有budget | exact keys；深16/節點256/children32；ID<=64、String<=256、finite scalar<=999999999 | 共享結構驗證可修未知op/形狀/bounds；需保留合法API相容與全分支invalid傳遞 |
| flag葉 | equals可省略預設true；same_value null可等false/空字串/0/unset；int/float數值比；String/StringName按str | equals必需；宣告facts存在才合法；數值可相等但bool不與數字混同；StringName非strict scalar | 正式三章沒有缺equals，API相容仍應明示；不得把未知事實任意補false再在not下放行 |
| 布林樹 | 短路；invalid與false混為bool；not({unknown:true})會成true | validate+evaluate valid/value/error；每支走完驗事實；invalid不被not或其他分支蓋掉 | schema-only gate不等於完整值級ledger/facts接線 |
| receipt/account | reader回bool/String；account_state忽略account參數；false/status投影不能獨立區分未存在與壞/locked | receipt葉僅第一章7ID；account僅ch1_lounge與合法6子集；ledger需locked、當前descriptor指紋/delta/依賴證明；descriptor表可包含後章交易 | 不能只拿live ledger覆蓋proposed candidate。現行正式三章receipt葉只用ch1 IDs，不代表API永遠只有七種 |
| 候選快照 | run_flag_commit29/35、StoryFlagCompletion151、StoryResultCompletion420/421以Callable讀候選flags/held/ledger | evaluate需顯式facts/context投影 | 新adapter必須保留reader候選語義、runtime/context已宣告預設，不要無條件回live服務 |

正式三章資料盤點：flag 葉全部明示 equals；receipt 葉目前只引用第一章交易ID（第二章也只查第一章委託收據，第三章無 receipt 葉）。這不表示既存 public runtime API 永遠只有七種 receipt/account，也不表示省略 equals 或 StringName 原API從未合法。strict ledger描述表可包含後章交易，但 strict receipt條件葉本身目前仍限定第一章七ID。


**可最小共用的修法建議與測試入口（供另隔離實作者決定，不在本審查修改）**

1. 沿現有 StoryRules / StoryConditionTree 收斂有界結構檢查；不要另建框架。若重用 validator，先分清結構（exact keys/type/depth/nodes/children）與第一章7收據/account的領域限制，不能為接runtime而放寬既有嚴格planner契約，也不能用新的七ID gate 無意改掉舊runtime合法來源。

2. 每支子條件都先取得 valid/value，invalid 不得被 not 或成立的 any/不成立的 all 吞掉。只把結構 schema gate 接上時，交付範圍必須叫 schema/bounds 防護；不可順便宣稱 unknown flag/item、locked/malformed/drift ledger 的完整 strict facts 接線已完成。後者須有 owner 宣告與原 ledger/descriptor 證據，不可把未知事實補 false 再反轉。

3. 保留 eligible 外層 legacy requires/unless、取得史 owns / 現持有 holds，以及八種scalar truth。same_value:67–75 的原 null fallback、int/float、String/StringName 和省略 equals 的API相容應由明確回歸鎖住。run_flag_commit:29/35、StoryFlagCompletion:151、StoryResultCompletion:420/421 的 Callable 讀的是候選快照；不得把它們改成只讀當下live owner，否則derived/續段會讀錯時間點。

4. 保留 StoryContentSuite::_test_condition_contract:314–364、receipt_trust:389–437、limits:440起的全部原assertions；在 CutsceneSuite::_test_story_runtime:917起加真 scene_available/dispatch、option/branch/skip 的壞條件 gates，檢查 flags/items/progress 不變、來源 path明確。schema malformed/extra op、bad child在前/後、not/any/all、depth/node/cycle/shared alias各需獨立；不要用只測pure strict evaluator代替runtime入口。八種legacy scalar在Cutscene:676–680、歷史物品733–734、custody:798起繼續保留。


**原始 packet 核對**

`packet-checks.json` 固定 dbb blobs：ST-3 radio/custody/conditions/result-plan/silent-install/durable-write 共75份歷史原始log/exit的repository-LF SHA核對全吻合。四份正式後續封包（terminal、npc、sunday、clinic）整包SHA均吻合原validation或README記錄；只讀雜湊，沒有重跑其引擎流程、重包或複製歷史素材。

初期 custody/conditions/silent/durable packet明示 formal_scene_wired=false / formal_scene_installed=false / Main未啟用，這些歷史限制不能被忽略。較晚ST-9已有真Main標籤/週日/診間/交接櫃資料與獨立冷讀，故也不能繼續一概說今天仍只有framework。

radio packet保留154/4負控制、修後及180/0原選取；custody早期型別錯誤、durable 350/7 JSON邊界失敗、terminal一次原生SIGSEGV及後續原範圍重跑等歷史失敗按原資料保持，不改寫成全歷史無錯誤。symbolic-link權限跳過不當通過。


全部來源定位與23份當前核心/測試/正式資料blob SHA在 `audit.json`；所有hash均針對指定published commit。本文沒有 PM狀態變更或完成判定。
