# NE218 看門狗四足接口（供 root 整合，尚未掛載交付）

基線：c0250bff9dd6a44a8b1c9df557eaab18b0a12996。NE218 已存在，不另開票。本檔是現有接口核對與最小變更建議，不是新角色定稿或已驗收 runtime。

目前 `watchdog.tres`：`rig_skin="warden"`、`rig_weapon="minigun"`、`body_size=(34,78)`、`move_speed=46`。行為鏈 watchdog → custodian → warden_boss → Enemy。watchdog.gd 的舊註解「兩腿一尾」與使用者／NE218 四足需求相反，root 掛載時一併修正；不能把此註解當規格。

現有正式非人形資料在 `art/creatures/<id>.json`，由 EnemyData.creature_skin 指定；Enemy 優先建立 rig_skin，rig 成功時不建立 creature。所以只新增 creature_skin、不清除 rig_skin，仍會顯示人形。

## 已存在的資料契約

| 項目 | 實際接口與單位 |
|---|---|
| 外觀 | `dir`、`texture_scale`；diffuse/normal/glow 原生 RGBA 和來源 SHA 見 inventory.json |
| 零件 | `parts[]`: name,file,pivot（貼圖像素）,pos（父 joint 局部世界像素）,parent,z,rot（弧度）,tint |
| 父鏈 | 父部件必須較早定義；`joint.position=pos`；sprite.offset=-pivot、sprite.scale=texture_scale |
| 狀態 | states[state].channels: part,prop(rot/x/y/sx/sy),base,amp,freq,phase,abs,vfreq；root.bob_amp/bob_freq/tilt；show 限定可見件 |
| 驅動 | `animate(delta,state,velocity,face,aim_angle)`；face=-1/1；aim 相對面向；只有根 x 鏡射一次 |
| 掛點 | part.aim、recoil 世界局部位移、muzzle 部件 joint 局部世界坐標；`muzzle_global(name)`、`joint_of(name)`、`part_names()` |
| 受擊 | flash()、set_wear(Color)、extra_position/rotation/scale；擊發 kick() |
| 原有 Part gait | stride/full_speed/hop、legs[].part/phase/swing/lift；距離相位＋正弦擺動，**沒有世界座標 foot lock** |
| FootGait | place(world_point)、begin_step(world_target,duration,lift)、advance(delta)、target()；foot/group/stepping/landed。duration 下限0.05秒；釘腳時 advance 不移動 foot |
| 現有落腳排程 | ChainCreature.ground_probe(world_x)→world_y；group 交替，trigger/lead/step_time/lift/full_speed/dip；超過可達距離會解除組排程保護。這是觸手鏈的既有行為，不能直接當狗膝／肘姿態通過 |

`shock_hound` 現有 body pivot=(68,63),pos=(0,0),z=0；tail pivot=(68,6),pos=(-12,-9),parent=body,z=-1；texture_scale=0.25、stride=16、full_speed=90、hop=1.6、legs=[]。來源 body_s2.png 是完整犬體，四肢尚未分開；不能用 body 拉長或加一尾交付四足動畫。`wall_gecko` 同樣只有 body、legs=[]。飛行蜂群只有一張整體圖，但不要求它走路。

## root 所需最小素材帳本

沿用 PartCreature，不增加另一套角色／骨架框架。下面是建議的新部件識別符，**目前不存在**，像素 pivot/pos 必須按 root 最終來源實測，不能抄人形或這裡虛填數值。

| name／父鏈 | pivot 與內容 | 層序／接合要求 |
|---|---|---|
| body | 脊柱／肩帶與骨盆參考，完整腹部；地面原點不在圖框底 | 中層；身體只一份，不包含可獨立擺動的整條腿 |
| neck→body、head→neck、jaw→head | 真頸根、顱底、顎關節；牙／爪留原生像素 | 近側頭與嘴需真切件；非獨立下顎可併入 head 並明記 |
| fore_far_upper→body→fore_far_lower→fore_far_foot | 肩、肘、腕／掌；遠前腳完整隱藏層 | 先定義遠前腿；父鏈實際是 body→upper→lower→foot；far 在 body 後 |
| hind_far_upper→body→hind_far_lower→hind_far_foot | 髖、膝、跗／掌；勿把跗關節當反向膝 | 同上遠後腿；腿座與腹部底層保留 |
| fore_near_upper→body→fore_near_lower→fore_near_foot | 近前肢肩／肘／腕，完整前爪 | near 在 body 前；不得拿同一近側截圖代替不同遮擋的遠側底層 |
| hind_near_upper→body→hind_near_lower→hind_near_foot | 近後肢髖／膝／跗，完整後爪 | 同上；股骨頭、膝與趾端 source-space 同時對位 |
| tail_1→body、tail_2→tail_1（有需才分） | 真尾根、分節機械附件；不是第五條承重腿 | 尾根固定、遠近遮擋由來源確定；非正常游離電弧不可任刪 |
| weapon→body、core_port→body（若外觀有此裝備） | 原 minigun 的視覺槍口／後座及核心位置 | weapon 不沿用人形握槍手；muzzle 與 projectile 真來源相同；core 不是額外完整軀幹 |
| armor_*（僅真裝甲） | 完整未受損底層，各片獨立；normal/glow同尺寸/pivot | 不能讓完整身體或腿被當作脫落碎片 |

「→body」在上表指 upper.parent=body，不是把 body 掛在 upper 下。每件原生 RGBA、source SHA、mask、bbox、source-space pivot、rest／bind transform、遊戲 size／texture_scale 和兩面向 z 都由同一來源產生。game/cutscene 最大展示尺度的來源密度另驗；不插值放大舊PNG充新來源。

## 可復用步態與測試接口

在 PartCreature 內增加可選四足模式（接口建議，未實作）：四個 FootGait 分別綁定四個 *_foot；每腳記 upper/lower/foot、固定 rest 長度、source-space 肘／膝彎曲方向、neutral_world_contact。接地探針沿用 `ground_probe(world_x)` Callable 形式。四腳的承重材質最低點相對 foot pivot 要保存，不能以 joint.y=0 替代爪／掌接地。

步態組建議：fore_near＋hind_far 為組0，fore_far＋hind_near 為組1，作為對角小跑起點；慢走必須另列四腳支撐順序，不能把小跑相位直接當慢走。此為專案起點，沒有宣稱已核對官方生物學數值。FootGait 的既有世界座標釘腳／跨步軌跡可直接復用；固定骨長的四肢解算／膝肘方向仍需來源校準，不能用人形 TwoBoneIK 的 pose 測試替代。ChainPose 的等長多節弧線適用既有觸手，不能把犬的上／下肢比例默默改成等長觸手。

距離／速度轉換：world_velocity / actor_scale 後餵進局部步態；FootGait 世界點只換算一次；翻面一次、釘腳狀態須重置／重定位，不能二次鏡射。root 腳測試要區分「上一格及本格都踩地」與剛落地的跨步結束，量完整世界位移，不能只累計 <0.001 的微小位移。既有 ChainCreatureSuite 的 slipped 條件排除了較大位移，因此該 assertion 本身不足以證明沒有腳滑；本 Session 不改 shared test。

復用的真 Suite：PartCreatureSuite（建立／狀態／show／muzzle／recoil）、ChainCreatureSuite（FootGait 排程、grounding、sever／核心）、ExoticEnemiesSuite（翼頻／表面／軌道／群體）、Chapter1EnemiesSuite（watchdog 睡眠、傷勢保留、watchdog_gate、不觸發 boss_defeated）、AssaultEnemiesSuite（shock_hound 群體／撲咬）、HeavyEnemiesSuite（原 Warden core 行為，root 改共享 Boss 才需要）。不要重跑 unrelated humanoid suite 來代驗四足。

新增掛載局部驗證必須有：四 feet 數量／唯一名稱／非空 joint 集合、固定 rest 長、肘膝方向、逐腳材質接地、兩格踩地腳 slip、支撐組／重心、翻面／轉身、1×／3.4×、idle/walk/run/attack/stagger/dead 與全實際 FSM 狀態。walk/run 不是現有 watchdog FSM 新玩法：由真 velocity 選外觀移動狀態，沒有真移動時不假踩步。

## 最小掛載改動與必補的真 caller

1. root 接受完整新素材與四足步態後，watchdog.tres 清空 rig_skin、rig_weapon，設定 creature_skin="watchdog"、creature_states。保留 story／toast／gate／對話／出場及攻擊時序。
2. 覆蓋 watchdog._creature_aim：把目標方向換成相對 face 的弧度。覆蓋 _muzzle：creature.muzzle_global("weapon")；原 Enemy._muzzle 只認人形 rig，否則退回碰撞框邊，不認 PartCreature 掛點。
3. core 掛點若真有該裝備，使用 joint_of("core_port") 的世界點轉回 Enemy local；原 _core_point 只認人形 core_port/chest，否則使用 body_size 比例。watchdog reachable 攻擊為 burst/leap、二階段 fan，**沒有 core_cannon／summon**；不得因 Warden 註冊了狀態而替狗增加攻擊。
4. Enemy._physics_process 在 _dying 時只 drive_rig 後 return；單換 creature_skin 不會播放 dead。root 應在 watchdog 既有死亡期間驅動 creature dead／四肢落地，保持 custodian 的6次小爆炸、watchdog_gate及不結束關卡。不是站姿整體轉90度。
5. burst 的 _shoot 會 creature.kick；fan 使用 WeaponSystem.fire_spread 直接發射，只設 _rig_input.recoil，不會 kick PartCreature。root 在狗的 fan 發射事件補一次視覺 kick，不能更改發射判定與間隔。
6. data.body_size=(34,78) 是既有人形替身碰撞包絡；新犬體的水平外觀、ground origin、weapon/core 與包絡須實測對位。不要只按人形身高縮一隻狗、也不要未驗就改戰鬥 hurtbox。確需調包絡時由 root 在 NE218 驗證攻擊來源／接觸／傷害與 gate 回歸。

最小資料 diff 見 minimal-mount.patch。它**只提供接線形狀**，沒有新素材時不能套用或稱已交付。runtime 補點以上列 caller 為準，交 root 做，不在本分支修改。

FSM 的真 reachable 外觀表：dormant→idle，intro→idle，idle→idle/實際移動，burst_windup→attack_windup，burst→attack，leap_windup→leap_windup，leap→leap/land，fan_windup→fan_windup，phase_shift→phase_shift；受擊／死亡從 _stun_left/_dying 另驅動。全部要在新 watchdog.json 明確定義，不能缺動畫就回退 idle 卻當通過。
