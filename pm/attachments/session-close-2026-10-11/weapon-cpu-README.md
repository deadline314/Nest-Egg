# Cloud武器 phone-context 分支獨立CPU審查

限界：只fetch已授權origin/codex/cloud-weapon-phone-context-review一個branch，未改checkout/index/main/source，未engine/commit/push。審查HEAD41f326ab09060ebff2b58907ac50122926b9f17d，caller review9333c0d1713bddb6c787d6684241de461d7d84f4，測試基準2dab08d7a433d49af5ae8419ddcc794a16c83994；發布再rebase7e328僅上游文件。以下行號均指41f Git blob，不是目前primary工作樹行號。

在指定 invalid-spec preflight／paid-tail 路徑未發現新增明顯邏輯阻擋。這是可窄合成的review候選，仍不足以完成NE237票或把Phone原red當修好。

## 來源與測試範圍

全部17候選來源（含design/diagnostic helper/test fixture）與9333 caller版逐byte相同；51附件manifest entries hash、12最新raw tar members的bytes/hash全部exact。27正式武器/升級/近戰平衡定義與2dab base逐byte相同。Main/Story/Level/Snapshot/Visual/Rig/Fx、原runner/selector/filter/known/Smoke/Phone source均與base及caller版相同。

独立解析完整check(...) expressions並核原順序為subsequence：Progression74→145、MeleeWeapons128→145、Feel148→153、contextual helper34→34。這是source callsites，不是runtime checks；attachments對較舊b95的145等欄位不是本2dab基準原assert數量。原predicates無刪/弱化；Feel只加wall deadline觀測與新negative fixture，volume>-4／duck>-2原門檻不變。

最新raw三shard11,374＋41,054＋31,019＝83,447checks，各fail0；72 SuiteTime唯一且與selector逐名exact。原console/exit保存exit0。按原filters独立核180expected-negative ERROR＋2exit-diagnostic ERROR，Script/Parse/Compile0、unexpected0；退出仍有13resources/7RID ERROR及26ObjectDB warning，不能說raw0ERROR。Godot4.7.2官方headless。Recorded bare testHEAD25f052ab…不在這次只fetch指定發布branch取得的本機objects中；本review沒有另fetchtestSHA，改核17來源hash與固定test manifest/原raw證據一致，不能聲稱親自checkout或重跑該HEAD。

## 射擊caller順序

- `game/player/player.gd` 609–627：非槍/空武器先退；611–617讀muzzle/rate、驗bloom及共用can_fire；619才consume_ammo，625–627才設cooldown/resolve與實際fire。錯誤資料不進耗彈、冷卻、音效/FX路徑。
- `game/vehicles/vehicle.gd` 170–179：can_fire在cooldown/muzzleflash/fire前，Vehicle使用其實際weapon/aim。
- `core/weapon_system.gd` 21–49：can_fire共用shot_problems，weapon.validate含spec identity/style/numerics與sound，spawn_problems驗origin/direction/speed；team、scatter合成和rate denominator有界。fire再次preflight以保direct caller；fire_spread與pool各加數值/工作上限，最多64次spawn且fullpool首個失敗後break。
- `tests/suite/test_melee_weapons.gd` 897–987：真Level.Player/Vehicle，13 Player faults＋8 Vehicle faults，檢ammo/cooldown、velocity、visual、sound、particles、pool、muzzle/input marks及samples，903接真sound signal。先reset有效weapon再damagespec，910明確clone external spec以免污染正式cache。合法滿池control971–984仍付ammo/cooldown/feedback，沒有改成免費射击。

這是實際類別方法與物理fixture證據，不是Main新局、真人按鍵/硬體controller或畫面證據。hot path目前重複weapon/spec validation（Player can_fire→fire can_fire→fire_spread→pool每pellet），每次會配置PackedStringArray/dictionaries；上界可讀，但CPU review沒有給它效能零成本或記憶體benchmark保證。整合後在高速多發實際場景量測即可，不建議為省分配偷跳validity guards。

## 凍結付費尾招

`game/player/player.gd` 769/791保存首次chain的paid-tail id；continue使用凍結角色，不由live extension relabel抹掉付費要求。770呼叫set.attack帶角色，771–773 empty立即清鏈拒絕，774–788 guard/charge及InputFeel成本在此之後；872–879的_end_melee清paid id與buffer。

`game/player/melee_set.gd` 109–126每次live attack重驗numeric/role；paid missing或unsafe返回空，不免費fallback。196–203要求正guard_cost及cancel_after==recovery；普通missing-base仍完整DEFAULT safeattack。63–76在combo建構時也驗tail，初始不安全不append。

`tests/suite/test_melee_weapons.gd` 1000–1043：匕首/重錘各4fault。先公開buy並真Player逐step自然完成，確認chain已含付費tail，再改0cost/earlycancel/delete/relabel，檢真_try_melee拒絕、guard/charge/input不變、phase/chain/buffer清理，await前還原cachedJSON並validate。沒有造「已射擊」proof/owner。其它weapon/tuning/native只是既有證據，不能把此8負控泛化成所有Main／難度／控制器驗收。

## 可獨立review/採用分組

1. 型錄與嚴格準備：WeaponCatalog gd＋UID、WeaponData/WeaponUpgradeData validation、MeleeSet raw/numeric validation、Progression prepare_install/upgrade_catalog **兩hunks**，對應Progression tests及corrupt JSON fixture。Root現有atomic busy gate必須保留，不能整檔Progression覆寫。
2. 射擊caller安全：ProjectileSpec numeric/spawn validation、WeaponData sharedguards、WeaponSystem fire/preflight/muzzle/spread、ProjectilePool spawn guard、Player _try_fire與Vehicle _try_fire、真caller tests。依賴第1組驗證型別；不是任取W1 patch便獨立完整。ST16的shooter/proof/nonlethal路徑由Root窄合WeaponSystem/Pool/Player，不能整檔覆寫。附件w1-source-only及weapon-system-only/pool-only/player-only只是hunk入口，需當前preimage核對。
3. paid-tail runtime角色：MeleeSet combo/attack/tail_role與Player paid id/start/end hunks＋8fault tests，依賴raw validators；w2-source-only patch可供review。不能只加Player參數而漏MeleeSet拒絕／正成本完整recovery。
4. Feel fixture wall-deadline：僅test_feel來源可獨立review，無Sfx產品變更。保原timer與threshold，新增明確300ms真ticks wait及160ms catchup負控；最初無觀測duck red根因仍未全證實。
5. contextual helper診斷／design／review evidence另列：helper4、138、160、166、170仍呼叫NE237_HEADER_PROBE，打印全域readonly快照；沒有新await/state write，原34callsites保留。最新『no_probe』僅指Phone natural overlay移除，**不是所有diagnostic instrumentation移除**。這57行不是武器產品必要依賴；如Root不採會形成新測試來源epoch，須自己的原changed/native驗收，不能套83447來源receipt。NE237 PM review段只採本票，不把繼承NE90/NE249/NE222 PM/素材整branch歸給武器票。

## PM與Phone限界

NE237保持「進行中」，兩個已checked條件是既有可選招/用途说明；其餘5條仍unchecked（輸入一致、完整動作回饋、每目標傷害/interruptreset、比較與無限取消、真退出續玩經濟）。Commit1/2既有部分交付保留，Commit3明說未合main review候選。72/83447最新green不抵銷原72/83449/2Phone red；Phone來源與knownlist全原樣，未加known。NE249已在main完成的是Encounter輸入隔離，不能歸因成Phone修復。自然13前序candidate/base各4330/0、controlledcatchup red和新grouping green只能證fixture前提缺口，原uninstrumentedPhone兩失敗仍未因果歸因。

Root採各組後仍須真Main／coldContinue／controller／Forward+／新來源affected驗收，與共同Story/ST16合成所有權分開。不將cloud CPU真節點方法負控冒充完整章節或native交付。

機械audit SHA b0a4dbae81f3d488817d7ded77c903012b93cd0b951cba1d1de4f3f65a2d7b7b 在audit.json。
